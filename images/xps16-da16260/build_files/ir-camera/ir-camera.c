// Reads the infrared camera for a few seconds, with its lamp on, and writes each frame to stdout as a PGM.
// For katze-ir-camera@.service: it needs root, and hm1092 lets nobody without CAP_SYS_RAWIO start the sensor.
//
// The IPU7 driver writes past the CPU cache and never flushes it, so a frame can show old cache lines.
// This drops them before each buffer is queued and after each frame arrives.
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <immintrin.h>
#include <linux/media-bus-format.h>
#include <linux/media.h>
#include <linux/v4l2-subdev.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define LAMP "/sys/class/leds/HIMX1092_00::ir_flood_led/brightness"
#define SENSOR "hm1092 "
#define CODE MEDIA_BUS_FMT_SGRBG10_1X10 // a mono sensor: the IPU7 driver has no mono format
#define SENSOR_W 648
#define SENSOR_H 368
// The middle of the picture: the sensor's last row is dark
#define OUT_W 640
#define OUT_H 360
#define LEFT ((SENSOR_W - OUT_W) / 2)
#define TOP ((SENSOR_H - OUT_H) / 2)
#define NBUF 4
#define SECONDS_MAX 8
#define WARM_UP 3 // frames not shown, while the sensor and the lamp settle
#define BRIGHT 170 // where the exposure puts the brightest 5% of the picture
#define SETTLE 3 // frames until a new exposure shows

static int lamp = -1;

// Safe inside a signal handler
static void lamp_off(void)
{
	if (lamp >= 0 && pwrite(lamp, "0", 1, 0) < 0)
		_exit(3);
}

static void on_signal(int sig)
{
	lamp_off();
	_exit(sig == SIGALRM ? 2 : 0); // closing the node stops the sensor
}

__attribute__((format(printf, 1, 2), noreturn)) static void die(const char *format, ...)
{
	va_list args;
	lamp_off();
	va_start(args, format);
	vfprintf(stderr, format, args);
	va_end(args);
	fputc('\n', stderr);
	exit(1);
}

static void drop_cache(const char *p, size_t n)
{
	for (size_t i = 0; i < n; i += 64)
		_mm_clflush(p + i);
	_mm_mfence();
}

static int set_control(int fd, uint32_t id, int value)
{
	struct v4l2_control control = { .id = id, .value = value };
	return ioctl(fd, VIDIOC_S_CTRL, &control);
}

// Exposure, then digital gain (256 is 1x), as one number: lines of exposure * 256
struct exposure {
	int min, max;
	long total;
};

#define GAIN_MAX 1023L

static void split(const struct exposure *e, int *lines, int *gain)
{
	long l = e->total / 256, g;
	if (l > e->max)
		l = e->max;
	if (l < e->min)
		l = e->min;
	g = e->total / l;
	if (g > GAIN_MAX)
		g = GAIN_MAX;
	if (g < 256)
		g = 256;
	*lines = l;
	*gain = g;
}

// Returns whether the exposure has to change
static int expose(struct exposure *e, const uint8_t *frame)
{
	unsigned count[256] = { 0 }, above = 0;
	int level = 255;
	long was = e->total;
	for (int i = 0; i < OUT_W * OUT_H; i++)
		count[frame[i]]++;
	while (level > 0 && (above += count[level]) < OUT_W * OUT_H / 20)
		level--;
	if (level > BRIGHT * 85 / 100 && level < BRIGHT * 115 / 100)
		return 0;
	// A saturated or black picture says little about how far off it is
	long percent = level >= 250 ? 40 : level < 1 ? 200 : BRIGHT * 100 / level;
	if (percent > 200)
		percent = 200;
	if (percent < 40)
		percent = 40;
	e->total = e->total * percent / 100;
	if (e->total > e->max * GAIN_MAX)
		e->total = e->max * GAIN_MAX;
	if (e->total < e->min * 256L)
		e->total = e->min * 256L;
	return e->total != was;
}

// 10 bits in 16, to 8 bits, and only the middle of the picture
static void convert(const char *raw, size_t line, uint8_t *frame)
{
	for (int y = 0; y < OUT_H; y++) {
		const uint16_t *in = (const uint16_t *)(raw + (y + TOP) * line) + LEFT;
		for (int x = 0; x < OUT_W; x++)
			*frame++ = in[x] > 1023 ? 255 : in[x] >> 2;
	}
}

struct graph {
	int media, sensor, bridge, video;
};

static int open_node(const struct media_entity_desc *entity)
{
	char path[64];
	snprintf(path, sizeof(path), "/dev/char/%u:%u", entity->dev.major, entity->dev.minor);
	return open(path, O_RDWR | O_CLOEXEC);
}

static int get_entity(int media, uint32_t id, struct media_entity_desc *entity)
{
	memset(entity, 0, sizeof(*entity));
	entity->id = id;
	return ioctl(media, MEDIA_IOC_ENUM_ENTITIES, entity);
}

// The links of an entity, at most 16. Returns how many, or -1
static int get_links(int media, const struct media_entity_desc *entity, struct media_link_desc *links)
{
	struct media_pad_desc pads[32];
	struct media_links_enum request = { .entity = entity->id, .pads = pads, .links = links };
	if (entity->links > 16 || entity->pads > 32)
		return -1;
	return ioctl(media, MEDIA_IOC_ENUM_LINKS, &request) ? -1 : entity->links;
}

// Follows sensor -> CSI-2 receiver -> first capture node, and leaves only that last link on:
// another capture node of the same receiver would get the same frames
static int open_graph(int media, struct graph *g)
{
	struct media_entity_desc sensor, bridge, video;
	struct media_link_desc links[16], chosen;
	int n, found = 0;
	uint32_t id = 0;

	do {
		if (get_entity(media, id | MEDIA_ENT_ID_FLAG_NEXT, &sensor))
			return -1;
		id = sensor.id;
	} while (strncmp(sensor.name, SENSOR, strlen(SENSOR)));

	n = get_links(media, &sensor, links);
	if (n < 1 || get_entity(media, links[0].sink.entity, &bridge))
		return -1;
	n = get_links(media, &bridge, links);
	for (int i = 0; i < n; i++) {
		if (links[i].source.entity != bridge.id)
			continue;
		if (!found) {
			found = 1;
			chosen = links[i];
			continue;
		}
		links[i].flags &= ~MEDIA_LNK_FL_ENABLED;
		if (ioctl(media, MEDIA_IOC_SETUP_LINK, &links[i]))
			die("Cannot turn a link off: %s", strerror(errno));
	}
	if (!found || get_entity(media, chosen.sink.entity, &video))
		return -1;

	g->media = media;
	g->sensor = open_node(&sensor);
	g->bridge = open_node(&bridge);
	g->video = open_node(&video);
	if (g->sensor < 0 || g->bridge < 0 || g->video < 0)
		return -1;
	chosen.flags |= MEDIA_LNK_FL_ENABLED;
	if (ioctl(media, MEDIA_IOC_SETUP_LINK, &chosen))
		die("Cannot turn the link on: %s", strerror(errno));

	struct v4l2_subdev_format format = {
		.which = V4L2_SUBDEV_FORMAT_ACTIVE,
		.format = { .width = SENSOR_W, .height = SENSOR_H, .code = CODE, .field = V4L2_FIELD_NONE },
	};
	struct v4l2_subdev_format sink = format, source = format;
	struct v4l2_subdev_selection crop = {
		.which = V4L2_SUBDEV_FORMAT_ACTIVE,
		.target = V4L2_SEL_TGT_CROP,
		.r = { .width = SENSOR_W, .height = SENSOR_H },
	};
	crop.pad = source.pad = chosen.source.index;
	if (ioctl(g->bridge, VIDIOC_SUBDEV_S_FMT, &sink) || ioctl(g->bridge, VIDIOC_SUBDEV_S_SELECTION, &crop) ||
	    ioctl(g->bridge, VIDIOC_SUBDEV_S_FMT, &source))
		die("Cannot set the receiver's format: %s", strerror(errno));
	return 0;
}

// Just after the driver is loaded, its nodes take a moment
static void find_camera(struct graph *g)
{
	for (int tries = 0; tries < 30; tries++) {
		DIR *dir = opendir("/dev");
		struct dirent *entry;
		while (dir && (entry = readdir(dir))) {
			char path[300];
			if (strncmp(entry->d_name, "media", 5) || !isdigit((unsigned char)entry->d_name[5]))
				continue;
			snprintf(path, sizeof(path), "/dev/%s", entry->d_name);
			int media = open(path, O_RDWR | O_CLOEXEC);
			if (media < 0)
				continue;
			if (!open_graph(media, g)) {
				closedir(dir);
				return;
			}
			close(media);
		}
		if (dir)
			closedir(dir);
		usleep(100000);
	}
	die("No infrared camera: the driver is not loaded, or the sensor did not answer");
}

static int write_all(const void *data, size_t size)
{
	const char *p = data;
	while (size) {
		ssize_t n = write(STDOUT_FILENO, p, size);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			return -1;
		p += n;
		size -= n;
	}
	return 0;
}

static int self_test(void)
{
	static uint8_t frame[OUT_W * OUT_H];
	static uint16_t raw[SENSOR_W * SENSOR_H];
	struct exposure e = { .min = 2, .max = 719, .total = 360 * 256 };
	int lines, gain, failed = 0;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "self-test: %s\n", #x); failed = 1; } } while (0)
	raw[TOP * SENSOR_W + LEFT] = 1023;
	raw[(TOP + OUT_H - 1) * SENSOR_W + LEFT + OUT_W - 1] = 4;
	raw[(TOP + OUT_H) * SENSOR_W] = 1023; // below the picture
	convert((const char *)raw, SENSOR_W * 2, frame);
	CHECK(frame[0] == 255 && frame[1] == 0 && frame[OUT_W * OUT_H - 1] == 1);
	split(&e, &lines, &gain);
	CHECK(lines == 360 && gain == 256);
	// A scene whose brightness follows the exposure reaches the wanted level, dark or sunny
	for (int scene = 1; scene <= 2000; scene *= 10) {
		e.total = 360 * 256;
		int level = 0, steps = 0;
		do {
			split(&e, &lines, &gain);
			long light = (long)lines * gain / 256 * scene / 20;
			level = light > 255 ? 255 : light;
			memset(frame, level, sizeof(frame));
		} while (expose(&e, frame) && ++steps < 30);
		CHECK(steps < 30);
		CHECK(lines >= 2 && lines <= 719 && gain >= 256 && gain <= 1023);
		CHECK(scene > 100 || (level > 130 && level < 200) || (lines == 719 && gain == 1023));
	}
	return failed;
}

int main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "--self-test"))
		return self_test();
	int seconds = argc == 2 ? atoi(argv[1]) : 0;
	if (seconds < 1 || seconds > SECONDS_MAX || isatty(STDOUT_FILENO)) {
		fprintf(stderr, "usage: ir-camera <seconds, 1 to %d> > frames.pgm\n", SECONDS_MAX);
		return 2;
	}

	struct sigaction action = { .sa_handler = on_signal };
	for (int *s = (int[]){ SIGTERM, SIGINT, SIGHUP, SIGALRM, 0 }; *s; s++)
		sigaction(*s, &action, NULL);
	signal(SIGPIPE, SIG_IGN); // whoever asked went away: write() says so

	lamp = open(LAMP, O_WRONLY | O_CLOEXEC);
	if (lamp < 0)
		die("No lamp: %s", strerror(errno));
	struct graph g;
	find_camera(&g);

	struct exposure e = { 0 };
	struct v4l2_queryctrl range = { .id = V4L2_CID_EXPOSURE };
	if (ioctl(g.sensor, VIDIOC_QUERYCTRL, &range))
		die("No exposure control: %s", strerror(errno));
	e.min = range.minimum;
	e.max = range.maximum;
	e.total = range.default_value * 256L;
	set_control(g.sensor, V4L2_CID_EXPOSURE, range.default_value);
	set_control(g.sensor, V4L2_CID_DIGITAL_GAIN, 256);
	// Any program of the user's can set these on the sensor
	set_control(g.sensor, V4L2_CID_ANALOGUE_GAIN, 0);
	if (set_control(g.sensor, V4L2_CID_TEST_PATTERN, 0))
		die("Cannot turn the test pattern off: %s", strerror(errno));

	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	struct v4l2_format format = { .type = type };
	format.fmt.pix.width = SENSOR_W;
	format.fmt.pix.height = SENSOR_H;
	format.fmt.pix.pixelformat = V4L2_PIX_FMT_SGRBG10;
	if (ioctl(g.video, VIDIOC_S_FMT, &format))
		die("VIDIOC_S_FMT: %s", strerror(errno));
	size_t line = format.fmt.pix.bytesperline, size = line * SENSOR_H;
	if (format.fmt.pix.width != SENSOR_W || format.fmt.pix.height != SENSOR_H ||
	    format.fmt.pix.pixelformat != V4L2_PIX_FMT_SGRBG10 || line < SENSOR_W * 2)
		die("Unexpected format");

	struct v4l2_requestbuffers request = { .count = NBUF, .type = type, .memory = V4L2_MEMORY_MMAP };
	char *memory[NBUF];
	size_t length[NBUF];
	if (ioctl(g.video, VIDIOC_REQBUFS, &request))
		die("VIDIOC_REQBUFS: %s", strerror(errno));
	if (request.count < 2 || request.count > NBUF)
		die("Unexpected number of buffers");
	for (unsigned i = 0; i < request.count; i++) {
		struct v4l2_buffer buffer = { .index = i, .type = type, .memory = V4L2_MEMORY_MMAP };
		if (ioctl(g.video, VIDIOC_QUERYBUF, &buffer))
			die("VIDIOC_QUERYBUF: %s", strerror(errno));
		length[i] = buffer.length;
		if (length[i] < size)
			die("Short buffer");
		memory[i] = mmap(NULL, length[i], PROT_READ | PROT_WRITE, MAP_SHARED, g.video, buffer.m.offset);
		if (memory[i] == MAP_FAILED)
			die("mmap: %s", strerror(errno));
		drop_cache(memory[i], length[i]);
		if (ioctl(g.video, VIDIOC_QBUF, &buffer))
			die("VIDIOC_QBUF: %s", strerror(errno));
	}

	// From here on the lamp goes off whatever happens: signals, the alarm, die(), and the unit's ExecStopPost
	alarm(seconds + 2);
	if (pwrite(lamp, "1", 1, 0) != 1)
		die("Cannot turn the lamp on: %s", strerror(errno));
	if (ioctl(g.video, VIDIOC_STREAMON, &type))
		die("VIDIOC_STREAMON: %s", strerror(errno));
	fputs("infrared camera on\n", stderr);

	static uint8_t frame[OUT_W * OUT_H];
	struct timespec now, start;
	int shown = 0, settle = SETTLE;
	clock_gettime(CLOCK_MONOTONIC, &start);
	for (int n = 0;; n++) {
		struct pollfd wait = { g.video, POLLIN, 0 };
		struct v4l2_buffer buffer = { .type = type, .memory = V4L2_MEMORY_MMAP };
		clock_gettime(CLOCK_MONOTONIC, &now);
		if (now.tv_sec - start.tv_sec >= seconds)
			break;
		if (poll(&wait, 1, 2000) <= 0)
			die("No frame after 2 s");
		if (ioctl(g.video, VIDIOC_DQBUF, &buffer))
			die("VIDIOC_DQBUF: %s", strerror(errno));
		drop_cache(memory[buffer.index], length[buffer.index]);
		if (n >= WARM_UP && !(buffer.flags & V4L2_BUF_FLAG_ERROR)) {
			convert(memory[buffer.index], line, frame);
			if (dprintf(STDOUT_FILENO, "P5\n%d %d\n255\n", OUT_W, OUT_H) < 0 || write_all(frame, sizeof(frame)))
				break; // nobody is reading any more
			shown++;
			if (--settle <= 0 && expose(&e, frame)) {
				int lines, gain;
				split(&e, &lines, &gain);
				set_control(g.sensor, V4L2_CID_EXPOSURE, lines);
				set_control(g.sensor, V4L2_CID_DIGITAL_GAIN, gain);
				settle = SETTLE;
			}
		}
		drop_cache(memory[buffer.index], length[buffer.index]);
		if (ioctl(g.video, VIDIOC_QBUF, &buffer))
			die("VIDIOC_QBUF: %s", strerror(errno));
	}
	lamp_off();
	ioctl(g.video, VIDIOC_STREAMOFF, &type);
	fprintf(stderr, "infrared camera off, %d frames\n", shown);
	return 0;
}
