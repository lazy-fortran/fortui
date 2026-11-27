module fortui_net
    !! Network service: HTTP requests and server-sent event streams as owned
    !! asynchronous requests, the same on every host. The application keeps the
    !! request value and looks at it in its frames:
    !!
    !!     call net_fetch(req, "/api/log?from=3")
    !!     ...
    !!     if (net_poll(req)) then              ! true in the frame it finished
    !!         if (req%status == NET_DONE) call apply(req%body)
    !!     end if
    !!
    !!     call net_stream_open(events, "/api/events")
    !!     do while (net_stream_next(events, data))
    !!         ...
    !!     end do
    !!
    !! Relative URLs resolve against the page in a browser and against
    !! `net_set_base` elsewhere. The runtime keeps the outcome until the
    !! application asks, so no borrowed value is held across frames.
    use fortui_net_transport
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_core, only: ui_wake_after
    implicit none
    private

    public :: NET_IDLE, NET_PENDING, NET_DONE, NET_FAILED, NET_UNSUPPORTED, NET_CANCELLED, NET_OPEN
    public :: net_transport_t

    type, public :: net_request_t
        integer :: status = NET_IDLE
        !> HTTP status of a finished request.
        integer :: code = 0
        character(:), allocatable :: body, message
        integer :: id = 0
    end type net_request_t

    type, public :: net_stream_t
        !> NET_PENDING while (re)connecting, NET_OPEN while connected.
        integer :: status = NET_IDLE
        character(:), allocatable :: message
        integer :: id = 0
    end type net_stream_t

    public :: net_fetch, net_poll, net_cancel, net_stream_open, net_stream_next, net_stream_close
    public :: net_use, net_set_base, net_resolve

    integer :: next_id = 0
    character(:), allocatable :: base

    ! How long a host without wake-ups waits before looking again.
    real, parameter :: POLL_SECONDS = 0.02

contains

    subroutine net_use(transport)
        !! Install the host's transport; backends do this when they start.
        class(net_transport_t), intent(in) :: transport
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (allocated(ctx%net)) deallocate (ctx%net)
        allocate (ctx%net, source=transport)
    end subroutine net_use

    subroutine net_set_base(url)
        !! Origin for relative URLs on hosts without a page, e.g. "http://host:4190".
        character(*), intent(in) :: url
        base = url
        do while (len(base) > 0)
            if (base(len(base):len(base)) /= '/') exit
            base = base(1:len(base) - 1)
        end do
    end subroutine net_set_base

    function net_resolve(url) result(full)
        !! `url` against the base when it is relative and a base is set.
        character(*), intent(in) :: url
        character(:), allocatable :: full
        full = url
        if (.not. allocated(base)) return
        if (len(base) == 0 .or. index(url, '://') > 0) return
        if (len(url) > 0) then
            if (url(1:1) == '/') then
                full = base // url
                return
            end if
        end if
        full = base // '/' // url
    end function net_resolve

    integer function new_id()
        if (next_id >= huge(next_id) - 1) next_id = 0
        next_id = next_id + 1
        new_id = next_id
    end function new_id

    subroutine net_fetch(req, url, method, body, content_type)
        !! Start a request; an open one with the same value is cancelled first.
        !! `method` defaults to GET, or POST when a body is given.
        type(net_request_t), intent(inout) :: req
        character(*), intent(in) :: url
        character(*), intent(in), optional :: method, body, content_type
        character(:), allocatable :: m, b, ct
        type(fortui_context_t), pointer :: ctx
        call net_cancel(req)
        b = ''
        if (present(body)) b = body
        m = 'GET'
        if (present(body)) m = 'POST'
        if (present(method)) m = method
        ct = 'text/plain; charset=utf-8'
        if (present(content_type)) ct = content_type
        req%code = 0
        req%body = ''
        req%message = ''
        req%status = NET_UNSUPPORTED
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%net)) then
            req%message = 'no network on this host'
            return
        end if
        req%id = new_id()
        if (.not. ctx%net%start(req%id, m, net_resolve(url), b, ct, .false.)) then
            req%message = 'cannot request ' // url
            req%id = 0
            return
        end if
        req%status = NET_PENDING
        if (.not. ctx%net%wakes()) call ui_wake_after(POLL_SECONDS)
    end subroutine net_fetch

    logical function net_poll(req) result(finished)
        !! True in the frame in which the request finished (NET_DONE: `code` and
        !! `body`; NET_FAILED: `message`).
        type(net_request_t), intent(inout) :: req
        type(fortui_context_t), pointer :: ctx
        integer :: status, code
        character(:), allocatable :: body, message
        finished = .false.
        if (req%status /= NET_PENDING) return
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%net)) return
        call ctx%net%take(req%id, status, code, body, message)
        if (status == NET_PENDING) then
            if (.not. ctx%net%wakes()) call ui_wake_after(POLL_SECONDS)
            return
        end if
        req%status = status
        req%code = code
        req%body = body
        req%message = message
        req%id = 0
        finished = .true.
    end function net_poll

    subroutine net_cancel(req)
        type(net_request_t), intent(inout) :: req
        type(fortui_context_t), pointer :: ctx
        if (req%status == NET_PENDING .and. req%id /= 0) then
            ctx => get_default_context()
            if (associated(ctx)) then
                if (allocated(ctx%net)) call ctx%net%cancel(req%id)
            end if
            req%status = NET_CANCELLED
        end if
        req%id = 0
    end subroutine net_cancel

    subroutine net_stream_open(s, url)
        !! Follow a server-sent event stream; it reconnects by itself.
        type(net_stream_t), intent(inout) :: s
        character(*), intent(in) :: url
        type(fortui_context_t), pointer :: ctx
        call net_stream_close(s)
        s%message = ''
        s%status = NET_UNSUPPORTED
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%net)) then
            s%message = 'no network on this host'
            return
        end if
        s%id = new_id()
        if (.not. ctx%net%start(s%id, 'GET', net_resolve(url), '', '', .true.)) then
            s%message = 'cannot follow ' // url
            s%id = 0
            return
        end if
        s%status = NET_PENDING
        if (.not. ctx%net%wakes()) call ui_wake_after(POLL_SECONDS)
    end subroutine net_stream_open

    logical function net_stream_next(s, data) result(got)
        !! The next message, if one arrived; call until false in every frame.
        type(net_stream_t), intent(inout) :: s
        character(:), allocatable, intent(out) :: data
        type(fortui_context_t), pointer :: ctx
        integer :: status
        got = .false.
        data = ''
        if (s%id == 0) return
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%net)) return
        call ctx%net%next_message(s%id, status, data, got)
        s%status = status
        if (status == NET_FAILED) then
            s%message = data
            data = ''
            got = .false.
            s%id = 0
            return
        end if
        if (.not. got .and. .not. ctx%net%wakes()) call ui_wake_after(POLL_SECONDS)
    end function net_stream_next

    subroutine net_stream_close(s)
        type(net_stream_t), intent(inout) :: s
        type(fortui_context_t), pointer :: ctx
        if (s%id /= 0) then
            ctx => get_default_context()
            if (associated(ctx)) then
                if (allocated(ctx%net)) call ctx%net%cancel(s%id)
            end if
        end if
        s%id = 0
        if (s%status == NET_PENDING .or. s%status == NET_OPEN) s%status = NET_CANCELLED
    end subroutine net_stream_close

end module fortui_net
