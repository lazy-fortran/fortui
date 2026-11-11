module web_demo_app
    !! The demo's state and its frame. State lives in a module: the browser calls
    !! the frame after the main program has returned.
    use fortui
    implicit none
    private

    public :: compose

    logical :: checked = .false., submitted = .false.
    integer :: value = 25, tab = 1, clicks = 0, ticks = 0
    double precision :: next_tick = 0d0
    character(len=:), allocatable :: name
    character(len=16), parameter :: tab_labels(3) = [character(len=16) :: "Controls", &
        "Text", "About"]

contains

    subroutine compose()
        integer :: k

        if (.not. allocated(name)) name = ""
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
        end select
    end subroutine compose

end module web_demo_app

