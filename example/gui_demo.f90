program gui_demo
! Comprehensive GUI backend demonstration
! Shows automatic backend selection, GUI features, and cross-platform compatibility
use fortui
implicit none

logical :: running, save_clicked, load_clicked, auto_save
real :: volume = 50.0, brightness = 75.0
integer :: frame_count = 0
character(len=64) :: status_text
type(view) :: plot_view
! Text node types removed - text widgets work immediate-mode
type(node) :: root_node  ! Root node for UI tree

print *, "=== fortui GUI Backend Demo ==="
print *, ""

! Automatic backend selection - uses GUI if available, TUI otherwise
call ui_init("auto", 640, 480, "fortui GUI Demo", target_fps=60, vsync=.true.)

! Configure power-efficient settings for GUI mode
#ifdef ENABLE_GUI
    print *, "GUI backend compiled in - using raylib for pixel-perfect rendering"
    call ui_set_idle_policy("adaptive", idle_fps=12)
#else
    print *, "TUI-only mode - using terminal with cell-based rendering"  
#endif
print *, ""

running = .true.
do while (running)
    call ui_frame_begin(timeout_ms=50)  ! Fast updates for smooth demo
    frame_count = frame_count + 1
    
    ! Create status text
    write(status_text, '("Frame: ",I6," | Volume: ",F4.1,"% | Brightness: ",F4.1,"%")') &
        frame_count, volume, brightness
    
    ! Demo UI with various widgets  
    call text("title", "fortui GUI Backend Demo", text_size=20.0)
    call text("subtitle", "Cross-platform GUI with raylib integration")
    call text("status", status_text)
    
    ! Interactive controls
    save_clicked = button("save", "Save Settings", width=120.0, height=35.0)
    load_clicked = button("load", "Load Settings", width=120.0, height=35.0)
    
    ! Sliders for numeric input
    if (slider("volume", 0.0, 100.0, 1.0, volume, width=200.0)) then
        ! Volume changed - could trigger audio update
    end if
    
    if (slider("brightness", 0.0, 100.0, 1.0, brightness, width=200.0)) then  
        ! Brightness changed - could trigger display update
    end if
    
    ! Checkbox for toggles
    auto_save = checkbox("autosave", auto_save, "Enable Auto-Save")
    
    ! Viewport for interactive content
    if (viewport("demo_plot", 400.0, 200.0, plot_view)) then
        ! View changed - could trigger plot redraw
    end if
    
    ! Handle button clicks
    if (save_clicked) then
        print *, "Saving settings: Volume=", volume, "Brightness=", brightness, &
                 "Auto-save=", auto_save
    end if
    
    if (load_clicked) then
        ! Reset to defaults
        volume = 50.0
        brightness = 75.0
        auto_save = .false.
        print *, "Settings loaded (reset to defaults)"
    end if
    
    ! End the frame properly to avoid warning spam
    ! Create a minimal tree structure with just a root node
    root_node%layout_type = "none"
    call ui_present(root_node)
    running = .not. ui_should_close()
end do

call ui_shutdown()

print *, ""
print *, "Demo completed after", frame_count, "frames"
print *, "Final settings: Volume=", volume, "Brightness=", brightness
#ifdef ENABLE_GUI
    print *, "GUI backend demonstration successful!"
#else
    print *, "TUI backend demonstration successful!"
#endif

end program gui_demo