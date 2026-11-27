module fortui_files
    !! Owned file content and UTF-8 paths. Browser selections carry bytes and a
    !! display name, never a path into the user's filesystem.
    use iso_c_binding, only: c_ptr, c_char, c_int, c_null_char, c_associated, c_long_long
    use iso_fortran_env, only: int8
    implicit none
    private
    integer, parameter, public :: FILE_IDLE = 0, FILE_PENDING = 1, FILE_ACCEPTED = 2, &
        FILE_CANCELLED = 3, FILE_FAILED = 4, FILE_UNSUPPORTED = 5
    type, public :: file_entry_t
        character(len=:), allocatable :: name
        logical :: directory = .false.
    end type
    public :: file_list, file_read, file_write, file_join, file_parent, file_name, file_home
    public :: file_is_directory, file_matches, file_lower, file_is_readable, file_absolute
    public :: file_make_dirs
    interface
        type(c_ptr) function dir_open(path) bind(C, name="fortui_dir_open")
            import c_ptr, c_char
            character(c_char), intent(in) :: path(*)
        end function
        integer(c_int) function dir_next(d, name, cap, directory) &
                bind(C, name="fortui_dir_next")
            import c_ptr, c_int, c_char
            type(c_ptr), value :: d
            character(c_char), intent(out) :: name(*)
            integer(c_int), value :: cap
            integer(c_int), intent(out) :: directory
        end function
        subroutine dir_close(d) bind(C, name="fortui_dir_close")
            import c_ptr
            type(c_ptr), value :: d
        end subroutine
        integer(c_int) function is_dir(path) bind(C, name="fortui_file_directory")
            import c_char, c_int
            character(c_char), intent(in) :: path(*)
        end function
        type(c_ptr) function read_open(path, n) bind(C, name="fortui_file_open")
            import c_ptr, c_char, c_long_long
            character(c_char), intent(in) :: path(*)
            integer(c_long_long), intent(out) :: n
        end function
        integer(c_int) function read_copy(handle, bytes, n) bind(C, name="fortui_file_copy")
            import c_ptr, c_int, int8
            type(c_ptr), value :: handle
            integer(int8), intent(out) :: bytes(*)
            integer(c_int), value :: n
        end function
        subroutine read_close(handle) bind(C, name="fortui_file_close")
            import c_ptr
            type(c_ptr), value :: handle
        end subroutine
        integer(c_int) function make_dirs(path) bind(C, name="fortui_make_dirs")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: path(*)
        end function make_dirs
        integer(c_int) function readable(path) bind(C, name="fortui_file_readable")
            import c_char, c_int
            character(c_char), intent(in) :: path(*)
        end function
        integer(c_int) function absolute_path(path, out, capacity) bind(C, name="fortui_file_absolute")
            import c_char, c_int
            character(c_char), intent(in) :: path(*)
            character(c_char), intent(out) :: out(*)
            integer(c_int), value :: capacity
        end function
    end interface
contains
    subroutine file_list(path, entries, message, extensions, hidden)
        character(*), intent(in) :: path
        type(file_entry_t), allocatable, intent(out) :: entries(:)
        character(:), allocatable, intent(out) :: message
        character(*), intent(in), optional :: extensions
        logical, intent(in), optional :: hidden
        type(file_entry_t), allocatable :: buf(:), grown(:)
        type(file_entry_t) :: item
        type(c_ptr) :: d
        character(c_char) :: name(4096)
        character(:), allocatable :: s
        integer(c_int) :: rc, directory
        integer :: n, i, j, k
        logical :: show_hidden
        show_hidden = .false.
        if (present(hidden)) show_hidden = hidden
        message = ""
        allocate(buf(64))
        n = 0
        d = dir_open(trim(path) // c_null_char)
        if (.not. c_associated(d)) then
            message = "Cannot read this folder. Check its location and permissions."
            allocate(entries(0))
            return
        end if
        do
            rc = dir_next(d, name, int(size(name), c_int), directory)
            if (rc <= 0) exit
            k = 1
            do while (k <= size(name))
                if (name(k) == c_null_char) exit
                k = k + 1
            end do
            s = ""
            do i = 1, k - 1
                s = s // name(i)
            end do
            if (s == "." .or. s == ".." .or. len(s) == 0) cycle
            if (.not. show_hidden) then
                if (s(1:1) == "." .or. iand(directory, 2) /= 0) cycle
            end if
            if (iand(directory, 1) == 0 .and. present(extensions)) then
                if (.not. file_matches(s, extensions)) cycle
            end if
            if (n == size(buf)) then
                allocate(grown(2 * size(buf)))
                grown(1:n) = buf
                call move_alloc(grown, buf)
            end if
            n = n + 1
            buf(n) = file_entry_t(s, iand(directory, 1) /= 0)
        end do
        call dir_close(d)
        if (rc < 0) message = "The folder changed or could not be read completely."
        entries = buf(1:n)
        ! Folders first, with stable case-insensitive name ordering.
        do i = 2, n
            item = entries(i)
            j = i - 1
            do while (j >= 1)
                if (.not. after(entries(j), item)) exit
                entries(j + 1) = entries(j)
                j = j - 1
            end do
            entries(j + 1) = item
        end do
    end subroutine
    logical function after(a, b)
        type(file_entry_t), intent(in) :: a, b
        if (a%directory .neqv. b%directory) then
            after = b%directory
        else
            after = file_lower(a%name) > file_lower(b%name)
        end if
    end function
    subroutine file_read(path, bytes, message)
        character(*), intent(in) :: path
        integer(int8), allocatable, intent(out) :: bytes(:)
        character(:), allocatable, intent(out) :: message
        type(c_ptr) :: handle
        integer(c_long_long) :: n
        integer(c_int) :: rc
        message = ""
        allocate(bytes(0))
        handle = read_open(path // c_null_char, n)
        if (.not. c_associated(handle)) then
            message = "Cannot open this file. Check its location and permissions."
            return
        end if
        if (n > int(huge(0_c_int), c_long_long)) then
            message = "This file is too large to open."
        else
            deallocate(bytes)
            allocate(bytes(int(n)))
            rc = read_copy(handle, bytes, int(n,c_int))
            if (rc /= 0) message = "Cannot read this file."
        end if
        call read_close(handle)
    end subroutine
    subroutine file_write(path, bytes, message)
        !! Writes `bytes` to `path`, replacing the file; `message` is empty on
        !! success. In the browser the file lands in memory: ui_offer_file
        !! hands it to the visitor.
        character(*), intent(in) :: path
        integer(int8), intent(in) :: bytes(:)
        character(:), allocatable, intent(out) :: message
        integer :: unit, ios
        message = ""
        open(newunit=unit, file=path, access="stream", form="unformatted", &
            status="replace", action="write", iostat=ios)
        if (ios /= 0) then
            message = "Cannot write this file. Check its location and permissions."
            return
        end if
        write(unit, iostat=ios) bytes
        if (ios /= 0) message = "Cannot write this file."
        close(unit)
    end subroutine file_write
    logical function file_make_dirs(path)
        !! Create directory `path` with its missing parents; whether it exists.
        character(*), intent(in) :: path
        file_make_dirs = make_dirs(path // c_null_char) /= 0
    end function file_make_dirs

    logical function file_is_readable(path)
        character(*), intent(in) :: path
        file_is_readable = readable(path // c_null_char) /= 0
    end function
    logical function file_is_directory(path)
        character(*), intent(in) :: path
        file_is_directory = is_dir(path // c_null_char) /= 0
    end function
    function file_absolute(path) result(s)
        character(*), intent(in) :: path
        character(:), allocatable :: s
        character(c_char) :: out(4096)
        integer :: k
        s = file_slashes(path)
        if (absolute_path(path // c_null_char, out, int(size(out),c_int)) == 0) return
        s = ""
        do k = 1, size(out)
            if (out(k) == c_null_char) exit
            s = s // out(k)
        end do
        s = file_slashes(s)
    end function
    function file_home() result(s)
        character(:), allocatable :: s
        character(4096) :: v
        integer :: st
        call get_environment_variable("HOME", v, status=st)
        if (st /= 0 .or. len_trim(v) == 0) &
            call get_environment_variable("USERPROFILE", v, status=st)
        s = "."
        if (st == 0 .and. len_trim(v) > 0) s = file_slashes(trim(v))
    end function
    pure function file_slashes(s) result(t)
        character(*), intent(in) :: s
        character(len(s)) :: t
        integer :: i
        t = s
        do i = 1, len(t)
            if (iachar(t(i:i)) == 92) t(i:i) = "/"
        end do
    end function
    function file_join(dir, name) result(s)
        character(*), intent(in) :: dir, name
        character(:), allocatable :: s, p
        p = file_slashes(trim(name))
        s = p
        if (len(p) == 0) then
            s = dir
            return
        end if
        if (p(1:1) == "/") return
        if (len(p) > 1) then
            if (p(2:2) == ":") return
        end if
        s = file_slashes(trim(dir))
        if (len(s) > 0) then
            if (s(len(s):) /= "/") s = s // "/"
        end if
        s = s // p
    end function
    function file_parent(path) result(s)
        character(*), intent(in) :: path
        character(:), allocatable :: s
        integer :: k, root
        s = file_slashes(trim(path))
        root = 1
        if (len(s) >= 3) then
            if (s(2:3) == ":/") root = 3
        end if
        do while (len(s) > root)
            if (s(len(s):) /= "/") exit
            s = s(:len(s) - 1)
        end do
        k = index(s, "/", back=.true.)
        if (k == 0) then
            s = "."
        else
            s = s(:max(k - 1, root))
        end if
    end function
    function file_name(path) result(s)
        character(*), intent(in) :: path
        character(:), allocatable :: s
        integer :: k
        s = file_slashes(trim(path))
        k = index(s, "/", back=.true.)
        s = s(k + 1:)
    end function
    pure logical function file_matches(name, extensions) result(ok)
        character(*), intent(in) :: name, extensions
        character(:), allocatable :: ext, choices
        integer :: k
        ok = len_trim(extensions) == 0 .or. trim(extensions) == "*"
        if (ok) return
        k = index(name, ".", back=.true.)
        if (k == 0) return
        ext = file_lower(name(k:))
        choices = "," // file_lower(trim(extensions)) // ","
        ok = index(choices, "," // ext // ",") > 0
    end function
    pure function file_lower(s) result(t)
        character(*), intent(in) :: s
        character(len(s)) :: t
        integer :: k, c
        t = s
        do k = 1, len(s)
            c = iachar(s(k:k))
            if (c >= 65 .and. c <= 90) t(k:k) = achar(c + 32)
        end do
    end function
end module fortui_files
