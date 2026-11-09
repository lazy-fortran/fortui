module web_demo_app
    !! The demo's state and its frame. State lives in a module: the browser calls
    !! the frame after the main program has returned.
    use fortui
    implicit none
    private

    public :: compose

    logical :: checked = .false., submitted = .false.
    integer :: value = 25, tab = 1, clicks = 0
    character(len=:), allocatable :: name
    character(len=16), parameter :: tab_labels(3) = [character(len=16) :: "Controls", &
        "Text", "About"]

contains

    subroutine compose()
        integer :: k

        if (.not. allocated(name)) name = ""
        call text("FortUI in the browser", style=UI_TITLE)
        if (tabs("tabs", tab_labels, tab)) continue
        select case (tab)
        case (1)
            call row_begin(8.0)
            if (button("one", "One")) value = 10
            if (button("two", "Two")) value = 90
            if (button("count", "Clicked " // ui_str(clicks))) clicks = clicks + 1
            call row_end()
            call text("Value " // ui_str(value))
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

program web_demo
    !! The same semantic controls as the terminal and GUI demos, realized as DOM
    !! elements in a browser.
    use fortui, only: ui_init, ui_run
    use fortui_web, only: web_backend_t
    use web_demo_app, only: compose
    implicit none
    integer :: stat

    call ui_init(web_backend_t(root_id="app"), 900, 640, "FortUI web demo", stat=stat)
    if (stat /= 0) error stop "No browser document available"
    call ui_run(compose)
end program web_demo
