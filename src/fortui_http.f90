module fortui_http
    !! HTTP/1.1 framing for the network service on hosts that speak to sockets
    !! themselves: URL parts, the request text, a response read as it arrives
    !! (Content-Length, chunked, or until the connection closes) and server-sent
    !! event messages. Bytes travel in character strings unchanged.
    implicit none
    private

    character(len=2), parameter :: CRLF = achar(13) // achar(10)

    type, public :: http_url_t
        character(:), allocatable :: scheme, host, target
        integer :: port = 80
        logical :: ok = .false.
    end type http_url_t

    type, public :: http_reader_t
        !! Bytes not yet consumed, then the decoded body as it grows.
        character(:), allocatable :: pending, body
        logical :: head_done = .false., chunked = .false.
        logical :: complete = .false., failed = .false.
        integer :: code = 0, length = -1
        ! Bytes left in the current chunk; -1 a size line is due, -2 the CRLF
        ! after a chunk's data.
        integer :: chunk_left = -1
    end type http_reader_t

    type, public :: sse_reader_t
        character(:), allocatable :: pending
    end type sse_reader_t

    public :: http_parse_url, http_request_text, http_reader_reset, http_feed, http_finish
    public :: sse_feed, sse_next

contains

    function http_parse_url(url) result(u)
        !! scheme://host[:port]/path?query. The target is path and query, "/" if empty.
        character(*), intent(in) :: url
        type(http_url_t) :: u
        integer :: s, slash, colon, ios
        character(:), allocatable :: hostport
        u%ok = .false.
        s = index(url, '://')
        if (s < 2) return
        u%scheme = lower(url(1:s - 1))
        if (u%scheme == 'https') then
            u%port = 443
        else if (u%scheme == 'http') then
            u%port = 80
        else
            return
        end if
        slash = index(url(s + 3:), '/')
        if (slash == 0) then
            hostport = url(s + 3:)
            u%target = '/'
        else
            hostport = url(s + 3:s + 1 + slash)
            u%target = url(s + 2 + slash:)
        end if
        if (len(hostport) == 0) return
        colon = index(hostport, ':', back=.true.)
        if (colon > 0 .and. index(hostport, ']') < colon) then
            read (hostport(colon + 1:), *, iostat=ios) u%port
            if (ios /= 0 .or. u%port <= 0 .or. u%port > 65535) return
            u%host = hostport(1:colon - 1)
        else
            u%host = hostport
        end if
        if (len(u%host) > 2) then
            if (u%host(1:1) == '[') u%host = u%host(2:len(u%host) - 1)
        end if
        u%ok = len(u%host) > 0
    end function http_parse_url

    function http_request_text(method, u, body, content_type, stream) result(req)
        character(*), intent(in) :: method, body, content_type
        type(http_url_t), intent(in) :: u
        logical, intent(in) :: stream
        character(:), allocatable :: req, host
        host = u%host
        if (index(host, ':') > 0) host = '[' // host // ']'
        if ((u%scheme == 'http' .and. u%port /= 80) .or. (u%scheme == 'https' .and. u%port /= 443)) &
            host = host // ':' // itoa(u%port)
        req = method // ' ' // u%target // ' HTTP/1.1' // CRLF // 'Host: ' // host // CRLF // &
            'Connection: close' // CRLF
        if (stream) then
            req = req // 'Accept: text/event-stream' // CRLF // 'Cache-Control: no-cache' // CRLF
        else
            req = req // 'Accept: */*' // CRLF
        end if
        if (method /= 'GET' .and. method /= 'HEAD') then
            req = req // 'Content-Type: ' // content_type // CRLF // 'Content-Length: ' // &
                itoa(len(body)) // CRLF
        end if
        req = req // CRLF // body
    end function http_request_text

    subroutine http_reader_reset(r)
        type(http_reader_t), intent(out) :: r
        r%pending = ''
        r%body = ''
    end subroutine http_reader_reset

    subroutine http_feed(r, bytes)
        !! Bytes as they arrive.
        type(http_reader_t), intent(inout) :: r
        character(*), intent(in) :: bytes
        integer :: e, size, take, ios, semi
        if (r%complete .or. r%failed) return
        r%pending = r%pending // bytes
        if (.not. r%head_done) then
            e = index(r%pending, CRLF // CRLF)
            if (e == 0) then
                if (len(r%pending) > 65536) r%failed = .true.
                return
            end if
            call read_head(r, r%pending(1:e + 1))
            r%pending = r%pending(e + 4:)
            if (r%failed) return
        end if
        if (.not. r%chunked) then
            r%body = r%body // r%pending
            r%pending = ''
            if (r%length >= 0 .and. len(r%body) >= r%length) then
                r%body = r%body(1:r%length)
                r%complete = .true.
            end if
            return
        end if
        do
            if (r%chunk_left == -1) then
                e = index(r%pending, CRLF)
                if (e == 0) return
                semi = index(r%pending(1:e - 1), ';')
                if (semi == 0) semi = e
                read (r%pending(1:semi - 1), '(z16)', iostat=ios) size
                if (ios /= 0 .or. semi == 1) then
                    r%failed = .true.
                    return
                end if
                r%pending = r%pending(e + 2:)
                if (size == 0) then
                    r%complete = .true.
                    return
                end if
                r%chunk_left = size
            else if (r%chunk_left == -2) then
                if (len(r%pending) < 2) return
                if (r%pending(1:2) /= CRLF) then
                    r%failed = .true.
                    return
                end if
                r%pending = r%pending(3:)
                r%chunk_left = -1
            else
                take = min(r%chunk_left, len(r%pending))
                if (take == 0) return
                r%body = r%body // r%pending(1:take)
                r%pending = r%pending(take + 1:)
                r%chunk_left = r%chunk_left - take
                if (r%chunk_left == 0) r%chunk_left = -2
            end if
        end do
    end subroutine http_feed

    subroutine http_finish(r)
        !! The connection closed: a body without length ends here; anything else
        !! unfinished failed.
        type(http_reader_t), intent(inout) :: r
        if (r%complete .or. r%failed) return
        if (r%head_done .and. .not. r%chunked .and. r%length < 0) then
            r%complete = .true.
        else
            r%failed = .true.
        end if
    end subroutine http_finish

    subroutine read_head(r, head)
        type(http_reader_t), intent(inout) :: r
        character(*), intent(in) :: head
        integer :: s, e, colon, ios
        character(:), allocatable :: line, name, value
        e = index(head, CRLF)
        line = head(1:e - 1)
        if (len(line) < 12 .or. line(1:5) /= 'HTTP/') then
            r%failed = .true.
            return
        end if
        read (line(10:12), *, iostat=ios) r%code
        if (ios /= 0) then
            r%failed = .true.
            return
        end if
        s = e + 2
        do while (s < len(head))
            e = index(head(s:), CRLF)
            if (e == 0) exit
            line = head(s:s + e - 2)
            s = s + e + 1
            colon = index(line, ':')
            if (colon == 0) cycle
            name = lower(trim(line(1:colon - 1)))
            value = trim(adjustl(line(colon + 1:)))
            if (name == 'content-length') then
                read (value, *, iostat=ios) r%length
                if (ios /= 0) r%length = -1
            else if (name == 'transfer-encoding') then
                r%chunked = index(lower(value), 'chunked') > 0
            end if
        end do
        r%head_done = .true.
        if (r%chunked) r%length = -1
    end subroutine read_head

    subroutine sse_feed(s, text)
        !! Decoded event-stream text as it arrives.
        type(sse_reader_t), intent(inout) :: s
        character(*), intent(in) :: text
        if (.not. allocated(s%pending)) s%pending = ''
        s%pending = s%pending // text
    end subroutine sse_feed

    logical function sse_next(s, data) result(got)
        !! The data of the next complete event, its data lines joined by line
        !! feeds. Comments, keep-alives and events without data are skipped.
        type(sse_reader_t), intent(inout) :: s
        character(:), allocatable, intent(out) :: data
        character(:), allocatable :: block, line
        integer :: e, k, cut
        logical :: any_data
        got = .false.
        data = ''
        if (.not. allocated(s%pending)) return
        do
            call normalise(s%pending)
            e = index(s%pending, achar(10) // achar(10))
            if (e == 0) return
            block = s%pending(1:e)
            s%pending = s%pending(e + 2:)
            any_data = .false.
            do while (len(block) > 0)
                k = index(block, achar(10))
                line = block(1:k - 1)
                block = block(k + 1:)
                if (len(line) < 4) cycle
                if (line(1:4) /= 'data') cycle
                if (len(line) == 4) then
                    cut = 5
                else if (line(5:5) /= ':') then
                    cycle
                else if (len(line) >= 6 .and. line(6:6) == ' ') then
                    cut = 7
                else
                    cut = 6
                end if
                if (any_data) data = data // achar(10)
                data = data // line(cut:)
                any_data = .true.
            end do
            if (any_data) then
                got = .true.
                return
            end if
        end do
    end function sse_next

    subroutine normalise(t)
        !! CRLF and lone CR line ends to LF.
        character(:), allocatable, intent(inout) :: t
        integer :: k
        do
            k = index(t, achar(13))
            if (k == 0) return
            if (k < len(t)) then
                if (t(k + 1:k + 1) == achar(10)) then
                    t = t(1:k - 1) // t(k + 1:)
                    cycle
                end if
            else
                ! A CR at the very end may still be followed by its LF.
                return
            end if
            t(k:k) = achar(10)
        end do
    end subroutine normalise

    function lower(s) result(t)
        character(*), intent(in) :: s
        character(len(s)) :: t
        integer :: i, c
        t = s
        do i = 1, len(s)
            c = iachar(s(i:i))
            if (c >= 65 .and. c <= 90) t(i:i) = achar(c + 32)
        end do
    end function lower

    function itoa(n) result(s)
        integer, intent(in) :: n
        character(:), allocatable :: s
        character(len=12) :: b
        write (b, '(i0)') n
        s = trim(b)
    end function itoa

end module fortui_http
