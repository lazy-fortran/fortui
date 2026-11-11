module fortui_testing
    !! Automation and inspection for tests, agents and probes: synthetic events
    !! applied by the next ui_frame_begin (any backend), runtime/backend counters
    !! and queries of the last presented semantic frame. Not needed by applications.
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_backend, only: ui_backend_stats_t
    use fortui_layout, only: layout_box_t
    use fortui_input, only: key_press_t, input_host_key, input_claims
    implicit none
    private

    type, public :: ui_stats_t
        !! Runtime and backend counters since ui_init.
        integer :: frames = 0
        integer :: waiting_presents = 0
        logical :: last_present_waits = .false.
        !! Seconds after which the waiting host wakes for a timer; negative: none.
        real :: wake_in = -1.0
        integer :: followups = 0
        integer :: duplicates = 0
        integer :: active_layers = 0
        integer :: presents = 0
        integer :: waits = 0
        integer :: vertex_uploads = 0
        integer :: attribute_uploads = 0
        integer :: index_uploads = 0
    end type ui_stats_t

    public :: ui_inject_pointer, ui_inject_wheel, ui_inject_key, ui_inject_text
    public :: ui_inject_time, ui_inject_resize
    public :: ui_stats, ui_layer_uploads, ui_node_rect, ui_node_text, ui_node_count
    public :: ui_focused_id, ui_node_scroll, ui_inject_host, ui_frame_boxes
    public :: ui_inject_press, ui_host_key_claim, ui_node_revealed

contains

    subroutine ui_inject_pointer(x, y, down)
        !! Pointer state (logical units) seen by the next ui_frame_begin.
        real, intent(in) :: x, y
        logical, intent(in) :: down
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        ctx%inject_pointer = .true.
        ctx%inject_x = x
        ctx%inject_y = y
        ctx%inject_down = down
    end subroutine ui_inject_pointer

    subroutine ui_inject_wheel(steps)
        real, intent(in) :: steps
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (associated(ctx)) ctx%inject_wheel = ctx%inject_wheel + steps
    end subroutine ui_inject_wheel

    subroutine ui_inject_key(key)
        !! Named key (KEY_*) for the next frame.
        integer, intent(in) :: key
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%inject_key_count >= size(ctx%inject_keys)) return
        ctx%inject_key_count = ctx%inject_key_count + 1
        ctx%inject_keys(ctx%inject_key_count) = key
    end subroutine ui_inject_key

    subroutine ui_inject_press(key, code, mods, repeat, mac, focus)
        !! A key press with modifiers for the next frame: a named key (KEY_*), or
        !! KEY_NONE and the code point of a character; MOD_* and FOCUS_* are in
        !! fortui_input.
        integer, intent(in) :: key, code, mods
        logical, intent(in), optional :: repeat, mac
        integer, intent(in), optional :: focus
        type(fortui_context_t), pointer :: ctx
        type(key_press_t) :: p

        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%inject_press_count >= size(ctx%inject_presses)) return
        p%key = key
        p%code = code
        p%mods = mods
        if (present(repeat)) p%repeat = repeat
        if (present(mac)) p%mac = mac
        if (present(focus)) p%focus = focus
        ctx%inject_press_count = ctx%inject_press_count + 1
        ctx%inject_presses(ctx%inject_press_count) = p
    end subroutine ui_inject_press

    integer function ui_host_key_claim(key, flags, code, time) result(claim)
        !! What a host is told at the moment of a key, before its own default
        !! action (CLAIM_* in fortui_input); the arguments are those of
        !! input_host_key, `time` in seconds.
        integer, intent(in) :: key, flags, code
        double precision, intent(in) :: time
        type(fortui_context_t), pointer :: ctx

        claim = 0
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        claim = input_claims(ctx%input, input_host_key(key, flags, code), time)
    end function ui_host_key_claim

    logical function ui_node_revealed(id) result(revealed)
        !! Whether node `id` was asked into view in the last presented frame.
        character(*), intent(in) :: id
        type(fortui_context_t), pointer :: ctx
        integer :: i

        revealed = .false.
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        i = ctx%previous_frame%find(id)
        if (i > 0) revealed = ctx%previous_frame%nodes(i)%reveal
    end function ui_node_revealed

    subroutine ui_inject_text(utf8)
        !! Committed UTF-8 text typed before the next frame.
        character(*), intent(in) :: utf8
        type(fortui_context_t), pointer :: ctx
        integer :: n
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        n = min(len(utf8), len(ctx%inject_text) - ctx%inject_text_len)
        if (n <= 0) return
        ctx%inject_text(ctx%inject_text_len + 1:ctx%inject_text_len + n) = utf8(1:n)
        ctx%inject_text_len = ctx%inject_text_len + n
    end subroutine ui_inject_text

    subroutine ui_inject_time(seconds)
        !! Input timestamp (double-click detection) of the next frame.
        double precision, intent(in) :: seconds
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (associated(ctx)) ctx%inject_time = seconds
    end subroutine ui_inject_time

    subroutine ui_inject_resize(width, height)
        !! Window size (logical units) from the next frame on.
        integer, intent(in) :: width, height
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        ctx%inject_width = max(1, width)
        ctx%inject_height = max(1, height)
        ctx%inject_resize = .true.
    end subroutine ui_inject_resize

    function ui_stats() result(stats)
        type(ui_stats_t) :: stats
        type(fortui_context_t), pointer :: ctx
        type(ui_backend_stats_t) :: b

        ctx => get_default_context()
        if (.not. associated(ctx)) return
        stats%frames = ctx%frame_count
        stats%waiting_presents = ctx%waiting_presents
        stats%last_present_waits = ctx%wait_next
        stats%wake_in = ctx%backend%wake_in
        stats%followups = ctx%followups
        stats%duplicates = ctx%duplicates
        stats%active_layers = ctx%canvas%active_layers()
        if (.not. allocated(ctx%backend)) return
        b = ctx%backend%stats()
        stats%presents = b%presents
        stats%waits = b%waits
        stats%vertex_uploads = b%vertex_uploads
        stats%attribute_uploads = b%attribute_uploads
        stats%index_uploads = b%index_uploads
    end function ui_stats

    subroutine ui_layer_uploads(canvas_id, key, uploads, index_uploads)
        !! Uploads the backend performed for one retained layer (-1 when absent):
        !! positions of a vertex layer, colours/sizes of a point or line layer;
        !! `index_uploads` counts segment uploads of a line layer. `canvas_id` is
        !! the scoped canvas identity (e.g. "main/graph").
        character(*), intent(in) :: canvas_id, key
        integer, intent(out) :: uploads, index_uploads
        type(fortui_context_t), pointer :: ctx
        integer :: slot

        uploads = -1
        index_uploads = -1
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%backend)) return
        slot = ctx%canvas%lookup(trim(canvas_id) // "/" // trim(key))
        if (slot == 0) return
        call ctx%backend%canvas%uploads(slot, uploads, index_uploads)
    end subroutine ui_layer_uploads

    logical function ui_node_rect(id, x, y, width, height) result(found)
        !! Realized rectangle (logical units) of node `id` in the last presented frame.
        character(*), intent(in) :: id
        real, intent(out) :: x, y, width, height
        type(fortui_context_t), pointer :: ctx
        integer :: i

        x = 0.0
        y = 0.0
        width = 0.0
        height = 0.0
        found = .false.
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        i = ctx%previous_frame%find(id)
        if (i == 0) return
        found = .true.
        associate(n => ctx%previous_frame%nodes(i))
            x = n%x
            y = n%y
            width = n%width
            height = n%height
        end associate
    end function ui_node_rect

    function ui_node_text(id) result(value)
        !! Text (label, value or body) of node `id` in the last presented frame.
        character(*), intent(in) :: id
        character(len=:), allocatable :: value
        type(fortui_context_t), pointer :: ctx
        integer :: i

        value = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        i = ctx%previous_frame%find(id)
        if (i == 0) return
        if (allocated(ctx%previous_frame%nodes(i)%body)) then
            value = ctx%previous_frame%nodes(i)%body
        else
            value = trim(ctx%previous_frame%nodes(i)%text)
        end if
    end function ui_node_text

    integer function ui_node_count() result(n)
        !! Number of semantic nodes in the last presented frame.
        type(fortui_context_t), pointer :: ctx
        n = 0
        ctx => get_default_context()
        if (associated(ctx)) n = ctx%previous_frame%count
    end function ui_node_count

    logical function ui_node_scroll(id, scroll, content_height, line_count) result(found)
        !! Scroll offset, wrapped content height and line count of scroll_text `id`.
        character(*), intent(in) :: id
        real, intent(out) :: scroll, content_height
        integer, intent(out) :: line_count
        type(fortui_context_t), pointer :: ctx
        integer :: i

        scroll = 0.0
        content_height = 0.0
        line_count = 0
        found = .false.
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        i = ctx%previous_frame%find(id)
        if (i == 0) return
        found = .true.
        scroll = ctx%previous_frame%nodes(i)%scroll
        content_height = ctx%previous_frame%nodes(i)%content_height
        line_count = ctx%previous_frame%nodes(i)%line_count
    end function ui_node_scroll

    function ui_focused_id() result(id)
        !! Identity of the keyboard focus ("" when none).
        character(len=:), allocatable :: id
        type(fortui_context_t), pointer :: ctx
        id = ""
        ctx => get_default_context()
        if (associated(ctx)) id = trim(ctx%input%focus_id)
    end function ui_focused_id


    subroutine ui_inject_host(kind, id, value)
        !! A semantic host event (HOST_* from fortui_input) before the next frame.
        integer, intent(in) :: kind
        character(*), intent(in) :: id
        character(*), intent(in), optional :: value
        type(fortui_context_t), pointer :: ctx

        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%inject_host_count >= size(ctx%inject_host)) return
        ctx%inject_host_count = ctx%inject_host_count + 1
        ctx%inject_host(ctx%inject_host_count)%kind = kind
        ctx%inject_host(ctx%inject_host_count)%id = id
        ctx%inject_host(ctx%inject_host_count)%value = ""
        if (present(value)) ctx%inject_host(ctx%inject_host_count)%value = value
    end subroutine ui_inject_host

    subroutine ui_frame_boxes(boxes, count, node_id, node_box)
        !! Containers of the last presented frame, and the box of node `node_id`.
        type(layout_box_t), allocatable, intent(out) :: boxes(:)
        integer, intent(out) :: count, node_box
        character(*), intent(in) :: node_id
        type(fortui_context_t), pointer :: ctx
        integer :: j

        count = 0
        node_box = -1
        allocate (boxes(0))
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        associate(f => ctx%previous_frame)
            count = f%box_count
            if (count > 0) boxes = f%boxes(1:count)
            j = f%find(node_id)
            if (j > 0) node_box = f%nodes(j)%box
        end associate
    end subroutine ui_frame_boxes

end module fortui_testing
