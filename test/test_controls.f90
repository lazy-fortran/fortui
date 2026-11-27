program test_controls
    !! Scroll containers (clipping, wheel, following the end), virtual lists,
    !! drop-down lists, menus, segmented choices, the data grid, notifications,
    !! modal dialogs and symbols.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_node_rect, ui_inject_pointer, ui_inject_wheel, ui_inject_host, &
        ui_inject_key, ui_node_count
    use fortui_icons, only: icon_svg, icon_polylines, icon_path
    use fortui_input, only: HOST_VALUE, HOST_DISMISS
    implicit none
    integer :: section = 1
    character(len=8) :: view_id = 'view'
    integer :: fails = 0, stat, lines, k, pick, seg, chosen, first, last, page_clicks
    logical :: stick, show_modal = .false.
    real :: x, y, w, h, y_before, vx, vy, vw, vh
    character(len=12) :: options(3), cols(2), cells(2, 5)
    type(grid_state_t) :: grid
    real, allocatable :: xy(:, :)
    integer, allocatable :: starts(:)
    integer :: n
    double precision :: t0

    options = [character(len=12) :: 'Alpha', 'Beta', 'Gamma']
    cols = [character(len=12) :: 'Name', 'Ripple']
    cells = reshape([character(len=12) :: 'c', '10', 'a', '2.5', 'b', '-1', 'd', '100', 'e', 'n/a'], [2, 5])
    call ui_init(headless_backend_t(), 800, 600, 'controls', stat=stat)

    ! --- scroll container ---------------------------------------------------------
    lines = 40
    stick = .false.
    call scroll_frames(2)
    call check(ui_node_rect('view/line1', vx, vy, vw, vh), 'the first line is composed')
    call check(ui_node_rect('above', x, y, w, h) .and. abs(y + h - vy) < 1.0, &
        'the first line starts at the top of the viewport')
    call check(ui_node_rect('below', x, y, w, h) .and. abs(y - (vy + 200.0)) < 13.0, &
        'what follows the container comes after its 200 unit viewport')
    call ui_node_rect_or('line1', x, y_before)
    call ui_inject_pointer(vx + 20.0, vy + 100.0, .false.)
    call ui_inject_wheel(-2.0)
    call scroll_frames(2)
    call ui_node_rect_or('line1', x, y)
    call check(y < y_before - 50.0, 'the wheel over the viewport scrolls its content')
    ! A button scrolled out of view takes no click where it would be.
    page_clicks = 0
    call ui_inject_pointer(vx + 20.0, y_before + 2.0, .true.)
    call scroll_frames(1)
    call ui_inject_pointer(vx + 20.0, y_before + 2.0, .false.)
    call scroll_frames(1)
    call check(page_clicks == 0, 'a button clipped away takes no click')

    stick = .true.
    view_id = 'chat'
    lines = 40
    call scroll_frames(3)
    call ui_node_rect_or('line40', x, y, h)
    call check(y + h <= vy + 200.0 + 1.0 .and. y >= vy, 'a sticking view shows the last line')
    lines = 45
    call scroll_frames(3)
    call ui_node_rect_or('line45', x, y, h)
    call check(y + h <= vy + 200.0 + 1.0 .and. y >= vy, 'it keeps showing the end as lines arrive')
    call ui_inject_pointer(vx + 20.0, vy + 100.0, .false.)
    call ui_inject_wheel(3.0)
    call scroll_frames(2)
    lines = 50
    call scroll_frames(3)
    call ui_node_rect_or('line50', x, y)
    call check(y >= vy + 200.0, 'scrolled up, the view stays where the reader is')

    ! --- virtual list ---------------------------------------------------------------
    call ui_inject_pointer(-10.0, -10.0, .false.)
    call virtual_frame()
    call check(first == 1 .and. last < 20, 'a virtual list composes the rows in view only')
    call check(ui_node_count() < 40, 'ten thousand rows stay a screenful of nodes')
    call ui_inject_host(HOST_VALUE, 'big', '24000')
    call virtual_frame()
    call check(first > 990 .and. first <= 1001 .and. last < 1020, 'the host''s offset picks the rows')
    call check(ui_node_rect('big/r1001', x, y, w, h), 'row 1001 is composed after scrolling')

    ! --- drop-down, menu, segmented ----------------------------------------------------
    pick = 1
    seg = 1
    chosen = 0
    page_clicks = 0
    call choice_frames(1)
    call click('pick')
    call check(ui_node_rect('pick.list/item#3', x, y, w, h), 'a click opens the drop-down list')
    call click('pick.list/item#3')
    call check(pick == 3, 'choosing an option selects it')
    call check(.not. ui_node_rect('pick.list/item#3', x, y, w, h), 'and closes the list')
    call ui_inject_host(HOST_VALUE, 'pick', '2')
    call choice_frames(1)
    call check(pick == 2, 'the browser''s picker selects by number')
    call click('pick')
    call ui_inject_key(KEY_ESCAPE)
    call choice_frames(2)
    call check(.not. ui_node_rect('pick.list/item#1', x, y, w, h), 'Escape closes the list')

    call click('actions')
    call check(ui_node_rect('actions.list/item#2', x, y, w, h), 'a click opens the menu')
    ! The menu floats over the page button beneath it and takes the click.
    call check(ui_node_rect('under-b', vx, vy, vw, vh) .and. vy < y + h .and. vy + vh > y, &
        'the page button lies under the open menu')
    call click('actions.list/item#2')
    call check(chosen == 2 .and. page_clicks == 0, 'the menu item, not the page beneath, takes the click')
    call click('actions')
    call ui_inject_host(HOST_DISMISS, 'actions.list')
    call choice_frames(2)
    call check(.not. ui_node_rect('actions.list/item#1', x, y, w, h), 'a press outside dismisses the menu')
    call click('tool/option#2')
    call check(seg == 2, 'a segment selects its option')

    section = 2
    ! --- data grid ------------------------------------------------------------------------
    call grid_frames(1)
    call click('grid/head#2')
    call check(grid%sort_column == 2, 'a heading sorts by its column')
    call check(all(grid%order(1:4) == [3, 2, 1, 4]), 'numbers sort as numbers, text after them')
    call click('grid/head#2')
    call check(grid%descending .and. grid%order(1) == 4, 'again: the other way')
    grid%filter = 'a'
    grid%dirty = .true.
    call grid_frames(1)
    call check(size(grid%order) == 2, 'the filter keeps rows with its text in a cell')
    grid%filter = ''
    call grid_frames(1)
    call click('grid/rows/row#5')
    call check(grid%selected == 5, 'a click on a row selects it')

    ! --- notifications and dialogs -------------------------------------------------------
    call toast('Saved', UI_TONE_POSITIVE, seconds=0.3)
    call plain_frames(1)
    call check(ui_node_rect('fui-toasts/toast1/close', x, y, w, h), 'a notification shows')
    t0 = ui_time()
    do while (ui_time() - t0 < 0.6d0)
    end do
    call plain_frames(1)
    call check(.not. ui_node_rect('fui-toasts/toast1/close', x, y, w, h), 'it goes after its time')

    section = 3
    show_modal = .true.
    page_clicks = 0
    call plain_frames(1)
    call check(ui_node_rect('under2', x, y, w, h), 'the page button is composed under the dialog')
    call ui_inject_pointer(x + 2.0, y + 2.0, .true.)
    call plain_frames(1)
    call ui_inject_pointer(x + 2.0, y + 2.0, .false.)
    call plain_frames(1)
    call check(page_clicks == 0, 'while a modal dialog is open the page takes no click')
    call click('ask/ok')
    call check(.not. show_modal, 'the dialog''s own button works')

    ! --- symbols ----------------------------------------------------------------------------
    call check(icon_svg('O12 12 2') == 'M10 12 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0', &
        'a circle becomes two arcs')
    call icon_polylines(icon_path('close'), xy, starts, n)
    call check(n == 2 .and. starts(3) == 5, 'the close symbol is two strokes')
    call check(all([(len(icon_path(icon_names_at(k))) > 0, k = 1, size(icon_names()))]), &
        'every symbol has strokes')

    if (fails > 0) error stop 1
    print '(a)', 'test_controls: all passed'

contains

    function icon_names_at(k) result(name)
        integer, intent(in) :: k
        character(len=:), allocatable :: name
        character(len=14) :: all(size(icon_names()))
        all = icon_names()
        name = trim(all(k))
    end function icon_names_at

    subroutine ui_node_rect_or(id, x, y, h)
        character(*), intent(in) :: id
        real, intent(out) :: x, y
        real, intent(out), optional :: h
        real :: w, hh
        if (.not. ui_node_rect(trim(view_id) // '/' // id, x, y, w, hh)) then
            x = -1.0
            y = 1.0e9
        end if
        if (present(h)) h = hh
    end subroutine ui_node_rect_or

    subroutine scroll_frames(count)
        integer, intent(in) :: count
        integer :: f, j
        do f = 1, count
            call ui_frame_begin()
            call text('above', id='above')
            call scroll_begin(trim(view_id), 200.0, stick=stick)
            do j = 1, lines
                if (j == 1) then
                    if (button('line1', 'Line 1', height=20.0)) page_clicks = page_clicks + 1
                else
                    call text('Line ' // ui_str(j), id='line' // ui_str(j), size=14.0)
                end if
            end do
            call scroll_end()
            call text('below', id='below')
            call ui_present()
        end do
    end subroutine scroll_frames

    subroutine virtual_frame()
        integer :: r
        call ui_frame_begin()
        call virtual_list_begin('big', 10000, 24.0, 240.0, first, last)
        do r = first, last
            call row_begin(0.0, height=24.0)
            call text('Row ' // ui_str(r), id='r' // ui_str(r))
            call row_end()
        end do
        call virtual_list_end()
        call ui_present()
    end subroutine virtual_frame

    subroutine choice_frames(count)
        integer, intent(in) :: count
        integer :: f, c
        character(len=12) :: items(3), tools(2)
        items = [character(len=12) :: 'Open', 'Rename', 'Delete']
        tools = [character(len=12) :: 'Pen', 'Eraser']
        do f = 1, count
            call ui_frame_begin()
            call row_begin(8.0)
            if (dropdown('pick', options, pick)) continue
            c = menu('actions', 'Actions', items)
            if (c > 0) chosen = c
            call row_end()
            if (button('under', 'Under the menu', width=400.0)) page_clicks = page_clicks + 1
            if (button('under-b', 'Also under', width=400.0)) page_clicks = page_clicks + 1
            if (segmented('tool', tools, seg)) continue
            call ui_present()
        end do
    end subroutine choice_frames

    subroutine grid_frames(count)
        integer, intent(in) :: count
        integer :: f
        do f = 1, count
            call ui_frame_begin()
            if (data_grid('grid', cols, cells, grid, 300.0)) continue
            call ui_present()
        end do
    end subroutine grid_frames

    subroutine plain_frames(count)
        integer, intent(in) :: count
        integer :: f
        do f = 1, count
            call ui_frame_begin()
            if (button('under2', 'Page', width=700.0, height=400.0)) page_clicks = page_clicks + 1
            if (show_modal) then
                call modal_begin('ask', 'Discard the branch?', 360.0, 160.0)
                if (button('ok', 'Discard')) show_modal = .false.
                call modal_end()
            end if
            call ui_present()
        end do
    end subroutine plain_frames

    subroutine click(id)
        !! Press and release on the centre of `id`, composing with the frame
        !! routine of the section under test.
        character(*), intent(in) :: id
        real :: cx, cy, cw, ch
        if (.not. ui_node_rect(id, cx, cy, cw, ch)) then
            call check(.false., 'no node ' // id // ' to click')
            return
        end if
        call ui_inject_pointer(cx + 0.5 * cw, cy + 0.5 * ch, .true.)
        call again()
        call ui_inject_pointer(cx + 0.5 * cw, cy + 0.5 * ch, .false.)
        call again()
        call again()
    end subroutine click

    subroutine again()
        select case (section)
        case (2); call grid_frames(1)
        case (3); call plain_frames(1)
        case default; call choice_frames(1)
        end select
    end subroutine again

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            fails = fails + 1
            print '(a)', 'FAIL: ' // what
        end if
    end subroutine check

end program test_controls
