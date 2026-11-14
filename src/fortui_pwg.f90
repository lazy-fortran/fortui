module fortui_pwg
    !! PWG raster (PWG 5102.4) encoder for 8-bit sRGB pages.
    !!
    !! A print document is the sync word "RaS2" followed, for every page, by a
    !! 1796-byte big-endian header and the compressed rows: each group of equal
    !! rows starts with a repeat count, then packets of either one pixel repeated
    !! up to 128 times or up to 128 literal pixels. Printers that accept
    !! image/pwg-raster print such a page without rescaling it, so the page raster
    !! decides placement, cropping and borders exactly.
    use iso_fortran_env, only: int8, int32
    implicit none
    private

    integer, parameter, public :: PWG_QUALITY_DEFAULT = 0
    integer, parameter, public :: PWG_QUALITY_DRAFT = 3
    integer, parameter, public :: PWG_QUALITY_NORMAL = 4
    integer, parameter, public :: PWG_QUALITY_HIGH = 5

    integer, parameter :: HEADER_BYTES = 1796
    integer, parameter :: SRGB = 19

    type, public :: pwg_stream_t
        !! The encoded document: bytes(1:n).
        integer(int8), allocatable :: bytes(:)
        integer :: n = 0
    end type pwg_stream_t

    public :: pwg_begin, pwg_add_page

contains

    subroutine pwg_begin(s)
        !! Start a document (drops anything encoded before).
        type(pwg_stream_t), intent(inout) :: s
        s%n = 0
        call put_text(s, "RaS2", 4)
    end subroutine pwg_begin

    subroutine pwg_add_page(s, rgb, dpi, media, quality, media_type)
        !! Append one page: rgb(3, width, height) sRGB bytes, row 1 at the top of
        !! the sheet, at `dpi` in both directions. `media` is the PWG media name
        !! (for example "na_index-4x6_4x6in"), `quality` an IPP print-quality enum
        !! (PWG_QUALITY_*), `media_type` the IPP media-type keyword.
        type(pwg_stream_t), intent(inout) :: s
        integer(int8), intent(in) :: rgb(:, :, :)
        integer, intent(in) :: dpi
        character(*), intent(in), optional :: media, media_type
        integer, intent(in), optional :: quality
        integer :: w, h, start, y, rep

        w = size(rgb, 2)
        h = size(rgb, 3)
        start = s%n
        call reserve(s, HEADER_BYTES)
        s%bytes(start + 1:start + HEADER_BYTES) = 0_int8
        s%n = start + HEADER_BYTES
        call header_text(s, start, 0, "PwgRaster")
        if (present(media_type)) call header_text(s, start, 128, media_type)
        call header_u32(s, start, 276, dpi)
        call header_u32(s, start, 280, dpi)
        call header_u32(s, start, 340, 1)
        ! Page size in points, rounded as CUPS does.
        call header_u32(s, start, 352, nint(real(w) * 72.0 / real(dpi)))
        call header_u32(s, start, 356, nint(real(h) * 72.0 / real(dpi)))
        call header_u32(s, start, 372, w)
        call header_u32(s, start, 376, h)
        call header_u32(s, start, 384, 8)
        call header_u32(s, start, 388, 24)
        call header_u32(s, start, 392, 3 * w)
        call header_u32(s, start, 400, SRGB)
        call header_u32(s, start, 420, 3)
        ! TotalPageCount, CrossFeedTransform, FeedTransform, ImageBox, white.
        call header_u32(s, start, 452, 1)
        call header_u32(s, start, 456, 1)
        call header_u32(s, start, 460, 1)
        call header_u32(s, start, 472, w)
        call header_u32(s, start, 476, h)
        call header_u32(s, start, 480, int(z'00FFFFFF'))
        if (present(quality)) call header_u32(s, start, 484, quality)
        call header_text(s, start, 1668, "perceptual")
        if (present(media)) call header_text(s, start, 1732, media)

        y = 1
        do while (y <= h)
            rep = 0
            do while (y + rep < h .and. rep < 255)
                if (any(rgb(:, :, y + rep + 1) /= rgb(:, :, y))) exit
                rep = rep + 1
            end do
            call put_byte(s, rep)
            call encode_row(s, rgb(:, :, y))
            y = y + rep + 1
        end do
    end subroutine pwg_add_page

    subroutine encode_row(s, row)
        !! Packets of one row: runs of two or more equal pixels (count - 1, pixel)
        !! and literal stretches of two or more pixels (257 - count, pixels); a
        !! lone pixel is a run of one.
        type(pwg_stream_t), intent(inout) :: s
        integer(int8), intent(in) :: row(:, :)
        integer :: w, i, run, lit

        w = size(row, 2)
        call reserve(s, w * 3 + (w + 127) / 128 + 1)
        i = 1
        do while (i <= w)
            run = 1
            do while (i + run <= w .and. run < 128)
                if (any(row(:, i + run) /= row(:, i))) exit
                run = run + 1
            end do
            if (run >= 2 .or. i == w) then
                call put_byte(s, run - 1)
                call put_pixels(s, row(:, i:i))
                i = i + run
                cycle
            end if
            lit = 1
            do while (i + lit <= w .and. lit < 128)
                if (i + lit < w) then
                    if (all(row(:, i + lit) == row(:, i + lit + 1))) exit
                end if
                lit = lit + 1
            end do
            if (lit == 1) then
                call put_byte(s, 0)
            else
                call put_byte(s, 257 - lit)
            end if
            call put_pixels(s, row(:, i:i + lit - 1))
            i = i + lit
        end do
    end subroutine encode_row

    subroutine reserve(s, extra)
        type(pwg_stream_t), intent(inout) :: s
        integer, intent(in) :: extra
        integer(int8), allocatable :: grown(:)

        if (.not. allocated(s%bytes)) allocate(s%bytes(max(4096, 2 * extra)))
        if (s%n + extra <= size(s%bytes)) return
        allocate(grown(max(2 * size(s%bytes), s%n + extra)))
        grown(1:s%n) = s%bytes(1:s%n)
        call move_alloc(grown, s%bytes)
    end subroutine reserve

    subroutine put_byte(s, value)
        type(pwg_stream_t), intent(inout) :: s
        integer, intent(in) :: value
        call reserve(s, 1)
        s%n = s%n + 1
        s%bytes(s%n) = int(iand(value, 255) - merge(256, 0, iand(value, 255) > 127), int8)
    end subroutine put_byte

    subroutine put_pixels(s, px)
        type(pwg_stream_t), intent(inout) :: s
        integer(int8), intent(in) :: px(:, :)
        integer :: k

        call reserve(s, size(px))
        do k = 1, size(px, 2)
            s%bytes(s%n + 1:s%n + 3) = px(1:3, k)
            s%n = s%n + 3
        end do
    end subroutine put_pixels

    subroutine put_text(s, text, length)
        type(pwg_stream_t), intent(inout) :: s
        character(*), intent(in) :: text
        integer, intent(in) :: length
        integer :: k

        call reserve(s, length)
        do k = 1, length
            s%n = s%n + 1
            s%bytes(s%n) = int(ichar(text(k:k)), int8)
        end do
    end subroutine put_text

    subroutine header_text(s, start, offset, text)
        !! NUL-terminated string field of 64 bytes.
        type(pwg_stream_t), intent(inout) :: s
        integer, intent(in) :: start, offset
        character(*), intent(in) :: text
        integer :: k

        do k = 1, min(len_trim(text), 63)
            s%bytes(start + offset + k) = int(ichar(text(k:k)), int8)
        end do
    end subroutine header_text

    subroutine header_u32(s, start, offset, value)
        !! Big-endian unsigned 32-bit field.
        type(pwg_stream_t), intent(inout) :: s
        integer, intent(in) :: start, offset, value
        integer :: k, b

        do k = 0, 3
            b = int(iand(ishft(int(value, int32), -8 * (3 - k)), 255_int32))
            s%bytes(start + offset + k + 1) = int(b - merge(256, 0, b > 127), int8)
        end do
    end subroutine header_u32

end module fortui_pwg
