program tui_demo
! Comprehensive TUI demo showing ALL fortui capabilities:
! - Text rendering with labels and dynamic content
! - Buttons with click detection and visual feedback
! - Sliders with mouse-driven value adjustment
! - Checkboxes with toggle state
! - Viewport with pan/zoom
! - Column and row layouts with gaps
! - Nested layout composition
!
! Controls:
!   Mouse click   - interact with widgets
!   Mouse drag    - pan viewport
!   Mouse scroll  - zoom viewport
!   Tab           - cycle keyboard focus between widgets
!   Enter / Space - activate focused button or toggle checkbox
!   Left / Right  - adjust focused slider
!   ESC / Ctrl-C  - quit
use fortui
use fortui_layout, only: layout_get_cursor
implicit none

type(node) :: ui_tree
logical :: running
integer :: frame_count
logical :: btn_save, btn_load, btn_reset, btn_quit
real :: volume, brightness, speed
logical :: opt_sound, opt_fullscreen, opt_vsync
logical :: chk_toggled, slider_changed
type(view) :: vp_state
logical :: vp_changed
character(len=64) :: status_text, frame_text

call ui_init(backend="tui", width=80, height=24, &
    title="fortui TUI Demo")

running = .true.
frame_count = 0
volume = 50.0
brightness = 75.0
speed = 1.0
opt_sound = .true.
opt_fullscreen = .false.
opt_vsync = .true.
vp_state = view()
status_text = "Ready"

ui_tree = column()

do while (running .and. .not. ui_should_close())
    call ui_frame_begin()
    frame_count = frame_count + 1

    ! Title row
    call row_begin(2.0)
    call text("title", value="fortui TUI Demo", text_size=2.0)
    write(frame_text, '(A,I6)') "Frame:", frame_count
    call text("frame", value=trim(frame_text))
    call row_end()

    ! Separator
    call text("sep1", value=repeat('-', 60), width=60.0)

    ! Main content in columns
    call row_begin(4.0)

    ! Left column: buttons
    call column_begin(1.0)
    call text("btn_hdr", value="Actions")
    btn_save = button("save", label="Save")
    btn_load = button("load", label="Load")
    btn_reset = button("reset", label="Reset")
    btn_quit = button("quit", label="Quit")
    call column_end()

    ! Middle column: sliders
    call column_begin(1.0)
    call text("sld_hdr", value="Settings")

    call row_begin(1.0)
    call text("vol_lbl", value="Volume: ", width=8.0)
    slider_changed = slider("volume", min_val=0.0, &
        max_val=100.0, step_val=5.0, value=volume, width=20.0)
    call row_end()

    call row_begin(1.0)
    call text("brt_lbl", value="Bright: ", width=8.0)
    slider_changed = slider("brightness", min_val=0.0, &
        max_val=100.0, value=brightness, width=20.0)
    call row_end()

    call row_begin(1.0)
    call text("spd_lbl", value="Speed:  ", width=8.0)
    slider_changed = slider("speed", min_val=0.1, &
        max_val=10.0, step_val=0.1, value=speed, width=20.0)
    call row_end()

    call column_end()

    ! Right column: checkboxes
    call column_begin(1.0)
    call text("chk_hdr", value="Options")
    chk_toggled = checkbox("sound", checked=opt_sound, &
        label="Sound")
    chk_toggled = checkbox("fullscr", checked=opt_fullscreen, &
        label="Fullscreen")
    chk_toggled = checkbox("vsync", checked=opt_vsync, &
        label="VSync")
    call column_end()

    call row_end()

    ! Separator
    call text("sep2", value=repeat('-', 60), width=60.0)

    ! Viewport
    call text("vp_hdr", value="Viewport (drag to pan, scroll to zoom)")
    vp_changed = viewport("main_vp", 40.0, 8.0, vp_state)

    ! Status bar
    call text("sep3", value=repeat('-', 60), width=60.0)

    ! Handle button actions
    if (btn_save) status_text = "Saved!"
    if (btn_load) status_text = "Loaded!"
    if (btn_reset) then
        status_text = "Reset to defaults"
        volume = 50.0
        brightness = 75.0
        speed = 1.0
        opt_sound = .true.
        opt_fullscreen = .false.
        opt_vsync = .true.
        vp_state = view()
    end if
    if (btn_quit) running = .false.

    call text("status", value="Status: " // trim(status_text))

    call ui_present(ui_tree)
end do

call ui_shutdown()

end program tui_demo
