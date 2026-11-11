program test_html
    !! The first frame as HTML matches what the browser host builds: nesting and
    !! order of containers and nodes, keys, escaping and native control types.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_html, only: ui_frame_html, html_escape
    use fortui_testing, only: ui_node_rect
    implicit none

    character(len=:), allocatable :: html, name, note
    integer :: stat, tab
    integer :: j, k
    integer(8) :: t0, t1, rate
    logical :: clicked
    real :: plain(4), rect(4)

    name = 'Ada "<x>"'
    note = 'a < b'//new_line('a')//'c'
    tab = 2
    call ui_init(headless_backend_t(), 800, 600, "html", stat=stat)
    call ui_frame_begin()
    call text("Title & more", style=UI_TITLE)
    call column_begin(10.0, id="c")
    call row_begin(8.0, height=40.0)
    call text("label")
    clicked = button("go", "Go")
    call row_end()
    if (text_input("name", name, width=UI_FILL)) continue
    if (text_input("note", note, placeholder="Note", lines=4)) continue
    call column_end()
    if (tabs("t", [character(len=4) :: "A", "B"], tab, width=200.0)) continue
    call text("after")
    call text(repeat("long ", 400)//"end", id="long")
    clicked = link("docs", "Docs & more", "/docs?a=1&b=2")
    call text("call f(1)", style=UI_CODE, ends=[4, 7, 8, 9], tones=[UI_TONE_KEYWORD, 0, UI_TONE_NUMBER, 0])
    call ui_present()
    html = ui_frame_html()
    call ui_shutdown()

    call check(index(html, '<div class="fui-root fui-box fui-col">') == 1, 'root container')
    call check(index(html, 'Title &amp; more') > 0, 'text is escaped')
    call check(at('data-key="1:~1"') < at('data-key="b1"'), 'the title comes before the column')
    call check(at('data-key="b1"') < at('data-key="b2"') .and. &
        at('data-key="b2"') < at('data-key="1:~2"'), 'the row is inside the column')
    call check(index(html, 'class="fui-box fui-row" style="gap: 8px; min-height: 40px;"') > 0, &
        'row with its gap and height')
    call check(index(html, '<button type="button" class="fui fui-k2" data-key="2:c/go" '// &
        'data-id="c/go"') > 0, 'button with key and id')
    call check(index(html, '<textarea rows="4" placeholder="Note"') > 0 .and. &
        index(html, '>a &lt; b'//new_line('a')//'c</textarea>') > 0, &
        'a field of several lines is a textarea with its escaped text')
    call check(index(html, 'value="Ada &quot;&lt;x&gt;&quot;"') > 0 .and. &
        index(html, 'align-self: stretch;') > 0, 'filling text field with its escaped value')
    call check(index(html, 'role="tab" aria-selected="true" class="fui fui-k5" data-key="5:t#2"') &
        > 0, 'selected tab')
    call check(at('data-key="5:t#1"') < at('data-key="1:~3"'), 'text after the tabs comes last')
    call check(index(html, '<span data-t="5">call</span><span> f(</span><span data-t="8">1</span><span>)</span>') &
        > 0, 'rich text as spans')
    call check(index(html, 'class="fui-box fui-col" data-box="c"') > 0, 'a container carries its id')
    call check(index(html, repeat("long ", 400)//"end</div>") > 0, 'a 2003-character text is not cut')
    call check(index(html, '<a href="/docs?a=1&amp;b=2" class="fui fui-k9" data-key="9:docs" '// &
        'data-id="docs" data-style="1" data-tone="14"') > 0 .and. index(html, '>Docs &amp; more</a>') > 0, &
        'a link is an anchor with its location')
    call check(html_escape('a<b>&"c"') == 'a&lt;b&gt;&amp;&quot;c&quot;', 'html_escape')

    ! Style names and page addresses: data-look and id on the elements that were
    ! given them, on no others, and the layout of other hosts is the same.
    call marks_frame(.false.)
    call check(count_of('data-look=') == 0 .and. count_of(' id="') == 0, &
        'without look and anchor no element carries data-look or id')
    plain = rect
    call marks_frame(.true.)
    call check(plain(3) > 0.0 .and. all(rect == plain), 'look and anchor leave the layout as it was')
    call check(index(html, 'class="fui-box fui-row" data-look="bar" id="checks" '// &
        'style="gap: 4px;"') > 0, 'a row carries its look and its anchor')
    call check(index(html, 'class="fui-box fui-col" data-look="list" style=') > 0, &
        'a column carries its look')
    call check(index(html, '<div class="fui fui-k1" data-key="1:~1" data-style="1" '// &
        'data-tone="17" data-look="state" id="L812"') > 0, &
        'a text carries the attention tone, its look and its anchor')
    call check(index(html, 'data-key="2:land" data-id="land" data-style="1" data-tone="0" '// &
        'data-look="primary" id="land-button"') > 0, 'a button carries its look and its anchor')
    call check(index(html, 'data-key="9:file" data-id="file" data-style="1" data-tone="14" '// &
        'data-look="path" id="f&quot;1"') > 0, 'a link carries its look and its escaped anchor')
    call check(count_of('data-look=') == 5 .and. count_of(' id="') == 4, &
        'elements without look or anchor carry neither')

    ! Names as the page can carry them: whole characters within the limits, no
    ! control characters, and an address on one element only, in every frame.
    do k = 1, 2
        call ui_init(headless_backend_t(), 800, 600, "html", stat=stat)
        call ui_frame_begin()
        call text("cut", look=repeat("l", 31)//"ä", anchor=repeat("a", 63)//"ä")
        call text("control", look="l"//achar(9)//"k", anchor="c"//achar(13)//"r"//achar(31)//"s")
        call text("dup one", anchor="dup")
        call row_begin(anchor="dup")
        call text("dup two", anchor="dup")
        call row_end()
        do j = 1, 200
            call text("line", anchor="L"//ui_str(j))
        end do
        call ui_present()
        html = ui_frame_html()
        call ui_shutdown()
    end do
    call check(index(html, ' data-look="'//repeat("l", 31)//'" id="'//repeat("a", 63)//'"') > 0, &
        'a look and an anchor are cut before a character that does not fit')
    call check(index(html, ' data-look="lk" id="crs"') > 0, &
        'control characters are left out of a look and an anchor')
    call check(count_of(' id="dup"') == 1 .and. at(' id="dup"') < at('dup one') .and. &
        at('dup one') < at('dup two'), 'of two elements with one anchor only the first carries it')
    call check(count_of(' id="L') == 200 .and. at(' id="L200"') > 0, &
        'two hundred anchors in one frame are all kept')

    ! A long page (a large diff): its HTML grows in time linear in its length.
    call ui_init(headless_backend_t(), 800, 600, "html", stat=stat)
    call ui_frame_begin()
    do k = 1, 200
        call column_begin(0.0, id="f"//ui_str(k))
        do j = 1, 100
            call text(repeat("x", 60), style=UI_CODE)
        end do
        call column_end()
    end do
    call ui_present()
    call system_clock(t0, rate)
    html = ui_frame_html()
    call system_clock(t1)
    call ui_shutdown()
    call check(at('data-box="f200"') < at('data-key="1:~20000"') .and. &
        at('data-key="1:~19901"') > at('data-box="f200"'), 'each block holds its lines')
    call check(real(t1 - t0) / real(rate) < 2.0, '20000 lines as HTML in under 2 s')
    print *, "fortui html tests passed"

contains

    subroutine marks_frame(marked)
        !! The same controls with or without look and anchor.
        logical, intent(in) :: marked

        call ui_init(headless_backend_t(), 800, 600, "html", stat=stat)
        call ui_frame_begin()
        if (marked) then
            call row_begin(4.0, look="bar", anchor="checks")
            call text("your turn", tone=UI_TONE_ATTENTION, look="state", anchor="L812")
            clicked = button("land", "Land", look="primary", anchor="land-button")
            clicked = link("file", "a.f90", "/f/a.f90", look="path", anchor='f"1')
            call row_end()
            call column_begin(look="list")
        else
            call row_begin(4.0)
            call text("your turn")
            clicked = button("land", "Land")
            clicked = link("file", "a.f90", "/f/a.f90")
            call row_end()
            call column_begin()
        end if
        call text("plain")
        call column_end()
        call ui_present()
        html = ui_frame_html()
        ! The last control of the row: its place depends on all before it.
        clicked = ui_node_rect("file", rect(1), rect(2), rect(3), rect(4))
        call ui_shutdown()
    end subroutine marks_frame

    integer function count_of(s)
        character(*), intent(in) :: s
        integer :: from, hit

        count_of = 0
        from = 1
        do
            hit = index(html(from:), s)
            if (hit == 0) exit
            count_of = count_of + 1
            from = from + hit
        end do
    end function count_of

    integer function at(s)
        character(*), intent(in) :: s
        at = index(html, s)
        if (at == 0) at = huge(1)
    end function at

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            print '(a)', html
            error stop 1
        end if
    end subroutine check

end program test_html
