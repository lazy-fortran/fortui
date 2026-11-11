program canvas_bench
    !! Retained-canvas demo and frame-time probe: a sidebar (search field, toggles,
    !! wrapped UTF-8 Markdown note) beside a GPU canvas with ~50k points and ~200k
    !! line segments. Interactive by default (idle waiting, wheel zoom, drag pan,
    !! click to pick). Benchmark mode exits on its own:
    !!
    !!   FORTUI_BENCH_FRAMES=600 [FORTUI_BENCH_UPDATE=1] [FORTUI_BENCH_POINTS=50000] \
    !!       fpm run --example canvas_bench
    !!
    !! prints median/p95 frame milliseconds and canvas upload counters. With
    !! FORTUI_BENCH_UPDATE=1 every frame moves all points (re-upload per frame).
    use iso_fortran_env, only: int32, int64, real64
    use fortui
    use fortui_backends, only: ui_init
    use fortui_testing, only: ui_stats, ui_stats_t
    implicit none

    integer, parameter :: STEPS(4) = [13, 21, 34, 55]
    real, parameter :: GOLDEN = 2.39996323
    real, allocatable :: xy(:, :), base(:, :), sizes(:)
    integer(int32), allocatable :: rgba(:), edge_rgba(:)
    integer, allocatable :: segs(:, :)
    real(real64), allocatable :: frame_ms(:)
    character(len=:), allocatable :: query, note
    character(len=128) :: status_line
    character(len=32) :: env
    type(canvas_view_t) :: cam
    type(canvas_events_t) :: ev
    type(ui_stats_t) :: stats
    integer :: bench_frames, i, j, k, ns, np, stat, gen, picked, frame_no
    integer(int64) :: t0, t1, rate
    logical :: update_every_frame, show_labels, animate, submitted
    real :: wx, wy, best, d, phase

    call get_environment_variable("FORTUI_BENCH_FRAMES", env, status=stat)
    bench_frames = 0
    if (stat == 0) read(env, *, iostat=stat) bench_frames
    if (stat /= 0) bench_frames = 0
    call get_environment_variable("FORTUI_BENCH_POINTS", env, status=stat)
    np = 50000
    if (stat == 0) read(env, *, iostat=stat) np
    if (stat /= 0 .or. np < 100) np = 50000
    call get_environment_variable("FORTUI_BENCH_UPDATE", env, status=stat)
    update_every_frame = stat == 0 .and. trim(env) == "1"

    allocate(xy(2, np), base(2, np), sizes(np), rgba(np))
    do i = 1, np
        ! Sunflower spiral: index neighbours i+1, i+2, ... are spatial neighbours.
        base(1, i) = 4.0 * sqrt(real(i)) * cos(GOLDEN * real(i))
        base(2, i) = 4.0 * sqrt(real(i)) * sin(GOLDEN * real(i))
        sizes(i) = 3.0 + real(mod(i * 7919, 6))
        rgba(i) = palette(mod(i, 5))
    end do
    xy = base
    ns = size(STEPS) * (np - maxval(STEPS))
    allocate(segs(2, ns), edge_rgba(np))
    k = 0
    do i = 1, np - maxval(STEPS)
        do j = 1, size(STEPS)
            k = k + 1
            segs(1, k) = i
            segs(2, k) = i + STEPS(j)
        end do
    end do
    edge_rgba = ui_rgba(140, 150, 170, 90)

    query = ""
    note = build_note()
    show_labels = .true.
    animate = .false.
    picked = 0
    gen = 1
    phase = 0.0
    status_line = "click a point"
    cam = canvas_view_t(zoom=0.6, pan_x=600.0, pan_y=450.0)

    if (bench_frames > 0) then
        call ui_init("gui", 1600, 1000, "FortUI canvas bench", target_fps=0, &
            vsync=.false., &
            stat=stat)
    else
        call ui_init("gui", 1600, 1000, "FortUI canvas demo", stat=stat)
    end if
    if (stat /= 0) error stop "GUI backend unavailable (build with make build-gui)"
    if (bench_frames > 0) then
        call ui_set_continuous(.true.)
        allocate(frame_ms(bench_frames))
    end if

    call system_clock(t0, rate)
    frame_no = 0
    do while (.not. ui_should_close())
        call ui_frame_begin()
        if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
        call split_begin("main", first=360.0, gap=8.0)
        call column_begin(6.0)
        call text("Graph – Übersicht", style=UI_HEADING)
        if (text_input("search", query, placeholder="Search…", submitted=submitted)) &
            status_line = "query: " // query
        if (checkbox("labels", show_labels, "Show labels")) continue
        if (checkbox("animate", animate, "Animate layout")) call ui_set_continuous(animate)
        call text(trim(status_line), style=UI_CAPTION, ellipsis=.true.)
        call scroll_text("note", note, markdown=.true.)
        call column_end()
        call split_next()

        if (animate .or. update_every_frame) then
            phase = phase + 0.05
            xy(1, :) = base(1, :) + 3.0 * sin(phase + 0.01 * base(2, :))
            xy(2, :) = base(2, :) + 3.0 * cos(phase + 0.01 * base(1, :))
            gen = gen + 1
        end if
        if (bench_frames > 0 .and. .not. update_every_frame) &
            cam%pan_x = 600.0 + 100.0 * sin(0.01 * real(frame_no))

        call canvas_begin("graph", cam, ev, fill=ui_rgba(16, 18, 24))
        call canvas_vertices("pos", gen, xy)
        call canvas_lines("edges", "pos", segs, edge_rgba, generation=1, width=1.0)
        call canvas_points("nodes", "pos", rgba, sizes=sizes, min_pixels=2.0)
        if (show_labels) then
            do i = 1, 40
                call canvas_label(xy(1, i * 97), xy(2, i * 97), "Knoten Nr. " // &
                    ui_str(i * 97), &
                    13.0, ui_rgba(220, 220, 230))
            end do
            if (picked > 0) call canvas_label(xy(1, picked), xy(2, picked), &
                "▶ " // ui_str(picked), 16.0, ui_rgba(255, 220, 90))
        end if
        if (abs(ev%wheel) > 0.0) call canvas_zoom_at(cam, 1.15**ev%wheel, ev%local_x, &
            ev%local_y, 0.01, 200.0)
        if (ev%dragging) then
            cam%pan_x = cam%pan_x + ev%drag_dx
            cam%pan_y = cam%pan_y + ev%drag_dy
        end if
        if (ev%clicked) then
            best = huge(1.0)
            picked = 0
            do i = 1, np
                d = (xy(1, i) - ev%x)**2 + (xy(2, i) - ev%y)**2
                if (d < best) then
                    best = d
                    picked = i
                end if
            end do
            call canvas_to_world(cam, ev%local_x, ev%local_y, wx, wy)
            write(status_line, '(a,i0,a,2f9.1)') "picked ", picked, " at", wx, wy
        end if
        call canvas_end(cam)
        call split_end()
        call ui_present()

        frame_no = frame_no + 1
        call system_clock(t1)
        if (bench_frames > 0) then
            frame_ms(frame_no) = real(t1 - t0, real64) * 1000.0_real64 / real(rate, real64)
            t0 = t1
            if (frame_no >= bench_frames) exit
        end if
    end do

    stats = ui_stats()
    if (bench_frames > 20 .and. frame_no > 20) then
        call sort(frame_ms(11:frame_no))
        write(*, '(a,i0,a,i0,a,i0)') "points=", np, " segments=", ns, " frames=", frame_no
        write(*, '(a,f8.3,a,f8.3)') "median_ms=", frame_ms(10 + (frame_no - 10) / 2), &
            " p95_ms=", frame_ms(10 + nint(0.95 * real(frame_no - 10)))
        write(*, '(a,i0,a,i0,a,i0,a,i0)') "vertex_uploads=", stats%vertex_uploads, &
            " attribute_uploads=", stats%attribute_uploads, " index_uploads=", &
            stats%index_uploads, " layers=", stats%active_layers
        write(*, '(a,f5.2)') "ui_scale=", ui_scale()
    end if
    call ui_shutdown()

contains

    integer(int32) function palette(j)
        integer, intent(in) :: j
        select case (j)
        case (0); palette = ui_rgba(102, 194, 165)
        case (1); palette = ui_rgba(252, 141, 98)
        case (2); palette = ui_rgba(141, 160, 203)
        case (3); palette = ui_rgba(231, 138, 195)
        case default; palette = ui_rgba(166, 216, 84)
        end select
    end function palette

    function build_note() result(s)
        character(len=:), allocatable :: s
        integer :: j

        s = "# Notiz: Größenordnung" // achar(10) // achar(10)
        do j = 1, 60
            s = s // "## Abschnitt " // ui_str(j) // achar(10) // &
                "Über die Brücke gehen Bären, Füchse und Rehe; die Straße führt → " // &
                "zum Ölberg. Greek: α β γ δ λ π Ω. Größe ≤ 10 ± 2 °C, Preis 5 €. " // &
                "Ein längerer Absatz prüft den Umbruch über mehrere Zeilen hinweg, " // &
                "ohne dass Wörter in der Mitte getrennt werden." // achar(10) // achar(10)
        end do
    end function build_note

    subroutine sort(a)
        real(real64), intent(inout) :: a(:)
        integer :: i, j
        real(real64) :: v
        do i = 2, size(a)
            v = a(i)
            j = i - 1
            do while (j >= 1)
                if (a(j) <= v) exit
                a(j + 1) = a(j)
                j = j - 1
            end do
            a(j + 1) = v
        end do
    end subroutine sort

end program canvas_bench
