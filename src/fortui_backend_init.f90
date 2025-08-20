module fortui_backend_init
! Module for automatic backend registration
! Separates registration from core to avoid circular dependencies
use fortui_backend
use fortui_tui
#ifdef ENABLE_GUI
use fortui_gui
#endif
implicit none
private

public :: ensure_backends_registered

! Module-level flag to track registration
logical, save :: backends_registered = .false.

contains

subroutine ensure_backends_registered()
    ! Register all available backends (idempotent)
    if (backends_registered) return
    
    ! Always register TUI backend
    call register_tui_backend()
    
#ifdef ENABLE_GUI
    ! Register GUI backend if compiled in
    call register_gui_backend()
#endif
    
    backends_registered = .true.
end subroutine ensure_backends_registered

end module fortui_backend_init