module fortui_html
    !! A composed frame as HTML, as the browser backend's host would build it:
    !! the same elements, classes, styles and data-keys. A server composes the
    !! first frame of a page (with the headless backend) and sends this HTML, so
    !! the page shows before any script runs; the browser backend then adopts the
    !! elements by key instead of rebuilding them.
    use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_LINK, UI_SLIDER, &
        UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, UI_TEXT_AREA, &
        WIDTH_FIXED, &
        WIDTH_FILL
    use fortui_layout, only: KIND_ROW, KIND_SPLIT, KIND_PANE
    use fortui_text, only: ui_str
    use fortui_context, only: fortui_context_t, get_default_context
    implicit none
    private

    public :: frame_to_html, html_escape, ui_frame_html

contains

    function frame_to_html(frame) result(html)
        !! The root container with everything in it.
        type(ui_frame_t), intent(in) :: frame
        character(len=:), allocatable :: html
        character(len=:), allocatable :: keys(:), buf
        integer, allocatable :: anon(:), node_first(:), node_next(:), box_first(:), box_next(:)
        integer :: i, p, used

        ! Keys as the host makes them: kind:id, or kind:~n for the n-th node
        ! without id of that kind.
        allocate (character(len=128) :: keys(frame%count))
        allocate (anon(0:16))
        anon = 0
        do i = 1, frame%count
            associate (n => frame%nodes(i))
                if (len_trim(n%id) == 0) then
                    anon(n%kind) = anon(n%kind) + 1
                    keys(i) = ui_str(n%kind)//':~'//ui_str(anon(n%kind))
                else
                    keys(i) = ui_str(n%kind)//':'//trim(n%id)
                end if
            end associate
        end do
        ! Nodes and boxes of each container in composition order, as linked lists.
        allocate (node_first(0:frame%box_count), node_next(frame%count))
        allocate (box_first(0:frame%box_count), box_next(frame%box_count))
        node_first = 0
        box_first = 0
        do i = frame%count, 1, -1
            p = frame%nodes(i)%box
            node_next(i) = node_first(p)
            node_first(p) = i
        end do
        do i = frame%box_count, 1, -1
            p = frame%boxes(i)%parent
            box_next(i) = box_first(p)
            box_first(p) = i
        end do
        ! The page grows in one buffer that doubles, so its length costs linear time.
        allocate (character(len=4096) :: buf)
        used = 0
        call put('<div class="fui-root fui-box fui-col">')
        call children(0)
        call put('</div>')
        html = buf(1:used)

    contains

        subroutine put(s)
            character(len=*), intent(in) :: s
            character(len=:), allocatable :: grown
            if (used + len(s) > len(buf)) then
                allocate (character(len=max(2 * len(buf), used + len(s))) :: grown)
                grown(1:used) = buf(1:used)
                call move_alloc(grown, buf)
            end if
            buf(used + 1:used + len(s)) = s
            used = used + len(s)
        end subroutine put

        recursive subroutine children(parent)
            !! Boxes and nodes of `parent` in composition order: a box opened after
            !! node c comes between node c and node c + 1.
            integer, intent(in) :: parent
            integer :: b, k

            b = box_first(parent)
            k = node_first(parent)
            do while (b > 0 .or. k > 0)
                if (b > 0 .and. k > 0) then
                    if (frame%boxes(b)%after < k) then
                        call box_html(b)
                        b = box_next(b)
                    else
                        call put(node_html(k, in_row(parent)))
                        k = node_next(k)
                    end if
                else if (b > 0) then
                    call box_html(b)
                    b = box_next(b)
                else
                    call put(node_html(k, in_row(parent)))
                    k = node_next(k)
                end if
            end do
        end subroutine children

        recursive subroutine box_html(b)
            integer, intent(in) :: b
            character(len=:), allocatable :: s, style, cls

            associate (x => frame%boxes(b))
                cls = 'fui-box fui-col'
                if (x%kind == KIND_ROW .or. x%kind == KIND_SPLIT) cls = 'fui-box fui-row'
                style = 'gap: '//ui_str(nint(x%gap))//'px;'
                if (x%cross > 0.0) style = style//' min-height: '//ui_str(nint(x%cross))//'px;'
                if (x%kind == KIND_PANE .and. x%width >= 0.0) style = style//' width: '// &
                    ui_str(nint(x%width))//'px; flex: 0 0 auto;'
            end associate
            s = '<div data-key="b'//ui_str(b)//'" class="'//cls//'"'
            if (len_trim(frame%boxes(b)%id) > 0) s = s//' data-box="'// &
                html_escape(trim(frame%boxes(b)%id))//'"'
            s = s//marks(frame%boxes(b)%look, frame%boxes(b)%anchor)
            call put(s//' style="'//style//'">')
            call children(b)
            call put('</div>')
        end subroutine box_html

        logical function in_row(b)
            integer, intent(in) :: b
            in_row = .false.
            if (b > 0) in_row = frame%boxes(b)%kind == KIND_ROW .or. &
                frame%boxes(b)%kind == KIND_SPLIT
        end function in_row

        function node_html(k, row) result(s)
            integer, intent(in) :: k
            logical, intent(in) :: row
            character(len=:), allocatable :: s, a, style, text, body

            associate (n => frame%nodes(k))
                text = html_escape(trim(n%text))
                body = ''
                if (allocated(n%body)) body = html_escape(n%body)
                a = ' class="fui fui-k'//ui_str(n%kind)
                if ((n%kind == UI_TEXT .or. n%kind == UI_LINK) .and. n%ellipsis) a = a//' fui-ellipsis'
                a = a//'" data-key="'//html_escape(trim(keys(k)))//'"'
                if (len_trim(n%id) > 0) a = a//' data-id="'//html_escape(trim(n%id))//'"'
                a = a//' data-style="'//ui_str(n%style)//'" data-tone="'//ui_str(n%tone)//'"'
                a = a//marks(n%look, n%anchor)
                if (n%disabled) a = a//' disabled'
                ! The control with the focus (ui_focus) has it when the page loads.
                if (n%focused .and. n%kind /= UI_CHECKBOX .and. n%kind /= UI_SCROLL_TEXT) &
                    a = a//' autofocus'
                style = 'font-size: '//ui_str(nint(n%text_size))//'px;'//width_style(n, row)
                select case (n%kind)
                case (UI_BUTTON, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT)
                    style = style//' height: '//ui_str(nint(n%height))//'px;'
                end select
                a = a//' style="'//style//'"'
                select case (n%kind)
                case (UI_BUTTON)
                    s = '<button type="button"'//a//'>'//text//'</button>'
                case (UI_LINK)
                    s = '<a href="'//body//'"'//a//'>'//text//'</a>'
                case (UI_TAB)
                    if (n%checked) then
                        s = '<button type="button" role="tab" aria-selected="true"'
                    else
                        s = '<button type="button" role="tab" aria-selected="false"'
                    end if
                    s = s//a//'>'//text//'</button>'
                case (UI_SLIDER)
                    s = '<input type="range" step="any" min="'//ui_str(n%min_value, 4)// &
                        '" max="'//ui_str(n%max_value, 4)//'" value="'//ui_str(n%value, 4)// &
                        '"'//a//'>'
                case (UI_CHECKBOX)
                    s = '<label'//a//'><input type="checkbox"'
                    if (n%checked) s = s//' checked'
                    if (n%focused) s = s//' autofocus'
                    s = s//'><span>'//text//'</span></label>'
                case (UI_CANVAS)
                    s = '<canvas width="'//ui_str(nint(n%width))//'" height="'// &
                        ui_str(nint(n%height))//'"'//a//'></canvas>'
                case (UI_SCROLL_TEXT)
                    s = '<div'//a//'>'//body//'</div>'
                case (UI_TEXT_INPUT)
                    s = '<input type="text" value="'//body//'" placeholder="'//text//'"'//a//'>'
                case (UI_TEXT_AREA)
                    s = '<textarea rows="'//ui_str(n%line_count)//'" placeholder="'//text//'"'// &
                        a//'>'//body//'</textarea>'
                case default
                    if (allocated(n%run_end)) text = runs_html(trim(n%text), n%run_end, n%run_tone)
                    s = '<div'//a//'>'//text//'</div>'
                end select
            end associate
        end function node_html

    end function frame_to_html

    function ui_frame_html() result(html)
        !! The last presented frame of the running application as HTML.
        character(len=:), allocatable :: html
        type(fortui_context_t), pointer :: ctx

        html = ''
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        html = frame_to_html(ctx%previous_frame)
    end function ui_frame_html

    function runs_html(text, ends, tones) result(s)
        !! Rich text as spans, as the browser host builds it.
        character(len=*), intent(in) :: text
        integer, intent(in) :: ends(:), tones(:)
        character(len=:), allocatable :: s
        integer :: k, at, e

        s = ''
        at = 0
        do k = 1, size(ends)
            e = min(ends(k), len(text))
            if (e <= at) cycle
            if (tones(k) /= 0) then
                s = s//'<span data-t="'//ui_str(tones(k))//'">'//html_escape(text(at + 1:e))//'</span>'
            else
                s = s//'<span>'//html_escape(text(at + 1:e))//'</span>'
            end if
            at = e
        end do
        if (at < len(text)) s = s//html_escape(text(at + 1:))
    end function runs_html

    function marks(look, anchor) result(s)
        !! The style name as data-look and the page address as id, where given.
        character(len=*), intent(in) :: look, anchor
        character(len=:), allocatable :: s

        s = ''
        if (len_trim(look) > 0) s = s//' data-look="'//html_escape(trim(look))//'"'
        if (len_trim(anchor) > 0) s = s//' id="'//html_escape(trim(anchor))//'"'
    end function marks

    function width_style(n, row) result(s)
        !! As the host sizes elements: fixed width, filling the container, or natural.
        type(ui_node_t), intent(in) :: n
        logical, intent(in) :: row
        character(len=:), allocatable :: s

        select case (n%width_mode)
        case (WIDTH_FIXED)
            s = ' width: '//ui_str(nint(n%width))//'px; flex: 0 0 auto;'
        case (WIDTH_FILL)
            if (row) then
                s = ' min-width: 0px; flex: 1 1 0px;'
            else
                s = ' min-width: 0px; align-self: stretch;'
            end if
        case default
            s = ' flex: 0 0 auto;'
        end select
    end function width_style

    function html_escape(s) result(r)
        !! Text for HTML content and attribute values.
        character(len=*), intent(in) :: s
        character(len=:), allocatable :: r
        integer :: i, n

        n = 0
        do i = 1, len(s)
            select case (s(i:i))
            case ('&'); n = n + 5
            case ('<', '>'); n = n + 4
            case ('"'); n = n + 6
            case default; n = n + 1
            end select
        end do
        allocate (character(len=n) :: r)
        n = 0
        do i = 1, len(s)
            select case (s(i:i))
            case ('&'); r(n + 1:n + 5) = '&amp;'; n = n + 5
            case ('<'); r(n + 1:n + 4) = '&lt;'; n = n + 4
            case ('>'); r(n + 1:n + 4) = '&gt;'; n = n + 4
            case ('"'); r(n + 1:n + 6) = '&quot;'; n = n + 6
            case default; r(n + 1:n + 1) = s(i:i); n = n + 1
            end select
        end do
    end function html_escape

end module fortui_html
