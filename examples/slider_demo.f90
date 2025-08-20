program slider_demo
use fortui_widgets
use fortui_units
implicit none

real :: volume = 50.0
real :: brightness = 75.0
real :: temperature = 22.5
logical :: volume_changed, brightness_changed, temp_changed
logical :: running = .true.
integer :: frame = 0

print *, "Slider Demo - Testing interactive numeric controls"
print *, "Initial values: volume=", volume, "brightness=", brightness, "temperature=", temperature

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "Frame", frame
    
    ! Volume slider (0-100, step 5)
    volume_changed = slider("volume", 0.0, 100.0, 5.0, volume, width=dp(120.0))
    if (volume_changed) print *, "Volume changed to:", volume
    print *, "Volume:", volume
    
    ! Brightness slider (0-100, step 1) 
    brightness_changed = slider("brightness", 0.0, 100.0, 1.0, brightness)
    if (brightness_changed) print *, "Brightness changed to:", brightness
    print *, "Brightness:", brightness
    
    ! Temperature slider (15-30°C, continuous)
    temp_changed = slider("temperature", 15.0, 30.0, 0.0, temperature, width=cw(15.0))
    if (temp_changed) print *, "Temperature changed to:", temperature, "°C"
    print *, "Temperature:", temperature, "°C"
    
    ! Exit condition for demo
    if (frame >= 5) running = .false.
end do

print *, "Final values: volume=", volume, "brightness=", brightness, "temperature=", temperature
end program