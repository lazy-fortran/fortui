program simple_gui_test
#ifdef ENABLE_GUI
    use fortui_gui, only: is_gui_available_impl
    print *, "GUI module compiled successfully"
    print *, "GUI available:", is_gui_available_impl()
#else
    print *, "GUI module not compiled (ENABLE_GUI not defined)"
#endif
end program
