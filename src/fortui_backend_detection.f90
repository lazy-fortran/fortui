module fortui_backend_detection
! Backend availability detection and resolution logic
! Provides environment detection and backend selection functionality
use fortui_backend, only: backend_t, get_backend, select_best_backend
use fortui_error, only: report_error, report_warning, report_info
implicit none
private

! Public interface
public :: resolve_backend, is_gui_available, is_tui_available, is_headless_environment
public :: set_environment_variable_simulation, clear_environment_variable_simulation

contains

function resolve_backend(requested) result(backend)
    character(*), intent(in) :: requested
    character(len=32) :: backend
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for environment variable override
    call get_environment_variable("FORTUI_BACKEND", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        backend = trim(env_var)
        return
    end if
    
    ! Handle case sensitivity
    select case (trim(adjustl(requested)))
    case ("TUI", "tui", "terminal", "console")
        backend = "tui"
    case ("GUI", "gui", "window", "graphics")
        backend = "gui"
    case ("auto", "AUTO", "")
        ! Auto-detect best available backend
        backend = select_best_backend()
        if (len_trim(backend) == 0) then
            backend = "tui"  ! Fallback if no backend available
        end if
    case default
        ! Invalid backend - fall back to TUI
        call report_warning("fortui_backend_detection", "resolve_backend", &
             "Unknown backend '" // trim(requested) // "', using TUI")
        backend = "tui"
    end select
    
    ! Validate that selected backend is actually available
    if (trim(backend) == "gui" .and. .not. is_gui_available()) then
        call report_warning("fortui_backend_detection", "resolve_backend", &
            "GUI backend not available, falling back to TUI")
        backend = "tui"
    end if
    
    ! Also validate TUI availability (headless environments)
    if (trim(backend) == "tui" .and. .not. is_tui_available()) then
        call report_error("fortui_backend_detection", "resolve_backend", &
            "TUI backend not available (headless environment)")
        backend = ""  ! No backend available
    end if
end function resolve_backend

logical function is_gui_available()
    ! Check if GUI backend can be initialized
    type(backend_t), pointer :: gui_backend
    
    gui_backend => get_backend("gui")
    if (associated(gui_backend)) then
        if (associated(gui_backend%is_available)) then
            is_gui_available = gui_backend%is_available(gui_backend%backend_data)
        else
            is_gui_available = .false.
        end if
    else
        is_gui_available = .false.
    end if
end function is_gui_available

logical function is_tui_available()
    ! Check if TUI backend can be initialized
    type(backend_t), pointer :: tui_backend
    
    tui_backend => get_backend("tui")
    if (associated(tui_backend)) then
        if (associated(tui_backend%is_available)) then
            is_tui_available = tui_backend%is_available(tui_backend%backend_data)
        else
            is_tui_available = .false.
        end if
    else
        is_tui_available = .false.
    end if
end function is_tui_available

logical function is_headless_environment()
    ! Detect headless environment (no display available)
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for explicit headless flag
    call get_environment_variable("FORTUI_HEADLESS", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for CI environment
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("GITHUB_ACTIONS", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for SSH session
    call get_environment_variable("SSH_CLIENT", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("SSH_TTY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for display availability
    call get_environment_variable("DISPLAY", env_var, status=ios)
    if (ios /= 0 .or. len_trim(env_var) == 0) then
        ! No X11 DISPLAY, check for Wayland
        call get_environment_variable("WAYLAND_DISPLAY", env_var, status=ios)
        if (ios /= 0 .or. len_trim(env_var) == 0) then
            is_headless_environment = .true.
            return
        end if
    end if
    
    is_headless_environment = .false.
end function is_headless_environment

subroutine set_environment_variable_simulation(name, value)
    character(*), intent(in) :: name, value
    ! This is a stub for testing - real implementation would set env vars
    call report_info("fortui_backend_detection", "set_environment_variable_simulation", &
         "Setting " // trim(name) // "=" // trim(value))
end subroutine set_environment_variable_simulation

subroutine clear_environment_variable_simulation(name)
    character(*), intent(in) :: name
    ! This is a stub for testing - real implementation would clear env vars
    call report_info("fortui_backend_detection", "clear_environment_variable_simulation", &
         "Clearing " // trim(name))
end subroutine clear_environment_variable_simulation

end module fortui_backend_detection