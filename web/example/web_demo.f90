program web_demo
    !! The same semantic controls as the terminal and GUI demos, realized as DOM
    !! elements in a browser.
    use fortui, only: ui_init, ui_run
    use fortui_web, only: web_backend_t
    use web_demo_app, only: compose
    implicit none
    integer :: stat

    call ui_init(web_backend_t(root_id="app"), 900, 640, "FortUI web demo", stat=stat)
    if (stat /= 0) error stop "No browser document available"
    call ui_run(compose)
end program web_demo
