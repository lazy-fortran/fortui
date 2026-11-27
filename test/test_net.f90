module test_net_fake
    !! A transport whose outcomes the test decides.
    use fortui_net_transport
    implicit none
    private
    type, extends(net_transport_t), public :: fake_transport_t
        integer :: started = 0, cancelled = 0, last_id = 0
        integer :: streams = 0
        character(:), allocatable :: last_url, last_method, last_body, last_type
        logical :: finish = .false.
        integer :: messages = 0
    contains
        procedure :: start => fake_start
        procedure :: take => fake_take
        procedure :: next_message => fake_next
        procedure :: cancel => fake_cancel
        procedure :: wakes => fake_wakes
    end type fake_transport_t
contains
    logical function fake_start(self, id, method, url, body, content_type, stream)
        class(fake_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        character(*), intent(in) :: method, url, body, content_type
        logical, intent(in) :: stream
        fake_start = index(url, 'refuse') == 0
        if (.not. fake_start) return
        self%started = self%started + 1
        if (stream) self%streams = self%streams + 1
        self%last_type = content_type
        self%last_id = id
        self%last_url = url
        self%last_method = method
        self%last_body = body
    end function fake_start
    subroutine fake_take(self, id, status, code, body, message)
        class(fake_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status, code
        character(:), allocatable, intent(out) :: body, message
        status = NET_PENDING
        code = 0
        body = ''
        message = ''
        if (.not. self%finish .or. id /= self%last_id) return
        status = NET_DONE
        code = 200
        body = 'echo ' // self%last_body
        self%finish = .false.
    end subroutine fake_take
    subroutine fake_next(self, id, status, data, got)
        class(fake_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status
        character(:), allocatable, intent(out) :: data
        logical, intent(out) :: got
        status = NET_OPEN
        got = self%messages > 0 .and. id == self%last_id
        data = ''
        if (got) then
            data = 'message ' // achar(48 + self%messages)
            self%messages = self%messages - 1
        end if
    end subroutine fake_next
    subroutine fake_cancel(self, id)
        class(fake_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        if (id > 0) self%cancelled = self%cancelled + 1
    end subroutine fake_cancel
    logical function fake_wakes(self)
        class(fake_transport_t), intent(in) :: self
        fake_wakes = self%started >= 0
    end function fake_wakes
end module test_net_fake

module test_net_wake
    !! A waker that counts its calls, as a host's event loop would wake.
    use iso_c_binding, only: c_int
    implicit none
    integer(c_int), volatile :: wakes = 0
contains
    subroutine count_wake() bind(C)
        wakes = wakes + 1
    end subroutine count_wake
end module test_net_wake

module test_net_server
    !! A tiny HTTP server in a child process, for the socket transport.
    use iso_c_binding
    implicit none
    private
    public :: serve_in_child, stop_child

    type, bind(C) :: sockaddr_in_t
        integer(c_int16_t) :: family = 0
        integer(c_int16_t) :: port = 0
        integer(c_int32_t) :: addr = 0
        character(kind=c_char) :: zero(8) = c_null_char
    end type sockaddr_in_t

    interface
        integer(c_int) function c_socket(d, t, p) bind(C, name='socket')
            import :: c_int
            integer(c_int), value :: d, t, p
        end function c_socket
        integer(c_int) function c_bind(fd, a, n) bind(C, name='bind')
            import :: c_int, sockaddr_in_t
            integer(c_int), value :: fd
            type(sockaddr_in_t), intent(in) :: a
            integer(c_int), value :: n
        end function c_bind
        integer(c_int) function c_listen(fd, n) bind(C, name='listen')
            import :: c_int
            integer(c_int), value :: fd, n
        end function c_listen
        integer(c_int) function c_accept(fd, a, n) bind(C, name='accept')
            import :: c_int, c_ptr
            integer(c_int), value :: fd
            type(c_ptr), value :: a, n
        end function c_accept
        integer(c_int) function c_getsockname(fd, a, n) bind(C, name='getsockname')
            import :: c_int, sockaddr_in_t
            integer(c_int), value :: fd
            type(sockaddr_in_t), intent(inout) :: a
            integer(c_int), intent(inout) :: n
        end function c_getsockname
        integer(c_long) function c_recv(fd, b, n, f) bind(C, name='recv')
            import :: c_int, c_long, c_char, c_size_t
            integer(c_int), value :: fd
            character(kind=c_char), intent(out) :: b(*)
            integer(c_size_t), value :: n
            integer(c_int), value :: f
        end function c_recv
        integer(c_long) function c_send(fd, b, n, f) bind(C, name='send')
            import :: c_int, c_long, c_char, c_size_t
            integer(c_int), value :: fd
            character(kind=c_char), intent(in) :: b(*)
            integer(c_size_t), value :: n
            integer(c_int), value :: f
        end function c_send
        integer(c_int) function c_close(fd) bind(C, name='close')
            import :: c_int
            integer(c_int), value :: fd
        end function c_close
        integer(c_int) function c_fork() bind(C, name='fork')
            import :: c_int
        end function c_fork
        integer(c_int) function c_kill(pid, sig) bind(C, name='kill')
            import :: c_int
            integer(c_int), value :: pid, sig
        end function c_kill
        integer(c_int) function c_waitpid(pid, st, opt) bind(C, name='waitpid')
            import :: c_int
            integer(c_int), value :: pid
            integer(c_int), intent(out) :: st
            integer(c_int), value :: opt
        end function c_waitpid
        integer(c_int) function c_usleep(us) bind(C, name='usleep')
            import :: c_int
            integer(c_int), value :: us
        end function c_usleep
        subroutine c_exit(st) bind(C, name='_exit')
            import :: c_int
            integer(c_int), value :: st
        end subroutine c_exit
        integer(c_int16_t) function c_htons(x) bind(C, name='htons')
            import :: c_int16_t
            integer(c_int16_t), value :: x
        end function c_htons
        integer(c_int32_t) function c_htonl(x) bind(C, name='htonl')
            import :: c_int32_t
            integer(c_int32_t), value :: x
        end function c_htonl
    end interface

    character(len=2), parameter :: CRLF = achar(13) // achar(10)

contains

    subroutine serve_in_child(port, pid)
        !! Listen on a free port of 127.0.0.1 and answer requests in a child:
        !! /len (Content-Length), /chunk (chunked), /events (two events slowly).
        integer, intent(out) :: port, pid
        type(sockaddr_in_t) :: a
        integer(c_int) :: fd, n, rc
        fd = c_socket(2_c_int, 1_c_int, 0_c_int)
        a%family = 2_c_int16_t
        a%addr = c_htonl(int(z'7F000001', c_int32_t))
        rc = c_bind(fd, a, int(c_sizeof(a), c_int))
        rc = c_listen(fd, 8_c_int)
        n = int(c_sizeof(a), c_int)
        rc = c_getsockname(fd, a, n)
        port = iand(int(c_htons(a%port)), 65535)
        pid = int(c_fork())
        if (pid /= 0) then
            rc = c_close(fd)
            return
        end if
        call serve(fd)
        call c_exit(0_c_int)
    end subroutine serve_in_child

    subroutine serve(fd)
        integer(c_int), intent(in) :: fd
        integer(c_int) :: cfd
        character(len=4096) :: buf
        character(:), allocatable :: req
        integer(c_long) :: k
        integer :: i
        do i = 1, 8
            cfd = c_accept(fd, c_null_ptr, c_null_ptr)
            if (cfd < 0) return
            req = ''
            do while (index(req, CRLF // CRLF) == 0)
                k = c_recv(cfd, buf, int(len(buf), c_size_t), 0_c_int)
                if (k <= 0) exit
                req = req // buf(1:k)
            end do
            if (index(req, 'GET /len ') == 1) then
                call put(cfd, 'HTTP/1.1 200 OK' // CRLF // 'Content-Length: 5' // CRLF // CRLF // 'hello')
            else if (index(req, 'POST /chunk ') == 1) then
                call put(cfd, 'HTTP/1.1 200 OK' // CRLF // 'Transfer-Encoding: chunked' // CRLF // CRLF // '3' // CRLF)
                k = c_usleep(30000_c_int)
                call put(cfd, 'abc' // CRLF // '4' // CRLF // body_of(req) // CRLF // '0' // CRLF // CRLF)
            else if (index(req, 'GET /events ') == 1) then
                call put(cfd, 'HTTP/1.1 200 OK' // CRLF // 'Content-Type: text/event-stream' // CRLF // CRLF // &
                    ': hello' // achar(10) // achar(10) // 'data: one' // achar(10) // achar(10))
                k = c_usleep(50000_c_int)
                call put(cfd, 'data: two' // achar(10) // achar(10))
                k = c_usleep(50000_c_int)
            else
                call put(cfd, 'HTTP/1.1 404 Not Found' // CRLF // 'Content-Length: 0' // CRLF // CRLF)
            end if
            k = c_close(cfd)
        end do
    end subroutine serve

    function body_of(req) result(b)
        character(*), intent(in) :: req
        character(:), allocatable :: b
        b = req(index(req, CRLF // CRLF) + 4:)
    end function body_of

    subroutine put(fd, text)
        integer(c_int), intent(in) :: fd
        character(*), intent(in) :: text
        integer(c_long) :: k
        k = c_send(fd, text, int(len(text), c_size_t), 0_c_int)
    end subroutine put

    subroutine stop_child(pid)
        integer, intent(in) :: pid
        integer(c_int) :: rc, st
        rc = c_kill(int(pid, c_int), 9_c_int)
        rc = c_waitpid(int(pid, c_int), st, 0_c_int)
    end subroutine stop_child

end module test_net_server

program test_net
    !! The network service: owned requests and streams through the runtime
    !! (a transport the test controls), and the socket transport against a
    !! server in a child process.
    use iso_c_binding, only: c_null_funptr, c_int, c_funloc
    use test_net_wake, only: wakes, count_wake
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_net, only: net_use, net_resolve
    use fortui_net_posix, only: posix_transport
    use test_net_fake
    use test_net_server
    implicit none
    integer :: fails = 0, stat, port, pid, i, n
    type(net_request_t) :: req, req2
    type(net_stream_t) :: ev
    type(fake_transport_t) :: fake
    character(:), allocatable :: data, got
    interface
        integer(c_int) function usleep(us) bind(C, name='usleep')
            import :: c_int
            integer(c_int), value :: us
        end function usleep
    end interface

    call ui_init(headless_backend_t(), 300, 200, 'net', stat=stat)
    call net_fetch(req, 'http://example.org/')
    call check(req%status == NET_UNSUPPORTED .and. len(req%message) > 0, 'no transport: unsupported')
    call check(ui_url_param('site') == '', 'no address parameters on a native host')

    call net_use(fake)
    call net_fetch(req, '/api/op?from=3', body='op line')
    call check(req%status == NET_PENDING, 'a started request is pending')
    call check(.not. net_poll(req), 'not finished while the host works')
    call set_finish()
    call check(net_poll(req) .and. req%status == NET_DONE .and. req%code == 200 .and. &
        req%body == 'echo op line', 'finished once with code and body')
    call check(.not. net_poll(req), 'a finished request is reported once')

    call net_fetch(req, '/a')
    call net_fetch(req2, '/b')
    call net_cancel(req)
    call check(req%status == NET_CANCELLED, 'cancel marks the request')
    call net_fetch(req, 'http://refuse/')
    call check(req%status == NET_UNSUPPORTED, 'a refused URL is unsupported')

    call net_set_base('http://127.0.0.1:4190/')
    call check(net_resolve('/api/log') == 'http://127.0.0.1:4190/api/log' .and. &
        net_resolve('x') == 'http://127.0.0.1:4190/x' .and. net_resolve('http://o/p') == 'http://o/p', &
        'relative URLs resolve against the base')

    call net_stream_open(ev, '/api/events')
    call set_messages(2)
    n = 0
    do while (net_stream_next(ev, data))
        n = n + 1
    end do
    call check(n == 2 .and. data == '' .and. ev%status == NET_OPEN, 'stream messages until none is left')
    call net_stream_close(ev)
    call check(ev%status == NET_CANCELLED, 'a closed stream is cancelled')

    ! The socket transport against a real server.
    call serve_in_child(port, pid)
    call net_use(posix_transport(c_null_funptr))
    call net_set_base('http://127.0.0.1:' // itoa(port))
    call net_fetch(req, '/len')
    call wait_for(req)
    call check(req%status == NET_DONE .and. req%code == 200 .and. req%body == 'hello', &
        'socket: Content-Length answer')
    call net_fetch(req, '/chunk', body='wxyz')
    call wait_for(req)
    call check(req%status == NET_DONE .and. req%body == 'abcwxyz', 'socket: chunked answer to a POST')
    call net_fetch(req, '/missing')
    call wait_for(req)
    call check(req%status == NET_DONE .and. req%code == 404, 'socket: an error status is an answer')
    call net_stream_open(ev, '/events')
    got = ''
    do i = 1, 400
        do while (net_stream_next(ev, data))
            got = got // data // ';'
        end do
        if (got == 'one;two;') exit
        stat = usleep(5000_c_int)
    end do
    call check(got == 'one;two;', 'socket: event stream messages, got "' // got // '"')
    call net_stream_close(ev)
    ! With a waker the host is woken when the answer can be read, without
    ! anybody looking at the request in the meantime.
    call net_use(posix_transport(c_funloc(count_wake)))
    wakes = 0
    call net_fetch(req, '/len')
    do i = 1, 200
        if (wakes > 0) exit
        stat = usleep(2000_c_int)
    end do
    call check(wakes > 0, 'socket: the helper thread wakes the host')
    call wait_for(req)
    call check(req%status == NET_DONE .and. req%body == 'hello', 'socket: answer after the wake-ups')
    call stop_child(pid)
    call net_fetch(req, 'http://127.0.0.1:1/')
    call wait_for(req)
    call check(req%status == NET_FAILED .and. len(req%message) > 0, 'socket: refused connection fails')
    call net_fetch(req, 'https://example.org/')
    call check(req%status == NET_UNSUPPORTED, 'socket: https is refused without TLS')

    if (fails > 0) error stop 1
    print '(a)', 'test_net: all passed'

contains

    subroutine wait_for(r)
        type(net_request_t), intent(inout) :: r
        integer :: k
        do k = 1, 1000
            if (net_poll(r)) return
            if (r%status /= NET_PENDING) return
            stat = usleep(2000_c_int)
        end do
    end subroutine wait_for

    subroutine set_finish()
        !! Reach the installed copy of the fake transport through a fresh one.
        type(fake_transport_t) :: f
        f = fake
        f%finish = .true.
        f%last_id = req%id
        f%last_body = 'op line'
        call net_use(f)
    end subroutine set_finish

    subroutine set_messages(k)
        integer, intent(in) :: k
        type(fake_transport_t) :: f
        f%messages = k
        f%last_id = ev%id
        call net_use(f)
    end subroutine set_messages

    function itoa(k) result(t)
        integer, intent(in) :: k
        character(:), allocatable :: t
        character(len=12) :: b
        write (b, '(i0)') k
        t = trim(b)
    end function itoa

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print '(a)', 'FAIL ' // what
            fails = fails + 1
        end if
    end subroutine check

end program test_net
