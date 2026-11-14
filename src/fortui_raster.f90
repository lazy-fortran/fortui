module fortui_raster
    !! Software rasterizer for canvas layers (terminal backends).
    !!
    !! Draws the retained point and indexed-line layers of one canvas node into an
    !! RGB buffer (0x00RRGGBB per pixel) with source-over alpha blending, in layer
    !! order. The same raster feeds terminal braille cells (2x4 dots per cell) and
    !! pixel protocols. A `raster_map_t` maps logical frame coordinates to raster
    !! pixels, so the same canvas view gives the same picture at any resolution.
    !!
    !! Hot path: buffers are reused (grown only), lines and discs are clipped to
    !! horizontal bands, and bands are drawn in parallel with OpenMP when FortUI is
    !! compiled with it; each pixel belongs to one band, so the result does not
    !! depend on the thread count.
    use iso_fortran_env, only: int32
    use fortui_frame, only: ui_frame_t, ui_node_t, ui_layer_ref_t, LAYER_POINTS, &
        LAYER_LINES, LAYER_IMAGE
    use fortui_canvas, only: canvas_store_t
    !$ use omp_lib, only: omp_get_max_threads
    implicit none
    private

    integer, parameter, public :: BRAILLE_BASE = 10240
    !! Braille dot bit of the dot at column dx (0..1), row dy (0..3) of a cell.
    integer, parameter, public :: BRAILLE_BIT(0:1, 0:3) = reshape( &
        [1, 8, 2, 16, 4, 32, 64, 128], [2, 4])

    type, public :: raster_map_t
        !! raster x = (logical x - origin_x) * scale_x (same for y); logical units are
        !! frame coordinates of the canvas node.
        real :: origin_x = 0.0
        real :: origin_y = 0.0
        real :: scale_x = 1.0
        real :: scale_y = 1.0
        !! Discs wider than three times this many pixels are drawn as rings of
        !! this width (0: always filled). Coarse rasters (braille) use rings so
        !! that large overlapping discs stay distinguishable.
        real :: outline = 0.0
    end type raster_map_t

    type, public :: raster_t
        integer :: width = 0
        integer :: height = 0
        integer(int32) :: background = 0
        integer(int32), allocatable :: rgb(:)
        ! Workspace: transformed vertex positions and per-layer offsets into them.
        real, allocatable :: px(:), py(:)
        integer, allocatable :: offset(:)
        integer, allocatable :: offset_slot(:)
    end type raster_t

    public :: raster_resize, raster_clear, raster_canvas, raster_line, raster_disc
    public :: raster_braille, braille_cell, rgb_pack, rgb_of_rgba, rgb_blend
    public :: rgb_to_xterm256, rgb_contrast, rgb_boost

contains

    pure integer(int32) function rgb_pack(r, g, b) result(c)
        integer, intent(in) :: r, g, b
        c = int(ior(ior(ishft(iand(r, 255), 16), ishft(iand(g, 255), 8)), iand(b, 255)), &
            int32)
    end function rgb_pack

    pure integer(int32) function rgb_of_rgba(rgba) result(c)
        !! 0x00RRGGBB of a `ui_rgba` value (alpha dropped).
        integer(int32), intent(in) :: rgba
        c = rgb_pack(int(iand(rgba, 255_int32)), int(iand(ishft(rgba, -8), 255_int32)), &
            int(iand(ishft(rgba, -16), 255_int32)))
    end function rgb_of_rgba

    pure integer(int32) function rgb_blend(dst, src, alpha) result(c)
        !! Source-over blend of `src` onto `dst` with alpha 0..255.
        integer(int32), intent(in) :: dst, src
        integer, intent(in) :: alpha
        integer :: dr, dg, db, sr, sg, sb

        if (alpha >= 255) then
            c = src
            return
        end if
        dr = int(iand(ishft(dst, -16), 255_int32))
        dg = int(iand(ishft(dst, -8), 255_int32))
        db = int(iand(dst, 255_int32))
        sr = int(iand(ishft(src, -16), 255_int32))
        sg = int(iand(ishft(src, -8), 255_int32))
        sb = int(iand(src, 255_int32))
        dr = dr + ((sr - dr) * alpha + sign(127, sr - dr)) / 255
        dg = dg + ((sg - dg) * alpha + sign(127, sg - dg)) / 255
        db = db + ((sb - db) * alpha + sign(127, sb - db)) / 255
        c = rgb_pack(dr, dg, db)
    end function rgb_blend

    pure integer function rgb_contrast(a, b) result(d)
        !! Largest channel difference of two packed colours.
        integer(int32), intent(in) :: a, b
        d = max(abs(int(iand(ishft(a, -16), 255_int32)) - &
            int(iand(ishft(b, -16), 255_int32))), &
            abs(int(iand(ishft(a, -8), 255_int32)) - int(iand(ishft(b, -8), 255_int32))), &
            abs(int(iand(a, 255_int32)) - int(iand(b, 255_int32))))
    end function rgb_contrast

    pure integer(int32) function rgb_boost(c, bg) result(out)
        !! Raise the contrast of `c` against `bg` to min(2 contrast,
        !! 255 sqrt(contrast/255)), keeping its hue: thin braille dots of faint
        !! (blended) colours stay visible, dimmed content stays dimmer than opaque.
        integer(int32), intent(in) :: c, bg
        integer :: m, k, ch(3), bc(3)
        real :: f

        m = rgb_contrast(c, bg)
        if (m <= 0) then
            out = c
            return
        end if
        f = min(2.0, 255.0 * sqrt(real(m) / 255.0) / real(m))
        do k = 1, 3
            ch(k) = int(iand(ishft(c, -8 * (3 - k)), 255_int32))
            bc(k) = int(iand(ishft(bg, -8 * (3 - k)), 255_int32))
            ch(k) = max(0, min(255, bc(k) + nint(f * real(ch(k) - bc(k)))))
        end do
        out = rgb_pack(ch(1), ch(2), ch(3))
    end function rgb_boost

    pure integer function rgb_to_xterm256(c) result(idx)
        !! Nearest xterm-256 palette index (6x6x6 cube 16..231 or grey 232..255).
        integer(int32), intent(in) :: c
        integer, parameter :: LEVEL(0:5) = [0, 95, 135, 175, 215, 255]
        integer :: ch(3), q(3), k, grey, gi, dc, dg, avg

        do k = 1, 3
            ch(k) = int(iand(ishft(c, -8 * (3 - k)), 255_int32))
            if (ch(k) < 48) then
                q(k) = 0
            else if (ch(k) < 115) then
                q(k) = 1
            else
                q(k) = min(5, (ch(k) - 35) / 40)
            end if
        end do
        dc = 0
        do k = 1, 3
            dc = dc + (ch(k) - LEVEL(q(k)))**2
        end do
        avg = (ch(1) + ch(2) + ch(3)) / 3
        gi = max(0, min(23, (avg - 3) / 10))
        grey = 8 + 10 * gi
        dg = (ch(1) - grey)**2 + (ch(2) - grey)**2 + (ch(3) - grey)**2
        if (dg < dc) then
            idx = 232 + gi
        else
            idx = 16 + 36 * q(1) + 6 * q(2) + q(3)
        end if
    end function rgb_to_xterm256

    subroutine raster_resize(r, width, height)
        !! Size the raster; storage is reallocated only when it must grow.
        type(raster_t), intent(inout) :: r
        integer, intent(in) :: width, height
        integer :: n

        r%width = max(0, width)
        r%height = max(0, height)
        n = r%width * r%height
        if (allocated(r%rgb)) then
            if (size(r%rgb) >= n) return
            deallocate(r%rgb)
        end if
        allocate(r%rgb(max(n, 1)))
    end subroutine raster_resize

    subroutine raster_clear(r, background)
        type(raster_t), intent(inout) :: r
        integer(int32), intent(in) :: background
        integer :: n

        r%background = background
        n = r%width * r%height
        if (n > 0) r%rgb(1:n) = background
    end subroutine raster_clear

    subroutine raster_canvas(r, store, frame, node, map)
        !! Clear to the node fill and draw every layer of canvas `node` in order.
        type(raster_t), intent(inout) :: r
        type(canvas_store_t), intent(in) :: store
        type(ui_frame_t), intent(in) :: frame
        type(ui_node_t), intent(in) :: node
        type(raster_map_t), intent(in) :: map
        integer :: nl, j, total, nb, b, y0, y1

        call raster_clear(r, rgb_of_rgba(node%fill))
        nl = node%layer_count
        if (nl <= 0 .or. r%width <= 0 .or. r%height <= 0) return
        call transform_vertices(r, store, frame, node, map, total)
        nb = 1
        !$ nb = omp_get_max_threads()
        nb = max(1, min(nb, r%height / 8))
        !$omp parallel do schedule(dynamic, 1) private(b, y0, y1, j) if (nb > 1)
        do b = 1, nb
            y0 = ((b - 1) * r%height) / nb
            y1 = (b * r%height) / nb
            do j = 1, nl
                call draw_layer(r, store, frame%layers(node%layer_first + j - 1), &
                    r%offset(j), node, map, y0, y1)
            end do
        end do
        !$omp end parallel do
    end subroutine raster_canvas

    subroutine transform_vertices(r, store, frame, node, map, total)
        !! Raster positions of the vertex layers the node references, each once.
        type(raster_t), intent(inout) :: r
        type(canvas_store_t), intent(in) :: store
        type(ui_frame_t), intent(in) :: frame
        type(ui_node_t), intent(in) :: node
        type(raster_map_t), intent(in) :: map
        integer, intent(out) :: total
        integer :: nl, j, k, slot, n, i, off
        real :: ax, bx, ay, by

        nl = node%layer_count
        call grow_int(r%offset, nl)
        call grow_int(r%offset_slot, nl)
        ! Pass 1: offsets per distinct vertex slot.
        total = 0
        do j = 1, nl
            slot = frame%layers(node%layer_first + j - 1)%vertex_slot
            r%offset(j) = -1
            r%offset_slot(j) = slot
            do k = 1, j - 1
                if (r%offset_slot(k) == slot) then
                    r%offset(j) = r%offset(k)
                    exit
                end if
            end do
            if (r%offset(j) >= 0) cycle
            r%offset(j) = total
            if (slot > 0) total = total + store%layers(slot)%vertex_count
        end do
        call grow_real(r%px, total)
        call grow_real(r%py, total)
        ! raster = (node + world * zoom + pan - origin) * scale
        ax = node%canvas_view%zoom * map%scale_x
        bx = (node%x + node%canvas_view%pan_x - map%origin_x) * map%scale_x
        ay = node%canvas_view%zoom * map%scale_y
        by = (node%y + node%canvas_view%pan_y - map%origin_y) * map%scale_y
        do j = 1, nl
            if (r%offset_slot(j) <= 0) cycle
            if (j > 1) then
                if (any(r%offset_slot(1:j - 1) == r%offset_slot(j))) cycle
            end if
            slot = r%offset_slot(j)
            off = r%offset(j)
            n = store%layers(slot)%vertex_count
            if (n <= 0) cycle
            !$omp parallel do schedule(static) if (n > 20000)
            do i = 1, n
                r%px(off + i) = ax * store%layers(slot)%xy(1, i) + bx
                r%py(off + i) = ay * store%layers(slot)%xy(2, i) + by
            end do
            !$omp end parallel do
        end do
    end subroutine transform_vertices

    subroutine grow_int(a, n)
        integer, allocatable, intent(inout) :: a(:)
        integer, intent(in) :: n
        if (allocated(a)) then
            if (size(a) >= n) return
            deallocate(a)
        end if
        allocate(a(max(n, 8)))
    end subroutine grow_int

    subroutine grow_real(a, n)
        real, allocatable, intent(inout) :: a(:)
        integer, intent(in) :: n
        if (allocated(a)) then
            if (size(a) >= n) return
            deallocate(a)
        end if
        allocate(a(max(n, 64)))
    end subroutine grow_real

    subroutine draw_layer(r, store, ref, off, node, map, y0, y1)
        !! Draw one layer into rows [y0, y1) of the raster.
        type(raster_t), intent(inout) :: r
        type(canvas_store_t), intent(in) :: store
        type(ui_layer_ref_t), intent(in) :: ref
        integer, intent(in) :: off, y0, y1
        type(ui_node_t), intent(in) :: node
        type(raster_map_t), intent(in) :: map
        integer :: i, n, a, ia, ib, aa, ab
        real :: scale, rad, thick

        if (ref%slot <= 0) return
        if (ref%kind == LAYER_IMAGE) then
            call raster_image(r, store%layers(ref%slot)%rgba, &
                store%layers(ref%slot)%image_width, store%layers(ref%slot)%image_height, &
                store%layers(ref%slot)%rect, node, map, y0, y1)
            return
        end if
        if (ref%vertex_slot <= 0) return
        associate(l => store%layers(ref%slot))
            select case (ref%kind)
            case (LAYER_POINTS)
                if (.not. allocated(l%rgba) .or. .not. allocated(l%sizes)) return
                scale = 1.0
                if (l%world_size) scale = node%canvas_view%zoom
                n = min(l%vertex_count, size(l%rgba), size(l%sizes))
                do i = 1, n
                    a = alpha_of(l%rgba(i))
                    if (a == 0) cycle
                    rad = max(0.5 * l%sizes(i) * scale, 0.5 * l%min_pixels)
                    call raster_disc(r, r%px(off + i), r%py(off + i), rad * map%scale_x, &
                        rad * map%scale_y, rgb_of_rgba(l%rgba(i)), a, y0, y1, map%outline)
                end do
            case (LAYER_LINES)
                if (.not. allocated(l%rgba) .or. .not. allocated(l%indices)) return
                thick = l%line_width * sqrt(map%scale_x * map%scale_y)
                n = min(l%index_count, size(l%indices)) / 2
                do i = 1, n
                    ia = int(l%indices(2 * i - 1)) + 1
                    ib = int(l%indices(2 * i)) + 1
                    if (ia > size(l%rgba) .or. ib > size(l%rgba)) cycle
                    aa = alpha_of(l%rgba(ia))
                    ab = alpha_of(l%rgba(ib))
                    if (aa == 0 .and. ab == 0) cycle
                    call raster_line(r, r%px(off + ia), r%py(off + ia), r%px(off + ib), &
                        r%py(off + ib), rgb_of_rgba(l%rgba(ia)), aa, &
                        rgb_of_rgba(l%rgba(ib)), ab, thick, y0, y1)
                end do
            end select
        end associate
    end subroutine draw_layer

    subroutine raster_image(r, rgba, iw, ih, rect, node, map, y0, y1)
        !! Nearest-pixel image into rows [y0, y1): each raster pixel takes the
        !! image pixel under its centre, blended by that pixel's alpha.
        type(raster_t), intent(inout) :: r
        integer(int32), intent(in) :: rgba(:)
        integer, intent(in) :: iw, ih, y0, y1
        real, intent(in) :: rect(4)
        type(ui_node_t), intent(in) :: node
        type(raster_map_t), intent(in) :: map
        real :: x0, xr, yt, yb
        integer :: px, py, ix, iy, a, p

        if (iw <= 0 .or. ih <= 0 .or. rect(3) <= 0.0 .or. rect(4) <= 0.0) return
        x0 = (node%x + node%canvas_view%pan_x + rect(1) * node%canvas_view%zoom - &
            map%origin_x) * map%scale_x
        xr = x0 + rect(3) * node%canvas_view%zoom * map%scale_x
        yt = (node%y + node%canvas_view%pan_y + rect(2) * node%canvas_view%zoom - &
            map%origin_y) * map%scale_y
        yb = yt + rect(4) * node%canvas_view%zoom * map%scale_y
        do py = max(y0, ceiling(yt - 0.5)), min(y1 - 1, r%height - 1)
            if (py + 0.5 >= yb) exit
            iy = min(ih, 1 + int((py + 0.5 - yt) / (yb - yt) * ih))
            do px = max(0, ceiling(x0 - 0.5)), r%width - 1
                if (px + 0.5 >= xr) exit
                ix = min(iw, 1 + int((px + 0.5 - x0) / (xr - x0) * iw))
                p = rgba(ix + (iy - 1) * iw)
                a = alpha_of(p)
                if (a == 0) cycle
                associate(dst => r%rgb(1 + px + py * r%width))
                    if (a == 255) then
                        dst = rgb_of_rgba(p)
                    else
                        dst = rgb_blend(dst, rgb_of_rgba(p), a)
                    end if
                end associate
            end do
        end do
    end subroutine raster_image

    pure integer function alpha_of(rgba) result(a)
        integer(int32), intent(in) :: rgba
        a = int(iand(ishft(rgba, -24), 255_int32))
    end function alpha_of

    subroutine raster_line(r, xa, ya, xb, yb, ca, aa, cb, ab, thickness, y0, y1)
        !! Line from (xa, ya) to (xb, yb) in raster pixels, colours/alphas linearly
        !! interpolated, `thickness` in pixels (rounded, at least 1), clipped to the
        !! raster and to rows [y0, y1).
        type(raster_t), intent(inout) :: r
        real, intent(in) :: xa, ya, xb, yb, thickness
        integer(int32), intent(in) :: ca, cb
        integer, intent(in) :: aa, ab, y0, y1
        integer :: k, o, lo
        real :: ox, oy

        k = max(1, nint(thickness))
        if (k == 1) then
            call line_1(r, xa, ya, xb, yb, ca, aa, cb, ab, y0, y1)
            return
        end if
        ! Thick lines: parallel offsets along the minor axis.
        lo = -(k - 1) / 2
        do o = lo, lo + k - 1
            ox = 0.0
            oy = 0.0
            if (abs(xb - xa) >= abs(yb - ya)) then
                oy = real(o)
            else
                ox = real(o)
            end if
            call line_1(r, xa + ox, ya + oy, xb + ox, yb + oy, ca, aa, cb, ab, y0, y1)
        end do
    end subroutine raster_line

    subroutine line_1(r, xa, ya, xb, yb, ca, aa, cb, ab, y0, y1)
        !! One-pixel line: samples k = 0..n at t = k / n with n = ceil(max(|dx|,
        !! |dy|)), colour and alpha interpolated linearly. Only the samples whose
        !! parameter lies in the clipped range are visited, and each sample is
        !! computed from k alone, so a line drawn in bands equals the line drawn
        !! whole (the raster does not depend on the thread count).
        type(raster_t), intent(inout) :: r
        real, intent(in) :: xa, ya, xb, yb
        integer(int32), intent(in) :: ca, cb
        integer, intent(in) :: aa, ab, y0, y1
        real, parameter :: LIMIT = 1.0e7
        real :: dx, dy, t0, t1, t, inv, x, y
        real :: cr, cg, cbl, al, dcr, dcg, dcb, dal
        integer :: n, k, klo, khi, ix, iy, idx, w, dr, dg, db
        integer(int32) :: dst
        logical :: ok

        if (y1 <= y0 .or. r%width <= 0) return
        if (.not. (abs(xa) < LIMIT)) return
        if (.not. (abs(ya) < LIMIT)) return
        if (.not. (abs(xb) < LIMIT)) return
        if (.not. (abs(yb) < LIMIT)) return
        if (max(ya, yb) < real(y0) .or. min(ya, yb) >= real(y1)) return
        if (max(xa, xb) < 0.0 .or. min(xa, xb) >= real(r%width)) return
        dx = xb - xa
        dy = yb - ya
        t0 = 0.0
        t1 = 1.0
        ok = .true.
        call clip(-dx, xa, t0, t1, ok)
        if (ok) call clip(dx, real(r%width) - xa, t0, t1, ok)
        if (ok) call clip(-dy, ya - real(y0), t0, t1, ok)
        if (ok) call clip(dy, real(y1) - ya, t0, t1, ok)
        if (.not. ok) return
        n = max(1, ceiling(max(abs(dx), abs(dy))))
        inv = 1.0 / real(n)
        ! One sample of margin each side; samples outside the band are skipped.
        klo = max(0, int(floor(t0 * real(n))) - 1)
        khi = min(n, int(ceiling(t1 * real(n))) + 1)
        w = r%width
        cr = real(iand(ishft(ca, -16), 255_int32))
        cg = real(iand(ishft(ca, -8), 255_int32))
        cbl = real(iand(ca, 255_int32))
        al = real(aa) / 255.0
        dcr = real(iand(ishft(cb, -16), 255_int32)) - cr
        dcg = real(iand(ishft(cb, -8), 255_int32)) - cg
        dcb = real(iand(cb, 255_int32)) - cbl
        dal = real(ab - aa) / 255.0
        do k = klo, khi
            t = real(k) * inv
            x = xa + dx * t
            y = ya + dy * t
            if (x < 0.0 .or. y < real(y0)) cycle
            ix = int(x)
            iy = int(y)
            if (ix >= w .or. iy >= y1) cycle
            idx = ix + iy * w + 1
            dst = r%rgb(idx)
            dr = int(iand(ishft(dst, -16), 255_int32))
            dg = int(iand(ishft(dst, -8), 255_int32))
            db = int(iand(dst, 255_int32))
            dr = dr + nint((cr + dcr * t - real(dr)) * (al + dal * t))
            dg = dg + nint((cg + dcg * t - real(dg)) * (al + dal * t))
            db = db + nint((cbl + dcb * t - real(db)) * (al + dal * t))
            r%rgb(idx) = int(ior(ior(ishft(dr, 16), ishft(dg, 8)), db), int32)
        end do
    end subroutine line_1

    pure subroutine clip(p, q, t0, t1, ok)
        !! Liang-Barsky step for the constraint p * t <= q.
        real, intent(in) :: p, q
        real, intent(inout) :: t0, t1
        logical, intent(inout) :: ok
        real :: t

        if (.not. (abs(p) > 0.0)) then
            if (q < 0.0) ok = .false.
            return
        end if
        t = q / p
        if (p < 0.0) then
            t0 = max(t0, t)
        else
            t1 = min(t1, t)
        end if
        if (t0 > t1) ok = .false.
    end subroutine clip

    subroutine raster_disc(r, cx, cy, rx, ry, c, a, y0, y1, ring)
        !! Filled ellipse with centre (cx, cy) and radii (rx, ry) in pixels: pixels
        !! whose centres lie inside, and at least the pixel containing the centre.
        !! With `ring` > 0 and both radii above 1.5 * ring, only the outer band of
        !! that width is drawn. Clipped to the raster and rows [y0, y1).
        type(raster_t), intent(inout) :: r
        real, intent(in) :: cx, cy, rx, ry
        integer(int32), intent(in) :: c
        integer, intent(in) :: a, y0, y1
        real, intent(in), optional :: ring
        real, parameter :: LIMIT = 1.0e7
        integer :: j, jlo, jhi, i, ilo, ihi, jc, ic, hlo, hhi, base
        real :: d, half, ryy, irx, iry, di

        if (.not. (abs(cx) < LIMIT)) return
        if (.not. (abs(cy) < LIMIT)) return
        if (cy + ry < real(y0) .or. cy - ry >= real(y1)) return
        if (cx + rx < 0.0 .or. cx - rx >= real(r%width)) return
        jc = int(floor(cy))
        ic = int(floor(cx))
        ryy = max(ry, 1.0e-6)
        irx = 0.0
        iry = 0.0
        if (present(ring)) then
            if (ring > 0.0 .and. min(rx, ry) > 1.5 * ring) then
                irx = rx - ring
                iry = ry - ring
            end if
        end if
        jlo = max(y0, int(floor(cy - ry)))
        jhi = min(y1 - 1, int(floor(cy + ry)))
        do j = jlo, jhi
            d = (real(j) + 0.5 - cy) / ryy
            if (abs(d) <= 1.0) then
                half = rx * sqrt(1.0 - d * d)
                ilo = ceiling(cx - half - 0.5)
                ihi = floor(cx + half - 0.5)
            else
                ilo = 1
                ihi = 0
            end if
            if (j == jc .and. ilo > ihi) then
                ilo = ic
                ihi = ic
            end if
            ! Hole of a ring: pixel centres inside the inner ellipse.
            hlo = 1
            hhi = 0
            if (iry > 0.0) then
                di = (real(j) + 0.5 - cy) / iry
                if (abs(di) < 1.0) then
                    half = irx * sqrt(1.0 - di * di)
                    hlo = ceiling(cx - half - 0.5)
                    hhi = floor(cx + half - 0.5)
                end if
            end if
            ilo = max(0, ilo)
            ihi = min(r%width - 1, ihi)
            base = j * r%width + 1
            if (hlo > hhi .and. a >= 255) then
                if (ihi >= ilo) r%rgb(base + ilo:base + ihi) = c
                cycle
            end if
            do i = ilo, ihi
                if (i >= hlo .and. i <= hhi) cycle
                r%rgb(base + i) = rgb_blend(r%rgb(base + i), c, a)
            end do
        end do
    end subroutine raster_disc

    pure subroutine braille_cell(r, col, row, threshold, glyph, fg)
        !! Braille glyph of cell (col, row) (0-based; dots 2col.., 4row..): a dot is
        !! set when its pixel differs from the background by at least `threshold`
        !! in some channel; `fg` is the dot colour of highest contrast (the last
        !! such dot on ties). Empty cells yield a space and the background.
        type(raster_t), intent(in) :: r
        integer, intent(in) :: col, row, threshold
        integer, intent(out) :: glyph
        integer(int32), intent(out) :: fg
        integer :: dx, dy, x, y, bits, m, best
        integer(int32) :: c

        bits = 0
        best = -1
        fg = r%background
        do dy = 0, 3
            y = 4 * row + dy
            if (y >= r%height) exit
            do dx = 0, 1
                x = 2 * col + dx
                if (x >= r%width) exit
                c = r%rgb(x + y * r%width + 1)
                m = rgb_contrast(c, r%background)
                if (m < threshold) cycle
                bits = ior(bits, BRAILLE_BIT(dx, dy))
                if (m >= best) then
                    best = m
                    fg = c
                end if
            end do
        end do
        if (bits == 0) then
            glyph = 32
        else
            glyph = BRAILLE_BASE + bits
        end if
    end subroutine braille_cell

    subroutine raster_braille(r, cols, rows, threshold, boost, glyph, fg)
        !! Braille cells of a raster of (2 cols) x (4 rows) dots, row-major:
        !! cell (c, k) is element c + k * cols + 1. With `boost`, faint colours are
        !! brightened (`rgb_boost`) so that single dots stay visible.
        type(raster_t), intent(in) :: r
        integer, intent(in) :: cols, rows, threshold
        logical, intent(in) :: boost
        integer, intent(inout) :: glyph(:)
        integer(int32), intent(inout) :: fg(:)
        integer :: c, k, g
        integer(int32) :: colour

        !$omp parallel do private(c, g, colour) if (cols * rows > 20000)
        do k = 0, rows - 1
            do c = 0, cols - 1
                call braille_cell(r, c, k, threshold, g, colour)
                if (boost .and. g /= 32) colour = rgb_boost(colour, r%background)
                glyph(c + k * cols + 1) = g
                fg(c + k * cols + 1) = colour
            end do
        end do
        !$omp end parallel do
    end subroutine raster_braille

end module fortui_raster
