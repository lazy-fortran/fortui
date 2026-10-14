#define _DEFAULT_SOURCE
/*
 * fortui_tty.c - small POSIX helpers for the termbox2 TUI backend.
 *
 * termbox2 owns the terminal (raw mode, alternate screen). These helpers use
 * its tty descriptor for what termbox2 does not offer: writing escape
 * sequences in-band (graphics), reading the replies of terminal queries
 * (capability detection works over ssh, where environment variables do not
 * cross), and the cell size in pixels from TIOCGWINSZ.
 */
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

int tb_get_fds(int *ttyfd, int *resizefd);

static int tty_fd(void) {
    int ttyfd = -1, resizefd = -1;
    if (tb_get_fds(&ttyfd, &resizefd) != 0) return -1;
    return ttyfd;
}

/* Write all n bytes; 0 on success, -1 on failure. */
int fortui_tty_write(const char *buf, long n) {
    int fd = tty_fd();
    long done = 0;
    if (fd < 0) return -1;
    while (done < n) {
        ssize_t w = write(fd, buf + done, (size_t)(n - done));
        if (w > 0) {
            done += w;
        } else if (w < 0 && (errno == EAGAIN || errno == EINTR)) {
            struct pollfd p = {fd, POLLOUT, 0};
            (void)poll(&p, 1, 100);
        } else {
            return -1;
        }
    }
    return 0;
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1.0e6;
}

/* Does buf end with a primary device attributes reply ESC [ ? ... c ? */
static int has_da1(const char *buf, long n) {
    long i;
    for (i = 0; i + 2 < n; i++) {
        if (buf[i] == 27 && buf[i + 1] == '[' && buf[i + 2] == '?') {
            long j = i + 3;
            while (j < n && ((buf[j] >= '0' && buf[j] <= '9') || buf[j] == ';'))
                j++;
            if (j < n && buf[j] == 'c') return 1;
        }
    }
    return 0;
}

/*
 * Send query (which should end with ESC [ c) and collect the replies until the
 * device attributes reply arrives or timeout_ms passes. Returns the number of
 * bytes stored in reply (at most cap), or -1 if the tty is not available.
 */
long fortui_tty_query(const char *query, long nquery, char *reply, long cap,
                      int timeout_ms) {
    int fd = tty_fd();
    long n = 0;
    double deadline;
    if (fd < 0) return -1;
    if (fortui_tty_write(query, nquery) != 0) return -1;
    deadline = now_ms() + timeout_ms;
    while (n < cap) {
        double left = deadline - now_ms();
        struct pollfd p = {fd, POLLIN, 0};
        ssize_t r;
        if (left <= 0) break;
        if (poll(&p, 1, (int)left + 1) <= 0) break;
        r = read(fd, reply + n, (size_t)(cap - n));
        if (r <= 0) {
            if (r < 0 && (errno == EAGAIN || errno == EINTR)) continue;
            break;
        }
        n += r;
        if (has_da1(reply, n)) break;
    }
    return n;
}

/* Terminal size in cells and pixels (pixels are 0 when unknown). */
int fortui_tty_size(int *cols, int *rows, int *xpixel, int *ypixel) {
    struct winsize ws;
    int fd = tty_fd();
    *cols = *rows = *xpixel = *ypixel = 0;
    if (fd < 0 || ioctl(fd, TIOCGWINSZ, &ws) != 0) return -1;
    *cols = ws.ws_col;
    *rows = ws.ws_row;
    *xpixel = ws.ws_xpixel;
    *ypixel = ws.ws_ypixel;
    return 0;
}
