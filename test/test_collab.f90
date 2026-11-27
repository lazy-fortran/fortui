program test_collab
    !! Undo and redo (merged drags, labels, the kept limit), values kept between
    !! runs (memory and file), parameters of the address on hosts without a
    !! page, and people's avatars (initials, a stable colour).
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_node_text
    implicit none
    integer :: fails = 0, stat, k, u
    type(command_history_t) :: h
    character(len=:), allocatable :: t, path
    character(len=512) :: tmp
    integer :: n

    call ui_init(headless_backend_t(), 300, 200, 'collab', stat=stat)

    ! --- undo and redo ---------------------------------------------------------
    call command_record(h, 'Move coil2', 'set coil2 0.16', 'set coil2 0.19', merge='coil2')
    call command_record(h, 'Move coil2', 'set coil2 0.15', 'set coil2 0.16', merge='coil2')
    call command_record(h, 'Rename', 'name b', 'name a')
    call check(h%undo_count == 2, 'a drag in quick succession is one step')
    call check(command_undo_label(h) == 'Rename', 'Undo names the last change')
    call check(command_undo(h, t) .and. t == 'name a', 'undo gives the text that takes it back')
    call check(command_undo(h, t) .and. t == 'set coil2 0.19', 'a merged drag undoes to where it began')
    call check(.not. command_undo(h, t), 'nothing more to undo')
    call check(command_redo_label(h) == 'Move coil2', 'Redo names what it does again')
    call check(command_redo(h, t) .and. t == 'set coil2 0.15', 'redo gives the merged end')
    call command_record(h, 'Rename', 'name c', 'name a')
    call check(.not. command_redo(h, t), 'a new change clears what could be redone')
    h%limit = 3
    do k = 1, 5
        call command_record(h, 'Step', 'f' // ui_str(k), 'b' // ui_str(k))
    end do
    call check(h%undo_count == 3, 'only the newest steps are kept')
    do k = 1, 3
        if (command_undo(h, t)) continue
    end do
    call check(t == 'b3', 'the oldest kept step is the third of five')

    ! --- values kept between runs ------------------------------------------------
    call check(ui_store_get('name') == '', 'nothing kept at first')
    call ui_store_set('name', 'user7')
    call check(ui_store_get('name') == 'user7', 'a value is kept')
    call get_environment_variable('TMPDIR', tmp, n)
    if (n == 0) tmp = '/tmp'
    path = trim(tmp) // '/fortui-test-collab/store.tsv'
    call ui_store_use(path)
    call ui_store_set('name', 'user8')
    call ui_store_set('draft', 'line one' // achar(10) // 'tab' // achar(9) // 'end \ slash')
    call ui_store_use('')
    call check(ui_store_get('name') == '', 'a memory store is empty')
    call ui_store_use(path)
    call check(ui_store_get('name') == 'user8', 'the file keeps a value for the next run')
    call check(ui_store_get('draft') == 'line one' // achar(10) // 'tab' // achar(9) // 'end \ slash', &
        'line ends, tabs and backslashes survive')
    call ui_store_set('draft', '')
    call ui_store_use(path)
    call check(ui_store_get('draft') == '' .and. ui_store_get('name') == 'user8', 'an empty value removes it')
    open (newunit=u, file=path, status='old')
    close (u, status='delete')

    ! --- the address --------------------------------------------------------------
    call ui_set_url_param('branch', 'cand-a')
    call ui_set_url_param('tab', 'review', push=.true.)
    call check(ui_url_param('branch') == 'cand-a', 'a parameter set is read back')
    call check(ui_location() == '?branch=cand-a&tab=review', 'the address to share: ' // ui_location())
    call ui_set_url_param('tab', '')
    call check(ui_location() == '?branch=cand-a', 'an empty value removes the parameter')

    ! --- people --------------------------------------------------------------------
    call ui_frame_begin()
    call row_begin(4.0)
    call text('x', id='x')
    call avatar('Chris Albert')
    call avatar('user42')
    call avatar('王小明')
    call row_end()
    call ui_present()
    call check(ui_user_colour('user42') == ui_user_colour('user42') .and. &
        ui_user_colour('user42') /= ui_user_colour('user43'), 'each person has a stable colour')
    call check(avatar_texts() == 'CA|Us|王', 'initials: ' // avatar_texts())

    if (fails > 0) error stop 1
    print '(a)', 'test_collab: all passed'

contains

    function avatar_texts() result(s)
        use fortui_context, only: fortui_context_t, get_default_context
        type(fortui_context_t), pointer :: ctx
        character(len=:), allocatable :: s
        integer :: i
        ctx => get_default_context()
        s = ''
        do i = 1, ctx%previous_frame%count
            if (ctx%previous_frame%nodes(i)%look /= 'fui-avatar') cycle
            if (len(s) > 0) s = s // '|'
            s = s // trim(ctx%previous_frame%nodes(i)%text)
        end do
    end function avatar_texts

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            fails = fails + 1
            print '(a)', 'FAIL: ' // what
        end if
    end subroutine check

end program test_collab
