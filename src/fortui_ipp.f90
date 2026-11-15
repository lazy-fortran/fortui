module fortui_ipp
    !! IPP (RFC 8010/8011) messages and their transport over HTTP/1.1, in Fortran:
    !! a request is built from attributes (strings, integers, ranges,
    !! resolutions and collections), encoded, posted to a printer or to the
    !! local CUPS server (a host starting with "/" is a local socket), and the
    !! response decoded the same way. Only plain HTTP: ipps and https fail.
    use iso_c_binding, only: c_int, c_long, c_char, c_null_char, c_loc, c_ptr
    use iso_fortran_env, only: int8
    implicit none
    private

    ! Delimiter tags (groups) and value tags.
    integer, parameter, public :: IPP_OPERATION = 1, IPP_JOB = 2, IPP_END = 3, &
        IPP_PRINTER = 4
    integer, parameter, public :: IPP_INTEGER = int(z'21'), IPP_BOOLEAN = int(z'22'), &
        IPP_ENUM = int(z'23'), IPP_DATE = int(z'31'), IPP_RESOLUTION = int(z'32'), &
        IPP_RANGE = int(z'33'), IPP_BEGIN_COLLECTION = int(z'34'), &
        IPP_TEXT_LANG = int(z'35'), IPP_NAME_LANG = int(z'36'), &
        IPP_END_COLLECTION = int(z'37'), IPP_TEXT = int(z'41'), IPP_NAME = int(z'42'), &
        IPP_KEYWORD = int(z'44'), IPP_URI = int(z'45'), IPP_CHARSET = int(z'47'), &
        IPP_LANGUAGE = int(z'48'), IPP_MIME = int(z'49'), IPP_MEMBER_NAME = int(z'4A')
    ! Operations.
    integer, parameter, public :: IPP_PRINT_JOB = int(z'0002'), &
        IPP_CANCEL_JOB = int(z'0008'), IPP_GET_PRINTER_ATTRIBUTES = int(z'000B'), &
        IPP_CUPS_GET_DEFAULT = int(z'4001'), IPP_CUPS_GET_PRINTERS = int(z'4002')

    type, public :: ipp_text_t
        character(len=:), allocatable :: s
    end type ipp_text_t

    type, public :: ipp_attr_t
        !! One attribute with its values. Per value k: tags(k), ints(:, k)
        !! (integer, enum or boolean in 1; range lower and upper in 1:2;
        !! resolution x, y and units in 1:3), texts(k) for strings, and for a
        !! collection its members, members(first(k):last(k)).
        integer :: group = 0
        ! Which group of the message (1, 2, ...): a response lists each printer
        ! or job in a group of its own.
        integer :: set = 0
        character(len=:), allocatable :: name
        integer :: n = 0
        integer, allocatable :: tags(:), ints(:, :), first(:), last(:)
        type(ipp_text_t), allocatable :: texts(:)
        type(ipp_attr_t), allocatable :: members(:)
    end type ipp_attr_t

    type, public :: ipp_msg_t
        !! Operation (request) or status code (response), request id, attributes.
        integer :: code = 0, request_id = 1
        integer :: n = 0
        type(ipp_attr_t), allocatable :: attrs(:)
    end type ipp_msg_t

    public :: ipp_request, ipp_attr, ipp_add, ipp_value_str, ipp_value_int, &
        ipp_value_col, ipp_encode, ipp_decode, ipp_find, ipp_str, ipp_int, &
        ipp_post, ipp_get, ipp_split_uri, ipp_user, ipp_members

    interface
        integer(c_int) function net_open(host, port, timeout_ms) bind(C, name="fortui_net_open")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: host(*)
            integer(c_int), value :: port, timeout_ms
        end function net_open
        integer(c_int) function net_send(fd, buf, n, timeout_ms) bind(C, name="fortui_net_send")
            import :: c_int, c_long, c_ptr
            integer(c_int), value :: fd, timeout_ms
            type(c_ptr), value :: buf
            integer(c_long), value :: n
        end function net_send
        integer(c_long) function net_recv(fd, buf, n, timeout_ms) bind(C, name="fortui_net_recv")
            import :: c_int, c_long, c_ptr
            integer(c_int), value :: fd, timeout_ms
            type(c_ptr), value :: buf
            integer(c_long), value :: n
        end function net_recv
        subroutine net_close(fd) bind(C, name="fortui_net_close")
            import :: c_int
            integer(c_int), value :: fd
        end subroutine net_close
        integer(c_int) function net_user(buf, n) bind(C, name="fortui_net_user")
            import :: c_int, c_char
            character(kind=c_char) :: buf(*)
            integer(c_int), value :: n
        end function net_user
    end interface

contains

    ! --- building ---------------------------------------------------------------

    subroutine ipp_request(msg, op, printer_uri)
        !! A new request with the attributes every request starts with.
        type(ipp_msg_t), intent(out) :: msg
        integer, intent(in) :: op
        character(*), intent(in), optional :: printer_uri
        msg%code = op
        msg%request_id = 1
        allocate(msg%attrs(16))
        call ipp_add(msg, ipp_attr(IPP_OPERATION, "attributes-charset", &
            ipp_value_str(IPP_CHARSET, "utf-8")))
        call ipp_add(msg, ipp_attr(IPP_OPERATION, "attributes-natural-language", &
            ipp_value_str(IPP_LANGUAGE, "en")))
        if (present(printer_uri)) call ipp_add(msg, ipp_attr(IPP_OPERATION, "printer-uri", &
            ipp_value_str(IPP_URI, printer_uri)))
    end subroutine ipp_request

    subroutine ipp_add(msg, attr)
        type(ipp_msg_t), intent(inout) :: msg
        type(ipp_attr_t), intent(in) :: attr
        type(ipp_attr_t), allocatable :: bigger(:)
        if (.not. allocated(msg%attrs)) allocate(msg%attrs(16))
        if (msg%n == size(msg%attrs)) then
            allocate(bigger(2 * size(msg%attrs)))
            bigger(1:msg%n) = msg%attrs(1:msg%n)
            call move_alloc(bigger, msg%attrs)
        end if
        msg%n = msg%n + 1
        msg%attrs(msg%n) = attr
    end subroutine ipp_add

    function ipp_attr(group, name, v1, v2, v3, v4, v5, v6, v7, v8) result(a)
        !! An attribute (or, with group 0, a collection member) from up to eight
        !! values made by ipp_value_str, ipp_value_int and ipp_value_col.
        integer, intent(in) :: group
        character(*), intent(in) :: name
        type(ipp_attr_t), intent(in) :: v1
        type(ipp_attr_t), intent(in), optional :: v2, v3, v4, v5, v6, v7, v8
        type(ipp_attr_t) :: a
        a = v1
        a%group = group
        a%name = name
        if (present(v2)) call append(a, v2)
        if (present(v3)) call append(a, v3)
        if (present(v4)) call append(a, v4)
        if (present(v5)) call append(a, v5)
        if (present(v6)) call append(a, v6)
        if (present(v7)) call append(a, v7)
        if (present(v8)) call append(a, v8)
    end function ipp_attr

    function ipp_value_str(tag, s) result(v)
        integer, intent(in) :: tag
        character(*), intent(in) :: s
        type(ipp_attr_t) :: v
        call empty(v)
        call push(v, tag)
        v%texts(1)%s = s
    end function ipp_value_str

    function ipp_value_int(tag, i, j, k) result(v)
        !! Integer, enum or boolean (i); range (i, j); resolution (i, j, units k).
        integer, intent(in) :: tag, i
        integer, intent(in), optional :: j, k
        type(ipp_attr_t) :: v
        call empty(v)
        call push(v, tag)
        v%ints(1, 1) = i
        if (present(j)) v%ints(2, 1) = j
        if (present(k)) v%ints(3, 1) = k
    end function ipp_value_int

    function ipp_value_col(m1, m2, m3, m4, m5, m6, m7, m8) result(v)
        !! A collection value of up to eight members made by ipp_attr(0, ...).
        type(ipp_attr_t), intent(in) :: m1
        type(ipp_attr_t), intent(in), optional :: m2, m3, m4, m5, m6, m7, m8
        type(ipp_attr_t) :: v
        type(ipp_attr_t) :: list(8)
        integer :: n
        n = 1
        list(1) = m1
        if (present(m2)) call take(m2)
        if (present(m3)) call take(m3)
        if (present(m4)) call take(m4)
        if (present(m5)) call take(m5)
        if (present(m6)) call take(m6)
        if (present(m7)) call take(m7)
        if (present(m8)) call take(m8)
        call empty(v)
        call push(v, IPP_BEGIN_COLLECTION)
        v%members = list(1:n)
        v%first(1) = 1
        v%last(1) = n
    contains
        subroutine take(m)
            type(ipp_attr_t), intent(in) :: m
            n = n + 1
            list(n) = m
        end subroutine take
    end function ipp_value_col

    subroutine empty(v)
        type(ipp_attr_t), intent(inout) :: v
        v%n = 0
        v%name = ""
        allocate(v%tags(0), v%ints(3, 0), v%first(0), v%last(0), v%texts(0), v%members(0))
    end subroutine empty

    subroutine push(a, tag)
        !! One more value with this tag, zero and empty.
        type(ipp_attr_t), intent(inout) :: a
        integer, intent(in) :: tag
        integer, allocatable :: ints(:, :)
        type(ipp_text_t), allocatable :: texts(:)
        if (.not. allocated(a%tags)) call empty(a)
        a%n = a%n + 1
        a%tags = [a%tags, tag]
        allocate(ints(3, a%n))
        ints(:, 1:a%n - 1) = a%ints(:, 1:a%n - 1)
        ints(:, a%n) = 0
        call move_alloc(ints, a%ints)
        a%first = [a%first, 1]
        a%last = [a%last, 0]
        allocate(texts(a%n))
        texts(1:a%n - 1) = a%texts(1:a%n - 1)
        texts(a%n)%s = ""
        call move_alloc(texts, a%texts)
    end subroutine push

    subroutine append(a, v)
        !! The values of v after those of a.
        type(ipp_attr_t), intent(inout) :: a
        type(ipp_attr_t), intent(in) :: v
        integer :: k, base
        do k = 1, v%n
            call push(a, v%tags(k))
            a%ints(:, a%n) = v%ints(:, k)
            a%texts(a%n)%s = v%texts(k)%s
            base = size(a%members)
            if (v%last(k) >= v%first(k)) then
                a%members = [a%members, v%members(v%first(k):v%last(k))]
                a%first(a%n) = base + 1
                a%last(a%n) = base + v%last(k) - v%first(k) + 1
            end if
        end do
    end subroutine append

    ! --- reading ----------------------------------------------------------------

    pure integer function ipp_find(attrs, name, n) result(k)
        !! Index of the attribute `name` among attrs(1:n) (all when n is absent), or 0.
        type(ipp_attr_t), intent(in) :: attrs(:)
        character(*), intent(in) :: name
        integer, intent(in), optional :: n
        integer :: last
        last = size(attrs)
        if (present(n)) last = n
        do k = 1, last
            if (attrs(k)%name == name) return
        end do
        k = 0
    end function ipp_find

    function ipp_str(a, k) result(s)
        !! String value k ("" when there is none).
        type(ipp_attr_t), intent(in) :: a
        integer, intent(in) :: k
        character(len=:), allocatable :: s
        s = ""
        if (k >= 1 .and. k <= a%n) s = a%texts(k)%s
    end function ipp_str

    integer function ipp_int(a, k, part) result(v)
        !! Integer value k (part 2 and 3: range upper, resolution y and units).
        type(ipp_attr_t), intent(in) :: a
        integer, intent(in) :: k
        integer, intent(in), optional :: part
        v = 0
        if (k < 1 .or. k > a%n) return
        if (present(part)) then
            v = a%ints(part, k)
        else
            v = a%ints(1, k)
        end if
    end function ipp_int

    function ipp_members(a, k) result(m)
        !! The members of collection value k.
        type(ipp_attr_t), intent(in) :: a
        integer, intent(in) :: k
        type(ipp_attr_t), allocatable :: m(:)
        m = a%members(a%first(k):a%last(k))
    end function ipp_members

    ! --- encoding ---------------------------------------------------------------

    subroutine ipp_encode(msg, bytes, n)
        !! The message as RFC 8010 bytes, bytes(1:n).
        type(ipp_msg_t), intent(in) :: msg
        integer(int8), allocatable, intent(out) :: bytes(:)
        integer, intent(out) :: n
        integer :: k, group
        allocate(bytes(4096))
        n = 0
        call put([2, 0])
        call put16(msg%code)
        call put32(msg%request_id)
        group = -1
        do k = 1, msg%n
            if (msg%attrs(k)%group /= group) then
                group = msg%attrs(k)%group
                call put([group])
            end if
            call put_attr(msg%attrs(k), .false.)
        end do
        call put([IPP_END])
    contains
        recursive subroutine put_attr(a, member)
            type(ipp_attr_t), intent(in) :: a
            logical, intent(in) :: member
            integer :: v, m
            if (member) then
                call put([IPP_MEMBER_NAME])
                call put16(0)
                call put_text(a%name)
            end if
            do v = 1, a%n
                call put([a%tags(v)])
                if (v == 1 .and. .not. member) then
                    call put_text(a%name)
                else
                    call put16(0)
                end if
                select case (a%tags(v))
                case (IPP_INTEGER, IPP_ENUM)
                    call put16(4)
                    call put32(a%ints(1, v))
                case (IPP_BOOLEAN)
                    call put16(1)
                    call put([merge(1, 0, a%ints(1, v) /= 0)])
                case (IPP_RANGE)
                    call put16(8)
                    call put32(a%ints(1, v))
                    call put32(a%ints(2, v))
                case (IPP_RESOLUTION)
                    call put16(9)
                    call put32(a%ints(1, v))
                    call put32(a%ints(2, v))
                    call put([a%ints(3, v)])
                case (IPP_BEGIN_COLLECTION)
                    call put16(0)
                    do m = a%first(v), a%last(v)
                        call put_attr(a%members(m), .true.)
                    end do
                    call put([IPP_END_COLLECTION])
                    call put16(0)
                    call put16(0)
                case default
                    call put_text(a%texts(v)%s)
                end select
            end do
        end subroutine put_attr
        subroutine put_text(s)
            character(*), intent(in) :: s
            integer :: i
            call put16(len(s))
            call put([(ichar(s(i:i)), i = 1, len(s))])
        end subroutine put_text
        subroutine put16(v)
            integer, intent(in) :: v
            call put([iand(ishft(v, -8), 255), iand(v, 255)])
        end subroutine put16
        subroutine put32(v)
            integer, intent(in) :: v
            call put([iand(ishft(v, -24), 255), iand(ishft(v, -16), 255), &
                iand(ishft(v, -8), 255), iand(v, 255)])
        end subroutine put32
        subroutine put(b)
            integer, intent(in) :: b(:)
            integer(int8), allocatable :: bigger(:)
            if (n + size(b) > size(bytes)) then
                allocate(bigger(2 * (n + size(b))))
                bigger(1:n) = bytes(1:n)
                call move_alloc(bigger, bytes)
            end if
            bytes(n + 1:n + size(b)) = int(b - 256 * merge(1, 0, b > 127), int8)
            n = n + size(b)
        end subroutine put
    end subroutine ipp_encode

    ! --- decoding ---------------------------------------------------------------

    subroutine ipp_decode(bytes, msg, ok)
        !! A message from its bytes; ok is false for a truncated or malformed one.
        integer(int8), intent(in) :: bytes(:)
        type(ipp_msg_t), intent(out) :: msg
        logical, intent(out) :: ok
        integer :: p, tag, group, set
        type(ipp_attr_t) :: a
        logical :: have

        ok = .false.
        allocate(msg%attrs(16))
        if (size(bytes) < 9) return
        msg%code = u(3) * 256 + u(4)
        msg%request_id = int(u(5) * 16777216_8 + u(6) * 65536 + u(7) * 256 + u(8))
        p = 9
        group = 0
        set = 0
        have = .false.
        do
            if (p > size(bytes)) return
            tag = u(p)
            if (tag == IPP_END) exit
            if (tag < 16) then
                if (have) call ipp_add(msg, a)
                have = .false.
                group = tag
                set = set + 1
                p = p + 1
                cycle
            end if
            if (.not. value(a, have, group)) return
        end do
        if (have) call ipp_add(msg, a)
        ok = .true.
    contains
        integer function u(i)
            integer, intent(in) :: i
            u = iand(int(bytes(i)), 255)
        end function u
        integer function u16(i)
            integer, intent(in) :: i
            u16 = u(i) * 256 + u(i + 1)
        end function u16
        integer function s32(i)
            integer, intent(in) :: i
            integer(8) :: v
            v = u(i) * 16777216_8 + u(i + 1) * 65536 + u(i + 2) * 256 + u(i + 3)
            if (v > 2147483647_8) v = v - 4294967296_8
            s32 = int(v)
        end function s32
        function text(i, n) result(s)
            integer, intent(in) :: i, n
            character(len=n) :: s
            integer :: k
            do k = 1, n
                s(k:k) = achar(u(i + k - 1))
            end do
        end function text
        recursive logical function value(a, have, group) result(good)
            !! One value at p: a new attribute (named) or one more value of a.
            type(ipp_attr_t), intent(inout) :: a
            logical, intent(inout) :: have
            integer, intent(in) :: group
            integer :: tag, nlen, vlen
            good = .false.
            if (p + 3 > size(bytes)) return
            tag = u(p)
            nlen = u16(p + 1)
            if (p + 3 + nlen + 1 > size(bytes)) return
            if (nlen > 0) then
                if (have .and. group /= 0) call ipp_add(msg, a)
                a = ipp_attr_t()
                call empty(a)
                a%group = group
                a%set = set
                a%name = text(p + 3, nlen)
                have = .true.
            else if (.not. have) then
                return
            end if
            vlen = u16(p + 3 + nlen)
            p = p + 5 + nlen
            if (p + vlen - 1 > size(bytes)) return
            call push(a, tag)
            select case (tag)
            case (IPP_INTEGER, IPP_ENUM)
                if (vlen /= 4) return
                a%ints(1, a%n) = s32(p)
            case (IPP_BOOLEAN)
                if (vlen /= 1) return
                a%ints(1, a%n) = u(p)
            case (IPP_RANGE)
                if (vlen /= 8) return
                a%ints(1:2, a%n) = [s32(p), s32(p + 4)]
            case (IPP_RESOLUTION)
                if (vlen /= 9) return
                a%ints(:, a%n) = [s32(p), s32(p + 4), u(p + 8)]
            case (IPP_TEXT_LANG, IPP_NAME_LANG)
                ! language length, language, text length, text
                if (vlen < 4) return
                a%texts(a%n)%s = text(p + 4 + u16(p) , u16(p + 2 + u16(p)))
            case (IPP_BEGIN_COLLECTION)
                p = p + vlen
                good = collection(a)
                return
            case default
                a%texts(a%n)%s = text(p, vlen)
            end select
            p = p + vlen
            good = .true.
        end function value
        recursive logical function collection(a) result(good)
            !! Members up to the end-collection tag, as the last value of a.
            type(ipp_attr_t), intent(inout) :: a
            type(ipp_attr_t), allocatable :: list(:)
            type(ipp_attr_t) :: m
            logical :: open
            integer :: tag, nlen, vlen, base
            good = .false.
            allocate(list(0))
            open = .false.
            do
                if (p + 4 > size(bytes)) return
                tag = u(p)
                if (tag == IPP_END_COLLECTION) then
                    nlen = u16(p + 1)
                    vlen = u16(p + 3 + nlen)
                    p = p + 5 + nlen + vlen
                    exit
                else if (tag == IPP_MEMBER_NAME) then
                    if (open) list = [list, m]
                    nlen = u16(p + 1)
                    vlen = u16(p + 3 + nlen)
                    if (p + 5 + nlen + vlen - 1 > size(bytes)) return
                    m = ipp_attr_t()
                    call empty(m)
                    m%name = text(p + 5 + nlen, vlen)
                    open = .true.
                    p = p + 5 + nlen + vlen
                else
                    if (.not. open) return
                    if (u16(p + 1) /= 0) return
                    if (.not. value(m, open, 0)) return
                end if
            end do
            if (open) list = [list, m]
            base = size(a%members)
            a%members = [a%members, list]
            a%first(a%n) = base + 1
            a%last(a%n) = base + size(list)
            good = .true.
        end function collection
    end subroutine ipp_decode

    ! --- transport --------------------------------------------------------------

    subroutine ipp_split_uri(uri, scheme, host, port, resource)
        !! scheme://host[:port]/resource; port 631 for ipp, 80 for http.
        character(*), intent(in) :: uri
        character(len=:), allocatable, intent(out) :: scheme, host, resource
        integer, intent(out) :: port
        integer :: a, b, c, ios
        character(len=:), allocatable :: rest
        scheme = ""
        host = ""
        resource = "/"
        port = 0
        a = index(uri, "://")
        if (a == 0) return
        scheme = uri(1:a - 1)
        rest = uri(a + 3:)
        b = index(rest, "/")
        if (b > 0) then
            resource = rest(b:)
            rest = rest(1:b - 1)
        end if
        if (index(rest, "@") > 0) rest = rest(index(rest, "@", back=.true.) + 1:)
        port = merge(80, 631, scheme == "http")
        if (len(rest) > 0) then
            if (rest(1:1) == "[") then
                c = index(rest, "]")
                if (c == 0) return
                host = rest(2:c - 1)
                rest = rest(c + 1:)
                if (len(rest) > 1) read (rest(2:), *, iostat=ios) port
                return
            end if
        end if
        c = index(rest, ":")
        if (c > 0) then
            host = rest(1:c - 1)
            read (rest(c + 1:), *, iostat=ios) port
            if (ios /= 0) port = 0
        else
            host = rest
        end if
    end subroutine ipp_split_uri

    function ipp_user() result(name)
        !! This process's user (requesting-user-name).
        character(len=:), allocatable :: name
        character(kind=c_char) :: buf(256)
        integer :: n, k
        n = net_user(buf, 256_c_int)
        if (n <= 0) then
            name = "anonymous"
            return
        end if
        allocate(character(len=n) :: name)
        do k = 1, n
            name(k:k) = buf(k)
        end do
    end function ipp_user

    subroutine ipp_post(host, port, resource, msg, response, error, document, timeout_ms)
        !! POST msg (with document after it) and decode the response; error is ""
        !! on success. A local CUPS socket that asks for authentication gets the
        !! peer credentials of this process, as libcups does.
        character(*), intent(in) :: host, resource
        integer, intent(in) :: port
        type(ipp_msg_t), intent(in) :: msg
        type(ipp_msg_t), intent(out) :: response
        character(len=:), allocatable, intent(out) :: error
        integer(int8), intent(in), optional, target :: document(:)
        integer, intent(in), optional :: timeout_ms
        integer(int8), allocatable, target :: body(:)
        integer(int8), allocatable :: reply(:)
        integer :: n, status, attempt, ms
        integer(int8), allocatable :: empty_doc(:)
        logical :: ok
        character(len=:), allocatable :: auth

        ms = 30000
        if (present(timeout_ms)) ms = timeout_ms
        call ipp_encode(msg, body, n)
        auth = ""
        allocate(empty_doc(0))
        do attempt = 1, 2
            if (present(document)) then
                call http_exchange(host, port, "POST", resource, auth, body(1:n), document, &
                    status, reply, error, ms)
            else
                call http_exchange(host, port, "POST", resource, auth, body(1:n), empty_doc, &
                    status, reply, error, ms)
            end if
            if (len(error) > 0) return
            if (status /= 401 .or. host(1:1) /= "/" .or. attempt == 2) exit
            auth = "Authorization: PeerCred " // ipp_user() // achar(13) // achar(10)
        end do
        if (status /= 200) then
            error = "HTTP status " // itoa(status)
            return
        end if
        call ipp_decode(reply, response, ok)
        if (.not. ok) error = "malformed IPP response"
    end subroutine ipp_post

    subroutine ipp_get(host, port, resource, text, error, timeout_ms)
        !! GET a text file (a printer's strings file).
        character(*), intent(in) :: host, resource
        integer, intent(in) :: port
        character(len=:), allocatable, intent(out) :: text, error
        integer, intent(in), optional :: timeout_ms
        integer(int8), allocatable :: reply(:), none(:)
        integer :: status, k, ms
        ms = 30000
        if (present(timeout_ms)) ms = timeout_ms
        allocate(none(0))
        text = ""
        call http_exchange(host, port, "GET", resource, "", none, none, status, reply, &
            error, ms)
        if (len(error) > 0) return
        if (status /= 200) then
            error = "HTTP status " // itoa(status)
            return
        end if
        allocate(character(len=size(reply)) :: text)
        do k = 1, size(reply)
            text(k:k) = achar(iand(int(reply(k)), 255))
        end do
    end subroutine ipp_get

    subroutine http_exchange(host, port, method, resource, extra, body, document, &
            status, reply, error, timeout_ms)
        !! One request on its own connection (Connection: close); the reply body
        !! with chunked transfer coding removed.
        character(*), intent(in) :: host, method, resource, extra
        integer, intent(in) :: port, timeout_ms
        integer(int8), intent(in), target :: body(:), document(:)
        integer, intent(out) :: status
        integer(int8), allocatable, intent(out) :: reply(:)
        character(len=:), allocatable, intent(out) :: error
        character(len=:), allocatable, target :: head
        character(kind=c_char), allocatable, target :: chead(:)
        integer(int8), allocatable, target :: got(:)
        integer(int8), allocatable :: grown(:)
        integer(c_int) :: fd
        integer(c_long) :: k
        integer :: n, i, hend, need
        logical :: chunked
        character(len=:), allocatable :: hosthdr
        character(len=2), parameter :: crlf = achar(13) // achar(10)

        status = 0
        error = ""
        chunked = .false.
        k = 0
        allocate(reply(0))
        fd = net_open(host // c_null_char, int(port, c_int), int(timeout_ms, c_int))
        if (fd < 0) then
            error = "cannot connect to " // host
            if (host(1:1) /= "/") error = error // ":" // itoa(port)
            return
        end if
        hosthdr = "localhost"
        if (host(1:1) /= "/") then
            hosthdr = host
            if (index(host, ":") > 0) hosthdr = "[" // host // "]"
            if (port /= 80 .or. method /= "GET") hosthdr = hosthdr // ":" // itoa(port)
        end if
        head = method // " " // resource // " HTTP/1.1" // crlf // "Host: " // hosthdr // crlf
        if (method == "POST") head = head // "Content-Type: application/ipp" // crlf // &
            "Content-Length: " // itoa(size(body) + size(document)) // crlf
        head = head // extra // "Connection: close" // crlf // crlf
        allocate(chead(len(head)))
        do i = 1, len(head)
            chead(i) = head(i:i)
        end do
        if (net_send(fd, c_loc(chead), int(len(head), c_long), int(timeout_ms, c_int)) /= 0) &
            goto 9
        if (size(body) > 0) then
            if (net_send(fd, c_loc(body), int(size(body), c_long), int(timeout_ms, c_int)) /= 0) &
                goto 9
        end if
        if (size(document) > 0) then
            if (net_send(fd, c_loc(document), int(size(document), c_long), &
                int(timeout_ms, c_int)) /= 0) goto 9
        end if
        ! Read until the reply is complete by its length or its last chunk, or
        ! until the peer closes: not every printer honours Connection: close.
        allocate(got(65536))
        n = 0
        hend = 0
        need = -1
        do
            if (n + 65536 > size(got)) then
                allocate(grown(2 * size(got)))
                grown(1:n) = got(1:n)
                call move_alloc(grown, got)
            end if
            k = net_recv(fd, c_loc(got(n + 1)), 65536_c_long, int(timeout_ms, c_int))
            if (k <= 0) exit
            n = n + int(k)
            if (complete()) exit
        end do
        call net_close(fd)
        if (k < 0 .and. .not. complete()) then
            error = "the connection to " // host // " failed"
            return
        end if
        if (hend == 0 .or. status == 0) then
            error = "malformed HTTP response"
            return
        end if
        if (chunked) then
            call dechunk(got(hend + 4:n), reply)
        else
            reply = got(hend + 4:n)
            if (need >= 0) reply = got(hend + 4:min(n, hend + 3 + need))
        end if
        return
        9       call net_close(fd)
        error = "the connection to " // host // " failed"
    contains
        logical function complete()
            !! Whether got(1:n) holds the whole reply; finds the header end, the
            !! status and the body length on the way (skipping 100 Continue).
            integer :: i, j, ios
            character(len=:), allocatable :: headers
            complete = .false.
            do while (hend == 0)
                do i = 1, n - 3
                    if (all(got(i:i + 3) == int([13, 10, 13, 10], int8))) then
                        hend = i
                        exit
                    end if
                end do
                if (hend == 0) return
                allocate(character(len=hend - 1) :: headers)
                do i = 1, hend - 1
                    headers(i:i) = achar(iand(int(got(i)), 255))
                end do
                if (index(headers, "HTTP/1.") /= 1 .or. len(headers) < 12) return
                read (headers(10:12), *, iostat=ios) status
                if (ios /= 0) status = 0
                if (status == 100) then
                    got(1:n - hend - 3) = got(hend + 4:n)
                    n = n - hend - 3
                    hend = 0
                    status = 0
                    deallocate(headers)
                    cycle
                end if
                headers = lower(headers)
                chunked = index(headers, "transfer-encoding: chunked") > 0
                i = index(headers, "content-length:")
                if (i > 0) then
                    j = index(headers(i:), achar(13))
                    if (j == 0) j = len(headers) - i + 2
                    read (headers(i + 15:i + j - 2), *, iostat=ios) need
                    if (ios /= 0) need = -1
                end if
            end do
            if (chunked) then
                complete = n - hend - 3 >= 5
                if (complete) complete = all(got(n - 4:n) == int([48, 13, 10, 13, 10], int8))
            else if (need >= 0) then
                complete = n - hend - 3 >= need
            end if
        end function complete
    end subroutine http_exchange

    subroutine dechunk(raw, out)
        integer(int8), intent(in) :: raw(:)
        integer(int8), allocatable, intent(out) :: out(:)
        integer :: p, e, size_, i, d, n
        allocate(out(size(raw)))
        n = 0
        p = 1
        do while (p <= size(raw))
            e = p
            do while (e < size(raw))
                if (raw(e) == 13_int8 .and. raw(e + 1) == 10_int8) exit
                e = e + 1
            end do
            size_ = 0
            do i = p, e - 1
                d = index("0123456789abcdef", achar(ior(iand(int(raw(i)), 255), 32))) - 1
                if (d < 0) exit
                size_ = 16 * size_ + d
            end do
            if (size_ == 0) exit
            p = e + 2
            if (p + size_ - 1 > size(raw)) exit
            out(n + 1:n + size_) = raw(p:p + size_ - 1)
            n = n + size_
            p = p + size_ + 2
        end do
        out = out(1:n)
    end subroutine dechunk

    pure function lower(s) result(t)
        character(*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k
        t = s
        do k = 1, len(s)
            if (s(k:k) >= "A" .and. s(k:k) <= "Z") t(k:k) = achar(iachar(s(k:k)) + 32)
        end do
    end function lower

    pure function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, '(i0)') i
        s = trim(buf)
    end function itoa

end module fortui_ipp
