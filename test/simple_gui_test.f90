program simple_gui_test
#ifdef ENABLE_GUI
    use fortui_backend, only: backend_interface, get_backend
    use fortui_backend_init, only: ensure_backends_registered
    
    ! Backend interface removed - testing with immediate mode API
    logical :: available
    
    print *, "GUI module compiled successfully"
    
    ! Ensure backends are registered
    call ensure_backends_registered()
    
    ! Test GUI backend availability
    backend => get_backend("gui")
    if (associated(backend)) then
        available = backend%is_available()
        print *, "GUI available:", available
    else
        print *, "GUI backend not registered"
    end if
#else
    print *, "GUI module not compiled (ENABLE_GUI not defined)"
#endif
end program
