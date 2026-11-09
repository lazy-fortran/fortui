program test_html
    !! The first frame as HTML matches what the browser host builds: nesting and
    !! order of containers and nodes, keys, escaping and native control types.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_html, only: ui_frame_html, html_escape
    implicit none

    character(len=:), allocatable :: html, name
    integer :: stat, tab
    integer :: j, k
    integer(8) :: t0, t1, rate
    logical :: clicked

    name = 'Ada "<x>"'
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
