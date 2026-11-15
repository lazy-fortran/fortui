module fortui_inflate
    !! Decoders for image payloads that terminals receive: zlib streams through
    !! fortzip, PNG images through fortimg (both Fortran, so every target has
    !! them, WebAssembly included), and base64.
    use iso_fortran_env, only: int8, int32
    use fortzip, only: zlib_decompress_bytes => zlib_decompress, ZIP_OK
    use fortimg, only: image_t, png_decode_image => png_decode, image_convert, IMG_OK
    implicit none
    private

    public :: zlib_decompress, png_decode, base64_decode

contains

    subroutine zlib_decompress(src, out, n, ok)
        !! A zlib stream into out(1:n); ok when it decoded and its checksum held.
        integer(int8), intent(in) :: src(:)
        integer(int8), allocatable, intent(out) :: out(:)
        integer, intent(out) :: n
        logical, intent(out) :: ok
        integer :: status
        call zlib_decompress_bytes(src, out, status)
        ok = status == ZIP_OK
        n = 0
        if (ok) n = size(out)
    end subroutine zlib_decompress

    subroutine png_decode(src, rgba, ok)
        !! A PNG (any colour type and depth, interlaced or not) into
        !! rgba(width, height) packed like ui_rgba (bytes R, G, B, A), row 1 at the top.
        integer(int8), intent(in) :: src(:)
        integer(int32), allocatable, intent(out) :: rgba(:, :)
        logical, intent(out) :: ok
        type(image_t) :: img
        integer :: status, x, y
        call png_decode_image(src, img, status)
        ok = status == IMG_OK
        if (.not. ok) return
        call image_convert(img, 4)
        allocate (rgba(img%width, img%height))
        do y = 1, img%height
            do x = 1, img%width
                rgba(x, y) = transfer(img%pixels(:, x, y), rgba(x, y))
            end do
        end do
    end subroutine png_decode

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
