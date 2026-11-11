module fortui_kitty
    !! Kitty terminal graphics protocol encoding (pure byte work, no terminal I/O).
    !!
    !! An RGB raster is packed as 24-bit pixels, compressed into a zlib stream
    !! (RFC 1950/1951: one fixed-Huffman block whose matches repeat the previous
    !! pixel or the pixel row above, which suits canvas images with large uniform
    !! areas), base64 encoded and split into escape-sequence chunks of at most
    !! 4096 payload bytes (`o=z`, `m=1` continuation). Image and placement ids let
    !! a new transmission replace the previous picture without flicker.
    !! Buffers are kept in `kitty_encoder_t` and grown only, so steady redraws
    !! allocate nothing.
    use iso_fortran_env, only: int8, int32, int64
    implicit none
    private

    integer, parameter, public :: KITTY_CHUNK = 4096
    character(len=*), parameter :: ESC = achar(27)
    character(len=*), parameter, public :: KITTY_QUERY = ESC // &
        "_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA" // ESC // "\"

    type, public :: kitty_encoder_t
        integer(int8), allocatable :: pixels(:)
        integer(int8), allocatable :: zlib(:)
        integer :: zlib_len = 0
        character(len=:), allocatable :: out
        integer :: out_len = 0
        ! bit writer state
        integer(int64) :: bitbuf = 0
        integer :: nbits = 0
    end type kitty_encoder_t

    public :: kitty_encode_image, kitty_delete, zlib_compress, base64_encode
    public :: base64_length

    character(len=64), parameter :: B64 = &
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    integer, parameter :: LEN_BASE(257:285) = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, &
        17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    integer, parameter :: LEN_EXTRA(257:285) = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, &
        2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    integer, parameter :: DIST_BASE(0:29) = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, &
        65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, &
        8193, 12289, 16385, 24577]
    integer, parameter :: DIST_EXTRA(0:29) = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, &
        5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

contains

    subroutine kitty_encode_image(enc, rgb, width, height, image_id, cols, rows)
        !! Commands transmitting `rgb` (0x00RRGGBB, row-major, width*height) as image
        !! `image_id`, displayed with placement 1 scaled to cols x rows cells at the
        !! cursor, below text (z=-1), without moving the cursor and without replies.
        !! The result is enc%out(1:enc%out_len).
        type(kitty_encoder_t), intent(inout) :: enc
        integer(int32), intent(in) :: rgb(:)
        integer, intent(in) :: width, height, image_id, cols, rows
        integer :: n, i, nb64, pos, chunk, more
        character(len=160) :: head

        n = width * height
        call grow_bytes(enc%pixels, 3 * n)
        !$omp parallel do schedule(static) if (n > 100000)
        do i = 1, n
            enc%pixels(3 * i - 2) = to_byte(int(iand(ishft(rgb(i), -16), 255_int32)))
            enc%pixels(3 * i - 1) = to_byte(int(iand(ishft(rgb(i), -8), 255_int32)))
            enc%pixels(3 * i) = to_byte(int(iand(rgb(i), 255_int32)))
        end do
        !$omp end parallel do
        call zlib_compress(enc, enc%pixels, 3 * n, 3 * width)
        nb64 = base64_length(enc%zlib_len)
        call grow_chars(enc%out, nb64 + (nb64 / KITTY_CHUNK + 1) * 32 + 200)
        enc%out_len = 0
        pos = 0
        write(head, '(a,i0,a,i0,a,i0,a,i0,a,i0)') ESC // "_Ga=T,q=2,f=24,o=z,s=", &
            width, ",v=", height, ",i=", image_id, ",p=1,C=1,z=-1,c=", cols, ",r=", rows
        ! Base64 directly into the output, then insert chunk framing by copying
        ! each chunk after its header (single pass over a scratch tail).
        call base64_encode(enc%zlib, enc%zlib_len, enc%out, len(enc%out) - nb64)
        do
            chunk = min(KITTY_CHUNK, nb64 - pos)
            more = merge(1, 0, pos + chunk < nb64)
            if (pos == 0) then
                call put(enc, trim(head) // ",m=" // achar(48 + more) // ";")
            else
                call put(enc, ESC // "_Gm=" // achar(48 + more) // ";")
            end if
            if (chunk > 0) then
                enc%out(enc%out_len + 1:enc%out_len + chunk) = &
                    enc%out(len(enc%out) - nb64 + pos + 1:len(enc%out) - nb64 + pos + chunk)
                enc%out_len = enc%out_len + chunk
            end if
            call put(enc, ESC // "\")
            pos = pos + chunk
            if (pos >= nb64) exit
        end do
    end subroutine kitty_encode_image

    function kitty_delete(image_id) result(s)
        !! Delete image `image_id` with its placements and data (no reply).
        integer, intent(in) :: image_id
        character(len=:), allocatable :: s
        character(len=48) :: buf
        write(buf, '(a,i0,a)') ESC // "_Ga=d,d=I,q=2,i=", image_id, ESC // "\"
        s = trim(buf)
    end function kitty_delete

    subroutine put(enc, s)
        type(kitty_encoder_t), intent(inout) :: enc
        character(*), intent(in) :: s
        enc%out(enc%out_len + 1:enc%out_len + len(s)) = s
        enc%out_len = enc%out_len + len(s)
    end subroutine put

    pure integer(int8) function to_byte(v) result(b)
        integer, intent(in) :: v
        if (v > 127) then
            b = int(v - 256, int8)
        else
            b = int(v, int8)
        end if
    end function to_byte

    pure integer function ubyte(b) result(v)
        integer(int8), intent(in) :: b
        v = iand(int(b), 255)
    end function ubyte

    subroutine grow_bytes(a, n)
        integer(int8), allocatable, intent(inout) :: a(:)
        integer, intent(in) :: n
        if (allocated(a)) then
            if (size(a) >= n) return
            deallocate(a)
        end if
        allocate(a(max(n, 1024)))
    end subroutine grow_bytes

    subroutine grow_chars(s, n)
        character(len=:), allocatable, intent(inout) :: s
        integer, intent(in) :: n
        if (allocated(s)) then
            if (len(s) >= n) return
            deallocate(s)
        end if
        allocate(character(len=max(n, 1024)) :: s)
    end subroutine grow_chars

    pure integer function base64_length(n) result(m)
        integer, intent(in) :: n
        m = 4 * ((n + 2) / 3)
    end function base64_length

    subroutine base64_encode(bytes, n, out, offset)
        !! Base64 of bytes(1:n) written to out(offset+1 : offset+base64_length(n)).
        integer(int8), intent(in) :: bytes(:)
        integer, intent(in) :: n, offset
        character(len=*), intent(inout) :: out
        integer :: i, j, v, b1, b2, b3, rest

        j = offset
        do i = 1, n - 2, 3
            v = ior(ior(ishft(ubyte(bytes(i)), 16), ishft(ubyte(bytes(i + 1)), 8)), &
                ubyte(bytes(i + 2)))
            out(j + 1:j + 1) = B64(ishft(v, -18) + 1:ishft(v, -18) + 1)
            out(j + 2:j + 2) = B64(iand(ishft(v, -12), 63) + 1:iand(ishft(v, -12), 63) + 1)
            out(j + 3:j + 3) = B64(iand(ishft(v, -6), 63) + 1:iand(ishft(v, -6), 63) + 1)
            out(j + 4:j + 4) = B64(iand(v, 63) + 1:iand(v, 63) + 1)
            j = j + 4
        end do
        rest = n - 3 * (n / 3)
        if (rest == 0) return
        b1 = ubyte(bytes(n - rest + 1))
        b2 = 0
        if (rest == 2) b2 = ubyte(bytes(n))
        b3 = 0
        v = ior(ior(ishft(b1, 16), ishft(b2, 8)), b3)
        out(j + 1:j + 1) = B64(ishft(v, -18) + 1:ishft(v, -18) + 1)
        out(j + 2:j + 2) = B64(iand(ishft(v, -12), 63) + 1:iand(ishft(v, -12), 63) + 1)
        if (rest == 2) then
            out(j + 3:j + 3) = B64(iand(ishft(v, -6), 63) + 1:iand(ishft(v, -6), 63) + 1)
        else
            out(j + 3:j + 3) = "="
        end if
        out(j + 4:j + 4) = "="
    end subroutine base64_encode

    ! --- zlib / deflate -------------------------------------------------------------

    subroutine zlib_compress(enc, data, n, stride)
        !! zlib stream of data(1:n) into enc%zlib(1:enc%zlib_len). Matches repeat the
        !! previous 3 bytes (one RGB pixel) or the bytes `stride` earlier (one row).
        type(kitty_encoder_t), intent(inout) :: enc
        integer(int8), intent(in) :: data(:)
        integer, intent(in) :: n, stride
        integer :: p, l3, lr, best, dist
        integer(int64) :: a, b
        integer :: k, kend

        ! Worst case: 9 bits per literal plus headers.
        call grow_bytes(enc%zlib, n + n / 8 + 64)
        enc%zlib_len = 0
        enc%bitbuf = 0
        enc%nbits = 0
        call put_byte(enc, 120) ! CMF: deflate, 32 KiB window
        call put_byte(enc, 1) ! FLG: no dictionary, check bits
        call put_bits(enc, 1, 1) ! BFINAL
        call put_bits(enc, 1, 2) ! BTYPE = fixed Huffman
        p = 1
        do while (p <= n)
            l3 = 0
            if (p > 3) l3 = match_length(data, n, p, 3)
            lr = 0
            if (stride > 3 .and. stride <= 32768 .and. p > stride .and. l3 < 258) &
                lr = match_length(data, n, p, stride)
            best = max(l3, lr)
            if (best >= 3) then
                dist = 3
                if (lr > l3) dist = stride
                call put_match(enc, best, dist)
                p = p + best
            else
                call put_literal(enc, ubyte(data(p)))
                p = p + 1
            end if
        end do
        call put_literal(enc, 256)
        if (enc%nbits > 0) call put_bits(enc, 0, 8 - enc%nbits)
        ! Adler-32 (big-endian) in blocks that cannot overflow.
        a = 1
        b = 0
        k = 1
        do while (k <= n)
            kend = min(n, k + 5551)
            do p = k, kend
                a = a + ubyte(data(p))
                b = b + a
            end do
            a = mod(a, 65521_int64)
            b = mod(b, 65521_int64)
            k = kend + 1
        end do
        call put_byte(enc, int(ishft(b, -8)))
        call put_byte(enc, int(iand(b, 255_int64)))
        call put_byte(enc, int(ishft(a, -8)))
        call put_byte(enc, int(iand(a, 255_int64)))
    end subroutine zlib_compress

    pure integer function match_length(data, n, p, dist) result(l)
        integer(int8), intent(in) :: data(:)
        integer, intent(in) :: n, p, dist
        integer :: lim

        lim = min(258, n - p + 1)
        l = 0
        do while (l < lim)
            if (data(p + l) /= data(p + l - dist)) exit
            l = l + 1
        end do
    end function match_length

    subroutine put_byte(enc, v)
        type(kitty_encoder_t), intent(inout) :: enc
        integer, intent(in) :: v
        enc%zlib_len = enc%zlib_len + 1
        enc%zlib(enc%zlib_len) = to_byte(iand(v, 255))
    end subroutine put_byte

    subroutine put_bits(enc, value, n)
        !! Append the n low bits of value, least significant first (RFC 1951).
        type(kitty_encoder_t), intent(inout) :: enc
        integer, intent(in) :: value, n
        enc%bitbuf = ior(enc%bitbuf, ishft(int(value, int64), enc%nbits))
        enc%nbits = enc%nbits + n
        do while (enc%nbits >= 8)
            call put_byte(enc, int(iand(enc%bitbuf, 255_int64)))
            enc%bitbuf = ishft(enc%bitbuf, -8)
            enc%nbits = enc%nbits - 8
        end do
    end subroutine put_bits

    subroutine put_code(enc, code, n)
        !! Huffman code (most significant bit first).
        type(kitty_encoder_t), intent(inout) :: enc
        integer, intent(in) :: code, n
        integer :: rev, i
        rev = 0
        do i = 0, n - 1
            if (btest(code, i)) rev = ibset(rev, n - 1 - i)
        end do
        call put_bits(enc, rev, n)
    end subroutine put_code

    subroutine put_literal(enc, sym)
        !! Fixed literal/length code of symbol 0..287.
        type(kitty_encoder_t), intent(inout) :: enc
        integer, intent(in) :: sym
        if (sym <= 143) then
            call put_code(enc, 48 + sym, 8)
        else if (sym <= 255) then
            call put_code(enc, 400 + sym - 144, 9)
        else if (sym <= 279) then
            call put_code(enc, sym - 256, 7)
        else
            call put_code(enc, 192 + sym - 280, 8)
        end if
    end subroutine put_literal

    subroutine put_match(enc, length, dist)
        type(kitty_encoder_t), intent(inout) :: enc
        integer, intent(in) :: length, dist
        integer :: sym, d

        sym = 285
        do while (LEN_BASE(sym) > length)
            sym = sym - 1
        end do
        call put_literal(enc, sym)
        if (LEN_EXTRA(sym) > 0) call put_bits(enc, length - LEN_BASE(sym), LEN_EXTRA(sym))
        d = 29
        do while (DIST_BASE(d) > dist)
            d = d - 1
        end do
        call put_code(enc, d, 5)
        if (DIST_EXTRA(d) > 0) call put_bits(enc, dist - DIST_BASE(d), DIST_EXTRA(d))
    end subroutine put_match

end module fortui_kitty
