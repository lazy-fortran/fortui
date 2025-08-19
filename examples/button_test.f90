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
    
    if (btn1_clicked) then
        print *, "Frame", i, ": test_button was clicked!"
    end if
    
    if (btn2_clicked) then
        print *, "Frame", i, ": custom_btn was clicked!"
    end if
end do

print *, ""
print *, "Button widget test completed successfully"
end program button_test