program gui_test_standalone
#ifdef ENABLE_GUI
    use fortui_backend, only: backend_interface, get_backend
    use fortui_backend_init, only: ensure_backends_registered
    use fortui_gui, only: gui_backend_t
    
    class(backend_interface), pointer :: backend => null()
    logical :: available, quit
    integer :: i
    
    print *, "=== GUI Backend Test ==="
    
    ! Ensure backends are registered
    call ensure_backends_registered()
    
    ! Test GUI backend selection through registry
    backend => get_backend("gui")
    if (associated(backend)) then
        available = backend%is_available()
        print *, "  GUI Available:", available
        
        if (available) then
            ! Test GUI initialization
            call backend%init(80, 24, "Test Window", 60, .true.)
            print *, "  GUI Initialized: SUCCESS"
            
            ! Test frame cycle
            do i = 1, 5
                call backend%begin_frame()
                call backend%present()
                quit = backend%check_quit()
                print *, "  Frame", i, "- Quit:", quit
                if (quit) exit
            end do
            
            ! Test GUI shutdown
            call backend%shutdown()
            print *, "  GUI Shutdown: SUCCESS"
        else
            print *, "  GUI not available - running in headless mode"
        end if
    else
        print *, "  GUI backend not registered"
    end if
    
    print *, "=== GUI Backend Test Complete ==="
    
#else
    print *, "GUI backend not compiled (ENABLE_GUI not defined)"
#endif
end program
