program test_keys_focus
    !! Keyboard shortcuts (ui_shortcut), moving the focus (ui_focus), asking a
    !! widget into view (ui_reveal), and what a host is told about a key before
    !! its own default action.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_key, ui_inject_text, ui_inject_time, ui_inject_press, &
        ui_host_key_claim, ui_focused_id, ui_node_revealed, ui_stats, ui_stats_t
    use fortui_input, only: KEY_NONE, MOD_CTRL, MOD_SHIFT, MOD_META, FOCUS_CONTROL, &
        FOCUS_FIELD, FOCUS_EDITOR, CLAIM_DELIVER, CLAIM_PREVENT
    use fortui_html, only: ui_frame_html
    use fortui_tui, only: tui_ctrl_letter
    implicit none

    integer, parameter :: BOTH = CLAIM_DELIVER + CLAIM_PREVENT
    integer, parameter :: IN_FIELD = 256 * FOCUS_FIELD, IN_EDITOR = 256 * FOCUS_EDITOR
    integer, parameter :: REPEATED = 32, ON_MAC = 16

    integer :: n_j, n_q, n_enter, n_escape, n_down, n_go, n_o, n_modk, n_bad, n_click
    integer :: stat, at, tag_first, tag_last
    logical :: submitted, with_escape
    character(len=:), allocatable :: name, notes, focus_first, focus_last, reveal, html, plain
    type(ui_stats_t) :: stats

    n_j = 0; n_q = 0; n_enter = 0; n_escape = 0; n_down = 0; n_go = 0; n_o = 0
    n_modk = 0; n_bad = 0; n_click = 0
    name = ""; notes = ""; focus_first = ""; focus_last = ""; reveal = ""
    with_escape = .true.

    call ui_init(headless_backend_t(), 600, 400, "keys", stat=stat)
    call frame()

    ! --- keys without a focus -------------------------------------------------
    call ui_inject_text("j")
    call frame()
    call check(n_j == 1, "a typed character presses its shortcut")
    stats = ui_stats()
    call check(.not. stats%last_present_waits, "a pressed shortcut schedules a follow-up frame")
    call frame()
    call check(n_j == 1, "a shortcut is pressed in one frame only")
    call ui_inject_text("?")
    call frame()
    call check(n_q == 1, "a shifted character is the character typed")
    call ui_inject_key(KEY_ENTER)
    call ui_inject_key(KEY_ARROW_DOWN)
    call frame()
    call check(n_enter == 1 .and. n_down == 1, "named keys press their shortcuts")
    call check(n_bad == 0, "a chord that cannot be read is never pressed")

    ! --- two keys in a row ----------------------------------------------------
    call ui_inject_time(10.0d0)
    call ui_inject_text("g")
    call frame()
    call ui_inject_time(10.5d0)
    call ui_inject_text("o")
    call frame()
    call check(n_go == 1 .and. n_o == 0, "the second key completes the chord and is not a key alone")
    call ui_inject_time(20.0d0)
    call ui_inject_text("g")
    call frame()
    call ui_inject_time(21.5d0)
    call ui_inject_text("o")
    call frame()
    call check(n_go == 1 .and. n_o == 1, "after a pause the second key stands alone")
    call ui_inject_text("go")
    call frame()
    call check(n_go == 2 .and. n_o == 1, "both keys of a chord in one frame")
    call ui_inject_text("o")
    call frame()
    call check(n_go == 2 .and. n_o == 2, "a completed chord is not continued")

    ! --- modifiers and repeats ------------------------------------------------
    call ui_inject_press(KEY_NONE, iachar('k'), MOD_CTRL)
    call frame()
    call check(n_modk == 1, "mod is Ctrl")
    call ui_inject_press(KEY_NONE, iachar('k'), MOD_META, mac=.true.)
    call frame()
    call check(n_modk == 2, "mod is Cmd on macOS")
    call ui_inject_press(KEY_NONE, iachar('k'), MOD_META)
    call ui_inject_press(KEY_NONE, iachar('k'), MOD_CTRL, mac=.true.)
    call ui_inject_press(KEY_NONE, iachar('K'), MOD_CTRL + MOD_SHIFT)
    call ui_inject_text("k")
    call frame()
    call check(n_modk == 2, "other modifiers are other chords")
    call ui_inject_press(KEY_NONE, iachar('K'), MOD_CTRL)
    call frame()
    call check(n_modk == 3, "with a modifier a letter ignores case")
    call ui_inject_press(KEY_NONE, iachar('j'), 0, repeat=.true.)
    call ui_inject_press(KEY_ARROW_DOWN, 0, 0, repeat=.true.)
    call frame()
    call check(n_j == 1 .and. n_down == 2, "key repeats count only where asked for")

    ! --- focus ----------------------------------------------------------------
    focus_first = "name"
    call frame()
    call check(ui_focused_id() == "c/name", "ui_focus before the control is composed")
    html = ui_frame_html()
    at = index(html, " autofocus")
    call check(at > 0, "the focused control is marked in the first frame's HTML")
    tag_first = index(html(1:at), "<", back=.true.)
    tag_last = at + index(html(at:), ">") - 1
    call check(index(html(tag_first:tag_last), 'data-id="c/name"') > 0 .and. &
        index(html(at + 1:), " autofocus") == 0, "and no other element is")
    call ui_inject_text("j")
    call frame()
    call check(name == "j" .and. n_j == 1, "a text field keeps what is typed into it")
    call ui_inject_key(KEY_ARROW_DOWN)
    call ui_inject_key(KEY_ENTER)
    call frame()
    call check(n_down == 3 .and. n_enter == 2 .and. submitted, &
        "a text field gives ArrowDown and Enter to the application, and Enter still submits")
    call ui_inject_press(KEY_NONE, iachar('k'), MOD_CTRL)
    call frame()
    call check(n_modk == 4 .and. name == "j", "a chord with Ctrl is pressed in a text field")
    call ui_inject_key(KEY_ESCAPE)
    call frame()
    call check(n_escape == 1 .and. ui_focused_id() == "", &
        "Escape reaches the application and leaves the field")

    focus_last = "notes"
    call frame()
    call check(ui_focused_id() == "c/notes", "ui_focus after the control is composed")
    call ui_inject_text("a")
    call frame()
    call ui_inject_key(KEY_ENTER)
    call ui_inject_key(KEY_ARROW_DOWN)
    call frame()
    call ui_inject_text("j")
    call frame()
    call check(notes == "a" // new_line('a') // "j" .and. n_enter == 2 .and. n_down == 3 &
        .and. n_j == 1, "a field of several lines keeps Enter, the arrows and what is typed")
    call ui_inject_key(KEY_ESCAPE)
    call frame()
    call check(n_escape == 2, "Escape reaches the application from a field of several lines")

    focus_last = "go"
    call frame()
    call check(ui_focused_id() == "c/go", "ui_focus on a button")
    call ui_inject_key(KEY_ENTER)
    call ui_inject_text("j")
    call frame()
    call check(n_click == 1 .and. n_enter == 2 .and. n_j == 2, &
        "Enter on a focused button activates it; a character is still a shortcut")
    focus_last = "off"
    call frame()
    focus_first = "nothing"
    call frame()
    call check(ui_focused_id() == "c/go", "a disabled or absent control does not take the focus")

    ! --- reveal ---------------------------------------------------------------
    plain = ui_frame_html()
    reveal = "go"
    call frame()
    call check(ui_node_revealed("c/go") .and. .not. ui_node_revealed("c/name"), &
        "ui_reveal marks its widget in the frame")
    call check(ui_frame_html() == plain, "the first frame's HTML does not scroll")
    call frame()
    call check(.not. ui_node_revealed("c/go"), "for one frame")

    ! --- what a host is told at the moment of a key ---------------------------
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('j'), 0.0d0) == BOTH, &
        "a registered key is delivered and the host's action prevented")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('x'), 0.0d0) == 0, &
        "a key nobody asked for is the host's")
    call check(ui_host_key_claim(KEY_NONE, IN_FIELD, iachar('j'), 0.0d0) == 0 .and. &
        ui_host_key_claim(KEY_ARROW_DOWN, IN_EDITOR, 0, 0.0d0) == 0 .and. &
        ui_host_key_claim(KEY_ENTER, 256 * FOCUS_CONTROL, 0, 0.0d0) == 0, &
        "keys the focused element uses itself are never taken from it")
    call check(ui_host_key_claim(KEY_ARROW_DOWN, IN_FIELD, 0, 0.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_ENTER, IN_FIELD, 0, 0.0d0) == BOTH, &
        "a text field gives up ArrowDown and Enter")
    call check(ui_host_key_claim(KEY_NONE, MOD_CTRL + IN_EDITOR, iachar('k'), 0.0d0) == BOTH &
        .and. ui_host_key_claim(KEY_NONE, MOD_META + ON_MAC, iachar('k'), 0.0d0) == BOTH &
        .and. ui_host_key_claim(KEY_NONE, MOD_META, iachar('k'), 0.0d0) == 0, &
        "a chord with the command modifier is claimed in any field")
    call check(ui_host_key_claim(KEY_NONE, REPEATED, iachar('j'), 0.0d0) == CLAIM_PREVENT &
        .and. ui_host_key_claim(KEY_ARROW_DOWN, REPEATED, 0, 0.0d0) == BOTH, &
        "a repeat is prevented like the press, and delivered only where asked for")
    call check(ui_host_key_claim(KEY_ESCAPE, 0, 0, 0.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_ESCAPE, IN_FIELD, 0, 0.0d0) == CLAIM_DELIVER, &
        "a registered Escape keeps its default in a field")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('i'), 1.0d0) == 0, &
        "the second key of a chord alone is the host's")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('g'), 2.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('i'), 2.5d0) == BOTH, &
        "both keys of a chord are claimed")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('g'), 5.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('i'), 7.0d0) == 0, &
        "but not the second after a pause")
    with_escape = .false.
    call frame()
    call check(ui_host_key_claim(KEY_ESCAPE, 0, 0, 0.0d0) == CLAIM_DELIVER, &
        "Escape always reaches the application")
    call ui_shutdown()

    ! --- the host's answer and the frames agree -------------------------------
    n_j = 0; n_enter = 0; n_down = 0; n_go = 0; n_o = 0; name = ""
    with_escape = .true.
    call ui_init(headless_backend_t(), 600, 400, "keys", stat=stat)
    call frame()
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('g'), 2.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('o'), 2.4d0) == BOTH, "g o at the host")
    call frame()
    call check(n_go == 1 .and. n_o == 0, "a chord the host saw completed is that chord in the frame")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('g'), 4.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('x'), 4.2d0) == 0 .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('o'), 4.4d0) == BOTH, "g x o at the host")
    call frame()
    call check(n_go == 1 .and. n_o == 1, "a key nobody asked for between the two ends the chord")
    call check(ui_host_key_claim(KEY_NONE, 0, iachar('g'), 6.0d0) == BOTH .and. &
        ui_host_key_claim(KEY_NONE, IN_FIELD, iachar('o'), 6.2d0) == 0 .and. &
        ui_host_key_claim(KEY_NONE, 0, iachar('o'), 6.4d0) == BOTH, "g, o typed into a field, o")
    call frame()
    call check(n_go == 1 .and. n_o == 2, "a character typed into a field between the two ends the chord")

    ! --- the same chord several times before a frame --------------------------
    call ui_inject_text("jjj")
    call frame()
    stats = ui_stats()
    call check(n_j == 1 .and. .not. stats%last_present_waits, &
        "a chord pressed again before the frame waits for the next one, which is scheduled")
    call frame()
    call frame()
    call check(n_j == 3, "and every press counts")
    call frame()
    call check(n_j == 3, "once")
    do at = 1, 5
        call ui_inject_press(KEY_ARROW_DOWN, 0, 0, repeat=at > 1)
    end do
    do at = 1, 5
        call frame()
    end do
    call check(n_down == 5, "every repeat of a held key counts where repeats are asked for")
    focus_first = "name"
    call frame()
    call ui_inject_text(repeat("a", 40))
    call ui_inject_press(KEY_ENTER, 0, 0)
    call frame()
    call check(name == repeat("a", 40) .and. n_enter == 1, &
        "a long text typed into a field does not cost the key after it")
    call ui_shutdown()

    ! --- terminal -------------------------------------------------------------
    call check(tui_ctrl_letter(11) == iachar('k') .and. tui_ctrl_letter(1) == iachar('a') .and. &
        tui_ctrl_letter(26) == iachar('z'), "a terminal's Ctrl+letter is that letter with Ctrl")
    call check(tui_ctrl_letter(8) == 0 .and. tui_ctrl_letter(9) == 0 .and. &
        tui_ctrl_letter(13) == 0 .and. tui_ctrl_letter(27) == 0 .and. tui_ctrl_letter(0) == 0, &
        "but not what terminals send for Backspace, Tab, Enter and Escape")

    print *, "fortui keys and focus tests passed"

contains

    subroutine frame()
        call ui_frame_begin()
        if (ui_shortcut("j")) n_j = n_j + 1
        if (ui_shortcut("?")) n_q = n_q + 1
        if (ui_shortcut("Enter")) n_enter = n_enter + 1
        if (with_escape) then
            if (ui_shortcut("Escape")) n_escape = n_escape + 1
        end if
        if (ui_shortcut("ArrowDown", repeat=.true.)) n_down = n_down + 1
        if (ui_shortcut("g o")) n_go = n_go + 1
        if (ui_shortcut("g i")) continue
        if (ui_shortcut("o")) n_o = n_o + 1
        if (ui_shortcut("mod+k")) n_modk = n_modk + 1
        if (ui_shortcut("hyper+x") .or. ui_shortcut("a b c") .or. ui_shortcut("")) n_bad = n_bad + 1
        call column_begin(8.0, id="c")
        if (len(focus_first) > 0) call ui_focus(focus_first)
        focus_first = ""
        if (button("go", "Go")) n_click = n_click + 1
        if (button("off", "Off", enabled=.false.)) continue
        if (text_input("name", name, submitted=submitted)) continue
        if (text_input("notes", notes, lines=3)) continue
        if (len(focus_last) > 0) call ui_focus(focus_last)
        focus_last = ""
        if (len(reveal) > 0) call ui_reveal(reveal)
        reveal = ""
        call column_end()
        call ui_present()
    end subroutine frame

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            error stop 1
        end if
    end subroutine check

end program test_keys_focus
