program test_text_area
    !! A text field of several lines, headless: Enter starts a new line and does
    !! not submit, Up and Down keep the column, Home and End act on the caret's
    !! line, a click places the caret on the clicked line, and the field is a
    !! textarea in HTML. A field of one line still submits on Enter.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_html, only: ui_frame_html
    use fortui_testing, only: ui_inject_pointer, ui_inject_key, ui_inject_text, ui_node_rect, &
        ui_focused_id
    use fortui_text, only: text_use_fixed_metrics, text_line_height
    implicit none

    character(len=*), parameter :: NL = new_line('a')
    character(len=:), allocatable :: note, one, html
    logical :: changed, submitted, one_submitted, found
    real :: x, y, w, h, single_h
    integer :: stat

    note = ""
    one = ""
    call text_use_fixed_metrics()
    call ui_init(headless_backend_t(), 800, 600, "text area", stat=stat)
    call check(stat == 0, "headless backend starts")
    call frame()
    found = ui_node_rect("one", x, y, w, single_h)
    found = ui_node_rect("note", x, y, w, h)
    call check(found .and. h > single_h .and. h >= 3.0 * text_line_height(14.0), &
        "three lines are taller than one")

    call click(x + 10.0, y + 10.0)
    call check(ui_focused_id() == "note", "a click focuses the field")
    call ui_inject_text("ab")
    call frame()
    call ui_inject_key(KEY_ENTER)
    call frame()
    call check(.not. submitted, "Enter does not submit")
    call ui_inject_text("cd")
    call frame()
    call check(changed .and. note == "ab"//NL//"cd" .and. .not. submitted, &
        "Enter starts a new line and does not submit: "//note)

    call ui_inject_key(KEY_ARROW_UP)
    call frame()
    call ui_inject_text("X")
    call frame()
    call check(note == "abX"//NL//"cd", "Up keeps the column: "//note)
    call ui_inject_key(KEY_HOME)
    call frame()
    call ui_inject_text("Y")
    call frame()
    call check(note == "YabX"//NL//"cd", "Home goes to the start of the line: "//note)
    call ui_inject_key(KEY_ARROW_DOWN)
    call ui_inject_key(KEY_END)
    call frame()
    call ui_inject_text("Z")
    call frame()
    call check(note == "YabX"//NL//"cdZ", "Down and End reach the end of the next line: "//note)
    call ui_inject_key(KEY_ARROW_UP)
    call ui_inject_key(KEY_END)
    call ui_inject_key(KEY_BACKSPACE)
    call frame()
    call check(note == "Yab"//NL//"cdZ", "End stops at the end of its own line: "//note)

    ! A click on the second line puts the caret there.
    call click(x + 7.0, y + 6.0 + 1.5 * text_line_height(14.0))
    call ui_inject_key(KEY_HOME)
    call frame()
    call ui_inject_text("!")
    call frame()
    call check(note == "Yab"//NL//"!cdZ", "a click places the caret on its line: "//note)

    html = ui_frame_html()
    call check(index(html, '<textarea rows="3"') > 0 .and. &
        index(html, '>Yab'//NL//'!cdZ</textarea>') > 0, "the field is a textarea in HTML: "//html)

    ! One line: Enter submits and adds nothing.
    found = ui_node_rect("one", x, y, w, h)
    call click(x + 10.0, y + 10.0)
    call ui_inject_text("q")
    call frame()
    call ui_inject_key(KEY_ENTER)
    call frame()
    call check(one == "q" .and. one_submitted, "a field of one line submits on Enter")

    call ui_shutdown()
    print *, "fortui text area tests passed"

contains

    subroutine frame()
        call ui_frame_begin()
        changed = text_input("note", note, placeholder="Note", submitted=submitted, lines=3)
        if (text_input("one", one, submitted=one_submitted)) continue
        call ui_present()
    end subroutine frame

    subroutine click(px, py)
        real, intent(in) :: px, py
        call ui_inject_pointer(px, py, .true.)
        call frame()
        call ui_inject_pointer(px, py, .false.)
        call frame()
    end subroutine click

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            error stop 1
        end if
    end subroutine check

end program test_text_area
