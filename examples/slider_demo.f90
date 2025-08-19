program slider_demo
use fortui_widgets
use fortui_units
use fortui_core, only: node
implicit none

real :: volume = 50.0
real :: brightness = 75.0
real :: temperature = 22.5
type(node) :: volume_node, brightness_node, temp_node
logical :: running = .true.
integer :: frame = 0

print *, "Slider Demo - Testing interactive numeric controls"
print *, "Initial values: volume=", volume, "brightness=", brightness, "temperature=", temperature

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "Frame", frame
    
    ! Volume slider (0-100, step 5)
    volume_node = slider("volume", 0.0, 100.0, 5.0, volume, width=dp(120.0))
    print *, "Volume:", volume
    
    ! Brightness slider (0-100, step 1) 
    brightness_node = slider("brightness", 0.0, 100.0, 1.0, brightness)
    print *, "Brightness:", brightness
    
    ! Temperature slider (15-30°C, continuous)
    temp_node = slider("temperature", 15.0, 30.0, 0.0, temperature, width=cw(15.0))
    print *, "Temperature:", temperature, "°C"
    
    ! Exit condition for demo
    if (frame >= 5) running = .false.
end do

print *, "Final values: volume=", volume, "brightness=", brightness, "temperature=", temperature
end program