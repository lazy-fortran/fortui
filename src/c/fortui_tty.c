#define _DEFAULT_SOURCE
/*
 * fortui_tty.c - the terminal device of the TUI backend (POSIX).
 *
 * Opens /dev/tty in raw mode, reports window size changes through a pipe that
 * the SIGWINCH handler writes to, and waits for input bytes or a resize. The
 * same descriptor serves in-band escape sequences (graphics), the replies of
 * terminal queries (capability detection works over ssh, where environment
 * variables do not cross) and the cell size in pixels from TIOCGWINSZ.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static int tty = -1;
static int winch_pipe[2] = {-1, -1};
static struct termios saved_tios;
static struct sigaction saved_winch;

static int tty_fd(void) { return tty; }

static void on_winch(int sig) {
    int saved_errno = errno;
    char c = 0;
    (void)sig;
    if (write(winch_pipe[1], &c, 1) < 0) { /* the pipe is full: a resize is pending */ }
    errno = saved_errno;
}

static void close_pipe(void) {
    if (winch_pipe[0] >= 0) close(winch_pipe[0]);
    if (winch_pipe[1] >= 0) close(winch_pipe[1]);
    winch_pipe[0] = winch_pipe[1] = -1;
}

/* Raw mode on /dev/tty; 0 on success, -1 if there is no terminal. */
int fortui_tty_open(void) {
    struct termios tios;
    struct sigaction sa;
    int k;
    if (tty >= 0) return -1;
    tty = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (tty < 0) return -1;
    if (tcgetattr(tty, &saved_tios) != 0 || pipe(winch_pipe) != 0) {
        close(tty);
        tty = -1;
        return -1;
    }
    for (k = 0; k < 2; k++) {
        fcntl(winch_pipe[k], F_SETFL, fcntl(winch_pipe[k], F_GETFL) | O_NONBLOCK);
        fcntl(winch_pipe[k], F_SETFD, FD_CLOEXEC);
    }
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_winch;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGWINCH, &sa, &saved_winch) != 0) {
        close_pipe();
        close(tty);
        tty = -1;
        return -1;
    }
    tios = saved_tios;
    tios.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    tios.c_oflag &= ~OPOST;
    tios.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    tios.c_cflag &= ~(CSIZE | PARENB);
    tios.c_cflag |= CS8;
    tios.c_cc[VMIN] = 1;
    tios.c_cc[VTIME] = 0;
    if (tcsetattr(tty, TCSAFLUSH, &tios) != 0) {
        sigaction(SIGWINCH, &saved_winch, NULL);
        close_pipe();
        close(tty);
        tty = -1;
        return -1;
    }
    return 0;
}

/* The terminal mode from before fortui_tty_open; 0 on success. */
int fortui_tty_close(void) {
    int status = 0;
    if (tty < 0) return -1;
    if (tcsetattr(tty, TCSAFLUSH, &saved_tios) != 0) status = -1;
    sigaction(SIGWINCH, &saved_winch, NULL);
    close_pipe();
    close(tty);
    tty = -1;
    return status;
}

/*
 * Wait up to timeout_ms (negative: without limit) and read at most cap bytes.
 * Returns the number of bytes, 0 when the time is up, -2 when the window size
 * changed, -1 on failure.
 */
long fortui_tty_read(char *buf, long cap, int timeout_ms) {
    struct pollfd p[2];
    char drain[64];
    int r;
    if (tty < 0) return -1;
    p[0].fd = winch_pipe[0];
    p[0].events = POLLIN;
    p[1].fd = tty;
    p[1].events = POLLIN;
    for (;;) {
        p[0].revents = p[1].revents = 0;
        r = poll(p, 2, timeout_ms < 0 ? -1 : timeout_ms);
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) return -1;
        if (r == 0) return 0;
        if (p[0].revents & POLLIN) {
            while (read(winch_pipe[0], drain, sizeof drain) > 0) {}
            return -2;
        }
        if (p[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t n = read(tty, buf, (size_t)cap);
            if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
            return n > 0 ? (long)n : -1;
        }
    }
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
