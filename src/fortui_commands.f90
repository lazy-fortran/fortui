module fortui_commands
    !! Undo and redo. The application applies a change, then records it with
    !! the text that does it again and the text that takes it back; undo and
    !! redo hand that text back for the application to apply in its own way
    !! (an operation it sends, a field it sets):
    !!
    !!     call command_record(history, "Move coil2", "set coil2.offset 0.15", &
    !!         "set coil2.offset 0.19", merge="coil2.offset")
    !!     if (command_undo(history, text)) call apply(text)
    !!
    !! Changes recorded with the same `merge` key in quick succession (one
    !! slider drag) become one step that undoes to where they began.
    !! `command_shortcuts` gives Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y (Cmd on Apple
    !! systems), which text fields keep for their own undo.
    use fortui_core, only: ui_time, ui_shortcut
    implicit none
    private

    type :: command_t
        character(len=:), allocatable :: label, forward, backward, merge
        double precision :: time = 0d0
    end type command_t

    type, public :: command_history_t
        type(command_t), allocatable :: undo(:), redo(:)
        integer :: undo_count = 0, redo_count = 0
        !! Steps kept; the oldest go first.
        integer :: limit = 200
        !! Seconds within which changes with the same merge key join.
        double precision :: merge_seconds = 1.5d0
    end type command_history_t

    public :: command_record, command_undo, command_redo, command_undo_label, &
        command_redo_label, command_shortcuts, command_clear

contains

    subroutine command_record(h, label, forward, backward, merge)
        !! A change the application just applied: `forward` does it again,
        !! `backward` takes it back. Clears what could be redone.
        type(command_history_t), intent(inout) :: h
        character(*), intent(in) :: label, forward, backward
        character(*), intent(in), optional :: merge
        double precision :: now
        now = ui_time()
        h%redo_count = 0
        if (present(merge) .and. h%undo_count > 0) then
            associate (top => h%undo(h%undo_count))
                if (len(merge) > 0 .and. top%merge == merge .and. &
                    now - top%time <= h%merge_seconds) then
                    top%forward = forward
                    top%label = label
                    top%time = now
                    return
                end if
            end associate
        end if
        call grow(h%undo, h%undo_count)
        if (h%undo_count == h%limit) then
            h%undo(1:h%undo_count - 1) = h%undo(2:h%undo_count)
            h%undo_count = h%undo_count - 1
        end if
        h%undo_count = h%undo_count + 1
        h%undo(h%undo_count)%label = label
        h%undo(h%undo_count)%forward = forward
        h%undo(h%undo_count)%backward = backward
        h%undo(h%undo_count)%merge = ''
        if (present(merge)) h%undo(h%undo_count)%merge = merge
        h%undo(h%undo_count)%time = now
    end subroutine command_record

    logical function command_undo(h, text) result(done)
        !! The text that takes the last change back, if there is one.
        type(command_history_t), intent(inout) :: h
        character(len=:), allocatable, intent(out) :: text
        text = ''
        done = h%undo_count > 0
        if (.not. done) return
        text = h%undo(h%undo_count)%backward
        call grow(h%redo, h%redo_count)
        h%redo_count = h%redo_count + 1
        h%redo(h%redo_count) = h%undo(h%undo_count)
        h%undo_count = h%undo_count - 1
    end function command_undo

    logical function command_redo(h, text) result(done)
        !! The text that does the last undone change again, if there is one.
        type(command_history_t), intent(inout) :: h
        character(len=:), allocatable, intent(out) :: text
        text = ''
        done = h%redo_count > 0
        if (.not. done) return
        text = h%redo(h%redo_count)%forward
        call grow(h%undo, h%undo_count)
        h%undo_count = h%undo_count + 1
        h%undo(h%undo_count) = h%redo(h%redo_count)
        ! A redone step never joins the next change.
        h%undo(h%undo_count)%time = -1d9
        h%redo_count = h%redo_count - 1
    end function command_redo

    function command_undo_label(h) result(label)
        !! What Undo would take back ("" when nothing).
        type(command_history_t), intent(in) :: h
        character(len=:), allocatable :: label
        label = ''
        if (h%undo_count > 0) label = h%undo(h%undo_count)%label
    end function command_undo_label

    function command_redo_label(h) result(label)
        type(command_history_t), intent(in) :: h
        character(len=:), allocatable :: label
        label = ''
        if (h%redo_count > 0) label = h%redo(h%redo_count)%label
    end function command_redo_label

    logical function command_shortcuts(h, text) result(done)
        !! Undo (mod+z) or redo (mod+shift+z, mod+y) asked for in this frame:
        !! the text to apply.
        type(command_history_t), intent(inout) :: h
        character(len=:), allocatable, intent(out) :: text
        logical :: undo, redo
        text = ''
        undo = ui_shortcut('mod+z', label='Undo')
        redo = ui_shortcut('mod+shift+z', label='Redo')
        if (ui_shortcut('mod+y')) redo = .true.
        done = .false.
        if (undo) then
            done = command_undo(h, text)
        else if (redo) then
            done = command_redo(h, text)
        end if
    end function command_shortcuts

    subroutine command_clear(h)
        !! Forget every step (after loading another document).
        type(command_history_t), intent(inout) :: h
        h%undo_count = 0
        h%redo_count = 0
    end subroutine command_clear

    subroutine grow(list, n)
        type(command_t), allocatable, intent(inout) :: list(:)
        integer, intent(in) :: n
        type(command_t), allocatable :: more(:)
        if (.not. allocated(list)) allocate (list(16))
        if (n < size(list)) return
        allocate (more(2 * size(list)))
        more(1:n) = list(1:n)
        call move_alloc(more, list)
    end subroutine grow

end module fortui_commands
