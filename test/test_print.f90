program test_print
    !! Printing service: PWG raster bytes worked out by hand from PWG 5102.4 for
    !! small rows; with -DENABLE_PRINT=1 the whole document decoded by libcups's
    !! own raster reader; page pixel sizes of sheets. With FORTUI_PRINT_TEST_PRINTER
    !! naming a queue, a held job is submitted to it and cancelled (nothing prints).
    use iso_c_binding
    use iso_fortran_env, only: int8, int32
    use fortui_pwg, only: pwg_stream_t, pwg_begin, pwg_add_page, PWG_QUALITY_HIGH
    use fortui_print, only: print_media_t, print_page_pixels, print_available, &
        print_printers, print_printer_t, print_capabilities, print_caps_t, print_page, &
        print_job_t, print_result_t, print_cancel, PRINT_OK, PRINT_UNSUPPORTED, &
        print_media_label, print_apply_strings, print_choice_t, print_keyword_label
    implicit none

    integer :: failures = 0
#ifdef ENABLE_PRINT
    type, bind(C) :: reader_t
        type(c_ptr) :: bytes
        integer(c_size_t) :: n, pos
    end type reader_t

    interface
        type(c_ptr) function cupsRasterOpenIO(iocb, ctx, mode) &
                bind(C, name="cupsRasterOpenIO")
            import :: c_ptr, c_funptr, c_int
            type(c_funptr), value :: iocb
            type(c_ptr), value :: ctx
            integer(c_int), value :: mode
        end function
        integer(c_int) function cupsRasterReadHeader2(r, h) &
                bind(C, name="cupsRasterReadHeader2")
            import :: c_ptr, c_int, c_int8_t
            type(c_ptr), value :: r
            integer(c_int8_t) :: h(1796)
        end function
        integer(c_int) function cupsRasterReadPixels(r, p, n) &
                bind(C, name="cupsRasterReadPixels")
            import :: c_ptr, c_int, c_int8_t
            type(c_ptr), value :: r
            integer(c_int8_t) :: p(*)
            integer(c_int), value :: n
        end function
        subroutine cupsRasterClose(r) bind(C, name="cupsRasterClose")
            import :: c_ptr
            type(c_ptr), value :: r
        end subroutine
    end interface
#endif

    call test_hand_encoded()
    call test_long_run()
    call test_page_pixels()
    call test_media_labels()
    call test_strings()
#ifdef ENABLE_PRINT
    call test_cups_decodes()
    call test_held_job()
#else
    call test_unsupported()
#endif

    if (failures > 0) then
        print '(i0,a)', failures, " print checks failed"
        error stop 1
    end if
    print '(a)', " fortui print tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

    function px(r, g, b) result(p)
        integer, intent(in) :: r, g, b
        integer(int8) :: p(3)
        p = int([r, g, b] - merge(256, 0, [r, g, b] > 127), int8)
    end function px

    function rows_of(s) result(b)
        !! The encoded rows: everything after the sync word and the header.
        type(pwg_stream_t), intent(in) :: s
        integer, allocatable :: b(:)
        b = iand(int(s%bytes(4 + 1796 + 1:s%n)), 255)
    end function rows_of

    subroutine test_hand_encoded()
        !! Two equal rows A A B C: row repeat 1; run of two A (1, A); literal
        !! B C (257 - 2 = 255, B, C).
        type(pwg_stream_t) :: s
        integer(int8) :: img(3, 4, 2)
        integer :: k

        do k = 1, 2
            img(:, 1, k) = px(10, 20, 30)
            img(:, 2, k) = px(10, 20, 30)
            img(:, 3, k) = px(200, 0, 0)
            img(:, 4, k) = px(0, 0, 250)
        end do
        call pwg_begin(s)
        call pwg_add_page(s, img, 600)
        call check(s%n == 4 + 1796 + 12, "two equal rows encode to 12 bytes")
        call check(all(rows_of(s) == [1, 1, 10, 20, 30, 255, 200, 0, 0, 0, 0, 250]), &
            "row bytes as worked out by hand")
        call check(all(achar(s%bytes(1:4)) == ["R", "a", "S", "2"]), "sync word")
        ! Header: width 4 at byte 372, height 2 at 376, sRGB (19) at 400, big-endian.
        call check(all(s%bytes(4 + 373:4 + 376) == int([0, 0, 0, 4], int8)) .and. &
            all(s%bytes(4 + 377:4 + 380) == int([0, 0, 0, 2], int8)) .and. &
            all(s%bytes(4 + 401:4 + 404) == int([0, 0, 0, 19], int8)), &
            "big-endian header fields")
    end subroutine test_hand_encoded

    subroutine test_long_run()
        !! 130 equal pixels then one other: runs of 128 (127, A) and 2 (1, A), then
        !! the lone last pixel as a run of one (0, B).
        type(pwg_stream_t) :: s
        integer(int8) :: img(3, 131, 1)
        integer :: k

        do k = 1, 130
            img(:, k, 1) = px(1, 2, 3)
        end do
        img(:, 131, 1) = px(9, 9, 9)
        call pwg_begin(s)
        call pwg_add_page(s, img, 300)
        call check(all(rows_of(s) == [0, 127, 1, 2, 3, 1, 1, 2, 3, 0, 9, 9, 9]), &
            "runs longer than 128 pixels split")
    end subroutine test_long_run

    subroutine test_page_pixels()
        !! 4x6 in at 600 dpi is 2400 x 3600 pixels; 3.4 mm at 600 dpi is 80.3 px.
        type(print_media_t) :: m
        integer :: w, h, l, t, r, b

        m%width = 10160
        m%length = 15240
        m%left = 340
        m%right = 340
        m%top = 500
        m%bottom = 500
        call print_page_pixels(m, 600, w, h, l, t, r, b)
        call check(w == 2400 .and. h == 3600, "4x6 in at 600 dpi")
        call check(l == 81 .and. r == 81 .and. t == 119 .and. b == 119, &
            "margins round up to whole pixels")
    end subroutine test_page_pixels

    subroutine test_strings()
        !! A strings file names only choices still labelled with their keyword.
        type(print_caps_t) :: caps
        character(len=:), allocatable :: text

        allocate(caps%media_types(2), caps%sources(1))
        caps%media_types(1) = print_choice_t("com.canon-mtgr", "com.canon-mtgr")
        caps%media_types(2) = print_choice_t("stationery", "Plain")
        caps%sources(1) = print_choice_t("rear", "rear")
        text = '"media-type.com.canon-mtgr" = "Photo Paper Plus Glossy II";' // &
            achar(10) // '"media-type.stationery" = "Plain Paper";' // achar(10) // &
            '"media-source.rear" = "Rear Tray";' // achar(10) // 'junk' // achar(10) // &
            '"printer-state-reasons.none" = "Ready";'
        call print_apply_strings(caps, text)
        call check(caps%media_types(1)%label == "Photo Paper Plus Glossy II", &
            "vendor media type named")
        call check(caps%media_types(2)%label == "Plain", "existing names are kept")
        call check(caps%sources(1)%label == "Rear Tray", "tray named")
    end subroutine test_strings

    subroutine test_media_labels()
        call check(print_media_label("na_index-4x6_4x6in", 10160, 15240) == &
            "4 x 6 in (10.2 x 15.2 cm)", "inch size with centimetres")
        call check(print_media_label("iso_a4_210x297mm_borderless", 21000, 29700) == &
            "A4, 210 x 297 mm", "ISO name in capitals, borderless suffix dropped")
        call check(print_media_label("om_business-card_55x91mm", 5500, 9100) == &
            "Business Card, 55 x 91 mm", "words of a name")
        call check(print_media_label("custom_120x120mm_120x120mm", 12000, 12000) == &
            "120 x 120 mm", "custom size by its dimensions")
        call check(print_media_label("odd", 1, 1) == "odd", "unknown form unchanged")
        call check(print_keyword_label("rear") == "Rear tray" .and. &
            print_keyword_label("stationery") == "Plain paper" .and. &
            print_keyword_label("tray-2") == "Tray 2", "keyword names")
    end subroutine test_media_labels

#ifdef ENABLE_PRINT
    function read_cb(ctx, buffer, length) result(got) bind(C)
        type(c_ptr), value :: ctx, buffer
        integer(c_size_t), value :: length
        integer(c_intptr_t) :: got
        type(reader_t), pointer :: rd
        integer(c_int8_t), pointer :: src(:), dst(:)
        integer(c_size_t) :: k

        call c_f_pointer(ctx, rd)
        got = int(min(length, rd%n - rd%pos), c_intptr_t)
        if (got <= 0) return
        call c_f_pointer(rd%bytes, src, [rd%n])
        call c_f_pointer(buffer, dst, [length])
        do k = 1, int(got, c_size_t)
            dst(k) = src(rd%pos + k)
        end do
        rd%pos = rd%pos + int(got, c_size_t)
    end function read_cb

    integer function native_u32(h, offset)
        integer(c_int8_t), intent(in) :: h(1796)
        integer, intent(in) :: offset
        native_u32 = transfer(h(offset + 1:offset + 4), 0_int32)
    end function native_u32

    subroutine test_cups_decodes()
        !! A 37 x 23 page with gradients, flat stretches and repeated rows,
        !! decoded by cupsRasterReadPixels, must give back every pixel.
        type(pwg_stream_t), target :: s
        type(reader_t), target :: rd
        integer(int8) :: img(3, 37, 23)
        integer(c_int8_t) :: h(1796), line(3 * 37)
        type(c_ptr) :: r
        integer :: x, y, bad
        character(len=64) :: name

        do y = 1, 23
            do x = 1, 37
                if (y > 10 .and. y < 15) then
                    img(:, x, y) = px(255, 255, 255)
                else if (x < 12) then
                    img(:, x, y) = px(mod(7 * x, 256), mod(11 * y, 256), 128)
                else
                    img(:, x, y) = px(0, 64, mod(x / 5, 2) * 200)
                end if
            end do
        end do
        call pwg_begin(s)
        call pwg_add_page(s, img, 600, media="na_index-4x6_4x6in", &
            quality=PWG_QUALITY_HIGH, media_type="photographic-glossy")
        rd = reader_t(c_loc(s%bytes), int(s%n, c_size_t), 0_c_size_t)
        r = cupsRasterOpenIO(c_funloc(read_cb), c_loc(rd), 0_c_int)
        call check(c_associated(r), "libcups opens the stream")
        if (.not. c_associated(r)) return
        call check(cupsRasterReadHeader2(r, h) == 1, "libcups reads the header")
        call check(native_u32(h, 372) == 37 .and. native_u32(h, 376) == 23, "size")
        call check(native_u32(h, 276) == 600 .and. native_u32(h, 280) == 600, "resolution")
        call check(native_u32(h, 392) == 111 .and. native_u32(h, 400) == 19 .and. &
            native_u32(h, 388) == 24, "bytes per line, sRGB, 24 bits")
        call check(native_u32(h, 484) == PWG_QUALITY_HIGH, "print quality")
        name = transfer(h(1733:1796), name)
        call check(name(1:index(name, achar(0)) - 1) == "na_index-4x6_4x6in", &
            "page size name")
        bad = 0
        do y = 1, 23
            if (cupsRasterReadPixels(r, line, 111_c_int) /= 111) bad = bad + 1
            if (any(line /= reshape(img(:, :, y), [111]))) bad = bad + 1
        end do
        call check(bad == 0, "libcups decodes every row unchanged")
        call cupsRasterClose(r)
    end subroutine test_cups_decodes

    subroutine test_held_job()
        !! Needs a real queue; the job is held and cancelled, so nothing prints.
        character(len=256) :: queue
        integer :: n, k, w, h
        type(print_printer_t), allocatable :: printers(:)
        type(print_caps_t) :: caps
        type(print_result_t) :: res
        type(print_job_t) :: job
        integer(int8), allocatable :: page(:, :, :)

        call get_environment_variable("FORTUI_PRINT_TEST_PRINTER", queue, n)
        if (n == 0) then
            print '(a)', "print: held-job check skipped (FORTUI_PRINT_TEST_PRINTER unset)"
            return
        end if
        call check(print_available(), "printing compiled in")
        call print_printers(printers, res)
        call check(any([(printers(k)%name == trim(queue), k = 1, size(printers))]), &
            "the queue is listed")
        call print_capabilities(trim(queue), caps, res)
        call check(res%status == PRINT_OK .and. size(caps%media) > 0 .and. caps%dpi > 0, &
            "capabilities: " // res%message)
        if (size(caps%media) == 0) return
        print '(a,i0,a,l1,a,i0,a)', "print: ", size(caps%media), " media, live ", &
            caps%live, ", ", count([(caps%media_types(n)%label /= &
            caps%media_types(n)%keyword, n = 1, size(caps%media_types))]), &
            " media types named by the printer"
        k = 1
        do n = 1, size(caps%media)
            if (caps%media(n)%borderless) then
                k = n
                exit
            end if
        end do
        call print_page_pixels(caps%media(k), caps%dpi, w, h)
        allocate(page(3, w, h))
        page = -1_int8
        job%printer = trim(queue)
        job%title = "fortui test (held, cancelled)"
        job%media = caps%media(k)%name
        job%hold = .true.
        call print_page(job, page, caps%dpi, res)
        call check(res%status == PRINT_OK .and. res%job_id > 0, &
            "held job accepted: " // res%message)
        if (res%job_id > 0) then
            call print_cancel(trim(queue), res%job_id, res)
            call check(res%status == PRINT_OK, "held job cancelled: " // res%message)
        end if
    end subroutine test_held_job
#else
    subroutine test_unsupported()
        type(print_printer_t), allocatable :: printers(:)
        type(print_result_t) :: res
        call check(.not. print_available(), "not compiled in")
        call print_printers(printers, res)
        call check(res%status == PRINT_UNSUPPORTED .and. size(printers) == 0, &
            "requests say unsupported")
    end subroutine test_unsupported
#endif

end program test_print
