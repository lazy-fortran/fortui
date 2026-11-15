module fortui_print
    !! Printing service over IPP, in Fortran (fortui_ipp), through the local
    !! CUPS server or straight to a printer.
    !!
    !! An application lists printers, asks one for its capabilities (paper sizes
    !! with their margins and borderless variants, media types, trays, print
    !! qualities, raster resolution and, from the device itself, which paper is
    !! loaded where and the ink levels), and prints pages it composed as sRGB
    !! rasters. Pages travel as PWG raster at the printer's raster resolution, so
    !! the page raster alone decides scaling, cropping and borders: nothing is
    !! fitted or shrunk on the way.
    !!
    !! A printer is a CUPS queue name or an IPP printer URI ("ipp://host/ipp/print"),
    !! which is then printed to directly. The CUPS server is found as libcups
    !! finds it: CUPS_SERVER, then ServerName in ~/.cups/client.conf and
    !! /etc/cups/client.conf, then the local socket, then localhost:631. Paper
    !! sizes are named and ordered as libcups does (cupsGetDestMediaByIndex).
    !!
    !! Requests are blocking calls that return a result with a status; a caller
    !! that must not stall runs them between frames. Encrypted connections (ipps,
    !! https) are not made: a device reached only that way reports no live state.
    use iso_fortran_env, only: int8
    use fortui_ipp, only: ipp_msg_t, ipp_attr_t, ipp_request, ipp_attr, ipp_add, &
        ipp_value_str, ipp_value_int, ipp_value_col, ipp_find, ipp_str, ipp_int, &
        ipp_members, ipp_post, ipp_get, ipp_split_uri, ipp_user, IPP_OPERATION, IPP_JOB, &
        IPP_PRINTER, IPP_INTEGER, IPP_ENUM, IPP_RANGE, IPP_RESOLUTION, &
        IPP_BEGIN_COLLECTION, IPP_KEYWORD, IPP_NAME, IPP_MIME, IPP_PRINT_JOB, &
        IPP_CANCEL_JOB, IPP_GET_PRINTER_ATTRIBUTES, IPP_CUPS_GET_DEFAULT, &
        IPP_CUPS_GET_PRINTERS
    use fortui_pwg, only: pwg_stream_t, pwg_begin, pwg_add_page, PWG_QUALITY_DEFAULT, &
        PWG_QUALITY_DRAFT, PWG_QUALITY_NORMAL, PWG_QUALITY_HIGH
    use fortui_pwg_sizes, only: pwg_size_name, pwg_size_of
    implicit none
    private

    integer, parameter, public :: PRINT_OK = 0
    integer, parameter, public :: PRINT_UNSUPPORTED = 1
    integer, parameter, public :: PRINT_FAILED = 2

    public :: PWG_QUALITY_DEFAULT, PWG_QUALITY_DRAFT, PWG_QUALITY_NORMAL, PWG_QUALITY_HIGH

    type, public :: print_result_t
        integer :: status = PRINT_OK
        integer :: job_id = 0
        character(len=:), allocatable :: message
    end type print_result_t

    type, public :: print_printer_t
        character(len=:), allocatable :: name, info, location, make_model, device_uri
        logical :: is_default = .false.
    end type print_printer_t

    type, public :: print_media_t
        !! One paper size as the printer offers it. Sizes and margins are in
        !! hundredths of a millimetre; a borderless variant has zero margins.
        character(len=:), allocatable :: name, label
        integer :: width = 0, length = 0
        integer :: left = 0, right = 0, top = 0, bottom = 0
        logical :: borderless = .false.
        !! Paper of this size is loaded, in tray `source` with type `media_type`.
        logical :: loaded = .false.
        character(len=:), allocatable :: source, media_type
    end type print_media_t

    type, public :: print_choice_t
        !! An IPP keyword and the printer's own name for it.
        character(len=:), allocatable :: keyword, label
    end type print_choice_t

    type, public :: print_marker_t
        character(len=:), allocatable :: name
        integer :: level = -1
    end type print_marker_t

    type, public :: print_caps_t
        type(print_media_t), allocatable :: media(:)
        type(print_choice_t), allocatable :: media_types(:), sources(:)
        integer, allocatable :: qualities(:)
        type(print_marker_t), allocatable :: markers(:)
        !! Raster resolution pages are composed at.
        integer :: dpi = 300
        logical :: color = .true.
        !! Loaded paper and ink levels came from the device (not CUPS's cache).
        logical :: live = .false.
    end type print_caps_t

    type, public :: print_job_t
        character(len=:), allocatable :: printer, title
        !! PWG media name from print_caps_t%media (with "_borderless" for a
        !! borderless sheet), media-type and media-source keywords ("" = printer).
        character(len=:), allocatable :: media, media_type, source
        integer :: quality = PWG_QUALITY_DEFAULT
        integer :: copies = 1
        logical :: color = .true.
        !! Keep the job in the queue until released (job-hold-until=indefinite).
        logical :: hold = .false.
    end type print_job_t

    public :: print_available, print_printers, print_capabilities, print_page
    public :: print_cancel, print_page_pixels, print_media_label, print_apply_strings
    public :: print_keyword_label

    type :: target_t
        !! Where requests for a printer go: the server, the resource posted to
        !! and the printer-uri named in them.
        character(len=:), allocatable :: host, resource, uri
        integer :: port = 631
    end type target_t

    ! A printer on the local network answers within milliseconds; an absent one
    ! must not hold the application up.
    integer, parameter :: DEVICE_TIMEOUT_MS = 400
    ! Sending a page of tens of megabytes to a busy printer takes a while.
    integer, parameter :: JOB_TIMEOUT_MS = 120000
    character(len=*), parameter :: CAPABILITY_ATTRIBUTES(12) = [character(len=40) :: &
        "media-col-database", "media-supported", "media-type-supported", &
        "media-source-supported", "print-quality-supported", &
        "pwg-raster-document-resolution-supported", "printer-resolution-supported", &
        "print-color-mode-supported", "device-uri", "media-col-ready", "media-ready", &
        "printer-uri-supported"]

contains

    logical function print_available()
        !! Whether this build can print: always, where there are sockets.
        print_available = .true.
    end function print_available

    pure subroutine print_page_pixels(media, dpi, width, height, left, top, right, bottom)
        !! Page raster size of a sheet at `dpi`, and its margins in pixels.
        type(print_media_t), intent(in) :: media
        integer, intent(in) :: dpi
        integer, intent(out) :: width, height
        integer, intent(out), optional :: left, top, right, bottom

        width = nint(real(media%width) / 2540.0 * real(dpi))
        height = nint(real(media%length) / 2540.0 * real(dpi))
        if (present(left)) left = ceiling(real(media%left) / 2540.0 * real(dpi))
        if (present(top)) top = ceiling(real(media%top) / 2540.0 * real(dpi))
        if (present(right)) right = ceiling(real(media%right) / 2540.0 * real(dpi))
        if (present(bottom)) bottom = ceiling(real(media%bottom) / 2540.0 * real(dpi))
    end subroutine print_page_pixels

    subroutine print_printers(printers, res)
        !! The print queues of the CUPS server, the default one marked. One
        !! CUPS-Get-Printers request: no browsing of the network, so it takes
        !! milliseconds.
        type(print_printer_t), allocatable, intent(out) :: printers(:)
        type(print_result_t), intent(out) :: res
        type(ipp_msg_t) :: req, resp
        type(target_t) :: server
        character(len=:), allocatable :: error, default_name
        integer :: k, n, set

        res%message = ""
        server = cups_server()
        call ipp_request(req, IPP_CUPS_GET_PRINTERS)
        call ipp_add(req, ipp_attr(IPP_OPERATION, "requested-attributes", &
            ipp_value_str(IPP_KEYWORD, "printer-name"), &
            ipp_value_str(IPP_KEYWORD, "printer-info"), &
            ipp_value_str(IPP_KEYWORD, "printer-location"), &
            ipp_value_str(IPP_KEYWORD, "printer-make-and-model"), &
            ipp_value_str(IPP_KEYWORD, "device-uri")))
        call ipp_post(server%host, server%port, "/", req, resp, error)
        allocate(printers(0))
        if (len(error) > 0) then
            res%status = PRINT_FAILED
            res%message = "the print server does not answer (" // error // ")"
            return
        end if
        ! One printer per group; a group without printer-name is not one.
        set = -1
        n = 0
        do k = 1, resp%n
            if (resp%attrs(k)%group /= IPP_PRINTER) cycle
            if (resp%attrs(k)%set /= set) then
                set = resp%attrs(k)%set
                printers = [printers, print_printer_t("", "", "", "", "", .false.)]
                n = n + 1
            end if
            select case (resp%attrs(k)%name)
            case ("printer-name")
                printers(n)%name = ipp_str(resp%attrs(k), 1)
            case ("printer-info")
                printers(n)%info = ipp_str(resp%attrs(k), 1)
            case ("printer-location")
                printers(n)%location = ipp_str(resp%attrs(k), 1)
            case ("printer-make-and-model")
                printers(n)%make_model = ipp_str(resp%attrs(k), 1)
            case ("device-uri")
                printers(n)%device_uri = ipp_str(resp%attrs(k), 1)
            end select
        end do
        printers = pack(printers, [(len(printers(k)%name) > 0, k = 1, n)])
        if (size(printers) == 0) then
            res%message = "no printers are set up"
            return
        end if
        default_name = default_printer(server)
        do k = 1, size(printers)
            printers(k)%is_default = printers(k)%name == default_name
        end do
    end subroutine print_printers

    subroutine print_capabilities(printer, caps, res)
        !! What `printer` offers. Loaded paper and ink levels are asked from the
        !! device when its queue talks IPP to it, else taken from CUPS.
        character(*), intent(in) :: printer
        type(print_caps_t), intent(out) :: caps
        type(print_result_t), intent(out) :: res
        type(ipp_msg_t) :: resp
        type(target_t) :: where
        integer :: k, a
        character(len=:), allocatable :: device

        res%message = ""
        allocate(caps%media(0), caps%media_types(0), caps%sources(0), caps%qualities(0), &
            caps%markers(0))
        where = target_of(printer)
        call printer_attributes(where, CAPABILITY_ATTRIBUTES, resp, res, printer)
        if (res%status /= PRINT_OK) return
        call media_list(resp, caps%media)
        caps%media_types = choices(resp, "media-type-supported")
        caps%sources = choices(resp, "media-source-supported")
        a = ipp_find(resp%attrs, "print-quality-supported", resp%n)
        if (a > 0) caps%qualities = [(ipp_int(resp%attrs(a), k), k = 1, resp%attrs(a)%n)]
        a = ipp_find(resp%attrs, "pwg-raster-document-resolution-supported", resp%n)
        if (a == 0) a = ipp_find(resp%attrs, "printer-resolution-supported", resp%n)
        if (a > 0) then
            if (resp%attrs(a)%n > 0) caps%dpi = max(1, maxval(resp%attrs(a)%ints(1, &
                1:resp%attrs(a)%n)))
        end if
        a = ipp_find(resp%attrs, "print-color-mode-supported", resp%n)
        caps%color = .false.
        if (a > 0) caps%color = any([(ipp_str(resp%attrs(a), k) == "color", &
            k = 1, resp%attrs(a)%n)])

        ! The device itself: the printer when printed to directly, else the
        ! queue's device URI.
        if (index(printer, "://") > 0) then
            device = printer
        else
            device = string_attr(resp, "device-uri")
        end if
        if (index(device, "ipp://") == 1) call device_state(device, caps)
        if (.not. caps%live) call ready_from(resp, caps)
        do k = 1, size(caps%media_types)
            if (caps%media_types(k)%label == caps%media_types(k)%keyword) &
                caps%media_types(k)%label = print_keyword_label(caps%media_types(k)%keyword)
        end do
        do k = 1, size(caps%sources)
            if (caps%sources(k)%label == caps%sources(k)%keyword) &
                caps%sources(k)%label = print_keyword_label(caps%sources(k)%keyword)
        end do
    end subroutine print_capabilities

    subroutine print_page(job, rgb, dpi, res)
        !! Print one page composed as rgb(3, width, height) sRGB bytes covering the
        !! whole sheet of `job%media` at `dpi` (see print_page_pixels).
        type(print_job_t), intent(in) :: job
        integer(int8), intent(in) :: rgb(:, :, :)
        integer, intent(in) :: dpi
        type(print_result_t), intent(out) :: res
        type(pwg_stream_t) :: doc
        type(ipp_msg_t) :: req, resp
        type(target_t) :: where
        type(print_media_t), allocatable :: media(:)
        character(len=:), allocatable :: error
        integer :: k, m

        res%message = ""
        where = target_of(job%printer)
        call printer_attributes(where, [character(len=40) :: "media-col-database", &
            "media-supported"], resp, res, job%printer)
        if (res%status /= PRINT_OK) return
        call media_list(resp, media)
        call pwg_begin(doc)
        if (allocated(job%media_type)) then
            call pwg_add_page(doc, rgb, dpi, media=strip_borderless(job%media), &
                quality=job%quality, media_type=job%media_type)
        else
            call pwg_add_page(doc, rgb, dpi, media=strip_borderless(job%media), &
                quality=job%quality)
        end if

        call ipp_request(req, IPP_PRINT_JOB, where%uri)
        call ipp_add(req, ipp_attr(IPP_OPERATION, "requesting-user-name", &
            ipp_value_str(IPP_NAME, ipp_user())))
        call ipp_add(req, ipp_attr(IPP_OPERATION, "job-name", &
            ipp_value_str(IPP_NAME, title_of(job))))
        call ipp_add(req, ipp_attr(IPP_OPERATION, "document-format", &
            ipp_value_str(IPP_MIME, "image/pwg-raster")))
        ! The sheet goes as media-col with its size and margins: the name
        ! "..._borderless" means nothing to a printer, but zero margins in
        ! media-col select the borderless sheet (IPP and PPD queues alike).
        m = 0
        do k = 1, size(media)
            if (media(k)%name == job%media) then
                m = k
                exit
            end if
        end do
        if (m > 0) then
            call ipp_add(req, media_col(media(m), job))
        else
            call ipp_add(req, ipp_attr(IPP_JOB, "media", ipp_value_str(IPP_KEYWORD, job%media)))
            if (given(job%media_type)) call ipp_add(req, ipp_attr(IPP_JOB, "media-type", &
                ipp_value_str(IPP_KEYWORD, job%media_type)))
            if (given(job%source)) call ipp_add(req, ipp_attr(IPP_JOB, "media-source", &
                ipp_value_str(IPP_KEYWORD, job%source)))
        end if
        if (job%quality /= PWG_QUALITY_DEFAULT) call ipp_add(req, ipp_attr(IPP_JOB, &
            "print-quality", ipp_value_int(IPP_ENUM, job%quality)))
        call ipp_add(req, ipp_attr(IPP_JOB, "copies", ipp_value_int(IPP_INTEGER, &
            max(1, job%copies))))
        call ipp_add(req, ipp_attr(IPP_JOB, "print-color-mode", ipp_value_str(IPP_KEYWORD, &
            trim(merge("color     ", "monochrome", job%color)))))
        if (job%hold) call ipp_add(req, ipp_attr(IPP_JOB, "job-hold-until", &
            ipp_value_str(IPP_KEYWORD, "indefinite")))

        call ipp_post(where%host, where%port, where%resource, req, resp, error, &
            doc%bytes(1:doc%n), JOB_TIMEOUT_MS)
        if (len(error) > 0) then
            res%status = PRINT_FAILED
            res%message = "sending the page failed: " // error
        else if (resp%code > 255) then
            res%status = PRINT_FAILED
            res%message = "the printer refused the job: " // status_text(resp)
        else
            k = ipp_find(resp%attrs, "job-id", resp%n)
            if (k > 0) res%job_id = ipp_int(resp%attrs(k), 1)
            if (res%job_id <= 0) then
                res%status = PRINT_FAILED
                res%message = "the printer did not accept the page"
            end if
        end if
    end subroutine print_page

    subroutine print_cancel(printer, job_id, res)
        !! Cancel a job that is still queued.
        character(*), intent(in) :: printer
        integer, intent(in) :: job_id
        type(print_result_t), intent(out) :: res
        type(ipp_msg_t) :: req, resp
        type(target_t) :: where
        character(len=:), allocatable :: error

        res%message = ""
        where = target_of(printer)
        call ipp_request(req, IPP_CANCEL_JOB, where%uri)
        call ipp_add(req, ipp_attr(IPP_OPERATION, "job-id", ipp_value_int(IPP_INTEGER, job_id)))
        call ipp_add(req, ipp_attr(IPP_OPERATION, "requesting-user-name", &
            ipp_value_str(IPP_NAME, ipp_user())))
        call ipp_post(where%host, where%port, where%resource, req, resp, error)
        if (len(error) > 0) then
            res%status = PRINT_FAILED
            res%message = error
        else if (resp%code > 255) then
            res%status = PRINT_FAILED
            res%message = status_text(resp)
        end if
    end subroutine print_cancel

    pure function print_media_label(name, width, length) result(label)
        !! A readable name for a PWG media name such as "na_index-4x6_4x6in"
        !! ("4 x 6 in (10.2 x 15.2 cm)") or "iso_a4_210x297mm" ("A4, 210 x 297
        !! mm"); `width`/`length` are in hundredths of a millimetre.
        character(*), intent(in) :: name
        integer, intent(in) :: width, length
        character(len=:), allocatable :: label, base, kind, dims, unit
        character(len=32) :: cm
        integer :: a, b, x

        base = strip_borderless(name)
        a = index(base, "_")
        b = index(base, "_", back=.true.)
        if (a == 0 .or. b <= a) then
            label = base
            return
        end if
        kind = base(a + 1:b - 1)
        dims = base(b + 1:)
        unit = ""
        if (len(dims) > 2) unit = dims(len(dims) - 1:)
        if (unit == "in" .or. unit == "mm") then
            dims = dims(1:len(dims) - 2)
        else
            unit = ""
        end if
        x = index(dims, "x")
        if (x > 0) dims = dims(1:x - 1) // " x " // dims(x + 1:)
        label = dims
        if (len(unit) > 0) label = label // " " // unit
        if (unit == "in") then
            write (cm, '(f0.1," x ",f0.1," cm")') real(width) / 1000.0, real(length) / 1000.0
            label = label // " (" // trim(cm) // ")"
        end if
        if (base(1:a - 1) == "custom" .or. scan(kind, "0123456789") > 0 .and. &
            len(kind) > 3) return
        label = title_case(kind) // ", " // label
    end function print_media_label

    pure function print_keyword_label(keyword) result(label)
        !! A name for an IPP media-type or media-source keyword that neither CUPS
        !! nor the printer named: the registered meaning of common keywords,
        !! otherwise the keyword in words ("tray-2" -> "Tray 2").
        character(*), intent(in) :: keyword
        character(len=:), allocatable :: label

        select case (keyword)
        case ("stationery")
            label = "Plain paper"
        case ("photographic")
            label = "Photo paper"
        case ("photographic-glossy")
            label = "Glossy photo paper"
        case ("photographic-matte")
            label = "Matte photo paper"
        case ("photographic-semi-gloss")
            label = "Semi-gloss photo paper"
        case ("auto")
            label = "Automatic"
        case ("main", "rear", "front", "top", "bottom", "middle", "side", "left", "right")
            label = title_case(keyword) // " tray"
        case ("manual")
            label = "Manual feed"
        case ("by-pass-tray")
            label = "Bypass tray"
        case ("disc")
            label = "Disc tray"
        case default
            label = title_case(keyword)
            if (len(label) > 4) label = label(1:1) // lower(label(2:))
        end select
    end function print_keyword_label

    pure function lower(s) result(t)
        character(*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k, c
        t = s
        do k = 1, len(s)
            c = ichar(s(k:k))
            if (c >= ichar("A") .and. c <= ichar("Z")) t(k:k) = achar(c + 32)
        end do
    end function lower

    pure function title_case(word) result(t)
        !! "business-card" -> "Business Card"; short names ("a4", "dl") in capitals.
        character(*), intent(in) :: word
        character(len=:), allocatable :: t
        integer :: k, c

        t = word
        do k = 1, len(t)
            c = ichar(t(k:k))
            if (t(k:k) == "-") then
                t(k:k) = " "
            else if (c >= ichar("a") .and. c <= ichar("z") .and. (k == 1 .or. &
                    len(t) <= 3)) then
                t(k:k) = achar(c - 32)
            else if (c >= ichar("a") .and. c <= ichar("z") .and. t(max(1, k - 1):max(1, k - 1)) &
                    == " ") then
                t(k:k) = achar(c - 32)
            end if
        end do
    end function title_case

    subroutine print_apply_strings(caps, text)
        !! Names from a printer strings file (lines `"media-type.KEY" = "Name";`)
        !! for media types and trays that have no name yet.
        type(print_caps_t), intent(inout) :: caps
        character(*), intent(in) :: text
        integer :: p, e, q(4), k, j
        character(len=:), allocatable :: key, val

        p = 1
        do while (p <= len(text))
            e = index(text(p:), achar(10))
            if (e == 0) then
                e = len(text)
            else
                e = p + e - 1
            end if
            q = 0
            k = p
            do j = 1, 4
                if (k > e) exit
                if (index(text(k:e), '"') == 0) exit
                q(j) = k + index(text(k:e), '"') - 1
                k = q(j) + 1
            end do
            if (all(q > 0)) then
                ! The value runs to the last quote on the line.
                q(4) = p + index(text(p:e), '"', back=.true.) - 1
                key = text(q(1) + 1:q(2) - 1)
                val = text(q(3) + 1:q(4) - 1)
                if (index(key, "media-type.") == 1) then
                    call name_choice(caps%media_types, key(12:), val)
                else if (index(key, "media-source.") == 1) then
                    call name_choice(caps%sources, key(14:), val)
                end if
            end if
            p = e + 1
        end do
    contains
        subroutine name_choice(list, keyword, label)
            type(print_choice_t), intent(inout) :: list(:)
            character(*), intent(in) :: keyword, label
            integer :: i
            do i = 1, size(list)
                if (list(i)%keyword == keyword .and. list(i)%label == keyword) &
                    list(i)%label = label
            end do
        end subroutine name_choice
    end subroutine print_apply_strings

    pure function strip_borderless(media) result(base)
        character(*), intent(in) :: media
        character(len=:), allocatable :: base
        integer :: k
        k = index(media, "_borderless", back=.true.)
        if (k > 0 .and. k + 10 == len(media)) then
            base = media(1:k - 1)
        else
            base = media
        end if
    end function strip_borderless

    function title_of(job) result(t)
        type(print_job_t), intent(in) :: job
        character(len=:), allocatable :: t
        t = "FortUI page"
        if (allocated(job%title)) then
            if (len(job%title) > 0) t = job%title
        end if
    end function title_of

    ! --- where requests go ---------------------------------------------------------

    function cups_server() result(t)
        !! The CUPS server as libcups finds it.
        type(target_t) :: t
        character(len=:), allocatable :: name
        logical :: there
        integer :: c, ios

        name = env("CUPS_SERVER")
        if (len(name) == 0) name = conf_value(env("HOME") // "/.cups/client.conf", "ServerName")
        if (len(name) == 0) name = conf_value("/etc/cups/client.conf", "ServerName")
        if (len(name) == 0) then
            inquire (file="/run/cups/cups.sock", exist=there)
            if (there) then
                name = "/run/cups/cups.sock"
            else
                inquire (file="/var/run/cups/cups.sock", exist=there)
                name = "localhost"
                if (there) name = "/var/run/cups/cups.sock"
            end if
        end if
        t%host = name
        t%port = 631
        t%resource = "/"
        t%uri = "ipp://localhost/"
        if (name(1:1) == "/") return
        c = index(name, ":", back=.true.)
        if (c > 0 .and. index(name, "]") < c) then
            read (name(c + 1:), *, iostat=ios) t%port
            if (ios /= 0) t%port = 631
            t%host = name(1:c - 1)
        end if
        if (t%host(1:1) == "[") t%host = t%host(2:len(t%host) - 1)
    end function cups_server

    function target_of(printer) result(t)
        !! A queue of the CUPS server, or a printer URI to print to directly.
        character(*), intent(in) :: printer
        type(target_t) :: t
        character(len=:), allocatable :: scheme
        if (index(printer, "://") > 0) then
            call ipp_split_uri(printer, scheme, t%host, t%port, t%resource)
            t%uri = printer
            ! ipps is not spoken; the request then fails to connect.
            if (scheme /= "ipp") t%host = ""
            return
        end if
        t = cups_server()
        t%resource = "/printers/" // printer
        t%uri = "ipp://localhost/printers/" // printer
    end function target_of

    function default_printer(server) result(name)
        !! The user's default as libcups picks it: LPDEST, PRINTER, the Default
        !! line of ~/.cups/lpoptions and /etc/cups/lpoptions, then the server's.
        type(target_t), intent(in) :: server
        character(len=:), allocatable :: name
        type(ipp_msg_t) :: req, resp
        character(len=:), allocatable :: error
        integer :: k

        name = env("LPDEST")
        if (len(name) == 0) then
            name = env("PRINTER")
            if (name == "lp") name = ""
        end if
        if (len(name) == 0) name = conf_value(env("HOME") // "/.cups/lpoptions", "Default")
        if (len(name) == 0) name = conf_value("/etc/cups/lpoptions", "Default")
        if (len(name) == 0) then
            call ipp_request(req, IPP_CUPS_GET_DEFAULT)
            call ipp_add(req, ipp_attr(IPP_OPERATION, "requested-attributes", &
                ipp_value_str(IPP_KEYWORD, "printer-name")))
            call ipp_post(server%host, server%port, "/", req, resp, error)
            if (len(error) == 0 .and. resp%code <= 255) name = string_attr(resp, "printer-name")
        end if
        ! "name/instance": the queue is the name.
        k = index(name, "/")
        if (k > 0) name = name(1:k - 1)
        k = index(name, " ")
        if (k > 0) name = name(1:k - 1)
    end function default_printer

    subroutine printer_attributes(where, names, resp, res, printer)
        !! Get-Printer-Attributes for the given attribute names.
        type(target_t), intent(in) :: where
        character(*), intent(in) :: names(:), printer
        type(ipp_msg_t), intent(out) :: resp
        type(print_result_t), intent(inout) :: res
        type(ipp_msg_t) :: req
        type(ipp_attr_t) :: want
        character(len=:), allocatable :: error
        integer :: k

        call ipp_request(req, IPP_GET_PRINTER_ATTRIBUTES, where%uri)
        want = ipp_attr(IPP_OPERATION, "requested-attributes", &
            ipp_value_str(IPP_KEYWORD, trim(names(1))))
        do k = 2, size(names)
            want = ipp_attr(IPP_OPERATION, "requested-attributes", want, &
                ipp_value_str(IPP_KEYWORD, trim(names(k))))
        end do
        call ipp_add(req, want)
        if (len(where%host) == 0) then
            res%status = PRINT_FAILED
            res%message = "only ipp:// printers can be reached directly"
            return
        end if
        call ipp_post(where%host, where%port, where%resource, req, resp, error)
        if (len(error) > 0) then
            res%status = PRINT_FAILED
            res%message = "the printer does not answer (" // error // ")"
        else if (resp%code == int(z'0406') .or. (resp%code > 255 .and. &
                index(printer, "://") == 0)) then
            res%status = PRINT_FAILED
            res%message = "no printer named '" // printer // "'"
        else if (resp%code > 255) then
            res%status = PRINT_FAILED
            res%message = status_text(resp)
        end if
    end subroutine printer_attributes

    ! --- reading capabilities -------------------------------------------------------

    subroutine media_list(resp, media)
        !! The sheets of media-col-database as cupsGetDestMediaByIndex lists them:
        !! sorted by size (stable), named by size, source and type, "_borderless"
        !! for zero margins; without a database the media-supported names with
        !! default margins. Custom size ranges are not sheets.
        type(ipp_msg_t), intent(in) :: resp
        type(print_media_t), allocatable, intent(out) :: media(:)
        type(ipp_attr_t), allocatable :: col(:)
        type(print_media_t) :: s
        character(len=:), allocatable :: key, source, mtype
        integer :: a, k, w, l, x, y

        allocate(media(0))
        a = ipp_find(resp%attrs, "media-col-database", resp%n)
        if (a > 0) then
            do k = 1, resp%attrs(a)%n
                if (resp%attrs(a)%tags(k) /= IPP_BEGIN_COLLECTION) cycle
                col = ipp_members(resp%attrs(a), k)
                if (.not. sheet_size(col, w, l)) cycle
                s = print_media_t()
                s%width = w
                s%length = l
                s%bottom = member_int(col, "media-bottom-margin")
                s%left = member_int(col, "media-left-margin")
                s%right = member_int(col, "media-right-margin")
                s%top = member_int(col, "media-top-margin")
                key = member_str(col, "media-key")
                if (len(key) == 0) then
                    key = member_str(col, "media-size-name")
                    if (len(key) == 0) key = pwg_size_name(w, l)
                    source = member_str(col, "media-source")
                    mtype = member_str(col, "media-type")
                    if (len(source) > 0) key = key // "_" // source
                    if (len(mtype) > 0) key = key // "_" // mtype
                    if (all([s%bottom, s%left, s%right, s%top] == 0)) &
                        key = key // "_borderless"
                end if
                s%name = key
                call insert(s)
            end do
        else
            a = ipp_find(resp%attrs, "media-supported", resp%n)
            if (a == 0) return
            do k = 1, resp%attrs(a)%n
                key = ipp_str(resp%attrs(a), k)
                if (index(key, "custom_min_") == 1 .or. index(key, "custom_max_") == 1) cycle
                call pwg_size_of(key, x, y)
                if (x <= 0 .or. y <= 0) cycle
                s = print_media_t(name=key, width=x, length=y, left=635, right=635, &
                    top=1270, bottom=1270)
                call insert(s)
            end do
        end if
        do k = 1, size(media)
            media(k)%borderless = max(media(k)%left, media(k)%right, media(k)%top, &
                media(k)%bottom) == 0
            media(k)%label = print_media_label(media(k)%name, media(k)%width, media(k)%length)
            media(k)%source = ""
            media(k)%media_type = ""
        end do
    contains
        subroutine insert(s)
            !! After every sheet of the same or a smaller size.
            type(print_media_t), intent(in) :: s
            integer :: at
            at = size(media) + 1
            do while (at > 1)
                if (media(at - 1)%width < s%width .or. (media(at - 1)%width == s%width &
                    .and. media(at - 1)%length <= s%length)) exit
                at = at - 1
            end do
            media = [media(1:at - 1), s, media(at:)]
        end subroutine insert
    end subroutine media_list

    logical function sheet_size(col, w, l) result(fixed)
        !! The fixed size of a media-col (a roll counts with its longest length).
        type(ipp_attr_t), intent(in) :: col(:)
        integer, intent(out) :: w, l
        type(ipp_attr_t), allocatable :: sz(:)
        integer :: m, x, y
        fixed = .false.
        w = 0
        l = 0
        m = ipp_find(col, "media-size")
        if (m == 0) return
        if (col(m)%n == 0) return
        if (col(m)%tags(1) /= IPP_BEGIN_COLLECTION) return
        sz = ipp_members(col(m), 1)
        x = ipp_find(sz, "x-dimension")
        y = ipp_find(sz, "y-dimension")
        if (x == 0 .or. y == 0) return
        if (sz(x)%tags(1) /= IPP_INTEGER) return
        w = ipp_int(sz(x), 1)
        if (sz(y)%tags(1) == IPP_INTEGER) then
            l = ipp_int(sz(y), 1)
        else if (sz(y)%tags(1) == IPP_RANGE) then
            l = ipp_int(sz(y), 1, 2)
        else
            return
        end if
        fixed = .true.
    end function sheet_size

    integer function member_int(col, name) result(v)
        type(ipp_attr_t), intent(in) :: col(:)
        character(*), intent(in) :: name
        integer :: m
        v = 0
        m = ipp_find(col, name)
        if (m == 0) return
        if (col(m)%n > 0) then
            if (col(m)%tags(1) == IPP_INTEGER) v = ipp_int(col(m), 1)
        end if
    end function member_int

    function member_str(col, name) result(v)
        !! A keyword or name member ("" for none or another type).
        type(ipp_attr_t), intent(in) :: col(:)
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        integer :: m
        v = ""
        m = ipp_find(col, name)
        if (m == 0) return
        if (col(m)%n == 0) return
        select case (col(m)%tags(1))
        case (IPP_KEYWORD, IPP_NAME, int(z'36'))
            v = ipp_str(col(m), 1)
        end select
    end function member_str

    function choices(resp, name) result(list)
        !! Supported keywords of `name`, each named by itself for now.
        type(ipp_msg_t), intent(in) :: resp
        character(*), intent(in) :: name
        type(print_choice_t), allocatable :: list(:)
        integer :: a, k
        a = ipp_find(resp%attrs, name, resp%n)
        if (a == 0) then
            allocate(list(0))
            return
        end if
        allocate(list(resp%attrs(a)%n))
        do k = 1, size(list)
            list(k)%keyword = ipp_str(resp%attrs(a), k)
            list(k)%label = list(k)%keyword
        end do
    end function choices

    function string_attr(resp, name) result(v)
        type(ipp_msg_t), intent(in) :: resp
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        integer :: a
        a = ipp_find(resp%attrs, name, resp%n)
        v = ""
        if (a > 0) v = ipp_str(resp%attrs(a), 1)
    end function string_attr

    subroutine ready_from(resp, caps)
        !! Loaded paper as CUPS last heard it (no tray or type).
        type(ipp_msg_t), intent(in) :: resp
        type(print_caps_t), intent(inout) :: caps
        type(ipp_attr_t), allocatable :: col(:)
        integer :: a, k, w, l
        a = ipp_find(resp%attrs, "media-col-ready", resp%n)
        if (a > 0) then
            do k = 1, resp%attrs(a)%n
                if (resp%attrs(a)%tags(k) /= IPP_BEGIN_COLLECTION) cycle
                col = ipp_members(resp%attrs(a), k)
                if (sheet_size(col, w, l)) call mark_loaded(caps, w, l, "", "")
            end do
            return
        end if
        a = ipp_find(resp%attrs, "media-ready", resp%n)
        if (a == 0) return
        do k = 1, resp%attrs(a)%n
            call pwg_size_of(ipp_str(resp%attrs(a), k), w, l)
            if (w > 0) call mark_loaded(caps, w, l, "", "")
        end do
    end subroutine ready_from

    subroutine mark_loaded(caps, width, length, source, media_type)
        !! Every variant of a size within 1 mm counts as loaded.
        type(print_caps_t), intent(inout) :: caps
        integer, intent(in) :: width, length
        character(*), intent(in) :: source, media_type
        integer :: k

        do k = 1, size(caps%media)
            if (abs(caps%media(k)%width - width) > 100 .or. &
                abs(caps%media(k)%length - length) > 100) cycle
            caps%media(k)%loaded = .true.
            if (len(caps%media(k)%source) == 0) caps%media(k)%source = source
            if (len(caps%media(k)%media_type) == 0) caps%media(k)%media_type = media_type
        end do
    end subroutine mark_loaded

    subroutine device_state(uri, caps)
        !! Get-Printer-Attributes from the device: media-col-ready and markers.
        character(*), intent(in) :: uri
        type(print_caps_t), intent(inout) :: caps
        type(ipp_msg_t) :: req, resp
        type(ipp_attr_t), allocatable :: col(:)
        character(len=:), allocatable :: scheme, host, resource, error
        integer :: port, a, b, k, n, w, l

        call ipp_split_uri(uri, scheme, host, port, resource)
        if (scheme /= "ipp" .or. len(host) == 0) return
        call ipp_request(req, IPP_GET_PRINTER_ATTRIBUTES, uri)
        call ipp_add(req, ipp_attr(IPP_OPERATION, "requested-attributes", &
            ipp_value_str(IPP_KEYWORD, "media-col-ready"), &
            ipp_value_str(IPP_KEYWORD, "marker-names"), &
            ipp_value_str(IPP_KEYWORD, "marker-levels"), &
            ipp_value_str(IPP_KEYWORD, "printer-strings-uri")))
        call ipp_post(host, port, resource, req, resp, error, timeout_ms=DEVICE_TIMEOUT_MS)
        if (len(error) > 0 .or. resp%code > 255) return
        a = ipp_find(resp%attrs, "media-col-ready", resp%n)
        caps%live = a > 0
        if (a > 0) then
            do k = 1, resp%attrs(a)%n
                if (resp%attrs(a)%tags(k) /= IPP_BEGIN_COLLECTION) cycle
                col = ipp_members(resp%attrs(a), k)
                if (sheet_size(col, w, l)) call mark_loaded(caps, w, l, &
                    member_str(col, "media-source"), member_str(col, "media-type"))
            end do
        end if
        a = ipp_find(resp%attrs, "marker-names", resp%n)
        b = ipp_find(resp%attrs, "marker-levels", resp%n)
        if (a > 0 .and. b > 0) then
            n = min(resp%attrs(a)%n, resp%attrs(b)%n)
            deallocate(caps%markers)
            allocate(caps%markers(n))
            do k = 1, n
                caps%markers(k)%name = ipp_str(resp%attrs(a), k)
                caps%markers(k)%level = ipp_int(resp%attrs(b), k)
            end do
        end if
        call load_strings(string_attr(resp, "printer-strings-uri"), caps)
    end subroutine device_state

    subroutine load_strings(uri, caps)
        !! Fetch the printer's strings file (IPP Everywhere printer-strings-uri)
        !! and take its names for media types and trays.
        character(*), intent(in) :: uri
        type(print_caps_t), intent(inout) :: caps
        character(len=:), allocatable :: scheme, host, resource, text, error
        integer :: port

        if (index(uri, "http://") /= 1) return
        call ipp_split_uri(uri, scheme, host, port, resource)
        call ipp_get(host, port, resource, text, error, DEVICE_TIMEOUT_MS)
        if (len(error) == 0 .and. len(text) > 0 .and. len(text) <= 4 * 1024 * 1024) &
            call print_apply_strings(caps, text)
    end subroutine load_strings

    ! --- jobs ---------------------------------------------------------------------

    function media_col(sheet, job) result(a)
        !! The media-col job attribute of a sheet, with the job's tray and type.
        type(print_media_t), intent(in) :: sheet
        type(print_job_t), intent(in) :: job
        type(ipp_attr_t) :: a
        type(ipp_attr_t) :: size_, members(4)
        size_ = ipp_attr(0, "media-size", ipp_value_col( &
            ipp_attr(0, "x-dimension", ipp_value_int(IPP_INTEGER, sheet%width)), &
            ipp_attr(0, "y-dimension", ipp_value_int(IPP_INTEGER, sheet%length))))
        members(1) = ipp_attr(0, "media-bottom-margin", ipp_value_int(IPP_INTEGER, sheet%bottom))
        members(2) = ipp_attr(0, "media-left-margin", ipp_value_int(IPP_INTEGER, sheet%left))
        members(3) = ipp_attr(0, "media-right-margin", ipp_value_int(IPP_INTEGER, sheet%right))
        members(4) = ipp_attr(0, "media-top-margin", ipp_value_int(IPP_INTEGER, sheet%top))
        if (given(job%source) .and. given(job%media_type)) then
            a = ipp_attr(IPP_JOB, "media-col", ipp_value_col(size_, members(1), members(2), &
                members(3), members(4), &
                ipp_attr(0, "media-source", ipp_value_str(IPP_KEYWORD, job%source)), &
                ipp_attr(0, "media-type", ipp_value_str(IPP_KEYWORD, job%media_type))))
        else if (given(job%source)) then
            a = ipp_attr(IPP_JOB, "media-col", ipp_value_col(size_, members(1), members(2), &
                members(3), members(4), &
                ipp_attr(0, "media-source", ipp_value_str(IPP_KEYWORD, job%source))))
        else if (given(job%media_type)) then
            a = ipp_attr(IPP_JOB, "media-col", ipp_value_col(size_, members(1), members(2), &
                members(3), members(4), &
                ipp_attr(0, "media-type", ipp_value_str(IPP_KEYWORD, job%media_type))))
        else
            a = ipp_attr(IPP_JOB, "media-col", ipp_value_col(size_, members(1), members(2), &
                members(3), members(4)))
        end if
    end function media_col

    function status_text(resp) result(t)
        !! The server's status-message, else the IPP status code.
        type(ipp_msg_t), intent(in) :: resp
        character(len=:), allocatable :: t
        character(len=24) :: buf
        t = string_attr(resp, "status-message")
        if (len(t) > 0) return
        write (buf, '("IPP status 0x",z4.4)') resp%code
        t = trim(buf)
    end function status_text

    logical function given(s)
        character(len=:), allocatable, intent(in) :: s
        given = .false.
        if (allocated(s)) given = len(s) > 0
    end function given

    ! --- configuration --------------------------------------------------------------

    function env(name) result(v)
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        integer :: n, st
        call get_environment_variable(name, length=n, status=st)
        allocate(character(len=max(n, 0)) :: v)
        if (st == 0 .and. n > 0) call get_environment_variable(name, v)
        if (st /= 0) v = ""
    end function env

    function conf_value(path, key) result(v)
        !! The value after `key` on its line in a CUPS configuration file.
        character(*), intent(in) :: path, key
        character(len=:), allocatable :: v
        character(len=1024) :: line
        integer :: u, ios
        logical :: there
        v = ""
        inquire (file=path, exist=there)
        if (.not. there) return
        open (newunit=u, file=path, status="old", action="read", iostat=ios)
        if (ios /= 0) return
        do
            read (u, '(a)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (index(line, key // " ") == 1 .or. index(line, key // achar(9)) == 1) then
                v = trim(adjustl(line(len(key) + 2:)))
            end if
        end do
        close (u)
    end function conf_value

end module fortui_print
