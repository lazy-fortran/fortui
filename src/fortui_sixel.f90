module fortui_sixel
    !! Sixel images (DEC VT340 graphics, as xterm, foot and tmux speak them):
    !! the decoder turns the data of a DCS q string into pixels, the encoder
    !! turns pixels into such a string for terminals without the kitty protocol.
    use iso_fortran_env, only: int32
    implicit none
    private

    public :: sixel_decode, sixel_encode

    ! VT340 default colours of registers 0..15 (percent RGB).
    integer, parameter :: VT340(3, 0:15) = reshape([0, 0, 0, 20, 20, 80, 80, 13, 13, &
        20, 80, 20, 80, 20, 80, 20, 80, 80, 80, 80, 20, 53, 53, 53, 26, 26, 26, 33, 33, 60, &
        60, 26, 26, 33, 60, 33, 60, 33, 60, 33, 60, 60, 60, 60, 33, 80, 80, 80], [3, 16])

contains

    subroutine sixel_decode(params, data, rgba, ok)
        !! `params` are the DCS parameters before "q" (P2 = 1: unset pixels stay
        !! transparent), `data` what follows it up to the string terminator.
        !! The image has the raster size when one is given, else the painted area.
        character(*), intent(in) :: params, data
        integer(int32), allocatable, intent(out) :: rgba(:, :)
        logical, intent(out) :: ok
        integer(int32) :: palette(0:255), colour, background
        integer(int32), allocatable :: grown(:, :)
        integer :: pos, x, y, w, h, maxx, maxy, reg, k, bit, rep, c, nums(5), nn, p2

        ok = .false.
        do k = 0, 255
            if (k <= 15) then
                palette(k) = pct(VT340(1, k), VT340(2, k), VT340(3, k))
            else
                palette(k) = pct(0, 0, 0)
            end if
        end do
        p2 = 0
        call numbers(params, 1, nums, nn, k)
        if (nn >= 2) p2 = nums(2)
        background = palette(0)
        if (p2 == 1) background = 0
        allocate(rgba(256, 256))
        rgba = background
        x = 0
        y = 0
        maxx = 0
        maxy = 0
        w = 0
        h = 0
        reg = 0
        colour = palette(0)
        pos = 1
        do while (pos <= len(data))
            c = iachar(data(pos:pos))
            select case (c)
            case (63:126)
                call paint(c - 63, 1)
                pos = pos + 1
            case (33) ! '!' repeat
                call numbers(data, pos + 1, nums, nn, pos)
                rep = 1
                if (nn >= 1) rep = max(1, nums(1))
                if (pos <= len(data)) then
                    c = iachar(data(pos:pos))
                    if (c >= 63 .and. c <= 126) call paint(c - 63, rep)
                    pos = pos + 1
                end if
            case (35) ! '#' colour
                call numbers(data, pos + 1, nums, nn, pos)
                if (nn >= 1) then
                    reg = modulo(nums(1), 256)
                    if (nn >= 5) then
                        if (nums(2) == 2) then
                            palette(reg) = pct(nums(3), nums(4), nums(5))
                        else if (nums(2) == 1) then
                            palette(reg) = hls(nums(3), nums(4), nums(5))
                        end if
                    end if
                    colour = palette(reg)
                end if
            case (34) ! '"' raster attributes Pan; Pad; Ph; Pv
                call numbers(data, pos + 1, nums, nn, pos)
                if (nn >= 4) then
                    w = max(0, nums(3))
                    h = max(0, nums(4))
                    if (w > 0 .and. h > 0) call ensure(w, h)
                end if
            case (36) ! '$' carriage return
                x = 0
                pos = pos + 1
            case (45) ! '-' next sixel row
                x = 0
                y = y + 6
                pos = pos + 1
            case default
                pos = pos + 1
            end select
        end do
        if (w <= 0) w = maxx
        if (h <= 0) h = maxy
        w = max(1, min(w, size(rgba, 1)))
        h = max(1, min(h, size(rgba, 2)))
        grown = rgba(1:w, 1:h)
        call move_alloc(grown, rgba)
        ok = maxx > 0
    contains
        subroutine paint(sixel, count)
            integer, intent(in) :: sixel, count
            integer :: i
            if (x + count > 10000 .or. y + 6 > 10000) return
            call ensure(x + count, y + 6)
            do bit = 0, 5
                if (btest(sixel, bit)) then
                    do i = 1, count
                        rgba(x + i, y + bit + 1) = colour
                    end do
                    maxy = max(maxy, y + bit + 1)
                end if
            end do
            x = x + count
            maxx = max(maxx, x)
        end subroutine paint
        subroutine ensure(nw, nh)
            integer, intent(in) :: nw, nh
            integer :: aw, ah
            if (nw <= size(rgba, 1) .and. nh <= size(rgba, 2)) return
            aw = max(size(rgba, 1), nw)
            ah = max(size(rgba, 2), nh)
            if (aw > size(rgba, 1)) aw = max(aw, 2 * size(rgba, 1))
            if (ah > size(rgba, 2)) ah = max(ah, 2 * size(rgba, 2))
            allocate(grown(aw, ah))
            grown = background
            grown(1:size(rgba, 1), 1:size(rgba, 2)) = rgba
            call move_alloc(grown, rgba)
        end subroutine ensure
    end subroutine sixel_decode

    subroutine numbers(s, start, nums, n, next)
        !! Semicolon-separated decimal numbers from s(start:); `next` is the
        !! position after them.
        character(*), intent(in) :: s
        integer, intent(in) :: start
        integer, intent(out) :: nums(:), n, next
        integer :: pos, c, v
        logical :: digits
        n = 0
        nums = 0
        pos = start
        v = 0
        digits = .false.
        do while (pos <= len(s))
            c = iachar(s(pos:pos))
            if (c >= 48 .and. c <= 57) then
                v = min(100000, 10 * v + c - 48)
                digits = .true.
            else if (c == 59) then
                if (n < size(nums)) n = n + 1
                nums(min(n, size(nums))) = v
                v = 0
                digits = .false.
            else
                exit
            end if
            pos = pos + 1
        end do
        if (digits .or. n > 0) then
            if (n < size(nums)) n = n + 1
            nums(min(n, size(nums))) = v
        end if
        next = pos
    end subroutine numbers

    pure integer(int32) function pct(r, g, b) result(c)
        integer, intent(in) :: r, g, b
        c = pack4(nint(2.55 * min(100, r)), nint(2.55 * min(100, g)), nint(2.55 * min(100, b)))
    end function pct

    pure integer(int32) function hls(hue, l, s) result(c)
        !! DEC HLS (hue 0 = blue, lightness and saturation in percent).
        integer, intent(in) :: hue, l, s
        real :: hh, ll, ss, q, p, rgb(3)
        integer :: k
        hh = modulo(real(hue) + 240.0, 360.0) / 360.0
        ll = real(min(100, l)) / 100.0
        ss = real(min(100, s)) / 100.0
        if (ss == 0.0) then
            rgb = ll
        else
            if (ll < 0.5) then
                q = ll * (1.0 + ss)
            else
                q = ll + ss - ll * ss
            end if
            p = 2.0 * ll - q
            do k = 1, 3
                rgb(k) = channel(p, q, hh + real(2 - k) / 3.0)
            end do
        end if
        c = pack4(nint(255 * rgb(1)), nint(255 * rgb(2)), nint(255 * rgb(3)))
    contains
        pure real function channel(p, q, t0)
            real, intent(in) :: p, q, t0
            real :: t
            t = modulo(t0, 1.0)
            if (t < 1.0 / 6.0) then
                channel = p + (q - p) * 6.0 * t
            else if (t < 0.5) then
                channel = q
            else if (t < 2.0 / 3.0) then
                channel = p + (q - p) * (2.0 / 3.0 - t) * 6.0
            else
                channel = p
            end if
        end function channel
    end function hls

    pure integer(int32) function pack4(r, g, b) result(c)
        integer, intent(in) :: r, g, b
        c = int(iand(r, 255), int32) + ishft(int(iand(g, 255), int32), 8) + &
            ishft(int(iand(b, 255), int32), 16) + ishft(-1_int32, 24)
    end function pack4

    subroutine sixel_encode(rgb, width, height, out)
        !! A complete sixel string (DCS ... ST) of an RGB raster rgb(width *
        !! height, row by row, 0x00RRGGBB). Colours are reduced to a fixed
        !! 6x7x6 cube of 252 registers, which needs no palette search.
        integer(int32), intent(in) :: rgb(:)
        integer, intent(in) :: width, height
        character(len=:), allocatable, intent(out) :: out
        character(len=:), allocatable :: buf
        integer :: n, band, x, y, k, reg, r, g, b, prev, run, six, b0
        integer, allocatable :: idx(:)
        logical :: used(0:251)
        real :: d
        integer, parameter :: BAYER(0:3, 0:3) = reshape([0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, &
            9, 15, 7, 13, 5], [4, 4])
        character(len=32) :: num

        allocate(idx(width * height))
        ! Ordered dithering (4 x 4 Bayer) hides the steps of the fixed palette.
        do k = 1, width * height
            x = modulo(k - 1, width)
            y = (k - 1) / width
            d = real(BAYER(modulo(x, 4), modulo(y, 4))) / 16.0 - 0.46875
            r = level(iand(ishft(rgb(k), -16), 255), 5, d)
            g = level(iand(ishft(rgb(k), -8), 255), 6, d)
            b = level(iand(rgb(k), 255), 5, d)
            idx(k) = r * 42 + g * 6 + b
        end do
        allocate(character(len=max(4096, width * height)) :: buf)
        n = 0
        call add(achar(27) // "P0;1;0q")
        write(num, '(a,i0,a,i0)') '"1;1;', width, ';', height
        call add(trim(num))
        used = .false.
        do k = 1, width * height
            used(idx(k)) = .true.
        end do
        do reg = 0, 251
            if (.not. used(reg)) cycle
            write(num, '(a,i0,a,i0,a,i0,a,i0)') '#', reg, ';2;', (reg / 42) * 20, ';', &
                nint(real(modulo(reg / 6, 7)) * 100.0 / 6.0), ';', modulo(reg, 6) * 20
            call add(trim(num))
        end do
        do band = 0, (height - 1) / 6
            b0 = band * 6
            used = .false.
            do k = b0 * width + 1, min(height, b0 + 6) * width
                used(idx(k)) = .true.
            end do
            do reg = 0, 251
                if (.not. used(reg)) cycle
                write(num, '(a,i0)') '#', reg
                call add(trim(num))
                prev = -1
                run = 0
                do x = 1, width
                    six = 0
                    do y = 0, 5
                        if (b0 + y >= height) exit
                        if (idx((b0 + y) * width + x) == reg) six = ibset(six, y)
                    end do
                    if (six == prev) then
                        run = run + 1
                    else
                        call flush_run()
                        prev = six
                        run = 1
                    end if
                end do
                call flush_run()
                call add("$")
            end do
            call add("-")
        end do
        call add(achar(27) // "\")
        out = buf(1:n)
    contains
        pure integer function level(v, top, offset)
            !! Palette step 0..top of channel value v, moved by offset steps.
            integer, intent(in) :: v, top
            real, intent(in) :: offset
            level = max(0, min(top, nint(real(v) * real(top) / 255.0 + offset)))
        end function level
        subroutine flush_run()
            if (run <= 0) return
            if (run > 3) then
                write(num, '(a,i0)') '!', run
                call add(trim(num) // achar(63 + prev))
            else
                call add(repeat(achar(63 + prev), run))
            end if
            run = 0
        end subroutine flush_run
        subroutine add(s)
            character(*), intent(in) :: s
            character(len=:), allocatable :: bigger
            if (n + len(s) > len(buf)) then
                allocate(character(len=2 * (n + len(s))) :: bigger)
                bigger(1:n) = buf(1:n)
                call move_alloc(bigger, buf)
            end if
            buf(n + 1:n + len(s)) = s
            n = n + len(s)
        end subroutine add
    end subroutine sixel_encode

end module fortui_sixel
