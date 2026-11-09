program web_demo_ssr
    !! The web demo's first frame as HTML, as a server would send it before the
    !! WebAssembly starts, written to the file named by the first argument
    !! (used by test/web_browser_test.mjs).
    use fortui, only: ui_init, ui_frame_begin, ui_present, ui_shutdown
    use fortui_backend_headless, only: headless_backend_t
    use fortui_html, only: ui_frame_html
    use web_demo_app, only: compose
    implicit none
    integer :: stat, u
    character(len=1024) :: path

    call get_command_argument(1, path)
    call ui_init(headless_backend_t(), 900, 640, "FortUI web demo", stat=stat)
    call ui_frame_begin()
    call compose()
    call ui_present()
    open (newunit=u, file=trim(path), status='replace', action='write')
    write (u, '(a)') ui_frame_html()
    close (u)
    call ui_shutdown()
end program web_demo_ssr
