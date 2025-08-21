module fortui_platform_measurement
! Cross-platform measurement detection for UI context integration
! Provides platform-specific measurement APIs with intelligent fallbacks
use fortui_units, only: ui_context
implicit none
private

! Public measurement functions
public :: measure_terminal_cells, detect_system_dpi, measure_font_metrics, detect_text_scaling
public :: validate_context, invalidate_layout, ui_update_context
public :: dp_to_cell_coords_with_context, dp_to_pixel_coords_with_context
public :: render_tui_element, render_gui_element

! Platform detection functions
public :: detect_platform, get_desktop_environment, check_api_availability
public :: get_fallback_context

! Measurement caching system
type :: measurement_cache_t
    logical :: terminal_measured = .false.
    real :: cached_cell_w_dp = 8.0
    real :: cached_cell_h_dp = 16.0
    logical :: dpi_measured = .false.
    real :: cached_dpi_scale = 1.0
    logical :: font_measured = .false.
    real :: cached_em_dp = 16.0
    logical :: text_scale_measured = .false.
    real :: cached_text_scale = 1.0
end type measurement_cache_t

! Cache now managed through context parameters - no global state

contains

! Terminal measurement functions

subroutine measure_terminal_cells(cell_w_dp, cell_h_dp)
    ! Measure terminal cell dimensions in dp units
    real, intent(out) :: cell_w_dp, cell_h_dp
    
    character(len=256) :: term_var
    integer :: ios
    
    ! Try platform-specific terminal measurement
    call get_environment_variable("TERM", term_var, status=ios)
    
    if (ios == 0) then
        ! Try terminfo/termcap integration for actual measurement
        call measure_terminal_via_terminfo(cell_w_dp, cell_h_dp)
    else
        ! Fallback to conservative defaults
        cell_w_dp = 8.0   ! Conservative monospace character width
        cell_h_dp = 16.0  ! Conservative line height
    end if
    
    ! Validate measurements
    if (cell_w_dp <= 0.0 .or. cell_w_dp > 50.0) cell_w_dp = 8.0
    if (cell_h_dp <= 0.0 .or. cell_h_dp > 100.0) cell_h_dp = 16.0
end subroutine measure_terminal_cells

subroutine measure_terminal_via_terminfo(cell_w_dp, cell_h_dp)
    ! Platform-specific terminal measurement via terminfo/termcap
    real, intent(out) :: cell_w_dp, cell_h_dp
    
    ! TODO: Implement actual terminfo/termcap integration
    ! For now, use intelligent defaults based on common terminal configurations
    
    ! Standard monospace font assumptions
    cell_w_dp = 8.0   ! Most terminals use 8-pixel wide characters
    cell_h_dp = 16.0  ! Most terminals use 16-pixel high lines
    
    ! Future implementation would query:
    ! - Terminal font metrics via escape sequences
    ! - Font configuration via fontconfig (Linux)
    ! - Registry settings (Windows)
    ! - System font APIs (macOS)
end subroutine measure_terminal_via_terminfo

! Display measurement functions

subroutine detect_system_dpi(dpi_scale)
    ! Detect system DPI scaling factor
    real, intent(out) :: dpi_scale
    
    character(len=256) :: platform
    
    ! Detect platform and use appropriate measurement method
    call detect_platform(platform)
    
    select case (trim(platform))
    case ("linux")
        call detect_linux_dpi(dpi_scale)
    case ("windows")
        call detect_windows_dpi(dpi_scale)
    case ("macos")
        call detect_macos_dpi(dpi_scale)
    case default
        dpi_scale = 1.0  ! Conservative fallback
    end select
    
    ! Validate DPI scale
    if (dpi_scale <= 0.1 .or. dpi_scale > 10.0) dpi_scale = 1.0
end subroutine detect_system_dpi

subroutine detect_linux_dpi(dpi_scale)
    ! Linux-specific DPI detection
    real, intent(out) :: dpi_scale
    
    character(len=256) :: de_var, display_var
    integer :: ios
    
    ! Try X11/Wayland DPI detection
    call get_environment_variable("DISPLAY", display_var, status=ios)
    if (ios == 0 .and. len_trim(display_var) > 0) then
        ! X11 environment - try X11 DPI queries
        call detect_x11_dpi(dpi_scale)
        return
    end if
    
    call get_environment_variable("WAYLAND_DISPLAY", display_var, status=ios)
    if (ios == 0 .and. len_trim(display_var) > 0) then
        ! Wayland environment - try Wayland DPI queries
        call detect_wayland_dpi(dpi_scale)
        return
    end if
    
    ! Fallback for headless or unknown environments
    dpi_scale = 1.0
end subroutine detect_linux_dpi

subroutine detect_x11_dpi(dpi_scale)
    ! X11-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! TODO: Implement actual X11 DPI queries
    ! Would use xrandr or X11 APIs to get actual DPI
    
    ! For now, use reasonable default
    dpi_scale = 1.0
    
    ! Future implementation would query:
    ! - xrandr --verbose for DPI information
    ! - X11 DisplayWidth/DisplayHeight and DisplayWidthMM/DisplayHeightMM
    ! - Desktop environment scaling settings
end subroutine detect_x11_dpi

subroutine detect_wayland_dpi(dpi_scale)
    ! Wayland-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! TODO: Implement actual Wayland DPI queries
    ! Would use Wayland protocol to get scaling information
    
    ! For now, use reasonable default
    dpi_scale = 1.0
    
    ! Future implementation would query:
    ! - Wayland output scaling factors
    ! - Compositor-specific scaling settings
    ! - Desktop environment scaling preferences
end subroutine detect_wayland_dpi

subroutine detect_windows_dpi(dpi_scale)
    ! Windows-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! TODO: Implement Windows DPI APIs
    ! Would use GetDpiForWindow, SystemParametersInfo, etc.
    
    ! For now, use reasonable default
    dpi_scale = 1.0
    
    ! Future implementation would use:
    ! - GetDpiForWindow API
    ! - SystemParametersInfo for system DPI
    ! - High-DPI awareness APIs
end subroutine detect_windows_dpi

subroutine detect_macos_dpi(dpi_scale)
    ! macOS-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! TODO: Implement macOS DPI APIs
    ! Would use NSScreen backingScaleFactor
    
    ! For now, use reasonable default
    dpi_scale = 1.0
    
    ! Future implementation would use:
    ! - NSScreen backingScaleFactor for Retina detection
    ! - System scaling preferences
    ! - Multi-monitor scaling awareness
end subroutine detect_macos_dpi

! Font measurement functions

subroutine measure_font_metrics(em_dp)
    ! Measure font metrics for em unit calculations
    real, intent(out) :: em_dp
    
    character(len=256) :: platform
    
    ! Try platform-specific font measurement
    call detect_platform(platform)
    
    select case (trim(platform))
    case ("linux")
        call measure_linux_fonts(em_dp)
    case ("windows")
        call measure_windows_fonts(em_dp)
    case ("macos")
        call measure_macos_fonts(em_dp)
    case default
        em_dp = 16.0  ! Conservative fallback
    end select
    
    ! Validate font metrics
    if (em_dp <= 4.0 .or. em_dp > 200.0) em_dp = 16.0
end subroutine measure_font_metrics

subroutine measure_linux_fonts(em_dp)
    ! Linux font measurement via fontconfig
    real, intent(out) :: em_dp
    
    ! TODO: Implement fontconfig integration
    ! Would query system default fonts and their metrics
    
    ! For now, use reasonable default
    em_dp = 16.0
    
    ! Future implementation would use:
    ! - fontconfig APIs to get default font
    ! - Font metrics from font files
    ! - Desktop environment font settings
end subroutine measure_linux_fonts

subroutine measure_windows_fonts(em_dp)
    ! Windows font measurement
    real, intent(out) :: em_dp
    
    ! TODO: Implement Windows font APIs
    ! Would use GDI+ or DirectWrite for font metrics
    
    ! For now, use reasonable default  
    em_dp = 16.0
    
    ! Future implementation would use:
    ! - System font metrics APIs
    ! - Default font family detection
    ! - Font scaling factor detection
end subroutine measure_windows_fonts

subroutine measure_macos_fonts(em_dp)
    ! macOS font measurement
    real, intent(out) :: em_dp
    
    ! TODO: Implement macOS font APIs
    ! Would use NSFont system font metrics
    
    ! For now, use reasonable default
    em_dp = 16.0
    
    ! Future implementation would use:
    ! - NSFont systemFontOfSize metrics
    ! - Font descriptor APIs
    ! - Dynamic Type scaling
end subroutine measure_macos_fonts

! Accessibility measurement functions

subroutine detect_text_scaling(text_scale)
    ! Detect accessibility text scaling factor
    real, intent(out) :: text_scale
    
    character(len=256) :: platform
    
    ! Try platform-specific accessibility detection
    call detect_platform(platform)
    
    select case (trim(platform))
    case ("linux")
        call detect_linux_text_scaling(text_scale)
    case ("windows")
        call detect_windows_text_scaling(text_scale)
    case ("macos")
        call detect_macos_text_scaling(text_scale)
    case default
        text_scale = 1.0  ! Conservative fallback
    end select
    
    ! Validate text scaling
    if (text_scale <= 0.1 .or. text_scale > 10.0) text_scale = 1.0
end subroutine detect_text_scaling

subroutine detect_linux_text_scaling(text_scale)
    ! Linux accessibility text scaling via gsettings
    real, intent(out) :: text_scale
    
    ! TODO: Implement gsettings integration
    ! Would query text-scaling-factor setting
    
    ! For now, use conservative default
    text_scale = 1.0
    
    ! Future implementation would query:
    ! - gsettings get org.gnome.desktop.interface text-scaling-factor
    ! - KDE scaling settings
    ! - Desktop environment accessibility preferences
end subroutine detect_linux_text_scaling

subroutine detect_windows_text_scaling(text_scale)
    ! Windows accessibility text scaling
    real, intent(out) :: text_scale
    
    ! TODO: Implement Windows accessibility APIs
    ! Would use SystemParametersInfo for accessibility settings
    
    ! For now, use conservative default
    text_scale = 1.0
    
    ! Future implementation would use:
    ! - SystemParametersInfo SPI_GETFONTSMOOTHING
    ! - Ease of Access text size settings
    ! - High contrast mode detection
end subroutine detect_windows_text_scaling

subroutine detect_macos_text_scaling(text_scale)
    ! macOS accessibility text scaling
    real, intent(out) :: text_scale
    
    ! TODO: Implement macOS accessibility APIs
    ! Would use NSUserDefaults preferredContentSizeCategory
    
    ! For now, use conservative default
    text_scale = 1.0
    
    ! Future implementation would use:
    ! - NSUserDefaults preferredContentSizeCategory
    ! - Dynamic Type scaling factors
    ! - Accessibility settings APIs
end subroutine detect_macos_text_scaling

! Context management functions

subroutine validate_context(ctx)
    ! Validate UI context values and provide corrections
    type(ui_context), intent(inout) :: ctx
    
    ! Validate DPI scale
    if (ctx%dpi_scale <= 0.0 .or. ctx%dpi_scale > 10.0) then
        print *, "validate_context: Invalid dpi_scale", ctx%dpi_scale, "correcting to 1.0"
        ctx%dpi_scale = 1.0
    end if
    
    ! Validate em_dp
    if (ctx%em_dp <= 0.0 .or. ctx%em_dp > 200.0) then
        print *, "validate_context: Invalid em_dp", ctx%em_dp, "correcting to 16.0"
        ctx%em_dp = 16.0
    end if
    
    ! Validate text_scale
    if (ctx%text_scale <= 0.0 .or. ctx%text_scale > 10.0) then
        print *, "validate_context: Invalid text_scale", ctx%text_scale, "correcting to 1.0"
        ctx%text_scale = 1.0
    end if
    
    ! Validate cell dimensions
    if (ctx%cell_w_dp <= 0.0 .or. ctx%cell_w_dp > 100.0) then
        print *, "validate_context: Invalid cell_w_dp", ctx%cell_w_dp, "correcting to 8.0"
        ctx%cell_w_dp = 8.0
    end if
    
    if (ctx%cell_h_dp <= 0.0 .or. ctx%cell_h_dp > 100.0) then
        print *, "validate_context: Invalid cell_h_dp", ctx%cell_h_dp, "correcting to 16.0"
        ctx%cell_h_dp = 16.0
    end if
end subroutine validate_context

subroutine ui_update_context(new_ctx)
    ! Update UI context with new measurement values
    use fortui_units, only: ui_set_context
    type(ui_context), intent(in) :: new_ctx
    
    type(ui_context) :: validated_ctx
    
    ! Validate new context
    validated_ctx = new_ctx
    call validate_context(validated_ctx)
    
    ! Apply validated context
    call ui_set_context(validated_ctx)
    
    ! Invalidate measurement cache to force remeasurement
    call invalidate_measurement_cache()
end subroutine ui_update_context

subroutine invalidate_layout()
    ! Invalidate layout calculations to trigger recalculation
    ! This would be called when context changes require layout updates
    
    ! For now, just a placeholder
    ! Future implementation would:
    ! - Mark all cached layout calculations as invalid
    ! - Trigger layout recalculation on next frame
    ! - Update widget dimensions and positions
end subroutine invalidate_layout

subroutine invalidate_measurement_cache()
    ! Invalidate measurement cache to force remeasurement
    ! Note: With context-based approach, no global cache to invalidate
    ! Measurements are computed fresh each time or cached in context
end subroutine invalidate_measurement_cache

! Context-aware rendering functions

subroutine dp_to_cell_coords_with_context(dp_x, dp_y, cell_x, cell_y, ctx)
    ! Convert dp coordinates to cell coordinates using provided context
    real, intent(in) :: dp_x, dp_y
    integer, intent(out) :: cell_x, cell_y
    type(ui_context), intent(in) :: ctx
    
    ! Convert and snap to cell boundaries
    cell_x = nint(dp_x / ctx%cell_w_dp)
    cell_y = nint(dp_y / ctx%cell_h_dp)
end subroutine dp_to_cell_coords_with_context

subroutine dp_to_pixel_coords_with_context(dp_x, pixel_x, ctx)
    ! Convert dp coordinates to pixel coordinates maintaining subpixel precision
    real, intent(in) :: dp_x
    real, intent(out) :: pixel_x
    type(ui_context), intent(in) :: ctx
    
    ! Convert with subpixel precision
    pixel_x = dp_x * ctx%dpi_scale
end subroutine dp_to_pixel_coords_with_context

subroutine render_tui_element(x_dp, y_dp, w_dp, h_dp, ctx)
    ! Render TUI element with context-aware coordinate conversion
    real, intent(in) :: x_dp, y_dp, w_dp, h_dp
    type(ui_context), intent(in) :: ctx
    
    integer :: cell_x, cell_y, cell_w, cell_h
    
    ! Convert to cell coordinates with snapping
    call dp_to_cell_coords_with_context(x_dp, y_dp, cell_x, cell_y, ctx)
    call dp_to_cell_coords_with_context(w_dp, h_dp, cell_w, cell_h, ctx)
    
    ! Render element at cell coordinates
    ! (Implementation would integrate with TUI rendering system)
end subroutine render_tui_element

subroutine render_gui_element(x_dp, y_dp, w_dp, h_dp, ctx)
    ! Render GUI element with context-aware coordinate conversion
    real, intent(in) :: x_dp, y_dp, w_dp, h_dp
    type(ui_context), intent(in) :: ctx
    
    real :: pixel_x, pixel_y, pixel_w, pixel_h
    
    ! Convert to pixel coordinates with subpixel precision
    call dp_to_pixel_coords_with_context(x_dp, pixel_x, ctx)
    call dp_to_pixel_coords_with_context(y_dp, pixel_y, ctx)
    call dp_to_pixel_coords_with_context(w_dp, pixel_w, ctx)
    call dp_to_pixel_coords_with_context(h_dp, pixel_h, ctx)
    
    ! Render element at pixel coordinates
    ! (Implementation would integrate with GUI rendering system)
end subroutine render_gui_element

! Platform detection functions

subroutine detect_platform(platform)
    ! Detect current operating system platform
    character(len=*), intent(out) :: platform
    
    character(len=256) :: os_var
    integer :: ios
    
    ! Use preprocessor detection for compile-time platform
#ifdef __linux__
    platform = "linux"
#elif defined(_WIN32) || defined(_WIN64)
    platform = "windows"
#elif defined(__APPLE__)
    platform = "macos"
#else
    platform = "unknown"
#endif
    
    ! Could also use runtime detection via environment variables
    ! This provides basic platform identification for measurement selection
end subroutine detect_platform

subroutine get_desktop_environment(de)
    ! Detect desktop environment on Linux
    character(len=*), intent(out) :: de
    
    character(len=256) :: env_var
    integer :: ios
    
    ! Try XDG_CURRENT_DESKTOP first
    call get_environment_variable("XDG_CURRENT_DESKTOP", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        de = trim(env_var)
        return
    end if
    
    ! Fallback to other detection methods
    call get_environment_variable("DESKTOP_SESSION", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        de = trim(env_var)
        return
    end if
    
    de = "unknown"
end subroutine get_desktop_environment

logical function check_api_availability(api_name)
    ! Check if specific measurement API is available
    character(len=*), intent(in) :: api_name
    
    ! TODO: Implement runtime API availability checking
    ! Would test for library availability, function symbols, etc.
    
    ! For now, assume APIs are not available (conservative approach)
    check_api_availability = .false.
end function check_api_availability

function get_fallback_context() result(ctx)
    ! Get conservative fallback context for when measurement fails
    type(ui_context) :: ctx
    
    ! Conservative defaults that work on most systems
    ctx%dpi_scale = 1.0     ! Standard DPI
    ctx%em_dp = 16.0        ! Standard font size
    ctx%text_scale = 1.0    ! No accessibility scaling
    ctx%cell_w_dp = 8.0     ! Standard monospace width
    ctx%cell_h_dp = 16.0    ! Standard line height
end function get_fallback_context

end module fortui_platform_measurement