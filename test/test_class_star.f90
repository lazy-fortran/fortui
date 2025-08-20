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
    class(*), intent(in), optional :: optional_param
    type(my_type) :: res
    
    res%val = 42
end function test_func

end module test_class_star

program test
use test_class_star
implicit none

type(my_type) :: result

result = test_func("test")
print *, "Result:", result%val

end program test