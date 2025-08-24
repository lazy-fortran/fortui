module fortui_tui_renderer
! TUI IMMEDIATE-MODE rendering procedures - NO INHERITANCE
! Direct procedural drawing calls for terminal backend
! ZERO TOLERANCE: No renderer objects, just procedures
implicit none
private

! Public procedural drawing functions - NO OBJECTS
public :: tui_draw_rectangle, tui_draw_text, tui_draw_line
public :: tui_draw_border, tui_set_clip_region, tui_get_text_size
public :: tui_initialize_drawing

contains

! PURE PROCEDURAL TUI DRAWING - NO OBJECTS

subroutine tui_initialize_drawing(width, height)
    integer, intent(in) :: width, height
    
    ! Initialize terminal drawing context
    ! Direct terminal initialization, no object state
end subroutine tui_initialize_drawing

subroutine tui_draw_rectangle(x, y, width, height, color)
    real, intent(in) :: x, y, width, height
    integer, intent(in), optional :: color
    
    ! Draw rectangle directly to terminal buffer
    ! Immediate drawing, no deferred rendering
end subroutine tui_draw_rectangle

subroutine tui_draw_text(x, y, text, color, size)
    real, intent(in) :: x, y
    character(*), intent(in) :: text
    integer, intent(in), optional :: color
    real, intent(in), optional :: size
    
    ! Draw text directly to terminal buffer
    ! Immediate text rendering
end subroutine tui_draw_text

subroutine tui_draw_line(x1, y1, x2, y2, color, width)
    real, intent(in) :: x1, y1, x2, y2
    integer, intent(in), optional :: color
    real, intent(in), optional :: width
    
    ! Draw line directly to terminal buffer
    ! Immediate line drawing
end subroutine tui_draw_line

subroutine tui_draw_border(x, y, width, height, color, style)
    real, intent(in) :: x, y, width, height
    integer, intent(in), optional :: color
    character(*), intent(in), optional :: style
    
    ! Draw border directly to terminal buffer
    ! Immediate border rendering
end subroutine tui_draw_border

subroutine tui_set_clip_region(x, y, width, height)
    real, intent(in) :: x, y, width, height
    
    ! Set clipping region for terminal drawing
    ! Direct state modification, no objects
end subroutine tui_set_clip_region

subroutine tui_get_text_size(text, width_dp, height_dp, font_size)
    character(*), intent(in) :: text
    real, intent(out) :: width_dp, height_dp
    real, intent(in), optional :: font_size
    
    ! Calculate text size for terminal rendering
    ! Direct measurement, no object state
    width_dp = real(len_trim(text)) * 8.0  ! 8dp per character
    height_dp = 16.0  ! 16dp line height
    
    if (present(font_size)) then
        width_dp = width_dp * (font_size / 16.0)
        height_dp = height_dp * (font_size / 16.0)
    end if
end subroutine tui_get_text_size

end module fortui_tui_renderer