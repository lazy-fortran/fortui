module fortui_net_transport
    !! The host side of the network service: a transport starts owned requests
    !! and hands out their outcome. The browser uses fetch and EventSource, a
    !! native host its sockets; a host without one reports NET_UNSUPPORTED.
    implicit none
    private

    integer, parameter, public :: NET_IDLE = 0, NET_PENDING = 1, NET_DONE = 2, NET_FAILED = 3, &
        NET_UNSUPPORTED = 4, NET_CANCELLED = 5, NET_OPEN = 6

    type, abstract, public :: net_transport_t
    contains
        procedure(start_i), deferred :: start
        procedure(take_i), deferred :: take
        procedure(next_i), deferred :: next_message
        procedure(cancel_i), deferred :: cancel
        procedure(wakes_i), deferred :: wakes
    end type net_transport_t

    abstract interface
        logical function start_i(self, id, method, url, body, content_type, stream)
            !! Begin request `id`; false when the host cannot (unsupported URL).
            import :: net_transport_t
            class(net_transport_t), intent(inout) :: self
            integer, intent(in) :: id
            character(*), intent(in) :: method, url, body, content_type
            logical, intent(in) :: stream
        end function start_i

        subroutine take_i(self, id, status, code, body, message)
            !! The outcome of request `id`: NET_PENDING while it runs, then once
            !! NET_DONE or NET_FAILED with the HTTP status and body or a message.
            import :: net_transport_t
            class(net_transport_t), intent(inout) :: self
            integer, intent(in) :: id
            integer, intent(out) :: status, code
            character(:), allocatable, intent(out) :: body, message
        end subroutine take_i

        subroutine next_i(self, id, status, data, got)
            !! The next message of event stream `id`. `status` is NET_PENDING
            !! while it (re)connects, NET_OPEN while connected, NET_FAILED when
            !! it cannot connect at all.
            import :: net_transport_t
            class(net_transport_t), intent(inout) :: self
            integer, intent(in) :: id
            integer, intent(out) :: status
            character(:), allocatable, intent(out) :: data
            logical, intent(out) :: got
        end subroutine next_i

        logical function wakes_i(self)
            !! Whether finished work wakes the host by itself; otherwise the
            !! runtime looks again a moment later while requests are open.
            import :: net_transport_t
            class(net_transport_t), intent(in) :: self
        end function wakes_i

        subroutine cancel_i(self, id)
            !! Forget request or stream `id` and release what it holds.
            import :: net_transport_t
            class(net_transport_t), intent(inout) :: self
            integer, intent(in) :: id
        end subroutine cancel_i
    end interface

end module fortui_net_transport
