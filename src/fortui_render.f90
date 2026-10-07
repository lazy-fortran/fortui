module fortui_render
!! Semantic-frame backend dispatch. Widgets never depend on this module.
use fortui_frame, only: ui_frame_t
implicit none
private

integer, parameter, public :: BACKEND_NONE = 0
integer, parameter, public :: BACKEND_HEADLESS = 1
integer, parameter, public :: BACKEND_TUI = 2
integer, parameter, public :: BACKEND_GUI = 3

public :: render_present

contains

subroutine render_present(frame, backend_id)
    type(ui_frame_t), intent(in) :: frame
    integer, intent(in) :: backend_id

    select case (backend_id)
    case (BACKEND_HEADLESS)
        return
    case (BACKEND_TUI)
        call render_tui(frame)
    case (BACKEND_GUI)
        call render_gui(frame)
    end select
end subroutine render_present

subroutine render_tui(frame)
    use fortui_tui, only: tui_render_frame
    type(ui_frame_t), intent(in) :: frame
    call tui_render_frame(frame)
end subroutine render_tui

subroutine render_gui(frame)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_render_frame
#endif
    type(ui_frame_t), intent(in) :: frame
#ifdef ENABLE_GUI
    call gui_render_frame(frame)
#endif
end subroutine render_gui

end module fortui_render
