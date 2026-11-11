module web_demo_app
    !! The demo's state and its frame. State lives in a module: the browser calls
    !! the frame after the main program has returned.
    use fortui
    implicit none
    private

    public :: compose

    logical :: checked = .false., submitted = .false., to_name = .false., to_end = .false.
    integer :: value = 25, tab = 1, clicks = 0, ticks = 0, presses = 0
    double precision :: next_tick = 0d0
    character(len=:), allocatable :: name, notes, last_key
    character(len=16), parameter :: tab_labels(3) = [character(len=16) :: "Controls", &
        "Text", "About"]

contains

    subroutine compose()
        integer :: k

        if (.not. allocated(name)) name = ""
        if (.not. allocated(notes)) notes = ""
        if (.not. allocated(last_key)) last_key = ""
        call text("FortUI in the browser", style=UI_TITLE)
        ! A clock driven only by timers: three ticks, 0.2 s apart, no input.
        if (ticks < 3) then
            if (next_tick <= 0d0) next_tick = ui_time() + 0.2d0
            if (ui_time() >= next_tick) then
                ticks = ticks + 1
                next_tick = ui_time() + 0.2d0
            end if
            if (ticks < 3) call ui_wake_after(real(next_tick - ui_time()))
        end if
        call text("Ticks " // ui_str(ticks), id="ticks")
        ! Shortcuts: "g o" shows the end of the listing, mod+k goes to the name.
        if (ui_shortcut("j")) call pressed("j")
        if (ui_shortcut("Escape")) call pressed("Escape")
        if (ui_shortcut("o")) call pressed("o")
        if (ui_shortcut("g o")) then
            call pressed("g o")
            tab = 3
            to_end = .true.
        end if
        if (ui_shortcut("mod+k")) then
            call pressed("mod+k")
            tab = 2
            to_name = .true.
        end if
        if (tab == 2) then
            ! As a command palette has them: pressed while the name is typed.
            if (ui_shortcut("ArrowDown")) call pressed("ArrowDown")
            if (ui_shortcut("Enter")) call pressed("Enter")
        end if
        call text("Keys " // ui_str(presses) // " " // last_key, id="keys")
        if (tabs("tabs", tab_labels, tab)) continue
        select case (tab)
        case (1)
            call row_begin(8.0, look="toolbar", anchor="controls")
            if (button("one", "One", look="primary")) value = 10
            if (button("two", "Two")) value = 90
            if (button("count", "Clicked " // ui_str(clicks))) clicks = clicks + 1
            call row_end()
            if (link("more", "Read more", "#more")) clicks = clicks + 100
            ! A low value asks for attention; the address #value stays either way.
            if (value < 50) then
                call text("Value " // ui_str(value), tone=UI_TONE_ATTENTION, &
                    look="low", anchor="value")
            else
                call text("Value " // ui_str(value), anchor="value")
            end if
            if (slider("value", 0, 100, value, step=5, width=240.0)) continue
            if (checkbox("check", checked, "Enabled")) continue
        case (2)
            if (text_input("name", name, placeholder="Your name", submitted=submitted, &
                width=320.0)) continue
            call text("Hello, " // name // "!")
            if (to_name) call ui_focus("name")
            to_name = .false.
            if (text_input("notes", notes, placeholder="Notes", width=320.0, lines=3)) continue
        case default
            call scroll_text("about", "Fortran compiled to WebAssembly with LFortran. " // &
                "Ordinary controls are DOM elements; the frame loop yields to the " // &
                "browser between frames.", height=120.0)
            call text("long line: "//repeat("abcdefghij ", 30), style=UI_CODE, id="longcode")
            call text("call solve(n, 3.5) ! done", style=UI_CODE, id="rich", &
                ends=[4, 11, 14, 17, 19, 26], tones=[UI_TONE_KEYWORD, 0, 0, UI_TONE_NUMBER, 0, &
                UI_TONE_COMMENT])
            ! A listing longer than the window: the browser scrolls the page.
            do k = 1, 60
                select case (mod(k, 3))
                case (1)
                    call text("+ added line " // ui_str(k), style=UI_CODE, tone=UI_TONE_POSITIVE)
                case (2)
                    call text("- removed line " // ui_str(k), style=UI_CODE, tone=UI_TONE_NEGATIVE)
                case default
                    call text("  context    " // ui_str(k), style=UI_CODE)
                end select
            end do
            call text("end of the listing", id="last")
            if (to_end) call ui_reveal("last")
            to_end = .false.
        end select
    end subroutine compose

    subroutine pressed(chord)
        character(*), intent(in) :: chord
        presses = presses + 1
        last_key = chord
    end subroutine pressed

end module web_demo_app

