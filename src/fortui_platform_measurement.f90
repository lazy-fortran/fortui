module fortui_platform_measurement
! Cross-platform measurement detection for UI context integration
! Provides platform-specific measurement APIs with intelligent fallbacks
use fortui_units, only: ui_context
use fortui_error, only: report_warning
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
    
    character(len=256) :: term_prog, cols_str, lines_str
    integer :: ios, cols, lines
    
    ! Try to get terminal dimensions and estimate cell size
    call get_environment_variable("COLUMNS", cols_str, status=ios)
    if (ios == 0) then
        read(cols_str, *, iostat=ios) cols
        if (ios /= 0) cols = 80
    else
        cols = 80  ! Default terminal width
    end if
    
    call get_environment_variable("LINES", lines_str, status=ios)
    if (ios == 0) then
        read(lines_str, *, iostat=ios) lines
        if (ios /= 0) lines = 24
    else
        lines = 24  ! Default terminal height
    end if
    
    ! Query font metrics via terminal capabilities
    call query_terminal_font_metrics(cell_w_dp, cell_h_dp)
    
    ! Validate and apply intelligent defaults if query failed
    if (cell_w_dp <= 0.0) then
        ! Estimate based on common terminal configurations
        call get_environment_variable("TERM_PROGRAM", term_prog, status=ios)
        if (ios == 0) then
            select case (trim(term_prog))
            case ("xterm", "xterm-256color")
                cell_w_dp = 7.0   ! xterm default
                cell_h_dp = 14.0
            case ("gnome-terminal")
                cell_w_dp = 8.0   ! GNOME terminal default
                cell_h_dp = 16.0
            case ("konsole")
                cell_w_dp = 8.0   ! KDE Konsole default
                cell_h_dp = 15.0
            case default
                cell_w_dp = 8.0   ! Conservative default
                cell_h_dp = 16.0
            end select
        else
            cell_w_dp = 8.0   ! Fallback default
            cell_h_dp = 16.0
        end if
    end if
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
    
    character(len=256) :: de_name, scale_env
    integer :: ios
    real :: parsed_scale
    
    ! Try desktop environment scaling settings first
    call get_desktop_environment(de_name)
    
    select case (trim(de_name))
    case ("GNOME", "ubuntu:GNOME")
        call detect_gnome_scaling(dpi_scale)
    case ("KDE", "plasma")
        call detect_kde_scaling(dpi_scale)
    case ("XFCE")
        call detect_xfce_scaling(dpi_scale)
    case default
        ! Try generic X11 methods
        call detect_generic_x11_scaling(dpi_scale)
    end select
    
    ! Check for user-specified scaling via environment
    call get_environment_variable("GDK_SCALE", scale_env, status=ios)
    if (ios == 0 .and. len_trim(scale_env) > 0) then
        read(scale_env, *, iostat=ios) parsed_scale
        if (ios == 0 .and. parsed_scale > 0.1 .and. parsed_scale <= 10.0) then
            dpi_scale = parsed_scale
        end if
    end if
    
    ! Validate final result
    if (dpi_scale <= 0.1 .or. dpi_scale > 10.0) dpi_scale = 1.0
end subroutine detect_x11_dpi

subroutine detect_wayland_dpi(dpi_scale)
    ! Wayland-specific DPI detection
    real, intent(out) :: dpi_scale
    
    character(len=256) :: de_name, scale_env
    integer :: ios
    real :: parsed_scale
    
    ! Wayland scaling is typically handled by desktop environment
    call get_desktop_environment(de_name)
    
    select case (trim(de_name))
    case ("GNOME", "ubuntu:GNOME")
        call detect_gnome_scaling(dpi_scale)
    case ("KDE", "plasma")
        call detect_kde_scaling(dpi_scale)
    case ("sway")
        call detect_sway_scaling(dpi_scale)
    case default
        ! Try environment variables commonly used with Wayland
        call detect_wayland_env_scaling(dpi_scale)
    end select
    
    ! Check for Wayland-specific scaling environment variables
    call get_environment_variable("WAYLAND_DISPLAY", scale_env, status=ios)
    if (ios == 0) then
        ! Check for scale environment variables
        call get_environment_variable("QT_SCALE_FACTOR", scale_env, status=ios)
        if (ios == 0 .and. len_trim(scale_env) > 0) then
            read(scale_env, *, iostat=ios) parsed_scale
            if (ios == 0 .and. parsed_scale > 0.1 .and. parsed_scale <= 10.0) then
                dpi_scale = parsed_scale
                return
            end if
        end if
    end if
    
    ! Validate final result
    if (dpi_scale <= 0.1 .or. dpi_scale > 10.0) dpi_scale = 1.0
end subroutine detect_wayland_dpi

subroutine detect_windows_dpi(dpi_scale)
    ! Windows-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! Windows DPI detection would use Win32 APIs:
    ! - GetDpiForWindow() for per-monitor DPI awareness
    ! - SystemParametersInfo() for system DPI settings
    ! - GetDC()/GetDeviceCaps() for display metrics
    
    ! Fallback to standard DPI until Win32 APIs are integrated
    dpi_scale = 1.0
    
    call report_warning("fortui_platform_measurement", "detect_windows_dpi", &
                        "Windows DPI detection not yet implemented - using default")
end subroutine detect_windows_dpi

subroutine detect_macos_dpi(dpi_scale)
    ! macOS-specific DPI detection
    real, intent(out) :: dpi_scale
    
    ! macOS DPI detection would use Cocoa APIs:
    ! - NSScreen.backingScaleFactor for Retina display detection
    ! - NSUserDefaults for system scaling preferences
    ! - CGDisplayModeGetPixelWidth/Height for physical resolution
    
    ! Fallback to standard DPI until Cocoa APIs are integrated
    dpi_scale = 1.0
    
    call report_warning("fortui_platform_measurement", "detect_macos_dpi", &
                        "macOS DPI detection not yet implemented - using default")
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
    ! Linux font measurement via system settings
    real, intent(out) :: em_dp
    
    character(len=256) :: de_name
    real :: font_size
    
    ! Try desktop environment font settings
    call get_desktop_environment(de_name)
    
    select case (trim(de_name))
    case ("GNOME", "ubuntu:GNOME")
        call get_gnome_font_size(font_size)
    case ("KDE", "plasma")
        call get_kde_font_size(font_size)
    case ("XFCE")
        call get_xfce_font_size(font_size)
    case default
        call get_generic_font_size(font_size)
    end select
    
    ! Convert font size to em units (approximately 1:1 for standard fonts)
    em_dp = font_size
    
    ! Apply reasonable bounds
    if (em_dp <= 4.0 .or. em_dp > 200.0) em_dp = 16.0
end subroutine measure_linux_fonts

subroutine measure_windows_fonts(em_dp)
    ! Windows font measurement
    real, intent(out) :: em_dp
    
    ! Windows font measurement would use:
    ! - GDI GetTextMetrics() for system font metrics
    ! - DirectWrite IDWriteFont interfaces for advanced metrics
    ! - SystemParametersInfo(SPI_GETNONCLIENTMETRICS) for UI fonts
    
    ! Fallback to standard em size until Win32 APIs are integrated
    em_dp = 16.0
    
    call report_warning("fortui_platform_measurement", "measure_windows_fonts", &
                        "Windows font measurement not yet implemented - using default")
end subroutine measure_windows_fonts

subroutine measure_macos_fonts(em_dp)
    ! macOS font measurement
    real, intent(out) :: em_dp
    
    ! macOS font measurement would use Cocoa APIs:
    ! - NSFont.systemFontOfSize() for system font metrics
    ! - NSFontDescriptor for detailed font characteristics
    ! - CTFont Core Text APIs for advanced typography
    
    ! Fallback to standard em size until Cocoa APIs are integrated
    em_dp = 16.0
    
    call report_warning("fortui_platform_measurement", "measure_macos_fonts", &
                        "macOS font measurement not yet implemented - using default")
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
    ! Linux accessibility text scaling via desktop environment settings
    real, intent(out) :: text_scale
    
    character(len=256) :: de_name
    
    ! Try desktop environment accessibility settings
    call get_desktop_environment(de_name)
    
    select case (trim(de_name))
    case ("GNOME", "ubuntu:GNOME")
        call get_gnome_text_scaling(text_scale)
    case ("KDE", "plasma")
        call get_kde_text_scaling(text_scale)
    case ("XFCE")
        call get_xfce_text_scaling(text_scale)
    case default
        call get_generic_text_scaling(text_scale)
    end select
    
    ! Validate scaling factor
    if (text_scale <= 0.1 .or. text_scale > 10.0) text_scale = 1.0
end subroutine detect_linux_text_scaling

subroutine detect_windows_text_scaling(text_scale)
    ! Windows accessibility text scaling
    real, intent(out) :: text_scale
    
    ! Windows accessibility detection would use:
    ! - SystemParametersInfo(SPI_GETLOGFONT) for system font scaling
    ! - GetSystemMetrics(SM_CYFIXEDFRAME) for UI scaling
    ! - Registry queries for Ease of Access settings
    
    ! Fallback to no scaling until Win32 APIs are integrated
    text_scale = 1.0
    
    call report_warning("fortui_platform_measurement", "detect_windows_text_scaling", &
                        "Windows accessibility detection not yet implemented - using default")
end subroutine detect_windows_text_scaling

subroutine detect_macos_text_scaling(text_scale)
    ! macOS accessibility text scaling
    real, intent(out) :: text_scale
    
    ! macOS accessibility detection would use Cocoa APIs:
    ! - NSUserDefaults preferredContentSizeCategory for Dynamic Type
    ! - NSWorkspace accessibilityDisplayOptions for system preferences
    ! - UIContentSizeCategory scaling factors
    
    ! Fallback to no scaling until Cocoa APIs are integrated
    text_scale = 1.0
    
    call report_warning("fortui_platform_measurement", "detect_macos_text_scaling", &
                        "macOS accessibility detection not yet implemented - using default")
end subroutine detect_macos_text_scaling

! Context management functions

subroutine validate_context(ctx)
    ! Validate UI context values and provide corrections
    type(ui_context), intent(inout) :: ctx
    character(len=256) :: msg
    
    ! Validate DPI scale
    if (ctx%dpi_scale <= 0.0 .or. ctx%dpi_scale > 10.0) then
        write(msg, '(A,F6.2,A)') "Invalid dpi_scale ", ctx%dpi_scale, " correcting to 1.0"
        call report_warning("fortui_platform_measurement", "validate_context", trim(msg))
        ctx%dpi_scale = 1.0
    end if
    
    ! Validate em_dp
    if (ctx%em_dp <= 0.0 .or. ctx%em_dp > 200.0) then
        write(msg, '(A,F6.2,A)') "Invalid em_dp ", ctx%em_dp, " correcting to 16.0"
        call report_warning("fortui_platform_measurement", "validate_context", trim(msg))
        ctx%em_dp = 16.0
    end if
    
    ! Validate text_scale
    if (ctx%text_scale <= 0.0 .or. ctx%text_scale > 10.0) then
        write(msg, '(A,F6.2,A)') "Invalid text_scale ", ctx%text_scale, " correcting to 1.0"
        call report_warning("fortui_platform_measurement", "validate_context", trim(msg))
        ctx%text_scale = 1.0
    end if
    
    ! Validate cell dimensions
    if (ctx%cell_w_dp <= 0.0 .or. ctx%cell_w_dp > 100.0) then
        write(msg, '(A,F6.2,A)') "Invalid cell_w_dp ", ctx%cell_w_dp, " correcting to 8.0"
        call report_warning("fortui_platform_measurement", "validate_context", trim(msg))
        ctx%cell_w_dp = 8.0
    end if
    
    if (ctx%cell_h_dp <= 0.0 .or. ctx%cell_h_dp > 100.0) then
        write(msg, '(A,F6.2,A)') "Invalid cell_h_dp ", ctx%cell_h_dp, " correcting to 16.0"
        call report_warning("fortui_platform_measurement", "validate_context", trim(msg))
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
    
    ! Validate cell dimensions to prevent division by zero
    if (ctx%cell_w_dp <= 0.0) then
        cell_x = 0
    else
        cell_x = nint(dp_x / ctx%cell_w_dp)
    end if
    
    if (ctx%cell_h_dp <= 0.0) then
        cell_y = 0
    else
        cell_y = nint(dp_y / ctx%cell_h_dp)
    end if
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
    
    character(len=256) :: platform, de_name
    integer :: ios
    
    call detect_platform(platform)
    
    select case (trim(api_name))
    case ("x11")
        check_api_availability = check_x11_available()
    case ("wayland")
        check_api_availability = check_wayland_available()
    case ("gnome_settings")
        call get_desktop_environment(de_name)
        check_api_availability = (index(de_name, "GNOME") > 0)
    case ("kde_settings")
        call get_desktop_environment(de_name)
        check_api_availability = (index(de_name, "KDE") > 0 .or. &
                                  index(de_name, "plasma") > 0)
    case ("fontconfig")
        check_api_availability = check_fontconfig_available()
    case ("terminfo")
        check_api_availability = check_terminfo_available()
    case default
        check_api_availability = .false.
    end select
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

! Terminal font metric querying
subroutine query_terminal_font_metrics(cell_w_dp, cell_h_dp)
    ! Query terminal for actual font metrics using escape sequences
    real, intent(out) :: cell_w_dp, cell_h_dp
    
    character(len=256) :: term_var
    integer :: ios
    logical :: query_supported
    
    ! Initialize to invalid values to detect query failure
    cell_w_dp = -1.0
    cell_h_dp = -1.0
    
    ! Check if terminal supports font metric queries
    call get_environment_variable("TERM", term_var, status=ios)
    query_supported = .false.
    
    if (ios == 0) then
        ! Only attempt queries on terminals that support them
        select case (trim(term_var))
        case ("xterm", "xterm-256color", "screen", "tmux", "alacritty")
            query_supported = .true.
        end select
    end if
    
    if (query_supported) then
        ! Attempt terminal font metric query (simplified implementation)
        call attempt_font_metric_query(cell_w_dp, cell_h_dp)
    end if
end subroutine query_terminal_font_metrics

subroutine attempt_font_metric_query(cell_w_dp, cell_h_dp)
    ! Attempt to query font metrics (placeholder for actual implementation)
    real, intent(out) :: cell_w_dp, cell_h_dp
    
    ! This would send terminal escape sequences to query font metrics
    ! For now, return invalid values to indicate query not implemented
    cell_w_dp = -1.0
    cell_h_dp = -1.0
    
    ! Actual implementation would:
    ! 1. Send CSI escape sequences to query cell dimensions
    ! 2. Parse terminal response
    ! 3. Calculate pixel dimensions from character grid
end subroutine attempt_font_metric_query

! Desktop environment specific scaling detection
subroutine detect_gnome_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    character(len=256) :: scale_env
    integer :: ios
    real :: parsed_scale
    
    ! GNOME uses GDK_SCALE and scaling-factor settings
    call get_environment_variable("GDK_SCALE", scale_env, status=ios)
    if (ios == 0 .and. len_trim(scale_env) > 0) then
        read(scale_env, *, iostat=ios) parsed_scale
        if (ios == 0 .and. parsed_scale > 0.1 .and. parsed_scale <= 10.0) then
            dpi_scale = parsed_scale
            return
        end if
    end if
    
    ! Try to detect HiDPI via common scaling factors
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_gnome_scaling

subroutine detect_kde_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    character(len=256) :: scale_env
    integer :: ios
    real :: parsed_scale
    
    ! KDE uses QT_SCALE_FACTOR
    call get_environment_variable("QT_SCALE_FACTOR", scale_env, status=ios)
    if (ios == 0 .and. len_trim(scale_env) > 0) then
        read(scale_env, *, iostat=ios) parsed_scale
        if (ios == 0 .and. parsed_scale > 0.1 .and. parsed_scale <= 10.0) then
            dpi_scale = parsed_scale
            return
        end if
    end if
    
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_kde_scaling

subroutine detect_xfce_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    
    ! XFCE typically uses X11 DPI settings
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_xfce_scaling

subroutine detect_sway_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    
    ! Sway uses Wayland output scaling
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_sway_scaling

subroutine detect_generic_x11_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_generic_x11_scaling

subroutine detect_wayland_env_scaling(dpi_scale)
    real, intent(out) :: dpi_scale
    
    call detect_hidpi_environment(dpi_scale)
end subroutine detect_wayland_env_scaling

subroutine detect_hidpi_environment(dpi_scale)
    ! Detect HiDPI environment using heuristics
    real, intent(out) :: dpi_scale
    character(len=256) :: display_size
    integer :: ios
    
    ! Use heuristics to detect HiDPI displays
    ! Check for common HiDPI indicators
    call get_environment_variable("DISPLAY", display_size, status=ios)
    if (ios == 0) then
        ! Assume standard DPI for now
        dpi_scale = 1.0
    else
        dpi_scale = 1.0
    end if
end subroutine detect_hidpi_environment

! Font size detection functions
subroutine get_gnome_font_size(font_size)
    real, intent(out) :: font_size
    
    ! Try to get GNOME font settings (simplified approach)
    font_size = 16.0  ! Default GNOME font size
end subroutine get_gnome_font_size

subroutine get_kde_font_size(font_size)
    real, intent(out) :: font_size
    
    ! Try to get KDE font settings
    font_size = 16.0  ! Default KDE font size
end subroutine get_kde_font_size

subroutine get_xfce_font_size(font_size)
    real, intent(out) :: font_size
    
    ! Try to get XFCE font settings
    font_size = 16.0  ! Default XFCE font size
end subroutine get_xfce_font_size

subroutine get_generic_font_size(font_size)
    real, intent(out) :: font_size
    
    ! Generic font size detection
    font_size = 16.0  ! Conservative default
end subroutine get_generic_font_size

! Text scaling detection functions
subroutine get_gnome_text_scaling(text_scale)
    real, intent(out) :: text_scale
    
    ! Try to get GNOME accessibility text scaling
    text_scale = 1.0  ! Default - no scaling
end subroutine get_gnome_text_scaling

subroutine get_kde_text_scaling(text_scale)
    real, intent(out) :: text_scale
    
    ! Try to get KDE accessibility text scaling
    text_scale = 1.0  ! Default - no scaling
end subroutine get_kde_text_scaling

subroutine get_xfce_text_scaling(text_scale)
    real, intent(out) :: text_scale
    
    ! Try to get XFCE accessibility text scaling
    text_scale = 1.0  ! Default - no scaling
end subroutine get_xfce_text_scaling

subroutine get_generic_text_scaling(text_scale)
    real, intent(out) :: text_scale
    
    ! Generic text scaling detection
    text_scale = 1.0  ! Conservative default
end subroutine get_generic_text_scaling

! API availability checking functions
logical function check_x11_available()
    character(len=256) :: display_env
    integer :: ios
    
    call get_environment_variable("DISPLAY", display_env, status=ios)
    check_x11_available = (ios == 0 .and. len_trim(display_env) > 0)
end function check_x11_available

logical function check_wayland_available()
    character(len=256) :: wayland_env
    integer :: ios
    
    call get_environment_variable("WAYLAND_DISPLAY", wayland_env, status=ios)
    check_wayland_available = (ios == 0 .and. len_trim(wayland_env) > 0)
end function check_wayland_available

logical function check_fontconfig_available()
    ! Check if fontconfig is available (simplified)
    check_fontconfig_available = .false.  ! Conservative default
end function check_fontconfig_available

logical function check_terminfo_available()
    character(len=256) :: term_env
    integer :: ios
    
    call get_environment_variable("TERM", term_env, status=ios)
    check_terminfo_available = (ios == 0 .and. len_trim(term_env) > 0)
end function check_terminfo_available

end module fortui_platform_measurement