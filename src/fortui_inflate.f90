module fortui_inflate
    !! Decoders for image payloads that terminals receive: DEFLATE and zlib
    !! streams (RFC 1950/1951), PNG images and base64, without a C library so
    !! that every target (including WebAssembly) has them.
    use iso_fortran_env, only: int8, int32
    implicit none
    private

    public :: inflate, zlib_decompress, png_decode, base64_decode

    ! Order of the code length code lengths (RFC 1951, 3.2.7).
    integer, parameter :: CL_ORDER(19) = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, &
        2, 14, 1, 15]
    integer, parameter :: LEN_BASE(29) = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, &
        31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    integer, parameter :: LEN_EXTRA(29) = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, &
        3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    integer, parameter :: DIST_BASE(30) = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, &
        129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, &
        16385, 24577]
    integer, parameter :: DIST_EXTRA(30) = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, &
        7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    type :: huffman_t
        !! Canonical code: count(len) codes of each length, symbols in code order.
        integer :: count(0:15) = 0
        integer, allocatable :: symbol(:)
    end type huffman_t

    type :: stream_t
        integer(int8), pointer :: src(:) => null()
        integer :: pos = 1, bitbuf = 0, bitcnt = 0
        logical :: bad = .false.
        integer(int8), allocatable :: out(:)
        integer :: n = 0
    end type stream_t

contains

    subroutine inflate(src, out, n, ok)
        !! Raw DEFLATE data in src into out(1:n).
        integer(int8), intent(in), target :: src(:)
        integer(int8), allocatable, intent(out) :: out(:)
        integer, intent(out) :: n
        logical, intent(out) :: ok
        type(stream_t) :: s
        integer :: last, kind

        s%src => src
        allocate(s%out(max(1024, 4 * size(src))))
        do
            last = bits(s, 1)
            kind = bits(s, 2)
            select case (kind)
            case (0); call stored(s)
            case (1); call fixed(s)
            case (2); call dynamic(s)
            case default; s%bad = .true.
            end select
            if (s%bad .or. last == 1) exit
        end do
        ok = .not. s%bad
        n = s%n
        call move_alloc(s%out, out)
    end subroutine inflate

    subroutine zlib_decompress(src, out, n, ok)
        !! A zlib stream (two header bytes, DEFLATE data, Adler-32) into out(1:n).
        integer(int8), intent(in) :: src(:)
        integer(int8), allocatable, intent(out) :: out(:)
        integer, intent(out) :: n
        logical, intent(out) :: ok
        integer :: cmf, flg

        ok = .false.
        n = 0
        if (size(src) < 6) then
            allocate(out(0))
            return
        end if
        cmf = byte(src(1))
        flg = byte(src(2))
        if (iand(cmf, 15) /= 8 .or. modulo(cmf * 256 + flg, 31) /= 0 .or. &
            iand(flg, 32) /= 0) then
            allocate(out(0))
            return
        end if
        call inflate(src(3:), out, n, ok)
    end subroutine zlib_decompress

    ! --- bit input -------------------------------------------------------------

    integer function bits(s, need) result(v)
        type(stream_t), intent(inout) :: s
        integer, intent(in) :: need
        do while (s%bitcnt < need)
            if (s%pos > size(s%src)) then
                s%bad = .true.
                v = 0
                return
            end if
            s%bitbuf = ior(s%bitbuf, ishft(byte(s%src(s%pos)), s%bitcnt))
            s%pos = s%pos + 1
            s%bitcnt = s%bitcnt + 8
        end do
        v = iand(s%bitbuf, ishft(1, need) - 1)
        s%bitbuf = ishft(s%bitbuf, -need)
        s%bitcnt = s%bitcnt - need
    end function bits

    subroutine put(s, b)
        type(stream_t), intent(inout) :: s
        integer(int8), intent(in) :: b
        integer(int8), allocatable :: grown(:)
        if (s%n == size(s%out)) then
            allocate(grown(2 * size(s%out)))
            grown(1:s%n) = s%out(1:s%n)
            call move_alloc(grown, s%out)
        end if
        s%n = s%n + 1
        s%out(s%n) = b
    end subroutine put

    ! --- blocks ----------------------------------------------------------------

    subroutine stored(s)
        type(stream_t), intent(inout) :: s
        integer :: length, k
        s%bitbuf = 0
        s%bitcnt = 0
        if (s%pos + 3 > size(s%src)) then
            s%bad = .true.
            return
        end if
        length = byte(s%src(s%pos)) + 256 * byte(s%src(s%pos + 1))
        s%pos = s%pos + 4
        if (s%pos + length - 1 > size(s%src)) then
            s%bad = .true.
            return
        end if
        do k = 0, length - 1
            call put(s, s%src(s%pos + k))
        end do
        s%pos = s%pos + length
    end subroutine stored

    subroutine fixed(s)
        type(stream_t), intent(inout) :: s
        type(huffman_t) :: lit, dist
        integer :: lengths(0:287), k
        lengths(0:143) = 8
        lengths(144:255) = 9
        lengths(256:279) = 7
        lengths(280:287) = 8
        call build(lit, lengths, 288)
        lengths(0:29) = 5
        call build(dist, lengths, 30)
        call codes(s, lit, dist)
        k = 0
    end subroutine fixed

    subroutine dynamic(s)
        type(stream_t), intent(inout) :: s
        type(huffman_t) :: lencode, lit, dist
        integer :: nlen, ndist, ncode, k, sym, rep, prev, lengths(0:319)

        nlen = bits(s, 5) + 257
        ndist = bits(s, 5) + 1
        ncode = bits(s, 4) + 4
        if (nlen > 286 .or. ndist > 30) then
            s%bad = .true.
            return
        end if
        lengths = 0
        do k = 1, ncode
            lengths(CL_ORDER(k)) = bits(s, 3)
        end do
        call build(lencode, lengths, 19)
        k = 0
        do while (k < nlen + ndist .and. .not. s%bad)
            sym = decode(s, lencode)
            if (sym < 16) then
                lengths(k) = sym
                k = k + 1
                cycle
            end if
            prev = 0
            select case (sym)
            case (16)
                if (k == 0) then
                    s%bad = .true.
                    return
                end if
                prev = lengths(k - 1)
                rep = 3 + bits(s, 2)
            case (17); rep = 3 + bits(s, 3)
            case default; rep = 11 + bits(s, 7)
            end select
            if (k + rep > nlen + ndist) then
                s%bad = .true.
                return
            end if
            lengths(k:k + rep - 1) = prev
            k = k + rep
        end do
        if (s%bad) return
        call build(lit, lengths(0:nlen - 1), nlen)
        call build(dist, lengths(nlen:nlen + ndist - 1), ndist)
        call codes(s, lit, dist)
    end subroutine dynamic

    subroutine codes(s, lit, dist)
        type(stream_t), intent(inout) :: s
        type(huffman_t), intent(in) :: lit, dist
        integer :: sym, length, d, k
        do
            sym = decode(s, lit)
            if (s%bad) return
            if (sym < 256) then
                call put(s, int(sym, int8))
            else if (sym == 256) then
                return
            else
                sym = sym - 257
                if (sym >= 29) then
                    s%bad = .true.
                    return
                end if
                length = LEN_BASE(sym + 1) + bits(s, LEN_EXTRA(sym + 1))
                sym = decode(s, dist)
                if (sym < 0 .or. sym >= 30) then
                    s%bad = .true.
                    return
                end if
                d = DIST_BASE(sym + 1) + bits(s, DIST_EXTRA(sym + 1))
                if (d > s%n) then
                    s%bad = .true.
                    return
                end if
                do k = 1, length
                    call put(s, s%out(s%n - d + 1))
                end do
            end if
        end do
    end subroutine codes

    subroutine build(h, lengths, n)
        type(huffman_t), intent(out) :: h
        integer, intent(in) :: lengths(0:), n
        integer :: offs(0:15), k, len
        h%count = 0
        do k = 0, n - 1
            h%count(lengths(k)) = h%count(lengths(k)) + 1
        end do
        offs(1) = 0
        do len = 1, 14
            offs(len + 1) = offs(len) + h%count(len)
        end do
        allocate(h%symbol(0:max(0, n - 1)))
        h%symbol = 0
        do k = 0, n - 1
            if (lengths(k) /= 0) then
                h%symbol(offs(lengths(k))) = k
                offs(lengths(k)) = offs(lengths(k)) + 1
            end if
        end do
    end subroutine build

    integer function decode(s, h) result(sym)
        type(stream_t), intent(inout) :: s
        type(huffman_t), intent(in) :: h
        integer :: code, first, index, len, cnt
        code = 0
        first = 0
        index = 0
        do len = 1, 15
            code = ior(code, bits(s, 1))
            if (s%bad) exit
            cnt = h%count(len)
            if (code - cnt < first) then
                sym = h%symbol(index + (code - first))
                return
            end if
            index = index + cnt
            first = ishft(first + cnt, 1)
            code = ishft(code, 1)
        end do
        s%bad = .true.
        sym = -1
    end function decode

    pure integer function byte(b)
        integer(int8), intent(in) :: b
        byte = iand(int(b), 255)
    end function byte

    ! --- PNG -------------------------------------------------------------------

    subroutine png_decode(src, rgba, ok)
        !! An 8-bit PNG (grey, grey+alpha, RGB, RGBA or palette, not interlaced)
        !! into rgba(width, height) packed like ui_rgba, row 1 at the top.
        integer(int8), intent(in) :: src(:)
        integer(int32), allocatable, intent(out) :: rgba(:, :)
        logical, intent(out) :: ok
        integer(int8), allocatable :: idat(:), raw(:)
        integer :: pos, length, w, h, depth, ctype, interlace, nraw, nidat, channels
        integer :: stride, x, y, filter, k, a, b, c, p, pa, pb, pc, v, i
        integer :: plte(3, 0:255), trns(0:255)
        character(len=4) :: tag
        integer(int8), allocatable :: grown(:)

        ok = .false.
        w = 0
        h = 0
        depth = 0
        ctype = 0
        interlace = 0
        plte = 0
        trns = 255
        allocate(idat(max(1024, size(src))))
        nidat = 0
        if (size(src) < 8) return
        if (byte(src(2)) /= 80 .or. byte(src(3)) /= 78 .or. byte(src(4)) /= 71) return
        pos = 9
        do while (pos + 7 <= size(src))
            length = be32(src, pos)
            tag = transfer(src(pos + 4:pos + 7), tag)
            if (length < 0 .or. pos + 11 + length > size(src)) return
            select case (tag)
            case ("IHDR")
                w = be32(src, pos + 8)
                h = be32(src, pos + 12)
                depth = byte(src(pos + 16))
                ctype = byte(src(pos + 17))
                interlace = byte(src(pos + 20))
            case ("PLTE")
                do k = 0, min(255, length / 3 - 1)
                    plte(:, k) = [(byte(src(pos + 8 + 3 * k + i)), i = 0, 2)]
                end do
            case ("tRNS")
                if (ctype == 3) then
                    do k = 0, min(255, length - 1)
                        trns(k) = byte(src(pos + 8 + k))
                    end do
                end if
            case ("IDAT")
                if (nidat + length > size(idat)) then
                    allocate(grown(2 * (nidat + length)))
                    grown(1:nidat) = idat(1:nidat)
                    call move_alloc(grown, idat)
                end if
                idat(nidat + 1:nidat + length) = src(pos + 8:pos + 7 + length)
                nidat = nidat + length
            case ("IEND")
                exit
            end select
            pos = pos + 12 + length
        end do
        if (w <= 0 .or. h <= 0 .or. depth /= 8 .or. interlace /= 0) return
        select case (ctype)
        case (0); channels = 1
        case (2); channels = 3
        case (3); channels = 1
        case (4); channels = 2
        case (6); channels = 4
        case default; return
        end select
        call zlib_decompress(idat(1:nidat), raw, nraw, ok)
        if (.not. ok) return
        ok = .false.
        stride = w * channels
        if (nraw < h * (stride + 1)) return
        allocate(rgba(w, h))
        do y = 0, h - 1
            filter = byte(raw(y * (stride + 1) + 1))
            do x = 0, stride - 1
                k = y * (stride + 1) + 2 + x
                a = 0
                b = 0
                c = 0
                if (x >= channels) a = byte(raw(k - channels))
                if (y > 0) b = byte(raw(k - stride - 1))
                if (x >= channels .and. y > 0) c = byte(raw(k - stride - 1 - channels))
                v = byte(raw(k))
                select case (filter)
                case (1); v = v + a
                case (2); v = v + b
                case (3); v = v + (a + b) / 2
                case (4)
                    p = a + b - c
                    pa = abs(p - a)
                    pb = abs(p - b)
                    pc = abs(p - c)
                    if (pa <= pb .and. pa <= pc) then
                        v = v + a
                    else if (pb <= pc) then
                        v = v + b
                    else
                        v = v + c
                    end if
                end select
                v = iand(v, 255)
                if (v > 127) v = v - 256
                raw(k) = int(v, int8)
            end do
            do x = 0, w - 1
                k = y * (stride + 1) + 2 + x * channels
                select case (ctype)
                case (0)
                    v = byte(raw(k))
                    rgba(x + 1, y + 1) = pack4(v, v, v, 255)
                case (2)
                    rgba(x + 1, y + 1) = pack4(byte(raw(k)), byte(raw(k + 1)), &
                        byte(raw(k + 2)), 255)
                case (3)
                    v = byte(raw(k))
                    rgba(x + 1, y + 1) = pack4(plte(1, v), plte(2, v), plte(3, v), trns(v))
                case (4)
                    v = byte(raw(k))
                    rgba(x + 1, y + 1) = pack4(v, v, v, byte(raw(k + 1)))
                case (6)
                    rgba(x + 1, y + 1) = pack4(byte(raw(k)), byte(raw(k + 1)), &
                        byte(raw(k + 2)), byte(raw(k + 3)))
                end select
            end do
        end do
        ok = .true.
    end subroutine png_decode

    pure integer function be32(src, pos)
        integer(int8), intent(in) :: src(:)
        integer, intent(in) :: pos
        be32 = ior(ior(ishft(byte(src(pos)), 24), ishft(byte(src(pos + 1)), 16)), &
            ior(ishft(byte(src(pos + 2)), 8), byte(src(pos + 3))))
    end function be32

    pure integer(int32) function pack4(r, g, b, a) result(c)
        !! ui_rgba packing (bytes R, G, B, A in memory).
        integer, intent(in) :: r, g, b, a
        integer :: top
        top = iand(a, 255)
        if (top > 127) top = top - 256
        c = int(iand(r, 255), int32) + ishft(int(iand(g, 255), int32), 8) + &
            ishft(int(iand(b, 255), int32), 16) + ishft(int(top, int32), 24)
    end function pack4

    ! --- base64 ----------------------------------------------------------------

    subroutine base64_decode(text, out, n)
        !! Standard base64 (padding optional, other characters skipped).
        character(*), intent(in) :: text
        integer(int8), allocatable, intent(out) :: out(:)
        integer, intent(out) :: n
        integer :: k, v, acc, nbits, c

        allocate(out(3 * (len(text) / 4) + 3))
        n = 0
        acc = 0
        nbits = 0
        do k = 1, len(text)
            c = iachar(text(k:k))
            select case (c)
            case (65:90); v = c - 65
            case (97:122); v = c - 71
            case (48:57); v = c + 4
            case (43); v = 62
            case (47); v = 63
            case default; cycle
            end select
            acc = ior(ishft(iand(acc, 65535), 6), v)
            nbits = nbits + 6
            if (nbits >= 8) then
                nbits = nbits - 8
                v = iand(ishft(acc, -nbits), 255)
                if (v > 127) v = v - 256
                n = n + 1
                out(n) = int(v, int8)
            end if
        end do
    end subroutine base64_decode

end module fortui_inflate
