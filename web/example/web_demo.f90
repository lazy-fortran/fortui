program web_demo
    !! The same semantic controls as the terminal and GUI demos, realized as DOM
    !! elements in a browser.
    use fortui
    use fortui_web, only: web_backend_t
    implicit none

    logical :: checked, submitted
    integer :: value, tab, stat, clicks
    character(len=:), allocatable :: name
    character(len=16), parameter :: tab_labels(3) = [character(len=16) :: "Controls", &
        "Text", "About"]

    checked = .false.
    value = 25
    tab = 1
    clicks = 0
    name = ""

    call ui_init(web_backend_t(root_id="app"), 900, 640, "FortUI web demo", stat=stat)
    if (stat /= 0) error stop "No browser document available"

    do while (.not. ui_should_close())
        call ui_frame_begin()
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
        end select
        call ui_present()
    end do

    call ui_shutdown()
end program web_demo
