program test_backend_conformance
!! One scenario run against every buildable backend: headless always; the
!! raylib backend in -DENABLE_GUI=1 builds when a display is reachable (a real
!! window opens briefly). Expectations are the canvas realization contract:
!! upload once per data version, nothing for view changes or unchanged frames,
!! stale segments dropped when vertices shrink, fresh resources after a kind
!! change or removal, slot growth, and one present per frame.
use iso_fortran_env, only: int32
use fortui
use fortui_backend, only: ui_backend_t
use fortui_backend_headless, only: headless_backend_t
use fortui_testing, only: ui_stats, ui_stats_t, ui_layer_uploads, ui_node_rect
use fortui_context, only: fortui_context_t, get_default_context
! Empty unless built with -DENABLE_GUI=1 (raylib_backend_t, raylib_is_available).
use fortui_gui_raylib
implicit none

integer :: failures
! Scenario state shared with compose().
character(len=:), allocatable :: label
type(canvas_view_t) :: cam
type(canvas_events_t) :: ev
real :: xy(2, 4)
integer(int32) :: rgba(4)
integer :: segs(2, 3), gen, seg_gen, n, tab, extra
logical :: show, own_lines

failures = 0
call scenario(headless_backend_t(), "headless")
#ifdef ENABLE_GUI
if (raylib_is_available()) then
    call scenario(raylib_backend_t(), "gui")
else
    print '(a)', "conformance: raylib backend skipped (no display or FORTUI_HEADLESS=1)"
end if
#endif
if (failures > 0) error stop 1

contains

subroutine scenario(backend, name)
    class(ui_backend_t), intent(in) :: backend
    character(*), intent(in) :: name

    type(ui_stats_t) :: s0, s
    real :: x, y, w, h, ww, wh
    integer :: stat, u, iu

    label = name
    call ui_init(backend, 640, 480, "FortUI conformance", target_fps=0, vsync=.false., &
        stat=stat)
    call check(stat == 0, name, "init")
    if (stat /= 0) return
    call ui_set_continuous(.true.)
    call ui_window_size(ww, wh)
    call check(ww > 0.0 .and. wh > 0.0, name, "window has a logical size")

    xy = reshape([0.0, 0.0, 40.0, 0.0, 40.0, 40.0, 0.0, 40.0], [2, 4])
    rgba = [ui_rgba(255, 0, 0), ui_rgba(0, 255, 0), ui_rgba(0, 0, 255), &
        ui_rgba(255, 255, 0)]
    segs = reshape([1, 2, 2, 3, 3, 4], [2, 3])
    gen = 1
    seg_gen = 1
    n = 4
    tab = 1
    show = .true.
    own_lines = .false.
    extra = 0
    cam = canvas_view_t(zoom=2.0, pan_x=50.0, pan_y=50.0)

    s0 = ui_stats()
    call compose()
    s = ui_stats()
    call check(s%vertex_uploads - s0%vertex_uploads == 2 .and. &
        s%attribute_uploads - s0%attribute_uploads == 3 .and. &
        s%index_uploads - s0%index_uploads == 1, name, "first frame uploads")
    call check(ui_node_rect("main/plot", x, y, w, h) .and. abs(x - 168.0) < 1e-3, &
        name, "canvas placed in the second pane")
    s0 = s
    call compose()
    call compose()
    call compose()
    cam%zoom = 3.0
    cam%pan_x = 10.0
    call compose()
    s = ui_stats()
    call check(s%vertex_uploads == s0%vertex_uploads .and. &
        s%attribute_uploads == s0%attribute_uploads .and. &
        s%index_uploads == s0%index_uploads, name, "no uploads without data changes")
    call check(s%presents - s0%presents == 4, name, "one present per frame")

    gen = 2
    xy(1, 1) = 5.0
    call compose()
    call ui_layer_uploads("main/plot", "v", u, iu)
    call check(u == 2, name, "positions re-uploaded once for two layers")
    call ui_layer_uploads("main/plot", "p", u, iu)
    call check(u == 2, name, "points follow the vertex generation")
    call ui_layer_uploads("main/plot", "l", u, iu)
    call check(u == 1 .and. iu == 1, name, "lines with their own generation unchanged")

    gen = 3
    n = 2
    call compose()
    call ui_layer_uploads("main/plot", "l", u, iu)
    call check(u == 2 .and. iu == 2, name, "vertex shrink revalidates segments once")
    call check(ui_stats_index_count() == 2, name, "stale segments are dropped")
    n = 4
    gen = 4

    own_lines = .true.
    call compose()
    call ui_layer_uploads("main/plot", "o", u, iu)
    call check(u == 1 .and. iu == 1, name, "kind change under one key starts afresh")

    show = .false.
    call compose()
    s = ui_stats()
    call check(s%active_layers == 0, name, "layers released with their canvas")
    show = .true.
    call compose()
    call ui_layer_uploads("main/plot", "v", u, iu)
    call check(u == 1, name, "re-created canvas uploads afresh")

    extra = 12
    s0 = ui_stats()
    call compose()
    s = ui_stats()
    call check(s%active_layers == 5 + 2 * 12 .and. &
        s%attribute_uploads - s0%attribute_uploads == 12, name, &
        "store and backend grow past eight slots")
    call compose()
    s0 = s
    s = ui_stats()
    call check(s%attribute_uploads == s0%attribute_uploads, name, &
        "grown layers stay realized")

    call ui_shutdown()
    print '(a)', "conformance: " // name // " done"
end subroutine scenario

subroutine compose()
    integer :: k
    real :: one(2, 1)

    call ui_frame_begin()
    call split_begin("main", first=160.0, gap=8.0)
    call column_begin(4.0)
    call text("Conformance " // label, style=UI_HEADING)
    call text("A caption that is too long for the narrow sidebar", &
        style=UI_CAPTION, ellipsis=.true.)
    if (button("b", "Button")) continue
    if (tabs("t", [character(4) :: "One", "Two"], tab)) continue
    call column_end()
    call split_next()
    if (show) then
        call canvas_begin("plot", cam, ev, fill=ui_rgba(16, 18, 24))
        call canvas_vertices("v", gen, xy(:, 1:n))
        call canvas_lines("l", "v", segs, rgba(1:1), generation=seg_gen, width=2.0)
        call canvas_points("p", "v", rgba(1:n), size=6.0)
        if (own_lines) then
            call canvas_lines("o", 1, xy, rgba, segs)
        else
            call canvas_points("o", 1, xy, rgba(1:1), size=4.0)
        end if
        do k = 1, extra
            one(:, 1) = [real(k), real(k)]
            call canvas_points("x" // ui_str(k), 1, one, rgba(1:1))
        end do
        call canvas_label(0.0, 0.0, "origin", 13.0)
        call canvas_end(cam)
    end if
    call split_end()
    call ui_present()
end subroutine compose

integer function ui_stats_index_count() result(count)
    !! Index count recorded for layer "l" in the last frame (via the store).
    type(fortui_context_t), pointer :: ctx
    integer :: slot
    count = -1
    ctx => get_default_context()
    slot = ctx%canvas%lookup("main/plot/l")
    if (slot > 0) count = ctx%canvas%layers(slot)%index_count
end function ui_stats_index_count

subroutine check(condition, backend, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: backend, message
    if (condition) return
    write(*, '(a)') "FAIL [" // backend // "]: " // message
    failures = failures + 1
end subroutine check

end program test_backend_conformance
