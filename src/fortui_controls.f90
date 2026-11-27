module fortui_controls
    !! Controls composed from the primitives of fortui_widgets and the
    !! containers of fortui_layout: symbols, chips and badges, segmented
    !! choices, drop-down lists, menus, notifications, modal dialogs, scroll
    !! containers, virtual lists and a data grid.
    !!
    !! Popups (menus, drop-down lists on hosts without a picker of their own)
    !! float above the page and close on a choice, on Escape and on a press
    !! outside them. Scroll containers clip what they hold; with `stick` they
    !! keep showing the end while the view is there (chat, logs).
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_frame, only: ui_node_t, UI_CHIP, UI_ICON, UI_SELECT, UI_SCROLL_TEXT, UI_LIST_BOX, &
        UI_TEXT_AREA, UI_CANVAS, UI_CAPTION, UI_HEADING, &
        UI_BODY, UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, &
        UI_TONE_ACCENT, UI_TONE_ATTENTION, UI_EMPHASIS_QUIET, label_size, style_size, &
        style_weight, ui_control_height, ui_control_padding, ui_control_min_width
    use fortui_layout, only: layout_get_cursor, layout_available, layout_fill_width, &
        row_begin, row_end, column_begin, column_end, dialog_begin, dialog_end, &
        scroll_region_begin, scroll_region_end, float_begin, float_end, layout_set_padding, &
        KIND_POPUP, KIND_TOASTS, KIND_SCROLL
    use fortui_widgets, only: button, text, text_input, scoped_id, claim, composing, &
        resolve_width, width_mode, set_enabled, decorate_from_input, place_and_emit, &
        icon_size, ICON_GAP, parse_number
    use fortui_input, only: input_activated, input_host_value, input_host_dismissed, &
        input_key_arrived, input_hovered, KEY_ESCAPE, KEY_ARROW_UP, KEY_ARROW_DOWN
    use fortui_icons, only: icon_path, icon_glyph
    use fortui_text, only: text_width, text_line_height, ui_str
    use fortui_core, only: ui_wake_after, ui_time, ui_window_size
    use fortui_canvas, only: ui_rgba
    use iso_fortran_env, only: int32
    implicit none
    private

    public :: icon, badge, chip, segmented, dropdown, menu, avatar, ui_user_colour
    public :: toast, modal_begin, modal_end
    public :: scroll_begin, scroll_end, virtual_list_begin, virtual_list_end
    public :: grid_state_t, data_grid

    type, public :: grid_state_t
        !! What a data grid keeps between frames: the sort column (0: the
        !! given order), its direction, the filter text, the selected row (an
        !! index of the given rows, 0: none) and the rows shown, in order.
        !! Set `dirty` when the cells changed and the grid has more than
        !! GRID_ALWAYS rows; smaller grids look at their cells every frame.
        integer :: sort_column = 0
        logical :: descending = .false.
        character(len=:), allocatable :: filter
        integer :: selected = 0
        integer, allocatable :: order(:)
        logical :: dirty = .true.
        integer :: seen_rows = -1, seen_columns = -1, seen_column = -1
        logical :: seen_descending = .false.
        character(len=:), allocatable :: seen_filter
    end type grid_state_t

    integer, parameter :: GRID_ALWAYS = 2000

    ! A wheel notch scrolls this far.
    real, parameter :: WHEEL_STEP = 48.0
    ! Rows composed beyond the visible ones on each side.
    integer, parameter :: OVERSCAN = 4

    ! Open scroll containers: their states, viewports and whether the view
    ! follows the end.
    integer, parameter :: MAX_OPEN = 16
    integer :: open_state(MAX_OPEN) = 0
    real :: open_height(MAX_OPEN) = 0.0
    logical :: open_stick(MAX_OPEN) = .false.
    integer :: open_count = 0

    ! Notifications on screen.
    type :: toast_t
        character(len=:), allocatable :: message
        integer :: tone = UI_TONE_NORMAL
        double precision :: until = 0d0
        integer :: serial = 0
    end type toast_t
    integer, parameter :: MAX_TOASTS = 4
    type(toast_t) :: toasts(MAX_TOASTS)
    integer :: toast_count = 0, toast_serial = 0

contains

    ! --- symbols, chips, badges ----------------------------------------------------

    subroutine icon(name, size, tone, tooltip, id)
        !! A symbol of fortui_icons at `size` (default: beside body text) in
        !! `tone`; `tooltip` names it for hover and assistive technology.
        character(*), intent(in) :: name
        real, intent(in), optional :: size
        integer, intent(in), optional :: tone
        character(*), intent(in), optional :: tooltip, id
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: node
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        node%kind = UI_ICON
        if (present(id)) then
            node%id = scoped_id(id)
            if (.not. claim(ctx, trim(node%id), "icon")) return
        end if
        node%icon = icon_path(name)
        node%glyph = icon_glyph(name)
        node%text = ''
        if (present(tooltip)) node%tooltip = tooltip
        if (present(tone)) node%tone = tone
        node%width = icon_size(label_size())
        if (present(size)) node%width = max(1.0, size)
        node%height = node%width
        node%text_size = node%width
        call place_and_emit(ctx, node)
    end subroutine icon

    subroutine badge(label, tone)
        !! A short static label in a rounded shape: a count, a state.
        character(*), intent(in) :: label
        integer, intent(in), optional :: tone
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: node
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        node%kind = UI_CHIP
        node%text = label
        node%style = UI_CAPTION
        node%text_size = style_size(UI_CAPTION)
        if (present(tone)) node%tone = tone
        node%height = real(nint(text_line_height(node%text_size) + 2.0))
        node%width = max(node%height, text_width(label, node%text_size, style_weight(UI_CAPTION)) + &
            node%height)
        call place_and_emit(ctx, node)
    end subroutine badge

    logical function chip(id, label, selected, icon, tone, key, enabled) result(clicked)
        !! A chip that can be selected (a filter, a tag); true once when
        !! activated, and the application changes `selected`.
        character(*), intent(in) :: id, label
        logical, intent(in), optional :: selected, enabled
        character(*), intent(in), optional :: icon
        integer, intent(in), optional :: tone, key
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: node
        clicked = .false.
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        node%kind = UI_CHIP
        node%id = scoped_id(id, key)
        if (.not. claim(ctx, trim(node%id), "chip")) return
        node%text = label
        node%text_size = label_size()
        node%toggle = .true.
        if (present(selected)) node%checked = selected
        if (present(tone)) node%tone = tone
        if (present(icon)) then
            node%icon = icon_path(icon)
            node%glyph = icon_glyph(icon)
            if (len(node%icon) == 0) deallocate (node%icon, node%glyph)
        end if
        node%height = real(nint(0.875 * ui_control_height()))
        node%width = text_width(label, node%text_size, style_weight(6)) + node%height
        if (allocated(node%icon)) node%width = node%width + icon_size(node%text_size) + ICON_GAP
        call set_enabled(node, enabled)
        call decorate_from_input(ctx, node)
        if (.not. node%disabled) clicked = input_activated(ctx%input, trim(node%id))
        if (clicked) ctx%followup = .true.
        call place_and_emit(ctx, node)
    end function chip

    subroutine avatar(name, colour, tooltip, size)
        !! A person as their initials in a circle of their colour (default:
        !! ui_user_colour(name)); `tooltip` says who and what they do.
        character(*), intent(in) :: name
        integer(int32), intent(in), optional :: colour
        character(*), intent(in), optional :: tooltip
        real, intent(in), optional :: size
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: node
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        node%kind = UI_CHIP
        node%text = initials(name)
        node%look = 'fui-avatar'
        node%style = UI_CAPTION
        node%text_size = style_size(UI_CAPTION)
        node%fill = ui_user_colour(name)
        if (present(colour)) node%fill = colour
        node%tooltip = name
        if (present(tooltip)) node%tooltip = tooltip
        node%height = 26.0
        if (present(size)) node%height = size
        node%width = node%height
        call place_and_emit(ctx, node)
    end subroutine avatar

    function initials(name) result(s)
        !! Up to two letters: the first of each of the first two words, or the
        !! first two of a single word; a name in another script: its first
        !! character.
        character(*), intent(in) :: name
        character(len=:), allocatable :: s, firsts, word
        integer :: k, words
        logical :: start
        s = ''
        firsts = ''
        word = ''
        words = 0
        start = .true.
        do k = 1, len_trim(name)
            if (iachar(name(k:k)) >= 128 .and. words == 0) then
                s = name(k:min(len_trim(name), k + utf8_len(name(k:k)) - 1))
                return
            end if
            if (index(' ._-@', name(k:k)) > 0) then
                start = .true.
                cycle
            end if
            if (start) then
                words = words + 1
                if (words <= 2) firsts = firsts // upper(name(k:k))
                start = .false.
            end if
            if (words == 1) word = word // name(k:k)
        end do
        if (words >= 2) then
            s = firsts
        else if (len(word) >= 2) then
            s = upper(word(1:1)) // word(2:2)
        else
            s = firsts
        end if
    end function initials

    pure integer function utf8_len(c)
        character, intent(in) :: c
        integer :: b
        b = iachar(c)
        utf8_len = 1
        if (b >= 240) then
            utf8_len = 4
        else if (b >= 224) then
            utf8_len = 3
        else if (b >= 192) then
            utf8_len = 2
        end if
    end function utf8_len

    pure function upper(c) result(u)
        character, intent(in) :: c
        character :: u
        u = c
        if (c >= 'a' .and. c <= 'z') u = achar(iachar(c) - 32)
    end function upper

    integer(int32) function ui_user_colour(name) result(c)
        !! A colour of its own for each person, the same everywhere: one of ten
        !! hues that keep white initials readable.
        character(*), intent(in) :: name
        integer :: k, h
        integer, parameter :: rgb(3, 10) = reshape([196, 49, 75, 202, 80, 16, 152, 111, 11, &
            16, 124, 16, 0, 120, 120, 0, 99, 177, 79, 82, 178, 135, 100, 184, 194, 57, 179, &
            92, 92, 92], [3, 10])
        h = 7
        do k = 1, len_trim(name)
            h = modulo(h * 31 + iachar(name(k:k)), 1000003)
        end do
        k = modulo(h, 10) + 1
        c = ui_rgba(rgb(1, k), rgb(2, k), rgb(3, k))
    end function ui_user_colour

    ! --- choices ---------------------------------------------------------------------

    logical function segmented(id, labels, selected, icons, enabled) result(changed)
        !! One of a few options as joined buttons (a view, a tool, a language);
        !! `selected` (1-based) changes on a click. `icons` names a symbol per
        !! option. Returns whether `selected` changed.
        character(*), intent(in) :: id, labels(:)
        integer, intent(inout) :: selected
        character(*), intent(in), optional :: icons(:)
        logical, intent(in), optional :: enabled
        integer :: k, old
        logical :: hit
        changed = .false.
        old = selected
        call row_begin(0.0, id=id, look="fui-segmented")
        do k = 1, size(labels)
            if (present(icons)) then
                hit = button("option", trim(labels(k)), key=k, pressed=k == selected, &
                    enabled=enabled, icon=trim(icons(k)))
            else
                hit = button("option", trim(labels(k)), key=k, pressed=k == selected, &
                    enabled=enabled)
            end if
            if (hit) selected = k
        end do
        call row_end()
        changed = selected /= old
    end function segmented

    logical function dropdown(id, options, selected, width, enabled) result(changed)
        !! One of `options`, shown closed; `selected` (1-based, 0: none) changes
        !! when one is chosen. Browsers and phones show their own picker; other
        !! hosts a list below the field, also driven by Up and Down.
        character(*), intent(in) :: id, options(:)
        integer, intent(inout) :: selected
        real, intent(in), optional :: width
        logical, intent(in), optional :: enabled
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: node
        character(len=:), allocatable :: v, all
        real :: natural, iw
        integer :: k, st, old, n
        changed = .false.
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        n = size(options)
        old = selected
        node%kind = UI_SELECT
        node%id = scoped_id(id)
        if (.not. claim(ctx, trim(node%id), "dropdown")) return
        node%text_size = label_size()
        iw = icon_size(node%text_size)
        natural = ui_control_min_width()
        all = ''
        do k = 1, n
            natural = max(natural, text_width(trim(options(k)), node%text_size) + &
                2.0 * ui_control_padding() + iw + ICON_GAP)
            all = all // trim(options(k)) // achar(10)
        end do
        node%body = all
        node%icon = icon_path('chevron-down')
        node%glyph = icon_glyph('chevron-down')
        node%width = resolve_width(width, natural)
        node%width_mode = width_mode(width)
        node%height = ui_control_height()
        call set_enabled(node, enabled)
        call decorate_from_input(ctx, node)
        st = ctx%state(trim(node%id))
        ! The browser's picker reports the option itself.
        if (input_host_value(ctx%input, trim(node%id), v)) then
            k = nint(parse_number(v, 0.0))
            if (k >= 1 .and. k <= n) selected = k
        end if
        if (.not. node%disabled) then
            if (input_activated(ctx%input, trim(node%id))) &
                ctx%states(st)%open = .not. ctx%states(st)%open
            if (node%focused .and. .not. ctx%states(st)%open) then
                if (input_key_arrived(ctx%input, KEY_ARROW_DOWN)) selected = min(n, selected + 1)
                if (input_key_arrived(ctx%input, KEY_ARROW_UP)) selected = max(1, selected - 1)
            end if
        end if
        selected = max(0, min(n, selected))
        node%value = real(selected)
        node%text = ''
        if (selected > 0) node%text = trim(options(selected))
        call place_and_emit(ctx, node)
        if (ctx%states(st)%open .and. .not. node%disabled) then
            k = pick(ctx, st, trim(node%id), node, options, selected)
            if (k > 0) selected = k
        end if
        changed = selected /= old
        if (changed) ctx%followup = .true.
    end function dropdown

    integer function menu(id, label, items, icon, emphasis, enabled) result(chosen)
        !! A button that opens a list of commands; the number of the command
        !! chosen in this frame (1-based), else 0. An item "-" separates groups.
        character(*), intent(in) :: id, label, items(:)
        character(*), intent(in), optional :: icon
        integer, intent(in), optional :: emphasis
        logical, intent(in), optional :: enabled
        type(fortui_context_t), pointer :: ctx
        type(ui_node_t) :: anchor
        integer :: st, current
        logical :: hit
        chosen = 0
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        call column_begin(look="fui-anchor")
        if (present(icon)) then
            hit = button(id, label, emphasis=emphasis, enabled=enabled, icon=icon, tooltip=label)
        else
            hit = button(id, label, emphasis=emphasis, enabled=enabled, icon='chevron-down')
        end if
        if (ctx%current_frame%count > 0) anchor = ctx%current_frame%nodes(ctx%current_frame%count)
        st = ctx%state(trim(anchor%id))
        if (hit) ctx%states(st)%open = .not. ctx%states(st)%open
        if (ctx%states(st)%open) then
            current = 0
            chosen = pick(ctx, st, trim(anchor%id), anchor, items, current)
        end if
        call column_end()
    end function menu

    integer function pick(ctx, st, owner, anchor, items, current) result(chosen)
        !! The open list of a drop-down or menu below `anchor`; closes it on a
        !! choice, on Escape and on a press outside it and its anchor.
        type(fortui_context_t), intent(inout) :: ctx
        integer, intent(in) :: st, current
        character(*), intent(in) :: owner, items(:)
        type(ui_node_t), intent(in) :: anchor
        real :: w, bounds(4)
        integer :: k
        logical :: outside
        chosen = 0
        w = anchor%width
        do k = 1, size(items)
            w = max(w, text_width(trim(items(k)), label_size()) + 2.0 * ui_control_padding() + 8.0)
        end do
        outside = ctx%input%pointer_pressed .and. &
            .not. input_hovered(ctx%input, ctx%states(st)%bounds(1), ctx%states(st)%bounds(2), &
            ctx%states(st)%bounds(3), ctx%states(st)%bounds(4)) .and. &
            .not. input_hovered(ctx%input, anchor%x, anchor%y, anchor%width, anchor%height)
        if (input_key_arrived(ctx%input, KEY_ESCAPE) .or. outside .or. &
            input_host_dismissed(ctx%input, owner // ".list")) then
            ctx%states(st)%open = .false.
            ctx%followup = .true.
            return
        end if
        call float_begin(id_tail(owner) // ".list", anchor%x, anchor%y + anchor%height + 2.0, w, &
            KIND_POPUP)
        do k = 1, size(items)
            if (trim(items(k)) == '-') then
                call text('', size=4.0)
                cycle
            end if
            if (current > 0) then
                if (button("item", trim(items(k)), key=k, emphasis=UI_EMPHASIS_QUIET, width=w, &
                    pressed=k == current)) chosen = k
            else
                if (button("item", trim(items(k)), key=k, emphasis=UI_EMPHASIS_QUIET, width=w)) &
                    chosen = k
            end if
        end do
        call float_end(bounds)
        ctx%states(st)%bounds = bounds
        if (chosen > 0) then
            ctx%states(st)%open = .false.
            ctx%followup = .true.
        end if
    end function pick

    function id_tail(full) result(tail)
        !! The last part of a scoped id: what composes it again in its scope.
        character(*), intent(in) :: full
        character(len=:), allocatable :: tail
        integer :: k
        k = index(full, '/', back=.true.)
        tail = full(k + 1:)
    end function id_tail

    ! --- notifications ------------------------------------------------------------------

    subroutine toast(message, tone, seconds)
        !! A short notification at the bottom of the window for `seconds`
        !! (default 4), or until closed; at most four are shown.
        character(*), intent(in) :: message
        integer, intent(in), optional :: tone
        real, intent(in), optional :: seconds
        type(fortui_context_t), pointer :: ctx
        integer :: k
        real :: life
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (toast_count == MAX_TOASTS) then
            do k = 1, MAX_TOASTS - 1
                toasts(k) = toasts(k + 1)
            end do
            toast_count = toast_count - 1
        end if
        life = 4.0
        if (present(seconds)) life = max(0.5, seconds)
        toast_count = toast_count + 1
        toast_serial = toast_serial + 1
        toasts(toast_count)%message = message
        toasts(toast_count)%tone = UI_TONE_NORMAL
        if (present(tone)) toasts(toast_count)%tone = tone
        toasts(toast_count)%until = ui_time() + life
        toasts(toast_count)%serial = toast_serial
        ctx%overlays => compose_toasts
        ctx%followup = .true.
    end subroutine toast

    subroutine compose_toasts()
        type(fortui_context_t), pointer :: ctx
        integer :: k, j
        real :: ww, wh, w, next
        character(len=:), allocatable :: symbol
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        j = 0
        do k = 1, toast_count
            if (ui_time() >= toasts(k)%until) cycle
            j = j + 1
            if (j /= k) toasts(j) = toasts(k)
        end do
        toast_count = j
        if (toast_count == 0) return
        call ui_window_size(ww, wh)
        w = min(440.0, ww - 32.0)
        call float_begin("fui-toasts", 0.5 * (ww - w), &
            wh - 16.0 - real(toast_count) * (ui_control_height() + 20.0), w, KIND_TOASTS)
        next = huge(1.0)
        do k = 1, toast_count
            select case (toasts(k)%tone)
            case (UI_TONE_POSITIVE); symbol = 'check'
            case (UI_TONE_NEGATIVE); symbol = 'error'
            case (UI_TONE_ATTENTION); symbol = 'warning'
            case default; symbol = 'info'
            end select
            call row_begin(8.0, id="toast" // ui_str(toasts(k)%serial), height=ui_control_height() + 12.0, &
                look="fui-toast")
            call icon(symbol, tone=toasts(k)%tone)
            call text(toasts(k)%message, width=w - 2.0 * ui_control_height() - 24.0, ellipsis=.true.)
            if (button("close", "", emphasis=UI_EMPHASIS_QUIET, icon="close", tooltip="Close")) &
                toasts(k)%until = 0d0
            call row_end()
            next = min(next, real(toasts(k)%until - ui_time()))
        end do
        call float_end()
        if (next < huge(1.0)) call ui_wake_after(max(0.05, next))
    end subroutine compose_toasts

    ! --- dialogs ------------------------------------------------------------------------

    subroutine modal_begin(id, title, width, height)
        !! A modal dialog with `title` as its heading and accessible name; only
        !! it takes the pointer while open. The application closes it (Escape:
        !! ui_key_pressed(KEY_ESCAPE)).
        character(*), intent(in) :: id, title
        real, intent(in), optional :: width, height
        real :: w, h, aw, ah
        call layout_available(aw, ah)
        w = 480.0
        if (present(width)) w = width
        h = min(ah, 360.0)
        if (present(height)) h = height
        call dialog_begin(id, w, h, 12.0, 20.0, label=title)
        call text(title, style=UI_HEADING)
    end subroutine modal_begin

    subroutine modal_end()
        call dialog_end()
    end subroutine modal_end

    ! --- scrolling ----------------------------------------------------------------------

    subroutine scroll_begin(id, height, stick, content, reports)
        !! A container of the remaining width that shows `height` of what it
        !! holds and scrolls the rest (wheel, touch, scroll bar). With `stick`,
        !! the view stays at the end while it is there, so new lines show (chat,
        !! logs). `content` is the height of what it holds where known in
        !! advance; `reports` asks the host for the offset (virtual lists).
        character(*), intent(in) :: id
        real, intent(in) :: height
        logical, intent(in), optional :: stick, reports
        real, intent(in), optional :: content
        type(fortui_context_t), pointer :: ctx
        character(len=:), allocatable :: full, v
        real :: offset, x, y, w, h, total
        logical :: follow, report
        integer :: st
        ctx => get_default_context()
        if (.not. composing(ctx)) return
        follow = .false.
        if (present(stick)) follow = stick
        report = .false.
        if (present(reports)) report = reports
        full = scoped_id(id)
        st = ctx%state(full)
        associate(s => ctx%states(st))
            if (present(content)) s%content = content
            offset = s%scroll
            if (input_host_value(ctx%input, full, v)) then
                offset = parse_number(v, offset)
                s%at_end = offset >= s%content - height - 2.0
            end if
            call layout_get_cursor(x, y)
            call layout_available(w, h)
            if (ctx%input%wheel /= 0.0 .and. wheel_target(ctx) == full .and. &
                input_hovered(ctx%input, x, y, w, height)) then
                offset = offset - ctx%input%wheel * WHEEL_STEP
                s%at_end = offset >= s%content - height - 1.0
                ctx%followup = .true.
            end if
            total = max(0.0, s%content - height)
            if (follow .and. s%at_end) offset = total
            offset = max(0.0, min(total, offset))
            s%scroll = offset
        end associate
        if (open_count < MAX_OPEN) then
            open_count = open_count + 1
            open_state(open_count) = st
            open_height(open_count) = height
            open_stick(open_count) = follow
        end if
        call scroll_region_begin(id, height, offset, follow, report)
    end subroutine scroll_begin

    function wheel_target(ctx) result(id)
        !! The scroll container the wheel turns: the innermost one under the
        !! pointer in the last frame, unless a control there scrolls itself.
        type(fortui_context_t), intent(in) :: ctx
        character(len=:), allocatable :: id
        integer :: i, k
        id = ''
        if (len_trim(ctx%input%scroll_id) > 0) then
            k = ctx%previous_frame%find(trim(ctx%input%scroll_id))
            if (k > 0) then
                select case (ctx%previous_frame%nodes(k)%kind)
                case (UI_SCROLL_TEXT, UI_LIST_BOX, UI_TEXT_AREA, UI_CANVAS)
                    return
                end select
            end if
        end if
        do i = ctx%previous_frame%box_count, 1, -1
            associate(b => ctx%previous_frame%boxes(i))
                if (b%kind /= KIND_SCROLL) cycle
                if (.not. input_hovered(ctx%input, b%bounds(1), b%bounds(2), b%bounds(3), &
                    b%bounds(4))) cycle
                id = trim(b%id)
                return
            end associate
        end do
    end function wheel_target

    subroutine scroll_end()
        !! Close the innermost scroll container.
        type(fortui_context_t), pointer :: ctx
        real :: content
        content = scroll_region_end()
        ctx => get_default_context()
        if (.not. associated(ctx) .or. open_count == 0) return
        associate(s => ctx%states(open_state(open_count)))
            if (content /= s%content) then
                ! What it holds changed: a view at the end follows it next frame.
                if (open_stick(open_count) .and. s%at_end) ctx%followup = .true.
                s%content = content
            end if
            if (.not. open_stick(open_count)) &
                s%at_end = s%scroll >= s%content - open_height(open_count) - 1.0
        end associate
        open_count = open_count - 1
    end subroutine scroll_end

    subroutine virtual_list_begin(id, count, row_height, height, first, last, stick)
        !! A scroll container of `count` rows of `row_height` each that composes
        !! only rows `first` to `last`, those in view and a few beyond: lists of
        !! any length at the cost of a screenful. Compose each row in a container
        !! of exactly `row_height` (row_begin(height=row_height)).
        character(*), intent(in) :: id
        integer, intent(in) :: count
        real, intent(in) :: row_height, height
        integer, intent(out) :: first, last
        logical, intent(in), optional :: stick
        type(fortui_context_t), pointer :: ctx
        real :: rh, offset
        rh = max(1.0, row_height)
        call scroll_begin(id, height, stick, content=real(count) * rh, reports=.true.)
        ctx => get_default_context()
        first = 1
        last = 0
        if (.not. associated(ctx) .or. open_count == 0) return
        offset = ctx%states(open_state(open_count))%scroll
        first = max(1, int(offset / rh) + 1 - OVERSCAN)
        last = min(count, int((offset + height) / rh) + 1 + OVERSCAN)
        call layout_set_padding(real(first - 1) * rh, real(max(0, count - last)) * rh)
    end subroutine virtual_list_begin

    subroutine virtual_list_end()
        call scroll_end()
    end subroutine virtual_list_end

    ! --- data grid ------------------------------------------------------------------------

    logical function data_grid(id, columns, cells, state, height, widths, row_height) &
            result(changed)
        !! A table of `cells(column, row)` under `columns`: a click on a heading
        !! sorts by that column (again: the other way), the filter keeps rows
        !! that contain its text in any cell, a click on a row selects it. Only
        !! the rows in view are composed. Numbers sort as numbers. Returns
        !! whether the selection changed; `state%selected` is an index of the
        !! given rows.
        character(*), intent(in) :: id, columns(:), cells(:, :)
        type(grid_state_t), intent(inout) :: state
        real, intent(in) :: height
        real, intent(in), optional :: widths(:), row_height
        real, allocatable :: w(:)
        real :: rh, size_l
        integer :: nc, nr, j, r, i, first, last, old
        character(len=:), allocatable :: sym
        changed = .false.
        nc = size(columns)
        nr = size(cells, 2)
        old = state%selected
        if (.not. allocated(state%filter)) state%filter = ''
        size_l = label_size()
        rh = ui_control_height()
        if (present(row_height)) rh = row_height
        allocate (w(nc))
        if (present(widths)) then
            w = widths(1:nc)
        else
            do j = 1, nc
                w(j) = text_width(trim(columns(j)), size_l) + icon_size(size_l) + ICON_GAP + &
                    2.0 * ui_control_padding()
                do r = 1, min(nr, 200)
                    w(j) = max(w(j), text_width(trim(cells(j, r)), size_l) + 2.0 * ui_control_padding())
                end do
                w(j) = min(w(j), 240.0)
            end do
        end if
        call column_begin(4.0, id=id, look="fui-grid")
        call row_begin(8.0, height=ui_control_height())
        call icon('search', tone=UI_TONE_MUTED)
        if (text_input("filter", state%filter, placeholder="Filter", &
            width=min(280.0, layout_fill_width()))) state%dirty = .true.
        call grid_order(state, cells)
        call text(ui_str(size(state%order)) // " / " // ui_str(nr), style=UI_CAPTION, &
            tone=UI_TONE_MUTED)
        call row_end()
        call row_begin(0.0, look="fui-grid-head")
        do j = 1, nc
            sym = 'remove'
            if (state%sort_column == j) sym = merge('arrow-down', 'arrow-up  ', state%descending)
            if (state%sort_column /= j) then
                if (button("head", trim(columns(j)), key=j, emphasis=UI_EMPHASIS_QUIET, width=w(j), &
                    look="fui-grid-head")) then
                    state%sort_column = j
                    state%descending = .false.
                end if
            else
                if (button("head", trim(columns(j)), key=j, emphasis=UI_EMPHASIS_QUIET, width=w(j), &
                    look="fui-grid-head", icon=trim(sym))) state%descending = .not. state%descending
            end if
        end do
        call row_end()
        call grid_order(state, cells)
        call virtual_list_begin("rows", size(state%order), rh, height, first, last)
        do r = first, last
            i = state%order(r)
            call row_begin(0.0, height=rh, look=merge("fui-grid-row-selected", "fui-grid-row         ", &
                i == state%selected))
            if (button("row", trim(cells(1, i)), key=i, emphasis=UI_EMPHASIS_QUIET, width=w(1), &
                pressed=i == state%selected, ellipsis=.true., look="fui-grid-cell")) state%selected = i
            do j = 2, nc
                call text(trim(cells(j, i)), width=w(j), ellipsis=.true., look="fui-grid-cell")
            end do
            call row_end()
        end do
        call virtual_list_end()
        call column_end()
        changed = state%selected /= old
    end function data_grid

    subroutine grid_order(state, cells)
        !! The rows shown: those matching the filter, stably sorted.
        type(grid_state_t), intent(inout) :: state
        character(*), intent(in) :: cells(:, :)
        integer :: nr, nc, r, n
        integer, allocatable :: keep(:)
        character(len=:), allocatable :: needle
        nc = size(cells, 1)
        nr = size(cells, 2)
        if (.not. state%dirty .and. nr > GRID_ALWAYS .and. allocated(state%order) .and. &
            allocated(state%seen_filter)) then
            if (state%seen_rows == nr .and. state%seen_columns == nc .and. &
                state%seen_column == state%sort_column .and. &
                (state%seen_descending .eqv. state%descending) .and. &
                state%seen_filter == state%filter) return
        end if
        needle = lower(trim(state%filter))
        allocate (keep(nr))
        n = 0
        do r = 1, nr
            if (len(needle) > 0) then
                if (.not. any_cell(r)) cycle
            end if
            n = n + 1
            keep(n) = r
        end do
        state%order = keep(1:n)
        if (state%sort_column >= 1 .and. state%sort_column <= nc .and. n > 1) &
            call merge_sort(state%order, cells(state%sort_column, :), state%descending)
        if (state%selected > nr) state%selected = 0
        state%dirty = .false.
        state%seen_rows = nr
        state%seen_columns = nc
        state%seen_column = state%sort_column
        state%seen_descending = state%descending
        state%seen_filter = state%filter

    contains

        logical function any_cell(row)
            integer, intent(in) :: row
            integer :: j
            any_cell = .false.
            do j = 1, nc
                if (index(lower(trim(cells(j, row))), needle) > 0) then
                    any_cell = .true.
                    return
                end if
            end do
        end function any_cell

    end subroutine grid_order

    subroutine merge_sort(order, keys, descending)
        !! Stable sort of `order` by keys(order(:)).
        integer, intent(inout) :: order(:)
        character(*), intent(in) :: keys(:)
        logical, intent(in) :: descending
        integer, allocatable :: tmp(:)
        real, allocatable :: num(:)
        logical, allocatable :: isnum(:)
        integer :: width, lo, mid, hi, i, j, k, n
        n = size(order)
        allocate (tmp(n), num(size(keys)), isnum(size(keys)))
        do i = 1, size(keys)
            num(i) = parse_number(trim(adjustl(keys(i))), huge(1.0))
            isnum(i) = num(i) /= huge(1.0)
        end do
        width = 1
        do while (width < n)
            lo = 1
            do while (lo <= n)
                mid = min(lo + width, n + 1)
                hi = min(lo + 2 * width, n + 1)
                i = lo
                j = mid
                k = lo
                do while (i < mid .and. j < hi)
                    if (before(order(j), order(i))) then
                        tmp(k) = order(j)
                        j = j + 1
                    else
                        tmp(k) = order(i)
                        i = i + 1
                    end if
                    k = k + 1
                end do
                do while (i < mid)
                    tmp(k) = order(i)
                    i = i + 1
                    k = k + 1
                end do
                do while (j < hi)
                    tmp(k) = order(j)
                    j = j + 1
                    k = k + 1
                end do
                lo = hi
            end do
            order = tmp
            width = 2 * width
        end do

    contains

        logical function before(a, b)
            !! Strictly before: equal keys keep their order.
            integer, intent(in) :: a, b
            if (isnum(a) .and. isnum(b)) then
                before = num(a) < num(b)
                if (descending) before = num(a) > num(b)
            else if (isnum(a) .neqv. isnum(b)) then
                ! Numbers before text, either way.
                before = isnum(a)
            else
                before = llt(lower(trim(keys(a))), lower(trim(keys(b))))
                if (descending) before = lgt(lower(trim(keys(a))), lower(trim(keys(b))))
            end if
        end function before

    end subroutine merge_sort

    pure function lower(s) result(t)
        character(*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: i, c
        t = s
        do i = 1, len(s)
            c = iachar(s(i:i))
            if (c >= 65 .and. c <= 90) t(i:i) = achar(c + 32)
        end do
    end function lower

end module fortui_controls
