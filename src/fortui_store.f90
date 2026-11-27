module fortui_store
    !! Small key-value text the application keeps between runs (settings, a
    !! draft, the user's name), as a browser's local storage keeps it. Hosts
    !! without one keep it in a file: $FORTUI_STORE, else
    !! $XDG_DATA_HOME/fortui/<name>.tsv, else ~/.local/share/fortui/<name>.tsv,
    !! one "key<TAB>value" line per entry with tabs, line ends and backslashes
    !! escaped. Without a file (tests) the values live in memory only.
    use fortui_files, only: file_make_dirs, file_parent, file_home
    implicit none
    private

    type, public :: store_t
        character(len=:), allocatable :: path
        character(len=256), allocatable :: keys(:)
        type(text_t), allocatable :: values(:)
        integer :: count = 0
        logical :: loaded = .false.
    contains
        procedure :: get => store_get
        procedure :: set => store_set
        procedure :: use_file => store_use_file
    end type store_t

    type, public :: text_t
        character(len=:), allocatable :: s
    end type text_t

    public :: store_default_path

contains

    function store_default_path(name) result(path)
        !! Where a host without local storage keeps the values of application `name`.
        character(*), intent(in) :: name
        character(len=:), allocatable :: path
        character(len=1024) :: v
        integer :: n, st
        call get_environment_variable('FORTUI_STORE', v, n, st)
        if (st == 0 .and. n > 0) then
            path = v(1:n)
            return
        end if
        call get_environment_variable('XDG_DATA_HOME', v, n, st)
        if (st == 0 .and. n > 0) then
            path = v(1:n) // '/fortui/' // safe(name) // '.tsv'
        else
            path = file_home() // '/.local/share/fortui/' // safe(name) // '.tsv'
        end if
    end function store_default_path

    function safe(name) result(s)
        !! A file name from an application title: letters, digits, '-' and '_'.
        character(*), intent(in) :: name
        character(len=:), allocatable :: s
        integer :: k
        character :: c
        s = ''
        do k = 1, len_trim(name)
            c = name(k:k)
            select case (c)
            case ('a':'z', 'A':'Z', '0':'9', '-', '_')
                s = s // c
            case default
                s = s // '_'
            end select
        end do
        if (len(s) == 0) s = 'fortui'
    end function safe

    subroutine store_use_file(self, path)
        !! Keep the values in file `path` ("" for memory only), reading it now.
        class(store_t), intent(inout) :: self
        character(*), intent(in) :: path
        integer :: u, ios, tab
        character(len=65536) :: line
        self%path = path
        self%count = 0
        self%loaded = .true.
        if (len(path) == 0) return
        open (newunit=u, file=path, status='old', action='read', iostat=ios)
        if (ios /= 0) return
        do
            read (u, '(a)', iostat=ios) line
            if (ios /= 0) exit
            tab = index(line, achar(9))
            if (tab < 2) cycle
            call put(self, line(1:tab - 1), unescape(trim(line(tab + 1:))))
        end do
        close (u)
    end subroutine store_use_file

    function store_get(self, key) result(value)
        class(store_t), intent(inout) :: self
        character(*), intent(in) :: key
        character(len=:), allocatable :: value
        integer :: k
        value = ''
        do k = 1, self%count
            if (trim(self%keys(k)) == key) then
                value = self%values(k)%s
                return
            end if
        end do
    end function store_get

    subroutine store_set(self, key, value)
        !! Keep `value` under `key` ("" removes it), writing the file at once.
        class(store_t), intent(inout) :: self
        character(*), intent(in) :: key, value
        integer :: u, ios, k
        call put(self, key, value)
        if (.not. allocated(self%path)) return
        if (len(self%path) == 0) return
        if (.not. file_make_dirs(file_parent(self%path))) return
        open (newunit=u, file=self%path, status='replace', action='write', iostat=ios)
        if (ios /= 0) return
        do k = 1, self%count
            if (len(self%values(k)%s) == 0) cycle
            write (u, '(a)') trim(self%keys(k)) // achar(9) // escape(self%values(k)%s)
        end do
        close (u)
    end subroutine store_set

    subroutine put(self, key, value)
        type(store_t), intent(inout) :: self
        character(*), intent(in) :: key, value
        integer :: k
        character(len=256), allocatable :: more_keys(:)
        type(text_t), allocatable :: more_values(:)
        do k = 1, self%count
            if (trim(self%keys(k)) == key) then
                self%values(k)%s = value
                return
            end if
        end do
        if (.not. allocated(self%keys)) allocate (self%keys(16), self%values(16))
        if (self%count == size(self%keys)) then
            allocate (more_keys(2 * self%count), more_values(2 * self%count))
            more_keys(1:self%count) = self%keys
            do k = 1, self%count
                call move_alloc(self%values(k)%s, more_values(k)%s)
            end do
            call move_alloc(more_keys, self%keys)
            call move_alloc(more_values, self%values)
        end if
        self%count = self%count + 1
        self%keys(self%count) = key
        self%values(self%count)%s = value
    end subroutine put

    function escape(s) result(t)
        character(*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k
        t = ''
        do k = 1, len(s)
            select case (s(k:k))
            case ('\')
                t = t // '\\'
            case (achar(9))
                t = t // '\t'
            case (achar(10))
                t = t // '\n'
            case (achar(13))
                t = t // '\r'
            case default
                t = t // s(k:k)
            end select
        end do
    end function escape

    function unescape(s) result(t)
        character(*), intent(in) :: s
        character(len=:), allocatable :: t
        integer :: k
        t = ''
        k = 1
        do while (k <= len(s))
            if (s(k:k) == '\' .and. k < len(s)) then
                select case (s(k + 1:k + 1))
                case ('t'); t = t // achar(9)
                case ('n'); t = t // achar(10)
                case ('r'); t = t // achar(13)
                case default; t = t // s(k + 1:k + 1)
                end select
                k = k + 2
            else
                t = t // s(k:k)
                k = k + 1
            end if
        end do
    end function unescape

end module fortui_store
