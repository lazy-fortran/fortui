module fortui_tui_renderer
! TUI renderer implementation for Widget-Renderer Collaboration Pattern
! Backend-specific renderer for terminal-based drawing operations
! Issue #61: Implements primitive drawing operations for TUI backend
use fortui_widget_renderer
use fortui_error, only: report_warning
implicit none
private

public :: tui_renderer_t

! TUI-specific renderer extending abstract widget renderer
type, extends(widget_renderer_t) :: tui_renderer_t
    integer :: terminal_width = 80
    integer :: terminal_height = 24
    integer :: cell_width_dp = 8
    integer :: cell_height_dp = 16
contains
    procedure :: draw_rectangle => tui_draw_rectangle
    procedure :: draw_text => tui_draw_text
    procedure :: draw_line => tui_draw_line
    procedure :: draw_border => tui_draw_border
    procedure :: set_clip_region => tui_set_clip_region
    procedure :: get_text_size => tui_get_text_size
    procedure :: initialize => tui_initialize
end type tui_renderer_t

contains

subroutine tui_initialize(self, width, height)
    class(tui_renderer_t), intent(inout) :: self
    integer, intent(in) :: width, height
    
    self%terminal_width = width
    self%terminal_height = height
end subroutine tui_initialize

subroutine tui_draw_rectangle(self, x, y, width, height, color)
    class(tui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    type(ui_color), intent(in) :: color
    
    integer :: cell_x, cell_y, cell_w, cell_h, i, j
    character :: fill_char
    
    ! Convert dp coordinates to cell coordinates
    cell_x = max(1, int(x / real(self%cell_width_dp)) + 1)
    cell_y = max(1, int(y / real(self%cell_height_dp)) + 1)
    cell_w = max(1, int(width / real(self%cell_width_dp)))
    cell_h = max(1, int(height / real(self%cell_height_dp)))
    
    ! Choose fill character based on color intensity
    if (color%r + color%g + color%b > 1.5) then
        fill_char = ' '  ! Light colors use space (background)
    else if (color%r + color%g + color%b > 0.75) then
        fill_char = '.'  ! Medium colors use dots
    else
        fill_char = '#'  ! Dark colors use blocks
    end if
    
    ! Simulate drawing rectangle in terminal
    do j = 0, cell_h - 1
        if (cell_y + j <= self%terminal_height) then
            do i = 0, cell_w - 1
                if (cell_x + i <= self%terminal_width) then
                    ! In real implementation, this would call termbox2
                    ! For now, just simulate the drawing operation
                    continue
                end if
            end do
        end if
    end do
end subroutine tui_draw_rectangle

subroutine tui_draw_text(self, text, x, y, color)
    class(tui_renderer_t), intent(inout) :: self
    character(*), intent(in) :: text
    real, intent(in) :: x, y
    type(ui_color), intent(in) :: color
    
    integer :: cell_x, cell_y, i, text_len
    
    cell_x = max(1, int(x / real(self%cell_width_dp)) + 1)
    cell_y = max(1, int(y / real(self%cell_height_dp)) + 1)
    text_len = len_trim(text)
    
    ! Clip text to terminal bounds
    if (cell_y > self%terminal_height) return
    
    ! Simulate drawing text in terminal
    do i = 1, min(text_len, self%terminal_width - cell_x + 1)
        if (cell_x + i - 1 <= self%terminal_width) then
            ! In real implementation, this would call termbox2
            ! tb_set_cell(cell_x + i - 2, cell_y - 1, ichar(text(i:i)), fg, bg)
            continue
        end if
    end do
end subroutine tui_draw_text

subroutine tui_draw_line(self, x1, y1, x2, y2, color)
    class(tui_renderer_t), intent(inout) :: self
    real, intent(in) :: x1, y1, x2, y2
    type(ui_color), intent(in) :: color
    
    integer :: cell_x1, cell_y1, cell_x2, cell_y2
    integer :: dx, dy, steps, i
    real :: step_x, step_y, curr_x, curr_y
    character :: line_char
    
    ! Convert to cell coordinates
    cell_x1 = int(x1 / real(self%cell_width_dp)) + 1
    cell_y1 = int(y1 / real(self%cell_height_dp)) + 1
    cell_x2 = int(x2 / real(self%cell_width_dp)) + 1
    cell_y2 = int(y2 / real(self%cell_height_dp)) + 1
    
    ! Simple line drawing using character approximation
    dx = abs(cell_x2 - cell_x1)
    dy = abs(cell_y2 - cell_y1)
    steps = max(dx, dy)
    
    if (steps == 0) return
    
    step_x = real(cell_x2 - cell_x1) / real(steps)
    step_y = real(cell_y2 - cell_y1) / real(steps)
    
    ! Choose line character based on direction
    if (abs(step_x) > abs(step_y)) then
        line_char = '-'  ! Horizontal
    else if (abs(step_y) > abs(step_x)) then
        line_char = '|'  ! Vertical
    else
        line_char = '+'  ! Diagonal
    end if
    
    curr_x = real(cell_x1)
    curr_y = real(cell_y1)
    
    do i = 0, steps
        if (int(curr_x) >= 1 .and. int(curr_x) <= self%terminal_width .and. &
            int(curr_y) >= 1 .and. int(curr_y) <= self%terminal_height) then
            ! In real implementation: tb_set_cell(int(curr_x)-1, int(curr_y)-1, ichar(line_char), fg, bg)
            continue
        end if
        curr_x = curr_x + step_x
        curr_y = curr_y + step_y
    end do
end subroutine tui_draw_line

subroutine tui_draw_border(self, x, y, width, height, color)
    class(tui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    type(ui_color), intent(in) :: color
    
    ! Draw border as four lines
    call self%draw_line(x, y, x + width, y, color)              ! Top
    call self%draw_line(x, y + height, x + width, y + height, color)  ! Bottom
    call self%draw_line(x, y, x, y + height, color)            ! Left
    call self%draw_line(x + width, y, x + width, y + height, color)   ! Right
end subroutine tui_draw_border

subroutine tui_set_clip_region(self, x, y, width, height)
    class(tui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    
    ! TUI clipping is basic - just note the region
    ! In real implementation, this would set clip bounds for subsequent drawing
end subroutine tui_set_clip_region

subroutine tui_get_text_size(self, text, width, height)
    class(tui_renderer_t), intent(in) :: self
    character(*), intent(in) :: text
    real, intent(out) :: width, height
    
    ! TUI text size is predictable (monospace)
    width = real(len_trim(text) * self%cell_width_dp)
    height = real(self%cell_height_dp)
end subroutine tui_get_text_size

end module fortui_tui_renderer