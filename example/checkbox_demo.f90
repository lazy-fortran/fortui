program checkbox_demo
use fortui_core
use fortui_widgets
implicit none

logical :: sound_enabled = .true.
logical :: notifications = .false.
logical :: auto_save = .true.
logical :: dark_mode = .false.
logical :: running = .true.
integer :: frame = 0
logical :: sound_toggled, notifications_toggled, save_toggled, theme_toggled

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "=== Settings Panel (Frame", frame, ") ==="
    
    ! Audio settings - capture toggle status
    sound_toggled = checkbox("sound", sound_enabled, "Enable Sound")
    if (sound_toggled) sound_enabled = .not. sound_enabled
    
    notifications_toggled = checkbox("notifications", notifications, "Notifications")
    if (notifications_toggled) notifications = .not. notifications
    
    ! Application settings  
    save_toggled = checkbox("auto_save", auto_save, "Auto-save Documents")
    if (save_toggled) auto_save = .not. auto_save
    
    theme_toggled = checkbox("dark_mode", dark_mode, "Dark Theme", width=150.0)
    if (theme_toggled) dark_mode = .not. dark_mode
    
    ! Display current settings
    print *, "Sound:", sound_enabled, "| Notifications:", notifications
    print *, "Auto-save:", auto_save, "| Dark mode:", dark_mode
    
    ! Exit condition
    if (.not. sound_enabled .and. .not. notifications) then
        print *, "All audio features disabled - exiting"
        running = .false.
    end if
end do
end program