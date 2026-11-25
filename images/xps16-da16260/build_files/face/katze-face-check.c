// For pam_exec on the lock screen (/etc/pam.d/kde-fingerprint), which runs as the user.
//
//   katze-face-check enrolled   exits 0 if the user has a face registered (katze-face add)
//   katze-face-check            asks katze-face.socket whether the user is in front of the infrared camera: 0 for yes
//
// It needs no privilege, sends nothing and links nothing big: the service reads who is asking from the socket.
// It only answers for the account it runs as, and only when that is the one PAM is unlocking.
#include <errno.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET "/run/katze-face.sock"
#define STATE "/var/lib/katze/face"

int main(int argc, char **argv)
{
	// pam_exec sets PAM_USER
	const char *name = getenv("PAM_USER");
	struct passwd *pw = name ? getpwnam(name) : NULL;
	if (!pw || pw->pw_uid != getuid() || pw->pw_uid != geteuid())
		return 1;

	if (argc == 2 && !strcmp(argv[1], "enrolled")) {
		char path[64];
		struct stat st;
		snprintf(path, sizeof(path), STATE "/%u", (unsigned)pw->pw_uid);
		return stat(path, &st) ? 1 : 0;
	}
	if (argc != 1)
		return 2;

	struct sockaddr_un address = { .sun_family = AF_UNIX, .sun_path = SOCKET };
	char answer[8] = { 0 };
	size_t got = 0;
	alarm(15); // the camera gives about 5 s
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address)))
		return 2;
	while (got < sizeof(answer) - 1) {
		ssize_t n = read(fd, answer + got, sizeof(answer) - 1 - got);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;
		got += n;
	}
	return strcmp(answer, "yes\n") ? 1 : 0;
}
