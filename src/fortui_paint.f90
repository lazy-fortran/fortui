module fortui_paint
    !! Theme painters: a semantic frame becomes a display list in physical pixels.
    !!
    !! Every graphical backend draws the same list, so a theme looks the same on
    !! all of them. Coordinates are physical pixels; edges of solid rectangles lie
    !! on whole pixels, so one-pixel lines stay one pixel wide and sharp. The
    !! classic painter draws Windows 95 controls from 1 px lines (2 px at scale 2);
    !! the material painter draws Material Design 3 shapes with antialiased edges.
    !!
    !! Commands: filled rectangles with optional corner radius, border and a
    !! one-pixel checker pattern (dotted focus rectangles, scroll tracks), thick
    !! line segments, text runs (face, pixel size, colour; `h` is the line box),
    !! clip push/pop, and canvas nodes the backend realizes itself.
    use iso_fortran_env, only: int32
    use fortui_theme, only: theme, STYLE_CLASSIC, FACE_REGULAR, FACE_STRONG, FACE_MONO, &
        ROLE_LABEL
    use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_LINK, UI_SLIDER, &
        UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, UI_TEXT_AREA, &
        UI_CAPTION, UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, &
        UI_TONE_ACCENT, UI_TONE_KEYWORD, UI_TONE_HUNK, UI_TONE_LINK, UI_TONE_ATTENTION, &
        UI_EMPHASIS_PRIMARY, UI_EMPHASIS_QUIET, style_weight
    use fortui_text, only: text_width, text_fit, text_line_height, TEXT_STYLE_REGULAR, &
        TEXT_STYLE_BOLD, TEXT_STYLE_MONO
    implicit none
    private

    integer, parameter, public :: PAINT_RECT = 1, PAINT_LINE = 2, PAINT_TEXT = 3, &
        PAINT_CLIP = 4, PAINT_UNCLIP = 5, PAINT_CANVAS = 6
    integer, parameter, public :: PATTERN_NONE = 0, PATTERN_CHECKER = 1

    type, public :: paint_cmd_t
        integer :: kind = 0
        !! Rectangle, clip, canvas and text box; a line runs from (x, y) to (w, h).
        real :: x = 0.0, y = 0.0, w = 0.0, h = 0.0
        real :: radius = 0.0
        !! Border width (rectangles) or thickness (lines), in pixels.
        real :: border = 0.0
        integer(int32) :: fill = 0, stroke = 0
        !! PATTERN_CHECKER: `fill` on pixels with even x + y, `stroke` on the others.
        integer :: pattern = PATTERN_NONE
        integer :: text_first = 0, text_last = -1
        integer :: face = FACE_REGULAR
        real :: size = 0.0
        integer :: node = 0
    end type paint_cmd_t

    type, public :: paint_list_t
        type(paint_cmd_t), allocatable :: cmds(:)
        integer :: n = 0
        character(len=:), allocatable :: pool
        integer :: pool_len = 0
        real :: scale = 1.0
        integer(int32) :: background = 0
    contains
        procedure :: clear => list_clear
        procedure :: add => list_add
        procedure :: text_of => list_text_of
    end type paint_list_t

    public :: paint_frame, paint_face, face_weight

    ! State of the frame being painted.
    real :: s = 1.0, u = 1.0

contains

    ! --- list ----------------------------------------------------------------------

    subroutine list_clear(self)
        class(paint_list_t), intent(inout) :: self
        self%n = 0
        self%pool_len = 0
        if (.not. allocated(self%cmds)) allocate(self%cmds(256))
        if (.not. allocated(self%pool)) allocate(character(len=4096) :: self%pool)
    end subroutine list_clear

    subroutine list_add(self, cmd, text)
        class(paint_list_t), intent(inout) :: self
        type(paint_cmd_t), intent(in) :: cmd
        character(*), intent(in), optional :: text
        type(paint_cmd_t), allocatable :: grown(:)
        character(len=:), allocatable :: bigger

        if (self%n == size(self%cmds)) then
            allocate(grown(2 * size(self%cmds)))
            grown(1:self%n) = self%cmds(1:self%n)
            call move_alloc(grown, self%cmds)
        end if
        self%n = self%n + 1
        self%cmds(self%n) = cmd
        if (present(text)) then
            if (self%pool_len + len(text) > len(self%pool)) then
                allocate(character(len=2 * (len(self%pool) + len(text))) :: bigger)
                bigger(1:self%pool_len) = self%pool(1:self%pool_len)
                call move_alloc(bigger, self%pool)
            end if
            self%cmds(self%n)%text_first = self%pool_len + 1
            self%cmds(self%n)%text_last = self%pool_len + len(text)
            if (len(text) > 0) self%pool(self%pool_len + 1:self%pool_len + len(text)) = text
            self%pool_len = self%pool_len + len(text)
        end if
    end subroutine list_add

    function list_text_of(self, k) result(t)
        class(paint_list_t), intent(in) :: self
        integer, intent(in) :: k
        character(len=:), allocatable :: t
        t = self%pool(self%cmds(k)%text_first:self%cmds(k)%text_last)
    end function list_text_of

    pure integer function paint_face(weight) result(face)
        !! Font face of a TEXT_STYLE_* weight.
        integer, intent(in) :: weight
        face = FACE_REGULAR
        if (weight == TEXT_STYLE_BOLD) face = FACE_STRONG
        if (weight == TEXT_STYLE_MONO) face = FACE_MONO
    end function paint_face

    pure integer function face_weight(face) result(weight)
        integer, intent(in) :: face
        weight = TEXT_STYLE_REGULAR
        if (face == FACE_STRONG) weight = TEXT_STYLE_BOLD
        if (face == FACE_MONO) weight = TEXT_STYLE_MONO
    end function face_weight

    ! --- primitives (physical pixels) ------------------------------------------------

    subroutine rect(list, x, y, w, h, c, radius, border, stroke, pattern, stroke_only)
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        integer(int32), intent(in) :: c
        real, intent(in), optional :: radius, border
        integer(int32), intent(in), optional :: stroke
        integer, intent(in), optional :: pattern
        logical, intent(in), optional :: stroke_only
        type(paint_cmd_t) :: cmd

        if (w <= 0.0 .or. h <= 0.0) return
        cmd%kind = PAINT_RECT
        cmd%x = x
        cmd%y = y
        cmd%w = w
        cmd%h = h
        cmd%fill = c
        if (present(radius)) cmd%radius = radius
        if (present(border)) cmd%border = border
        if (present(stroke)) cmd%stroke = stroke
        if (present(pattern)) cmd%pattern = pattern
        if (present(stroke_only)) then
            if (stroke_only) cmd%fill = 0
        end if
        call list%add(cmd)
    end subroutine rect

    subroutine line(list, x0, y0, x1, y1, width, c)
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x0, y0, x1, y1, width
        integer(int32), intent(in) :: c
        type(paint_cmd_t) :: cmd
        cmd%kind = PAINT_LINE
        cmd%x = x0
        cmd%y = y0
        cmd%w = x1
        cmd%h = y1
        cmd%border = width
        cmd%fill = c
        call list%add(cmd)
    end subroutine line

    subroutine text_run(list, str, x, y, line_h, face, size_px, c)
        !! Text whose line box starts at (x, y) and is `line_h` tall.
        type(paint_list_t), intent(inout) :: list
        character(*), intent(in) :: str
        real, intent(in) :: x, y, line_h, size_px
        integer, intent(in) :: face
        integer(int32), intent(in) :: c
        type(paint_cmd_t) :: cmd
        if (len(str) == 0) return
        cmd%kind = PAINT_TEXT
        cmd%x = real(nint(x))
        cmd%y = real(nint(y))
        cmd%w = 0.0
        cmd%h = line_h
        cmd%face = face
        cmd%size = size_px
        cmd%fill = c
        call list%add(cmd, str)
    end subroutine text_run

    subroutine clip(list, x, y, w, h)
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        type(paint_cmd_t) :: cmd
        cmd%kind = PAINT_CLIP
        cmd%x = x
        cmd%y = y
        cmd%w = max(0.0, w)
        cmd%h = max(0.0, h)
        call list%add(cmd)
    end subroutine clip

    subroutine unclip(list)
        type(paint_list_t), intent(inout) :: list
        type(paint_cmd_t) :: cmd
        cmd%kind = PAINT_UNCLIP
        call list%add(cmd)
    end subroutine unclip

    pure integer(int32) function with_alpha(c, a) result(out)
        !! `c` with alpha 0..255.
        integer(int32), intent(in) :: c
        integer, intent(in) :: a
        out = ior(iand(c, int(z'00FFFFFF', int32)), ishft(int(iand(a, 255), int32), 24))
    end function with_alpha

    pure integer(int32) function over(base, top, a) result(out)
        !! `top` at opacity a/255 over the opaque `base` (state layers).
        integer(int32), intent(in) :: base, top
        integer, intent(in) :: a
        integer :: k, b, t
        out = ior(0_int32, ishft(255_int32, 24))
        do k = 0, 2
            b = int(iand(ishft(base, -8 * k), 255_int32))
            t = int(iand(ishft(top, -8 * k), 255_int32))
            out = ior(out, ishft(int((b * (255 - a) + t * a + 127) / 255, int32), 8 * k))
        end do
    end function over

    ! --- frame -----------------------------------------------------------------------

    subroutine paint_frame(frame, scale, width, height, list)
        !! Display list of `frame` for a window of `width` x `height` pixels at
        !! `scale` pixels per logical unit, in the current theme.
        type(ui_frame_t), intent(in) :: frame
        real, intent(in) :: scale, width, height
        type(paint_list_t), intent(inout) :: list
        integer :: i

        call list%clear()
        list%scale = scale
        s = scale
        u = max(1.0, real(nint(scale)))
        list%background = theme%window
        call rect(list, 0.0, 0.0, width, height, theme%window)
        do i = 1, frame%count
            call paint_node(list, frame, frame%nodes(i), i)
        end do
    end subroutine paint_frame

    pure real function px(v)
        !! Logical coordinate to the nearest whole pixel.
        real, intent(in) :: v
        px = real(nint(v * s))
    end function px

    subroutine node_box(node, x, y, w, h)
        type(ui_node_t), intent(in) :: node
        real, intent(out) :: x, y, w, h
        x = px(node%x)
        y = px(node%y)
        w = max(1.0, px(node%x + node%width) - x)
        h = max(1.0, px(node%y + node%height) - y)
    end subroutine node_box

    integer(int32) function tone_colour(tone) result(c)
        integer, intent(in) :: tone
        select case (tone)
        case (UI_TONE_POSITIVE); c = theme%positive
        case (UI_TONE_NEGATIVE); c = theme%negative
        case (UI_TONE_MUTED); c = theme%on_surface_muted
        case (UI_TONE_ACCENT); c = theme%primary
        case (UI_TONE_LINK); c = theme%link
        case (UI_TONE_ATTENTION); c = theme%attention
        case (UI_TONE_KEYWORD:UI_TONE_HUNK); c = theme%code(tone - UI_TONE_KEYWORD + 1)
        case default; c = theme%on_surface
        end select
    end function tone_colour

    subroutine label(list, str, x, y, h, size_l, weight, c, align_center, avail)
        !! One line of text vertically centred in [y, y + h) (pixels), from
        !! logical size `size_l`; centred horizontally in `avail` when asked.
        type(paint_list_t), intent(inout) :: list
        character(*), intent(in) :: str
        real, intent(in) :: x, y, h, size_l
        integer, intent(in) :: weight
        integer(int32), intent(in) :: c
        logical, intent(in), optional :: align_center
        real, intent(in), optional :: avail
        real :: lh, tx
        lh = real(nint(text_line_height(size_l) * s))
        tx = x
        if (present(align_center) .and. present(avail)) then
            if (align_center) tx = x + real(floor(0.5 * (avail - text_width(str, size_l, &
                weight) * s)))
        end if
        call text_run(list, str, tx, y + real(floor(0.5 * (h - lh))), lh, paint_face(weight), &
            size_l * s, c)
    end subroutine label

    subroutine paint_node(list, frame, node, index)
        type(paint_list_t), intent(inout) :: list
        type(ui_frame_t), intent(in) :: frame
        type(ui_node_t), intent(in) :: node
        integer, intent(in) :: index
        type(paint_cmd_t) :: cmd

        select case (node%kind)
        case (UI_TEXT, UI_LINK)
            call paint_text_node(list, node)
        case (UI_BUTTON)
            if (theme%kind == STYLE_CLASSIC) then
                call classic_button(list, node)
            else
                call material_button(list, node)
            end if
        case (UI_CHECKBOX)
            if (theme%kind == STYLE_CLASSIC) then
                call classic_checkbox(list, node)
            else
                call material_checkbox(list, node)
            end if
        case (UI_SLIDER)
            if (theme%kind == STYLE_CLASSIC) then
                call classic_slider(list, node)
            else
                call material_slider(list, node)
            end if
        case (UI_TAB)
            if (theme%kind == STYLE_CLASSIC) then
                call classic_tab(list, node)
            else
                call material_tab(list, node)
            end if
        case (UI_TEXT_INPUT, UI_TEXT_AREA)
            call paint_field(list, node)
        case (UI_SCROLL_TEXT)
            call paint_scroll_text(list, node)
        case (UI_CANVAS)
            call node_box(node, cmd%x, cmd%y, cmd%w, cmd%h)
            cmd%kind = PAINT_CANVAS
            cmd%node = index
            cmd%fill = node%fill
            call list%add(cmd)
        end select
        if (frame%count < 0) return
    end subroutine paint_node

    ! --- text ------------------------------------------------------------------------

    subroutine paint_text_node(list, node)
        !! Text and links, with tone runs (code, diffs) and an underline for links.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, tx, lh
        integer :: weight, k, first, last
        integer(int32) :: c
        character(len=:), allocatable :: str

        call node_box(node, x, y, w, h)
        weight = style_weight(node%style)
        c = tone_colour(node%tone)
        if (node%style == UI_CAPTION .and. node%tone == UI_TONE_NORMAL) &
            c = theme%on_surface_muted
        if (node%kind == UI_LINK) c = theme%link
        if (node%disabled) c = theme%disabled
        str = trim(node%text)
        if (node%ellipsis) str = text_fit(str, node%text_size, node%width, weight)
        lh = real(nint(text_line_height(node%text_size) * s))
        if (allocated(node%run_end) .and. .not. node%ellipsis) then
            tx = x
            first = 1
            do k = 1, size(node%run_end)
                last = min(len(str), node%run_end(k))
                if (last >= first) then
                    call label(list, str(first:last), tx, y, h, node%text_size, weight, &
                        tone_colour(node%run_tone(k)))
                    tx = tx + text_width(str(first:last), node%text_size, weight) * s
                end if
                first = last + 1
            end do
            if (first <= len(str)) call label(list, str(first:), tx, y, h, node%text_size, &
                weight, c)
        else
            call label(list, str, x, y, h, node%text_size, weight, c)
        end if
        if (node%kind == UI_LINK) then
            call rect(list, x, y + real(floor(0.5 * (h - lh))) + lh - u, real(nint( &
                text_width(str, node%text_size, weight) * s)), u, c)
            if (node%focused) call focus_rect(list, x - u, y, &
                real(nint(text_width(str, node%text_size, weight) * s)) + 2.0 * u, h)
        end if
    end subroutine paint_text_node

    subroutine focus_rect(list, x, y, w, h)
        !! Keyboard focus: a dotted rectangle (classic) or a 3 px ring (material).
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        if (theme%kind == STYLE_CLASSIC) then
            call rect(list, x, y, w, u, theme%focus, stroke=0, pattern=PATTERN_CHECKER)
            call rect(list, x, y + h - u, w, u, theme%focus, stroke=0, &
                pattern=PATTERN_CHECKER)
            call rect(list, x, y + u, u, h - 2.0 * u, theme%focus, stroke=0, &
                pattern=PATTERN_CHECKER)
            call rect(list, x + w - u, y + u, u, h - 2.0 * u, theme%focus, stroke=0, &
                pattern=PATTERN_CHECKER)
        else
            call ring(list, x, y, w, h, 4.0 * s)
        end if
    end subroutine focus_rect

    ! --- classic (Windows 95) ---------------------------------------------------------

    subroutine bevel(list, x, y, w, h, tl_out, br_out, tl_in, br_in)
        !! Two-pixel 3D edge as DrawEdge draws it: top/left lines first, then
        !! bottom/right over the corners, outer pair then inner pair.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        integer(int32), intent(in) :: tl_out, br_out, tl_in, br_in
        call rect(list, x, y, w - u, u, tl_out)
        call rect(list, x, y, u, h - u, tl_out)
        call rect(list, x, y + h - u, w, u, br_out)
        call rect(list, x + w - u, y, u, h, br_out)
        call rect(list, x + u, y + u, w - 3.0 * u, u, tl_in)
        call rect(list, x + u, y + u, u, h - 3.0 * u, tl_in)
        call rect(list, x + u, y + h - 2.0 * u, w - 2.0 * u, u, br_in)
        call rect(list, x + w - 2.0 * u, y + u, u, h - 2.0 * u, br_in)
    end subroutine bevel

    subroutine raised(list, x, y, w, h)
        !! Push button edge: white and black outside, light grey and grey inside.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        call rect(list, x, y, w, h, theme%face)
        call bevel(list, x, y, w, h, theme%hilight, theme%dark_shadow, theme%light, &
            theme%shadow)
    end subroutine raised

    subroutine sunken_field(list, x, y, w, h, fill)
        !! Edit field and check box edge: grey and white outside, black and light
        !! grey inside.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        integer(int32), intent(in) :: fill
        call rect(list, x, y, w, h, fill)
        call bevel(list, x, y, w, h, theme%shadow, theme%hilight, theme%dark_shadow, &
            theme%light)
    end subroutine sunken_field

    subroutine etched_text(list, str, x, y, h, size_l, weight, center, avail)
        !! Disabled text: white copy one pixel down-right, grey on top.
        type(paint_list_t), intent(inout) :: list
        character(*), intent(in) :: str
        real, intent(in) :: x, y, h, size_l, avail
        integer, intent(in) :: weight
        logical, intent(in) :: center
        call label(list, str, x + u, y + u, h, size_l, weight, theme%hilight, center, avail)
        call label(list, str, x, y, h, size_l, weight, theme%shadow, center, avail)
    end subroutine etched_text

    subroutine classic_button(list, node)
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, d, pad
        integer :: weight
        logical :: framed
        character(len=:), allocatable :: str

        call node_box(node, x, y, w, h)
        weight = style_weight(ROLE_LABEL)
        framed = (node%emphasis == UI_EMPHASIS_PRIMARY .or. node%focused) .and. &
            .not. node%disabled
        if (framed) then
            call rect(list, x, y, w, h, theme%dark_shadow)
            x = x + u
            y = y + u
            w = w - 2.0 * u
            h = h - 2.0 * u
        end if
        d = 0.0
        if (node%active .and. node%hovered .and. .not. node%disabled) then
            ! Pressed: a flat grey line inside the black frame, label 1 px down-right.
            call rect(list, x, y, w, h, theme%face)
            call rect(list, x, y, w, u, theme%shadow)
            call rect(list, x, y + h - u, w, u, theme%shadow)
            call rect(list, x, y, u, h, theme%shadow)
            call rect(list, x + w - u, y, u, h, theme%shadow)
            d = u
        else
            call raised(list, x, y, w, h)
        end if
        pad = real(nint(ui_pad() * s))
        str = trim(node%text)
        if (node%ellipsis) str = text_fit(str, node%text_size, (w - 2.0 * pad) / s, weight)
        if (node%disabled) then
            call etched_text(list, str, x + d, y + d, h, node%text_size, weight, .true., w)
        else
            call label(list, str, x + d, y + d, h, node%text_size, weight, theme%on_surface, &
                .true., w)
        end if
        if (node%focused .and. .not. node%disabled) call focus_rect(list, x + 3.0 * u, &
            y + 3.0 * u, w - 6.0 * u, h - 6.0 * u)
    end subroutine classic_button

    real function ui_pad()
        ui_pad = theme%control_padding
    end function ui_pad

    subroutine classic_checkbox(list, node)
        !! 13 px sunken box with the 7 x 7 check glyph; dotted focus around the label.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, b, bx, by, lx, tw
        integer :: weight, r, c0
        integer(int32) :: ink, fill
        ! Check glyph rows (bit k = column k from the left), 7 x 7.
        integer, parameter :: glyph(7) = [1, 3, 71, 110, 124, 56, 16]

        call node_box(node, x, y, w, h)
        weight = style_weight(1)
        b = real(nint(theme%check_size * s))
        bx = x
        by = y + real(floor(0.5 * (h - b)))
        fill = theme%field
        if (node%disabled .or. (node%active .and. node%hovered)) fill = theme%face
        call sunken_field(list, bx, by, b, b, fill)
        ink = theme%on_field
        if (node%disabled) ink = theme%shadow
        if (node%checked) then
            do r = 1, 7
                do c0 = 0, 6
                    if (btest(glyph(r), 6 - c0)) call rect(list, bx + 3.0 * u + c0 * u, &
                        by + 2.0 * u + r * u, u, u, ink)
                end do
            end do
        end if
        lx = bx + b + real(nint(theme%check_gap * s))
        if (len_trim(node%text) == 0) return
        if (node%disabled) then
            call etched_text(list, trim(node%text), lx, y, h, node%text_size, weight, &
                .false., 0.0)
        else
            call label(list, trim(node%text), lx, y, h, node%text_size, weight, &
                theme%on_surface)
        end if
        if (node%focused) then
            tw = real(nint(text_width(trim(node%text), node%text_size, weight) * s))
            call focus_rect(list, lx - u, by - u, tw + 3.0 * u, b + 2.0 * u)
        end if
    end subroutine classic_checkbox

    subroutine classic_slider(list, node)
        !! Trackbar: a 4 px sunken channel and an 11 x 21 raised thumb.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, tw, th, cx, cy, f
        call node_box(node, x, y, w, h)
        tw = real(nint(theme%slider_thumb * s))
        th = min(h - 2.0 * u, real(nint(21.0 * s)))
        cy = y + real(floor(0.5 * h))
        call bevel(list, x + real(floor(0.5 * tw)), cy - 2.0 * u, w - tw, 4.0 * u, &
            theme%shadow, theme%hilight, theme%dark_shadow, theme%light)
        f = slider_fraction(node)
        cx = x + real(nint(f * (w - tw)))
        call pointed_thumb(list, cx, y + real(floor(0.5 * (h - th))), tw, th)
        if (node%focused) call focus_rect(list, x, y, w, h)
    end subroutine classic_slider

    subroutine pointed_thumb(list, x, y, w, h)
        !! Trackbar thumb pointing down: a raised block whose lower part narrows
        !! two pixels per row, white and light grey on the left, black and grey on
        !! the right, as Windows 95 draws it.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h
        real :: tip, body, ty
        integer :: r, n
        n = nint(0.5 * (w / u - 1.0))
        tip = real(n) * u
        body = h - tip
        call rect(list, x, y, w, body, theme%face)
        call rect(list, x, y, w - u, u, theme%hilight)
        call rect(list, x, y, u, body, theme%hilight)
        call rect(list, x + u, y + u, w - 3.0 * u, u, theme%light)
        call rect(list, x + u, y + u, u, body - u, theme%light)
        call rect(list, x + w - u, y, u, body, theme%dark_shadow)
        call rect(list, x + w - 2.0 * u, y + u, u, body - u, theme%shadow)
        do r = 0, n - 1
            ty = y + body + real(r) * u
            call rect(list, x + real(r + 1) * u, ty, w - real(2 * r + 2) * u, u, theme%face)
            call rect(list, x + real(r) * u, ty, u, u, theme%hilight)
            call rect(list, x + real(r + 1) * u, ty, u, u, theme%light)
            call rect(list, x + w - real(r + 1) * u, ty, u, u, theme%dark_shadow)
            call rect(list, x + w - real(r + 2) * u, ty, u, u, theme%shadow)
        end do
        call rect(list, x + real(n) * u, y + body + real(n) * u - u, u, u, theme%dark_shadow)
    end subroutine pointed_thumb

    real function slider_fraction(node)
        type(ui_node_t), intent(in) :: node
        slider_fraction = 0.0
        if (node%max_value > node%min_value) slider_fraction = (node%value - &
            node%min_value) / (node%max_value - node%min_value)
        slider_fraction = max(0.0, min(1.0, slider_fraction))
    end function slider_fraction

    subroutine classic_tab(list, node)
        !! Tab: white left/top edge with cut corners, grey and black on the right;
        !! unselected tabs sit 2 px lower on the panel's white top line.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, top, tw
        integer :: weight
        call node_box(node, x, y, w, h)
        weight = style_weight(ROLE_LABEL)
        top = y
        if (.not. node%checked) then
            top = y + 2.0 * u
            call rect(list, x, y + h - u, w, u, theme%hilight)
        end if
        call rect(list, x, top, w, y + h - top - merge(0.0, u, node%checked), theme%face)
        call rect(list, x, top + 2.0 * u, u, y + h - top - 2.0 * u - merge(0.0, u, &
            node%checked), theme%hilight)
        call rect(list, x + u, top + u, u, u, theme%hilight)
        call rect(list, x + 2.0 * u, top, w - 4.0 * u, u, theme%hilight)
        call rect(list, x + w - 2.0 * u, top + u, u, u, theme%dark_shadow)
        call rect(list, x + w - u, top + 2.0 * u, u, y + h - top - 2.0 * u - &
            merge(0.0, u, node%checked), theme%dark_shadow)
        call rect(list, x + w - 2.0 * u, top + 2.0 * u, u, y + h - top - 2.0 * u - &
            merge(0.0, u, node%checked), theme%shadow)
        call label(list, text_fit(trim(node%text), node%text_size, w / s - 8.0, weight), x, &
            top, y + h - top, node%text_size, weight, merge(theme%shadow, theme%on_surface, &
            node%disabled), .true., w)
        if (node%focused) then
            tw = real(nint(text_width(trim(node%text), node%text_size, weight) * s))
            call focus_rect(list, x + real(floor(0.5 * (w - tw))) - 2.0 * u, top + 3.0 * u, &
                tw + 4.0 * u, y + h - top - 6.0 * u)
        end if
    end subroutine classic_tab

    ! --- material 3 ------------------------------------------------------------------

    subroutine material_button(list, node)
        !! Tonal (normal), filled (primary) or text (quiet) button, fully rounded,
        !! with hover/press state layers and a focus ring.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, r
        integer(int32) :: fill, ink
        integer :: weight, layer
        logical :: filled
        character(len=:), allocatable :: str

        call node_box(node, x, y, w, h)
        weight = style_weight(ROLE_LABEL)
        r = 0.5 * h
        filled = node%emphasis /= UI_EMPHASIS_QUIET
        select case (node%emphasis)
        case (UI_EMPHASIS_PRIMARY)
            fill = theme%primary
            ink = theme%on_primary
        case (UI_EMPHASIS_QUIET)
            fill = theme%window
            ink = theme%primary
        case default
            fill = theme%tonal
            ink = theme%on_tonal
        end select
        layer = 0
        if (node%hovered) layer = 20
        if (node%active) layer = 26
        if (node%focused) layer = max(layer, 26)
        if (node%disabled) then
            if (filled) call rect(list, x, y, w, h, with_alpha(theme%on_surface, 31), radius=r)
            ink = theme%disabled
        else
            if (filled .or. layer > 0) call rect(list, x, y, w, h, over(fill, ink, layer), &
                radius=r)
        end if
        str = trim(node%text)
        if (node%ellipsis) str = text_fit(str, node%text_size, w / s - 2.0 * ui_pad(), weight)
        call label(list, str, x, y, h, node%text_size, weight, ink, .true., w)
        if (node%focused .and. .not. node%disabled) call ring(list, x, y, w, h, r)
    end subroutine material_button

    subroutine ring(list, x, y, w, h, r)
        !! M3 focus indicator: 3 dp outline 2 dp outside the shape.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, w, h, r
        real :: o
        o = 5.0 * s
        call rect(list, x - o, y - o, w + 2.0 * o, h + 2.0 * o, 0, radius=r + o, &
            border=3.0 * s, stroke=theme%focus)
    end subroutine ring

    subroutine material_checkbox(list, node)
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, b, bx, by, lx, cx, cy, q
        integer :: weight, layer
        integer(int32) :: tint

        call node_box(node, x, y, w, h)
        weight = style_weight(1)
        b = real(nint(theme%check_size * s))
        bx = x + real(nint(11.0 * s))
        by = y + real(floor(0.5 * (h - b)))
        cx = bx + 0.5 * b
        cy = by + 0.5 * b
        tint = merge(theme%primary, theme%on_surface, node%checked)
        layer = 0
        if (node%hovered) layer = 20
        if (node%active .or. node%focused) layer = 26
        if (layer > 0 .and. .not. node%disabled) call rect(list, cx - 20.0 * s, cy - 20.0 * s, &
            40.0 * s, 40.0 * s, with_alpha(tint, layer), radius=20.0 * s)
        if (node%checked) then
            call rect(list, bx, by, b, b, merge(theme%disabled, theme%primary, node%disabled), &
                radius=2.0 * s)
            q = b / 18.0
            call line(list, bx + 4.3 * q, by + 9.2 * q, bx + 7.6 * q, by + 12.5 * q, 2.0 * s, &
                merge(theme%window, theme%on_primary, node%disabled))
            call line(list, bx + 7.6 * q, by + 12.5 * q, bx + 14.0 * q, by + 5.8 * q, 2.0 * s, &
                merge(theme%window, theme%on_primary, node%disabled))
        else
            call rect(list, bx, by, b, b, 0, radius=2.0 * s, border=2.0 * s, &
                stroke=merge(theme%disabled, theme%on_surface_muted, node%disabled))
        end if
        lx = bx + b + real(nint((11.0 + theme%check_gap) * s))
        if (len_trim(node%text) > 0) call label(list, trim(node%text), lx, y, h, &
            node%text_size, weight, merge(theme%disabled, theme%on_surface, node%disabled))
    end subroutine material_checkbox

    subroutine material_slider(list, node)
        !! 4 dp track (active part in primary) and a 20 dp handle.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, t, r, cx, cy
        integer(int32) :: active, inactive
        call node_box(node, x, y, w, h)
        r = 0.5 * real(nint(theme%slider_thumb * s))
        t = 4.0 * s
        cy = y + 0.5 * h
        cx = x + r + slider_fraction(node) * (w - 2.0 * r)
        active = theme%primary
        inactive = theme%tonal
        if (node%disabled) then
            active = theme%disabled
            inactive = with_alpha(theme%on_surface, 31)
        end if
        call rect(list, x + r, cy - 0.5 * t, w - 2.0 * r, t, inactive, radius=0.5 * t)
        call rect(list, x + r, cy - 0.5 * t, cx - x - r, t, active, radius=0.5 * t)
        if ((node%hovered .or. node%active .or. node%focused) .and. .not. node%disabled) &
            call rect(list, cx - 20.0 * s, cy - 20.0 * s, 40.0 * s, 40.0 * s, &
            with_alpha(theme%primary, merge(26, 20, node%active .or. node%focused)), &
            radius=20.0 * s)
        call rect(list, cx - r, cy - r, 2.0 * r, 2.0 * r, active, radius=r)
    end subroutine material_slider

    subroutine material_tab(list, node)
        !! Primary tab: label, 3 dp indicator under it when selected, divider.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, tw
        integer :: weight
        integer(int32) :: ink
        character(len=:), allocatable :: str
        call node_box(node, x, y, w, h)
        weight = style_weight(ROLE_LABEL)
        if (node%hovered .or. node%active) call rect(list, x, y, w, h, over(theme%window, &
            theme%on_surface, merge(26, 20, node%active)))
        call rect(list, x, y + h - u, w, u, theme%outline_variant)
        ink = merge(theme%primary, theme%on_surface_muted, node%checked)
        if (node%disabled) ink = theme%disabled
        str = text_fit(trim(node%text), node%text_size, w / s - 16.0, weight)
        call label(list, str, x, y, h, node%text_size, weight, ink, .true., w)
        tw = real(nint(text_width(str, node%text_size, weight) * s))
        if (node%checked) call rect(list, x + real(floor(0.5 * (w - tw))), y + h - 3.0 * s, &
            tw, 3.0 * s, theme%primary, radius=1.5 * s)
        if (node%focused) call rect(list, x + 2.0 * s, y + 2.0 * s, w - 4.0 * s, &
            h - 4.0 * s, 0, radius=4.0 * s, border=3.0 * s, stroke=theme%focus)
    end subroutine material_tab

    ! --- fields and scrolling text ---------------------------------------------------

    subroutine paint_field(list, node)
        !! Single- and multi-line text fields: sunken white field (classic) or an
        !! outlined field (material), placeholder, text and caret.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, pad, lh, tx, ty, caret_x, shift
        integer :: first, last, row, caret_row
        integer(int32) :: ink

        call node_box(node, x, y, w, h)
        pad = real(nint(theme%input_padding * s))
        if (theme%kind == STYLE_CLASSIC) then
            call sunken_field(list, x, y, w, h, merge(theme%face, theme%field, node%disabled))
        else
            call rect(list, x, y, w, h, theme%field, radius=theme%field_radius * s)
            if (node%focused) then
                call rect(list, x, y, w, h, 0, radius=theme%field_radius * s, border=2.0 * s, &
                    stroke=theme%primary)
            else
                call rect(list, x, y, w, h, 0, radius=theme%field_radius * s, border=1.0 * s, &
                    stroke=merge(theme%on_surface, theme%outline, node%hovered))
            end if
        end if
        call clip(list, x + 2.0 * u, y + 2.0 * u, w - 4.0 * u, h - 4.0 * u)
        lh = real(nint(text_line_height(node%text_size) * s))
        ink = merge(theme%disabled, theme%on_field, node%disabled)
        if (node%kind == UI_TEXT_INPUT) then
            ty = y + real(floor(0.5 * (h - lh)))
            caret_x = 0.0
            if (node%caret > 0 .and. allocated(node%body)) caret_x = real(nint(text_width( &
                node%body(1:min(node%caret, len(node%body))), node%text_size) * s))
            shift = max(0.0, caret_x - (w - 2.0 * pad))
            tx = x + pad - shift
            if (.not. allocated(node%body)) then
                call placeholder(list, node, x + pad, ty, lh)
            else if (len(node%body) == 0) then
                call placeholder(list, node, x + pad, ty, lh)
            else
                call text_run(list, node%body, tx, ty, lh, FACE_REGULAR, node%text_size * s, ink)
            end if
            if (node%focused) call caret(list, tx + caret_x, ty, lh)
        else
            ty = y + pad
            caret_row = 0
            caret_x = 0.0
            if (.not. allocated(node%body)) then
                call placeholder(list, node, x + pad, ty, lh)
            else if (len(node%body) == 0) then
                call placeholder(list, node, x + pad, ty, lh)
            else
                first = 1
                row = 0
                do
                    last = index(node%body(first:), new_line('a'))
                    if (last == 0) then
                        last = len(node%body)
                    else
                        last = first + last - 2
                    end if
                    if (last >= first) call text_run(list, node%body(first:last), x + pad, &
                        ty + row * lh, lh, FACE_REGULAR, node%text_size * s, ink)
                    if (node%caret >= first - 1 .and. node%caret <= last) then
                        caret_row = row
                        caret_x = 0.0
                        if (node%caret >= first) caret_x = real(nint(text_width( &
                            node%body(first:node%caret), node%text_size) * s))
                    end if
                    if (last >= len(node%body)) exit
                    first = last + 2
                    row = row + 1
                    if (first > len(node%body)) then
                        if (node%caret >= len(node%body)) then
                            caret_row = row
                            caret_x = 0.0
                        end if
                        exit
                    end if
                end do
            end if
            if (node%focused) call caret(list, x + pad + caret_x, ty + caret_row * lh, lh)
        end if
        call unclip(list)
    end subroutine paint_field

    subroutine placeholder(list, node, x, y, lh)
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real, intent(in) :: x, y, lh
        if (node%focused .or. len_trim(node%text) == 0) return
        call text_run(list, trim(node%text), x, y, lh, FACE_REGULAR, node%text_size * s, &
            merge(theme%shadow, theme%on_surface_muted, theme%kind == STYLE_CLASSIC))
    end subroutine placeholder

    subroutine caret(list, x, y, lh)
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, lh
        if (theme%kind == STYLE_CLASSIC) then
            call rect(list, real(nint(x)), y, u, lh, theme%on_field)
        else
            call rect(list, real(nint(x)), y + 2.0 * s, 2.0 * s, lh - 4.0 * s, theme%primary)
        end if
    end subroutine caret

    subroutine paint_scroll_text(list, node)
        !! Wrapped lines in a field, with a scroll bar when they do not fit: Windows
        !! 95 arrows, dithered track and raised thumb, or a thin rounded M3 thumb.
        type(paint_list_t), intent(inout) :: list
        type(ui_node_t), intent(in) :: node
        real :: x, y, w, h, top, ly, lh, total, max_scroll, sw, th, ty, pad, tl
        integer :: i

        call node_box(node, x, y, w, h)
        pad = real(nint(theme%scroll_padding * s))
        if (theme%kind == STYLE_CLASSIC) then
            call sunken_field(list, x, y, w, h, theme%field)
        else
            call rect(list, x, y, w, h, theme%surface_low, radius=12.0 * s)
        end if
        call clip(list, x + 2.0 * u, y + 2.0 * u, w - 4.0 * u, h - 4.0 * u)
        top = y + pad - real(nint(node%scroll * s))
        do i = 1, node%line_count
            associate(ln => node%lines(i))
                lh = real(nint(text_line_height(ln%size) * s))
                ly = top + real(nint(ln%y * s))
                if (ly + lh < y) cycle
                if (ly > y + h) exit
                if (ln%last >= ln%first) call text_run(list, node%body(ln%first:ln%last), &
                    x + pad, ly, lh, paint_face(ln%style), ln%size * s, theme%on_field)
            end associate
        end do
        call unclip(list)
        total = node%content_height + 2.0 * theme%scroll_padding
        if (total <= node%height) return
        max_scroll = total - node%height
        sw = real(nint(theme%scrollbar_width * s))
        if (theme%kind == STYLE_CLASSIC) then
            ! Inside the field's 2 px edge: arrow buttons, checker track, thumb.
            x = x + w - 2.0 * u - sw
            y = y + 2.0 * u
            h = h - 4.0 * u
            call raised(list, x, y, sw, sw)
            call arrow(list, x, y, sw, .true.)
            call raised(list, x, y + h - sw, sw, sw)
            call arrow(list, x, y + h - sw, sw, .false.)
            tl = h - 2.0 * sw
            call rect(list, x, y + sw, sw, tl, theme%hilight, stroke=theme%face, &
                pattern=PATTERN_CHECKER)
            th = max(8.0 * u, real(nint(tl * node%height / total)))
            ty = y + sw + real(nint(node%scroll / max_scroll * (tl - th)))
            call raised(list, x, ty, sw, th)
        else
            th = max(24.0 * s, h * node%height / total)
            ty = y + node%scroll / max_scroll * (h - th)
            call rect(list, x + w - sw + 3.0 * s, ty + 2.0 * s, sw - 6.0 * s, th - 4.0 * s, &
                with_alpha(theme%on_surface_muted, merge(160, 97, node%hovered)), &
                radius=0.5 * (sw - 6.0 * s))
        end if
    end subroutine paint_scroll_text

    subroutine arrow(list, x, y, size, up)
        !! The 7 x 4 black triangle of a scroll bar button.
        type(paint_list_t), intent(inout) :: list
        real, intent(in) :: x, y, size
        logical, intent(in) :: up
        real :: cx, cy
        integer :: r
        cx = x + real(floor(0.5 * (size - 7.0 * u)))
        cy = y + real(floor(0.5 * (size - 4.0 * u)))
        do r = 0, 3
            if (up) then
                call rect(list, cx + (3 - r) * u, cy + r * u, (2 * r + 1) * u, u, &
                    theme%dark_shadow)
            else
                call rect(list, cx + r * u, cy + r * u, (7 - 2 * r) * u, u, theme%dark_shadow)
            end if
        end do
    end subroutine arrow

end module fortui_paint
