module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
implicit none
private

! Public types
public :: node, view

! Public procedures
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy

! Internal state management
type :: ui_state_t
    logical :: initialized = .false.
    character(len=32) :: active_backend = ""
    integer :: window_width = 0
    integer :: window_height = 0
    character(len=256) :: window_title = ""
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    character(len=32) :: idle_mode = "adaptive"
    integer :: idle_fps = 12
    logical :: should_quit = .false.
end type ui_state_t

type(ui_state_t), save :: ui_state

! Core UI tree building block - extensible for widgets
type :: node
    ! Minimal structure - will be extended by widget types
    ! Backend-agnostic design (identical behavior regardless of compilation flags)
end type node

! Pan/zoom state for plot areas with default values from DESIGN.md
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis
    real :: scale_y = 1.0  ! Zoom factor Y-axis
    real :: off_x = 0.0    ! Pan offset X-axis
    real :: off_y = 0.0    ! Pan offset Y-axis
end type view

contains

! Lifecycle & pacing procedures
subroutine ui_init(backend, width, height, title, target_fps, vsync)
    character(*), intent(in) :: backend        ! "tui" | "gui" | "auto"
    integer,      intent(in) :: width, height  ! grid units (gu)
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
    logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
    
    character(len=32) :: resolved_backend
    character(len=256) :: display_var, ssh_client, ci_var
    integer :: ios
    
    ! Reset state if reinitializing
    if (ui_state%initialized) then
        call ui_shutdown()
    end if
    
    ! Validate and resolve backend
    resolved_backend = resolve_backend(backend)
    
    ! Validate parameters
    if (width <= 0 .or. height <= 0) then
        print *, "ui_init: Warning - Invalid dimensions (", width, "x", height, "), using defaults"
        ui_state%window_width = max(1, width)
        ui_state%window_height = max(1, height)
    else
        ui_state%window_width = width
        ui_state%window_height = height
    end if
    
    ! Store configuration
    ui_state%active_backend = resolved_backend
    ui_state%window_title = title
    ui_state%target_fps = 60
    if (present(target_fps)) ui_state%target_fps = max(1, target_fps)
    ui_state%vsync_enabled = .true.
    if (present(vsync)) ui_state%vsync_enabled = vsync
    
    ! Initialize backend-specific resources
    select case (trim(resolved_backend))
    case ("tui")
        call init_tui_backend()
    case ("gui")
        call init_gui_backend()
    case default
        print *, "ui_init: Error - Unsupported backend: ", trim(resolved_backend)
        print *, "ui_init: Falling back to TUI backend"
        ui_state%active_backend = "tui"
        call init_tui_backend()
    end select
    
    ui_state%initialized = .true.
    ui_state%should_quit = .false.
    
    ! Debug output for tests
    print *, "ui_init: backend=", trim(ui_state%active_backend), " size=", &
             ui_state%window_width, "x", ui_state%window_height
end subroutine ui_init

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
    character(*), intent(in) :: mode                   ! "steady" | "adaptive"
    integer,      intent(in), optional :: idle_fps     ! e.g., 12
    
    ! Validate mode parameter
    select case (trim(mode))
    case ("steady", "adaptive")
        ui_state%idle_mode = trim(mode)
    case default
        print *, "ui_set_idle_policy: Warning - Invalid mode '", trim(mode), "', using 'adaptive'"
        ui_state%idle_mode = "adaptive"
    end select
    
    ! Set idle FPS if provided (only meaningful for adaptive mode)
    if (present(idle_fps)) then
        ui_state%idle_fps = max(1, idle_fps)
    end if
    
    ! Apply policy for GUI backend only
#ifdef ENABLE_GUI
    if (trim(ui_state%active_backend) == "gui") then
        print *, "ui_set_idle_policy: mode=", trim(ui_state%idle_mode)
        if (present(idle_fps)) print *, "  idle_fps=", ui_state%idle_fps
    end if
#endif
end subroutine ui_set_idle_policy

subroutine ui_frame_begin(timeout_ms)
    integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
    
    if (.not. ui_state%initialized) then
        print *, "ui_frame_begin: Error - UI not initialized. Call ui_init first."
        return
    end if
    
    ! Backend-specific frame preparation
    select case (trim(ui_state%active_backend))
    case ("tui")
        ! TUI: Event-driven with timeout
        call begin_tui_frame(timeout_ms)
    case ("gui")
        ! GUI: Frame timing controlled by target_fps, timeout ignored
        call begin_gui_frame()
    end select
end subroutine ui_frame_begin

subroutine ui_present(tree)
    class(node), intent(in) :: tree
    
    if (.not. ui_state%initialized) then
        print *, "ui_present: Error - UI not initialized. Call ui_init first."
        return
    end if
    
    ! Backend-specific presentation
    select case (trim(ui_state%active_backend))
    case ("tui")
        call present_tui(tree)
    case ("gui")
        call present_gui(tree)
    end select
end subroutine ui_present

logical function ui_should_close()
    ! Check if application should terminate
    ! Returns true for quit events (ESC key, window close, etc.)
    
    if (.not. ui_state%initialized) then
        ui_should_close = .true.  ! Force quit if not initialized
        return
    end if
    
    ! Check backend-specific quit conditions
    select case (trim(ui_state%active_backend))
    case ("tui")
        ui_should_close = check_tui_quit() .or. ui_state%should_quit
    case ("gui")
        ui_should_close = check_gui_quit() .or. ui_state%should_quit
    case default
        ui_should_close = .true.  ! Unknown backend, force quit
    end select
end function ui_should_close

subroutine ui_shutdown()
    ! Clean shutdown of UI backend
    
    if (.not. ui_state%initialized) then
        ! Safe to call multiple times
        return
    end if
    
    ! Backend-specific cleanup
    select case (trim(ui_state%active_backend))
    case ("tui")
        call shutdown_tui_backend()
    case ("gui")
        call shutdown_gui_backend()
    end select
    
    ! Reset all state
    ui_state%initialized = .false.
    ui_state%active_backend = ""
    ui_state%window_width = 0
    ui_state%window_height = 0
    ui_state%window_title = ""
    ui_state%target_fps = 60
    ui_state%vsync_enabled = .true.
    ui_state%idle_mode = "adaptive"
    ui_state%idle_fps = 12
    ui_state%should_quit = .false.
    
    print *, "ui_shutdown: cleaning up backend resources"
end subroutine ui_shutdown

! Internal backend resolution and management functions

function resolve_backend(requested) result(backend)
    character(*), intent(in) :: requested
    character(len=32) :: backend
    character(len=256) :: env_var
    integer :: ios
    logical :: gui_available
    
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
        if (is_gui_available() .and. .not. is_headless_environment()) then
            backend = "gui"
        else
            backend = "tui"
        end if
    case default
        ! Invalid backend - fall back to TUI
        print *, "resolve_backend: Warning - Unknown backend '", trim(requested), "', using TUI"
        backend = "tui"
    end select
    
    ! Validate that selected backend is actually available
    if (trim(backend) == "gui" .and. .not. is_gui_available()) then
        print *, "resolve_backend: GUI backend not available, falling back to TUI"
        backend = "tui"
    end if
end function resolve_backend

logical function is_gui_available()
    ! Check if GUI backend can be initialized
#ifdef ENABLE_GUI
    character(len=256) :: disable_gui
    integer :: ios
    
    ! Check DISABLE_GUI environment variable
    call get_environment_variable("DISABLE_GUI", disable_gui, status=ios)
    if (ios == 0 .and. trim(disable_gui) == "1") then
        is_gui_available = .false.
        return
    end if
    
    ! TODO: Add runtime raylib initialization check when backend modules available
    is_gui_available = .true.
#else
    is_gui_available = .false.
#endif
end function is_gui_available

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

! Backend-specific initialization stubs (will be implemented when backend modules available)
subroutine init_tui_backend()
    ! Initialize TUI backend
    ! TODO: Initialize termbox2 when TUI module available
end subroutine init_tui_backend

subroutine init_gui_backend()
    ! Initialize GUI backend
#ifdef ENABLE_GUI
    ! TODO: Initialize raylib when GUI module available
#endif
end subroutine init_gui_backend

! Backend-specific frame management stubs
subroutine begin_tui_frame(timeout_ms)
    integer, intent(in) :: timeout_ms
    ! TODO: TUI event polling with timeout
end subroutine begin_tui_frame

subroutine begin_gui_frame()
    ! TODO: GUI frame timing
end subroutine begin_gui_frame

! Backend-specific presentation stubs
subroutine present_tui(tree)
    class(node), intent(in) :: tree
    ! TODO: TUI rendering with diff-based updates
end subroutine present_tui

subroutine present_gui(tree)
    class(node), intent(in) :: tree
    ! TODO: GUI rendering with raygui
end subroutine present_gui

! Backend-specific quit detection stubs
logical function check_tui_quit()
    ! TODO: Check for TUI quit events (ESC, Ctrl+C, etc.)
    check_tui_quit = .false.
end function check_tui_quit

logical function check_gui_quit()
    ! TODO: Check for GUI quit events (window close, etc.)
    check_gui_quit = .false.
end function check_gui_quit

! Backend-specific shutdown stubs
subroutine shutdown_tui_backend()
    ! TODO: TUI cleanup
end subroutine shutdown_tui_backend

subroutine shutdown_gui_backend()
    ! TODO: GUI cleanup
#ifdef ENABLE_GUI
#endif
end subroutine shutdown_gui_backend

end module fortui_core