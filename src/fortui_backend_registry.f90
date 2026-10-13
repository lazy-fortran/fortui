module fortui_backend_registry
!! Explicit backend selection. The only module that names concrete backends;
!! the runtime core and widgets depend on the abstract interface alone.
!! A requested backend that is unavailable is an error, never a fallback.
use fortui_backend, only: ui_backend_t
use fortui_backend_headless, only: headless_backend_t
use fortui_tui, only: tui_backend_t, tui_is_available
use fortui_gui_raylib, only: raylib_backend_t, raylib_is_available
implicit none
private

public :: create_backend

contains

subroutine create_backend(requested, backend)
    !! Allocate the backend for `requested` (FORTUI_BACKEND overrides it).
    !! "auto" picks gui, then tui, then headless only with FORTUI_HEADLESS=1.
    !! `backend` stays unallocated when the choice is unknown or unavailable.
    character(*), intent(in) :: requested
    class(ui_backend_t), allocatable, intent(out) :: backend
    character(len=64) :: choice, env_value
    integer :: status

    choice = lower(trim(requested))
    call get_environment_variable("FORTUI_BACKEND", env_value, status=status)
    if (status == 0 .and. len_trim(env_value) > 0) choice = lower(trim(env_value))

    select case (trim(choice))
    case ("headless")
        allocate(headless_backend_t :: backend)
    case ("tui", "terminal", "console")
        if (tui_is_available()) allocate(tui_backend_t :: backend)
    case ("gui", "graphics", "window", "raylib")
        if (raylib_is_available()) allocate(raylib_backend_t :: backend)
    case ("auto", "")
        if (raylib_is_available()) then
            allocate(raylib_backend_t :: backend)
        else if (tui_is_available()) then
            allocate(tui_backend_t :: backend)
        else
            call get_environment_variable("FORTUI_HEADLESS", env_value, status=status)
            if (status == 0 .and. trim(env_value) == "1") &
                allocate(headless_backend_t :: backend)
        end if
    end select
end subroutine create_backend

pure function lower(value) result(out)
    character(*), intent(in) :: value
    character(len=len(value)) :: out
    integer :: i, code

    out = value
    do i = 1, len(value)
        code = iachar(out(i:i))
        if (code >= iachar('A') .and. code <= iachar('Z')) out(i:i) = achar(code + 32)
    end do
end function lower

end module fortui_backend_registry
