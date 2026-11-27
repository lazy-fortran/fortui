/*
 * fortui_net.c - the socket calls that Fortran cannot make portably: name
 * lookup, connecting with a time limit to a host and port or to a local socket
 * (a host starting with "/"), and sending and receiving with a time limit, for
 * the printing service (fortui_ipp); and the same without waiting for the
 * network service (fortui_net_posix), which advances a request a little in
 * every frame. Elsewhere than POSIX every call fails.
 */
#if !defined(_WIN32)
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <pthread.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

/* Darwin has neither flag; open_socket sets SO_NOSIGPIPE there instead. */
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* A socket closed on exec that a closed peer does not answer with SIGPIPE. */
static int open_socket(int domain, int type, int protocol) {
#ifdef SOCK_CLOEXEC
    return socket(domain, type | SOCK_CLOEXEC, protocol);
#else
    int fd = socket(domain, type, protocol);
    if (fd < 0) return -1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0) {
        close(fd);
        return -1;
    }
#ifdef SO_NOSIGPIPE
    {
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one) != 0) {
            close(fd);
            return -1;
        }
    }
#endif
    return fd;
#endif
}

static int wait_for(int fd, short events, int timeout_ms) {
    struct pollfd p = {fd, events, 0};
    int r;
    do {
        r = poll(&p, 1, timeout_ms);
    } while (r < 0 && errno == EINTR);
    return r > 0 ? 0 : -1;
}

/* Connect within timeout_ms; on success the descriptor, else -1. */
static int connect_within(int fd, const struct sockaddr *addr, socklen_t len,
                          int timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0), err = 0;
    socklen_t elen = sizeof err;
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (connect(fd, addr, len) != 0) {
        if (errno != EINPROGRESS || wait_for(fd, POLLOUT, timeout_ms) != 0 ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &elen) != 0 || err != 0) {
            close(fd);
            return -1;
        }
    }
    fcntl(fd, F_SETFL, flags);
    return fd;
}

int fortui_net_open(const char *host, int port, int timeout_ms) {
    if (host[0] == '/') {
        struct sockaddr_un a;
        int fd;
        if (strlen(host) >= sizeof a.sun_path) return -1;
        memset(&a, 0, sizeof a);
        a.sun_family = AF_UNIX;
        strcpy(a.sun_path, host);
        if ((fd = open_socket(AF_UNIX, SOCK_STREAM, 0)) < 0) return -1;
        return connect_within(fd, (struct sockaddr *)&a, sizeof a, timeout_ms);
    }
    struct addrinfo hints, *list, *ai;
    char service[16];
    int fd = -1;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(service, sizeof service, "%d", port);
    if (getaddrinfo(host, service, &hints, &list) != 0) return -1;
    for (ai = list; ai && fd < 0; ai = ai->ai_next) {
        int s = open_socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (s >= 0) fd = connect_within(s, ai->ai_addr, ai->ai_addrlen, timeout_ms);
    }
    freeaddrinfo(list);
    return fd;
}

/* Send all n bytes; 0 on success, else -1. */
int fortui_net_send(int fd, const char *buf, long n, int timeout_ms) {
    while (n > 0) {
        ssize_t k;
        if (wait_for(fd, POLLOUT, timeout_ms) != 0) return -1;
        k = send(fd, buf, (size_t)n, MSG_NOSIGNAL);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return -1;
        buf += k;
        n -= k;
    }
    return 0;
}

/* Up to n bytes: the count, 0 at the end of the stream, -1 on error or time-out. */
long fortui_net_recv(int fd, char *buf, long n, int timeout_ms) {
    ssize_t k;
    if (wait_for(fd, POLLIN, timeout_ms) != 0) return -1;
    do {
        k = recv(fd, buf, (size_t)n, 0);
    } while (k < 0 && errno == EINTR);
    return (long)k;
}

void fortui_net_close(int fd) {
    if (fd >= 0) close(fd);
}

/* Start connecting without waiting: the descriptor (left nonblocking), or -1.
 * The name lookup still waits. */
int fortui_net_begin(const char *host, int port) {
    struct addrinfo hints, *list, *ai;
    char service[16];
    int fd = -1;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(service, sizeof service, "%d", port);
    if (getaddrinfo(host, service, &hints, &list) != 0) return -1;
    for (ai = list; ai && fd < 0; ai = ai->ai_next) {
        int s = open_socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (s < 0) continue;
        fcntl(s, F_SETFL, fcntl(s, F_GETFL, 0) | O_NONBLOCK);
        if (connect(s, ai->ai_addr, ai->ai_addrlen) == 0 || errno == EINPROGRESS) fd = s;
        else close(s);
    }
    freeaddrinfo(list);
    return fd;
}

/* 1 when the connection started by fortui_net_begin is up, 0 while it is
 * pending, -1 when it failed. */
int fortui_net_connected(int fd) {
    struct pollfd p = {fd, POLLOUT, 0};
    int err = 0;
    socklen_t elen = sizeof err;
    if (poll(&p, 1, 0) == 0) return 0;
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &elen) != 0 || err != 0) return -1;
    return 1;
}

/* Bytes sent now (possibly 0), or -1 on error. */
long fortui_net_send_now(int fd, const char *buf, long n) {
    ssize_t k = send(fd, buf, (size_t)n, MSG_NOSIGNAL);
    if (k < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;
    return (long)k;
}

/* Bytes received now: the count, 0 at the end of the stream, -2 when nothing
 * has arrived yet, -1 on error. */
long fortui_net_recv_now(int fd, char *buf, long n) {
    ssize_t k = recv(fd, buf, (size_t)n, 0);
    if (k < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? -2 : -1;
    return (long)k;
}

/* A thread that waits on the sockets of open network requests and wakes the
 * host's event loop once when one of them can be read or written, so a frame
 * advances the request without the runtime looking on a timer. The frame hands
 * over the new set of sockets, which also re-arms the notification. */
#define WATCH_MAX 64
static struct {
    pthread_mutex_t lock;
    int pipe[2];
    int fds[WATCH_MAX];
    short events[WATCH_MAX];
    int n;
    void (*waker)(void);
    int started;
} watch = {PTHREAD_MUTEX_INITIALIZER, {-1, -1}, {0}, {0}, 0, NULL, 0};

static void *watch_loop(void *arg) {
    struct pollfd p[WATCH_MAX + 1];
    (void)arg;
    for (;;) {
        int n, i;
        pthread_mutex_lock(&watch.lock);
        n = watch.n;
        for (i = 0; i < n; i++) {
            p[i + 1].fd = watch.fds[i];
            p[i + 1].events = watch.events[i];
            p[i + 1].revents = 0;
        }
        pthread_mutex_unlock(&watch.lock);
        p[0].fd = watch.pipe[0];
        p[0].events = POLLIN;
        p[0].revents = 0;
        if (poll(p, (nfds_t)(n + 1), -1) < 0) continue;
        if (p[0].revents) {
            char b[64];
            while (read(watch.pipe[0], b, sizeof b) > 0) {}
            continue;
        }
        /* One wake-up per set: the frame that follows hands over a new set. */
        pthread_mutex_lock(&watch.lock);
        watch.n = 0;
        pthread_mutex_unlock(&watch.lock);
        if (watch.waker) watch.waker();
    }
    return NULL;
}

/* Start the thread with the host's waker; 0 on success. */
int fortui_net_watch_start(void (*waker)(void)) {
    pthread_t t;
    if (watch.started) {
        watch.waker = waker;
        return 0;
    }
    if (pipe(watch.pipe) != 0) return -1;
    fcntl(watch.pipe[0], F_SETFL, O_NONBLOCK);
    fcntl(watch.pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(watch.pipe[1], F_SETFD, FD_CLOEXEC);
    watch.waker = waker;
    if (pthread_create(&t, NULL, watch_loop, NULL) != 0) return -1;
    pthread_detach(t);
    watch.started = 1;
    return 0;
}

/* The sockets to wait on: writing[i] nonzero waits until fds[i] can be written
 * (a connection or a request still going out), else until it can be read. */
void fortui_net_watch_set(const int *fds, const int *writing, int n) {
    int i;
    if (!watch.started) return;
    if (n > WATCH_MAX) n = WATCH_MAX;
    pthread_mutex_lock(&watch.lock);
    for (i = 0; i < n; i++) {
        watch.fds[i] = fds[i];
        watch.events[i] = writing[i] ? POLLOUT : POLLIN;
    }
    watch.n = n;
    pthread_mutex_unlock(&watch.lock);
    (void)!write(watch.pipe[1], "x", 1);
}

/* The login name of this process's user, for requesting-user-name. */
int fortui_net_user(char *buf, int n) {
    struct passwd *pw = getpwuid(getuid());
    if (!pw || (int)strlen(pw->pw_name) >= n) return -1;
    strcpy(buf, pw->pw_name);
    return (int)strlen(buf);
}
#else
int fortui_net_open(const char *host, int port, int timeout_ms) {
    (void)host; (void)port; (void)timeout_ms;
    return -1;
}
int fortui_net_send(int fd, const char *buf, long n, int timeout_ms) {
    (void)fd; (void)buf; (void)n; (void)timeout_ms;
    return -1;
}
long fortui_net_recv(int fd, char *buf, long n, int timeout_ms) {
    (void)fd; (void)buf; (void)n; (void)timeout_ms;
    return -1;
}
void fortui_net_close(int fd) { (void)fd; }
int fortui_net_begin(const char *host, int port) {
    (void)host; (void)port;
    return -1;
}
int fortui_net_connected(int fd) {
    (void)fd;
    return -1;
}
long fortui_net_send_now(int fd, const char *buf, long n) {
    (void)fd; (void)buf; (void)n;
    return -1;
}
long fortui_net_recv_now(int fd, char *buf, long n) {
    (void)fd; (void)buf; (void)n;
    return -1;
}
int fortui_net_watch_start(void (*waker)(void)) {
    (void)waker;
    return -1;
}
void fortui_net_watch_set(const int *fds, const int *writing, int n) {
    (void)fds; (void)writing; (void)n;
}
int fortui_net_user(char *buf, int n) {
    (void)buf; (void)n;
    return -1;
}
#endif
