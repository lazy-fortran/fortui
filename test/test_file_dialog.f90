program test_file_dialog
    use iso_c_binding, only: c_char, c_int, c_null_char
    use iso_fortran_env, only: int8
    use fortui
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
