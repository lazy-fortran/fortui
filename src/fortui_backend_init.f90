module fortui_backend_init
! Context-aware backend registration module
! Separates registration from core to avoid circular dependencies
use fortui_backend
use fortui_tui, only: register_tui_backend
use fortui_context, only: fortui_context_t, get_default_context
implicit none
private

public :: ensure_backends_registered, ensure_backends_registered_with_context
! Backend registration state type for context storage
type :: backend_registration_state
    logical :: backends_registered = .false.
end type backend_registration_state

contains

! Context-aware backend registration (new API)
subroutine ensure_backends_registered_with_context(ctx)
    type(fortui_context_t), intent(inout) :: ctx
    
    ! Use proper backend_state field instead of widget_states
    if (.not. allocated(ctx%backend_state)) then
        ! Initialize backend registration state in proper location
        allocate(ctx%backend_state, source=backend_registration_state())
    end if
    
    ! Check if already registered
    select type(state_obj => ctx%backend_state)
    type is (backend_registration_state)
        if (state_obj%backends_registered) return
        
        ! Always register TUI backend
        call register_tui_backend()
        
        state_obj%backends_registered = .true.
    end select
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
        call register_tui_backend()
        
    end if
end subroutine ensure_backends_registered

end module fortui_backend_init
