module fortui_render
! Backend-agnostic render constants and dispatch flag.
! The render_backend integer selects the active backend.
! Dispatch wrappers call into fortui_tui or fortui_gui based on flag.
implicit none
private

! Backend dispatch flag
integer, parameter, public :: RENDER_NONE = 0
integer, parameter, public :: RENDER_TUI = 1
integer, parameter, public :: RENDER_GUI = 2
integer, save, public :: render_backend = RENDER_NONE

! Backend-agnostic color constants (same values as termbox2)
integer, parameter, public :: RC_DEFAULT = 0
integer, parameter, public :: RC_BLACK = 1
integer, parameter, public :: RC_RED = 2
integer, parameter, public :: RC_GREEN = 3
integer, parameter, public :: RC_YELLOW = 4
integer, parameter, public :: RC_BLUE = 5
integer, parameter, public :: RC_MAGENTA = 6
integer, parameter, public :: RC_CYAN = 7
integer, parameter, public :: RC_WHITE = 8
integer, parameter, public :: RC_BOLD = 256
integer, parameter, public :: RC_UNDERLINE = 512
integer, parameter, public :: RC_REVERSE = 1024

public :: render_set_cell, render_is_active, render_is_gui
public :: render_get_width, render_get_height
public :: render_fill_rect, render_draw_text, render_draw_border

contains

subroutine render_set_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg

    select case (render_backend)
    case (RENDER_TUI)
        call tui_set_cell_dispatch(x, y, ch, fg, bg)
    case (RENDER_GUI)
        call gui_set_cell_dispatch(x, y, ch, fg, bg)
    end select
end subroutine render_set_cell

logical function render_is_active()
    render_is_active = (render_backend /= RENDER_NONE)
end function render_is_active

logical function render_is_gui()
    render_is_gui = (render_backend == RENDER_GUI)
end function render_is_gui

integer function render_get_width()
    select case (render_backend)
    case (RENDER_TUI)
        call tui_get_width_dispatch(render_get_width)
    case (RENDER_GUI)
        call gui_get_width_dispatch(render_get_width)
    case default
        render_get_width = 80
    end select
end function render_get_width

integer function render_get_height()
    select case (render_backend)
    case (RENDER_TUI)
        call tui_get_height_dispatch(render_get_height)
    case (RENDER_GUI)
        call gui_get_height_dispatch(render_get_height)
    case default
        render_get_height = 24
    end select
end function render_get_height

subroutine render_fill_rect(x, y, w, h, color)
    integer, intent(in) :: x, y, w, h, color

    if (render_backend == RENDER_GUI) then
        call gui_fill_rect_dispatch(x, y, w, h, color)
    end if
end subroutine render_fill_rect

subroutine render_draw_text(x, y, str, fg, bg)
    integer, intent(in) :: x, y, fg, bg
    character(*), intent(in) :: str

    if (render_backend == RENDER_GUI) then
        call gui_draw_text_dispatch(x, y, str, fg, bg)
    end if
end subroutine render_draw_text

subroutine render_draw_border(x, y, w, h, fg, bg)
    integer, intent(in) :: x, y, w, h, fg, bg

    if (render_backend == RENDER_GUI) then
        call gui_draw_border_dispatch(x, y, w, h, fg, bg)
    end if
end subroutine render_draw_border

! Dispatch trampolines that call into backend modules.
! Using subroutine wrappers to avoid circular module dependencies.
! The actual implementations are in fortui_tui and fortui_gui.

subroutine tui_set_cell_dispatch(x, y, ch, fg, bg)
    use fortui_tui, only: tui_set_cell
    integer, intent(in) :: x, y, ch, fg, bg

    call tui_set_cell(x, y, ch, fg, bg)
end subroutine tui_set_cell_dispatch

subroutine tui_get_width_dispatch(w)
    use fortui_tui, only: tui_get_width
    integer, intent(out) :: w

    w = tui_get_width()
end subroutine tui_get_width_dispatch

subroutine tui_get_height_dispatch(h)
    use fortui_tui, only: tui_get_height
    integer, intent(out) :: h

    h = tui_get_height()
end subroutine tui_get_height_dispatch

subroutine gui_set_cell_dispatch(x, y, ch, fg, bg)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_set_cell
#endif
    integer, intent(in) :: x, y, ch, fg, bg
#ifdef ENABLE_GUI
    call gui_set_cell(x, y, ch, fg, bg)
#endif
end subroutine gui_set_cell_dispatch

subroutine gui_get_width_dispatch(w)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_get_width
#endif
    integer, intent(out) :: w
#ifdef ENABLE_GUI
    w = gui_get_width()
#else
    w = 80
#endif
end subroutine gui_get_width_dispatch

subroutine gui_get_height_dispatch(h)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_get_height
#endif
    integer, intent(out) :: h
#ifdef ENABLE_GUI
    h = gui_get_height()
#else
    h = 24
#endif
end subroutine gui_get_height_dispatch

subroutine gui_fill_rect_dispatch(x, y, w, h, color)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_fill_rect
#endif
    integer, intent(in) :: x, y, w, h, color
#ifdef ENABLE_GUI
    call gui_fill_rect(x, y, w, h, color)
#endif
end subroutine gui_fill_rect_dispatch

subroutine gui_draw_text_dispatch(x, y, str, fg, bg)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_draw_text
#endif
    integer, intent(in) :: x, y, fg, bg
    character(*), intent(in) :: str
#ifdef ENABLE_GUI
    call gui_draw_text(x, y, str, fg, bg)
#endif
end subroutine gui_draw_text_dispatch

subroutine gui_draw_border_dispatch(x, y, w, h, fg, bg)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_draw_border
#endif
    integer, intent(in) :: x, y, w, h, fg, bg
#ifdef ENABLE_GUI
    call gui_draw_border(x, y, w, h, fg, bg)
#endif
end subroutine gui_draw_border_dispatch

end module fortui_render
