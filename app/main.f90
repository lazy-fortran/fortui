program fortui_demo
    !! Minimal FortUI application: controls plus a pannable/zoomable canvas.
    use fortui
    use fortui_backends, only: ui_init
    implicit none

    real :: gain, xy(2, 64), shown(2, 64)
    logical :: grid
    type(canvas_view_t) :: cam
    type(canvas_events_t) :: ev
    integer :: stat, i, gen

    gain = 1.0
    gen = 1
    grid = .false.
    cam = canvas_view_t(zoom=4.0, pan_x=320.0, pan_y=180.0)
    do i = 1, size(xy, 2)
        xy(:, i) = [real(i - 32), 10.0 * sin(0.2 * real(i))]
    end do

    call ui_init("auto", 900, 640, "FortUI demo", stat=stat)
    if (stat /= 0) error stop "No interactive backend available"

    do while (.not. ui_should_close())
        call ui_frame_begin()
        if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
        call text("FortUI", style=UI_TITLE)
        call row_begin(8.0)
        if (button("zoom_in", "Zoom In")) cam%zoom = cam%zoom * 1.2
        if (button("zoom_out", "Zoom Out")) cam%zoom = cam%zoom / 1.2
        if (button("quit", "Quit")) call ui_request_quit()
        call row_end()
        call text("Gain " // ui_str(gain, 1), style=UI_CAPTION)
        if (slider("gain", 0.1, 5.0, gain, step=0.1, width=260.0)) gen = gen + 1
        if (checkbox("grid", grid, "Show grid")) continue
        call canvas_begin("plot", cam, ev, fill=ui_rgba(20, 22, 28))
        if (abs(ev%wheel) > 0.0) call canvas_zoom_at(cam, 1.2**ev%wheel, ev%local_x, &
            ev%local_y)
        if (ev%dragging) then
            cam%pan_x = cam%pan_x + ev%drag_dx
            cam%pan_y = cam%pan_y + ev%drag_dy
        end if
        shown(1, :) = xy(1, :)
        shown(2, :) = gain * xy(2, :)
        call canvas_points("samples", gen, shown, [ui_rgba(120, 200, 255)], size=0.8)
        call canvas_end(cam)
        call ui_present()
    end do

    call ui_shutdown()
end program fortui_demo
