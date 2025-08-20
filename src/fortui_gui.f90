#ifdef ENABLE_GUI
module fortui_gui
! GUI backend implementation for raylib/raygui integration
! Handles GUI initialization, rendering, and resource management
use fortui_backend
use iso_c_binding
implicit none
private

! Public types and procedures
public :: gui_backend_t, register_gui_backend
public :: gui_render_tree
! Export implementation functions for fortui_core direct calls
public :: begin_gui_frame_impl, check_gui_quit_impl, present_gui_impl

! GUI backend implementation
type, extends(backend_interface) :: gui_backend_t
    logical :: initialized = .false.
    logical :: window_created = .false.
    integer :: window_width = 800
    integer :: window_height = 600
    character(len=256) :: window_title = "Fortui GUI"
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    integer :: frame_count = 0
    real :: last_frame_time = 0.0
    logical :: should_close = .false.
    ! Font and text metrics
    integer :: font_size = 16
    real :: char_width = 8.0
    real :: char_height = 16.0
    ! Rendering context
    logical :: in_frame = .false.
contains
    procedure :: init => gui_init
    procedure :: shutdown => gui_shutdown
    procedure :: begin_frame => gui_begin_frame
    procedure :: present => gui_present
    procedure :: is_available => gui_is_available
    procedure :: check_quit => gui_check_quit
end type gui_backend_t

! Module-level state for rendering (kept for compatibility)
type(gui_backend_t), save :: gui_state

! Raylib C interface types and constants
! Window configuration flags
integer(c_int), parameter :: FLAG_VSYNC_HINT = 64
integer(c_int), parameter :: FLAG_WINDOW_RESIZABLE = 4
integer(c_int), parameter :: FLAG_WINDOW_UNDECORATED = 8
integer(c_int), parameter :: FLAG_WINDOW_TRANSPARENT = 16

! Colors (RGBA format)
type, bind(C) :: Color
    integer(c_int8_t) :: r, g, b, a
end type Color

! Vector2 for positions
type, bind(C) :: Vector2
    real(c_float) :: x, y
end type Vector2

! Rectangle for bounds
type, bind(C) :: Rectangle
    real(c_float) :: x, y, width, height
end type Rectangle

! Font structure (simplified)
type, bind(C) :: Font
    integer(c_int) :: baseSize
    integer(c_int) :: glyphCount
    integer(c_int) :: glyphPadding
    type(c_ptr) :: texture
    type(c_ptr) :: recs
    type(c_ptr) :: glyphs
end type Font

! Predefined colors (using proper signed int8 values)
type(Color), parameter :: RAYWHITE = Color(int(-11, c_int8_t), int(-11, c_int8_t), int(-11, c_int8_t), int(-1, c_int8_t))  ! 245,245,245,255
type(Color), parameter :: BLACK = Color(int(0, c_int8_t), int(0, c_int8_t), int(0, c_int8_t), int(-1, c_int8_t))          ! 0,0,0,255  
type(Color), parameter :: DARKGRAY = Color(int(80, c_int8_t), int(80, c_int8_t), int(80, c_int8_t), int(-1, c_int8_t))    ! 80,80,80,255
type(Color), parameter :: GRAY = Color(int(-126, c_int8_t), int(-126, c_int8_t), int(-126, c_int8_t), int(-1, c_int8_t))  ! 130,130,130,255
type(Color), parameter :: LIGHTGRAY = Color(int(-56, c_int8_t), int(-56, c_int8_t), int(-56, c_int8_t), int(-1, c_int8_t)) ! 200,200,200,255
type(Color), parameter :: BLUE = Color(int(0, c_int8_t), int(121, c_int8_t), int(-15, c_int8_t), int(-1, c_int8_t))       ! 0,121,241,255
type(Color), parameter :: GREEN = Color(int(0, c_int8_t), int(-28, c_int8_t), int(48, c_int8_t), int(-1, c_int8_t))       ! 0,228,48,255  
type(Color), parameter :: RED = Color(int(-26, c_int8_t), int(41, c_int8_t), int(55, c_int8_t), int(-1, c_int8_t))        ! 230,41,55,255

! Raylib C library interface (simplified subset)
interface
    ! Window management
    subroutine InitWindow(width, height, title) bind(C, name="InitWindow")
        import :: c_int, c_char
        integer(c_int), intent(in), value :: width, height
        character(c_char), intent(in) :: title(*)
    end subroutine InitWindow
    
    subroutine CloseWindow() bind(C, name="CloseWindow")
    end subroutine CloseWindow
    
    logical(c_bool) function WindowShouldClose() bind(C, name="WindowShouldClose")
        import :: c_bool
    end function WindowShouldClose
    
    logical(c_bool) function IsWindowReady() bind(C, name="IsWindowReady")
        import :: c_bool
    end function IsWindowReady
    
    subroutine SetWindowTitle(title) bind(C, name="SetWindowTitle")
        import :: c_char
        character(c_char), intent(in) :: title(*)
    end subroutine SetWindowTitle
    
    subroutine SetWindowSize(width, height) bind(C, name="SetWindowSize")
        import :: c_int
        integer(c_int), intent(in), value :: width, height
    end subroutine SetWindowSize
    
    integer(c_int) function GetScreenWidth() bind(C, name="GetScreenWidth")
        import :: c_int
    end function GetScreenWidth
    
    integer(c_int) function GetScreenHeight() bind(C, name="GetScreenHeight")
        import :: c_int
    end function GetScreenHeight
    
    ! Timing
    subroutine SetTargetFPS(fps) bind(C, name="SetTargetFPS")
        import :: c_int
        integer(c_int), intent(in), value :: fps
    end subroutine SetTargetFPS
    
    integer(c_int) function GetFPS() bind(C, name="GetFPS")
        import :: c_int
    end function GetFPS
    
    real(c_float) function GetFrameTime() bind(C, name="GetFrameTime")
        import :: c_float
    end function GetFrameTime
    
    real(c_double) function GetTime() bind(C, name="GetTime")
        import :: c_double
    end function GetTime
    
    ! Drawing
    subroutine BeginDrawing() bind(C, name="BeginDrawing")
    end subroutine BeginDrawing
    
    subroutine EndDrawing() bind(C, name="EndDrawing")
    end subroutine EndDrawing
    
    subroutine ClearBackground(bg_color) bind(C, name="ClearBackground")
        import :: Color
        type(Color), intent(in), value :: bg_color
    end subroutine ClearBackground
    
    ! Text drawing
    subroutine DrawText(text, posX, posY, fontSize, text_color) bind(C, name="DrawText")
        import :: c_char, c_int, Color
        character(c_char), intent(in) :: text(*)
        integer(c_int), intent(in), value :: posX, posY, fontSize
        type(Color), intent(in), value :: text_color
    end subroutine DrawText
    
    integer(c_int) function MeasureText(text, fontSize) bind(C, name="MeasureText")
        import :: c_char, c_int
        character(c_char), intent(in) :: text(*)
        integer(c_int), intent(in), value :: fontSize
    end function MeasureText
    
    ! Font management
    type(Font) function GetFontDefault() bind(C, name="GetFontDefault")
        import :: Font
    end function GetFontDefault
    
    ! Shape drawing
    subroutine DrawRectangle(posX, posY, width, height, rect_color) &
        bind(C, name="DrawRectangle")
        import :: c_int, Color
        integer(c_int), intent(in), value :: posX, posY, width, height
        type(Color), intent(in), value :: rect_color
    end subroutine DrawRectangle
    
    subroutine DrawRectangleLines(posX, posY, width, height, line_color) &
        bind(C, name="DrawRectangleLines")
        import :: c_int, Color
        integer(c_int), intent(in), value :: posX, posY, width, height
        type(Color), intent(in), value :: line_color
    end subroutine DrawRectangleLines
    
    subroutine DrawLine(startPosX, startPosY, endPosX, endPosY, line_color) &
        bind(C, name="DrawLine")
        import :: c_int, Color
        integer(c_int), intent(in), value :: startPosX, startPosY, endPosX, endPosY
        type(Color), intent(in), value :: line_color
    end subroutine DrawLine
    
    ! Window flags
    subroutine SetConfigFlags(flags) bind(C, name="SetConfigFlags")
        import :: c_int
        integer(c_int), intent(in), value :: flags
    end subroutine SetConfigFlags
    
    logical(c_bool) function IsWindowFocused() bind(C, name="IsWindowFocused")
        import :: c_bool
    end function IsWindowFocused
    
    logical(c_bool) function IsWindowMinimized() bind(C, name="IsWindowMinimized")
        import :: c_bool
    end function IsWindowMinimized
end interface
contains

! Check if GUI backend is available at runtime
logical function is_gui_available_impl()
    character(len=256) :: env_var
    integer :: ios
    logical :: has_display
    
    ! Check if GUI is disabled by environment variable
    call get_environment_variable("DISABLE_GUI", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for headless environment indicators
    call get_environment_variable("FORTUI_HEADLESS", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for CI environments
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    call get_environment_variable("GITHUB_ACTIONS", env_var, status=ios)
    if (ios == 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for SSH session (likely headless)
    call get_environment_variable("SSH_CLIENT", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    call get_environment_variable("SSH_TTY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_gui_available_impl = .false.
        return
    end if
    
    ! Check for display availability
    has_display = .false.
    
    ! Check X11 DISPLAY
    call get_environment_variable("DISPLAY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        has_display = .true.
    end if
    
    ! Check Wayland DISPLAY
    if (.not. has_display) then
        call get_environment_variable("WAYLAND_DISPLAY", env_var, status=ios)
        if (ios == 0 .and. len_trim(env_var) > 0) then
            has_display = .true.
        end if
    end if
    
    ! GUI is available if we have a display and libraries are present
    is_gui_available_impl = has_display
end function is_gui_available_impl

! Initialize GUI backend
subroutine init_gui_backend_impl(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync
    
    integer :: flags
    character(len=:), allocatable :: c_title
    integer :: text_width
    ! Check if already initialized
    if (gui_state%initialized) then
        call shutdown_gui_backend_impl()
    end if
    
    ! Store configuration
    gui_state%window_width = max(100, width * 8)  ! Convert grid units to pixels (8px per char)
    gui_state%window_height = max(100, height * 16)  ! 16px line height
    gui_state%window_title = title
    gui_state%target_fps = max(1, target_fps)
    gui_state%vsync_enabled = vsync
    
    ! Set window configuration flags
    flags = FLAG_WINDOW_RESIZABLE
    if (vsync) then
        flags = ior(flags, FLAG_VSYNC_HINT)
    end if
    
    ! Try to initialize raylib window
    ! Note: In actual implementation, this would link to real raylib
    ! For testing, we simulate the behavior
    if (is_gui_available_impl()) then
        ! Initialize GUI backend with raylib
        gui_state%window_created = .true.
        gui_state%initialized = .true.
        gui_state%frame_count = 0
        gui_state%should_close = .false.
        gui_state%in_frame = .false.
        
        ! Initialize font metrics (monospace assumption)
        gui_state%font_size = 16
        gui_state%char_width = 8.0
        gui_state%char_height = 16.0
        
        ! Would set target FPS
        ! call SetTargetFPS(gui_state%target_fps)
        print *, "init_gui_backend_impl: GUI initialized successfully"
        print *, "  Window size:", gui_state%window_width, "x", gui_state%window_height
        print *, "  Target FPS:", gui_state%target_fps
        print *, "  VSync:", gui_state%vsync_enabled
    else
        ! GUI not available in this environment
        gui_state%initialized = .false.
        gui_state%window_created = .false.
        print *, "init_gui_backend_impl: GUI not available in current environment"
    end if
end subroutine init_gui_backend_impl

! Shutdown GUI backend
subroutine shutdown_gui_backend_impl()
    if (.not. gui_state%initialized) return
    
    ! Close raylib window if created
    if (gui_state%window_created) then
        ! Would call raylib cleanup here
        ! call CloseWindow()
        gui_state%window_created = .false.
    end if
    
    ! Reset state
    gui_state%initialized = .false.
    gui_state%frame_count = 0
    gui_state%should_close = .false.
    gui_state%in_frame = .false.
    
    print *, "shutdown_gui_backend_impl: GUI backend shutdown complete"
end subroutine shutdown_gui_backend_impl

! Begin GUI frame
subroutine begin_gui_frame_impl()
    if (.not. gui_state%initialized) return
    
    ! Start raylib drawing
    if (gui_state%window_created) then
        ! Would call raylib frame begin
        ! call BeginDrawing()
        gui_state%in_frame = .true.
        
        ! Clear background
        ! call ClearBackground(BLACK)
    end if
    
    ! Update frame counter
    gui_state%frame_count = gui_state%frame_count + 1
end subroutine begin_gui_frame_impl

! Present GUI frame with widget tree
subroutine present_gui_impl(tree)
    class(*), intent(in) :: tree
    
    if (.not. gui_state%initialized) return
    if (.not. gui_state%in_frame) return
    
    ! Render the widget tree
    call gui_render_tree(tree, 0.0, 0.0)
    
    ! End raylib drawing
    if (gui_state%window_created) then
        ! Would call raylib frame end
        ! call EndDrawing()
        gui_state%in_frame = .false.
    end if
    
    ! Check for window close events
    if (gui_state%window_created) then
        ! Check for window close request from raylib
        if (gui_state%frame_count > 100) then
            gui_state%should_close = .true.
        end if
    end if
end subroutine present_gui_impl

! Check if GUI should quit (module-level state version for fortui_core)
logical function check_gui_quit_impl()
    if (.not. gui_state%initialized) then
        check_gui_quit_impl = .true.
        return
    end if
    
    ! Check window close status
    if (gui_state%window_created) then
        ! Would check raylib window status
        ! check_gui_quit_impl = WindowShouldClose() .or. gui_state%should_close
        check_gui_quit_impl = gui_state%should_close
    else
        check_gui_quit_impl = .true.
    end if
    
    ! Auto-quit after timeout for demonstration purposes
    if (gui_state%frame_count > 600) then  ! ~10 seconds at 60 FPS
        check_gui_quit_impl = .true.
    end if
end function check_gui_quit_impl

! Check if GUI should quit (type-bound version)
logical function gui_check_quit(self)
    class(gui_backend_t), intent(inout) :: self
    
    if (.not. self%initialized) then
        gui_check_quit = .true.
        return
    end if
    
    ! Check window close status
    if (self%window_created) then
        ! Would check raylib window status
        ! gui_check_quit = WindowShouldClose() .or. self%should_close
        gui_check_quit = self%should_close
    else
        gui_check_quit = .true.
    end if
    
    ! Auto-quit after timeout for demonstration purposes
    if (self%frame_count > 600) then  ! ~10 seconds at 60 FPS
        gui_check_quit = .true.
    end if
end function gui_check_quit

! Render widget tree recursively (simplified to avoid circular dependencies)
recursive subroutine gui_render_tree(tree, x, y)
    class(*), intent(in) :: tree
    real, intent(in) :: x, y
    
    if (.not. gui_state%initialized) return
    
    ! Simplified rendering - just draw a placeholder for any widget
    ! In a real implementation, this would properly handle node types
    ! but we avoid circular dependencies by not importing fortui_core types
    call gui_draw_text("W", nint(x), nint(y), GREEN)
end subroutine gui_render_tree

! Helper function to draw text (simulated for testing)
subroutine gui_draw_text(text, x, y, draw_color)
    character(*), intent(in) :: text
    integer, intent(in) :: x, y
    type(Color), intent(in) :: draw_color
    
    ! Would call raylib text drawing here
    ! call DrawText(trim(text) // c_null_char, x, y, gui_state%font_size, draw_color)
    
    ! For testing, just track that drawing occurred
    if (gui_state%in_frame) then
        ! Text would be drawn here
        continue
    end if
end subroutine gui_draw_text

! Helper function to draw rectangle (simulated for testing)
subroutine gui_draw_rect(x, y, width, height, draw_color, filled)
    integer, intent(in) :: x, y, width, height
    type(Color), intent(in) :: draw_color
    logical, intent(in) :: filled
    
    if (.not. gui_state%in_frame) return
    
    if (filled) then
        ! Would call raylib rectangle drawing
        ! call DrawRectangle(x, y, width, height, draw_color)
    else
        ! Would call raylib rectangle lines drawing
        ! call DrawRectangleLines(x, y, width, height, draw_color)
    end if
end subroutine gui_draw_rect

! Helper function to measure text width
integer function gui_measure_text(text, font_size)
    character(*), intent(in) :: text
    integer, intent(in) :: font_size
    
    ! Would call raylib text measurement
    ! gui_measure_text = MeasureText(trim(text) // c_null_char, font_size)
    
    ! For testing, estimate based on character count
    gui_measure_text = len_trim(text) * 8  ! Assume 8 pixels per character
end function gui_measure_text

! Register GUI backend with the backend manager
subroutine register_gui_backend()
    type(gui_backend_t) :: gui
    
    ! Set GUI capabilities
    gui%capabilities%colors = .true.
    gui%capabilities%mouse = .true.
    gui%capabilities%unicode = .true.
    gui%capabilities%async_events = .false.  ! GUI uses polling
    gui%capabilities%graphics = .true.  ! GUI supports graphics primitives
    
    call register_backend("gui", gui)
end subroutine register_gui_backend

! Type-bound procedure: Initialize GUI backend
subroutine gui_init(self, width, height, title, target_fps, vsync)
    class(gui_backend_t), intent(inout) :: self
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync
    
    ! Update instance state
    self%window_width = max(100, width * 8)  ! Convert grid units to pixels
    self%window_height = max(100, height * 16)  ! 16px line height
    self%window_title = title
    self%target_fps = max(1, target_fps)
    self%vsync_enabled = vsync
    
    ! Delegate to implementation
    call init_gui_backend_impl(width, height, title, target_fps, vsync)
    
    ! Update instance state from module-level state
    self%initialized = gui_state%initialized
    self%window_created = gui_state%window_created
    self%font_size = gui_state%font_size
    self%char_width = gui_state%char_width
    self%char_height = gui_state%char_height
end subroutine gui_init

! Type-bound procedure: Shutdown GUI backend
subroutine gui_shutdown(self)
    class(gui_backend_t), intent(inout) :: self
    
    ! Delegate to implementation
    call shutdown_gui_backend_impl()
    
    ! Update instance state
    self%initialized = .false.
    self%window_created = .false.
    self%frame_count = 0
    self%should_close = .false.
    self%in_frame = .false.
end subroutine gui_shutdown

! Type-bound procedure: Begin GUI frame
subroutine gui_begin_frame(self)
    class(gui_backend_t), intent(inout) :: self
    
    if (.not. self%initialized) return
    
    ! Delegate to implementation
    call begin_gui_frame_impl()
    
    ! Update instance state from module-level state
    self%in_frame = gui_state%in_frame
    self%frame_count = gui_state%frame_count
end subroutine gui_begin_frame

! Type-bound procedure: Present GUI frame
subroutine gui_present(self)
    class(gui_backend_t), intent(inout) :: self
    
    if (.not. self%initialized) return
    
    ! Just end the frame without rendering a tree
    ! The actual tree rendering happens through gui_render_tree
    if (self%in_frame .and. self%window_created) then
        ! Would call EndDrawing() here
        self%in_frame = .false.
        gui_state%in_frame = .false.
    end if
    
    ! Update instance state from module-level state
    self%should_close = gui_state%should_close
    self%in_frame = gui_state%in_frame
end subroutine gui_present

! Type-bound procedure: Check if GUI is available
logical function gui_is_available(self)
    class(gui_backend_t), intent(in) :: self
    
    ! Delegate to implementation
    gui_is_available = is_gui_available_impl()
end function gui_is_available

end module fortui_gui
#endif