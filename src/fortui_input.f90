module fortui_input
    !! Backend-neutral input snapshot and routing against the previous semantic frame.
    use fortui_frame, only: ui_frame_t
    use fortui_text, only: utf8_decode
    implicit none
    private

    ! Backend-neutral named keys. Printable characters arrive as typed text.
    integer, parameter, public :: KEY_NONE = 0
    integer, parameter, public :: KEY_ENTER = 1
    integer, parameter, public :: KEY_ESCAPE = 2
    integer, parameter, public :: KEY_TAB = 3
    integer, parameter, public :: KEY_BACKSPACE = 4
    integer, parameter, public :: KEY_DELETE = 5
    integer, parameter, public :: KEY_HOME = 6
    integer, parameter, public :: KEY_END = 7
    integer, parameter, public :: KEY_ARROW_LEFT = 8
    integer, parameter, public :: KEY_ARROW_RIGHT = 9
    integer, parameter, public :: KEY_ARROW_UP = 10
    integer, parameter, public :: KEY_ARROW_DOWN = 11
    integer, parameter, public :: KEY_PAGE_UP = 12
    integer, parameter, public :: KEY_PAGE_DOWN = 13
    integer, parameter, public :: KEY_SPACE = 14
    integer, parameter, public :: KEY_INSERT = 15
    integer, parameter, public :: MAX_FRAME_KEYS = 32
    integer, parameter, public :: MAX_FRAME_TEXT = 256
    ! Semantic events from hosts whose controls handle input themselves (the
    ! browser): the element they concern is known, so no pointer routing is needed.
    integer, parameter, public :: HOST_ACTIVATE = 1, HOST_FOCUS = 2, HOST_BLUR = 3, &
        HOST_VALUE = 4, HOST_SUBMIT = 5
    integer, parameter, public :: MAX_HOST_EVENTS = 16

    type, public :: host_event_t
        integer :: kind = 0
        character(len=96) :: id = ""
        character(len=:), allocatable :: value
    end type host_event_t
    ! Modifiers of a key press. In a chord, MOD_PRIMARY is the platform's command
    ! modifier: Cmd on macOS, Ctrl elsewhere.
    integer, parameter, public :: MOD_CTRL = 1, MOD_ALT = 2, MOD_SHIFT = 4, MOD_META = 8, &
        MOD_PRIMARY = 16
    ! What the control with the focus does itself with unmodified keys: nothing;
    ! Enter and Space (a button); also the navigation keys (a slider); all but
    ! ArrowUp, ArrowDown, Enter and Escape (a text field of one line); all but
    ! Escape (a text field of several lines).
    integer, parameter, public :: FOCUS_UNKNOWN = -1, FOCUS_PLAIN = 0, FOCUS_CONTROL = 1, &
        FOCUS_RANGE = 2, FOCUS_FIELD = 3, FOCUS_EDITOR = 4
    ! Answer to a host that asks about a key press before its own default action.
    integer, parameter, public :: CLAIM_DELIVER = 1, CLAIM_PREVENT = 2
    ! Presses waiting for their frame; further ones are dropped.
    integer, parameter, public :: MAX_PENDING_PRESSES = 1024
    ! The second key of a chord such as "g o" follows the first within this time.
    double precision, parameter, public :: CHORD_SECONDS = 1.0d0

    type, public :: key_press_t
        !! A key press with its modifiers: a named key (KEY_*) or the code point
        !! of the character it types.
        integer :: key = KEY_NONE
        integer :: code = 0
        integer :: mods = 0
        logical :: repeat = .false.
        ! The command modifier of the host is Meta (macOS).
        logical :: mac = .false.
        ! FOCUS_* as the host saw it, or FOCUS_UNKNOWN: the runtime's own focus.
        integer :: focus = FOCUS_UNKNOWN
        double precision :: time = 0.0d0
        ! Set when the press is sorted, once: used by the focused control
        ! itself, a press some chord of the last frame presses, or the second
        ! key of a chord whose first key is kept here.
        logical :: sorted = .false.
        logical :: consumed = .false.
        logical :: wanted = .false.
        logical :: final = .false.
        integer :: first_key = KEY_NONE
        integer :: first_code = 0
        integer :: first_mods = 0
    end type key_press_t

    type, public :: chord_t
        !! One key, or two keys in a row; steps = 0 is no chord.
        integer :: steps = 0
        integer :: key(2) = KEY_NONE
        integer :: code(2) = 0
        integer :: mods(2) = 0
        logical :: repeat = .false.
    end type chord_t

    type, public :: key_track_t
        !! The press a following one may complete a chord with.
        logical :: armed = .false.
        type(key_press_t) :: prev
    end type key_track_t

    real, parameter, public :: DRAG_THRESHOLD = 4.0
    real, parameter, public :: DOUBLE_CLICK_SECONDS = 0.4
    real, parameter, public :: DOUBLE_CLICK_DISTANCE = 6.0

    type, public :: input_state_t
        ! Host window in logical units and framebuffer pixels per unit; persistent.
        integer :: width = 1
        integer :: height = 1
        real :: scale = 1.0
        ! Positional uncertainty of the pointer in logical units (half a terminal
        ! cell for cell-based mice); hit tests may widen their tolerance by it.
        real :: pointer_slop = 0.0
        real :: pointer_x = -1.0
        real :: pointer_y = -1.0
        real :: pointer_dx = 0.0
        real :: pointer_dy = 0.0
        logical :: pointer_down = .false.
        logical :: pointer_pressed = .false.
        logical :: pointer_released = .false.
        integer :: scroll_y = 0
        real :: wheel = 0.0
        integer :: key_count = 0
        integer :: keys(MAX_FRAME_KEYS) = KEY_NONE
        ! Typed-text length when each key arrived, preserving key/text ordering.
        integer :: key_text_pos(MAX_FRAME_KEYS) = 0
        character(len=MAX_FRAME_TEXT) :: text = ""
        integer :: text_len = 0
        logical :: resized = .false.
        double precision :: time = 0.0d0
        real :: press_x = 0.0
        real :: press_y = 0.0
        logical :: drag_exceeded = .false.
        character(len=96) :: click_id = ""
        character(len=96) :: double_click_id = ""
        character(len=96) :: last_click_id = ""
        double precision :: last_click_time = -1.0d9
        real :: last_click_x = 0.0
        real :: last_click_y = 0.0
        character(len=96) :: focus_id = ""
        character(len=96) :: active_id = ""
        character(len=96) :: activated_id = ""
        character(len=96) :: scroll_id = ""
        integer :: host_count = 0
        type(host_event_t) :: host(MAX_HOST_EVENTS)
        ! Key presses for shortcuts, oldest first. The first press_shown are the
        ! ones of this frame; the others wait, so that no frame has the same
        ! chord pressed twice.
        integer :: press_count = 0
        integer :: press_shown = 0
        type(key_press_t), allocatable :: presses(:)
        ! Chords asked for in the frame being composed, and those of the last
        ! presented frame, which decide what a host keeps from its default action.
        type(chord_t), allocatable :: chords(:), claimed(:)
        integer :: chord_count = 0
        integer :: claimed_count = 0
        ! Chord progress over all presses in the order they happened.
        type(key_track_t) :: track
    end type input_state_t

    public :: input_begin_frame, input_update_pointer, input_scroll, input_set_key
    public :: input_route, input_activated, input_focused, input_active
    public :: input_hovered, input_key_arrived
    public :: input_type_text, input_set_time, input_wheel_for, input_has_events
    public :: input_host_event, input_apply_host, input_host_value, input_host_submitted
    public :: input_key_press, input_widget_key, input_sort_presses, input_shortcut, input_commit_chords
    public :: input_host_key, input_claims, chord_parse, input_presses_wait

contains

    subroutine input_begin_frame(input)
        type(input_state_t), intent(inout) :: input
        integer :: i

        input%pointer_dx = 0.0
        input%pointer_dy = 0.0
        input%pointer_pressed = .false.
        input%pointer_released = .false.
        input%scroll_y = 0
        input%wheel = 0.0
        input%key_count = 0
        input%text_len = 0
        input%resized = .false.
        input%activated_id = ""
        input%scroll_id = ""
        input%click_id = ""
        input%double_click_id = ""
        input%host_count = 0
        ! The presses the last frame saw are done; those that waited stay.
        do i = input%press_shown + 1, input%press_count
            input%presses(i - input%press_shown) = input%presses(i)
        end do
        input%press_count = input%press_count - input%press_shown
        input%press_shown = 0
    end subroutine input_begin_frame

    logical function input_has_events(input)
        !! Whether this frame's input could change presentation (idle-wait decision).
        type(input_state_t), intent(in) :: input
        input_has_events = abs(input%pointer_dx) > 0.0 .or. &
            abs(input%pointer_dy) > 0.0 .or. input%pointer_pressed .or. &
            input%pointer_released .or. abs(input%wheel) > 0.0 .or. &
            input%key_count > 0 .or. input%text_len > 0 .or. input%resized .or. &
            input%host_count > 0 .or. input%press_count > 0
    end function input_has_events

    pure logical function input_presses_wait(input) result(waiting)
        !! Whether presses wait for a frame after this one.
        type(input_state_t), intent(in) :: input
        waiting = input%press_count > input%press_shown
    end function input_presses_wait

    subroutine input_type_text(input, utf8)
        !! Append committed UTF-8 text typed during this frame.
        type(input_state_t), intent(inout) :: input
        character(*), intent(in) :: utf8
        integer :: n, at, cp, nbytes

        n = min(len(utf8), MAX_FRAME_TEXT - input%text_len)
        if (n <= 0) return
        input%text(input%text_len + 1:input%text_len + n) = utf8(1:n)
        input%text_len = input%text_len + n
        ! Every typed character is also a key press; Space is the named key.
        at = 1
        do while (at <= n)
            call utf8_decode(utf8(1:n), at, cp, nbytes)
            if (cp > 32 .and. cp /= 127) call input_key_press(input, KEY_NONE, cp, 0)
            at = at + nbytes
        end do
    end subroutine input_type_text

    subroutine input_set_time(input, seconds)
        type(input_state_t), intent(inout) :: input
        double precision, intent(in) :: seconds
        input%time = seconds
    end subroutine input_set_time

    real function input_wheel_for(input, id)
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id

        input_wheel_for = 0.0
        if (len_trim(input%scroll_id) > 0 .and. trim(input%scroll_id) == trim(id)) &
            input_wheel_for = input%wheel
    end function input_wheel_for

    subroutine input_update_pointer(input, x, y, down, pressed)
        type(input_state_t), intent(inout) :: input
        real, intent(in) :: x, y
        logical, intent(in) :: down
        logical, intent(in), optional :: pressed

        logical :: was_down

        was_down = input%pointer_down
        if (input%pointer_x >= 0.0) then
            input%pointer_dx = input%pointer_dx + x - input%pointer_x
            input%pointer_dy = input%pointer_dy + y - input%pointer_y
        end if

        input%pointer_x = x
        input%pointer_y = y
        input%pointer_down = down
        if (present(pressed)) input%pointer_pressed = input%pointer_pressed .or. pressed
        if (.not. was_down .and. down) input%pointer_pressed = .true.
        if (was_down .and. .not. down) input%pointer_released = .true.
        if (down .and. .not. was_down) then
            input%press_x = x
            input%press_y = y
            input%drag_exceeded = .false.
        else if (down) then
            if (abs(x - input%press_x) > DRAG_THRESHOLD .or. &
                abs(y - input%press_y) > DRAG_THRESHOLD) input%drag_exceeded = .true.
        end if
    end subroutine input_update_pointer

    subroutine input_scroll(input, amount, wheel)
        !! Record wheel motion: integer notches and, optionally, precise wheel steps.
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: amount
        real, intent(in), optional :: wheel
        input%scroll_y = input%scroll_y + amount
        if (present(wheel)) then
            input%wheel = input%wheel + wheel
        else
            input%wheel = input%wheel + real(amount)
        end if
    end subroutine input_scroll

    subroutine input_set_key(input, key)
        !! Record a named key (KEY_*); KEY_NONE and unknown values are ignored.
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: key

        call input_key_press(input, key, 0, 0, widgets=.true.)
    end subroutine input_set_key

    subroutine input_key_press(input, key, code, mods, repeat, focus, mac, widgets)
        !! Record a key press for shortcuts: a named key (KEY_*), or KEY_NONE and
        !! the code point of the typed character, with its MOD_* modifiers.
        !! `focus` is what the host knows about the control with the focus,
        !! `mac` that its command modifier is Meta. With `widgets` a named key
        !! also goes to the widgets, as input_set_key delivers it.
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: key, code, mods
        logical, intent(in), optional :: repeat, mac, widgets
        integer, intent(in), optional :: focus
        type(key_press_t) :: p

        if (key < KEY_NONE .or. key > KEY_INSERT) return
        if (key == KEY_NONE .and. code <= 32) return
        if (present(widgets)) then
            if (widgets) call input_widget_key(input, key)
        end if
        p%key = key
        if (key == KEY_NONE) p%code = code
        p%mods = iand(mods, MOD_CTRL + MOD_ALT + MOD_SHIFT + MOD_META)
        call canonical(p%code, p%mods, .false.)
        if (present(repeat)) p%repeat = repeat
        if (present(mac)) p%mac = mac
        if (present(focus)) p%focus = focus
        call add_press(input, p)
    end subroutine input_key_press

    subroutine input_widget_key(input, key)
        !! A named key (KEY_*) for the widgets of this frame only, for a host
        !! whose press is already with the shortcuts (input_claims).
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: key

        if (key <= KEY_NONE .or. key > KEY_INSERT) return
        if (input%key_count >= MAX_FRAME_KEYS) return
        input%key_count = input%key_count + 1
        input%keys(input%key_count) = key
        input%key_text_pos(input%key_count) = input%text_len
    end subroutine input_widget_key

    subroutine add_press(input, p)
        type(input_state_t), intent(inout) :: input
        type(key_press_t), intent(in) :: p
        type(key_press_t), allocatable :: grown(:)
        integer :: i

        if (input%press_count >= MAX_PENDING_PRESSES) return
        if (.not. allocated(input%presses)) allocate (input%presses(32))
        if (input%press_count >= size(input%presses)) then
            allocate (grown(2 * size(input%presses)))
            do i = 1, input%press_count
                grown(i) = input%presses(i)
            end do
            call move_alloc(grown, input%presses)
        end if
        input%press_count = input%press_count + 1
        input%presses(input%press_count) = p
    end subroutine add_press

    pure subroutine canonical(code, mods, chord)
        !! One spelling for a character with modifiers. Alone or with Shift it is
        !! the character typed, so Shift says nothing more ("?", "G"); with
        !! another modifier a letter ignores case and Shift counts.
        integer, intent(inout) :: code, mods
        logical, intent(in) :: chord

        if (code == 0) return
        if (iand(mods, MOD_CTRL + MOD_ALT + MOD_META + MOD_PRIMARY) == 0) then
            if (iand(mods, MOD_SHIFT) == 0) return
            if (.not. chord) then
                mods = 0
            else if (code >= iachar('a') .and. code <= iachar('z')) then
                ! "shift+j" in a chord is the character J.
                code = code - 32
                mods = 0
            end if
        else if (code >= iachar('A') .and. code <= iachar('Z')) then
            code = code + 32
        end if
    end subroutine canonical

    pure function chord_parse(text) result(c)
        !! "j", "?", "Enter", "mod+k", "ctrl+shift+ArrowUp", or two of them
        !! separated by a space ("g o"). Modifiers are mod, ctrl, alt, shift and
        !! meta; keys are one character or Enter, Escape, Tab, Space, Backspace,
        !! Delete, Insert, Home, End, PageUp, PageDown, ArrowLeft, ArrowRight,
        !! ArrowUp, ArrowDown. Anything else gives steps = 0.
        character(*), intent(in) :: text
        type(chord_t) :: c
        integer :: a, b, n
        logical :: ok

        n = len_trim(text)
        a = 1
        do while (a <= n)
            if (text(a:a) == ' ') then
                a = a + 1
                cycle
            end if
            b = index(text(a:n), ' ')
            if (b == 0) then
                b = n
            else
                b = a + b - 2
            end if
            if (c%steps == 2) then
                c%steps = 0
                return
            end if
            c%steps = c%steps + 1
            call parse_step(text(a:b), c%key(c%steps), c%code(c%steps), c%mods(c%steps), ok)
            if (.not. ok) then
                c%steps = 0
                return
            end if
            a = b + 1
        end do
    end function chord_parse

    pure subroutine parse_step(token, key, code, mods, ok)
        character(*), intent(in) :: token
        integer, intent(out) :: key, code, mods
        logical, intent(out) :: ok
        integer :: a, i, m, cp, nbytes

        key = KEY_NONE
        code = 0
        mods = 0
        a = 1
        do
            ! A "+" that begins or ends what is left is the key itself.
            i = index(token(a:), '+')
            if (i <= 1 .or. a + i - 1 >= len(token)) exit
            select case (lower(token(a:a + i - 2)))
            case ('mod'); m = MOD_PRIMARY
            case ('ctrl'); m = MOD_CTRL
            case ('alt'); m = MOD_ALT
            case ('shift'); m = MOD_SHIFT
            case ('meta'); m = MOD_META
            case default; m = 0
            end select
            if (m == 0) exit
            mods = ior(mods, m)
            a = a + i
        end do
        call utf8_decode(token, a, cp, nbytes)
        if (a + nbytes - 1 == len(token)) then
            code = cp
            ok = cp > 32 .and. cp /= 127
            call canonical(code, mods, .true.)
            return
        end if
        select case (lower(token(a:)))
        case ('enter'); key = KEY_ENTER
        case ('escape'); key = KEY_ESCAPE
        case ('tab'); key = KEY_TAB
        case ('space'); key = KEY_SPACE
        case ('backspace'); key = KEY_BACKSPACE
        case ('delete'); key = KEY_DELETE
        case ('insert'); key = KEY_INSERT
        case ('home'); key = KEY_HOME
        case ('end'); key = KEY_END
        case ('pageup'); key = KEY_PAGE_UP
        case ('pagedown'); key = KEY_PAGE_DOWN
        case ('arrowleft'); key = KEY_ARROW_LEFT
        case ('arrowright'); key = KEY_ARROW_RIGHT
        case ('arrowup'); key = KEY_ARROW_UP
        case ('arrowdown'); key = KEY_ARROW_DOWN
        end select
        ok = key /= KEY_NONE
    end subroutine parse_step

    pure function lower(s) result(r)
        character(*), intent(in) :: s
        character(len=len(s)) :: r
        integer :: i

        r = s
        do i = 1, len(s)
            if (s(i:i) >= 'A' .and. s(i:i) <= 'Z') r(i:i) = achar(iachar(s(i:i)) + 32)
        end do
    end function lower

    pure logical function step_is(c, step, key, code, mods, mac) result(same)
        !! Whether step `step` of chord `c` is the key with these modifiers.
        type(chord_t), intent(in) :: c
        integer, intent(in) :: step, key, code, mods
        logical, intent(in) :: mac
        integer :: want

        want = c%mods(step)
        if (iand(want, MOD_PRIMARY) /= 0) then
            want = want - MOD_PRIMARY
            if (mac) then
                want = ior(want, MOD_META)
            else
                want = ior(want, MOD_CTRL)
            end if
        end if
        same = c%key(step) == key .and. c%code(step) == code .and. want == mods
    end function step_is

    pure logical function focus_uses(focus, key, mods) result(uses)
        !! Whether the control with the focus acts on the press itself. A press
        !! with Ctrl or Meta is never its own.
        integer, intent(in) :: focus, key, mods

        uses = .false.
        if (iand(mods, MOD_CTRL + MOD_META) /= 0) return
        select case (focus)
        case (FOCUS_CONTROL)
            uses = key == KEY_ENTER .or. key == KEY_SPACE
        case (FOCUS_RANGE)
            uses = key == KEY_ENTER .or. key == KEY_SPACE .or. &
                (key >= KEY_HOME .and. key <= KEY_PAGE_DOWN)
        case (FOCUS_FIELD)
            uses = key /= KEY_ARROW_UP .and. key /= KEY_ARROW_DOWN .and. &
                key /= KEY_ENTER .and. key /= KEY_ESCAPE
        case (FOCUS_EDITOR)
            uses = key /= KEY_ESCAPE
        end select
    end function focus_uses

    pure subroutine sort_press(chords, n, track, focus, p, claimed, repeats)
        !! Decides what press `p` is among the `n` chords: left to the control
        !! with the focus, the second key of a chord, or a key on its own.
        !! `claimed`: a chord has it as one of its keys; `repeats`: one that
        !! also wants its repeats.
        type(chord_t), intent(in) :: chords(:)
        integer, intent(in) :: n, focus
        type(key_track_t), intent(inout) :: track
        type(key_press_t), intent(inout) :: p
        logical, intent(out) :: claimed, repeats
        integer :: i, at

        claimed = .false.
        repeats = .false.
        p%final = .false.
        p%wanted = .false.
        p%sorted = .true.
        at = p%focus
        if (at == FOCUS_UNKNOWN) at = focus
        p%consumed = focus_uses(at, p%key, p%mods)
        if (p%consumed) then
            track%armed = .false.
            return
        end if
        if (track%armed .and. .not. p%repeat) then
            if (p%time - track%prev%time <= CHORD_SECONDS) then
                do i = 1, n
                    if (chords(i)%steps /= 2) cycle
                    if (step_is(chords(i), 1, track%prev%key, track%prev%code, &
                        track%prev%mods, track%prev%mac) .and. &
                        step_is(chords(i), 2, p%key, p%code, p%mods, p%mac)) p%final = .true.
                end do
            end if
        end if
        if (p%final) then
            p%first_key = track%prev%key
            p%first_code = track%prev%code
            p%first_mods = track%prev%mods
            track%armed = .false.
            claimed = .true.
            p%wanted = .true.
            return
        end if
        do i = 1, n
            if (.not. step_is(chords(i), 1, p%key, p%code, p%mods, p%mac)) cycle
            claimed = .true.
            if (chords(i)%steps == 1 .and. chords(i)%repeat) repeats = .true.
        end do
        p%wanted = claimed .and. (.not. p%repeat .or. repeats)
        if (.not. p%repeat) then
            track%prev = p
            track%armed = .true.
        end if
    end subroutine sort_press

    subroutine input_sort_presses(input, focus, time)
        !! Sorts the presses a host did not sort at the key (input_claims)
        !! against the chords of the last presented frame, and decides which
        !! presses this frame sees: all up to the first that would press a
        !! chord a second time, which waits for the next frame with those after
        !! it. `focus` (FOCUS_*) is the runtime's own focus.
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: focus
        double precision, intent(in) :: time
        logical :: claimed, repeats
        integer :: i, k

        input%press_shown = 0
        if (input%press_count == 0) return
        if (.not. allocated(input%claimed)) allocate (input%claimed(16))
        do i = 1, input%press_count
            if (input%presses(i)%sorted) cycle
            input%presses(i)%time = time
            call sort_press(input%claimed, input%claimed_count, input%track, focus, &
                input%presses(i), claimed, repeats)
        end do
        shown: do i = 1, input%press_count
            if (input%presses(i)%wanted) then
                do k = 1, i - 1
                    if (same_press(input%presses(k), input%presses(i))) exit shown
                end do
            end if
            input%press_shown = i
        end do shown
    end subroutine input_sort_presses

    pure logical function same_press(a, b) result(same)
        !! Whether two sorted presses press the same chords.
        type(key_press_t), intent(in) :: a, b

        same = a%wanted .and. b%wanted .and. a%key == b%key .and. a%code == b%code .and. &
            a%mods == b%mods .and. (a%mac .eqv. b%mac) .and. (a%final .eqv. b%final)
        if (same .and. a%final) same = a%first_key == b%first_key .and. &
            a%first_code == b%first_code .and. a%first_mods == b%first_mods
    end function same_press

    logical function input_shortcut(input, chord, repeat) result(pressed)
        !! Asks for `chord` in the frame being composed; true when it was pressed.
        type(input_state_t), intent(inout) :: input
        character(*), intent(in) :: chord
        logical, intent(in), optional :: repeat
        type(chord_t) :: c
        type(chord_t), allocatable :: grown(:)
        integer :: i, at

        pressed = .false.
        c = chord_parse(chord)
        if (c%steps == 0) return
        if (present(repeat)) c%repeat = repeat .and. c%steps == 1
        if (.not. allocated(input%chords)) allocate (input%chords(16))
        at = 0
        do i = 1, input%chord_count
            if (input%chords(i)%steps == c%steps .and. all(input%chords(i)%key == c%key) &
                .and. all(input%chords(i)%code == c%code) .and. &
                all(input%chords(i)%mods == c%mods)) at = i
        end do
        if (at > 0) then
            if (c%repeat) input%chords(at)%repeat = .true.
        else
            if (input%chord_count >= size(input%chords)) then
                allocate (grown(2 * size(input%chords)))
                grown(1:input%chord_count) = input%chords(1:input%chord_count)
                call move_alloc(grown, input%chords)
            end if
            input%chord_count = input%chord_count + 1
            input%chords(input%chord_count) = c
        end if
        do i = 1, input%press_shown
            associate (p => input%presses(i))
                if (p%consumed) cycle
                if (p%repeat .and. .not. c%repeat) cycle
                if (c%steps == 1) then
                    if (.not. p%final .and. step_is(c, 1, p%key, p%code, p%mods, p%mac)) &
                        pressed = .true.
                else if (p%final) then
                    if (step_is(c, 1, p%first_key, p%first_code, p%first_mods, p%mac) .and. &
                        step_is(c, 2, p%key, p%code, p%mods, p%mac)) pressed = .true.
                end if
            end associate
        end do
    end function input_shortcut

    subroutine input_commit_chords(input)
        !! The chords of the composed frame are the ones in force until the next.
        type(input_state_t), intent(inout) :: input
        integer :: n

        n = input%chord_count
        if (n == 0 .and. input%claimed_count == 0) return
        if (allocated(input%claimed)) then
            if (size(input%claimed) < n) deallocate (input%claimed)
        end if
        if (.not. allocated(input%claimed)) allocate (input%claimed(max(16, n)))
        if (n > 0) input%claimed(1:n) = input%chords(1:n)
        input%claimed_count = n
        input%chord_count = 0
    end subroutine input_commit_chords

    function input_host_key(key, flags, code) result(p)
        !! A key press as a host packs it into one event: the named key, the
        !! code point, and flags: MOD_* (1..8), 16 the command modifier is Meta,
        !! 32 a repeat, and FOCUS_* times 256.
        integer, intent(in) :: key, flags, code
        type(key_press_t) :: p

        p%key = key
        if (key == KEY_NONE) p%code = code
        p%mods = iand(flags, MOD_CTRL + MOD_ALT + MOD_SHIFT + MOD_META)
        call canonical(p%code, p%mods, .false.)
        p%mac = iand(flags, 16) /= 0
        p%repeat = iand(flags, 32) /= 0
        p%focus = min(iand(flags, 65280) / 256, FOCUS_EDITOR)
    end function input_host_key

    integer function input_claims(input, press, time) result(claim)
        !! For a host at the moment of a key, before its own default action:
        !! CLAIM_DELIVER when the application wants the press (it is a key of a
        !! chord of the last frame, or Escape, which is always the
        !! application's), plus CLAIM_PREVENT when the host's default action
        !! must not happen. Keys the focused control uses itself are neither,
        !! and Escape in a text field keeps its default. The host tells every
        !! key, so that chords of two keys follow the keys as they were pressed;
        !! a press the application wants is kept for the next frame as sorted
        !! here, and the host does not record it again.
        type(input_state_t), intent(inout) :: input
        type(key_press_t), intent(in) :: press
        double precision, intent(in) :: time
        type(key_press_t) :: p
        logical :: claimed, repeats

        claim = 0
        if (press%key < KEY_NONE .or. press%key > KEY_INSERT) return
        if (press%key == KEY_NONE .and. press%code <= 32) return
        if (.not. allocated(input%claimed)) allocate (input%claimed(16))
        p = press
        p%time = time
        call sort_press(input%claimed, input%claimed_count, input%track, FOCUS_PLAIN, &
            p, claimed, repeats)
        if (claimed) then
            if (.not. p%repeat .or. repeats) claim = CLAIM_DELIVER
            if (p%key /= KEY_ESCAPE .or. p%focus < FOCUS_FIELD) claim = claim + CLAIM_PREVENT
        end if
        if (p%key == KEY_ESCAPE) claim = ior(claim, CLAIM_DELIVER)
        if (iand(claim, CLAIM_DELIVER) /= 0) call add_press(input, p)
    end function input_claims

    subroutine input_route(input, previous)
        type(input_state_t), intent(inout) :: input
        type(ui_frame_t), intent(in) :: previous

        integer :: hit, i, focused_index, first_focus, next_focus

        ! Pointer capture ends when its node disappears or the button is up.
        if (len_trim(input%active_id) > 0) then
            if (previous%find(trim(input%active_id)) == 0) input%active_id = ""
        end if
        if (.not. input%pointer_down .and. &
            .not. input%pointer_released) input%active_id = ""

        if (input_key_arrived(input, KEY_TAB)) then
            first_focus = 0
            focused_index = 0
            do i = 1, previous%count
                if (.not. previous%nodes(i)%focusable .or. previous%nodes(i)%disabled) cycle
                if (first_focus == 0) first_focus = i
                if (trim(previous%nodes(i)%id) == trim(input%focus_id)) focused_index = i
            end do

            next_focus = 0
            if (focused_index > 0) then
                do i = focused_index + 1, previous%count
                    if (previous%nodes(i)%focusable .and. &
                        .not. previous%nodes(i)%disabled) then
                        next_focus = i
                        exit
                    end if
                end do
            end if
            if (next_focus == 0) next_focus = first_focus
            if (next_focus > 0) input%focus_id = previous%nodes(next_focus)%id
        end if

        if (input%pointer_pressed) then
            hit = hit_test(previous, input%pointer_x, input%pointer_y, .true.)
            if (hit > 0) then
                input%active_id = previous%nodes(hit)%id
                if (previous%nodes(hit)%focusable) input%focus_id = previous%nodes(hit)%id
            else
                input%active_id = ""
            end if
        end if

        if (input%pointer_released) then
            hit = hit_test(previous, input%pointer_x, input%pointer_y, .true.)
            if (hit > 0) then
                if (trim(previous%nodes(hit)%id) == trim(input%active_id)) then
                    input%activated_id = previous%nodes(hit)%id
                    if (.not. input%drag_exceeded) call register_click(input)
                end if
            end if
            input%active_id = ""
        end if

        if ((input_key_arrived(input, KEY_ENTER) .or. input_key_arrived(input, KEY_SPACE)) &
            .and. len_trim(input%focus_id) > 0) then
            input%activated_id = input%focus_id
        end if

        if (input%scroll_y /= 0) then
            hit = hit_test(previous, input%pointer_x, input%pointer_y, .false.)
            if (hit > 0) input%scroll_id = previous%nodes(hit)%id
        end if
    end subroutine input_route

    subroutine register_click(input)
        !! A click is press+release on one node without exceeding the drag threshold.
        type(input_state_t), intent(inout) :: input

        input%click_id = input%activated_id
        if (trim(input%last_click_id) == trim(input%click_id) .and. &
            input%time - input%last_click_time <= DOUBLE_CLICK_SECONDS .and. &
            abs(input%press_x - input%last_click_x) <= DOUBLE_CLICK_DISTANCE .and. &
            abs(input%press_y - input%last_click_y) <= DOUBLE_CLICK_DISTANCE) then
            input%double_click_id = input%click_id
            input%last_click_id = ""
            input%last_click_time = -1.0d9
        else
            input%last_click_id = input%click_id
            input%last_click_time = input%time
            input%last_click_x = input%press_x
            input%last_click_y = input%press_y
        end if
    end subroutine register_click

    integer function hit_test(frame, x, y, interactive_only) result(index)
        type(ui_frame_t), intent(in) :: frame
        real, intent(in) :: x, y
        logical, intent(in) :: interactive_only
        integer :: i

        index = 0
        do i = frame%count, 1, -1
            if (interactive_only .and. .not. frame%nodes(i)%focusable) cycle
            if (len_trim(frame%nodes(i)%id) == 0) cycle
            if (frame%nodes(i)%disabled) cycle
            if (x >= frame%nodes(i)%x .and. &
                x < frame%nodes(i)%x + frame%nodes(i)%width .and. &
                y >= frame%nodes(i)%y .and. &
                y < frame%nodes(i)%y + frame%nodes(i)%height) then
                index = i
                return
            end if
        end do
    end function hit_test

    logical function input_activated(input, id)
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id
        input_activated = len_trim(input%activated_id) > 0 .and. &
            trim(input%activated_id) == trim(id)
    end function input_activated

    logical function input_focused(input, id)
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id
        input_focused = len_trim(input%focus_id) > 0 .and. trim(input%focus_id) == trim(id)
    end function input_focused

    logical function input_active(input, id)
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id
        input_active = len_trim(input%active_id) > 0 .and. trim(input%active_id) == trim(id)
    end function input_active

    logical function input_hovered(input, x, y, width, height)
        type(input_state_t), intent(in) :: input
        real, intent(in) :: x, y, width, height
        input_hovered = input%pointer_x >= x .and. input%pointer_x < x + width .and. &
            input%pointer_y >= y .and. input%pointer_y < y + height
    end function input_hovered

    logical function input_key_arrived(input, key)
        !! Whether `key` is among the keys of this frame.
        type(input_state_t), intent(in) :: input
        integer, intent(in) :: key
        input_key_arrived = any(input%keys(1:input%key_count) == key)
    end function input_key_arrived


    subroutine input_host_event(input, kind, id, value)
        !! Record a semantic host event (HOST_*); extra events in one frame are dropped.
        type(input_state_t), intent(inout) :: input
        integer, intent(in) :: kind
        character(*), intent(in) :: id
        character(*), intent(in), optional :: value

        if (input%host_count >= MAX_HOST_EVENTS) return
        input%host_count = input%host_count + 1
        input%host(input%host_count)%kind = kind
        input%host(input%host_count)%id = id
        input%host(input%host_count)%value = ""
        if (present(value)) input%host(input%host_count)%value = value
    end subroutine input_host_event

    subroutine input_apply_host(input)
        !! Activation and focus from host events; values stay for their widgets.
        type(input_state_t), intent(inout) :: input
        integer :: i

        do i = 1, input%host_count
            associate(e => input%host(i))
                select case (e%kind)
                case (HOST_ACTIVATE)
                    input%activated_id = e%id
                    input%focus_id = e%id
                case (HOST_FOCUS)
                    input%focus_id = e%id
                case (HOST_BLUR)
                    if (trim(input%focus_id) == trim(e%id)) input%focus_id = ""
                end select
            end associate
        end do
    end subroutine input_apply_host

    logical function input_host_value(input, id, value) result(found)
        !! The last value the host reported for `id` in this frame.
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id
        character(len=:), allocatable, intent(inout) :: value
        integer :: i

        found = .false.
        do i = input%host_count, 1, -1
            if (input%host(i)%kind == HOST_VALUE .and. trim(input%host(i)%id) == trim(id)) then
                value = input%host(i)%value
                found = .true.
                return
            end if
        end do
    end function input_host_value

    logical function input_host_submitted(input, id) result(found)
        type(input_state_t), intent(in) :: input
        character(*), intent(in) :: id
        integer :: i

        found = .false.
        do i = 1, input%host_count
            if (input%host(i)%kind == HOST_SUBMIT .and. trim(input%host(i)%id) == trim(id)) &
                found = .true.
        end do
    end function input_host_submitted

end module fortui_input
