program gui_test_standalone
#ifdef ENABLE_GUI
    use fortui_gui, only: is_gui_available_impl, init_gui_backend_impl, &
                          begin_gui_frame_impl, present_gui_impl, &
                          check_gui_quit_impl, shutdown_gui_backend_impl
    
    logical :: available, quit, gui_initialized
    integer :: i
    
    print *, "=== GUI Backend Test ==="
    
    ! Test GUI availability detection
    available = is_gui_available_impl()
    print *, "  GUI Available:", available
    
    if (available) then
        ! Test GUI initialization
        call init_gui_backend_impl(80, 24, "Test Window", 60, .true.)
        gui_initialized = .true.
        print *, "  GUI Initialized: SUCCESS"
        
        ! Test frame cycle
        do i = 1, 5
            call begin_gui_frame_impl()
            call present_gui_impl(0)  ! Pass dummy tree
            quit = check_gui_quit_impl()
            print *, "  Frame", i, "- Quit:", quit
            if (quit) exit
        end do
        
        ! Test GUI shutdown
        call shutdown_gui_backend_impl()
        print *, "  GUI Shutdown: SUCCESS"
    else
        print *, "  GUI not available - running in headless mode"
    end if
    
    print *, "=== GUI Backend Test Complete ==="
    
#else
    print *, "GUI backend not compiled (ENABLE_GUI not defined)"
#endif
end program
