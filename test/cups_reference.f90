module cups_reference
    !! libcups, opened at run time, as the reference the printing tests compare
    !! against: its PWG raster reader, its names for paper sizes and its list of
    !! a printer's sheets. FortUI itself does not use it.
    use iso_c_binding
    implicit none
    private
    public :: cups_open, cups_size_name, cups_media_list, cups_raster_rows

    type, bind(C) :: pwg_media_t
        type(c_ptr) :: pwg, legacy, ppd
        integer(c_int) :: width, length
    end type pwg_media_t

    type, bind(C), public :: cups_size_t
        character(kind=c_char) :: media(128)
        integer(c_int) :: width, length, bottom, left, right, top
    end type cups_size_t

    type, bind(C) :: reader_t
        type(c_ptr) :: bytes
        integer(c_size_t) :: n, pos
    end type reader_t

    abstract interface
        type(c_ptr) function fn_media_for_size(width, length) bind(C)
            import :: c_ptr, c_int
            integer(c_int), value :: width, length
        end function
        type(c_ptr) function fn_dest_with_uri(name, uri) bind(C)
            import :: c_ptr, c_char
            character(kind=c_char), intent(in) :: name(*), uri(*)
        end function
        type(c_ptr) function fn_connect(host, port, addrlist, family, encryption, &
                blocking, msec, cancel) bind(C)
            import :: c_ptr, c_int, c_char
            character(kind=c_char), intent(in) :: host(*)
            integer(c_int), value :: port, family, encryption, blocking, msec
            type(c_ptr), value :: addrlist, cancel
        end function
        type(c_ptr) function fn_copy_dest_info(http, dest) bind(C)
            import :: c_ptr
            type(c_ptr), value :: http, dest
        end function
        integer(c_int) function fn_media_count(http, dest, info, flags) bind(C)
            import :: c_ptr, c_int
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: flags
        end function
        integer(c_int) function fn_media_by_index(http, dest, info, n, flags, size) bind(C)
            import :: c_ptr, c_int, cups_size_t
            type(c_ptr), value :: http, dest, info
            integer(c_int), value :: n, flags
            type(cups_size_t) :: size
        end function
        type(c_ptr) function fn_raster_open(iocb, ctx, mode) bind(C)
            import :: c_ptr, c_funptr, c_int
            type(c_funptr), value :: iocb
            type(c_ptr), value :: ctx
            integer(c_int), value :: mode
        end function
        integer(c_int) function fn_read_header(r, h) bind(C)
            import :: c_ptr, c_int, c_int8_t
            type(c_ptr), value :: r
            integer(c_int8_t) :: h(1796)
        end function
        integer(c_int) function fn_read_pixels(r, p, n) bind(C)
            import :: c_ptr, c_int, c_int8_t
            type(c_ptr), value :: r
            integer(c_int8_t) :: p(*)
            integer(c_int), value :: n
        end function
        subroutine fn_close(r) bind(C)
            import :: c_ptr
            type(c_ptr), value :: r
        end subroutine
    end interface

    interface
        type(c_ptr) function dlopen(name, flags) bind(C)
            import :: c_ptr, c_char, c_int
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: flags
        end function
        type(c_funptr) function dlsym(handle, name) bind(C)
            import :: c_ptr, c_funptr, c_char
            type(c_ptr), value :: handle
            character(kind=c_char), intent(in) :: name(*)
        end function
        integer(c_size_t) function strlen(s) bind(C)
            import :: c_size_t, c_ptr
            type(c_ptr), value :: s
        end function
    end interface

    procedure(fn_media_for_size), pointer :: pwgMediaForSize => null()
    procedure(fn_dest_with_uri), pointer :: cupsGetDestWithURI => null()
    procedure(fn_connect), pointer :: httpConnect2 => null()
    procedure(fn_copy_dest_info), pointer :: cupsCopyDestInfo => null()
    procedure(fn_media_count), pointer :: cupsGetDestMediaCount => null()
    procedure(fn_media_by_index), pointer :: cupsGetDestMediaByIndex => null()
    procedure(fn_raster_open), pointer :: cupsRasterOpenIO => null()
    procedure(fn_read_header), pointer :: cupsRasterReadHeader2 => null()
    procedure(fn_read_pixels), pointer :: cupsRasterReadPixels => null()
    procedure(fn_close), pointer :: cupsRasterClose => null()
    type(c_ptr), save :: lib = c_null_ptr

contains

    logical function cups_open()
        if (.not. c_associated(lib)) then
            lib = dlopen("libcups.so.2" // c_null_char, 2_c_int)
            if (.not. c_associated(lib)) lib = dlopen("libcups.2.dylib" // c_null_char, 2_c_int)
            if (c_associated(lib)) then
                call c_f_procpointer(sym("pwgMediaForSize"), pwgMediaForSize)
                call c_f_procpointer(sym("cupsGetDestWithURI"), cupsGetDestWithURI)
                call c_f_procpointer(sym("httpConnect2"), httpConnect2)
                call c_f_procpointer(sym("cupsCopyDestInfo"), cupsCopyDestInfo)
                call c_f_procpointer(sym("cupsGetDestMediaCount"), cupsGetDestMediaCount)
                call c_f_procpointer(sym("cupsGetDestMediaByIndex"), cupsGetDestMediaByIndex)
                call c_f_procpointer(sym("cupsRasterOpenIO"), cupsRasterOpenIO)
                call c_f_procpointer(sym("cupsRasterReadHeader2"), cupsRasterReadHeader2)
                call c_f_procpointer(sym("cupsRasterReadPixels"), cupsRasterReadPixels)
                call c_f_procpointer(sym("cupsRasterClose"), cupsRasterClose)
            end if
        end if
        cups_open = c_associated(lib)
    contains
        type(c_funptr) function sym(name)
            character(*), intent(in) :: name
            sym = dlsym(lib, name // c_null_char)
        end function sym
    end function cups_open

    function cups_size_name(width, length) result(name)
        !! pwgMediaForSize's name for a size in hundredths of a millimetre.
        integer, intent(in) :: width, length
        character(len=:), allocatable :: name
        type(c_ptr) :: p
        type(pwg_media_t), pointer :: m
        name = ""
        p = pwgMediaForSize(int(width, c_int), int(length, c_int))
        if (.not. c_associated(p)) return
        call c_f_pointer(p, m)
        name = c_string(m%pwg)
    end function cups_size_name

    subroutine cups_media_list(host, port, uri, names, sizes, ok)
        !! The sheets libcups lists for a printer URI (cupsGetDestMediaByIndex):
        !! names and (width, length, bottom, left, right, top).
        character(*), intent(in) :: host, uri
        integer, intent(in) :: port
        character(len=128), allocatable, intent(out) :: names(:)
        integer, allocatable, intent(out) :: sizes(:, :)
        logical, intent(out) :: ok
        type(c_ptr) :: dest, http, info
        type(cups_size_t) :: s
        integer :: n, k, j
        ok = .false.
        allocate(names(0), sizes(6, 0))
        dest = cupsGetDestWithURI("reference" // c_null_char, uri // c_null_char)
        if (.not. c_associated(dest)) return
        http = httpConnect2(host // c_null_char, int(port, c_int), c_null_ptr, 0_c_int, &
            0_c_int, 1_c_int, 5000_c_int, c_null_ptr)
        if (.not. c_associated(http)) return
        info = cupsCopyDestInfo(http, dest)
        if (.not. c_associated(info)) return
        n = cupsGetDestMediaCount(http, dest, info, 0_c_int)
        deallocate(names, sizes)
        allocate(names(n), sizes(6, n))
        do k = 1, n
            if (cupsGetDestMediaByIndex(http, dest, info, int(k - 1, c_int), 0_c_int, s) == 0) return
            names(k) = ""
            do j = 1, index_null(s%media) - 1
                names(k)(j:j) = s%media(j)
            end do
            sizes(:, k) = [s%width, s%length, s%bottom, s%left, s%right, s%top]
        end do
        ok = .true.
    end subroutine cups_media_list

    subroutine cups_raster_rows(bytes, n, header, rows, ok)
        !! Decode a PWG raster stream with cupsRasterReadPixels: the header and
        !! every row of the first page.
        integer(c_int8_t), intent(in), target :: bytes(:)
        integer, intent(in) :: n
        integer(c_int8_t), intent(out) :: header(1796)
        integer(c_int8_t), allocatable, intent(out) :: rows(:, :)
        logical, intent(out) :: ok
        type(reader_t), target :: rd
        type(c_ptr) :: r
        integer :: bpl, h, y
        ok = .false.
        rd = reader_t(c_loc(bytes), int(n, c_size_t), 0_c_size_t)
        r = cupsRasterOpenIO(c_funloc(read_cb), c_loc(rd), 0_c_int)
        if (.not. c_associated(r)) return
        if (cupsRasterReadHeader2(r, header) /= 1) return
        bpl = native_u32(header, 392)
        h = native_u32(header, 376)
        allocate(rows(bpl, h))
        do y = 1, h
            if (cupsRasterReadPixels(r, rows(:, y), int(bpl, c_int)) /= bpl) return
        end do
        call cupsRasterClose(r)
        ok = .true.
    end subroutine cups_raster_rows

    integer function native_u32(h, offset)
        integer(c_int8_t), intent(in) :: h(1796)
        integer, intent(in) :: offset
        native_u32 = transfer(h(offset + 1:offset + 4), 0_c_int32_t)
    end function native_u32

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

    integer function index_null(a)
        character(kind=c_char), intent(in) :: a(:)
        do index_null = 1, size(a)
            if (a(index_null) == c_null_char) return
        end do
    end function index_null

    function c_string(p) result(s)
        type(c_ptr), intent(in) :: p
        character(len=:), allocatable :: s
        character(kind=c_char), pointer :: chars(:)
        integer :: n, k
        n = int(strlen(p))
        call c_f_pointer(p, chars, [n])
        allocate(character(len=n) :: s)
        do k = 1, n
            s(k:k) = chars(k)
        end do
    end function c_string

end module cups_reference
