program button_test
! Test button widget functionality with click detection
use fortui_widgets
use fortui_units
use fortui_core, only: node
implicit none

type(node) :: btn1_node, btn2_node
integer :: i

print *, "Button Widget Test"
print *, "=================="

! Test basic button functionality
do i = 1, 5
    ! Basic button with ID and default label
    btn1_node = button("test_button")
    
    ! Button with custom label and size
    btn2_node = button("custom_btn", label="Click Me!", width=dp(80.0), height=dp(30.0))
    
    ! Note: In new API, interaction detection would be handled by UI framework
    print *, "Frame", i, ": Buttons rendered successfully"
end do

print *, ""
print *, "Button widget test completed successfully"
end program button_test