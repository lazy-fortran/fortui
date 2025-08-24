module test_class_star
implicit none
private

public :: test_func, my_type

type :: my_type
    integer :: val = 0
end type my_type

contains

function test_func(id, optional_param) result(res)
    character(*), intent(in) :: id
    type(my_type), intent(in), optional :: optional_param
    type(my_type) :: res
    
    if (present(optional_param)) then
        res%val = optional_param%val
    else
        res%val = 42
    end if
end function test_func

end module test_class_star

program test
use test_class_star
implicit none

type(my_type) :: result

result = test_func("test")
print *, "Result:", result%val

end program test