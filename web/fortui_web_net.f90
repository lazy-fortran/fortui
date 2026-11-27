module fortui_web_net
    !! Network transport of the browser backend: requests through `fetch`,
    !! event streams through `EventSource` (which reconnects by itself). The
    !! host copies each outcome into a queue owned here and wakes a frame.
    use, intrinsic :: iso_c_binding, only: c_int, c_char, c_ptr, c_loc, c_null_ptr, c_int8_t
    use fortui_net_transport
    implicit none
    private

    public :: web_transport_t, fortui_web_net_deliver

    ! What the host delivers: an answer (failed: a message instead), a stream
    ! message, a stream that opened, a stream that lost its connection (failed:
    ! closed for good).
    integer, parameter :: ANSWER = 1, MESSAGE = 2, OPENED = 3, LOST = 4
    integer, parameter :: QMAX = 1024, SMAX = 64

    type :: delivery_t
        integer :: id = 0, kind = 0, failed = 0, code = 0
        integer(c_int8_t), allocatable :: bytes(:)
    end type delivery_t

    type(delivery_t), target :: queue(QMAX)
    integer :: queued = 0
    ! Connection state of open streams.
    integer :: stream_id(SMAX) = 0, stream_status(SMAX) = NET_PENDING

    type, extends(net_transport_t) :: web_transport_t
    contains
        procedure :: start => web_start
        procedure :: take => web_take
        procedure :: next_message => web_next
        procedure :: cancel => web_cancel
        procedure :: wakes => web_wakes
    end type web_transport_t

    interface
        subroutine js_start(id, method, nmethod, url, nurl, body, nbody, ctype, nctype, stream) &
                bind(C, name="fortui_web_net_start")
            import :: c_int, c_char
            integer(c_int), value :: id
            character(kind=c_char), intent(in) :: method(*), url(*), body(*), ctype(*)
            integer(c_int), value :: nmethod, nurl, nbody, nctype, stream
        end subroutine js_start
        subroutine js_cancel(id) bind(C, name="fortui_web_net_cancel")
            import :: c_int
            integer(c_int), value :: id
        end subroutine js_cancel
    end interface

contains

    type(c_ptr) function fortui_web_net_deliver(id, kind, failed, code, n) &
            bind(C, name="fortui_web_net_deliver")
        !! Room for n bytes of a new delivery; the host copies them there.
        integer(c_int), value :: id, kind, failed, code, n
        fortui_web_net_deliver = c_null_ptr
        if (queued >= QMAX) return
        queued = queued + 1
        queue(queued)%id = int(id)
        queue(queued)%kind = int(kind)
        queue(queued)%failed = int(failed)
        queue(queued)%code = int(code)
        if (allocated(queue(queued)%bytes)) deallocate (queue(queued)%bytes)
        allocate (queue(queued)%bytes(max(1, int(n))))
        if (n > 0) then
            fortui_web_net_deliver = c_loc(queue(queued)%bytes)
        else
            deallocate (queue(queued)%bytes)
            allocate (queue(queued)%bytes(0))
        end if
    end function fortui_web_net_deliver

    function text_of(k) result(t)
        integer, intent(in) :: k
        character(:), allocatable :: t
        integer :: i
        allocate (character(len=size(queue(k)%bytes)) :: t)
        do i = 1, size(queue(k)%bytes)
            t(i:i) = achar(iand(int(queue(k)%bytes(i)), 255))
        end do
    end function text_of

    subroutine drop(k)
        integer, intent(in) :: k
        integer :: j
        do j = k, queued - 1
            queue(j)%id = queue(j + 1)%id
            queue(j)%kind = queue(j + 1)%kind
            queue(j)%failed = queue(j + 1)%failed
            queue(j)%code = queue(j + 1)%code
            call move_alloc(queue(j + 1)%bytes, queue(j)%bytes)
        end do
        queued = queued - 1
    end subroutine drop

    logical function web_start(self, id, method, url, body, content_type, stream) result(started)
        class(web_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        character(*), intent(in) :: method, url, body, content_type
        logical, intent(in) :: stream
        integer :: k
        integer(c_int) :: s
        started = .true.
        s = 0
        if (stream) then
            s = 1
            do k = 1, SMAX
                if (stream_id(k) /= 0) cycle
                stream_id(k) = id
                stream_status(k) = NET_PENDING
                exit
            end do
        end if
        call js_start(int(id, c_int), method, int(len(method), c_int), url, int(len(url), c_int), &
            body // ' ', int(len(body), c_int), content_type // ' ', int(len(content_type), c_int), s)
    end function web_start

    subroutine web_take(self, id, status, code, body, message)
        class(web_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status, code
        character(:), allocatable, intent(out) :: body, message
        integer :: k
        status = NET_PENDING
        code = 0
        body = ''
        message = ''
        do k = 1, queued
            if (queue(k)%id /= id .or. queue(k)%kind /= ANSWER) cycle
            if (queue(k)%failed /= 0) then
                status = NET_FAILED
                message = text_of(k)
            else
                status = NET_DONE
                code = queue(k)%code
                body = text_of(k)
            end if
            call drop(k)
            return
        end do
    end subroutine web_take

    subroutine web_next(self, id, status, data, got)
        class(web_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer, intent(out) :: status
        character(:), allocatable, intent(out) :: data
        logical, intent(out) :: got
        integer :: k, s
        got = .false.
        data = ''
        status = NET_FAILED
        s = findloc(stream_id, id, 1)
        if (s == 0) return
        k = 1
        do while (k <= queued)
            if (queue(k)%id /= id) then
                k = k + 1
                cycle
            end if
            select case (queue(k)%kind)
            case (OPENED)
                stream_status(s) = NET_OPEN
                call drop(k)
            case (LOST)
                if (queue(k)%failed /= 0) then
                    stream_status(s) = NET_FAILED
                    stream_id(s) = 0
                    status = NET_FAILED
                    data = 'event stream closed'
                    call drop(k)
                    return
                end if
                stream_status(s) = NET_PENDING
                call drop(k)
            case (MESSAGE)
                data = text_of(k)
                got = .true.
                call drop(k)
                exit
            case default
                k = k + 1
            end select
        end do
        status = stream_status(s)
    end subroutine web_next

    subroutine web_cancel(self, id)
        class(web_transport_t), intent(inout) :: self
        integer, intent(in) :: id
        integer :: k
        call js_cancel(int(id, c_int))
        k = 1
        do while (k <= queued)
            if (queue(k)%id == id) then
                call drop(k)
            else
                k = k + 1
            end if
        end do
        where (stream_id == id) stream_id = 0
    end subroutine web_cancel

    logical function web_wakes(self)
        class(web_transport_t), intent(in) :: self
        web_wakes = .true.
    end function web_wakes

end module fortui_web_net
