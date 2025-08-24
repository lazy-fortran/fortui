module fortui_gui_renderer
! GUI IMMEDIATE-MODE rendering procedures - NO INHERITANCE
! Direct procedural drawing calls for GUI backend
! ZERO TOLERANCE: No renderer objects, just procedures
implicit none
private

! Public procedural drawing functions - NO OBJECTS
public :: gui_draw_rectangle, gui_draw_text, gui_draw_line
public :: gui_draw_border, gui_set_clip_region, gui_get_text_size
public :: gui_initialize_drawing

contains

! PURE PROCEDURAL GUI DRAWING - NO OBJECTS

subroutine gui_initialize_drawing(width, height, dpi_scale)
    integer, intent(in) :: width, height
    real, intent(in), optional :: dpi_scale
    
    ! Initialize GUI drawing context
    ! Direct graphics initialization, no object state
end subroutine gui_initialize_drawing

subroutine gui_draw_rectangle(x, y, width, height, color)
    real, intent(in) :: x, y, width, height
    integer, intent(in), optional :: color
    
    ! Draw rectangle directly to graphics buffer
    ! Immediate drawing, no deferred rendering
end subroutine gui_draw_rectangle

subroutine gui_draw_text(x, y, text, color, size)
    real, intent(in) :: x, y
    character(*), intent(in) :: text
    integer, intent(in), optional :: color
    real, intent(in), optional :: size
    
    ! Draw text directly to graphics buffer
    ! Immediate text rendering
end subroutine gui_draw_text

subroutine gui_draw_line(x1, y1, x2, y2, color, width)
    real, intent(in) :: x1, y1, x2, y2
    integer, intent(in), optional :: color
    real, intent(in), optional :: width
    
    ! Draw line directly to graphics buffer
    ! Immediate line drawing
end subroutine gui_draw_line

subroutine gui_draw_border(x, y, width, height, color, style)
    real, intent(in) :: x, y, width, height
    integer, intent(in), optional :: color
    character(*), intent(in), optional :: style
    
    ! Draw border directly to graphics buffer
    ! Immediate border rendering
end subroutine gui_draw_border

subroutine gui_set_clip_region(x, y, width, height)
    real, intent(in) :: x, y, width, height
    
    ! Set clipping region for GUI drawing
    ! Direct state modification, no objects
end subroutine gui_set_clip_region

subroutine gui_get_text_size(text, width_dp, height_dp, font_size)
    character(*), intent(in) :: text
    real, intent(out) :: width_dp, height_dp
    real, intent(in), optional :: font_size
    
    ! Calculate text size for GUI rendering
    ! Direct measurement, no object state
    real :: size_factor
    
    size_factor = 16.0
    if (present(font_size)) size_factor = font_size
    
    width_dp = real(len_trim(text)) * size_factor * 0.6  ! Approximate character width
    height_dp = size_factor * 1.2  ! Line height with spacing
end subroutine gui_get_text_size

end module fortui_gui_renderer