program test_tui_canvas
!! Terminal canvas realization without a terminal: braille raster cells and
!! colours for known layers, line clipping, discs at the raster edges, colour
!! conversion, kitty image encoding decoded back (base64 + an independent
!! fixed-Huffman inflate in this test), terminal reply parsing and the mapping
!! of terminal mouse cells/pixels to canvas world coordinates.
use iso_fortran_env, only: int8, int32
use fortui_frame, only: ui_frame_t, ui_node_t, UI_CANVAS
use fortui_canvas, only: canvas_store_t, canvas_view_t, ui_rgba, canvas_to_world
use fortui_raster, only: raster_t, raster_map_t, raster_resize, raster_clear, &
    raster_canvas, raster_line, raster_disc, raster_braille, rgb_pack, rgb_blend, &
    rgb_to_xterm256, rgb_boost, rgb_contrast, BRAILLE_BASE
use fortui_kitty, only: kitty_encoder_t, kitty_encode_image, KITTY_CHUNK
use fortui_tui, only: tui_parse_replies, tui_replies_t, tui_cell_to_logical, &
    tui_pixel_to_logical, tui_canvas_map, CELL_W_DP, CELL_H_DP
implicit none

integer :: failures = 0

call test_braille_canvas()
call test_line_clipping()
call test_disc_edges()
call test_colours()
call test_kitty_round_trip()
call test_replies()
call test_pointer_mapping()

if (failures > 0) then
    print '(i0,a)', failures, " tui canvas checks failed"
    error stop 1
end if
print '(a)', " fortui tui canvas tests passed"

contains

subroutine check(ok, what)
    logical, intent(in) :: ok
    character(*), intent(in) :: what
    if (.not. ok) then
        failures = failures + 1
        print '(a)', "FAIL: " // what
    end if
end subroutine check

subroutine canvas_frame(store, frame, node, xy, prgba, lrgba, segs, size)
    !! A frame with one canvas node at the origin (2x2 cells) drawing `segs`
    !! as lines, then the vertices as points.
    type(canvas_store_t), intent(inout) :: store
    type(ui_frame_t), intent(inout) :: frame
    type(ui_node_t), intent(out) :: node
    real, intent(in) :: xy(:, :)
    integer(int32), intent(in) :: prgba(:), lrgba(:)
    integer, intent(in) :: segs(:, :)
    real, intent(in) :: size
    integer :: v, p, l, k

    v = store%submit_vertices("c/pos", 1, xy, 1)
    l = store%submit_lines("c/l", v, 1, lrgba, 1, segs, 1)
    p = store%submit_points("c/p", v, 1, prgba, size=size, frame_no=1)
    call frame%reset()
    node%kind = UI_CANVAS
    node%id = "c"
    node%width = 2 * CELL_W_DP
    node%height = 2 * CELL_H_DP
    node%fill = ui_rgba(0, 0, 0)
    node%layer_first = 1
    node%layer_count = 2
    k = frame%append_layer(store%ref(l))
    k = frame%append_layer(store%ref(p))
    k = frame%append(node)
end subroutine canvas_frame

subroutine test_braille_canvas()
    !! 2x2 cells = 4x8 dots; one logical unit is 1/4 dot. Points at world
    !! (2, 2) and (14, 30) hit dots (0, 0) and (3, 7); the line between the
    !! first point and (14, 2) covers dots (0..3, 0).
    type(canvas_store_t) :: store
    type(ui_frame_t) :: frame
    type(ui_node_t) :: node
    type(raster_t) :: r
    real :: xy(2, 3)
    integer :: segs(2, 1), glyph(4)
    integer(int32) :: fg(4), red, green

    xy = reshape([2.0, 2.0, 14.0, 30.0, 14.0, 2.0], [2, 3])
    segs(:, 1) = [1, 3]
    red = rgb_pack(255, 0, 0)
    green = rgb_pack(0, 128, 0)
    call canvas_frame(store, frame, node, xy, &
        [ui_rgba(255, 0, 0), ui_rgba(255, 0, 0), ui_rgba(0, 0, 0, 0)], &
        [ui_rgba(0, 128, 0), ui_rgba(0, 128, 0), ui_rgba(0, 128, 0)], segs, 1.0)
    call raster_resize(r, 4, 8)
    call raster_canvas(r, store, frame, frame%nodes(1), tui_canvas_map(0, 0, 2, 4))
    call check(r%rgb(1) == red, "point over line keeps the point colour")
    call check(r%rgb(2) == green .and. r%rgb(4) == green, "line pixels")
    call check(r%rgb(4 + 7 * 4) == red, "second point at dot (3, 7)")
    call check(count(r%rgb(1:32) /= 0) == 5, "nothing else drawn")
    call raster_braille(r, 2, 2, 10, .false., glyph, fg)
    ! Cell (0,0): dots (0,0) and (1,0) -> bits 1 + 8; red has the most contrast.
    call check(glyph(1) == BRAILLE_BASE + 9, "cell (0,0) braille dots")
    call check(fg(1) == red, "cell (0,0) dominant colour")
    call check(glyph(2) == BRAILLE_BASE + 9 .and. fg(2) == green, "cell (1,0)")
    call check(glyph(3) == 32 .and. fg(3) == 0, "empty cell is a space")
    call check(glyph(4) == BRAILLE_BASE + 128 .and. fg(4) == red, "cell (1,1) dot 8")
    ! The same canvas at a pixel resolution (kitty path) puts the points at
    ! the same relative places: 10x20 pixel cells.
    call raster_resize(r, 20, 40)
    call raster_canvas(r, store, frame, frame%nodes(1), tui_canvas_map(0, 0, 10, 20))
    call check(r%rgb(2 + 2 * 20 + 1) == red, "pixel raster: first point")
    call check(r%rgb(17 + 37 * 20 + 1) == red, "pixel raster: second point")
end subroutine test_braille_canvas

subroutine test_line_clipping()
    type(raster_t) :: r, top
    integer(int32) :: white

    white = rgb_pack(255, 255, 255)
    call raster_resize(r, 4, 8)
    call raster_clear(r, 0_int32)
    call raster_line(r, -100.0, 1.5, 100.0, 1.5, white, 255, white, 255, 1.0, 0, 8)
    call check(all(r%rgb(5:8) == white) .and. count(r%rgb(1:32) /= 0) == 4, &
        "long horizontal line clipped to one row")
    call raster_clear(r, 0_int32)
    call raster_line(r, -5.0, -5.0, -1.0, 20.0, white, 255, white, 255, 1.0, 0, 8)
    call raster_line(r, 1.0e30, 0.0, 2.0, 2.0, white, 255, white, 255, 1.0, 0, 8)
    call check(count(r%rgb(1:32) /= 0) == 0, "outside and non-finite lines skipped")
    ! A diagonal through the raster, drawn whole and in two bands.
    call raster_clear(r, 0_int32)
    call raster_line(r, -2.0, -4.0, 6.0, 12.0, white, 255, white, 255, 1.0, 0, 8)
    call raster_resize(top, 4, 8)
    call raster_clear(top, 0_int32)
    call raster_line(top, -2.0, -4.0, 6.0, 12.0, white, 255, white, 255, 1.0, 0, 4)
    call raster_line(top, -2.0, -4.0, 6.0, 12.0, white, 255, white, 255, 1.0, 4, 8)
    call check(all(r%rgb(1:32) == top%rgb(1:32)), "banded drawing equals whole")
    call check_band_invariance()
    call check(count(r%rgb(1:32) /= 0) == 8, "diagonal: one pixel per row")
    call check(r%rgb(1) == white .and. r%rgb(4 + 7 * 4) == white, &
        "diagonal corners")
end subroutine test_line_clipping

subroutine check_band_invariance()
    !! Shallow and steep lines with alpha and colour gradients, drawn whole and
    !! in uneven bands (as threads do), give identical rasters.
    type(raster_t) :: whole, banded
    integer, parameter :: BANDS(0:4) = [0, 3, 11, 12, 40]
    integer :: k, b
    real :: xa, ya, xb, yb

    call raster_resize(whole, 37, 40)
    call raster_resize(banded, 37, 40)
    call raster_clear(whole, rgb_pack(17, 19, 25))
    call raster_clear(banded, rgb_pack(17, 19, 25))
    do k = 1, 25
        xa = -5.0 + 1.7 * k
        ya = 2.3 * mod(k * 7, 19) - 3.0
        xb = 40.0 - 1.3 * k
        yb = 41.0 - 1.9 * mod(k * 5, 23)
        call raster_line(whole, xa, ya, xb, yb, rgb_pack(250, 10 * k, 30), 60, &
            rgb_pack(20, 200, 9 * k), 200, 1.0, 0, 40)
        do b = 1, 4
            call raster_line(banded, xa, ya, xb, yb, rgb_pack(250, 10 * k, 30), 60, &
                rgb_pack(20, 200, 9 * k), 200, 1.0, BANDS(b - 1), BANDS(b))
        end do
    end do
    call check(all(whole%rgb(1:37 * 40) == banded%rgb(1:37 * 40)), &
        "blended lines: bands equal the whole raster")
    call check(count(whole%rgb(1:37 * 40) /= rgb_pack(17, 19, 25)) > 300, &
        "blended lines drawn")
end subroutine check_band_invariance

subroutine test_disc_edges()
    type(raster_t) :: r
    integer(int32) :: c
    integer :: i

    c = rgb_pack(10, 200, 30)
    call raster_resize(r, 4, 8)
    call raster_clear(r, 0_int32)
    ! Centre left of the raster: only the pixels of column 0 inside the disc.
    call raster_disc(r, -0.2, 3.5, 1.0, 1.0, c, 255, 0, 8)
    call check(r%rgb(1 + 3 * 4) == c .and. count(r%rgb(1:32) /= 0) == 1, &
        "disc clipped at the left edge")
    call raster_clear(r, 0_int32)
    call raster_disc(r, 3.9, 7.9, 0.1, 0.1, c, 255, 0, 8)
    call check(r%rgb(32) == c .and. count(r%rgb(1:32) /= 0) == 1, &
        "tiny disc at the corner is one pixel")
    call raster_clear(r, 0_int32)
    call raster_disc(r, 2.0, 4.0, 1.5, 3.0, c, 255, 0, 8)
    call check(count(r%rgb(1:32) == c) == 12, "elliptic disc pixel count")
    ! Rings: a narrow ellipse has no pixel centre inside its hole (inner radii
    ! 0.5 x 2) and stays filled; a wide disc keeps its rim only.
    call raster_clear(r, 0_int32)
    call raster_disc(r, 2.0, 4.0, 1.5, 3.0, c, 255, 0, 8, ring=1.0)
    call check(count(r%rgb(1:32) == c) == 12, "narrow ellipse stays filled")
    call raster_resize(r, 16, 16)
    call raster_clear(r, 0_int32)
    call raster_disc(r, 8.0, 8.0, 6.0, 6.0, c, 255, 0, 16)
    i = count(r%rgb(1:256) == c)
    call raster_clear(r, 0_int32)
    call raster_disc(r, 8.0, 8.0, 6.0, 6.0, c, 255, 0, 16, ring=1.0)
    call check(r%rgb(8 + 8 * 16 + 1) == 0 .and. r%rgb(2 + 8 * 16 + 1) == c .and. &
        count(r%rgb(1:256) == c) < i, "ring: hollow centre, filled rim")
    call raster_resize(r, 4, 8)
    call raster_clear(r, 0_int32)
    call raster_disc(r, 2.0, 50.0, 1.5, 1.5, c, 255, 0, 8)
    call check(count(r%rgb(1:32) /= 0) == 0, "disc below the raster")
end subroutine test_disc_edges

subroutine test_colours()
    integer(int32) :: grey

    grey = rgb_blend(0_int32, rgb_pack(255, 255, 255), 128)
    call check(grey == rgb_pack(128, 128, 128), "half alpha blend")
    call check(rgb_blend(rgb_pack(1, 2, 3), rgb_pack(9, 9, 9), 0) == &
        rgb_pack(1, 2, 3), "zero alpha keeps destination")
    call check(rgb_to_xterm256(rgb_pack(255, 0, 0)) == 196, "xterm red")
    call check(rgb_to_xterm256(0_int32) == 16, "xterm black")
    call check(rgb_to_xterm256(rgb_pack(128, 128, 128)) == 244, "xterm grey")
    call check(rgb_to_xterm256(rgb_pack(95, 135, 175)) == 67, "xterm cube")
    ! Faint colours are brightened, opaque ones are unchanged.
    call check(rgb_contrast(rgb_boost(rgb_pack(25, 0, 0), 0_int32), 0_int32) == 50, &
        "boost of a faint colour is at most double")
    call check(rgb_contrast(rgb_boost(rgb_pack(0, 160, 0), 0_int32), 0_int32) == 202, &
        "boost of a medium colour")
    call check(rgb_boost(rgb_pack(255, 0, 0), 0_int32) == rgb_pack(255, 0, 0), &
        "boost keeps full colours")
end subroutine test_colours

subroutine test_kitty_round_trip()
    integer, parameter :: W = 50, H = 40
    type(kitty_encoder_t) :: enc
    integer(int32) :: rgb(W * H)
    integer(int8), allocatable :: expected(:), packed(:), plain(:)
    character(len=:), allocatable :: payload, s
    integer :: i, x, y, p, q, chunks, np
    logical :: last_seen, sizes_ok

    do y = 0, H - 1
        do x = 0, W - 1
            rgb(1 + x + y * W) = rgb_pack(17, 19, 25)
            if (mod(x * 7 + y * 3, 11) == 0) rgb(1 + x + y * W) = &
                rgb_pack(mod(x * 5, 256), mod(y * 9, 256), 200)
            if (x == y) rgb(1 + x + y * W) = rgb_pack(255, 255, 255)
        end do
    end do
    allocate(expected(3 * W * H))
    do i = 1, W * H
        expected(3 * i - 2) = byte(iand(ishft(rgb(i), -16), 255_int32))
        expected(3 * i - 1) = byte(iand(ishft(rgb(i), -8), 255_int32))
        expected(3 * i) = byte(iand(rgb(i), 255_int32))
    end do
    call kitty_encode_image(enc, rgb, W, H, 7001, 5, 2)
    s = enc%out(1:enc%out_len)
    call check(index(s, achar(27) // "_Ga=T,q=2,f=24,o=z,s=50,v=40,i=7001,p=1," // &
        "C=1,z=-1,c=5,r=2,m=") == 1, "kitty header")
    ! Collect chunk payloads; every chunk is framed and at most 4096 bytes.
    payload = ""
    chunks = 0
    sizes_ok = .true.
    last_seen = .false.
    p = 1
    do while (p <= len(s))
        q = index(s(p:), ";")
        i = index(s(p:), achar(27) // "\")
        if (q == 0 .or. i == 0) exit
        if (i - q - 1 > KITTY_CHUNK) sizes_ok = .false.
        last_seen = s(p + q - 4:p + q - 2) == "m=0"
        payload = payload // s(p + q:p + i - 2)
        chunks = chunks + 1
        p = p + i + 1
    end do
    call check(p == len(s) + 1, "chunks cover the whole output")
    call check(sizes_ok .and. last_seen, "chunk sizes and final m=0")
    call base64_decode(payload, packed)
    call inflate(packed, plain, np)
    call check(np == 3 * W * H, "inflated size")
    if (np == 3 * W * H) call check(all(plain(1:np) == expected), &
        "inflated pixels equal the raster")
    call check(adler_ok(packed, plain(1:max(np, 1)), np), "adler-32 trailer")
    ! A large uniform image compresses to a few bytes per row.
    call kitty_encode_image(enc, [(rgb_pack(17, 19, 25), i = 1, 400 * 300)], 400, &
        300, 1, 40, 15)
    call check(enc%zlib_len < 300 * 40, "uniform image compresses")
end subroutine test_kitty_round_trip

pure integer(int8) function byte(v)
    integer(int32), intent(in) :: v
    if (v > 127) then
        byte = int(v - 256, int8)
    else
        byte = int(v, int8)
    end if
end function byte

subroutine base64_decode(s, out)
    character(*), intent(in) :: s
    integer(int8), allocatable, intent(out) :: out(:)
    character(len=*), parameter :: A = &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    integer :: i, n, v, k, pad, j

    pad = 0
    if (len(s) > 0) then
        if (s(len(s):len(s)) == "=") pad = 1
        if (len(s) > 1) then
            if (s(len(s) - 1:len(s) - 1) == "=") pad = 2
        end if
    end if
    n = 3 * (len(s) / 4) - pad
    allocate(out(n))
    j = 0
    do i = 1, len(s), 4
        v = 0
        do k = 0, 3
            v = 64 * v + max(0, index(A, s(i + k:i + k)) - 1)
        end do
        do k = 2, 0, -1
            if (j + 3 - k > n) cycle
            out(j + 3 - k) = byte(int(iand(ishft(v, -8 * k), 255), int32))
        end do
        j = j + 3
    end do
end subroutine base64_decode

integer function bits(z, pos, n) result(v)
    !! n bits, least significant first, from bit position pos (0-based).
    integer(int8), intent(in) :: z(:)
    integer, intent(inout) :: pos
    integer, intent(in) :: n
    integer :: k, b

    v = 0
    do k = 0, n - 1
        b = iand(int(z(pos / 8 + 1)), 255)
        if (btest(b, mod(pos, 8))) v = ibset(v, k)
        pos = pos + 1
    end do
end function bits

subroutine inflate(z, out, n)
    !! Decoder for zlib streams of stored and fixed-Huffman blocks.
    integer(int8), intent(in) :: z(:)
    integer(int8), allocatable, intent(out) :: out(:)
    integer, intent(out) :: n
    integer, parameter :: LB(0:28) = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, &
        23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    integer, parameter :: LE(0:28) = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, &
        2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    integer, parameter :: DB(0:29) = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, &
        97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, &
        8193, 12289, 16385, 24577]
    integer, parameter :: DE(0:29) = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, &
        6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    integer :: pos, final, btype, code, length, sym, d, dist, k, nb, i

    allocate(out(1000000))
    n = 0
    if (mod(256 * iand(int(z(1)), 255) + iand(int(z(2)), 255), 31) /= 0) return
    pos = 16
    do
        final = bits(z, pos, 1)
        btype = bits(z, pos, 2)
        if (btype == 0) then
            pos = 8 * ((pos + 7) / 8)
            length = bits(z, pos, 16)
            k = bits(z, pos, 16)
            do i = 1, length
                n = n + 1
                out(n) = byte(int(bits(z, pos, 8), int32))
            end do
        else if (btype == 1) then
            do
                code = 0
                sym = -1
                do nb = 1, 9
                    code = 2 * code + bits(z, pos, 1)
                    if (nb == 7 .and. code <= 23) sym = 256 + code
                    if (nb == 8 .and. code >= 48 .and. code <= 191) sym = code - 48
                    if (nb == 8 .and. code >= 192 .and. code <= 199) &
                        sym = 280 + code - 192
                    if (nb == 9 .and. code >= 400) sym = 144 + code - 400
                    if (sym >= 0) exit
                end do
                if (sym < 0) return
                if (sym < 256) then
                    n = n + 1
                    out(n) = byte(int(sym, int32))
                else if (sym == 256) then
                    exit
                else
                    length = LB(sym - 257) + bits(z, pos, LE(sym - 257))
                    d = 0
                    do nb = 1, 5
                        d = 2 * d + bits(z, pos, 1)
                    end do
                    dist = DB(d) + bits(z, pos, DE(d))
                    do i = 1, length
                        out(n + 1) = out(n + 1 - dist)
                        n = n + 1
                    end do
                end if
            end do
        else
            return
        end if
        if (final == 1) exit
    end do
end subroutine inflate

logical function adler_ok(z, plain, n)
    integer(int8), intent(in) :: z(:), plain(:)
    integer, intent(in) :: n
    integer :: a, b, i, m, stored

    a = 1
    b = 0
    do i = 1, n
        a = mod(a + iand(int(plain(i)), 255), 65521)
        b = mod(b + a, 65521)
    end do
    m = size(z)
    stored = 0
    do i = m - 3, m
        stored = 256 * stored + iand(int(z(i)), 255)
    end do
    adler_ok = stored == ior(ishft(b, 16), a)
end function adler_ok

subroutine test_replies()
    character(len=*), parameter :: E = achar(27)
    type(tui_replies_t) :: r

    r = tui_parse_replies(E // "_Gi=31;OK" // E // "\" // E // "[6;21;10t" // E // &
        "[?1016;2$y" // E // "P1$r0;38:2::1:2:3m" // E // "\" // E // "[?62;22;52c")
    call check(r%kitty_graphics .and. r%truecolor .and. r%pixel_mouse .and. &
        r%device_attributes, "kitty terminal replies")
    call check(r%cell_px_w == 10 .and. r%cell_px_h == 21, "cell size reply")
    r = tui_parse_replies(E // "[?1016;0$y" // E // "P0$r" // E // "\" // E // &
        "[?1;2c")
    call check(.not. (r%kitty_graphics .or. r%truecolor .or. r%pixel_mouse) .and. &
        r%device_attributes .and. r%cell_px_w == 0, "plain terminal replies")
    r = tui_parse_replies(E // "P1+r524742=383A383A38" // E // "\" // E // "[?65;4c")
    call check(r%truecolor .and. .not. r%kitty_graphics, "XTGETTCAP RGB reply")
    r = tui_parse_replies(E // "P0+r524742" // E // "\" // E // "[?65;4c")
    call check(.not. r%truecolor, "XTGETTCAP without RGB")
    r = tui_parse_replies("")
    call check(.not. r%device_attributes, "no reply")
end subroutine test_replies

subroutine test_pointer_mapping()
    !! A click on the cell holding a braille dot maps back to that dot's world
    !! position within half a cell; pixel reports are finer.
    type(canvas_view_t) :: view
    type(raster_map_t) :: map
    real :: lx, ly, wx, wy, nx, ny, dotx, doty

    call tui_cell_to_logical(3, 2, lx, ly)
    call check(abs(lx - 28.0) < 1.0e-6 .and. abs(ly - 40.0) < 1.0e-6, &
        "cell centre in logical units")
    call tui_pixel_to_logical(15, 33, 10, 20, lx, ly)
    call check(abs(lx - 12.4) < 1.0e-5 .and. abs(ly - 26.8) < 1.0e-5, &
        "pixel position in logical units")
    ! Canvas node at cell (5, 1), view zoom 2, pan (-10, 4); a world point at
    ! (30, 20) lies at frame (40 + 50, 16 + 44) = (90, 60): braille dot
    ! (90 - 40) / 4 = 12.5 -> 12, (60 - 16) / 4 = 11 -> cell (5 + 6, 1 + 2).
    view = canvas_view_t(zoom=2.0, pan_x=-10.0, pan_y=4.0)
    map = tui_canvas_map(5, 1, 2, 4)
    dotx = (40.0 + 30.0 * 2.0 - 10.0 - map%origin_x) * map%scale_x
    doty = (16.0 + 20.0 * 2.0 + 4.0 - map%origin_y) * map%scale_y
    call check(int(dotx) == 12 .and. int(doty) == 11, "world point to braille dot")
    call tui_cell_to_logical(5 + int(dotx) / 2, 1 + int(doty) / 4, lx, ly)
    call canvas_to_world(view, lx - 40.0, ly - 16.0, wx, wy)
    nx = abs(wx - 30.0) * view%zoom
    ny = abs(wy - 20.0) * view%zoom
    call check(nx <= 0.5 * CELL_W_DP .and. ny <= 0.5 * CELL_H_DP, &
        "clicked cell maps back within half a cell")
end subroutine test_pointer_mapping

end program test_tui_canvas
