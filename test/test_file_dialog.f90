module file_dialog_test_backend
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t
    use fortui_input, only: input_state_t
    use fortui_canvas, only: canvas_store_t
    use fortui_text, only: text_use_fixed_metrics
    use iso_fortran_env, only: int64
    use fortui_files, only: FILE_PENDING, FILE_CANCELLED
    implicit none
    private

    logical, public :: start_native = .true.
    integer, public :: response = FILE_PENDING, cancellations = 0
    integer(int64), public :: current_request = 0, cancelled_request = 0
    character(:), allocatable, public :: selected_path
    type, extends(ui_backend_t), public :: dialog_test_backend_t
        logical :: running = .false.
        logical :: host_driven = .false.
    contains
        procedure :: name => dialog_test_name
        procedure :: init => dialog_test_init
        procedure :: shutdown => dialog_test_shutdown
        procedure :: poll => dialog_test_poll
        procedure :: present => dialog_test_present
        procedure :: should_close => dialog_test_should_close
        procedure :: install_text_metrics => dialog_test_metrics
        procedure :: capabilities => dialog_test_caps
        procedure :: file_open => test_open
        procedure :: file_poll => test_poll
        procedure :: file_cancel => test_cancel
    end type dialog_test_backend_t

contains

    function dialog_test_name(self) result(name)
        class(dialog_test_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
        name = "dialog_test"
    end function dialog_test_name

    logical function dialog_test_init(self)
        class(dialog_test_backend_t), intent(inout) :: self
        self%running = self%config%width > 0 .and. self%config%height > 0
        dialog_test_init = self%running
    end function dialog_test_init

    subroutine dialog_test_shutdown(self)
        class(dialog_test_backend_t), intent(inout) :: self
        self%running = .false.
    end subroutine dialog_test_shutdown

    subroutine dialog_test_poll(self, input, wait)
        class(dialog_test_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait
        if (wait) self%waits = self%waits + 1
        input%width = max(1, input%width)
        input%height = max(1, input%height)
        input%scale = max(1.0, input%scale)
    end subroutine dialog_test_poll

    subroutine dialog_test_present(self, frame, store)
        class(dialog_test_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        call self%canvas%realize_frame(store, frame)
        self%presents = self%presents + 1
    end subroutine dialog_test_present

    logical function dialog_test_should_close(self)
        class(dialog_test_backend_t), intent(in) :: self
        dialog_test_should_close = .not. self%running
    end function dialog_test_should_close

    subroutine dialog_test_metrics(self)
        class(dialog_test_backend_t), intent(inout) :: self
        call text_use_fixed_metrics()
    end subroutine dialog_test_metrics

    function dialog_test_caps(self) result(caps)
        class(dialog_test_backend_t), intent(in) :: self
        type(ui_backend_caps_t) :: caps
        caps%canvas_layers = .true.
        caps%pointer = .true.
        caps%text_entry = .true.
        caps%host_driven = self%host_driven
    end function dialog_test_caps

    logical function test_open(self, request, title, folder, extensions) result(started)
        class(dialog_test_backend_t), intent(inout) :: self
        integer(int64), intent(in) :: request
        character(*), intent(in) :: title, folder, extensions
        started = start_native
        if (started) current_request = request
    end function
    subroutine test_poll(self, request, status, path)
        class(dialog_test_backend_t), intent(inout) :: self
        integer(int64), intent(in) :: request
        integer, intent(out) :: status
        character(:), allocatable, intent(out) :: path
        status = FILE_CANCELLED
        path = ""
        if (request /= current_request) return
        status = response
        if (allocated(selected_path)) path = selected_path
    end subroutine
    subroutine test_cancel(self, request)
        class(dialog_test_backend_t), intent(inout) :: self
        integer(int64), intent(in) :: request
        cancellations = cancellations + 1
        cancelled_request = request
    end subroutine
end module file_dialog_test_backend

program test_file_dialog
    use iso_c_binding, only: c_char, c_int, c_null_char
    use iso_fortran_env, only: int8
    use fortui
    use file_dialog_test_backend
    use fortui_files
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_key, ui_inject_host, ui_focused_id, &
        ui_node_rect, ui_inject_pointer, ui_inject_wheel, ui_node_scroll
    use fortui_input, only: HOST_ACTIVATE, HOST_VALUE
    implicit none
    interface
        integer(c_int) function mkdir(path, mode) bind(C, name="mkdir")
            import c_char, c_int
            character(c_char), intent(in) :: path(*)
            integer(c_int), value :: mode
        end function
    end interface
    type(file_entry_t), allocatable :: entries(:)
    type(file_dialog_t) :: d
    integer(int8), allocatable :: bytes(:)
    character(:), allocatable :: message, names(:), saved
    integer(kind(current_request)) :: first_request
    integer :: rc, u, k, selected
    real :: x, y, w, h, scroll, content
    logical :: changed, go, found
    rc = mkdir("build" // c_null_char, 493_c_int)
    rc = mkdir("build/test-file-dialog" // c_null_char, 493_c_int)
    rc = mkdir("build/test-file-dialog/Album" // c_null_char, 493_c_int)
    open(newunit=u, file="build/test-file-dialog/Photo.JPG", status="replace", &
        access="stream", form="unformatted")
    write(u) [1_int8, 2_int8, 3_int8]
    close(u)
    open(newunit=u, file="build/test-file-dialog/notes.txt", status="replace")
    close(u)
    open(newunit=u, file="build/test-file-dialog/.hidden.png", status="replace")
    close(u)
    call file_list("build/test-file-dialog", entries, message, ".jpg,.jpeg,.png")
    call check(len(message) == 0 .and. size(entries) == 2, "filtered enumeration")
    call check(entries(1)%directory .and. entries(1)%name == "Album", "folders first")
    call check(entries(2)%name == "Photo.JPG", "case-insensitive extensions")
    call file_read("build/test-file-dialog/Photo.JPG", bytes, message)
    call check(size(bytes) == 3 .and. all(bytes == [1_int8,2_int8,3_int8]), "owned bytes")
    call file_write("build/test-file-dialog/out.bin", [-1_int8, 0_int8, 127_int8, -127_int8 - 1_int8], message)
    call check(len(message) == 0, "file written")
    call file_read("build/test-file-dialog/out.bin", bytes, message)
    call check(size(bytes) == 4 .and. all(bytes == [-1_int8, 0_int8, 127_int8, -127_int8 - 1_int8]), &
        "written bytes read back")
    call file_write("build/test-file-dialog/out.bin", [5_int8], message)
    call file_read("build/test-file-dialog/out.bin", bytes, message)
    call check(size(bytes) == 1, "writing replaces a longer file")
    call file_write("build/does-not-exist/out.bin", [5_int8], message)
    call check(len(message) > 0, "write failure")
    call check(file_parent("C:/Photos/test.jpg") == "C:/Photos", "Windows parent")
    call check(file_parent("C:/") == "C:/", "Windows drive root")
    call check(file_parent("/") == "/", "POSIX root")
    call check(file_join("/one", "/two/a.png") == "/two/a.png", "absolute path")
    call file_list("build/does-not-exist", entries, message)
    call check(size(entries) == 0 .and. len(message) > 0, "directory failure")
    call ui_init(headless_backend_t(), 800, 650, "file dialog")
    call file_dialog_open(d, "Open photo", "build/test-file-dialog", ".jpg,.jpeg,.png")
    call frame()
    call check(ui_focused_id() == "file-dialog/files", "initial keyboard focus")
    found = ui_node_rect("file-dialog/accept", x, y, w, h)
    call check(found .and. y + h <= 650.0, "dialog actions fit the window")
    call ui_inject_key(KEY_ARROW_DOWN)
    call frame()
    call check(d%filename == "Album", "keyboard selects folder")
    call ui_inject_key(KEY_ARROW_DOWN)
    call frame()
    call check(d%filename == "Photo.JPG", "keyboard selects image")
    call ui_inject_key(KEY_ENTER)
    call frame()
    call check(.not. d%active .and. d%status == FILE_ACCEPTED, "Enter accepts image")
    call check(d%path == file_absolute("build/test-file-dialog/Photo.JPG"), "selected path")
    saved = d%path
    call file_dialog_open(d, initial="build/test-file-dialog", extensions=".png")
    call frame()
    call ui_inject_key(KEY_ESCAPE)
    call frame()
    call check(.not. d%active .and. d%status == FILE_CANCELLED, "Escape cancels")
    call file_dialog_open(d, initial="build/test-file-dialog", extensions=".jpg")
    d%filename = "missing.jpg"
    call frame()
    call ui_inject_host(HOST_ACTIVATE, "file-dialog/accept")
    call frame()
    call check(d%active .and. len(d%message) > 0, "unreadable file stays in dialog")
    call ui_shutdown()
    call ui_init(headless_backend_t(), 640, 368, "compact dialog")
    call file_dialog_open(d, initial="build/test-file-dialog", extensions=".jpg")
    call frame()
    found = ui_node_rect("file-dialog/accept", x, y, w, h)
    call check(found .and. y + h <= 368.0, "compact dialog actions fit")
    d%message = "Cannot open this file. Check its location and permissions."
    call frame()
    found = ui_node_rect("file-dialog/accept", x, y, w, h)
    call check(found .and. y + h <= 368.0, "compact dialog error preserves actions")
    call ui_shutdown()
    allocate(character(24) :: names(40))
    do k = 1, size(names)
        names(k) = "Photo " // ui_str(k)
    end do
    call ui_init(headless_backend_t(), 300, 200, "list")
    selected = 0
    call list_frame()
    call ui_inject_key(KEY_END)
    call list_frame()
    call check(selected == 40, "End selects last item")
    found = ui_node_scroll("list", scroll, content, k)
    call check(scroll > 0, "keyboard selection scrolls into view")
    call ui_inject_key(KEY_HOME)
    call list_frame()
    call check(selected == 1, "Home selects first item")
    found = ui_node_rect("list", x,y,w,h)
    call ui_inject_pointer(x+20,y+30,.false.)
    call list_frame()
    call ui_inject_wheel(-3.0)
    call list_frame()
    found = ui_node_scroll("list", scroll, content, k)
    call check(scroll > 0, "wheel scrolls list")
    call ui_inject_pointer(x+w-2,y+20,.true.)
    call list_frame()
    call ui_inject_pointer(x+w-2,y+70,.true.)
    call list_frame()
    found = ui_node_scroll("list", content, h, k)
    call check(content > scroll, "scrollbar drag scrolls list")
    call ui_inject_pointer(x+w-2,y+70,.false.)
    call list_frame()
    call ui_shutdown()
    call ui_init(dialog_test_backend_t(), 800, 650, "native dialog")
    call file_dialog_open(d, initial="build/test-file-dialog", extensions=".jpg")
    call check(d%status == FILE_PENDING .and. .not. d%active, "native request preserves document composition")
    first_request = d%request
    call file_dialog_poll(d)
    call check(d%request == first_request, "pending request remains owned")
    selected_path = file_absolute("build/test-file-dialog/Photo ä space.JPG")
    response = FILE_ACCEPTED
    call file_dialog_poll(d)
    call check(d%status == FILE_ACCEPTED .and. d%path == selected_path, "native UTF-8 result")
    call check(d%name == "Photo ä space.JPG" .and. d%request == 0, "native result consumed once")
    selected_path = "changed after completion"
    call file_dialog_poll(d)
    call check(d%name == "Photo ä space.JPG", "result owns its path")
    response = FILE_PENDING
    call file_dialog_open(d)
    first_request = d%request
    call file_dialog_open(d)
    call check(cancelled_request == first_request .and. d%request /= first_request, "reopen cancels previous generation")
    response = FILE_CANCELLED
    call file_dialog_poll(d)
    call check(d%status == FILE_CANCELLED .and. .not. d%active, "native cancellation does not open fallback")
    call file_dialog_open(d)
    call file_dialog_cancel(d)
    call check(d%request == 0 .and. d%status == FILE_CANCELLED, "explicit cancellation releases request")
    call file_dialog_open(d)
    response = FILE_UNSUPPORTED
    call file_dialog_poll(d)
    call check(d%active .and. d%status == FILE_PENDING, "unavailable service opens in-window fallback")
    call file_dialog_cancel(d)
    start_native = .false.
    call file_dialog_open(d)
    call check(d%active .and. d%request == 0, "unsupported backend uses in-window chooser")
    call file_dialog_cancel(d)
    call ui_shutdown()
    print *, "File chooser navigation, filtering, selection, cancellation and errors passed"
contains
    subroutine check(ok, message)
        logical, intent(in) :: ok
        character(*), intent(in) :: message
        if (.not. ok) then
            print *, message
            error stop 1
        end if
    end subroutine
    subroutine frame()
        call ui_frame_begin()
        call file_dialog_show(d)
        call ui_present()
    end subroutine
    subroutine list_frame()
        call ui_frame_begin()
        changed = list_box("list", names, selected, go, height=100.0)
        call ui_focus("list")
        call ui_present()
    end subroutine
end program
