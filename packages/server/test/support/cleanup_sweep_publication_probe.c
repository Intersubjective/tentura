// Test-only fault injection at the real fixture's libc publication boundary.
// Transient mode exposes a direct write, but leaves atomic rename publication
// alone. Persistent mode corrupts the final marker, including renamed ones,
// to exercise the reader's failure diagnostic rather than require a retry API.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int selected(const char *path) {
  const char *marker = getenv("PUBLICATION_MARKER");
  const char *base = strrchr(path, '/');
  return marker && strcmp(base ? base + 1 : path, marker) == 0;
}

static void record_process(pid_t process_id) {
  const char *dir = getenv("PUBLICATION_RECORDS");
  if (!dir) return;
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "%s/%ld", dir, (long)process_id);
  int fd = open(path, O_CREAT | O_WRONLY, 0600);
  if (fd >= 0) close(fd);
}

// Record a child before the launcher can publish readiness. This lets test
// teardown reclaim it even if a deliberately corrupt marker is read before
// the child has been scheduled to open its own marker.
pid_t fork(void) {
  pid_t (*original)(void) = dlsym(RTLD_NEXT, "fork");
  pid_t child = original();
  if (child > 0) record_process(child);
  return child;
}

static void corrupt(const char *path) {
  int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0600);
  if (fd < 0) _exit(91);
  const char *text = getenv("PUBLICATION_CONTENT");
  if (!text) text = "publication interrupted\n";
  size_t size = strlen(text);
  if (write(fd, text, size) != (ssize_t)size) _exit(92);
  close(fd);
}

FILE *fopen(const char *path, const char *mode) {
  FILE *(*original)(const char *, const char *) = dlsym(RTLD_NEXT, "fopen");
  // Record even temporary writers so persistent corruption cannot leak a
  // sleeping compiler when the caller cannot parse its readiness marker.
  if (strchr(mode, 'w')) record_process(getpid());
  if (strchr(mode, 'w') && selected(path)) {
    corrupt(path);
    if (strcmp(getenv("PUBLICATION_MODE"), "transient") == 0) usleep(500000);
  }
  FILE *file = original(path, mode);
  if (file && strchr(mode, 'w') && selected(path) &&
      strcmp(getenv("PUBLICATION_MODE"), "persistent") == 0) {
    // Keep the marker invalid throughout fprintf/fclose, rather than expose
    // a valid PID for a scheduling-dependent instant before corrupting it.
    corrupt(path);
    int nullfd = open("/dev/null", O_WRONLY);
    if (nullfd < 0 || dup2(nullfd, fileno(file)) < 0) _exit(93);
    close(nullfd);
  }
  return file;
}

int rename(const char *old, const char *path) {
  int (*original)(const char *, const char *) = dlsym(RTLD_NEXT, "rename");
  if (selected(path) &&
      strcmp(getenv("PUBLICATION_MODE"), "persistent") == 0) corrupt(old);
  return original(old, path);
}
