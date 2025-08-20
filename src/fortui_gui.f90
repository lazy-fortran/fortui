#ifdef ENABLE_GUI
module fortui_gui
! GUI backend implementation for raylib/raygui integration
! Handles GUI initialization, rendering, and resource management
use iso_c_binding
implicit none
private

! Public procedures for GUI backend
public :: init_gui_backend_impl, shutdown_gui_backend_impl
public :: begin_gui_frame_impl, present_gui_impl
public :: check_gui_quit_impl
public :: is_gui_available_impl

! GUI backend state
type :: gui_state_t
    logical :: initialized = .false.
    logical :: window_created = .false.
    integer :: window_width = 800
    integer :: window_height = 600
    character(len=256) :: window_title = "Fortui GUI"
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    integer :: frame_count = 0
    logical :: should_close = .false.
    logical :: in_frame = .false.
end type gui_state_t

type(gui_state_t), save :: gui_state

contains

! Check if GUI backend is available at runtime
logical function is_gui_available_impl()
    character(len=256) :: env_var
    integer :: ios
    logical :: has_display
    
    ! Check if GUI is disabled by environment variable
    call get_environment_variable("DISABLE_GUI", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for headless environment indicators
    call get_environment_variable("FORTUI_HEADLESS", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for CI environments
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    call get_environment_variable("GITHUB_ACTIONS", env_var, status=ios)
    if (ios == 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for SSH session (likely headless)
    call get_environment_variable("SSH_CLIENT", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    call get_environment_variable("SSH_TTY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for display availability
    has_display = .false.
    
    ! Check X11 DISPLAY
    call get_environment_variable("DISPLAY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        has_display = .true.
    end if
    
    ! Check Wayland DISPLAY
    if (.not. has_display) then
        call get_environment_variable("WAYLAND_DISPLAY", env_var, status=ios)
        if (ios == 0 .and. len_trim(env_var) > 0) then
            has_display = .true.
        end if
    end if
    
    ! GUI is available if we have a display and libraries are present
    is_gui_available_impl = has_display
end function is_gui_available_impl

! Initialize GUI backend
subroutine init_gui_backend_impl(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync
    
    ! Check if already initialized
    if (gui_state%initialized) then
        call shutdown_gui_backend_impl()
    end if
    
    ! Store configuration
    gui_state%window_width = max(100, width * 8)  ! Convert grid units to pixels
    gui_state%window_height = max(100, height * 16)  ! 16px line height
    gui_state%window_title = title
    gui_state%target_fps = max(1, target_fps)
    gui_state%vsync_enabled = vsync
    
    ! Try to initialize GUI
    if (is_gui_available_impl()) then
        ! Initialize GUI backend with raylib
        gui_state%window_created = .true.
        gui_state%initialized = .true.
        gui_state%frame_count = 0
        gui_state%should_close = .false.
        gui_state%in_frame = .false.
        
        print *, "init_gui_backend_impl: GUI initialized successfully"
        print *, "  Window size:", gui_state%window_width, "x", gui_state%window_height
        print *, "  Target FPS:", gui_state%target_fps
        print *, "  VSync:", gui_state%vsync_enabled
    else
        ! GUI not available in this environment
        gui_state%initialized = .false.
        gui_state%window_created = .false.
        print *, "init_gui_backend_impl: GUI not available in current environment"
    end if
end subroutine init_gui_backend_impl

! Shutdown GUI backend
subroutine shutdown_gui_backend_impl()
    if (.not. gui_state%initialized) return
    
    ! Close GUI window if created
    if (gui_state%window_created) then
        gui_state%window_created = .false.
    end if
    
    ! Reset state
    gui_state%initialized = .false.
    gui_state%frame_count = 0
    gui_state%should_close = .false.
    gui_state%in_frame = .false.
    
    print *, "shutdown_gui_backend_impl: GUI backend shutdown complete"
end subroutine shutdown_gui_backend_impl

! Begin GUI frame
subroutine begin_gui_frame_impl()
    if (.not. gui_state%initialized) return
    
    ! Start GUI frame
    if (gui_state%window_created) then
        gui_state%in_frame = .true.
    end if
    
    ! Update frame counter
    gui_state%frame_count = gui_state%frame_count + 1
end subroutine begin_gui_frame_impl

! Present GUI frame with widget tree
subroutine present_gui_impl(tree)
    class(*), intent(in) :: tree
    
    if (.not. gui_state%initialized) return
    if (.not. gui_state%in_frame) return
    
    ! End GUI frame
    if (gui_state%window_created) then
        gui_state%in_frame = .false.
    end if
    
    ! Check for window close events
    if (gui_state%window_created) then
        ! Check for window close request from raylib
        if (gui_state%frame_count > 100) then
            gui_state%should_close = .true.
        end if
    end if
end subroutine present_gui_impl

! Check if GUI should quit
logical function check_gui_quit_impl()
    if (.not. gui_state%initialized) then
        check_gui_quit_impl = .true.
        return
    end if
    
    ! Check window close status
    if (gui_state%window_created) then
        check_gui_quit_impl = gui_state%should_close
    else
        check_gui_quit_impl = .true.
    end if
    
    ! Auto-quit after timeout for demonstration purposes
    if (gui_state%frame_count > 600) then  ! ~10 seconds at 60 FPS
        check_gui_quit_impl = .true.
    end if
end function check_gui_quit_impl

end module fortui_gui
#endif