module web_demo_app
    !! The demo's state and its frame. State lives in a module: the browser calls
    !! the frame after the main program has returned.
    use fortui
    use iso_fortran_env, only: int32
    implicit none
    private

    public :: compose

    logical :: checked = .false., submitted = .false., to_name = .false., to_end = .false.
    type(file_dialog_t) :: picker
    integer :: value = 25, tab = 1, clicks = 0, ticks = 0, presses = 0
    double precision :: next_tick = 0d0
    character(len=:), allocatable :: name, notes, last_key
    type(canvas_view_t) :: view
    ! Network service: an event stream followed from the first frame and a
    ! request started by a button.
    type(net_stream_t) :: events
    type(net_request_t) :: fetch
    integer :: received = 0
    character(len=:), allocatable :: fetched
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
        call swatch()
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
        call network()
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
            call file_open_button("open-file", "Open file...", picker, &
                extensions=".png,.jpg,.jpeg")
            if (picker%status == FILE_ACCEPTED) call text(picker%name // ": " // &
                ui_str(size(picker%bytes)) // " bytes", id="file-result")
            if (button("appearance", "Follow desktop theme")) call ui_set_theme("fluent")
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

    subroutine network()
        !! Messages of /api/events, the answer of POST /api/echo, the user's
        !! language and the page's "site" parameter, all present in every frame.
        character(len=:), allocatable :: data
        if (.not. allocated(fetched)) fetched = "-"
        if (events%status == NET_IDLE) call net_stream_open(events, "/api/events")
        do while (net_stream_next(events, data))
            received = received + 1
        end do
        if (net_poll(fetch)) then
            if (fetch%status == NET_DONE) then
                fetched = ui_str(fetch%code) // " " // fetch%body
            else
                fetched = "failed"
            end if
        end if
        call row_begin(8.0, anchor="network")
        if (button("fetch", "Fetch")) call net_fetch(fetch, "/api/echo", body="ping")
        call text("Fetched " // fetched, id="fetched")
        call text("Events " // ui_str(received), id="events")
        call text("Locale " // ui_locale(), id="locale")
        call text("Site " // ui_url_param("site"), id="site")
        call row_end()
    end subroutine network

    subroutine swatch()
        !! A canvas with a fill, a two-pixel image stretched over a rectangle and
        !! a line, in world units twice the logical size.
        integer(int32) :: pixels(2, 1)
        real :: xy(2, 2)
        pixels(1, 1) = ui_rgba(255, 0, 0)
        pixels(2, 1) = ui_rgba(0, 0, 255)
        xy = reshape([20.0, 90.0, 220.0, 90.0], [2, 2])
        view%zoom = 0.5
        call canvas_begin("swatch", view, width=120.0, height=60.0, fill=ui_rgba(30, 30, 30))
        call canvas_image("pixels", 1, pixels, 20.0, 20.0, 80.0, 40.0)
        call canvas_lines("line", 1, xy, [ui_rgba(0, 255, 0)], reshape([1, 2], [2, 1]), width=4.0)
        call canvas_end(view)
    end subroutine swatch

    subroutine pressed(chord)
        character(*), intent(in) :: chord
        presses = presses + 1
        last_key = chord
    end subroutine pressed

end module web_demo_app

