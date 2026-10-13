module fortui_tui
!! Terminal platform + renderer backend using termbox2. One terminal cell is
!! CELL_W_DP x CELL_H_DP logical units; layout uses matching fixed metrics.
use iso_c_binding, only: c_int, c_int8_t, c_int16_t, c_int32_t
use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_SLIDER, &
    UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, UI_CAPTION, &
    UI_HEADING, UI_TITLE, SCROLL_PADDING
use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
    input_set_key, input_type_text, KEY_NONE, KEY_ENTER, KEY_ESCAPE, KEY_TAB, &
    KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, &
    KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_INSERT, KEY_SPACE
use fortui_text, only: utf8_decode, utf8_encode, text_use_fixed_metrics
use fortui_error, only: report_error
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_canvas, only: canvas_store_t
implicit none
private

real, parameter, public :: CELL_W_DP = 8.0
real, parameter, public :: CELL_H_DP = 16.0

! termbox2.h constants (termbox2 v2, TB_OPT_ATTR_W 16 as compiled in src/c).
integer, parameter :: TB_OK = 0
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_KEY_BACKSPACE = 8, TB_KEY_TAB = 9, TB_KEY_ENTER = 13
integer, parameter :: TB_KEY_ESC = 27, TB_KEY_BACKSPACE2 = 127
integer, parameter :: TB_KEY_INSERT = 65535 - 12, TB_KEY_DELETE = 65535 - 13
integer, parameter :: TB_KEY_HOME = 65535 - 14, TB_KEY_END = 65535 - 15
integer, parameter :: TB_KEY_PGUP = 65535 - 16, TB_KEY_PGDN = 65535 - 17
integer, parameter :: TB_KEY_ARROW_UP = 65535 - 18, TB_KEY_ARROW_DOWN = 65535 - 19
integer, parameter :: TB_KEY_ARROW_LEFT = 65535 - 20, TB_KEY_ARROW_RIGHT = 65535 - 21
integer, parameter :: TB_KEY_MOUSE_LEFT = 65535 - 23, TB_KEY_MOUSE_RIGHT = 65535 - 24
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65535 - 26
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65535 - 27
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65535 - 28
integer, parameter :: TB_EVENT_KEY = 1, TB_EVENT_RESIZE = 2, TB_EVENT_MOUSE = 3
integer(c_int), parameter :: TB_INPUT_ESC = 1, TB_INPUT_MOUSE = 4
integer(c_int), parameter :: TB_OUTPUT_256 = 2
integer, parameter :: ATTR_BITS = 16
integer, parameter :: C_DEFAULT = 0, C_BLACK = 1, C_GREEN = 3
integer, parameter :: C_YELLOW = 4, C_CYAN = 7, C_WHITE = 8
integer, parameter :: C_BOLD = 256, C_REVERSE = 1024

type, bind(C) :: tb_event
    integer(c_int8_t) :: type
    integer(c_int8_t) :: mod
    integer(c_int16_t) :: key
    integer(c_int32_t) :: ch
    integer(c_int32_t) :: w, h, x, y
end type tb_event

interface
    integer(c_int) function tb_init() bind(C, name="tb_init")
        import :: c_int
    end function tb_init
    integer(c_int) function tb_shutdown() bind(C, name="tb_shutdown")
        import :: c_int
    end function tb_shutdown
    integer(c_int) function tb_width() bind(C, name="tb_width")
        import :: c_int
    end function tb_width
    integer(c_int) function tb_height() bind(C, name="tb_height")
        import :: c_int
    end function tb_height
    integer(c_int) function tb_clear() bind(C, name="tb_clear")
        import :: c_int
    end function tb_clear
    integer(c_int) function tb_present() bind(C, name="tb_present")
        import :: c_int
    end function tb_present
    integer(c_int) function tb_hide_cursor() bind(C, name="tb_hide_cursor")
        import :: c_int
    end function tb_hide_cursor
    integer(c_int) function tb_attr_width() bind(C, name="tb_attr_width")
        import :: c_int
    end function tb_attr_width
    integer(c_int) function tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        !! uintattr_t is uint16_t for TB_OPT_ATTR_W 16 (checked at init).
        import :: c_int, c_int16_t, c_int32_t
        integer(c_int), value :: x, y
        integer(c_int32_t), value :: ch
        integer(c_int16_t), value :: fg, bg
    end function tb_set_cell
    integer(c_int) function tb_peek_event(event, timeout) bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), value :: timeout
    end function tb_peek_event
    integer(c_int) function tb_poll_event(event) bind(C, name="tb_poll_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
    end function tb_poll_event
    integer(c_int) function tb_set_input_mode(mode) bind(C, name="tb_set_input_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function tb_set_input_mode
    integer(c_int) function tb_set_output_mode(mode) bind(C, name="tb_set_output_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function tb_set_output_mode
end interface

type, extends(ui_backend_t), public :: tui_backend_t
    !! termbox2 terminal backend: adapts meaning (summaries) rather than pixels.
    logical :: active = .false.
    logical :: quit_requested = .false.
    logical :: draw_failed = .false.
    integer :: cols = 0
    integer :: rows = 0
contains
    procedure :: name => tui_name
    procedure :: init => tui_init
    procedure :: shutdown => tui_shutdown
    procedure :: poll => tui_poll
    procedure :: present => tui_present
    procedure :: should_close => tui_should_close
    procedure :: install_text_metrics => tui_metrics
    procedure :: capabilities => tui_caps
end type tui_backend_t

public :: tui_is_available, tui_map_key

contains

function tui_name(self) result(name)
    class(tui_backend_t), intent(in) :: self
    character(len=:), allocatable :: name
    name = "tui"
end function tui_name

logical function tui_init(self)
    !! The terminal decides the window size; the requested size is ignored.
    class(tui_backend_t), intent(inout) :: self
    integer :: status

    tui_init = .false.
    if (.not. tui_is_available()) then
        call report_error("fortui_tui", "init", "no terminal (TERM unset or headless)")
        return
    end if
    status = tb_init()
    if (status /= TB_OK) then
        call report_error("fortui_tui", "init", &
            "termbox2 could not initialize a terminal")
        return
    end if
    self%active = .true.
    if (tb_attr_width() /= ATTR_BITS) then
        call report_error("fortui_tui", "init", "termbox2 attribute width differs " // &
            "from the 16-bit binding")
        call tui_shutdown(self)
        return
    end if
    if (tb_set_output_mode(TB_OUTPUT_256) < 0 .or. &
        tb_set_input_mode(TB_INPUT_ESC + TB_INPUT_MOUSE) < 0 .or. &
        tb_hide_cursor() /= TB_OK) then
        call report_error("fortui_tui", "init", "termbox2 terminal setup failed")
        call tui_shutdown(self)
        return
    end if
    self%quit_requested = .false.
    tui_init = .true.
end function tui_init

subroutine tui_shutdown(self)
    class(tui_backend_t), intent(inout) :: self
    if (.not. self%active) return
    if (tb_shutdown() /= TB_OK) &
        call report_error("fortui_tui", "shutdown", "termbox2 shutdown failed")
    self%active = .false.
end subroutine tui_shutdown

subroutine tui_poll(self, input, wait)
    !! Terminal events; with `wait`, block until one arrives (keys, mouse, resize).
    class(tui_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    logical, intent(in) :: wait
    type(tb_event) :: event
    integer :: status

    if (.not. self%active) return
    call report_size(input)
    if (wait) then
        self%waits = self%waits + 1
        status = tb_poll_event(event)
        if (status == TB_OK) call process_event(self, input, event)
    end if
    do
        status = tb_peek_event(event, 0_c_int)
        if (status /= TB_OK) exit
        call process_event(self, input, event)
    end do
end subroutine tui_poll

subroutine report_size(input)
    type(input_state_t), intent(inout) :: input
    integer :: w, h

    w = max(1, nint(real(tb_width()) * CELL_W_DP))
    h = max(1, nint(real(tb_height()) * CELL_H_DP))
    if (w /= input%width .or. h /= input%height) input%resized = .true.
    input%width = w
    input%height = h
    input%scale = 1.0
end subroutine report_size

subroutine process_event(self, input, event)
    type(tui_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    type(tb_event), intent(in) :: event
    integer :: key
    real :: px, py

    key = iand(int(event%key), 65535)
    select case (int(event%type))
    case (TB_EVENT_KEY)
        if (key == TB_KEY_CTRL_C) self%quit_requested = .true.
        if (event%ch > 0) then
            ! Space is typed text and also the activation key.
            if (event%ch == 32) call input_set_key(input, KEY_SPACE)
            call input_type_text(input, utf8_encode(int(event%ch)))
        else
            call input_set_key(input, tui_map_key(key))
        end if
    case (TB_EVENT_RESIZE)
        call report_size(input)
        input%resized = .true.
    case (TB_EVENT_MOUSE)
        px = real(event%x) * CELL_W_DP
        py = real(event%y) * CELL_H_DP
        select case (key)
        case (TB_KEY_MOUSE_LEFT)
            call input_update_pointer(input, px, py, .true., .true.)
        case (TB_KEY_MOUSE_RELEASE)
            call input_update_pointer(input, px, py, .false.)
        case (TB_KEY_MOUSE_WHEEL_UP)
            call input_update_pointer(input, px, py, input%pointer_down)
            call input_scroll(input, 1)
        case (TB_KEY_MOUSE_WHEEL_DOWN)
            call input_update_pointer(input, px, py, input%pointer_down)
            call input_scroll(input, -1)
        case (TB_KEY_MOUSE_RIGHT)
            call input_update_pointer(input, px, py, input%pointer_down)
        end select
    end select
end subroutine process_event

pure integer function tui_map_key(tb_key) result(key)
    !! Backend-neutral KEY_* for a termbox2 key code (KEY_NONE if unnamed).
    integer, intent(in) :: tb_key
    select case (tb_key)
    case (TB_KEY_ENTER); key = KEY_ENTER
    case (TB_KEY_ESC); key = KEY_ESCAPE
    case (TB_KEY_TAB); key = KEY_TAB
    case (TB_KEY_BACKSPACE, TB_KEY_BACKSPACE2); key = KEY_BACKSPACE
    case (TB_KEY_DELETE); key = KEY_DELETE
    case (TB_KEY_INSERT); key = KEY_INSERT
    case (TB_KEY_HOME); key = KEY_HOME
    case (TB_KEY_END); key = KEY_END
    case (TB_KEY_PGUP); key = KEY_PAGE_UP
    case (TB_KEY_PGDN); key = KEY_PAGE_DOWN
    case (TB_KEY_ARROW_UP); key = KEY_ARROW_UP
    case (TB_KEY_ARROW_DOWN); key = KEY_ARROW_DOWN
    case (TB_KEY_ARROW_LEFT); key = KEY_ARROW_LEFT
    case (TB_KEY_ARROW_RIGHT); key = KEY_ARROW_RIGHT
    case default; key = KEY_NONE
    end select
end function tui_map_key

subroutine tui_present(self, frame, store)
    class(tui_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    integer :: i

    call self%canvas%realize_frame(store, frame)
    self%presents = self%presents + 1
    if (.not. self%active) return
    self%cols = int(tb_width())
    self%rows = int(tb_height())
    if (tb_clear() /= TB_OK) call draw_failure(self)
    do i = 1, frame%count
        call draw_node(self, frame%nodes(i))
    end do
    if (tb_present() /= TB_OK) call draw_failure(self)
end subroutine tui_present

subroutine draw_failure(self)
    type(tui_backend_t), intent(inout) :: self
    if (self%draw_failed) return
    self%draw_failed = .true.
    call report_error("fortui_tui", "present", "termbox2 drawing failed")
end subroutine draw_failure

logical function tui_should_close(self)
    class(tui_backend_t), intent(in) :: self
    tui_should_close = self%quit_requested
end function tui_should_close

subroutine tui_metrics(self)
    !! One logical 20-unit glyph maps to one 8x16 terminal cell.
    class(tui_backend_t), intent(inout) :: self
    call text_use_fixed_metrics(CELL_W_DP / 20.0, CELL_H_DP / 20.0)
end subroutine tui_metrics

function tui_caps(self) result(caps)
    class(tui_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
    caps%pointer = .true.
    caps%text_entry = .true.
    caps%event_waiting = .true.
end function tui_caps

subroutine draw_node(self, node)
    type(tui_backend_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node
    integer :: x, y, w, h, fg, bg, knob, track, i
    real :: fraction
    character(len=512) :: label

    x = max(0, nint(node%x / CELL_W_DP))
    y = max(0, nint(node%y / CELL_H_DP))
    w = max(1, nint(node%width / CELL_W_DP))
    h = max(1, nint(node%height / CELL_H_DP))

    fg = C_WHITE
    bg = C_DEFAULT
    if (node%disabled) fg = C_BLACK
    if (node%hovered) fg = C_CYAN + C_BOLD
    if (node%focused) fg = C_YELLOW + C_BOLD
    if (node%active) then
        fg = C_BLACK + C_BOLD
        bg = C_WHITE
    end if

    select case (node%kind)
    case (UI_TEXT)
        if (node%style == UI_HEADING .or. node%style == UI_TITLE) fg = fg + C_BOLD
        if (node%style == UI_CAPTION) fg = C_CYAN
        call draw_string(self, x, y, trim(node%text), fg, bg, w, node%ellipsis)
    case (UI_BUTTON)
        call put_cell(self, x, y, iachar('['), fg, bg)
        call draw_string(self, x + 1, y, trim(node%text), fg, bg, max(0, w - 2), &
            node%ellipsis)
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    case (UI_TAB)
        if (node%checked) fg = fg + C_REVERSE
        call draw_string(self, x, y, " " // trim(node%text) // " ", fg, bg, w, .true.)
    case (UI_CHECKBOX)
        call put_cell(self, x, y, iachar('['), fg, bg)
        if (node%checked) then
            call put_cell(self, x + 1, y, iachar('x'), C_GREEN + C_BOLD, bg)
        else
            call put_cell(self, x + 1, y, iachar(' '), fg, bg)
        end if
        call put_cell(self, x + 2, y, iachar(']'), fg, bg)
        if (len_trim(node%text) > 0) call draw_string(self, x + 4, y, trim(node%text), &
            fg, bg, max(0, w - 4), .true.)
    case (UI_SLIDER)
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        track = max(1, w - 2)
        knob = nint(fraction * real(max(0, track - 1)))
        call put_cell(self, x, y, iachar('['), fg, bg)
        do i = 0, track - 1
            if (i < knob) then
                call put_cell(self, x + 1 + i, y, iachar('='), C_CYAN, bg)
            else if (i == knob) then
                call put_cell(self, x + 1 + i, y, iachar('|'), C_WHITE + C_BOLD, bg)
            else
                call put_cell(self, x + 1 + i, y, iachar('-'), fg, bg)
            end if
        end do
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    case (UI_CANVAS)
        ! Terminal adaptation: a frame plus a semantic summary, not pixels.
        call draw_border(self, x, y, w, h, fg, bg)
        write(label, '(a,i0,a,i0,a)') " canvas " // trim(node%id) // ": ", &
            node%layer_count, " layers, ", node%label_count, " labels "
        call draw_string(self, x + 1, y, trim(label), fg, bg, max(0, w - 2), .true.)
    case (UI_SCROLL_TEXT)
        call draw_scroll_text(self, node, x, y, w, h, fg, bg)
    case (UI_TEXT_INPUT)
        call put_cell(self, x, y, iachar('['), fg, bg)
        if (allocated(node%body)) then
            if (len(node%body) > 0) then
                call draw_string(self, x + 1, y, node%body, fg, bg, max(0, w - 2), &
                    .false.)
            else
                call draw_string(self, x + 1, y, trim(node%text), C_BLACK + C_BOLD, &
                    bg, max(0, w - 2), .false.)
            end if
        end if
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    end select
end subroutine draw_node

subroutine draw_scroll_text(self, node, x, y, w, h, fg, bg)
    type(tui_backend_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node
    integer, intent(in) :: x, y, w, h, fg, bg
    integer :: i, row

    if (.not. allocated(node%body) .or. .not. allocated(node%lines)) return
    do i = 1, node%line_count
        row = nint((SCROLL_PADDING + node%lines(i)%y - node%scroll) / CELL_H_DP)
        if (row < 0) cycle
        if (row >= h) exit
        if (node%lines(i)%last >= node%lines(i)%first) call draw_string(self, x, &
            y + row, node%body(node%lines(i)%first:node%lines(i)%last), fg, bg, w, .false.)
    end do
end subroutine draw_scroll_text

subroutine draw_border(self, x, y, w, h, fg, bg)
    type(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: x, y, w, h, fg, bg
    integer :: i
    if (w < 2 .or. h < 2) return
    call put_cell(self, x, y, iachar('+'), fg, bg)
    call put_cell(self, x + w - 1, y, iachar('+'), fg, bg)
    call put_cell(self, x, y + h - 1, iachar('+'), fg, bg)
    call put_cell(self, x + w - 1, y + h - 1, iachar('+'), fg, bg)
    do i = 1, w - 2
        call put_cell(self, x + i, y, iachar('-'), fg, bg)
        call put_cell(self, x + i, y + h - 1, iachar('-'), fg, bg)
    end do
    do i = 1, h - 2
        call put_cell(self, x, y + i, iachar('|'), fg, bg)
        call put_cell(self, x + w - 1, y + i, iachar('|'), fg, bg)
    end do
end subroutine draw_border

subroutine draw_string(self, x, y, value, fg, bg, limit, ellipsis)
    !! Draw UTF-8 text, one code point per cell (no wide-character evidence yet);
    !! with `ellipsis`, a clipped string ends in U+2026.
    type(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: x, y, fg, bg, limit
    character(*), intent(in) :: value
    logical, intent(in) :: ellipsis
    integer :: pos, col, cp, nb

    pos = 1
    col = 0
    do while (pos <= len_trim(value) .and. col < limit)
        call utf8_decode(value, pos, cp, nb)
        pos = pos + nb
        if (ellipsis .and. col == limit - 1 .and. pos <= len_trim(value)) cp = 8230
        call put_cell(self, x + col, y, cp, fg, bg)
        col = col + 1
    end do
end subroutine draw_string

subroutine put_cell(self, x, y, ch, fg, bg)
    type(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: x, y, ch, fg, bg
    if (x < 0 .or. y < 0 .or. x >= self%cols .or. y >= self%rows) return
    if (tb_set_cell(int(x, c_int), int(y, c_int), int(ch, c_int32_t), &
        int(fg, c_int16_t), int(bg, c_int16_t)) /= TB_OK) call draw_failure(self)
end subroutine put_cell

logical function tui_is_available()
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        tui_is_available = .false.
        return
    end if
    call get_environment_variable("TERM", value, status=status)
    tui_is_available = status == 0 .and. len_trim(value) > 0
end function tui_is_available

end module fortui_tui
