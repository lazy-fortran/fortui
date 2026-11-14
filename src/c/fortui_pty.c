/*
 * fortui_pty.c - the POSIX calls of the terminal emulator (fortui_term) that
 * Fortran cannot make portably: starting a program on a pseudo-terminal (the
 * child of a threaded process may only call async-signal-safe functions, so
 * its environment is built before fork), ioctl (variadic) for the window size,
 * and a thread that wakes the host's event loop when the program writes.
 */
#if defined(ENABLE_TERM)
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

extern char **environ;

/* Start the program `args` (arguments separated by NUL bytes, nargs of them)
 * in directory `cwd` (empty: inherited) on a new pseudo-terminal of rows x
 * cols cells of xpix x ypix pixels. TERM, COLORTERM and TERM_PROGRAM tell it
 * what it talks to. Returns the master descriptor and sets *pid, or -1. */
int fortui_pty_spawn(const char *args, int nargs, const char *cwd, int rows, int cols,
                     int xpix, int ypix, int *pid) {
    struct winsize ws;
    char **argv, **envp;
    const char *p = args;
    int i, n, fd = -1;

    argv = calloc((size_t)nargs + 1, sizeof(char *));
    for (n = 0; environ[n]; n++) {}
    envp = calloc((size_t)n + 4, sizeof(char *));
    if (!argv || !envp) return -1;
    for (i = 0; i < nargs; i++) {
        argv[i] = (char *)p;
        p += strlen(p) + 1;
    }
    for (i = 0, n = 0; environ[i]; i++) {
        if (strncmp(environ[i], "TERM=", 5) == 0 || strncmp(environ[i], "COLORTERM=", 10) == 0 ||
            strncmp(environ[i], "TERM_PROGRAM=", 13) == 0)
            continue;
        envp[n++] = environ[i];
    }
    envp[n++] = "TERM=xterm-256color";
    envp[n++] = "COLORTERM=truecolor";
    envp[n++] = "TERM_PROGRAM=fortterm";
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = (unsigned short)xpix;
    ws.ws_ypixel = (unsigned short)ypix;
    *pid = forkpty(&fd, NULL, NULL, &ws);
    if (*pid == 0) {
        if (cwd && cwd[0]) {
            if (chdir(cwd) != 0) {}
        }
        signal(SIGPIPE, SIG_DFL);
        execvpe(argv[0], argv, envp);
        _exit(127);
    }
    free(argv);
    free(envp);
    return *pid < 0 ? -1 : fd;
}

int fortui_pty_resize(int fd, int rows, int cols, int xpix, int ypix) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = (unsigned short)xpix;
    ws.ws_ypixel = (unsigned short)ypix;
    return ioctl(fd, TIOCSWINSZ, &ws);
}

/* Exit status of the program once it ended (-1 while it runs). */
int fortui_pty_exited(int pid) {
    int status = 0;
    if (waitpid(pid, &status, WNOHANG) != pid) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

/* Watcher: calls wake() when fd has data, then sleeps until rearmed, so that
 * a host waiting for events sleeps while the program is quiet. */
typedef struct {
    int fd, rearm[2];
    void (*wake)(void);
    pthread_t thread;
} watch_t;

static void *watch_loop(void *arg) {
    watch_t *w = arg;
    struct pollfd p[2];
    char b;
    for (;;) {
        p[0].fd = w->fd;
        p[0].events = POLLIN;
        p[1].fd = w->rearm[0];
        p[1].events = POLLIN;
        if (poll(p, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (p[1].revents) {
            if (read(w->rearm[0], &b, 1) <= 0 || b == 'q') break;
            continue;
        }
        if (p[0].revents) {
            w->wake();
            /* Wait for the host to read before looking again. */
            p[1].revents = 0;
            if (poll(&p[1], 1, -1) < 0 && errno != EINTR) break;
            if (read(w->rearm[0], &b, 1) <= 0 || b == 'q') break;
        }
    }
    return NULL;
}

void *fortui_pty_watch(int fd, void (*wake)(void)) {
    watch_t *w = calloc(1, sizeof(watch_t));
    if (!w) return NULL;
    w->fd = fd;
    w->wake = wake;
    if (pipe(w->rearm) != 0) {
        free(w);
        return NULL;
    }
    if (pthread_create(&w->thread, NULL, watch_loop, w) != 0) {
        close(w->rearm[0]);
        close(w->rearm[1]);
        free(w);
        return NULL;
    }
    return w;
}

void fortui_pty_rearm(void *handle) {
    watch_t *w = handle;
    if (w && write(w->rearm[1], "r", 1) < 0) {}
}

void fortui_pty_unwatch(void *handle) {
    watch_t *w = handle;
    if (!w) return;
    if (write(w->rearm[1], "q", 1) < 0) {}
    pthread_join(w->thread, NULL);
    close(w->rearm[0]);
    close(w->rearm[1]);
    free(w);
}
#endif
