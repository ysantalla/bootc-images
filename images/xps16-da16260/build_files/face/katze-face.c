// Face unlock with the infrared camera: finds a face in the frames of katze-ir-camera.socket (YuNet),
// describes it (SFace) and compares it with the faces registered for that user. OpenVINO on the CPU.
//
//   katze-face add <user>       register more of the user's face (root, in a terminal)
//   katze-face remove <user>    forget it
//   katze-face test <user>      print how close each frame comes, without unlocking anything
//   katze-face serve            katze-face@.service: answers "yes", "no" or "none" for the user at the other end of stdin,
//                               and "no" without turning the camera on when that user is not the one at the screen
//   katze-face compare <a.pgm> <b.pgm>...   offline, how close the faces in those pictures are
//   katze-face --self-test
//
// It never keeps a picture: only 128 numbers for each registered frame, in /var/lib/katze/face/<uid>.
#define _GNU_SOURCE // struct ucred
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <openvino/c/openvino.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <systemd/sd-login.h>
#include <unistd.h>

#ifndef MODELS // a test build may put them elsewhere
#define MODELS "/usr/share/katze/face"
#endif
#define STATE "/var/lib/katze/face"
#define CAMERA "/run/katze-ir-camera.sock"

#define W 640 // what ir-camera writes
#define H 360
#define PAD_H 384 // YuNet wants multiples of 32
#define SIDE 112 // SFace's input
#define DIM 128 // and output

#define DETECT 0.8f // YuNet's score for a face
#define MIN_FACE 60 // pixels: a face further away is too small to tell
#define MATCH 0.5f // cosine similarity to a registered frame. SFace's own threshold, for colour, is 0.363
#define MATCHES 2 // frames in a row that must match
#define KEEP 20 // registered frames at most
#define ADD 5 // frames registered each time
#define CLEAR 0.85f // YuNet's score for a frame to register: infrared faces score about 0.9

struct face {
	float score, x, y, w, h;
	float points[10]; // eyes, nose, mouth corners: x, y
};

static ov_core_t *core;
static ov_infer_request_t *detector, *describer;

__attribute__((format(printf, 1, 2), noreturn)) static void die(const char *format, ...)
{
	va_list args;
	va_start(args, format);
	fputs("katze-face: ", stderr);
	vfprintf(stderr, format, args);
	va_end(args);
	fputc('\n', stderr);
	exit(1);
}

#define OV(call) do { ov_status_e s_ = (call); if (s_ != OK) die("%s: OpenVINO error %d", #call, s_); } while (0)

static ov_infer_request_t *load(const char *path, int64_t height, int64_t width)
{
	ov_model_t *model;
	ov_compiled_model_t *compiled;
	ov_infer_request_t *request;
	ov_partial_shape_t shape;
	ov_dimension_t dims[4] = { { 1, 1 }, { 3, 3 }, { height, height }, { width, width } };
	OV(ov_core_read_model(core, path, NULL, &model));
	OV(ov_partial_shape_create(4, dims, &shape));
	OV(ov_model_reshape_single_input(model, shape));
	ov_partial_shape_free(&shape);
	// Two threads: an answer in a fraction of a second is enough, and the machine stays quiet
	OV(ov_core_compile_model(core, model, "CPU", 2, &compiled, "INFERENCE_NUM_THREADS", "2", "PERFORMANCE_HINT", "LATENCY"));
	OV(ov_compiled_model_create_infer_request(compiled, &request));
	ov_compiled_model_free(compiled);
	ov_model_free(model);
	return request;
}

static void load_models(void)
{
	OV(ov_core_create(&core));
	detector = load(MODELS "/yunet.onnx", PAD_H, W);
	describer = load(MODELS "/sface.onnx", SIDE, SIDE);
}

static float *input(ov_infer_request_t *request)
{
	ov_tensor_t *tensor;
	void *data;
	OV(ov_infer_request_get_input_tensor_by_index(request, 0, &tensor));
	OV(ov_tensor_data(tensor, &data));
	ov_tensor_free(tensor);
	return data;
}

static const float *output(ov_infer_request_t *request, const char *name)
{
	ov_tensor_t *tensor;
	void *data;
	OV(ov_infer_request_get_tensor(request, name, &tensor));
	OV(ov_tensor_data(tensor, &data));
	ov_tensor_free(tensor); // the request keeps the data
	return data;
}

static float clamp01(float v)
{
	return v < 0 ? 0 : v > 1 ? 1 : v;
}

// The surest face, decoded as OpenCV's FaceDetectorYN does. Returns 0 if there is none, or it is too small.
static int detect(const uint8_t *frame, struct face *best)
{
	float *in = input(detector);
	// Three channels of the same grey, BGR 0 to 255, and black below the picture
	for (int c = 0; c < 3; c++) {
		float *plane = in + (size_t)c * PAD_H * W;
		for (int i = 0; i < W * H; i++)
			plane[i] = frame[i];
		memset(plane + W * H, 0, sizeof(float) * W * (PAD_H - H));
	}
	OV(ov_infer_request_infer(detector));

	int found = 0;
	for (int stride = 8; stride <= 32; stride *= 2) {
		char name[16];
		snprintf(name, sizeof(name), "cls_%d", stride);
		const float *cls = output(detector, name);
		snprintf(name, sizeof(name), "obj_%d", stride);
		const float *obj = output(detector, name);
		snprintf(name, sizeof(name), "bbox_%d", stride);
		const float *box = output(detector, name);
		snprintf(name, sizeof(name), "kps_%d", stride);
		const float *kps = output(detector, name);
		int cols = W / stride, rows = PAD_H / stride;
		for (int r = 0; r < rows; r++)
			for (int c = 0; c < cols; c++) {
				int i = r * cols + c;
				float score = sqrtf(clamp01(cls[i]) * clamp01(obj[i]));
				if (score < DETECT)
					continue;
				if (found && score <= best->score)
					continue;
				float w = expf(box[i * 4 + 2]) * stride, h = expf(box[i * 4 + 3]) * stride;
				best->score = score;
				best->w = w;
				best->h = h;
				best->x = (c + box[i * 4]) * stride - w / 2;
				best->y = (r + box[i * 4 + 1]) * stride - h / 2;
				for (int k = 0; k < 5; k++) {
					best->points[k * 2] = (kps[i * 10 + k * 2] + c) * stride;
					best->points[k * 2 + 1] = (kps[i * 10 + k * 2 + 1] + r) * stride;
				}
				found = 1;
			}
	}
	return found && best->w >= MIN_FACE && best->h >= MIN_FACE;
}

// Where SFace wants the eyes, the nose and the mouth corners, in a 112x112 picture (as OpenCV's alignCrop)
static const float target[10] = { 38.2946f, 51.6963f, 73.5318f, 51.5014f, 56.0252f, 71.7366f, 41.5493f, 92.3655f, 70.7299f, 92.2041f };

// The similarity transform (scale, rotation, shift) that best takes the face's points to the target:
// q = a p + t, with a = ar + i ai as a complex number. Least squares, which is Umeyama's without reflections.
static void similarity(const float *p, float *ar, float *ai, float *tx, float *ty)
{
	float pmx = 0, pmy = 0, qmx = 0, qmy = 0;
	for (int k = 0; k < 5; k++) {
		pmx += p[k * 2] / 5;
		pmy += p[k * 2 + 1] / 5;
		qmx += target[k * 2] / 5;
		qmy += target[k * 2 + 1] / 5;
	}
	float re = 0, im = 0, norm = 0;
	for (int k = 0; k < 5; k++) {
		float px = p[k * 2] - pmx, py = p[k * 2 + 1] - pmy;
		float qx = target[k * 2] - qmx, qy = target[k * 2 + 1] - qmy;
		re += px * qx + py * qy;
		im += px * qy - py * qx;
		norm += px * px + py * py;
	}
	*ar = re / norm;
	*ai = im / norm;
	*tx = qmx - (*ar * pmx - *ai * pmy);
	*ty = qmy - (*ai * pmx + *ar * pmy);
}

static float pixel(const uint8_t *frame, int x, int y)
{
	return x < 0 || y < 0 || x >= W || y >= H ? 0 : frame[y * W + x];
}

// 128 numbers of length 1 for the face: aligned to the target, bilinear, then SFace
static void describe(const uint8_t *frame, const struct face *face, float *out)
{
	float ar, ai, tx, ty;
	similarity(face->points, &ar, &ai, &tx, &ty);
	float d = ar * ar + ai * ai;
	float *in = input(describer);
	for (int v = 0; v < SIDE; v++)
		for (int u = 0; u < SIDE; u++) {
			// p = (q - t) / a
			float qx = u - tx, qy = v - ty;
			float x = (ar * qx + ai * qy) / d, y = (ar * qy - ai * qx) / d;
			int x0 = (int)floorf(x), y0 = (int)floorf(y);
			float fx = x - x0, fy = y - y0;
			float value = (1 - fy) * ((1 - fx) * pixel(frame, x0, y0) + fx * pixel(frame, x0 + 1, y0)) +
				      fy * ((1 - fx) * pixel(frame, x0, y0 + 1) + fx * pixel(frame, x0 + 1, y0 + 1));
			for (int c = 0; c < 3; c++)
				in[(c * SIDE + v) * SIDE + u] = value;
		}
	OV(ov_infer_request_infer(describer));
	ov_tensor_t *tensor;
	void *data;
	OV(ov_infer_request_get_output_tensor_by_index(describer, 0, &tensor));
	OV(ov_tensor_data(tensor, &data));
	float sum = 0;
	for (int i = 0; i < DIM; i++)
		sum += ((float *)data)[i] * ((float *)data)[i];
	for (int i = 0; i < DIM; i++)
		out[i] = ((float *)data)[i] / sqrtf(sum);
	ov_tensor_free(tensor);
}

static float closest(const float *f, const float *known, int n)
{
	float best = -1;
	for (int k = 0; k < n; k++) {
		float dot = 0;
		for (int i = 0; i < DIM; i++)
			dot += f[i] * known[k * DIM + i];
		if (dot > best)
			best = dot;
	}
	return best;
}

static int read_all(int fd, void *data, size_t size)
{
	char *p = data;
	while (size) {
		ssize_t n = read(fd, p, size);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			return -1;
		p += n;
		size -= n;
	}
	return 0;
}

// One frame of ir-camera's stream, exactly "P5\n640 360\n255\n" and the pixels. 0 at the end.
static int next_frame(int fd, uint8_t *frame)
{
	static const char header[] = "P5\n640 360\n255\n";
	char got[sizeof(header) - 1];
	if (read_all(fd, got, sizeof(got)))
		return 0;
	if (memcmp(got, header, sizeof(got)))
		die("unexpected picture from the camera");
	return read_all(fd, frame, W * H) == 0;
}

static int open_camera(void)
{
	struct sockaddr_un address = { .sun_family = AF_UNIX, .sun_path = CAMERA };
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address)))
		die("cannot reach the infrared camera (%s): %s", CAMERA, strerror(errno));
	return fd;
}

static void path_for(uid_t uid, char *path, size_t size)
{
	snprintf(path, size, STATE "/%u", (unsigned)uid);
}

// The registered frames of a user, or NULL
static float *known_faces(uid_t uid, int *n)
{
	char path[64];
	struct stat st;
	path_for(uid, path, sizeof(path));
	int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (fd < 0)
		return NULL;
	if (fstat(fd, &st) || st.st_size <= 0 || st.st_size % (DIM * sizeof(float)) || st.st_size > KEEP * DIM * (off_t)sizeof(float) ||
	    st.st_uid != 0 || (st.st_mode & 077))
		die("%s is not as katze-face writes it", path);
	float *known = malloc(st.st_size);
	if (!known || read_all(fd, known, st.st_size))
		die("cannot read %s", path);
	close(fd);
	*n = st.st_size / (DIM * sizeof(float));
	return known;
}

static uid_t user(const char *name)
{
	struct passwd *pw = getpwnam(name);
	if (!pw)
		die("no user called %s", name);
	return pw->pw_uid;
}

static int add(uid_t uid)
{
	int n = 0;
	float *known = known_faces(uid, &n);
	known = realloc(known, sizeof(float) * DIM * (n + ADD));
	if (!known)
		die("out of memory");
	load_models();
	fputs("Look at the screen for a few seconds...\n", stderr);
	int camera = open_camera(), added = 0, frames = 0;
	static uint8_t frame[W * H];
	struct face face;
	while (added < ADD && next_frame(camera, frame)) {
		// Every third frame with a clear face, so the frames differ a little
		if (frames++ % 3 || !detect(frame, &face) || face.score < CLEAR)
			continue;
		describe(frame, &face, known + (size_t)(n + added) * DIM);
		added++;
	}
	close(camera);
	if (!added)
		die("no face seen: try again, facing the camera from the usual distance");
	n += added;
	int drop = n > KEEP ? n - KEEP : 0; // the oldest go first
	char path[64], temporary[80];
	path_for(uid, path, sizeof(path));
	snprintf(temporary, sizeof(temporary), "%s.new", path);
	// Others may see whether a user has a face registered (katze-face-check enrolled), not read it
	if (mkdir(STATE, 0711) && errno != EEXIST)
		die("cannot create " STATE ": %s", strerror(errno));
	int fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (fd < 0 || write(fd, known + (size_t)drop * DIM, sizeof(float) * DIM * (n - drop)) != (ssize_t)(sizeof(float) * DIM * (n - drop)) ||
	    fsync(fd) || close(fd) || rename(temporary, path))
		die("cannot write %s: %s", path, strerror(errno));
	fprintf(stderr, "Registered %d frames, %d in all.\n", added, n - drop);
	return 0;
}

// The camera's frames, until MATCHES of them in a row are this user, or it stops (about 5 s)
static int look(uid_t uid, int verbose)
{
	int n;
	float *known = known_faces(uid, &n);
	if (!known)
		return -1;
	load_models();
	int camera = open_camera(), row = 0, frames = 0;
	static uint8_t frame[W * H];
	float f[DIM];
	struct face face;
	while (row < MATCHES && next_frame(camera, frame)) {
		frames++;
		if (!detect(frame, &face)) {
			row = 0;
			if (verbose)
				printf("frame %d: no face\n", frames);
			continue;
		}
		describe(frame, &face, f);
		float similar = closest(f, known, n);
		row = similar >= MATCH ? row + 1 : 0;
		if (verbose)
			printf("frame %d: face %.0fx%.0f, score %.2f, similarity %.3f%s\n", frames, face.w, face.h, face.score, similar,
			       similar >= MATCH ? " (match)" : "");
	}
	close(camera); // the camera goes off when nobody reads it
	return row >= MATCHES;
}

// Whether logind has this user in the foreground of a seat: "active", not "online" (SSH, a user switched
// away from) or "lingering". Anyone may ask the socket, so only the user at the screen turns the camera on,
// and another account cannot keep it busy for the lock screen.
static int at_the_screen(uid_t uid)
{
	char *state = NULL;
	int active = sd_uid_get_state(uid, &state) >= 0 && state && !strcmp(state, "active");
	free(state);
	return active;
}

static int serve(void)
{
	struct ucred peer;
	socklen_t size = sizeof(peer);
	if (getsockopt(STDIN_FILENO, SOL_SOCKET, SO_PEERCRED, &peer, &size))
		die("not started from katze-face.socket: %s", strerror(errno));
	int present = at_the_screen(peer.uid);
	int result = present ? look(peer.uid, 0) : 0;
	const char *answer = result < 0 ? "none\n" : result ? "yes\n" : "no\n";
	if (write(STDOUT_FILENO, answer, strlen(answer)) < 0)
		return 1;
	fprintf(stderr, "uid %u: %s%s", (unsigned)peer.uid, present ? "" : "not the active session, ", answer);
	return 0;
}

static void read_pgm(const char *path, uint8_t *frame)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0 || !next_frame(fd, frame))
		die("%s is not a 640x360 PGM", path);
	close(fd);
}

static int compare(int count, char **paths)
{
	load_models();
	float (*f)[DIM] = calloc(count, sizeof(*f));
	static uint8_t frame[W * H];
	struct face face;
	for (int i = 0; i < count; i++) {
		read_pgm(paths[i], frame);
		if (!detect(frame, &face))
			die("%s: no face", paths[i]);
		printf("%s: face at %.0f,%.0f %.0fx%.0f, score %.2f\n", paths[i], face.x, face.y, face.w, face.h, face.score);
		describe(frame, &face, f[i]);
	}
	for (int i = 0; i < count; i++)
		for (int j = i + 1; j < count; j++)
			printf("%s %s: similarity %.3f\n", paths[i], paths[j], closest(f[i], f[j], 1));
	return 0;
}

static int self_test(void)
{
	int failed = 0;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "self-test: %s\n", #x); failed = 1; } } while (0)
	// The target itself needs no change; moved and doubled, it comes back
	float p[10], ar, ai, tx, ty;
	similarity(target, &ar, &ai, &tx, &ty);
	CHECK(fabsf(ar - 1) < 1e-4f && fabsf(ai) < 1e-4f && fabsf(tx) < 1e-3f && fabsf(ty) < 1e-3f);
	for (int k = 0; k < 10; k++)
		p[k] = target[k] * 2 + (k % 2 ? 30 : 100);
	similarity(p, &ar, &ai, &tx, &ty);
	CHECK(fabsf(ar - 0.5f) < 1e-4f && fabsf(ai) < 1e-4f && fabsf(tx + 50) < 1e-3f && fabsf(ty + 15) < 1e-3f);
	// No face in a flat grey picture, and the models load
	static uint8_t frame[W * H];
	struct face face;
	memset(frame, 128, sizeof(frame));
	load_models();
	CHECK(!detect(frame, &face));
	return failed;
}

int main(int argc, char **argv)
{
	signal(SIGPIPE, SIG_IGN);
	alarm(30); // the camera gives about 5 s; nothing here should take long
	if (argc == 2 && !strcmp(argv[1], "--self-test"))
		return self_test();
	if (argc == 2 && !strcmp(argv[1], "serve"))
		return serve();
	if (argc >= 3 && !strcmp(argv[1], "compare"))
		return compare(argc - 2, argv + 2);
	if (argc == 3 && (!strcmp(argv[1], "add") || !strcmp(argv[1], "remove") || !strcmp(argv[1], "test"))) {
		if (geteuid())
			die("this needs root: sudo %s %s %s", argv[0], argv[1], argv[2]);
		uid_t uid = user(argv[2]);
		if (!strcmp(argv[1], "add"))
			return add(uid);
		if (!strcmp(argv[1], "remove")) {
			char path[64];
			path_for(uid, path, sizeof(path));
			if (unlink(path) && errno != ENOENT)
				die("cannot remove %s: %s", path, strerror(errno));
			return 0;
		}
		int result = look(uid, 1);
		if (result < 0)
			die("%s has no face registered: sudo %s add %s", argv[2], argv[0], argv[2]);
		puts(result ? "Recognized." : "Not recognized.");
		return !result;
	}
	fprintf(stderr, "usage: katze-face add|remove|test <user> | serve | compare <a.pgm> <b.pgm>... | --self-test\n");
	return 2;
}
