program test_image_codecs
    !! Decoders terminals need for images: zlib against FortUI's own compressor,
    !! a PNG built by hand (RGBA, filters None and Up), base64, and sixel round
    !! trips through the encoder.
    use iso_fortran_env, only: int8, int32
    use fortui_inflate, only: zlib_decompress, png_decode, base64_decode
    use fortui_kitty, only: kitty_encoder_t, zlib_compress
    use fortui_sixel, only: sixel_decode, sixel_encode
    implicit none

    integer :: failures = 0

    call test_zlib()
    call test_png()
    call test_base64()
    call test_sixel()
    if (failures > 0) error stop "image codec tests failed"
    print *, "fortui image codec tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            failures = failures + 1
        end if
    end subroutine check

    subroutine test_zlib()
        type(kitty_encoder_t) :: enc
        integer(int8), allocatable :: data(:), out(:)
        integer :: k, n
        logical :: ok

        allocate(data(3000))
        do k = 1, size(data)
            data(k) = int(modulo(k * 7 + k / 100, 120), int8)
        end do
        data(1500:2400) = 5_int8
        call zlib_compress(enc, data, size(data), 300)
        call zlib_decompress(enc%zlib(1:enc%zlib_len), out, n, ok)
        call check(ok, "zlib stream decodes")
        call check(n == size(data), "zlib length")
        if (n == size(data)) call check(all(out(1:n) == data), "zlib bytes")
        ! Highly compressible data: the output outgrows its first buffer many
        ! times while back-references copy from it.
        deallocate(data)
        allocate(data(2000000))
        data = 7_int8
        data(1:3) = [1_int8, 2_int8, 3_int8]
        call zlib_compress(enc, data, size(data), 3000)
        call zlib_decompress(enc%zlib(1:enc%zlib_len), out, n, ok)
        call check(ok .and. n == size(data), "long runs decode")
        if (n == size(data)) call check(all(out(1:n) == data), "long runs bytes")
    end subroutine test_zlib

    subroutine test_png()
        ! 2 x 2 RGBA: red, half-transparent green / blue, transparent black.
        integer(int8), parameter :: png(80) = int([-119, 80, 78, 71, 13, 10, 26, 10, 0, &
            0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0, 2, 8, 6, 0, 0, 0, 114, -74, &
            13, 36, 0, 0, 0, 23, 73, 68, 65, 84, 120, -38, 99, -8, -49, -64, -16, 31, &
            8, 27, -104, 24, -127, 36, 3, 35, 67, 3, 0, 54, 126, 5, 1, 16, -101, -90, &
            32, 0, 0, 0, 0, 73, 69, 78, 68, -82, 66, 96, -126], int8)
        integer(int32), allocatable :: rgba(:, :)
        logical :: ok

        call png_decode(png, rgba, ok)
        call check(ok, "png decodes")
        if (.not. ok) return
        call check(size(rgba, 1) == 2 .and. size(rgba, 2) == 2, "png size")
        call check(rgba(1, 1) == px(255, 0, 0, 255), "png red")
        call check(rgba(2, 1) == px(0, 255, 0, 128), "png green alpha")
        call check(rgba(1, 2) == px(0, 0, 255, 255), "png blue (Up filter)")
        call check(rgba(2, 2) == px(0, 0, 0, 0), "png transparent")
    end subroutine test_png

    subroutine test_base64()
        integer(int8), allocatable :: out(:)
        integer :: n
        character(len=5) :: s
        call base64_decode("SGVs" // new_line("a") // "bG8=", out, n)
        call check(n == 5, "base64 length")
        if (n == 5) then
            s = transfer(out(1:5), s)
            call check(s == "Hello", "base64 text")
        end if
    end subroutine test_base64

    subroutine test_sixel()
        integer(int32) :: rgb(13 * 8)
        integer(int32), allocatable :: rgba(:, :)
        character(len=:), allocatable :: str
        integer :: x, y, q
        logical :: ok

        do y = 0, 7
            do x = 0, 12
                if (x < 6) then
                    rgb(y * 13 + x + 1) = int(z'FF0000', int32)
                else if (y < 3) then
                    rgb(y * 13 + x + 1) = int(z'0000FF', int32)
                else
                    rgb(y * 13 + x + 1) = int(z'FFFFFF', int32)
                end if
            end do
        end do
        call sixel_encode(rgb, 13, 8, str)
        call check(str(1:2) == achar(27) // "P", "sixel starts with DCS")
        q = index(str, "q")
        call sixel_decode(str(3:q - 1), str(q + 1:len(str) - 2), rgba, ok)
        call check(ok, "sixel decodes")
        if (.not. ok) return
        call check(size(rgba, 1) == 13 .and. size(rgba, 2) == 8, "sixel raster size")
        call check(rgba(1, 1) == px(255, 0, 0, 255), "sixel red")
        call check(rgba(13, 1) == px(0, 0, 255, 255), "sixel blue")
        call check(rgba(13, 8) == px(255, 255, 255, 255), "sixel white, second band")
        ! An HLS colour register and a repeat introducer.
        call sixel_decode("0;1", "#1;1;0;50;100#1!4~", rgba, ok)
        call check(ok .and. size(rgba, 1) == 4 .and. size(rgba, 2) == 6, "sixel repeat size")
        if (ok) call check(rgba(4, 6) == px(0, 0, 255, 255), "sixel HLS hue 0 is blue")
    end subroutine test_sixel

    pure integer(int32) function px(r, g, b, a)
        integer, intent(in) :: r, g, b, a
        integer :: top
        top = a
        if (top > 127) top = top - 256
        px = int(r, int32) + ishft(int(g, int32), 8) + ishft(int(b, int32), 16) + &
            ishft(int(top, int32), 24)
    end function px

end program test_image_codecs
