module fortui_net_posix
    !! Network transport for native hosts: plain HTTP over sockets that never
    !! block the frame. Each request advances a little whenever the application
    !! looks at it. A helper thread waits on the sockets and wakes the host when
    !! one of them is ready, so nothing polls on a timer where the host has a
    !! waker; elsewhere the runtime looks again every few hundredths of a second.
    !! Name lookup still waits. HTTPS needs TLS, which this transport lacks: such
    !! URLs are refused.
    use iso_c_binding, only: c_int, c_long, c_char, c_null_char, c_funptr, c_associated
    use fortui_net_transport
    use fortui_http
    implicit none
    private

    integer, parameter :: FREE = 0, CONNECTING = 1, SENDING = 2, RECEIVING = 3, DONE = 4, &
        FAILED = 5, WAITING = 6
    ! Delay before a closed event stream connects again, as browsers do.
    double precision, parameter :: RETRY_SECONDS = 2d0

    type :: conn_t
        integer :: id = 0, fd = -1, state = FREE, sent = 0
        logical :: stream = .false., opened = .false.
        character(:), allocatable :: url, request, message
        type(http_reader_t) :: r
        type(sse_reader_t) :: sse
        double precision :: retry_at = 0d0
    end type conn_t

    type, extends(net_transport_t), public :: posix_transport_t
        type(conn_t), allocatable :: c(:)
        logical :: watching = .false.
    contains
        procedure :: start => posix_start
        procedure :: take => posix_take
        procedure :: next_message => posix_next
        procedure :: cancel => posix_cancel
        procedure :: wakes => posix_wakes
    end type posix_transport_t

    public :: posix_transport

    interface
        integer(c_int) function c_begin(host, port) bind(C, name="fortui_net_begin")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: host(*)
            integer(c_int), value :: port
        end function c_begin
        integer(c_int) function c_connected(fd) bind(C, name="fortui_net_connected")
            import :: c_int
            integer(c_int), value :: fd
        end function c_connected
        integer(c_long) function c_send_now(fd, buf, n) bind(C, name="fortui_net_send_now")
            import :: c_int, c_long, c_char
            integer(c_int), value :: fd
            character(kind=c_char), intent(in) :: buf(*)
            integer(c_long), value :: n
        end function c_send_now
        integer(c_long) function c_recv_now(fd, buf, n) bind(C, name="fortui_net_recv_now")
            import :: c_int, c_long, c_char
            integer(c_int), value :: fd
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_long), value :: n
        end function c_recv_now
        subroutine c_close(fd) bind(C, name="fortui_net_close")
            import :: c_int
            integer(c_int), value :: fd
        end subroutine c_close
        integer(c_int) function c_watch_start(waker) bind(C, name="fortui_net_watch_start")
            import :: c_int, c_funptr
            type(c_funptr), value :: waker
        end function c_watch_start
        subroutine c_watch_set(fds, writing, n) bind(C, name="fortui_net_watch_set")
            import :: c_int
            integer(c_int), intent(in) :: fds(*), writing(*)
            integer(c_int), value :: n
        end subroutine c_watch_set
    end interface

contains

    function posix_transport(waker) result(t)
        !! A transport that wakes the host through `waker` (a backend's waker,
        !! possibly null) when sockets are ready.
        type(c_funptr), intent(in) :: waker
        type(posix_transport_t) :: t
        allocate (t%c(0))
        t%watching = .false.
        if (c_associated(waker)) t%watching = c_watch_start(waker) == 0
    end function posix_transport

    logical function posix_wakes(self)
        !! A stream waiting to reconnect has no socket to wait on: the runtime
        !! then looks on a timer.
        class(posix_transport_t), intent(in) :: self
        posix_wakes = self%watching
        if (posix_wakes) posix_wakes = .not. any(self%c%state == WAITING)
    end function posix_wakes

    double precision function now()
        integer(8) :: count, rate
        call system_clock(count, rate)
        now = dble(count)/dble(rate)
    end function now

    logical function posix_start(self, id, method, url, body, content_type, stream) result(started)
        class(posix_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        character(*), intent(in) :: method, url, body, content_type
        logical, intent(in) :: stream
        type(http_url_t) :: u
        type(conn_t), allocatable :: grown(:)
        integer :: k
        started = .false.
        u = http_parse_url(url)
        if (.not. u%ok) return
        if (u%scheme /= 'http') return
        k = slot(self)
        if (k == 0) then
            allocate (grown(size(self%c) + 4))
            grown(1:size(self%c)) = self%c
            call move_alloc(grown, self%c)
            k = slot(self)
        end if
        self%c(k)%id = id
        self%c(k)%stream = stream
        self%c(k)%opened = .false.
        self%c(k)%url = url
        self%c(k)%request = http_request_text(method, u, body, content_type, stream)
        self%c(k)%message = ''
        call connect(self%c(k))
        call rewatch(self)
        started = .true.
    end function posix_start

    integer function slot(self)
        class(posix_transport_t), intent(in) :: self
        integer :: k
        slot = 0
        do k = 1, size(self%c)
            if (self%c(k)%state == FREE) then
                slot = k
                return
            end if
        end do
    end function slot

    integer function find(self, id)
        class(posix_transport_t), intent(in) :: self
        integer, intent(in) :: id
        integer :: k
        find = 0
        do k = 1, size(self%c)
            if (self%c(k)%state /= FREE .and. self%c(k)%id == id) then
                find = k
                return
            end if
        end do
    end function find

    subroutine connect(c)
        type(conn_t), intent(inout) :: c
        type(http_url_t) :: u
        u = http_parse_url(c%url)
        call http_reader_reset(c%r)
        c%sent = 0
        c%fd = int(c_begin(u%host // c_null_char, int(u%port, c_int)))
        if (c%fd < 0) then
            call fail(c, 'cannot connect to ' // u%host // ':' // itoa(u%port))
        else
            c%state = CONNECTING
        end if
    end subroutine connect

    subroutine fail(c, message)
        !! A request ends here; a stream that was open tries again later.
        type(conn_t), intent(inout) :: c
        character(*), intent(in) :: message
        if (c%fd >= 0) call c_close(int(c%fd, c_int))
        c%fd = -1
        c%message = message
        if (c%stream .and. c%opened) then
            c%state = WAITING
            c%retry_at = now() + RETRY_SECONDS
        else
            c%state = FAILED
        end if
    end subroutine fail

    subroutine advance(c)
        type(conn_t), intent(inout) :: c
        character(len=65536) :: buf
        integer(c_long) :: k
        integer :: rc
        select case (c%state)
        case (WAITING)
            if (now() >= c%retry_at) call connect(c)
            return
        case (CONNECTING)
            rc = int(c_connected(int(c%fd, c_int)))
            if (rc < 0) then
                call fail(c, 'connection refused: ' // c%url)
                return
            end if
            if (rc == 0) return
            c%state = SENDING
        end select
        if (c%state == SENDING) then
            k = c_send_now(int(c%fd, c_int), c%request(c%sent + 1:), int(len(c%request) - c%sent, c_long))
            if (k < 0) then
                call fail(c, 'connection lost: ' // c%url)
                return
            end if
            c%sent = c%sent + int(k)
            if (c%sent < len(c%request)) return
            c%state = RECEIVING
        end if
        if (c%state /= RECEIVING) return
        do
            k = c_recv_now(int(c%fd, c_int), buf, int(len(buf), c_long))
            if (k == -2) exit
            if (k < 0) then
                call fail(c, 'connection lost: ' // c%url)
                return
            end if
            if (k == 0) then
                call http_finish(c%r)
                call c_close(int(c%fd, c_int))
                c%fd = -1
                if (c%stream) then
                    call take_events(c)
                    call fail(c, 'event stream closed: ' // c%url)
                else if (c%r%complete) then
                    c%state = DONE
                else
                    c%state = FAILED
                    c%message = 'incomplete answer from ' // c%url
                end if
                return
            end if
            call http_feed(c%r, buf(1:k))
            if (c%r%failed) then
                call fail(c, 'malformed answer from ' // c%url)
                return
            end if
            if (c%stream) then
                if (c%r%head_done .and. c%r%code /= 200) then
                    call fail(c, 'event stream answered ' // itoa(c%r%code) // ': ' // c%url)
                    return
                end if
                if (c%r%head_done) c%opened = .true.
                call take_events(c)
            else if (c%r%complete) then
                call c_close(int(c%fd, c_int))
                c%fd = -1
                c%state = DONE
                return
            end if
        end do
    end subroutine advance

    subroutine take_events(c)
        type(conn_t), intent(inout) :: c
        if (len(c%r%body) == 0) return
        call sse_feed(c%sse, c%r%body)
        c%r%body = ''
    end subroutine take_events

    subroutine rewatch(self)
        !! Hand the sockets still in progress to the helper thread.
        class(posix_transport_t), intent(inout) :: self
        integer(c_int) :: fds(64), writing(64)
        integer :: k, n
        if (.not. self%watching) return
        n = 0
        do k = 1, size(self%c)
            select case (self%c(k)%state)
            case (CONNECTING, SENDING, RECEIVING)
                if (n == size(fds)) cycle
                n = n + 1
                fds(n) = int(self%c(k)%fd, c_int)
                writing(n) = 0
                if (self%c(k)%state /= RECEIVING) writing(n) = 1
            end select
        end do
        call c_watch_set(fds, writing, int(n, c_int))
    end subroutine rewatch

    subroutine posix_take(self, id, status, code, body, message)
        class(posix_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status, code
        character(:), allocatable, intent(out) :: body, message
        integer :: k
        status = NET_FAILED
        code = 0
        body = ''
        message = 'unknown request'
        k = find(self, id)
        if (k == 0) return
        call advance(self%c(k))
        select case (self%c(k)%state)
        case (DONE)
            status = NET_DONE
            code = self%c(k)%r%code
            body = self%c(k)%r%body
            message = ''
            call release(self%c(k))
        case (FAILED)
            message = self%c(k)%message
            call release(self%c(k))
        case default
            status = NET_PENDING
            message = ''
        end select
        call rewatch(self)
    end subroutine posix_take

    subroutine posix_next(self, id, status, data, got)
        class(posix_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status
        character(:), allocatable, intent(out) :: data
        logical, intent(out) :: got
        integer :: k
        got = .false.
        data = ''
        status = NET_FAILED
        k = find(self, id)
        if (k == 0) return
        if (.not. sse_next(self%c(k)%sse, data)) then
            call advance(self%c(k))
            got = sse_next(self%c(k)%sse, data)
        else
            got = .true.
        end if
        select case (self%c(k)%state)
        case (FAILED)
            status = NET_FAILED
            data = self%c(k)%message
            got = .false.
            call release(self%c(k))
        case (RECEIVING)
            status = NET_PENDING
            if (self%c(k)%opened) status = NET_OPEN
        case default
            status = NET_PENDING
        end select
        call rewatch(self)
    end subroutine posix_next

    subroutine posix_cancel(self, id)
        class(posix_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer :: k
        k = find(self, id)
        if (k > 0) call release(self%c(k))
        call rewatch(self)
    end subroutine posix_cancel

    subroutine release(c)
        type(conn_t), intent(inout) :: c
        if (c%fd >= 0) call c_close(int(c%fd, c_int))
        c%fd = -1
        c%state = FREE
        c%id = 0
        c%sse%pending = ''
    end subroutine release

    function itoa(n) result(s)
        integer, intent(in) :: n
        character(:), allocatable :: s
        character(len=12) :: b
        write (b, '(i0)') n
        s = trim(b)
    end function itoa

end module fortui_net_posix
