/*
 * fortui_net.c - the socket calls of the printing service (fortui_ipp) that
 * Fortran cannot make portably: name lookup, connecting with a time limit to a
 * host and port or to a local socket (a host starting with "/"), and sending
 * and receiving with a time limit. Elsewhere than POSIX every call fails.
 */
#if !defined(_WIN32)
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

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
        if ((fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0)) < 0) return -1;
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
        int s = socket(ai->ai_family, ai->ai_socktype | SOCK_CLOEXEC, ai->ai_protocol);
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
int fortui_net_user(char *buf, int n) {
    (void)buf; (void)n;
    return -1;
}
#endif
