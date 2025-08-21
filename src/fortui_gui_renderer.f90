module fortui_gui_renderer
! GUI renderer implementation for Widget-Renderer Collaboration Pattern
! Backend-specific renderer for graphics-based drawing operations
! Issue #61: Implements primitive drawing operations for GUI backend
use fortui_widget_renderer
use fortui_error, only: report_warning
use iso_c_binding, only: c_null_char
implicit none
private

public :: gui_renderer_t

! GUI-specific renderer extending abstract widget renderer
type, extends(widget_renderer_t) :: gui_renderer_t
    real :: dpi_scale = 1.0
    integer :: font_size = 16
    integer :: window_width = 800
    integer :: window_height = 600
contains
    procedure :: draw_rectangle => gui_draw_rectangle
    procedure :: draw_text => gui_draw_text
    procedure :: draw_line => gui_draw_line
    procedure :: draw_border => gui_draw_border
    procedure :: set_clip_region => gui_set_clip_region
    procedure :: get_text_size => gui_get_text_size
    procedure :: initialize => gui_initialize
end type gui_renderer_t

contains

subroutine gui_initialize(self, width, height, dpi_scale)
    class(gui_renderer_t), intent(inout) :: self
    integer, intent(in) :: width, height
    real, intent(in), optional :: dpi_scale
    
    self%window_width = width
    self%window_height = height
    if (present(dpi_scale)) self%dpi_scale = dpi_scale
end subroutine gui_initialize

subroutine gui_draw_rectangle(self, x, y, width, height, color)
    class(gui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    type(ui_color), intent(in) :: color
    
    integer :: pixel_x, pixel_y, pixel_w, pixel_h
    integer :: r, g, b, a
    
    ! Apply DPI scaling
    pixel_x = int(x * self%dpi_scale)
    pixel_y = int(y * self%dpi_scale)
    pixel_w = max(1, int(width * self%dpi_scale))
    pixel_h = max(1, int(height * self%dpi_scale))
    
    ! Convert color components to 8-bit integers
    r = max(0, min(255, int(color%r * 255.0)))
    g = max(0, min(255, int(color%g * 255.0)))
    b = max(0, min(255, int(color%b * 255.0)))
    a = max(0, min(255, int(color%a * 255.0)))
    
    ! Clip to window bounds
    if (pixel_x >= self%window_width .or. pixel_y >= self%window_height) return
    if (pixel_x + pixel_w < 0 .or. pixel_y + pixel_h < 0) return
    
    pixel_x = max(0, pixel_x)
    pixel_y = max(0, pixel_y)
    pixel_w = min(pixel_w, self%window_width - pixel_x)
    pixel_h = min(pixel_h, self%window_height - pixel_y)
    
    ! In real implementation, this would call raylib:
    ! call DrawRectangle(pixel_x, pixel_y, pixel_w, pixel_h, Color(r, g, b, a))
    
    ! Simulate rectangle drawing for testing
end subroutine gui_draw_rectangle

subroutine gui_draw_text(self, text, x, y, color)
    class(gui_renderer_t), intent(inout) :: self
    character(*), intent(in) :: text
    real, intent(in) :: x, y
    type(ui_color), intent(in) :: color
    
    integer :: pixel_x, pixel_y, scaled_font_size
    integer :: r, g, b, a
    character(len=:), allocatable :: c_text
    
    pixel_x = int(x * self%dpi_scale)
    pixel_y = int(y * self%dpi_scale)
    scaled_font_size = int(real(self%font_size) * self%dpi_scale)
    
    ! Convert color components
    r = max(0, min(255, int(color%r * 255.0)))
    g = max(0, min(255, int(color%g * 255.0)))
    b = max(0, min(255, int(color%b * 255.0)))
    a = max(0, min(255, int(color%a * 255.0)))
    
    ! Clip text to window bounds
    if (pixel_x >= self%window_width .or. pixel_y >= self%window_height) return
    
    ! Prepare null-terminated string for C interface
    c_text = trim(text) // c_null_char
    
    ! In real implementation, this would call raylib:
    ! call DrawText(c_text, pixel_x, pixel_y, scaled_font_size, Color(r, g, b, a))
    
    ! Simulate text drawing for testing
end subroutine gui_draw_text

subroutine gui_draw_line(self, x1, y1, x2, y2, color)
    class(gui_renderer_t), intent(inout) :: self
    real, intent(in) :: x1, y1, x2, y2
    type(ui_color), intent(in) :: color
    
    integer :: pixel_x1, pixel_y1, pixel_x2, pixel_y2
    integer :: r, g, b, a
    
    ! Apply DPI scaling
    pixel_x1 = int(x1 * self%dpi_scale)
    pixel_y1 = int(y1 * self%dpi_scale)
    pixel_x2 = int(x2 * self%dpi_scale)
    pixel_y2 = int(y2 * self%dpi_scale)
    
    ! Convert color components
    r = max(0, min(255, int(color%r * 255.0)))
    g = max(0, min(255, int(color%g * 255.0)))
    b = max(0, min(255, int(color%b * 255.0)))
    a = max(0, min(255, int(color%a * 255.0)))
    
    ! In real implementation, this would call raylib:
    ! call DrawLine(pixel_x1, pixel_y1, pixel_x2, pixel_y2, Color(r, g, b, a))
    
    ! Simulate line drawing for testing
end subroutine gui_draw_line

subroutine gui_draw_border(self, x, y, width, height, color)
    class(gui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    type(ui_color), intent(in) :: color
    
    integer :: pixel_x, pixel_y, pixel_w, pixel_h
    integer :: r, g, b, a
    
    ! Apply DPI scaling
    pixel_x = int(x * self%dpi_scale)
    pixel_y = int(y * self%dpi_scale)
    pixel_w = max(1, int(width * self%dpi_scale))
    pixel_h = max(1, int(height * self%dpi_scale))
    
    ! Convert color components
    r = max(0, min(255, int(color%r * 255.0)))
    g = max(0, min(255, int(color%g * 255.0)))
    b = max(0, min(255, int(color%b * 255.0)))
    a = max(0, min(255, int(color%a * 255.0)))
    
    ! In real implementation, this would call raylib:
    ! call DrawRectangleLines(pixel_x, pixel_y, pixel_w, pixel_h, Color(r, g, b, a))
    
    ! Simulate border drawing for testing
end subroutine gui_draw_border

subroutine gui_set_clip_region(self, x, y, width, height)
    class(gui_renderer_t), intent(inout) :: self
    real, intent(in) :: x, y, width, height
    
    integer :: pixel_x, pixel_y, pixel_w, pixel_h
    
    ! Apply DPI scaling
    pixel_x = int(x * self%dpi_scale)
    pixel_y = int(y * self%dpi_scale)
    pixel_w = max(1, int(width * self%dpi_scale))
    pixel_h = max(1, int(height * self%dpi_scale))
    
    ! In real implementation, this would call raylib:
    ! call BeginScissorMode(pixel_x, pixel_y, pixel_w, pixel_h)
    
    ! Simulate clipping for testing
end subroutine gui_set_clip_region

subroutine gui_get_text_size(self, text, width, height)
    class(gui_renderer_t), intent(in) :: self
    character(*), intent(in) :: text
    real, intent(out) :: width, height
    
    integer :: pixel_width, scaled_font_size
    character(len=:), allocatable :: c_text
    
    scaled_font_size = int(real(self%font_size) * self%dpi_scale)
    
    ! Prepare null-terminated string for C interface
    c_text = trim(text) // c_null_char
    
    ! In real implementation, this would call raylib:
    ! pixel_width = MeasureText(c_text, scaled_font_size)
    
    ! For testing, estimate text size based on character count and font size
    pixel_width = len_trim(text) * int(real(scaled_font_size) * 0.6)
    
    ! Convert back to dp units
    width = real(pixel_width) / self%dpi_scale
    height = real(scaled_font_size) / self%dpi_scale
end subroutine gui_get_text_size

end module fortui_gui_renderer