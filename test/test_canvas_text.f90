program test_canvas_text
!! Headless behavioural tests: retained canvas layers, canvas pointer semantics,
!! UTF-8 text input, wrapping with fixed metrics, scroll clamping, idle waiting.
use iso_fortran_env, only: int32
use fortui
use fortui_context, only: fortui_context_t, get_default_context
use fortui_text, only: text_wrap, text_line_t, utf8_prev, utf8_next, text_use_fixed_metrics
implicit none

type(fortui_context_t), pointer :: ctx
type(canvas_view_t) :: cam
type(canvas_events_t) :: ev
type(ui_stats_t) :: st
type(ui_backend_caps_t) :: caps
character(len=:), allocatable :: query, doc
real :: xy(2, 3), lxy(2, 3)
integer(int32) :: colours(3)
integer :: segs(2, 2), point_gen, line_gen, seg_gen, stat, vu, iu, i
logical :: show_canvas, changed, submitted, esc_seen
real :: bx, by, bh
double precision :: now

call test_wrap()

call ui_init("tui-or-gui-typo", 800, 600, "canvas test", stat=stat)
call check(stat /= 0 .and. .not. ui_is_initialized(), "unknown backend is an error")
call ui_init("headless", 800, 600, "canvas test", stat=stat)
call check(stat == 0, "headless init")
caps = ui_backend_capabilities()
call check(caps%canvas_layers .and. .not. caps%graphical, "headless capabilities")
ctx => get_default_context()

xy = reshape([0.0, 0.0, 10.0, 0.0, 0.0, 10.0], [2, 3])
lxy = xy
colours = [ui_rgba(255, 0, 0), ui_rgba(0, 255, 0), ui_rgba(0, 0, 255, 128)]
segs = reshape([1, 2, 2, 3], [2, 2])
point_gen = 1
line_gen = 1
seg_gen = 1
show_canvas = .true.
query = ""
doc = ""
cam = canvas_view_t(zoom=2.0, pan_x=10.0, pan_y=20.0)
now = 10.0d0

! --- retained layer generations ------------------------------------------------
call frame()
st = ui_stats()
call check(st%vertex_uploads == 2 .and. st%index_uploads == 1, "first frame uploads")
call frame()
call frame()
call ui_canvas_layer_uploads("graph", "nodes", vu, iu)
call check(vu == 1, "unchanged point generation does not re-upload")
call ui_canvas_layer_uploads("graph", "edges", vu, iu)
call check(vu == 1 .and. iu == 1, "unchanged line generations do not re-upload")
point_gen = 2
xy(1, 1) = 5.0
call frame()
call ui_canvas_layer_uploads("graph", "nodes", vu, iu)
call check(vu == 2, "new point generation uploads once")
call check(ctx%canvas%layers(ctx%canvas%lookup("graph/nodes"))%xy(1, 1) > 4.99, &
    "store holds an owned copy of the new data")
line_gen = 2
call frame()
call ui_canvas_layer_uploads("graph", "edges", vu, iu)
call check(vu == 2 .and. iu == 1, "vertex change keeps segment indices")
call check(ctx%previous_frame%layer_count == 2, "frame records two layer descriptors")
call check(ctx%previous_frame%layers(1)%index_count == 4, "line descriptor counts indices")
call check(ctx%previous_frame%label_count == 1, "frame records canvas label")

! --- split layout and canvas geometry -------------------------------------------
i = ctx%previous_frame%find("graph")
call check(abs(ctx%previous_frame%nodes(i)%x - 200.0) < 1e-4, "canvas follows sidebar")
call check(abs(ctx%previous_frame%nodes(i)%width - 600.0) < 1e-4, "canvas fills width")
call ui_inject_resize(1000, 500)
call frame()
i = ctx%previous_frame%find("graph")
call check(abs(ctx%previous_frame%nodes(i)%width - 800.0) < 1e-4, "canvas tracks resize")
call check(abs(ctx%previous_frame%nodes(i)%height - 500.0) < 1e-4, "canvas fills height")

! --- pointer semantics in canvas coordinates ------------------------------------
call ui_inject_pointer(300.0, 120.0, .false.)
call frame()
call check(ev%hovered, "canvas hovered")
call check(abs(ev%x - 45.0) < 1e-4 .and. abs(ev%y - 50.0) < 1e-4, "world coordinates")
call check(abs(ev%local_x - 100.0) < 1e-4, "local coordinates")
call click(300.0, 120.0)
call check(ev%clicked .and. ev%released .and. .not. ev%double_clicked, "single click")
now = now + 0.2d0
call click(301.0, 121.0)
call check(ev%clicked .and. ev%double_clicked, "double click within interval")
now = now + 1.0d0
call click(300.0, 120.0)
call check(ev%clicked .and. .not. ev%double_clicked, "slow second click is single")

now = now + 1.0d0
call ui_inject_pointer(300.0, 120.0, .true.)
call frame()
call check(ev%pressed .and. ev%captured .and. .not. ev%dragging, "press captures")
call check(abs(ev%press_x - 45.0) < 1e-4, "press position in world coordinates")
call ui_inject_pointer(320.0, 120.0, .true.)
call frame()
call check(ev%dragging .and. ev%drag_started .and. abs(ev%drag_dx - 20.0) < 1e-4, &
    "drag beyond threshold starts")
call ui_inject_pointer(50.0, 130.0, .true.)
call frame()
call check(ev%dragging .and. .not. ev%drag_started .and. .not. ev%hovered, &
    "capture keeps drag outside the canvas")
call ui_inject_pointer(50.0, 130.0, .false.)
call frame()
call check(ev%drag_ended .and. ev%released .and. .not. ev%clicked, "release ends drag")
call check(len_trim(ctx%input%active_id) == 0, "capture released on button up")

call ui_inject_pointer(300.0, 120.0, .true.)
call frame()
call check(ev%captured, "captured before removal")
show_canvas = .false.
call frame()
call frame()
call check(len_trim(ctx%input%active_id) == 0, "capture released on widget removal")
call check(ui_stats_layers() == 0, "layers released with their canvas")
show_canvas = .true.
call frame()
call check(.not. ev%captured, "re-added canvas is not captured")
call ui_canvas_layer_uploads("graph", "nodes", vu, iu)
call check(vu == 1, "re-created layer uploads afresh")
call ui_inject_pointer(300.0, 120.0, .false.)
call frame()

call ui_inject_wheel(1.5)
call frame()
call check(abs(ev%wheel - 1.5) < 1e-6, "wheel reported over canvas")
call canvas_zoom_at(cam, 2.0, ev%local_x, ev%local_y)
call check(abs((ev%local_x - cam%pan_x) / cam%zoom - ev%x) < 1e-4, "zoom keeps anchor")

! --- text input -----------------------------------------------------------------
call click(20.0, 16.0)
call check(trim(ctx%input%focus_id) == "search", "click focuses text input")
call ui_inject_text("Grüße")
call frame()
call check(changed .and. query == "Grüße", "typing inserts UTF-8")
call ui_inject_key(KEY_BACKSPACE)
call frame()
call check(query == "Grüß", "backspace removes one code point")
call ui_inject_key(KEY_ARROW_LEFT)
call ui_inject_key(KEY_ARROW_LEFT)
call ui_inject_key(KEY_DELETE)
call frame()
call check(query == "Grß", "delete after caret moves")
call ui_inject_key(KEY_HOME)
call ui_inject_text("Ä")
call frame()
call check(query == "ÄGrß", "home then insert")
call frame()
call check(.not. changed, "no change without input")
call ui_inject_key(KEY_END)
call ui_inject_key(KEY_ENTER)
call frame()
call check(submitted .and. .not. changed, "enter submits")
call ui_inject_key(KEY_ESCAPE)
call frame()
call check(len_trim(ctx%input%focus_id) == 0 .and. .not. ui_should_close(), &
    "escape leaves the text field without quitting")
call check(.not. esc_seen, "escape consumed by the text field is no shortcut")
call ui_set_escape_quits(.false.)
call ui_inject_key(KEY_ESCAPE)
call frame()
call check(esc_seen .and. .not. ui_should_close(), "escape as application shortcut")
call frame()
call check(.not. esc_seen, "shortcut key lasts one frame")
call ui_set_escape_quits(.true.)
call ui_inject_text("x")
call frame()
call check(query == "ÄGrß", "unfocused field ignores typing")

! --- scroll view ------------------------------------------------------------------
doc = ""
do i = 1, 100
    doc = doc // "line" // achar(10)
end do
doc = doc // "end"
call frame()
i = ctx%previous_frame%find("note")
call check(ctx%previous_frame%nodes(i)%line_count == 101, "one line per paragraph")
call check(abs(ctx%previous_frame%nodes(i)%content_height - 101 * 25.0) < 1e-3, &
    "content height from fixed metrics")
call ui_inject_pointer(100.0, 300.0, .false.)
call ui_inject_wheel(-1000.0)
call frame()
i = ctx%previous_frame%find("note")
call check(abs(ctx%previous_frame%nodes(i)%scroll - &
    (101 * 25.0 + 16.0 - ctx%previous_frame%nodes(i)%height)) < 1e-2, "scroll clamps at end")
call ui_inject_wheel(1000.0)
call frame()
call check(ctx%previous_frame%nodes(ctx%previous_frame%find("note"))%scroll < 1e-6, &
    "scroll clamps at top")
i = ctx%previous_frame%find("note")
bx = ctx%previous_frame%nodes(i)%x + ctx%previous_frame%nodes(i)%width - 3.0
by = ctx%previous_frame%nodes(i)%y
bh = ctx%previous_frame%nodes(i)%height
call ui_inject_pointer(bx, by + 5.0, .true.)
call frame()
call ui_inject_pointer(bx, by + 55.0, .true.)
call frame()
call check(abs(ctx%previous_frame%nodes(ctx%previous_frame%find("note"))%scroll - &
    50.0 * (101 * 25.0 + 16.0) / bh) < 1e-2, "scrollbar drag maps thumb motion to content")
call ui_inject_pointer(100.0, 300.0, .false.)
call frame()
i = ctx%states(ctx%state("note"))%wraps
call frame()
call check(ctx%states(ctx%state("note"))%wraps == i, "unchanged text is not rewrapped")
doc = "other"
call frame()
call check(ctx%previous_frame%nodes(ctx%previous_frame%find("note"))%scroll < 1e-6, &
    "new document starts at the top")

! --- idle waiting ----------------------------------------------------------------
call frame()
call frame()
st = ui_stats()
call check(st%last_present_waits, "idle frame may wait for events")
call ui_request_frame()
call frame()
st = ui_stats()
call check(.not. st%last_present_waits, "requested frame does not wait")
call frame()
call check(ui_stats_waits(), "request is one-shot")
call ui_set_continuous(.true.)
call frame()
call check(.not. ui_stats_waits(), "continuous mode does not wait")
call ui_set_continuous(.false.)
call ui_inject_pointer(110.0, 300.0, .false.)
call frame()
call check(.not. ui_stats_waits(), "frame after input settles without waiting")

call ui_shutdown()
print *, "fortui canvas/text tests passed"

contains

subroutine frame()
    call ui_inject_time(now)
    call ui_frame_begin()
    call split_begin(200.0)
    changed = text_input("search", query, placeholder="Search", submitted=submitted)
    esc_seen = ui_key_pressed(KEY_ESCAPE)
    call scroll_text("note", doc, markdown=.true.)
    call split_next()
    if (show_canvas) then
        call canvas_begin("graph", cam, ev, fill=ui_rgba(10, 10, 20))
        call canvas_lines("edges", line_gen, lxy, colours, segs, segment_generation=seg_gen)
        call canvas_points("nodes", point_gen, xy, colours, size=6.0)
        call canvas_label(0.0, 0.0, "Ursprung", 14.0)
        call canvas_end()
    end if
    call split_end()
    call ui_present()
end subroutine frame

subroutine click(x, y)
    real, intent(in) :: x, y
    call ui_inject_pointer(x, y, .true.)
    call frame()
    call ui_inject_pointer(x, y, .false.)
    call frame()
end subroutine click

integer function ui_stats_layers()
    type(ui_stats_t) :: s
    s = ui_stats()
    ui_stats_layers = s%active_layers
end function ui_stats_layers

logical function ui_stats_waits()
    type(ui_stats_t) :: s
    s = ui_stats()
    ui_stats_waits = s%last_present_waits
end function ui_stats_waits

subroutine test_wrap()
    type(text_line_t), allocatable :: lines(:)
    integer :: n
    real :: h
    character(len=*), parameter :: uml = "äöü äöü"

    call text_use_fixed_metrics()
    call text_wrap("hello world foo", 60.0, 20.0, .false., lines, n, h)
    call check(n == 3, "word wrap line count")
    call check(slice("hello world foo", lines(1)) == "hello" .and. &
        slice("hello world foo", lines(2)) == "world" .and. &
        slice("hello world foo", lines(3)) == "foo", "word wrap ranges")
    call check(abs(h - 75.0) < 1e-4 .and. abs(lines(3)%y - 50.0) < 1e-4, "line positions")
    call text_wrap(uml, 40.0, 20.0, .false., lines, n, h)
    call check(n == 2, "UTF-8 wrap counts code points, not bytes")
    call check(lines(1)%first == 1 .and. lines(1)%last == 6 .and. &
        slice(uml, lines(2)) == "äöü", "UTF-8 wrap ranges")
    call text_wrap("abcdefghij", 40.0, 20.0, .false., lines, n, h)
    call check(n == 3 .and. slice("abcdefghij", lines(3)) == "ij", "long word breaks")
    call text_wrap("a" // achar(10) // achar(10) // "b", 400.0, 20.0, .false., lines, n, h)
    call check(n == 3 .and. lines(2)%last < lines(2)%first, "empty paragraph line")
    call text_wrap("# Title" // achar(10) // "body", 400.0, 20.0, .true., lines, n, h)
    call check(n == 2 .and. lines(1)%style == 2 .and. abs(lines(1)%size - 30.0) < 1e-4 &
        .and. slice("# Title" // achar(10) // "body", lines(1)) == "Title", &
        "markdown heading styling")
    call check(utf8_length("Grüße") == 5, "code point length")
    call check(utf8_prev("aä", 3) == 1 .and. utf8_next("äa", 0) == 2, "caret stepping")
    call check(abs(ui_text_width("äb", 20.0) - 20.0) < 1e-6, "fixed metric width")
end subroutine test_wrap

function slice(s, line) result(out)
    character(*), intent(in) :: s
    type(text_line_t), intent(in) :: line
    character(len=:), allocatable :: out
    out = s(line%first:line%last)
end function slice

subroutine check(condition, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: message
    if (.not. condition) then
        write(*, '(a)') "FAIL: " // trim(message)
        error stop 1
    end if
end subroutine check

end program test_canvas_text
