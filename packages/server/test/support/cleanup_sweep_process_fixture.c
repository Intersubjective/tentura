// Test-only Linux process fixture. No Dart VM/compiler is started or signalled.
// The shared-library build limits /proc enumeration to test-owned processes;
// all per-process metadata is read unchanged from the kernel's real /proc.
// The executable build supplies sleeping runner/compiler stand-ins and a
// seccomp boundary that forbids signalling any PID outside this fixture.
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef CLEANUP_PROC_VIEW
#include <dirent.h>
#include <dlfcn.h>

DIR *opendir(const char *path) {
  static DIR *(*real_opendir)(const char *) = NULL;
  if (!real_opendir) real_opendir = dlsym(RTLD_NEXT, "opendir");
  const char *view = getenv("CLEANUP_SWEEP_PROC_VIEW");
  return real_opendir(view && strcmp(path, "/proc") == 0 ? view : path);
}

#else
#include <fcntl.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <signal.h>
#include <stddef.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/types.h>

static void ready(const char *path, pid_t process_id) {
  FILE *file = fopen(path, "w");
  if (!file) { perror("fixture ready"); exit(2); }
  fprintf(file, "%ld\n", (long)process_id);
  if (fclose(file)) { perror("fixture ready close"); exit(2); }
}

// kill(pid, sig) is allowed only for the two stand-ins. Also block alternate
// signalling syscalls, including process-group and pidfd signals, so even a
// differently implemented cleanup cannot signal the host's real compilers.
static void restrict_signals(pid_t owner, pid_t compiler) {
  if (owner <= 0) owner = compiler; // Never allow kill(0), a process-group signal.
  struct sock_filter instructions[] = {
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_kill, 0, 5),
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[0])),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (unsigned)owner, 2, 0),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (unsigned)compiler, 1, 0),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_tkill, 3, 0),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_tgkill, 2, 0),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_pidfd_send_signal, 1, 0),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
  };
  struct sock_fprog program = {
    .len = sizeof(instructions) / sizeof(instructions[0]),
    .filter = instructions,
  };
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) ||
      prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program)) {
    perror("fixture signal sandbox");
    exit(2);
  }
}

int main(int argc, char **argv) {
  // --sandbox OWNER_PID COMPILER_PID COMMAND [ARGS...]
  if (argc >= 5 && strcmp(argv[1], "--sandbox") == 0) {
    restrict_signals((pid_t)strtol(argv[2], NULL, 10),
                     (pid_t)strtol(argv[3], NULL, 10));
    execvp(argv[4], &argv[4]);
    perror("fixture sandbox exec");
    return 2;
  }

  for (int index = 1; index < argc; ++index) {
    if (strcmp(argv[index], "--standin-owner") == 0 ||
        strcmp(argv[index], "--standin-compiler") == 0) {
      if (index + 1 >= argc) return 2;
      ready(argv[index + 1], getpid());
      for (;;) pause();
    }
  }

  // --start live|orphan KERNEL COMPILER_READY OWNER_READY FRONTEND ARGV...
  if (argc >= 9 && strcmp(argv[1], "--start") == 0) {
    char executable[4096];
    ssize_t length = readlink("/proc/self/exe", executable, sizeof(executable)-1);
    if (length < 0) { perror("fixture executable"); return 2; }
    executable[length] = '\0';
    pid_t compiler = fork();
    if (compiler < 0) { perror("fixture fork"); return 2; }
    if (compiler == 0) {
      // Don't hold the launcher's captured pipes open after it exits.
      int null_fd = open("/dev/null", O_RDWR);
      if (null_fd < 0) _exit(2);
      for (int fd = 0; fd <= 2; ++fd) dup2(null_fd, fd);
      if (null_fd > 2) close(null_fd);
      execl(executable, argv[7], argv[6], "--target=vm", "--output-dill",
            argv[3], "--standin-compiler", argv[4], (char *)NULL);
      _exit(2);
    }
    ready(argv[4], compiler);
    if (strcmp(argv[2], "orphan") == 0) return 0;
    // Reuse the real outer runner's argv, without adding a reference to the
    // fixture kernel cache. The child's --output-dill is its real reference.
    char **owner_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (!owner_argv) return 2;
    int count = 0;
    for (int index = 7; index < argc; ++index) owner_argv[count++] = argv[index];
    owner_argv[count++] = "--standin-owner";
    owner_argv[count] = argv[5];
    execv(executable, owner_argv);
    perror("fixture owner exec");
    return 2;
  }
  fputs("invalid fixture invocation\n", stderr);
  return 2;
}
#endif
