/*
 * fortui_pty.c - the POSIX calls of the terminal emulator (fortui_term) that
 * Fortran cannot make portably: starting a program on a pseudo-terminal (the
 * child of a threaded process may only call async-signal-safe functions, so
 * its environment is built before fork), ioctl (variadic) for the window size,
 * and a reader thread with a ring buffer that wakes the host's event loop.
 */
#if defined(ENABLE_TERM)
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
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

/* Reader: a thread drains the program's output into a ring buffer, so that
 * the program never waits while the host draws, and calls wake() when data
 * arrives after the host asked for it (fortui_pty_rearm). The host takes the
 * bytes with fortui_pty_take. One producer, one consumer: head and tail are
 * atomic; a full ring makes the reader wait for space. */
typedef struct {
    int fd, stop[2];
    void (*wake)(void);
    pthread_t thread;
    char *buf;
    size_t cap;
    _Atomic size_t head, tail;
    _Atomic int eof, want;
    pthread_mutex_t lock;
    pthread_cond_t space;
} watch_t;

static void *watch_loop(void *arg) {
    watch_t *w = arg;
    struct pollfd p[2];
    for (;;) {
        size_t head = atomic_load(&w->head), tail = atomic_load(&w->tail);
        if (head - tail == w->cap) {
            pthread_mutex_lock(&w->lock);
            while (atomic_load(&w->head) - atomic_load(&w->tail) == w->cap) {
                struct pollfd q = {w->stop[0], POLLIN, 0};
                if (poll(&q, 1, 0) > 0) {
                    pthread_mutex_unlock(&w->lock);
                    return NULL;
                }
                pthread_cond_wait(&w->space, &w->lock);
            }
            pthread_mutex_unlock(&w->lock);
            continue;
        }
        {
            /* Read while there is output (non-blocking); wait only when none
             * is left, so a busy program costs one system call per chunk. */
            size_t at = head % w->cap;
            size_t room = w->cap - (head - tail);
            size_t n = w->cap - at < room ? w->cap - at : room;
            ssize_t got = read(w->fd, w->buf + at, n);
            if (got > 0) {
                atomic_store(&w->head, head + (size_t)got);
                if (atomic_exchange(&w->want, 0)) w->wake();
                continue;
            }
            if (got < 0 && errno == EINTR) continue;
            if (got < 0 && errno != EAGAIN) {
                atomic_store(&w->eof, 1);
                if (atomic_exchange(&w->want, 0)) w->wake();
                break;
            }
            if (got == 0) {
                atomic_store(&w->eof, 1);
                if (atomic_exchange(&w->want, 0)) w->wake();
                break;
            }
        }
        p[0].fd = w->fd;
        p[0].events = POLLIN;
        p[1].fd = w->stop[0];
        p[1].events = POLLIN;
        if (poll(p, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (p[1].revents) break;
    }
    return NULL;
}

void *fortui_pty_watch(int fd, void (*wake)(void)) {
    watch_t *w = calloc(1, sizeof(watch_t));
    if (!w) return NULL;
    w->cap = (size_t)16 << 20;
    w->buf = malloc(w->cap);
    w->fd = fd;
    w->wake = wake;
    atomic_store(&w->want, 1);
    pthread_mutex_init(&w->lock, NULL);
    pthread_cond_init(&w->space, NULL);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    if (!w->buf || pipe(w->stop) != 0) {
        free(w->buf);
        free(w);
        return NULL;
    }
    if (pthread_create(&w->thread, NULL, watch_loop, w) != 0) {
        close(w->stop[0]);
        close(w->stop[1]);
        free(w->buf);
        free(w);
        return NULL;
    }
    return w;
}

/* Up to max bytes of output: the count, 0 when none is waiting, -1 once the
 * program's side is closed and everything was taken. */
long fortui_pty_take(void *handle, char *dst, long max) {
    watch_t *w = handle;
    size_t head = atomic_load(&w->head), tail = atomic_load(&w->tail);
    size_t used = head - tail, n, at, first;
    if (used == 0) return atomic_load(&w->eof) ? -1 : 0;
    n = used < (size_t)max ? used : (size_t)max;
    at = tail % w->cap;
    first = w->cap - at < n ? w->cap - at : n;
    memcpy(dst, w->buf + at, first);
    if (n > first) memcpy(dst + first, w->buf, n - first);
    atomic_store(&w->tail, tail + n);
    if (used == w->cap) {
        pthread_mutex_lock(&w->lock);
        pthread_cond_signal(&w->space);
        pthread_mutex_unlock(&w->lock);
    }
    return (long)n;
}

/* The host took everything: wake it when more arrives (at once if some
 * already did). */
void fortui_pty_rearm(void *handle) {
    watch_t *w = handle;
    if (!w) return;
    atomic_store(&w->want, 1);
    if (atomic_load(&w->head) != atomic_load(&w->tail) || atomic_load(&w->eof)) {
        if (atomic_exchange(&w->want, 0)) w->wake();
    }
}

void fortui_pty_unwatch(void *handle) {
    watch_t *w = handle;
    if (!w) return;
    if (write(w->stop[1], "q", 1) < 0) {}
    pthread_mutex_lock(&w->lock);
    pthread_cond_signal(&w->space);
    pthread_mutex_unlock(&w->lock);
    pthread_join(w->thread, NULL);
    close(w->stop[0]);
    close(w->stop[1]);
    pthread_mutex_destroy(&w->lock);
    pthread_cond_destroy(&w->space);
    free(w->buf);
    free(w);
}
#endif
