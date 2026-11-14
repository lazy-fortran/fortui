module fortui_print
    !! Printing service over CUPS (libcups through iso_c_binding).
    !!
    !! An application lists printers, asks one for its capabilities (paper sizes
    !! with their margins and borderless variants, media types, trays, print
    !! qualities, raster resolution and, from the device itself, which paper is
    !! loaded where and the ink levels), and prints pages it composed as sRGB
    !! rasters. Pages travel as PWG raster at the printer's raster resolution, so
    !! the page raster alone decides scaling, cropping and borders: nothing is
    !! fitted or shrunk on the way.
    !!
    !! Requests are blocking calls that return a result with a status; a caller
    !! that must not stall runs them between frames. Built without
    !! -DENABLE_PRINT=1 (and -lcups), every request returns PRINT_UNSUPPORTED.
    use iso_c_binding
    use iso_fortran_env, only: int8
    use fortui_pwg, only: pwg_stream_t, pwg_begin, pwg_add_page, PWG_QUALITY_DEFAULT, &
        PWG_QUALITY_DRAFT, PWG_QUALITY_NORMAL, PWG_QUALITY_HIGH
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

#ifdef ENABLE_PRINT
    type, bind(C) :: cups_dest_t
        type(c_ptr) :: name, instance
        integer(c_int) :: is_default, num_options
        type(c_ptr) :: options
    end type cups_dest_t

    type, bind(C) :: cups_size_t
        character(kind=c_char) :: media(128)
        integer(c_int) :: width, length, bottom, left, right, top
    end type cups_size_t

    integer(c_int), parameter :: MEDIA_FLAGS_DEFAULT = 0, MEDIA_FLAGS_READY = 8
    integer(c_int), parameter :: HTTP_STATUS_CONTINUE = 100, HTTP_STATUS_OK = 200
    integer(c_int), parameter :: IPP_OP_GET_PRINTER_ATTRIBUTES = int(z'000B', c_int)
    integer(c_int), parameter :: IPP_TAG_ZERO = 0, IPP_TAG_OPERATION = 1
    integer(c_int), parameter :: IPP_TAG_INTEGER = int(z'21', c_int)
    integer(c_int), parameter :: IPP_TAG_BEGIN_COLLECTION = int(z'34', c_int)
    integer(c_int), parameter :: IPP_TAG_KEYWORD = int(z'44', c_int)
    integer(c_int), parameter :: IPP_TAG_URI = int(z'45', c_int)
    integer(c_int), parameter :: HTTP_URI_CODING_ALL = 15
    integer(c_int), parameter :: HTTP_ENCRYPTION_IF_REQUESTED = 0, &
        HTTP_ENCRYPTION_ALWAYS = 3

    interface
        integer(c_size_t) function c_strlen(s) bind(C, name="strlen")
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
        end function
        integer(c_int) function cupsGetDests(dests) bind(C, name="cupsGetDests")
            import :: c_ptr, c_int
            type(c_ptr) :: dests
        end function
        subroutine cupsFreeDests(n, dests) bind(C, name="cupsFreeDests")
            import :: c_ptr, c_int
            integer(c_int), value :: n
            type(c_ptr), value :: dests
        end subroutine
        type(c_ptr) function cupsGetNamedDest(http, name, instance) &
                bind(C, name="cupsGetNamedDest")
            import :: c_ptr, c_char
            type(c_ptr), value :: http
            character(kind=c_char), intent(in) :: name(*)
            type(c_ptr), value :: instance
        end function
        type(c_ptr) function cupsGetOption(name, n, options) bind(C, name="cupsGetOption")
            import :: c_ptr, c_char, c_int
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: n
            type(c_ptr), value :: options
        end function
        integer(c_int) function cupsAddOption(name, value, n, options) &
                bind(C, name="cupsAddOption")
            import :: c_ptr, c_char, c_int
            character(kind=c_char), intent(in) :: name(*), value(*)
            integer(c_int), value :: n
            type(c_ptr) :: options
        end function
        subroutine cupsFreeOptions(n, options) bind(C, name="cupsFreeOptions")
            import :: c_ptr, c_int
            integer(c_int), value :: n
            type(c_ptr), value :: options
        end subroutine
        type(c_ptr) function cupsCopyDestInfo(http, dest) bind(C, name="cupsCopyDestInfo")
            import :: c_ptr
            type(c_ptr), value :: http, dest
        end function
        subroutine cupsFreeDestInfo(info) bind(C, name="cupsFreeDestInfo")
            import :: c_ptr
            type(c_ptr), value :: info
        end subroutine
        integer(c_int) function cupsGetDestMediaCount(http, dest, info, flags) &
                bind(C, name="cupsGetDestMediaCount")
            import :: c_ptr, c_int
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: flags
        end function
        integer(c_int) function cupsGetDestMediaByIndex(http, dest, info, n, flags, &
                size) bind(C, name="cupsGetDestMediaByIndex")
            import :: c_ptr, c_int, cups_size_t
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: n, flags
            type(cups_size_t) :: size
        end function
        type(c_ptr) function cupsLocalizeDestMedia(http, dest, info, flags, size) &
                bind(C, name="cupsLocalizeDestMedia")
            import :: c_ptr, c_int, cups_size_t
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: flags
            type(cups_size_t) :: size
        end function
        type(c_ptr) function cupsLocalizeDestValue(http, dest, info, option, value) &
                bind(C, name="cupsLocalizeDestValue")
            import :: c_ptr, c_char
            type(c_ptr), value :: http, dest, info
            character(kind=c_char), intent(in) :: option(*), value(*)
        end function
        type(c_ptr) function cupsFindDestSupported(http, dest, info, option) &
                bind(C, name="cupsFindDestSupported")
            import :: c_ptr, c_char
            type(c_ptr), value :: http, dest, info
            character(kind=c_char), intent(in) :: option(*)
        end function
        integer(c_int) function ippGetCount(attr) bind(C, name="ippGetCount")
            import :: c_ptr, c_int
            type(c_ptr), value :: attr
        end function
        type(c_ptr) function ippGetString(attr, element, language) &
                bind(C, name="ippGetString")
            import :: c_ptr, c_int
            type(c_ptr), value :: attr
            integer(c_int), value :: element
            type(c_ptr), value :: language
        end function
        integer(c_int) function ippGetInteger(attr, element) bind(C, name="ippGetInteger")
            import :: c_ptr, c_int
            type(c_ptr), value :: attr
            integer(c_int), value :: element
        end function
        integer(c_int) function ippGetResolution(attr, element, yres, units) &
                bind(C, name="ippGetResolution")
            import :: c_ptr, c_int
            type(c_ptr), value :: attr
            integer(c_int), value :: element
            integer(c_int) :: yres, units
        end function
        type(c_ptr) function ippGetCollection(attr, element) &
                bind(C, name="ippGetCollection")
            import :: c_ptr, c_int
            type(c_ptr), value :: attr
            integer(c_int), value :: element
        end function
        type(c_ptr) function ippFindAttribute(ipp, name, tag) &
                bind(C, name="ippFindAttribute")
            import :: c_ptr, c_char, c_int
            type(c_ptr), value :: ipp
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: tag
        end function
        type(c_ptr) function ippNewRequest(op) bind(C, name="ippNewRequest")
            import :: c_ptr, c_int
            integer(c_int), value :: op
        end function
        type(c_ptr) function ippAddString(ipp, group, tag, name, language, value) &
                bind(C, name="ippAddString")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: ipp
            integer(c_int), value :: group, tag
            character(kind=c_char), intent(in) :: name(*)
            type(c_ptr), value :: language
            character(kind=c_char), intent(in) :: value(*)
        end function
        type(c_ptr) function ippAddStrings(ipp, group, tag, name, n, language, values) &
                bind(C, name="ippAddStrings")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: ipp
            integer(c_int), value :: group, tag
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: n
            type(c_ptr), value :: language
            type(c_ptr), intent(in) :: values(*)
        end function
        subroutine ippDelete(ipp) bind(C, name="ippDelete")
            import :: c_ptr
            type(c_ptr), value :: ipp
        end subroutine
        type(c_ptr) function cupsDoRequest(http, request, resource) &
                bind(C, name="cupsDoRequest")
            import :: c_ptr, c_char
            type(c_ptr), value :: http, request
            character(kind=c_char), intent(in) :: resource(*)
        end function
        integer(c_int) function httpSeparateURI(decoding, uri, scheme, slen, user, ulen, &
                host, hlen, port, resource, rlen) bind(C, name="httpSeparateURI")
            import :: c_int, c_char
            integer(c_int), value :: decoding, slen, ulen, hlen, rlen
            character(kind=c_char), intent(in) :: uri(*)
            character(kind=c_char) :: scheme(*), user(*), host(*), resource(*)
            integer(c_int) :: port
        end function
        type(c_ptr) function httpConnect2(host, port, addrlist, family, encryption, &
                blocking, msec, cancel) bind(C, name="httpConnect2")
            import :: c_ptr, c_int, c_char
            character(kind=c_char), intent(in) :: host(*)
            integer(c_int), value :: port, family, encryption, blocking, msec
            type(c_ptr), value :: addrlist, cancel
        end function
        subroutine httpClearFields(http) bind(C, name="httpClearFields")
            import :: c_ptr
            type(c_ptr), value :: http
        end subroutine
        integer(c_int) function httpGet(http, resource) bind(C, name="httpGet")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: http
            character(kind=c_char), intent(in) :: resource(*)
        end function
        integer(c_int) function httpUpdate(http) bind(C, name="httpUpdate")
            import :: c_ptr, c_int
            type(c_ptr), value :: http
        end function
        integer(c_intptr_t) function httpRead2(http, buffer, length) &
                bind(C, name="httpRead2")
            import :: c_ptr, c_intptr_t, c_size_t, c_char
            type(c_ptr), value :: http
            character(kind=c_char) :: buffer(*)
            integer(c_size_t), value :: length
        end function
        subroutine httpClose(http) bind(C, name="httpClose")
            import :: c_ptr
            type(c_ptr), value :: http
        end subroutine
        integer(c_int) function cupsCreateDestJob(http, dest, info, job_id, title, n, &
                options) bind(C, name="cupsCreateDestJob")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: http, dest, info
            integer(c_int) :: job_id
            character(kind=c_char), intent(in) :: title(*)
            integer(c_int), value :: n
            type(c_ptr), value :: options
        end function
        integer(c_int) function cupsStartDestDocument(http, dest, info, job_id, docname, &
                format, n, options, last) bind(C, name="cupsStartDestDocument")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: job_id, n, last
            character(kind=c_char), intent(in) :: docname(*), format(*)
            type(c_ptr), value :: options
        end function
        integer(c_int) function cupsWriteRequestData(http, buffer, length) &
                bind(C, name="cupsWriteRequestData")
            import :: c_ptr, c_int, c_size_t
            type(c_ptr), value :: http, buffer
            integer(c_size_t), value :: length
        end function
        integer(c_int) function cupsFinishDestDocument(http, dest, info) &
                bind(C, name="cupsFinishDestDocument")
            import :: c_ptr, c_int
            type(c_ptr), value :: http, dest, info
        end function
        integer(c_int) function cupsCancelDestJob(http, dest, job_id) &
                bind(C, name="cupsCancelDestJob")
            import :: c_ptr, c_int
            type(c_ptr), value :: http, dest
            integer(c_int), value :: job_id
        end function
        type(c_ptr) function cupsLastErrorString() bind(C, name="cupsLastErrorString")
            import :: c_ptr
        end function
    end interface
#endif

contains

    logical function print_available()
        !! Whether this build can print (compiled with -DENABLE_PRINT=1).
#ifdef ENABLE_PRINT
        print_available = .true.
#else
        print_available = .false.
#endif
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

    subroutine unsupported(res)
        type(print_result_t), intent(out) :: res
        res%status = PRINT_UNSUPPORTED
        res%message = "this program was built without printing (-DENABLE_PRINT=1, -lcups)"
    end subroutine unsupported

    subroutine print_printers(printers, res)
        !! The print queues CUPS knows, default first marked.
        type(print_printer_t), allocatable, intent(out) :: printers(:)
        type(print_result_t), intent(out) :: res
#ifdef ENABLE_PRINT
        type(c_ptr) :: dests
        type(cups_dest_t), pointer :: d(:)
        integer :: n, k

        res%message = ""
        dests = c_null_ptr
        n = cupsGetDests(dests)
        allocate(printers(max(n, 0)))
        if (n <= 0) then
            res%message = "no printers are set up"
            return
        end if
        call c_f_pointer(dests, d, [n])
        do k = 1, n
            printers(k)%name = f_str(d(k)%name)
            printers(k)%is_default = d(k)%is_default /= 0
            printers(k)%info = option(d(k), "printer-info")
            printers(k)%location = option(d(k), "printer-location")
            printers(k)%make_model = option(d(k), "printer-make-and-model")
            printers(k)%device_uri = option(d(k), "device-uri")
        end do
        call cupsFreeDests(int(n, c_int), dests)
#else
        allocate(printers(0))
        call unsupported(res)
#endif
    end subroutine print_printers

    subroutine print_capabilities(printer, caps, res)
        !! What `printer` offers. Loaded paper and ink levels are asked from the
        !! device when its queue talks IPP to it, else taken from CUPS.
        character(*), intent(in) :: printer
        type(print_caps_t), intent(out) :: caps
        type(print_result_t), intent(out) :: res
#ifdef ENABLE_PRINT
        type(c_ptr) :: dest, info, attr
        type(cups_dest_t), pointer :: d
        type(cups_size_t), target :: sz
        integer :: n, k, yres, units, best
        character(len=:), allocatable :: uri

        res%message = ""
        dest = cupsGetNamedDest(c_null_ptr, cstr(printer), c_null_ptr)
        if (.not. c_associated(dest)) then
            res%status = PRINT_FAILED
            res%message = "no printer named '" // printer // "'"
            allocate(caps%media(0), caps%media_types(0), caps%sources(0), &
                caps%qualities(0), caps%markers(0))
            return
        end if
        info = cupsCopyDestInfo(c_null_ptr, dest)
        n = cupsGetDestMediaCount(c_null_ptr, dest, info, MEDIA_FLAGS_DEFAULT)
        allocate(caps%media(max(n, 0)))
        do k = 1, n
            if (cupsGetDestMediaByIndex(c_null_ptr, dest, info, int(k - 1, c_int), &
                MEDIA_FLAGS_DEFAULT, sz) == 0) cycle
            caps%media(k)%name = f_chars(sz%media)
            caps%media(k)%width = sz%width
            caps%media(k)%length = sz%length
            caps%media(k)%left = sz%left
            caps%media(k)%right = sz%right
            caps%media(k)%top = sz%top
            caps%media(k)%bottom = sz%bottom
            caps%media(k)%borderless = max(sz%left, sz%right, sz%top, sz%bottom) == 0
            caps%media(k)%label = f_str(cupsLocalizeDestMedia(c_null_ptr, dest, info, &
                MEDIA_FLAGS_DEFAULT, sz))
            if (len(caps%media(k)%label) == 0 .or. caps%media(k)%label == &
                caps%media(k)%name) caps%media(k)%label = print_media_label( &
                caps%media(k)%name, int(sz%width), int(sz%length))
            caps%media(k)%source = ""
            caps%media(k)%media_type = ""
        end do
        call choices(dest, info, "media-type", caps%media_types)
        call choices(dest, info, "media-source", caps%sources)
        attr = cupsFindDestSupported(c_null_ptr, dest, info, cstr("print-quality"))
        allocate(caps%qualities(ippGetCount(attr)))
        do k = 1, size(caps%qualities)
            caps%qualities(k) = ippGetInteger(attr, int(k - 1, c_int))
        end do
        attr = cupsFindDestSupported(c_null_ptr, dest, info, &
            cstr("pwg-raster-document-resolution"))
        if (.not. c_associated(attr)) attr = cupsFindDestSupported(c_null_ptr, dest, &
            info, cstr("printer-resolution"))
        best = 0
        do k = 1, ippGetCount(attr)
            best = max(best, int(ippGetResolution(attr, int(k - 1, c_int), yres, units)))
        end do
        if (best > 0) caps%dpi = best
        attr = cupsFindDestSupported(c_null_ptr, dest, info, cstr("print-color-mode"))
        caps%color = .false.
        do k = 1, ippGetCount(attr)
            if (f_str(ippGetString(attr, int(k - 1, c_int), c_null_ptr)) == "color") &
                caps%color = .true.
        end do

        call c_f_pointer(dest, d)
        uri = option(d, "device-uri")
        allocate(caps%markers(0))
        if (index(uri, "ipp://") == 1 .or. index(uri, "ipps://") == 1) &
            call device_state(uri, caps)
        if (.not. caps%live) call cups_ready(dest, info, caps)
        do k = 1, size(caps%media_types)
            if (caps%media_types(k)%label == caps%media_types(k)%keyword) &
                caps%media_types(k)%label = print_keyword_label(caps%media_types(k)%keyword)
        end do
        do k = 1, size(caps%sources)
            if (caps%sources(k)%label == caps%sources(k)%keyword) &
                caps%sources(k)%label = print_keyword_label(caps%sources(k)%keyword)
        end do
        call cupsFreeDestInfo(info)
        call cupsFreeDests(1_c_int, dest)
#else
        allocate(caps%media(0), caps%media_types(0), caps%sources(0), caps%qualities(0), &
            caps%markers(0))
        if (len(printer) < 0) return
        call unsupported(res)
#endif
    end subroutine print_capabilities

    subroutine print_page(job, rgb, dpi, res)
        !! Print one page composed as rgb(3, width, height) sRGB bytes covering the
        !! whole sheet of `job%media` at `dpi` (see print_page_pixels).
        type(print_job_t), intent(in) :: job
        integer(int8), intent(in) :: rgb(:, :, :)
        integer, intent(in) :: dpi
        type(print_result_t), intent(out) :: res
#ifdef ENABLE_PRINT
        type(pwg_stream_t), target :: doc
        type(cups_size_t) :: sz
        type(c_ptr) :: dest, info, opts
        integer(c_int) :: nopt, job_id, st
        integer :: pos, chunk
        character(len=16) :: num

        res%message = ""
        dest = cupsGetNamedDest(c_null_ptr, cstr(job%printer), c_null_ptr)
        if (.not. c_associated(dest)) then
            res%status = PRINT_FAILED
            res%message = "no printer named '" // job%printer // "'"
            return
        end if
        call pwg_begin(doc)
        if (allocated(job%media_type)) then
            call pwg_add_page(doc, rgb, dpi, media=strip_borderless(job%media), &
                quality=job%quality, media_type=job%media_type)
        else
            call pwg_add_page(doc, rgb, dpi, media=strip_borderless(job%media), &
                quality=job%quality)
        end if
        info = cupsCopyDestInfo(c_null_ptr, dest)
        nopt = 0
        opts = c_null_ptr
        ! The sheet goes as media-col with its size and margins: CUPS maps the
        ! name "..._borderless" to the bordered size, but zero margins in
        ! media-col select the borderless one (IPP and PPD queues alike).
        if (find_media(dest, info, job%media, sz)) then
            nopt = cupsAddOption(cstr("media-col"), cstr(media_col(sz, job)), nopt, opts)
        else
            nopt = cupsAddOption(cstr("media"), cstr(job%media), nopt, opts)
            if (allocated(job%media_type)) then
                if (len(job%media_type) > 0) nopt = cupsAddOption(cstr("media-type"), &
                    cstr(job%media_type), nopt, opts)
            end if
            if (allocated(job%source)) then
                if (len(job%source) > 0) nopt = cupsAddOption(cstr("media-source"), &
                    cstr(job%source), nopt, opts)
            end if
        end if
        if (job%quality /= PWG_QUALITY_DEFAULT) then
            write (num, '(i0)') job%quality
            nopt = cupsAddOption(cstr("print-quality"), cstr(trim(num)), nopt, opts)
        end if
        write (num, '(i0)') max(1, job%copies)
        nopt = cupsAddOption(cstr("copies"), cstr(trim(num)), nopt, opts)
        nopt = cupsAddOption(cstr("print-color-mode"), &
            cstr(trim(merge("color     ", "monochrome", job%color))), nopt, opts)
        if (job%hold) nopt = cupsAddOption(cstr("job-hold-until"), cstr("indefinite"), &
            nopt, opts)

        job_id = 0
        st = cupsCreateDestJob(c_null_ptr, dest, info, job_id, cstr(title_of(job)), nopt, &
            opts)
        if (st > int(z'00FF', c_int) .or. job_id <= 0) then
            res%status = PRINT_FAILED
            res%message = "the printer refused the job: " // f_str(cupsLastErrorString())
        else
            res%job_id = job_id
            st = cupsStartDestDocument(c_null_ptr, dest, info, job_id, cstr(title_of(job)), &
                cstr("image/pwg-raster"), 0_c_int, c_null_ptr, 1_c_int)
            pos = 0
            do while (st == HTTP_STATUS_CONTINUE .and. pos < doc%n)
                chunk = min(doc%n - pos, 65536)
                st = cupsWriteRequestData(c_null_ptr, c_loc(doc%bytes(pos + 1)), &
                    int(chunk, c_size_t))
                pos = pos + chunk
            end do
            if (st /= HTTP_STATUS_CONTINUE) then
                res%status = PRINT_FAILED
                res%message = "sending the page failed: " // f_str(cupsLastErrorString())
            end if
            st = cupsFinishDestDocument(c_null_ptr, dest, info)
            if (res%status == PRINT_OK .and. st > int(z'00FF', c_int)) then
                res%status = PRINT_FAILED
                res%message = "the printer did not accept the page: " // &
                    f_str(cupsLastErrorString())
            end if
        end if
        call cupsFreeOptions(nopt, opts)
        call cupsFreeDestInfo(info)
        call cupsFreeDests(1_c_int, dest)
#else
        if (size(rgb) < 0 .or. dpi < 0 .or. len(job%printer) < 0) return
        call unsupported(res)
#endif
    end subroutine print_page

    subroutine print_cancel(printer, job_id, res)
        !! Cancel a job that is still queued.
        character(*), intent(in) :: printer
        integer, intent(in) :: job_id
        type(print_result_t), intent(out) :: res
#ifdef ENABLE_PRINT
        type(c_ptr) :: dest

        res%message = ""
        dest = cupsGetNamedDest(c_null_ptr, cstr(printer), c_null_ptr)
        if (.not. c_associated(dest)) then
            res%status = PRINT_FAILED
            res%message = "no printer named '" // printer // "'"
            return
        end if
        if (cupsCancelDestJob(c_null_ptr, dest, int(job_id, c_int)) > int(z'00FF', c_int)) then
            res%status = PRINT_FAILED
            res%message = f_str(cupsLastErrorString())
        end if
        call cupsFreeDests(1_c_int, dest)
#else
        if (len(printer) < 0 .or. job_id < 0) return
        call unsupported(res)
#endif
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

#ifdef ENABLE_PRINT
    subroutine choices(dest, info, name, list)
        !! Supported keywords of option `name` with the printer's labels.
        type(c_ptr), intent(in) :: dest, info
        character(*), intent(in) :: name
        type(print_choice_t), allocatable, intent(out) :: list(:)
        type(c_ptr) :: attr
        integer :: k
        ! Named, so they outlive the call: CUPS returns the value itself when it
        ! has no translation.
        character(kind=c_char, len=:), allocatable :: copt, cval

        copt = cstr(name)
        attr = cupsFindDestSupported(c_null_ptr, dest, info, copt)
        allocate(list(ippGetCount(attr)))
        do k = 1, size(list)
            list(k)%keyword = f_str(ippGetString(attr, int(k - 1, c_int), c_null_ptr))
            cval = cstr(list(k)%keyword)
            list(k)%label = f_str(cupsLocalizeDestValue(c_null_ptr, dest, info, copt, cval))
            if (len(list(k)%label) == 0) list(k)%label = list(k)%keyword
        end do
    end subroutine choices

    logical function find_media(dest, info, name, sz) result(found)
        !! The printer's sheet of exactly this name. cupsGetDestMediaByName does
        !! not know the "_borderless" names cupsGetDestMediaByIndex reports and
        !! returns some other size instead (CUPS 2.4.20).
        type(c_ptr), intent(in) :: dest, info
        character(*), intent(in) :: name
        type(cups_size_t), intent(out) :: sz
        integer :: k

        found = .false.
        do k = 1, cupsGetDestMediaCount(c_null_ptr, dest, info, MEDIA_FLAGS_DEFAULT)
            if (cupsGetDestMediaByIndex(c_null_ptr, dest, info, int(k - 1, c_int), &
                MEDIA_FLAGS_DEFAULT, sz) == 0) cycle
            if (f_chars(sz%media) == name) then
                found = .true.
                return
            end if
        end do
    end function find_media

    function media_col(sz, job) result(col)
        !! The IPP media-col collection of a sheet, as a CUPS option value.
        type(cups_size_t), intent(in) :: sz
        type(print_job_t), intent(in) :: job
        character(len=:), allocatable :: col
        character(len=160) :: buf

        write (buf, '(a,i0,a,i0,a,i0,a,i0,a,i0,a,i0)') &
            "{media-size={x-dimension=", sz%width, " y-dimension=", sz%length, &
            "} media-bottom-margin=", sz%bottom, " media-left-margin=", sz%left, &
            " media-right-margin=", sz%right, " media-top-margin=", sz%top
        col = trim(buf)
        if (allocated(job%source)) then
            if (len(job%source) > 0) col = col // " media-source=" // job%source
        end if
        if (allocated(job%media_type)) then
            if (len(job%media_type) > 0) col = col // " media-type=" // job%media_type
        end if
        col = col // "}"
    end function media_col

    subroutine cups_ready(dest, info, caps)
        !! Loaded paper as CUPS last heard it (no tray or type).
        type(c_ptr), intent(in) :: dest, info
        type(print_caps_t), intent(inout) :: caps
        type(cups_size_t) :: sz
        integer :: k

        do k = 1, cupsGetDestMediaCount(c_null_ptr, dest, info, MEDIA_FLAGS_READY)
            if (cupsGetDestMediaByIndex(c_null_ptr, dest, info, int(k - 1, c_int), &
                MEDIA_FLAGS_READY, sz) == 0) cycle
            call mark_loaded(caps, int(sz%width), int(sz%length), "", "")
        end do
    end subroutine cups_ready

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
        character(kind=c_char, len=32), target :: scheme
        character(kind=c_char, len=256), target :: user, host, resource
        character(kind=c_char, len=24), target :: want(4)
        type(c_ptr) :: values(4), http, req, resp, attr, col, size_col, a
        integer(c_int) :: port, enc
        integer :: k, w, l, n

        if (httpSeparateURI(HTTP_URI_CODING_ALL, cstr(uri), scheme, 32_c_int, user, &
            256_c_int, host, 256_c_int, port, resource, 256_c_int) < 0) return
        enc = HTTP_ENCRYPTION_IF_REQUESTED
        if (index(uri, "ipps://") == 1) enc = HTTP_ENCRYPTION_ALWAYS
        http = httpConnect2(host, port, c_null_ptr, 0_c_int, enc, 1_c_int, 3000_c_int, &
            c_null_ptr)
        if (.not. c_associated(http)) return
        req = ippNewRequest(IPP_OP_GET_PRINTER_ATTRIBUTES)
        a = ippAddString(req, IPP_TAG_OPERATION, IPP_TAG_URI, cstr("printer-uri"), &
            c_null_ptr, cstr(uri))
        want(1) = "media-col-ready" // c_null_char
        want(2) = "marker-names" // c_null_char
        want(3) = "marker-levels" // c_null_char
        want(4) = "printer-strings-uri" // c_null_char
        do k = 1, 4
            values(k) = c_loc(want(k))
        end do
        a = ippAddStrings(req, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, &
            cstr("requested-attributes"), 4_c_int, c_null_ptr, values)
        resp = cupsDoRequest(http, req, resource)
        if (c_associated(resp)) then
            attr = ippFindAttribute(resp, cstr("media-col-ready"), IPP_TAG_BEGIN_COLLECTION)
            caps%live = c_associated(attr)
            do k = 1, ippGetCount(attr)
                col = ippGetCollection(attr, int(k - 1, c_int))
                size_col = ippGetCollection(ippFindAttribute(col, cstr("media-size"), &
                    IPP_TAG_BEGIN_COLLECTION), 0_c_int)
                w = ippGetInteger(ippFindAttribute(size_col, cstr("x-dimension"), &
                    IPP_TAG_INTEGER), 0_c_int)
                l = ippGetInteger(ippFindAttribute(size_col, cstr("y-dimension"), &
                    IPP_TAG_INTEGER), 0_c_int)
                call mark_loaded(caps, w, l, keyword_of(col, "media-source"), &
                    keyword_of(col, "media-type"))
            end do
            attr = ippFindAttribute(resp, cstr("marker-names"), IPP_TAG_ZERO)
            a = ippFindAttribute(resp, cstr("marker-levels"), IPP_TAG_INTEGER)
            n = min(ippGetCount(attr), ippGetCount(a))
            deallocate(caps%markers)
            allocate(caps%markers(n))
            do k = 1, n
                caps%markers(k)%name = f_str(ippGetString(attr, int(k - 1, c_int), &
                    c_null_ptr))
                caps%markers(k)%level = ippGetInteger(a, int(k - 1, c_int))
            end do
            attr = ippFindAttribute(resp, cstr("printer-strings-uri"), IPP_TAG_URI)
            if (c_associated(attr)) call load_strings(f_str(ippGetString(attr, 0_c_int, &
                c_null_ptr)), caps)
            call ippDelete(resp)
        end if
        call httpClose(http)
    end subroutine device_state

    subroutine load_strings(uri, caps)
        !! Fetch the printer's strings file (IPP Everywhere printer-strings-uri)
        !! and take its names for media types and trays.
        character(*), intent(in) :: uri
        type(print_caps_t), intent(inout) :: caps
        character(kind=c_char, len=32) :: scheme
        character(kind=c_char, len=256) :: user, host, resource
        character(kind=c_char) :: chunk(8192)
        character(len=:), allocatable :: text
        type(c_ptr) :: http
        integer(c_int) :: port, st, enc
        integer(c_intptr_t) :: got
        integer :: k

        if (httpSeparateURI(HTTP_URI_CODING_ALL, cstr(uri), scheme, 32_c_int, user, &
            256_c_int, host, 256_c_int, port, resource, 256_c_int) < 0) return
        enc = HTTP_ENCRYPTION_IF_REQUESTED
        if (index(uri, "https://") == 1) enc = HTTP_ENCRYPTION_ALWAYS
        http = httpConnect2(host, port, c_null_ptr, 0_c_int, enc, 1_c_int, 3000_c_int, &
            c_null_ptr)
        if (.not. c_associated(http)) return
        text = ""
        ! Clearing sets the Host field, which the printer insists on.
        call httpClearFields(http)
        if (httpGet(http, resource) == 0) then
            st = httpUpdate(http)
            do while (st == HTTP_STATUS_CONTINUE)
                st = httpUpdate(http)
            end do
            if (st == HTTP_STATUS_OK) then
                do
                    got = httpRead2(http, chunk, int(size(chunk), c_size_t))
                    if (got <= 0 .or. len(text) > 4 * 1024 * 1024) exit
                    text = text // transfer(chunk(1:got), repeat(" ", int(got)))
                end do
            end if
        end if
        call httpClose(http)
        k = len(text)
        if (k > 0) call print_apply_strings(caps, text)
    end subroutine load_strings

    function keyword_of(col, name) result(v)
        type(c_ptr), intent(in) :: col
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        v = f_str(ippGetString(ippFindAttribute(col, cstr(name), IPP_TAG_ZERO), 0_c_int, &
            c_null_ptr))
    end function keyword_of

    function option(d, name) result(v)
        type(cups_dest_t), intent(in) :: d
        character(*), intent(in) :: name
        character(len=:), allocatable :: v
        v = f_str(cupsGetOption(cstr(name), d%num_options, d%options))
    end function option

    function cstr(s) result(c)
        character(*), intent(in) :: s
        character(kind=c_char, len=:), allocatable :: c
        c = s // c_null_char
    end function cstr

    function f_str(p) result(s)
        !! Copy of a C string ("" for NULL).
        type(c_ptr), intent(in) :: p
        character(len=:), allocatable :: s
        character(kind=c_char), pointer :: chars(:)
        integer :: n, k

        if (.not. c_associated(p)) then
            s = ""
            return
        end if
        n = int(c_strlen(p))
        call c_f_pointer(p, chars, [n])
        allocate(character(len=n) :: s)
        do k = 1, n
            s(k:k) = chars(k)
        end do
    end function f_str

    function f_chars(a) result(s)
        character(kind=c_char), intent(in) :: a(:)
        character(len=:), allocatable :: s
        integer :: n, k

        n = 0
        do while (n < size(a))
            if (a(n + 1) == c_null_char) exit
            n = n + 1
        end do
        allocate(character(len=n) :: s)
        do k = 1, n
            s(k:k) = a(k)
        end do
    end function f_chars
#endif

end module fortui_print
