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
    ! What the swatch canvas last felt: pointer kind, pressure in percent,
    ! samples of the last frame, and the product of all pinches in percent.
    integer :: felt_kind = -1, felt_pressure = 0, felt_samples = 0
    real :: zoom_total = 1.0
    character(len=:), allocatable :: fetched
    character(len=16), parameter :: tab_labels(4) = [character(len=16) :: "Controls", &
        "Text", "About", "Widgets"]
    ! Widgets: a view, a filter chip, a choice, the last command, a chat that
    ! grows, a long list and a table.
    integer :: view_mode = 1, colour = 2, command = 0, chat_lines = 3, turn = 40
    logical :: colour_loaded = .false.
    type(command_history_t) :: history
    logical :: only_open = .false., asking = .false.
    type(grid_state_t) :: grid

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
        case (4)
            call widgets()
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

    subroutine widgets()
        !! Symbols, chips, badges, segmented choices, a drop-down, a menu,
        !! notifications, a modal dialog, a chat that keeps its end in view, a
        !! virtual list of ten thousand rows and a data grid.
        character(len=12), parameter :: views(3) = [character(len=12) :: "List", "Board", "Graph"]
        character(len=12), parameter :: colours(3) = [character(len=12) :: "Red", "Green", "Blue"]
        character(len=12), parameter :: commands(4) = [character(len=12) :: "Rename", "Duplicate", &
            "-", "Delete"]
        character(len=12), parameter :: heads(3) = [character(len=12) :: "Coil", "Current", "Gap"]
        character(len=12) :: cells(3, 40)
        integer :: k, first, last, c, old_view, old_colour
        character(len=:), allocatable :: step
        ! The view follows the address (shareable, Back and Forward); the colour
        ! is kept between visits; changes of both can be undone.
        old_view = view_mode
        do k = 1, 3
            if (ui_url_param("view") == lower_name(views(k))) view_mode = k
        end do
        if (.not. colour_loaded) then
            colour_loaded = .true.
            step = ui_store_get("colour")
            if (len(step) == 1) then
                k = index("123", step)
                if (k > 0) colour = k
            end if
        end if
        old_colour = colour
        call row_begin(8.0, wrap=.true.)
        call icon("cube", tooltip="Model")
        if (segmented("view", views, view_mode, icons=[character(len=12) :: "menu", "cube", "branch"])) then
            call command_record(history, "View " // trim(views(view_mode)), "view " // ui_str(view_mode), &
                "view " // ui_str(old_view))
            call ui_set_url_param("view", lower_name(views(view_mode)), push=.true.)
        end if
        if (dropdown("colour", colours, colour)) then
            call command_record(history, "Colour", "colour " // ui_str(colour), "colour " // ui_str(old_colour))
            call ui_store_set("colour", ui_str(colour))
        end if
        c = menu("more", "More", commands)
        if (c > 0) command = c
        if (button("undo", "", icon="undo", tooltip="Undo " // command_undo_label(history), &
            enabled=len(command_undo_label(history)) > 0)) then
            if (command_undo(history, step)) call apply_step(step)
        end if
        if (button("redo", "", icon="redo", tooltip="Redo " // command_redo_label(history), &
            enabled=len(command_redo_label(history)) > 0)) then
            if (command_redo(history, step)) call apply_step(step)
        end if
        if (command_shortcuts(history, step)) call apply_step(step)
        call avatar("Chris Albert")
        call avatar("王小明", tooltip="王小明 @ China, on cand-a")
        call row_end()
        call row_begin(8.0, wrap=.true.)
        if (chip("open", "Open only", selected=only_open, icon="filter")) only_open = .not. only_open
        call badge("3 open", UI_TONE_ATTENTION)
        call badge("G4 passed", UI_TONE_POSITIVE)
        call text("View " // trim(views(view_mode)) // ", " // trim(colours(max(1, colour))) // &
            ", command " // ui_str(command), id="widget-state")
        if (button("save", "Save", icon="check", emphasis=UI_EMPHASIS_PRIMARY)) &
            call toast("Saved", UI_TONE_POSITIVE)
        if (button("ask", "Discard...")) asking = .true.
        call row_end()
        if (asking) then
            call modal_begin("confirm", "Discard the branch?", 360.0, 180.0)
            call text("Its changes are lost.")
            call row_begin(8.0)
            if (button("discard", "Discard", emphasis=UI_EMPHASIS_PRIMARY)) asking = .false.
            if (button("keep", "Keep")) asking = .false.
            call row_end()
            call modal_end()
            if (ui_key_pressed(KEY_ESCAPE)) asking = .false.
        end if
        call text("Chat", style=UI_HEADING)
        call scroll_begin("chat", 120.0, stick=.true.)
        do k = 1, chat_lines
            call text("Message " // ui_str(k), id="msg" // ui_str(k))
        end do
        call scroll_end()
        if (button("post", "Post")) chat_lines = chat_lines + 1
        call text("Ten thousand rows", style=UI_HEADING)
        call virtual_list_begin("many", 10000, 28.0, 140.0, first, last)
        do k = first, last
            call row_begin(8.0, height=28.0)
            call text("Row " // ui_str(k), id="row" // ui_str(k))
            call row_end()
        end do
        call virtual_list_end()
        do k = 1, 40
            cells(1, k) = "coil" // ui_str(k)
            cells(2, k) = ui_str(mod(k * 37, 101)) // ".5"
            cells(3, k) = ui_str(mod(k * 13, 17))
        end do
        if (data_grid("coils", heads, cells, grid, 200.0)) continue
        call surfaces()
    end subroutine widgets

    subroutine apply_step(step)
        !! "view N" or "colour N" from the undo history.
        character(*), intent(in) :: step
        character(len=5), parameter :: names(3) = ["List ", "Board", "Graph"]
        integer :: k
        k = index("123", step(len(step):len(step)))
        if (k == 0) return
        if (step(1:4) == "view") then
            view_mode = k
            call ui_set_url_param("view", lower_name(names(k)))
        else
            colour = k
            call ui_store_set("colour", ui_str(k))
        end if
    end subroutine apply_step

    function lower_name(s) result(t)
        character(*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k
        t = trim(s)
        do k = 1, len(t)
            if (t(k:k) >= "A" .and. t(k:k) <= "Z") t(k:k) = achar(iachar(t(k:k)) + 32)
        end do
    end function lower_name

    subroutine surfaces()
        !! Filled surfaces with depth: a red square in front of a blue one
        !! (composed after it), and a shaded torus that the slider turns.
        real :: xyz(3, 8), t, p
        integer(int32) :: colours(8), tris(3, 4)
        real, allocatable :: torus(:, :)
        integer(int32), allocatable :: tcol(:), ttri(:, :)
        type(canvas_view_t) :: v
        type(canvas_events_t) :: ev
        integer :: i, j, nu, nv
        call text("Surfaces", style=UI_HEADING)
        call row_begin(12.0)
        xyz = reshape([1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0, 1.0, -1.0, 1.0, &
            -1.0, -2.0, -2.0, -1.0, 2.0, -2.0, -1.0, 2.0, 2.0, -1.0, -2.0, 2.0], [3, 8])
        colours(1:4) = ui_rgba(255, 0, 0)
        colours(5:8) = ui_rgba(0, 0, 255)
        tris = reshape([4, 5, 6, 4, 6, 7, 0, 1, 2, 0, 2, 3], [3, 4])
        call canvas_begin("depth", v, ev, width=80.0, height=80.0, fill=ui_rgba(0, 255, 0))
        call canvas_mesh("squares", 1, xyz, colours, tris, camera_orbit(0.0, 0.0, 9.0, 1.0))
        call canvas_end()
        nu = 48
        nv = 24
        allocate (torus(3, nu * nv), tcol(nu * nv))
        do j = 1, nv
            do i = 1, nu
                t = 6.2831853 * real(i - 1) / real(nu)
                p = 6.2831853 * real(j - 1) / real(nv)
                torus(:, (j - 1) * nu + i) = [(1.0 + 0.4 * cos(p)) * cos(t), (1.0 + 0.4 * cos(p)) * sin(t), &
                    0.4 * sin(p)]
                tcol((j - 1) * nu + i) = ui_rgba(230, 140 + nint(60 * cos(p)), 60)
            end do
        end do
        ttri = mesh_grid(nu, nv, .true., .true.)
        call canvas_begin("torus", v, ev, width=240.0, height=160.0, fill=ui_rgba(20, 24, 32))
        call canvas_mesh("torus", 1, torus, tcol, ttri, camera_orbit(0.02 * turn, 0.6, 4.0, 1.5))
        call canvas_end()
        call row_end()
        if (slider("turn", 0, 314, turn, width=240.0)) continue
    end subroutine surfaces

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
        type(canvas_events_t) :: ev
        pixels(1, 1) = ui_rgba(255, 0, 0)
        pixels(2, 1) = ui_rgba(0, 0, 255)
        xy = reshape([20.0, 90.0, 220.0, 90.0], [2, 2])
        view%zoom = 0.5
        call canvas_begin("swatch", view, ev, width=120.0, height=60.0, fill=ui_rgba(30, 30, 30))
        if (ev%captured .or. ev%pressed) then
            felt_kind = ev%kind
            felt_pressure = nint(100 * ev%pressure)
            felt_samples = size(ev%samples, 2)
        end if
        zoom_total = zoom_total * ev%pinch
        call canvas_image("pixels", 1, pixels, 20.0, 20.0, 80.0, 40.0)
        call canvas_lines("line", 1, xy, [ui_rgba(0, 255, 0)], reshape([1, 2], [2, 1]), width=4.0)
        call canvas_end(view)
        call text("Pointer " // ui_str(felt_kind) // " " // ui_str(felt_pressure) // " " // &
            ui_str(felt_samples) // " " // ui_str(nint(100 * zoom_total)), id="felt")
    end subroutine swatch

    subroutine pressed(chord)
        character(*), intent(in) :: chord
        presses = presses + 1
        last_key = chord
    end subroutine pressed

end module web_demo_app

