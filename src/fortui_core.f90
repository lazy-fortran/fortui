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
    character(*), intent(in) :: backend        ! "tui" | "gui"
    integer,      intent(in) :: width, height  ! grid units (gu)
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
    logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
    
    ! Initialize UI backend
    ! Implementation will be completed when backend modules are available
    print *, "ui_init: backend=", backend, " size=", width, "x", height
end subroutine ui_init

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
    character(*), intent(in) :: mode                   ! "steady" | "adaptive"
    integer,      intent(in), optional :: idle_fps     ! e.g., 12
    
    ! Set idle policy for GUI backend
#ifdef ENABLE_GUI
    print *, "ui_set_idle_policy: mode=", mode
    if (present(idle_fps)) print *, "  idle_fps=", idle_fps
#endif
end subroutine ui_set_idle_policy

subroutine ui_frame_begin(timeout_ms)
    integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
    
    ! Begin frame rendering
    ! TUI: waits for events with timeout
    ! GUI: begins frame timing
    continue  ! Implementation placeholder
end subroutine ui_frame_begin

subroutine ui_present(tree)
    class(node), intent(in) :: tree
    
    ! Present UI tree to backend for rendering
    ! Implementation will traverse tree and render according to backend
    continue  ! Implementation placeholder
end subroutine ui_present

logical function ui_should_close()
    ! Check if application should terminate
    ! Returns true for quit events (ESC key, window close, etc.)
    ui_should_close = .false.  ! Implementation placeholder
end function ui_should_close

subroutine ui_shutdown()
    ! Clean shutdown of UI backend
    print *, "ui_shutdown: cleaning up backend resources"
end subroutine ui_shutdown

end module fortui_core