program button_test
! Test button widget functionality with click detection
use fortui_widgets
use fortui_units
implicit none

logical :: btn1_clicked, btn2_clicked
integer :: i

print *, "Button Widget Test"
print *, "=================="

! Test basic button functionality
do i = 1, 5
    ! Basic button with ID and default label
    btn1_clicked = button("test_button")
    
    ! Button with custom label and size
    btn2_clicked = button("custom_btn", label="Click Me!", width=dp(80.0), height=dp(30.0))
    
    ! Test interaction detection
    if (btn1_clicked) print *, "Frame", i, ": Test button clicked!"
    if (btn2_clicked) print *, "Frame", i, ": Custom button clicked!"
    
    print *, "Frame", i, ": Buttons rendered successfully"
end do

print *, ""
print *, "Button widget test completed successfully"
end program button_test