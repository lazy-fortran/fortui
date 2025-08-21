module fortui_backend_init
! Context-aware backend registration module
! Separates registration from core to avoid circular dependencies
use fortui_backend
use fortui_tui, only: register_tui_backend
use fortui_context, only: fortui_context_t, get_default_context
use fortui_tui_renderer, only: tui_renderer_t
use fortui_gui_renderer, only: gui_renderer_t
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
    
    integer :: state_index
    type(backend_registration_state) :: new_state
    
    ! Get or create backend registration state
    state_index = ctx%widget_states%get("_backend_registration", "internal")
    if (state_index == 0) then
        ! Create new registration state
        new_state = backend_registration_state()
        call ctx%widget_states%set("_backend_registration", "internal", new_state)
        state_index = ctx%widget_states%get("_backend_registration", "internal")
    end if
    
    if (state_index == 0) return
    
    ! Check if already registered
    select type(state_obj => ctx%widget_states%entries(state_index)%state)
    type is (backend_registration_state)
        if (state_obj%backends_registered) return
        
        ! Always register TUI backend
        call register_tui_backend()
        
#ifdef ENABLE_GUI
        ! Register GUI backend if compiled in
        call register_gui_backend()
#endif
        
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
        
#ifdef ENABLE_GUI
        call register_gui_backend()
#endif
    end if
end subroutine ensure_backends_registered

! Initialize appropriate renderer based on backend
subroutine initialize_renderer(ctx, backend_name)
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: backend_name
    
    select case(trim(backend_name))
    case("tui")
        ! Create and set TUI renderer
        block
            type(tui_renderer_t), pointer :: tui_renderer
            allocate(tui_renderer)
            call tui_renderer%initialize(ctx%window_width, ctx%window_height)
            call ctx%set_renderer(tui_renderer)
        end block
        
    case("gui")
        ! Create and set GUI renderer
        block
            type(gui_renderer_t), pointer :: gui_renderer
            allocate(gui_renderer)
            call gui_renderer%initialize(ctx%window_width, ctx%window_height, ctx%dpi_scale)
            call ctx%set_renderer(gui_renderer)
        end block
        
    case default
        ! Default to TUI renderer
        block
            type(tui_renderer_t), pointer :: default_renderer
            allocate(default_renderer)
            call default_renderer%initialize(80, 24)
            call ctx%set_renderer(default_renderer)
        end block
    end select
end subroutine initialize_renderer

end module fortui_backend_init