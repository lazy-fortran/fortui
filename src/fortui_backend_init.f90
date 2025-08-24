module fortui_backend_init
! Context-aware backend registration module
! Separates registration from core to avoid circular dependencies
use fortui_backend
use fortui_tui_simple, only: register_simple_tui_backend
use fortui_context, only: fortui_context_t, get_default_context
! Temporarily disabled polymorphic renderers for Issue #121
! use fortui_tui_renderer, only: tui_renderer_t
! use fortui_gui_renderer, only: gui_renderer_t
#ifdef ENABLE_GUI
use fortui_gui, only: register_gui_backend
#endif
implicit none
private

public :: ensure_backends_registered, ensure_backends_registered_with_context
public :: initialize_renderer

! Backend registration state type for context storage
type :: backend_registration_state
    logical :: backends_registered = .false.
end type backend_registration_state

contains

! Context-aware backend registration (new API)
subroutine ensure_backends_registered_with_context(ctx)
    type(fortui_context_t), intent(inout) :: ctx
    
    ! For now, always register backends (simplified for polymorphism removal)
    ! TODO: Implement proper backend registration state with union type
    
    ! Always register TUI backend
    call register_simple_tui_backend()
    
#ifdef ENABLE_GUI
    ! Register GUI backend if compiled in
    call register_gui_backend()
#endif
end subroutine ensure_backends_registered_with_context

! Default context version for backward compatibility
subroutine ensure_backends_registered()
    type(fortui_context_t), pointer :: ctx
    
    ! Get default context
    ctx => get_default_context()
    if (associated(ctx)) then
        call ensure_backends_registered_with_context(ctx)
    else
        ! Fallback to direct registration without context
        ! (for cases where context is not yet available)
        call register_simple_tui_backend()
        
#ifdef ENABLE_GUI
        call register_gui_backend()
#endif
    end if
end subroutine ensure_backends_registered

! Initialize appropriate renderer based on backend
subroutine initialize_renderer(ctx, backend_name)
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: backend_name
    
    ! Temporarily stub out renderer initialization for Issue #121
    ! This will be properly implemented after renderer polymorphism is removed
    ! For now, just set renderer to null to avoid crashes
    ctx%renderer => null()
end subroutine initialize_renderer

end module fortui_backend_init