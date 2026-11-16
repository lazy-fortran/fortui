module fortui_file_dialog
    !! An owned Open request. Compose only this dialog while it is active, so
    !! keyboard and pointer input cannot reach the document underneath it.
    use iso_fortran_env, only: int8
    use fortui_files
    use fortui_core, only: ui_request_frame, ui_shortcut, ui_window_size
    use fortui_widgets, only: text, button, text_input, checkbox, list_box, ui_focus
    use fortui_layout, only: column_begin, column_end, row_begin, row_end, &
        layout_available, dialog_begin, dialog_end
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_frame, only: UI_TITLE, UI_CAPTION, UI_HEADING, UI_TONE_NEGATIVE, UI_FILL, &
        UI_EMPHASIS_PRIMARY, ui_control_height
    use fortui_input, only: input_host_value
    use fortui_text, only: text_line_height, ui_str
    implicit none
    private
    integer, parameter, public :: FILE_IDLE = 0, FILE_PENDING = 1, FILE_ACCEPTED = 2, &
        FILE_CANCELLED = 3
    type, public :: file_dialog_t
        integer :: status = FILE_IDLE
        logical :: active = .false., hidden = .false., all_files = .false.
        logical :: first_frame = .false.
        character(:), allocatable :: title, folder, location, filename, search, message
        character(:), allocatable :: extensions, path, name
        integer(int8), allocatable :: bytes(:)
        type(file_entry_t), allocatable :: entries(:)
        integer :: selected = 0
    end type
    public :: file_dialog_open, file_dialog_show, file_open_button
contains
    subroutine file_dialog_open(d, title, initial, extensions)
        type(file_dialog_t), intent(inout) :: d
        character(*), intent(in), optional :: title, initial, extensions
        character(:), allocatable :: start
        d%title = "Open file"
        if (present(title)) d%title = title
        d%extensions = ""
        if (present(extensions)) d%extensions = extensions
        d%filename = ""
        d%search = ""
        d%path = ""
        d%name = ""
        if (allocated(d%bytes)) deallocate(d%bytes)
        start = file_home()
        if (allocated(d%folder)) start = d%folder
        if (present(initial)) then
            if (len_trim(initial) > 0) then
                start = initial
                if (.not. file_is_directory(start)) start = file_parent(start)
            end if
        end if
        if (.not. allocated(d%folder)) d%folder = file_home()
        if (.not. file_is_directory(d%folder)) d%folder = "."
        call navigate(d, start)
        if (.not. allocated(d%entries)) call navigate(d, d%folder)
        d%status = FILE_PENDING
        d%active = .true.
        d%first_frame = .true.
        call ui_request_frame()
    end subroutine
    subroutine file_open_button(id, label, d, title, initial, extensions, width)
        character(*), intent(in) :: id, label
        type(file_dialog_t), intent(inout) :: d
        character(*), intent(in), optional :: title, initial, extensions
        real, intent(in), optional :: width
        type(fortui_context_t), pointer :: ctx
        character(:), allocatable :: picked, msg
        integer :: k, u, ios
        logical :: clicked
        clicked = button(id, label, width=width)
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        k = ctx%current_frame%count
        if (k < 1) return
        ctx%current_frame%nodes(k)%file_accept = ""
        if (present(extensions)) ctx%current_frame%nodes(k)%file_accept = extensions
        if (ctx%backend_name == "web") then
            if (.not. input_host_value(ctx%input, &
                trim(ctx%current_frame%nodes(k)%id), picked)) return
            d%message = ""
            if (len(picked) == 0) then
                d%status = FILE_CANCELLED
                return
            end if
            ! The host owns the temporary capability until its bytes are copied.
            call file_read(picked, d%bytes, msg)
            open(newunit=u, file=picked, status="old", iostat=ios)
            if (ios == 0) close(u, status="delete")
            if (len(msg) > 0) then
                d%message = msg
                d%status = FILE_CANCELLED
                return
            end if
            d%path = ""
            d%name = file_name(picked)
            d%status = FILE_ACCEPTED
        else if (clicked) then
            call file_dialog_open(d, title, initial, extensions)
        end if
    end subroutine
    subroutine navigate(d, folder)
        type(file_dialog_t), intent(inout) :: d
        character(*), intent(in) :: folder
        type(file_entry_t), allocatable :: entries(:)
        character(:), allocatable :: message, filter, full
        full = file_absolute(folder)
        filter = d%extensions
        if (d%all_files) filter = ""
        call file_list(full, entries, message, filter, d%hidden)
        d%message = message
        if (.not. file_is_directory(full)) return
        d%folder = full
        d%location = full
        d%filename = ""
        d%selected = 0
        call move_alloc(entries, d%entries)
    end subroutine
    subroutine accept_name(d)
        type(file_dialog_t), intent(inout) :: d
        character(:), allocatable :: path
        if (len_trim(d%filename) == 0) return
        path = file_join(d%folder, trim(d%filename))
        if (file_is_directory(path)) then
            call navigate(d, path)
            return
        end if
        if (.not. file_is_readable(path)) then
            d%message = "Cannot open this file. Check its location and permissions."
            return
        end if
        d%path = path
        d%name = file_name(path)
        d%active = .false.
        d%status = FILE_ACCEPTED
        call ui_request_frame()
    end subroutine
    subroutine file_dialog_show(d)
        type(file_dialog_t), intent(inout) :: d
        character(:), allocatable :: labels(:), home, next, needle
        integer, allocatable :: map(:)
        real :: w, h, gap, list_h, side
        integer :: i, n, longest, selected, old
        logical :: changed, go, submit, compact
        if (.not. d%active) return
        if (ui_shortcut("Escape", label="Cancel")) then
            d%status = FILE_CANCELLED
            d%active = .false.
            call ui_request_frame()
            return
        end if
        call ui_window_size(w, h)
        compact = h < 520.0
        gap = 6.0
        if (compact) gap = 4.0
        call dialog_begin("file-dialog", 880.0, 660.0, gap, merge(8.0,16.0,compact))
        call text(d%title, style=merge(UI_HEADING,UI_TITLE,compact))
        call layout_available(w, h)
        call row_begin(gap)
        if (button("up", "Up", width=52.0) .or. &
            ui_shortcut("alt+ArrowUp", label="Up folder")) then
            next = file_parent(d%folder)
            call navigate(d, next)
        end if
        if (text_input("location", d%location, submitted=submit, &
            width=max(100.0, w - 58.0))) continue
        if (submit) then
            next = d%location
            call navigate(d, next)
        end if
        call row_end()
        if (ui_shortcut("mod+l", label="Location")) call ui_focus("location")
        if (text_input("search", d%search, placeholder="Filter this folder", &
            width=UI_FILL)) continue
        call layout_available(w, h)
        list_h = max(48.0, h - 4 * (ui_control_height() + gap) - &
            2 * text_line_height(15.0))
        if (compact) list_h = max(32.0, h - 3 * (ui_control_height() + gap) - &
            text_line_height(15.0) - gap)
        side = min(128.0, max(80.0, w * 0.2))
        call row_begin(gap)
        if (.not. compact) then
            call column_begin(gap)
            home = file_home()
            if (button("home", "Home", width=side)) call navigate(d, home)
            if (button("pictures", "Pictures", width=side)) &
                call navigate(d, file_join(home, "Pictures"))
            if (button("downloads", "Downloads", width=side)) &
                call navigate(d, file_join(home, "Downloads"))
            call column_end()
        end if
        n = 0
        longest = 1
        needle = file_lower(trim(d%search))
        allocate(map(size(d%entries)))
        do i = 1, size(d%entries)
            if (index(file_lower(d%entries(i)%name), needle) == 0) cycle
            n = n + 1
            map(n) = i
            longest = max(longest, len(d%entries(i)%name) + 3)
        end do
        allocate(character(longest) :: labels(n))
        selected = 0
        do i = 1, n
            labels(i) = d%entries(map(i))%name
            if (d%entries(map(i))%directory) labels(i) = "[" // trim(labels(i)) // "]"
            if (map(i) == d%selected) selected = i
        end do
        old = selected
        changed = list_box("files", labels, selected, go, width=UI_FILL, height=list_h)
        if (d%first_frame) then
            call ui_focus("files")
            d%first_frame = .false.
        end if
        if (selected > 0) then
            d%selected = map(selected)
            if (selected /= old .or. go) d%filename = d%entries(d%selected)%name
            if (go) call accept_name(d)
        end if
        call row_end()
        if (.not. compact) then
            if (n == 0) then
                call text("No matching files. Change the filter or choose another folder.", &
                    style=UI_CAPTION, width=UI_FILL)
            else
                call text(ui_str(n) // " items", style=UI_CAPTION)
            end if
        end if
        call row_begin(gap)
        changed = checkbox("all-files", d%all_files, "All file types")
        changed = checkbox("hidden", d%hidden, "Hidden files") .or. changed
        if (changed) then
            next = d%folder
            call navigate(d, next)
        end if
        call row_end()
        if (.not. compact) call text("File name", style=UI_CAPTION)
        if (text_input("filename", d%filename, placeholder="Choose a file or enter its path", &
            submitted=submit, width=UI_FILL)) continue
        if (submit) call accept_name(d)
        if (.not. compact .or. len(d%message) > 0) &
            call text(d%message, tone=UI_TONE_NEGATIVE, width=UI_FILL)
        call layout_available(w, h)
        call row_begin(gap)
        call text("", width=max(0.0, w - 172.0))
        if (button("cancel", "Cancel", width=80.0)) then
            d%active = .false.
            d%status = FILE_CANCELLED
        end if
        if (button("accept", "Open", width=80.0, emphasis=UI_EMPHASIS_PRIMARY, &
            enabled=len_trim(d%filename) > 0)) call accept_name(d)
        call row_end()
        call dialog_end()
    end subroutine
end module fortui_file_dialog
