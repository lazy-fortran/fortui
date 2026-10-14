program tui_canvas_bench
!! Terminal canvas cost without a terminal: rasterize a graph-sized canvas
!! (default 8000 points, 38000 lines) into braille cells at 200x60 cells and
!! into a kitty image at 10x21 pixel cells, then encode the kitty commands.
!! The view pans every frame, so every frame is a full redraw.
!!
!!   fpm run --example tui_canvas_bench [-- POINTS LINES COLS ROWS PXW PXH]
!!   (add -fopenmp to the flags and set OMP_NUM_THREADS for threads)
use iso_fortran_env, only: int32, int64
use fortui_frame, only: ui_frame_t, ui_node_t, UI_CANVAS
use fortui_canvas, only: canvas_store_t, ui_rgba
use fortui_raster, only: raster_t, raster_resize, raster_canvas, raster_braille
use fortui_kitty, only: kitty_encoder_t, kitty_encode_image
use fortui_tui, only: tui_canvas_map, CELL_W_DP, CELL_H_DP
!$ use omp_lib, only: omp_get_max_threads
implicit none

integer, parameter :: FRAMES = 20
integer :: n, m, cols, rows, pxw, pxh, i, v, l, p, k, f, threads
real, allocatable :: xy(:, :), sizes(:), u(:)
integer(int32), allocatable :: prgba(:), lrgba(:)
integer, allocatable :: segs(:, :)
type(canvas_store_t) :: store
type(ui_frame_t) :: frame
type(ui_node_t) :: node
type(raster_t) :: braille, pixels
type(kitty_encoder_t) :: enc
integer, allocatable :: glyph(:)
integer(int32), allocatable :: fg(:)
integer(int64) :: t0, t1, rate
real :: tb, tk, te, bytes

n = arg(1, 8000)
m = arg(2, 38000)
cols = arg(3, 200)
rows = arg(4, 60)
pxw = arg(5, 10)
pxh = arg(6, 21)
threads = 1
!$ threads = omp_get_max_threads()

allocate(xy(2, n), sizes(n), u(2 * n), prgba(n), lrgba(n), segs(2, m))
call random_seed(put=[(17 + i, i = 1, 64)])
call random_number(u)
do i = 1, n
    ! Points in a disc filling the canvas, denser in the centre.
    xy(1, i) = 0.5 * cols * CELL_W_DP + 0.45 * cols * CELL_W_DP * sqrt(u(i)) * &
        cos(6.2831853 * u(n + i))
    xy(2, i) = 0.5 * rows * CELL_H_DP + 0.45 * rows * CELL_H_DP * sqrt(u(i)) * &
        sin(6.2831853 * u(n + i))
    sizes(i) = 3.0 + 6.0 * u(n + i)
    prgba(i) = ui_rgba(80 + mod(i * 37, 170), 120 + mod(i * 11, 130), 200, 240)
    lrgba(i) = ui_rgba(80 + mod(i * 37, 170), 120 + mod(i * 11, 130), 200, 44)
end do
deallocate(u)
allocate(u(2 * m))
call random_number(u)
do k = 1, m
    ! Graph layouts connect mostly nearby nodes: the second end is the nearest
    ! of a few random candidates for 90% of the edges, any node otherwise.
    segs(1, k) = 1 + int(u(k) * real(n - 1))
    segs(2, k) = 1 + int(u(m + k) * real(n - 1))
    if (mod(k, 10) /= 0) segs(2, k) = nearest_of(segs(1, k), 40, k)
end do

v = store%submit_vertices("c/pos", 1, xy, 1)
l = store%submit_lines("c/edges", v, 1, lrgba, 1, segs, 1)
p = store%submit_points("c/nodes", v, 1, prgba, sizes=sizes, frame_no=1)
call frame%reset()
node%kind = UI_CANVAS
node%id = "c"
node%width = cols * CELL_W_DP
node%height = rows * CELL_H_DP
node%fill = ui_rgba(17, 19, 25)
node%layer_first = 1
node%layer_count = 2
k = frame%append_layer(store%ref(l))
k = frame%append_layer(store%ref(p))
k = frame%append(node)

call raster_resize(braille, 2 * cols, 4 * rows)
allocate(glyph(cols * rows), fg(cols * rows))
call raster_resize(pixels, cols * pxw, rows * pxh)
tb = 0.0
tk = 0.0
te = 0.0
bytes = 0.0
call system_clock(count_rate=rate)
do f = 0, FRAMES
    frame%nodes(1)%canvas_view%pan_x = 2.0 * f
    frame%nodes(1)%canvas_view%zoom = 1.0 + 0.01 * f
    call system_clock(t0)
    call raster_canvas(braille, store, frame, frame%nodes(1), &
        tui_canvas_map(0, 0, 2, 4))
    call raster_braille(braille, cols, rows, 10, .true., glyph, fg)
    call system_clock(t1)
    if (f > 0) tb = tb + real(t1 - t0)
    call system_clock(t0)
    call raster_canvas(pixels, store, frame, frame%nodes(1), &
        tui_canvas_map(0, 0, pxw, pxh))
    call system_clock(t1)
    if (f > 0) tk = tk + real(t1 - t0)
    call system_clock(t0)
    call kitty_encode_image(enc, pixels%rgb, pixels%width, pixels%height, 1, cols, rows)
    call system_clock(t1)
    if (f > 0) te = te + real(t1 - t0)
    if (f > 0) bytes = bytes + real(enc%out_len)
end do
print '(a,i0,a,i0,a,i0,a,i0,a,i0)', "points ", n, " lines ", m, " cells ", cols, &
    "x", rows, " threads ", threads
print '(a,f8.3,a)', "braille raster + cells: ", 1000.0 * tb / real(rate) / FRAMES, &
    " ms/frame"
print '(a,i0,a,i0,a,f8.3,a)', "kitty raster ", pixels%width, "x", pixels%height, &
    ": ", 1000.0 * tk / real(rate) / FRAMES, " ms/frame"
print '(a,i0,a,i0)', "checksums (thread-count invariant): braille ", &
    sum(int(glyph, int64) * 31 + int(fg, int64)), " pixels ", &
    sum(int(pixels%rgb(1:pixels%width * pixels%height), int64))
print '(a,f8.3,a,f9.1,a)', "kitty zlib+base64: ", 1000.0 * te / real(rate) / FRAMES, &
    " ms/frame, ", bytes / FRAMES / 1024.0, " KiB/frame"

contains

integer function nearest_of(i, tries, seed) result(best)
    integer, intent(in) :: i, tries, seed
    integer :: t, j
    real :: d, dbest
    best = 1 + mod(i, n)
    dbest = huge(1.0)
    do t = 1, tries
        j = 1 + mod(i * 31 + seed * 17 + t * 7919, n)
        if (j == i) cycle
        d = (xy(1, j) - xy(1, i))**2 + (xy(2, j) - xy(2, i))**2
        if (d < dbest) then
            dbest = d
            best = j
        end if
    end do
end function nearest_of

integer function arg(i, default)
    integer, intent(in) :: i, default
    character(len=32) :: s
    integer :: st
    arg = default
    if (command_argument_count() < i) return
    call get_command_argument(i, s)
    read(s, *, iostat=st) arg
    if (st /= 0) arg = default
end function arg

end program tui_canvas_bench
