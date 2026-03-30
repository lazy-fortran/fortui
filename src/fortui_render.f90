module fortui_render
! Backend-agnostic render dispatch via procedure pointers.
! Backends register their rendering functions during init.
! Widgets call render_set_cell etc. without knowing which
! backend is active.
implicit none
private

public :: render_set_cell, render_is_active
public :: render_get_width, render_get_height
public :: render_register_backend, render_clear_backend

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
integer, parameter, public :: RC_BOLD = 16777216
integer, parameter, public :: RC_UNDERLINE = 33554432
integer, parameter, public :: RC_REVERSE = 67108864

abstract interface
    subroutine set_cell_iface(x, y, ch, fg, bg)
        integer, intent(in) :: x, y, ch, fg, bg
    end subroutine

    logical function is_active_iface()
    end function

    integer function get_dim_iface()
    end function
end interface

procedure(set_cell_iface), pointer, save :: &
    set_cell_ptr => null()
procedure(is_active_iface), pointer, save :: &
    is_active_ptr => null()
procedure(get_dim_iface), pointer, save :: &
    get_width_ptr => null()
procedure(get_dim_iface), pointer, save :: &
    get_height_ptr => null()

contains

subroutine render_register_backend(set_cell_fn, is_active_fn, &
    get_width_fn, get_height_fn)
    procedure(set_cell_iface) :: set_cell_fn
    procedure(is_active_iface) :: is_active_fn
    procedure(get_dim_iface) :: get_width_fn
    procedure(get_dim_iface) :: get_height_fn

    set_cell_ptr => set_cell_fn
    is_active_ptr => is_active_fn
    get_width_ptr => get_width_fn
    get_height_ptr => get_height_fn
end subroutine render_register_backend

subroutine render_clear_backend()
    set_cell_ptr => null()
    is_active_ptr => null()
    get_width_ptr => null()
    get_height_ptr => null()
end subroutine render_clear_backend

subroutine render_set_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg

    if (associated(set_cell_ptr)) &
        call set_cell_ptr(x, y, ch, fg, bg)
end subroutine render_set_cell

logical function render_is_active()
    if (associated(is_active_ptr)) then
        render_is_active = is_active_ptr()
    else
        render_is_active = .false.
    end if
end function render_is_active

integer function render_get_width()
    if (associated(get_width_ptr)) then
        render_get_width = get_width_ptr()
    else
        render_get_width = 80
    end if
end function render_get_width

integer function render_get_height()
    if (associated(get_height_ptr)) then
        render_get_height = get_height_ptr()
    else
        render_get_height = 24
    end if
end function render_get_height

end module fortui_render
