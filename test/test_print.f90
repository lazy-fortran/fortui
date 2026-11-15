program test_print
    !! Printing service. PWG raster and IPP bytes worked out by hand from PWG
    !! 5102.4 and RFC 8010; with libcups at hand (opened at run time, never
    !! linked) the raster decoded by its reader, paper size names compared with
    !! its own over a grid of sizes, and a virtual printer (ippeveprinter, started
    !! here) asked for its sheets, which must be libcups's list, and sent two
    !! jobs, whose bytes and attributes the printer must have received. With
    !! FORTUI_PRINT_TEST_PRINTER naming a real queue, a held job is submitted
    !! to it and cancelled (nothing prints). FORTUI_PRINT_REFERENCE=require
    !! turns a missing libcups or ippeveprinter into a failure, as in CI.
    use iso_c_binding, only: c_int8_t
    use iso_fortran_env, only: int8
    use fortui_ipp, only: ipp_msg_t, ipp_attr_t, ipp_request, ipp_add, ipp_attr, &
        ipp_value_str, ipp_value_int, ipp_value_col, ipp_encode, ipp_decode, ipp_find, &
        ipp_str, ipp_int, ipp_members, IPP_PRINTER, IPP_INTEGER, IPP_RANGE, &
        IPP_RESOLUTION, IPP_KEYWORD, IPP_GET_PRINTER_ATTRIBUTES, IPP_BEGIN_COLLECTION
    use fortui_pwg, only: pwg_stream_t, pwg_begin, pwg_add_page, PWG_QUALITY_HIGH
    use fortui_pwg_sizes, only: pwg_size_name, pwg_size_of
    use fortui_print, only: print_media_t, print_page_pixels, print_available, &
        print_printers, print_printer_t, print_capabilities, print_caps_t, print_page, &
        print_job_t, print_result_t, print_cancel, PRINT_OK, &
        print_media_label, print_apply_strings, print_choice_t, print_keyword_label
    use cups_reference, only: cups_open, cups_size_name, cups_media_list, cups_raster_rows
    implicit none

    integer :: failures = 0
    logical :: required

    required = env("FORTUI_PRINT_REFERENCE") == "require"
    call test_hand_encoded()
    call test_long_run()
    call test_page_pixels()
    call test_media_labels()
    call test_strings()
    call test_ipp_bytes()
    call test_ipp_round_trip()
    call test_size_parse()
    if (cups_open()) then
        call test_cups_decodes()
        ! The table follows libcups 2.4, which renamed and added sizes.
        if (newest_sizes_known()) then
            call test_size_names()
        else
            print '(a)', "print: not run: size names (libcups older than 2.4)"
        end if
    else
        call not_run("libcups (libcups.so.2) not found: raster and size names not compared")
    end if
    call test_virtual_printer()
    call test_held_job()

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

    subroutine not_run(why)
        character(*), intent(in) :: why
        print '(a)', "print: not run: " // why
        if (required) call check(.false., "required reference missing: " // why)
    end subroutine not_run

    function env(name) result(v)
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        integer :: n, st
        call get_environment_variable(name, length=n, status=st)
        allocate(character(len=max(n, 0)) :: v)
        if (st == 0 .and. n > 0) call get_environment_variable(name, v)
        if (st /= 0) v = ""
    end function env

    subroutine test_ipp_bytes()
        !! Get-Printer-Attributes with the two leading operation attributes, a
        !! printer group with integer x = 7 and collection c = {m = keyword k},
        !! as RFC 8010 lays it out byte by byte.
        type(ipp_msg_t) :: msg
        integer(int8), allocatable :: b(:)
        integer :: n
        integer, allocatable :: want(:)
        call ipp_request(msg, IPP_GET_PRINTER_ATTRIBUTES)
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "x", ipp_value_int(IPP_INTEGER, 7)))
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "c", ipp_value_col( &
            ipp_attr(0, "m", ipp_value_str(IPP_KEYWORD, "k")))))
        call ipp_encode(msg, b, n)
        want = [2, 0, 0, 11, 0, 0, 0, 1, &
            1, 71, 0, 18, chars("attributes-charset"), 0, 5, chars("utf-8"), &
            72, 0, 27, chars("attributes-natural-language"), 0, 2, chars("en"), &
            4, 33, 0, 1, chars("x"), 0, 4, 0, 0, 0, 7, &
            52, 0, 1, chars("c"), 0, 0, &
            74, 0, 0, 0, 1, chars("m"), &
            68, 0, 0, 0, 1, chars("k"), &
            55, 0, 0, 0, 0, &
            3]
        call check(n == size(want), "encoded length")
        if (n == size(want)) call check(all(iand(int(b(1:n)), 255) == want), &
            "bytes as laid out by hand")
    end subroutine test_ipp_bytes

    function chars(s) result(c)
        character(*), intent(in) :: s
        integer :: c(len(s)), k
        c = [(iachar(s(k:k)), k = 1, len(s))]
    end function chars

    subroutine test_ipp_round_trip()
        !! Negative integers, ranges, resolutions, several values and a
        !! collection inside a collection come back as they went.
        type(ipp_msg_t) :: msg, back
        type(ipp_attr_t), allocatable :: m(:), inner(:)
        integer(int8), allocatable :: b(:)
        integer :: n, k
        logical :: ok
        call ipp_request(msg, IPP_GET_PRINTER_ATTRIBUTES, "ipp://h/p")
        msg%request_id = 70000
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "ints", ipp_value_int(IPP_INTEGER, -5), &
            ipp_value_int(IPP_INTEGER, 2147483647)))
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "range", ipp_value_int(IPP_RANGE, 1, 99)))
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "res", ipp_value_int(IPP_RESOLUTION, &
            600, 300, 3)))
        call ipp_add(msg, ipp_attr(IPP_PRINTER, "col", ipp_value_col( &
            ipp_attr(0, "size", ipp_value_col(ipp_attr(0, "x", ipp_value_int(IPP_INTEGER, 1)), &
            ipp_attr(0, "y", ipp_value_int(IPP_INTEGER, 2)))), &
            ipp_attr(0, "kw", ipp_value_str(IPP_KEYWORD, "a"), ipp_value_str(IPP_KEYWORD, "b"))), &
            ipp_value_col(ipp_attr(0, "z", ipp_value_int(IPP_INTEGER, 3)))))
        call ipp_encode(msg, b, n)
        call ipp_decode(b(1:n), back, ok)
        call check(ok .and. back%code == IPP_GET_PRINTER_ATTRIBUTES .and. &
            back%request_id == 70000 .and. back%n == msg%n, "message decodes")
        if (.not. ok) return
        k = ipp_find(back%attrs, "ints", back%n)
        call check(ipp_int(back%attrs(k), 1) == -5 .and. &
            ipp_int(back%attrs(k), 2) == 2147483647, "integers with sign")
        k = ipp_find(back%attrs, "range", back%n)
        call check(back%attrs(k)%tags(1) == IPP_RANGE .and. ipp_int(back%attrs(k), 1) == 1 &
            .and. ipp_int(back%attrs(k), 1, 2) == 99, "range")
        k = ipp_find(back%attrs, "res", back%n)
        call check(all(back%attrs(k)%ints(:, 1) == [600, 300, 3]), "resolution")
        call check(ipp_str(back%attrs(ipp_find(back%attrs, "printer-uri", back%n)), 1) == &
            "ipp://h/p", "printer-uri")
        k = ipp_find(back%attrs, "col", back%n)
        call check(back%attrs(k)%n == 2 .and. back%attrs(k)%tags(2) == IPP_BEGIN_COLLECTION, &
            "two collection values")
        m = ipp_members(back%attrs(k), 1)
        call check(size(m) == 2, "members of the first value")
        if (size(m) /= 2) return
        inner = ipp_members(m(1), 1)
        call check(m(1)%name == "size" .and. size(inner) == 2, "nested collection")
        if (size(inner) == 2) call check(inner(2)%name == "y" .and. ipp_int(inner(2), 1) == 2, &
            "nested member value")
        call check(m(2)%n == 2 .and. ipp_str(m(2), 2) == "b", "member with two values")
        m = ipp_members(back%attrs(k), 2)
        call check(size(m) == 1 .and. ipp_int(m(1), 1) == 3, "second collection value")
    end subroutine test_ipp_round_trip

    subroutine test_size_parse()
        integer :: w, l
        call pwg_size_of("na_number-10_4.125x9.5in", w, l)
        call check(w == 10478 .and. l == 24130, "inch sizes from a name")
        call pwg_size_of("iso_a4_210x297mm", w, l)
        call check(w == 21000 .and. l == 29700, "millimetre sizes from a name")
        call pwg_size_of("a4", w, l)
        call check(w == 0 .and. l == 0, "no size in a legacy name")
        call check(pwg_size_name(21010, 29690) == "iso_a4_210x297mm", "near size")
        call check(pwg_size_name(12000, 12000) == "custom_120x120mm_120x120mm", &
            "custom millimetres")
        call check(pwg_size_name(17780, 25400) == "custom_7x10in_7x10in", "custom inches")
    end subroutine test_size_parse

    subroutine test_size_names()
        !! Every size from 20 x 20 mm to 400 x 600 mm in 0.1 mm steps near the
        !! listed sizes, and in 1 mm steps elsewhere, named as libcups names it.
        integer :: w, l, bad, tried
        character(len=:), allocatable :: mine, ref
        bad = 0
        tried = 0
        do w = 2000, 40000, 100
            do l = 2000, 60000, 100
                tried = tried + 1
                mine = pwg_size_name(w, l)
                ref = cups_size_name(w, l)
                if (mine /= ref) then
                    bad = bad + 1
                    if (bad <= 3) print '(a,2i7,4a)', "  size ", w, l, ": ", mine, " vs ", ref
                end if
            end do
        end do
        call check(bad == 0, "size names as libcups gives them (1 mm grid)")
        bad = 0
        do w = 7000, 22000, 7
            l = nint(w * 1.4142)
            tried = tried + 1
            if (pwg_size_name(w, l) /= cups_size_name(w, l)) bad = bad + 1
            if (pwg_size_name(w, w + 4000) /= cups_size_name(w, w + 4000)) bad = bad + 1
        end do
        call check(bad == 0, "size names as libcups gives them (fine steps)")
    end subroutine test_size_names

    subroutine test_cups_decodes()
        !! A 37 x 23 page with gradients, flat stretches and repeated rows,
        !! decoded by cupsRasterReadPixels, must give back every pixel.
        type(pwg_stream_t) :: s
        integer(int8) :: img(3, 37, 23)
        integer(c_int8_t) :: h(1796)
        integer(c_int8_t), allocatable :: rows(:, :)
        integer :: x, y, bad
        logical :: ok
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
        call cups_raster_rows(s%bytes, s%n, h, rows, ok)
        call check(ok, "libcups reads the stream")
        if (.not. ok) return
        call check(u32(h, 372) == 37 .and. u32(h, 376) == 23, "size")
        call check(u32(h, 276) == 600 .and. u32(h, 280) == 600, "resolution")
        call check(u32(h, 392) == 111 .and. u32(h, 400) == 19 .and. &
            u32(h, 388) == 24, "bytes per line, sRGB, 24 bits")
        call check(u32(h, 484) == PWG_QUALITY_HIGH, "print quality")
        name = transfer(h(1733:1796), name)
        call check(name(1:index(name, achar(0)) - 1) == "na_index-4x6_4x6in", &
            "page size name")
        bad = 0
        do y = 1, 23
            if (any(rows(:, y) /= reshape(img(:, :, y), [111]))) bad = bad + 1
        end do
        call check(bad == 0, "libcups decodes every row unchanged")
    end subroutine test_cups_decodes

    logical function same_name(mine, ref)
        !! The same name, or one libcups before 2.4 does not know yet: it names
        !! the sizes PWG listed later as custom sizes ("custom_89x89mm_89x89mm"
        !! for "om_square-photo_89x89mm").
        character(*), intent(in) :: mine, ref
        same_name = mine == ref
        if (.not. same_name .and. index(ref, "custom_") == 1 .and. index(mine, "custom_") /= 1) &
            same_name = .not. newest_sizes_known()
    end function same_name

    logical function newest_sizes_known()
        !! Whether the reference libcups has PWG's later sizes (2.4 and newer).
        newest_sizes_known = cups_size_name(5500, 8500) == "om_business-card_55x85mm"
    end function newest_sizes_known

    integer function u32(h, offset)
        integer(c_int8_t), intent(in) :: h(1796)
        integer, intent(in) :: offset
        u32 = transfer(h(offset + 1:offset + 4), 0)
    end function u32

    subroutine test_virtual_printer()
        !! A virtual printer with sheets in no order, borderless and bordered
        !! variants, tray- and type-specific sheets, a size near A4, a custom
        !! size, a custom range and paper loaded in two trays. Its sheets must be
        !! libcups's list; job 1 borderless from the rear tray on glossy paper and
        !! job 2 with margins must arrive with those attributes and their bytes.
        character(len=:), allocatable :: dir, uri, eve, col
        character(len=128), allocatable :: names(:)
        integer, allocatable :: sizes(:, :)
        type(print_caps_t) :: caps
        type(print_result_t) :: res
        type(print_job_t) :: job
        type(pwg_stream_t) :: sent(2)
        integer(int8), allocatable :: page(:, :, :)
        integer :: k, n, m, w, h, port, tries, same, before
        real :: r
        logical :: ok
        character(len=*), parameter :: wanted(2) = [character(29) :: &
            "na_index-4x6_4x6in_borderless", "na_index-4x6_4x6in"]

        before = failures
        eve = env("FORTUI_IPPEVEPRINTER")
        if (len(eve) == 0) eve = "ippeveprinter"
        if (.not. runs("command -v " // eve // " > /dev/null")) then
            call not_run("ippeveprinter not found: no virtual printer")
            return
        end if
        call random_number(r)
        port = 20000 + int(r * 20000)
        dir = env("TMPDIR")
        if (len(dir) == 0) dir = "/tmp"
        dir = dir // "/fortui-print-" // itoa(port)
        call check(runs("rm -rf " // dir // " && mkdir -p " // dir), "spool directory")
        call write_conf(dir // "/printer.conf")
        call check(runs(eve // " -p " // itoa(port) // " -k -d " // dir // &
            ' -c "$(pwd)/test/system/keep-job.sh" -a ' // dir // &
            "/printer.conf fortui-test > " // dir // "/log 2>&1 & echo $! > " // dir // &
            "/pid"), "start ippeveprinter")
        uri = "ipp://localhost:" // itoa(port) // "/ipp/print"
        do tries = 1, 100
            call print_capabilities(uri, caps, res)
            if (res%status == PRINT_OK) exit
            call execute_command_line("sleep 0.1")
        end do
        call check(res%status == PRINT_OK, "virtual printer answers: " // res%message)
        if (res%status /= PRINT_OK) goto 9

        call check(caps%dpi == 600 .and. caps%color, "600 dpi in colour")
        call check(size(caps%qualities) == 3, "three qualities")
        call check(size(caps%sources) == 2 .and. size(caps%media_types) == 2, &
            "trays and media types")
        call check(caps%live, "loaded paper asked from the device")
        do k = 1, size(caps%media)
            if (caps%media(k)%name == "iso_a4_210x297mm") call check(caps%media(k)%loaded &
                .and. caps%media(k)%source == "main", "A4 loaded in the main tray")
        end do
        if (cups_open()) then
            call cups_media_list("localhost", port, uri, names, sizes, ok)
            call check(ok, "libcups lists the virtual printer's sheets")
            same = count([(k <= size(names), k = 1, size(caps%media))])
            call check(size(names) == size(caps%media), "as many sheets as libcups (" // &
                itoa(size(caps%media)) // " vs " // itoa(size(names)) // ")")
            do k = 1, min(size(names), size(caps%media))
                if (.not. same_name(caps%media(k)%name, trim(names(k))) .or. any(sizes(:, k) /= &
                    [caps%media(k)%width, caps%media(k)%length, caps%media(k)%bottom, &
                    caps%media(k)%left, caps%media(k)%right, caps%media(k)%top])) then
                    call check(.false., "sheet " // itoa(k) // ": " // caps%media(k)%name // &
                        " vs libcups " // trim(names(k)))
                end if
            end do
        end if

        do k = 1, 2
            m = 0
            do n = 1, size(caps%media)
                if (caps%media(n)%name == trim(wanted(k))) m = n
            end do
            call check(m > 0, "virtual printer offers " // trim(wanted(k)))
            if (m == 0) goto 9
            call print_page_pixels(caps%media(m), caps%dpi / 4, w, h)
            if (allocated(page)) deallocate(page)
            allocate(page(3, w, h))
            page = int(mod(17 * k, 128), int8)
            page(:, 1:w / 2, 1:h / 3) = 120_int8
            job%printer = uri
            job%title = "fortui-system"
            job%media = caps%media(m)%name
            job%source = "rear"
            job%media_type = "photographic-glossy"
            job%quality = PWG_QUALITY_HIGH
            call print_page(job, page, caps%dpi / 4, res)
            call check(res%status == PRINT_OK .and. res%job_id > 0, "virtual job sent: " // &
                res%message)
            call pwg_begin(sent(k))
            call pwg_add_page(sent(k), page, caps%dpi / 4, media="na_index-4x6_4x6in", &
                quality=PWG_QUALITY_HIGH, media_type="photographic-glossy")
        end do
        col = received(dir, 1, "IPP_MEDIA_COL")
        call check(index(col, "x-dimension=10160 y-dimension=15240") > 0, &
            "borderless job: 4x6 in sheet (" // col // ")")
        call check(index(col, "media-bottom-margin=0 ") > 0 .and. &
            index(col, "media-left-margin=0 ") > 0 .and. &
            index(col, "media-right-margin=0 ") > 0 .and. &
            index(col, "media-top-margin=0") > 0, "borderless job: zero margins")
        call check(index(col, "media-source=rear") > 0 .and. &
            index(col, "media-type=photographic-glossy") > 0, "tray and media type")
        call check(received(dir, 1, "IPP_PRINT_QUALITY") == "high", "high quality")
        col = received(dir, 2, "IPP_MEDIA_COL")
        call check(index(col, "media-left-margin=340") > 0 .and. &
            index(col, "media-top-margin=500") > 0, "bordered job keeps margins (" // &
            col // ")")
        do k = 1, 2
            call check(same_bytes(dir // "/" // itoa(k) // "-fortui-system.pwg", sent(k)), &
                "job " // itoa(k) // " arrives byte for byte")
        end do
        9       call execute_command_line("kill $(cat " // dir // "/pid) 2> /dev/null")
        ! A failure leaves what the printer received for a look.
        if (failures == before) then
            call execute_command_line("rm -rf " // dir)
        else
            print '(a)', "print: virtual printer spool kept in " // dir
        end if
    end subroutine test_virtual_printer

    subroutine write_conf(path)
        character(*), intent(in) :: path
        integer :: u
        character(len=*), parameter :: m = "MEMBER integer media-"
        open (newunit=u, file=path, status="replace", action="write")
        write (u, '(a)') "ATTR keyword media-type-supported stationery,photographic-glossy"
        write (u, '(a)') "ATTR keyword media-source-supported main,rear"
        write (u, '(a)') "ATTR enum print-quality-supported 3,4,5"
        write (u, '(a)') "ATTR resolution pwg-raster-document-resolution-supported 300dpi,600dpi"
        write (u, '(a)') "ATTR keyword print-color-mode-supported monochrome,color"
        write (u, '(a)') "ATTR keyword media-col-supported media-bottom-margin," // &
            "media-left-margin,media-right-margin,media-size,media-source,media-top-margin," // &
            "media-type"
        write (u, '(a)') "ATTR collection media-size-supported " // size_(21000, 29700) // &
            "," // size_(10160, 15240) // "," // size_(12000, 12000) // "," // &
            size_(21010, 29690) // "," // size_(21590, 27940) // "," // size_(8900, 8900)
        write (u, '(a)') "ATTR collection media-col-database " // &
            sheet(21000, 29700, 500, 340, 340, 500, "", "") // "," // &
            sheet(10160, 15240, 500, 340, 340, 500, "", "") // "," // &
            sheet(10160, 15240, 0, 0, 0, 0, "", "") // "," // &
            sheet(12000, 12000, 10, 10, 10, 10, "", "") // "," // &
            sheet(10160, 15240, 0, 0, 0, 0, "rear", "photographic-glossy") // "," // &
            sheet(21010, 29690, 500, 340, 340, 500, "", "") // "," // &
            "{MEMBER collection media-size {MEMBER rangeOfInteger x-dimension 7620-21590 " // &
            "MEMBER rangeOfInteger y-dimension 12700-35560} " // m // "bottom-margin 500 " // &
            m // "left-margin 340 " // m // "right-margin 340 " // m // "top-margin 500}," // &
            sheet(21590, 27940, 500, 640, 630, 500, "", "stationery") // "," // &
            sheet(8900, 8900, 0, 0, 0, 0, "", "")
        write (u, '(a)') "ATTR collection media-col-ready " // &
            sheet(21000, 29700, 500, 340, 340, 500, "main", "stationery") // "," // &
            sheet(10160, 15240, 0, 0, 0, 0, "rear", "photographic-glossy")
        close (u)
    end subroutine write_conf

    function size_(w, l) result(s)
        integer, intent(in) :: w, l
        character(len=:), allocatable :: s
        s = "{MEMBER integer x-dimension " // itoa(w) // " MEMBER integer y-dimension " // &
            itoa(l) // "}"
    end function size_

    function sheet(w, l, b, le, ri, t, source, mtype) result(s)
        integer, intent(in) :: w, l, b, le, ri, t
        character(*), intent(in) :: source, mtype
        character(len=:), allocatable :: s
        character(len=*), parameter :: m = "MEMBER integer media-"
        s = "{MEMBER collection media-size {MEMBER integer x-dimension " // itoa(w) // &
            " MEMBER integer y-dimension " // itoa(l) // "} " // m // "bottom-margin " // &
            itoa(b) // " " // m // "left-margin " // itoa(le) // " " // m // &
            "right-margin " // itoa(ri) // " " // m // "top-margin " // itoa(t)
        if (len(source) > 0) s = s // " MEMBER keyword media-source " // source
        if (len(mtype) > 0) s = s // " MEMBER keyword media-type " // mtype
        s = s // "}"
    end function sheet

    logical function same_bytes(path, s)
        !! The file holds exactly the stream's bytes (waiting up to 10 s for it).
        character(*), intent(in) :: path
        type(pwg_stream_t), intent(in) :: s
        integer(int8), allocatable :: got(:)
        integer :: u, n, ios, tries
        logical :: there
        same_bytes = .false.
        do tries = 1, 100
            inquire (file=path, exist=there, size=n)
            if (there .and. n == s%n) exit
            call execute_command_line("sleep 0.1")
        end do
        if (.not. there .or. n /= s%n) return
        allocate(got(n))
        open (newunit=u, file=path, access="stream", form="unformatted", status="old", &
            action="read", iostat=ios)
        if (ios /= 0) return
        read (u, iostat=ios) got
        close (u)
        same_bytes = ios == 0 .and. all(got == s%bytes(1:n))
    end function same_bytes

    function received(spool, job_id, name) result(value)
        !! An attribute the virtual printer got for job `job_id`, waiting up to
        !! 30 s for test/system/keep-job.sh to write it.
        character(*), intent(in) :: spool, name
        integer, intent(in) :: job_id
        character(len=:), allocatable :: value, path
        character(len=4096) :: line
        integer :: tries, u, ios
        logical :: there

        value = ""
        path = spool // "/" // itoa(job_id) // "-fortui-system.pwg.attributes"
        do tries = 1, 300
            inquire (file=path, exist=there)
            if (there) then
                open (newunit=u, file=path, status="old", action="read")
                do
                    read (u, '(a)', iostat=ios) line
                    if (ios /= 0) exit
                    if (index(line, name // "=") == 1) value = trim(line(len(name) + 2:))
                end do
                close (u)
                if (len(value) > 0) return
            end if
            call execute_command_line("sleep 0.1")
        end do
    end function received

    logical function runs(command)
        character(*), intent(in) :: command
        integer :: code, st
        call execute_command_line(command, exitstat=code, cmdstat=st)
        runs = st == 0 .and. code == 0
    end function runs

    pure function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, '(i0)') i
        s = trim(buf)
    end function itoa

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
        call check(print_available(), "printing available")
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

end program test_print
