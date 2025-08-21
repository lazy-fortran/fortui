! fortui_error.f90 - Consistent error handling for fortui
module fortui_error
use iso_fortran_env, only: error_unit
implicit none
private

! Public error reporting procedures
public :: report_error, report_warning, report_info

! Error severity levels
integer, parameter, public :: ERROR_CRITICAL = 3
integer, parameter, public :: ERROR_WARNING = 2
integer, parameter, public :: ERROR_INFO = 1

contains

!> Report an error message to error_unit
subroutine report_error(module_name, procedure_name, message, abort)
    character(*), intent(in) :: module_name
    character(*), intent(in) :: procedure_name
    character(*), intent(in) :: message
    logical, intent(in), optional :: abort
    
    logical :: should_abort
    
    should_abort = .false.
    if (present(abort)) should_abort = abort
    
    write(error_unit, '(A,A,A,A,A)') trim(module_name), "::", &
        trim(procedure_name), ": Error - ", trim(message)
    
    if (should_abort) then
        error stop "Critical error - aborting"
    end if
end subroutine report_error

!> Report a warning message to error_unit
subroutine report_warning(module_name, procedure_name, message)
    character(*), intent(in) :: module_name
    character(*), intent(in) :: procedure_name
    character(*), intent(in) :: message
    
    write(error_unit, '(A,A,A,A,A)') trim(module_name), "::", &
        trim(procedure_name), ": Warning - ", trim(message)
end subroutine report_warning

!> Report an informational message to error_unit (for debugging)
subroutine report_info(module_name, procedure_name, message)
    character(*), intent(in) :: module_name
    character(*), intent(in) :: procedure_name
    character(*), intent(in) :: message
    
    write(error_unit, '(A,A,A,A,A)') trim(module_name), "::", &
        trim(procedure_name), ": Info - ", trim(message)
end subroutine report_info

end module fortui_error