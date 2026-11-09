program test_fortui
!! Headless behavioural tests of the core: identity (scopes, keys, duplicates,
!! positional text), layout (rows, three-pane split, UI_FILL, balance), widgets
!! (button, checkbox, real/integer slider, tabs, ellipsis), keys, follow-up
!! frames and idle waiting, backend injection and the optional registry.
use fortui
use fortui_backend_headless, only: headless_backend_t
use fortui_backends, only: ui_init
use fortui_testing, only: ui_inject_pointer, ui_inject_key, ui_stats, ui_stats_t, &
    ui_node_rect, ui_node_text, ui_node_count, ui_focused_id
use fortui_text, only: text_fit, text_width, utf8_length, text_set_metrics, &
    text_set_mono_metrics, text_use_fixed_metrics, TEXT_STYLE_MONO, TEXT_MAX_CODEPOINT
use fortui_tui, only: tui_map_key
use fortui_input, only: KEY_NONE
implicit none

integer :: stat, sel, deg, k, n_before
real :: gain, x, y, w, h, x2, y2, w2, h2
logical :: checked, clicked, changed, flags(3)
type(ui_stats_t) :: st

call test_text_fit()
call test_tui_keys()

! --- registry: explicit names, no fallback ---------------------------------------
call ui_init("no-such-backend", 800, 600, "test", stat=stat)
call check(stat /= 0 .and. .not. ui_is_initialized(), &
    "unknown backend name is an error")
call ui_init("headless", 800, 600, "test", stat=stat)
call check(stat == 0 .and. trim(ui_get_backend()) == "headless", "registry headless")
call ui_shutdown()

! --- injection ---------------------------------------------------------------------
call ui_init(headless_backend_t(), 800, 600, "test", stat=stat)
call check(stat == 0 .and. trim(ui_get_backend()) == "headless", "injected headless")

gain = 50.0
checked = .false.
deg = 3
sel = 1
flags = .true.

call ui_frame_begin()
call text("Title", style=UI_TITLE)
call row_begin(8.0)
clicked = button("save", "Save")
call check(.not. clicked, "button is not spuriously activated")
call check(.not. checkbox("check", checked, "Check"), "checkbox not spuriously toggled")
call row_end()
call check(.not. slider("gain", 0.0, 100.0, gain, step=1.0, width=200.0), &
    "slider unchanged")
call ui_present()
call check(ui_node_count() == 4, "frame has four nodes (static text without id)")
call check(ui_node_rect("save", x, y, w, h), "button found by id")
call check(abs(x) < 1e-6 .and. abs(y - 32.5) < 1e-4, "row starts below the title")
call check(ui_node_rect("check", x2, y2, w2, h2) .and. abs(x2 - (x + w + 8.0)) < 1e-4, &
    "row advances by width plus gap")

! --- click, activation once, follow-up frame, idle wait -----------------------------
call click_at(x + 5.0, y + 5.0)
call check(clicked, "release on the pressed button activates it")
st = ui_stats()
call check(.not. st%last_present_waits .and. st%followups >= 1, &
    "activation schedules a follow-up frame")
call compose_basic()
call check(.not. clicked, "activation is consumed once")
st = ui_stats()
call check(st%last_present_waits, "follow-up frame without input may wait")
n_before = st%waits
call compose_basic()
st = ui_stats()
call check(st%waits == n_before + 1, "next poll was asked to wait")
call ui_inject_pointer(400.0, 400.0, .false.)
call compose_basic()
st = ui_stats()
call check(st%last_present_waits, "pointer motion alone needs no follow-up frame")

! --- keys: Escape is an ordinary key --------------------------------------------------
call ui_inject_key(KEY_ESCAPE)
call ui_frame_begin()
call check(ui_key_pressed(KEY_ESCAPE), "Escape reaches the application")
call ui_present()
call check(.not. ui_should_close(), "Escape does not quit")
st = ui_stats()
call check(.not. st%last_present_waits, "handled shortcut schedules a follow-up")
call ui_frame_begin()
call check(.not. ui_key_pressed(KEY_ESCAPE), "shortcut key lasts one frame")
call ui_present()

! --- scopes, keys, duplicates ---------------------------------------------------------
call ui_frame_begin()
call column_begin(4.0, id="list")
do k = 1, 3
    if (checkbox("flag", flags(k), "Flag " // ui_str(k), key=k)) continue
end do
changed = checkbox("flag", flags(1), "again", key=1)
call text("static")
call text("static")
call column_end()
call ui_present()
call check(ui_node_rect("list/flag#2", x, y, w, h), "scoped keyed identity")
call check(.not. ui_node_rect("flag#2", x, y, w, h), "identity includes the scope")
st = ui_stats()
call check(st%duplicates == 1 .and. ui_node_count() == 5, &
    "duplicate keyed id reported and skipped; repeated static text is fine")
call click_node("list/flag#2")
call check(.not. flags(2) .and. flags(1) .and. flags(3), &
    "click toggles exactly the keyed checkbox")

! --- three-pane split, fill width, ellipsis, balance ----------------------------------
call ui_inject_resize_frame()
call check(ui_node_rect("main/left", x, y, w, h) .and. abs(x) < 1e-6 .and. &
    abs(w - 200.0) < 1e-4, "first pane fixed width")
call check(ui_node_rect("main/mid", x, y, w, h) .and. abs(x - 210.0) < 1e-4 .and. &
    abs(w - (800.0 - 200.0 - 150.0 - 20.0)) < 1e-4, "middle pane fills, UI_FILL width")
call check(ui_node_rect("main/right", x, y, w, h) .and. abs(x - 650.0) < 1e-4 .and. &
    abs(w - 150.0) < 1e-4, "last pane fixed width at the right edge")
call check(ui_node_rect("main/long", x, y, w, h) .and. abs(w - 150.0) < 1e-4, &
    "ellipsis text is limited to the pane width")
call check(utf8_length(ui_node_text("main/long")) == 60, &
    "semantic text keeps the full value")
call ui_frame_begin()
call column_begin()
call row_begin()
call text("unbalanced")
call ui_present()
call ui_frame_begin()
call text("next frame starts at the top", id="top")
call ui_present()
call check(ui_node_rect("top", x, y, w, h) .and. abs(y) < 1e-6, &
    "unbalanced containers are reported and closed at present")

! --- tabs and integer slider ----------------------------------------------------------
call compose_tabs()
call check(ui_node_rect("tab#2", x, y, w, h) .and. abs(w - 400.0) < 1e-4, &
    "tabs share the width equally")
call click_node("tab#2")
call check(sel == 2, "clicking a tab selects it")
call compose_tabs()
call ui_inject_key(KEY_ARROW_LEFT)
call compose_tabs()
call check(sel == 1, "arrow key on the focused tab moves the selection")
call check(ui_focused_id() == "tab#2", "focus stays on the clicked tab")
call check(ui_node_rect("deg", x, y, w, h), "integer slider present")
call ui_inject_pointer(x + 0.5 * w, y + 0.5 * h, .true.)
call compose_tabs()
call ui_inject_pointer(x + 0.5 * w, y + 0.5 * h, .false.)
call compose_tabs()
call check(deg == 15, "integer slider maps the pointer to the nearest integer")
call ui_inject_key(KEY_ARROW_RIGHT)
call compose_tabs()
call check(deg == 16, "integer slider steps by one key press")

! --- fixed-height rows centre their items; tabs take an explicit width -------
call ui_frame_begin()
call row_begin(8.0, height=48.0)
call text("Label", id="label")
if (button("go", "Go")) continue
call row_end()
if (tabs("narrow", [character(8) :: "A", "B"], sel, width=200.0)) continue
call ui_present()
call check(ui_node_rect("label", x, y, w, h) .and. abs(y + 0.5 * h - 24.0) < 1e-4, &
    "text centred in a 48-unit row")
call check(ui_node_rect("go", x2, y2, w2, h2) .and. abs(y2 + 0.5 * h2 - 24.0) < 1e-4, &
    "button centred in the same row")
call check(ui_node_rect("narrow#2", x, y, w, h) .and. abs(y - 48.0) < 1e-4 &
    .and. abs(x - 100.0) < 1e-4 .and. abs(w - 100.0) < 1e-4, &
    "row is 48 tall; tabs share the given width")

! --- a link is laid out like text and activated like a button ---------------
call compose_link()
call check(ui_node_rect("docs", x, y, w, h) .and. ui_node_rect("plain", x2, y2, w2, h2) .and. &
    abs(w - w2) < 1e-4 .and. abs(h - h2) < 1e-4, "a link is as large as its text")
call check(.not. clicked, "a link is not spuriously activated")
call ui_inject_pointer(x + 2.0, y + 2.0, .true.)
call compose_link()
call ui_inject_pointer(x + 2.0, y + 2.0, .false.)
call compose_link()
call check(clicked, "releasing the pointer on a link activates it")
call compose_link()
call check(.not. clicked, "a link activation is consumed once")

call ui_shutdown()
call check(.not. ui_is_initialized(), "shutdown releases context")
print *, "fortui tests passed"

contains

subroutine compose_basic()
    call ui_frame_begin()
    call text("Title", style=UI_TITLE)
    call row_begin(8.0)
    clicked = button("save", "Save")
    if (checkbox("check", checked, "Check")) continue
    call row_end()
    if (slider("gain", 0.0, 100.0, gain, step=1.0, width=200.0)) continue
    call ui_present()
end subroutine compose_basic

subroutine click_at(px, py)
    real, intent(in) :: px, py
    call ui_inject_pointer(px, py, .true.)
    call compose_basic()
    call ui_inject_pointer(px, py, .false.)
    call compose_basic()
end subroutine click_at

subroutine click_node(id)
    character(*), intent(in) :: id
    real :: nx, ny, nw, nh
    call check(ui_node_rect(id, nx, ny, nw, nh), "node present: " // id)
    call ui_inject_pointer(nx + 0.5 * nw, ny + 0.5 * nh, .true.)
    call compose_last()
    call ui_inject_pointer(nx + 0.5 * nw, ny + 0.5 * nh, .false.)
    call compose_last()
end subroutine click_node

subroutine compose_link()
    call ui_frame_begin()
    clicked = link("docs", "Read the docs", "/docs")
    call text("Read the docs", id="plain")
    call ui_present()
end subroutine compose_link

subroutine compose_last()
    !! Re-run whichever composition the current section uses.
    if (ui_node_rect("tab#1", x, y, w, h)) then
        call compose_tabs()
    else
        call ui_frame_begin()
        call column_begin(4.0, id="list")
        do k = 1, 3
            if (checkbox("flag", flags(k), "Flag " // ui_str(k), key=k)) continue
        end do
        call column_end()
        call ui_present()
    end if
end subroutine compose_last

subroutine ui_inject_resize_frame()
    call ui_frame_begin()
    call split_begin("main", first=200.0, last=150.0, gap=10.0)
    call text("left", width=UI_FILL, id="left")
    call split_next()
    call text("mid", width=UI_FILL, id="mid")
    call split_next()
    call text(repeat("x", 59) // "é", ellipsis=.true., id="long")
    call text("right", width=UI_FILL, id="right")
    call split_end()
    call ui_present()
end subroutine ui_inject_resize_frame

subroutine compose_tabs()
    call ui_frame_begin()
    if (tabs("tab", [character(8) :: "Search", "Filters"], sel)) continue
    if (slider("deg", 0, 30, deg, width=300.0)) continue
    call ui_present()
end subroutine compose_tabs

subroutine test_text_fit()
    !! Fixed metrics: every code point advances 0.5 * size (10 units at 20).
    character(len=:), allocatable :: r
    character(len=*), parameter :: ell = char(226) // char(128) // char(166)

    r = text_fit("abcdefghij", 20.0, 100.0)
    call check(r == "abcdefghij", "fitting text is unchanged")
    r = text_fit("abcdefghij", 20.0, 55.0)
    call check(r == "abcd" // ell, "prefix plus ellipsis fits the width")
    call check(text_width(r, 20.0) <= 55.0, "fitted width within the limit")
    r = text_fit("äöüäöü", 20.0, 40.0)
    call check(r == "äöü" // ell, "ellipsis cuts at code point boundaries")
    r = text_fit("abc", 20.0, 5.0)
    call check(r == ell, "only the ellipsis when nothing fits")
    call check(ui_str(42) == "42" .and. ui_str(-7) == "-7", "ui_str integers")
    call check(ui_str(3.14159, 2) == "3.14" .and. ui_str(0.5) == "0.50", "ui_str reals")
    block
        real :: table(0:TEXT_MAX_CODEPOINT, 2)
        table = 0.5
        call text_set_metrics(table, [0.5, 0.55], 1.25)
        call text_set_mono_metrics(0.6)
        call check(abs(text_width("abc", 10.0, TEXT_STYLE_MONO) - 18.0) < 1e-4 .and. &
            abs(text_width("abc", 10.0) - 15.0) < 1e-4, "monospaced text has its own advance")
        call text_use_fixed_metrics()
    end block
end subroutine test_text_fit

subroutine test_tui_keys()
    !! termbox2 key codes (termbox2.h) map to backend-neutral keys.
    call check(tui_map_key(13) == KEY_ENTER .and. tui_map_key(27) == KEY_ESCAPE .and. &
        tui_map_key(9) == KEY_TAB, "TUI enter/escape/tab")
    call check(tui_map_key(8) == KEY_BACKSPACE .and. &
        tui_map_key(127) == KEY_BACKSPACE, &
        "TUI both backspace codes")
    call check(tui_map_key(65535 - 13) == KEY_DELETE .and. &
        tui_map_key(65535 - 14) == KEY_HOME .and. tui_map_key(65535 - 15) == KEY_END, &
        "TUI delete/home/end")
    call check(tui_map_key(65535 - 16) == KEY_PAGE_UP .and. &
        tui_map_key(65535 - 17) == KEY_PAGE_DOWN, "TUI page up/down")
    call check(tui_map_key(65535 - 18) == KEY_ARROW_UP .and. &
        tui_map_key(65535 - 19) == KEY_ARROW_DOWN .and. &
        tui_map_key(65535 - 20) == KEY_ARROW_LEFT .and. &
        tui_map_key(65535 - 21) == KEY_ARROW_RIGHT, "TUI arrows")
    call check(tui_map_key(65535) == KEY_NONE .and. &
        tui_map_key(65535 - 23) == KEY_NONE, &
        "TUI function and mouse codes are not named keys")
end subroutine test_tui_keys

subroutine check(condition, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: message
    if (.not. condition) then
        write(*, '(a)') "FAIL: " // trim(message)
        error stop 1
    end if
end subroutine check

end program test_fortui
