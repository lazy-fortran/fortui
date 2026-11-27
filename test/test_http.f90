program test_http
    !! HTTP framing of the network service against hand-written answers fed in
    !! pieces of every size: Content-Length, chunked, until close, failures, and
    !! server-sent events.
    use fortui_http
    implicit none
    character(len=2), parameter :: CRLF = achar(13) // achar(10)
    character(len=1), parameter :: LF = achar(10)
    integer :: fails = 0, step
    type(http_url_t) :: u
    type(http_reader_t) :: r
    type(sse_reader_t) :: s
    character(:), allocatable :: answer, data, req

    u = http_parse_url('http://example.org:8080/api/log?from=3')
    call check(u%ok .and. u%host == 'example.org' .and. u%port == 8080 .and. &
        u%target == '/api/log?from=3', 'URL with port and query')
    u = http_parse_url('https://example.org')
    call check(u%ok .and. u%scheme == 'https' .and. u%port == 443 .and. u%target == '/', 'https default port')
    u = http_parse_url('http://[::1]:4190/x')
    call check(u%ok .and. u%host == '::1' .and. u%port == 4190, 'IPv6 literal')
    u = http_parse_url('/relative')
    call check(.not. u%ok, 'a relative URL is refused')
    u = http_parse_url('ftp://a/b')
    call check(.not. u%ok, 'a foreign scheme is refused')

    u = http_parse_url('http://h:81/p')
    req = http_request_text('POST', u, 'a=1', 'text/plain', .false.)
    call check(index(req, 'POST /p HTTP/1.1' // CRLF) == 1 .and. index(req, 'Host: h:81' // CRLF) > 0 .and. &
        index(req, 'Content-Length: 3' // CRLF) > 0 .and. req(len(req) - 6:) == CRLF // CRLF // 'a=1', &
        'request text')

    answer = 'HTTP/1.1 200 OK' // CRLF // 'Content-Length: 11' // CRLF // CRLF // 'hello world' // 'extra'
    do step = 1, len(answer)
        call feed_in_steps(answer, step)
        call check(r%complete .and. r%code == 200 .and. r%body == 'hello world', &
            'Content-Length answer in pieces of ' // itoa(step))
        if (fails > 0) exit
    end do

    answer = 'HTTP/1.1 201 Created' // CRLF // 'transfer-encoding: Chunked' // CRLF // CRLF // &
        '5;ext=1' // CRLF // 'hello' // CRLF // '6' // CRLF // ' world' // CRLF // '0' // CRLF // CRLF
    do step = 1, len(answer)
        call feed_in_steps(answer, step)
        call check(r%complete .and. r%code == 201 .and. r%body == 'hello world', &
            'chunked answer in pieces of ' // itoa(step))
        if (fails > 0) exit
    end do

    answer = 'HTTP/1.0 200 OK' // CRLF // CRLF // 'until close'
    call feed_in_steps(answer, 3)
    call check(.not. r%complete, 'a body without length waits for the close')
    call http_finish(r)
    call check(r%complete .and. r%body == 'until close', 'the close ends a body without length')

    call feed_in_steps('HTTP/1.1 200 OK' // CRLF // 'Content-Length: 10' // CRLF // CRLF // 'short', 4)
    call http_finish(r)
    call check(r%failed, 'a body shorter than its length fails')
    call feed_in_steps('garbage' // CRLF // CRLF, 5)
    call check(r%failed, 'a malformed status line fails')
    call feed_in_steps('HTTP/1.1 200 OK' // CRLF // 'Transfer-Encoding: chunked' // CRLF // CRLF // &
        'zz' // CRLF, 4)
    call check(r%failed, 'a malformed chunk size fails')

    answer = ': keep-alive' // LF // LF // 'data: first' // CRLF // CRLF // 'event: x' // LF // &
        'data:two' // LF // 'data: lines' // LF // LF // 'id: 7' // LF // LF // 'data' // LF // LF
    do step = 1, len(answer)
        s%pending = ''
        call sse_steps(answer, step)
        if (fails > 0) exit
    end do

    if (fails > 0) error stop 1
    print '(a)', 'test_http: all passed'

contains

    subroutine feed_in_steps(text, step)
        character(*), intent(in) :: text
        integer, intent(in) :: step
        integer :: i
        call http_reader_reset(r)
        i = 1
        do while (i <= len(text))
            call http_feed(r, text(i:min(len(text), i + step - 1)))
            i = i + step
        end do
    end subroutine feed_in_steps

    subroutine sse_steps(text, step)
        character(*), intent(in) :: text
        integer, intent(in) :: step
        integer :: i, n
        character(len=16) :: got(4)
        n = 0
        i = 1
        do while (i <= len(text))
            call sse_feed(s, text(i:min(len(text), i + step - 1)))
            do while (sse_next(s, data))
                n = n + 1
                if (n <= 4) got(n) = data
            end do
            i = i + step
        end do
        call check(n == 3 .and. got(1) == 'first' .and. got(2) == 'two' // LF // 'lines' .and. &
            got(3) == '', 'event stream in pieces of ' // itoa(step))
    end subroutine sse_steps

    function itoa(n) result(t)
        integer, intent(in) :: n
        character(:), allocatable :: t
        character(len=12) :: b
        write (b, '(i0)') n
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

end program test_http
