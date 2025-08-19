module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
use iso_c_binding
implicit none
private

! Layout dimension constants
real, parameter :: DEFAULT_ROW_HEIGHT_DP = 32.0  ! Basic row height for vertical layout
real, parameter :: DEFAULT_COLUMN_WIDTH_DP = 64.0  ! Basic column width for horizontal layout

! Public types  
public :: ui_element, node, view

! Public procedures
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy
! Layout constructors
public :: column, row

! Internal state management
type :: ui_state_t
    logical :: initialized = .false.
    character(len=32) :: active_backend = ""
    integer :: window_width = 0
    integer :: window_height = 0
    character(len=256) :: window_title = ""
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    character(len=32) :: idle_mode = "adaptive"
    integer :: idle_fps = 12
    logical :: should_quit = .false.
end type ui_state_t

type(ui_state_t), save :: ui_state

! Abstract UI element hierarchy for tree construction
type, abstract :: ui_element
    ! Abstract base for all UI elements (nodes, widgets, layouts)
end type ui_element

! Core UI tree building block - extensible for widgets
type, extends(ui_element) :: node
    ! Layout metadata
    character(len=32) :: layout_type = "none"    ! "column", "row", "none"
    real :: gap_dp = 0.0                         ! Converted gap in dp units
    ! Children array for tree composition
    type(node), allocatable :: children(:)
    ! Backend-agnostic design (identical behavior regardless of compilation flags)
contains
    ! Assignment operator overload for proper memory management
    procedure :: assign_node
    generic :: assignment(=) => assign_node
end type node

! Pan/zoom state for plot areas with default values from DESIGN.md
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis
    real :: scale_y = 1.0  ! Zoom factor Y-axis
    real :: off_x = 0.0    ! Pan offset X-axis
    real :: off_y = 0.0    ! Pan offset Y-axis
end type view

! Termbox2 C library interface types and constants
! Event structure for C interoperability
type, bind(C) :: tb_event
    integer(c_int) :: type
    integer(c_int) :: mod
    integer(c_int) :: key
    integer(c_int32_t) :: ch
    integer(c_int) :: w, h
    integer(c_int) :: x, y
end type tb_event

! Cell structure for terminal rendering
type, bind(C) :: tb_cell
    integer(c_int32_t) :: ch
    integer(c_int) :: fg
    integer(c_int) :: bg
end type tb_cell

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_KEY_CTRL_D = 4
integer, parameter :: TB_KEY_CTRL_Z = 26
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3

! TUI backend state
type :: tui_state_t
    logical :: initialized = .false.
    integer :: terminal_width = 0
    integer :: terminal_height = 0
    type(tb_cell), allocatable :: front_buffer(:, :)
    type(tb_cell), allocatable :: back_buffer(:, :)
    integer, allocatable :: line_hashes(:)  ! For diff optimization
    logical :: resize_pending = .false.
    logical :: quit_requested = .false.
end type tui_state_t

type(tui_state_t), save :: tui_state

! Mock termbox2 state for testing without actual library
type :: mock_terminal_state_t
    logical :: initialized = .false.
    integer :: width = 80
    integer :: height = 24
    integer :: event_count = 0
end type mock_terminal_state_t

type(mock_terminal_state_t), save :: mock_terminal

contains

! Lifecycle & pacing procedures
subroutine ui_init(backend, width, height, title, target_fps, vsync)
    character(*), intent(in) :: backend        ! "tui" | "gui" | "auto"
    integer,      intent(in) :: width, height  ! grid units (gu)
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
    logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
    
    character(len=32) :: resolved_backend
    character(len=256) :: display_var, ssh_client, ci_var
    integer :: ios
    
    ! Reset state if reinitializing
    if (ui_state%initialized) then
        call ui_shutdown()
    end if
    
    ! Validate and resolve backend
    resolved_backend = resolve_backend(backend)
    
    ! Validate parameters
    if (width <= 0 .or. height <= 0) then
        print *, "ui_init: Warning - Invalid dimensions (", width, "x", height, "), using defaults"
        ui_state%window_width = max(1, width)
        ui_state%window_height = max(1, height)
    else
        ui_state%window_width = width
        ui_state%window_height = height
    end if
    
    ! Store configuration
    ui_state%active_backend = resolved_backend
    ui_state%window_title = title
    ui_state%target_fps = 60
    if (present(target_fps)) ui_state%target_fps = max(1, target_fps)
    ui_state%vsync_enabled = .true.
    if (present(vsync)) ui_state%vsync_enabled = vsync
    
    ! Initialize backend-specific resources
    select case (trim(resolved_backend))
    case ("tui")
        call init_tui_backend()
    case ("gui")
        call init_gui_backend()
    case default
        print *, "ui_init: Error - Unsupported backend: ", trim(resolved_backend)
        print *, "ui_init: Falling back to TUI backend"
        ui_state%active_backend = "tui"
        call init_tui_backend()
    end select
    
    ui_state%initialized = .true.
    ui_state%should_quit = .false.
    
    ! Debug output for tests
    print *, "ui_init: backend=", trim(ui_state%active_backend), " size=", &
             ui_state%window_width, "x", ui_state%window_height
end subroutine ui_init

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
    character(*), intent(in) :: mode                   ! "steady" | "adaptive"
    integer,      intent(in), optional :: idle_fps     ! e.g., 12
    
    ! Validate mode parameter
    select case (trim(mode))
    case ("steady", "adaptive")
        ui_state%idle_mode = trim(mode)
    case default
        print *, "ui_set_idle_policy: Warning - Invalid mode '", trim(mode), "', using 'adaptive'"
        ui_state%idle_mode = "adaptive"
    end select
    
    ! Set idle FPS if provided (only meaningful for adaptive mode)
    if (present(idle_fps)) then
        ui_state%idle_fps = max(1, idle_fps)
    end if
    
    ! Apply policy for GUI backend only
#ifdef ENABLE_GUI
    if (trim(ui_state%active_backend) == "gui") then
        print *, "ui_set_idle_policy: mode=", trim(ui_state%idle_mode)
        if (present(idle_fps)) print *, "  idle_fps=", ui_state%idle_fps
    end if
#endif
end subroutine ui_set_idle_policy

subroutine ui_frame_begin(timeout_ms)
    integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
    
    if (.not. ui_state%initialized) then
        print *, "ui_frame_begin: Error - UI not initialized. Call ui_init first."
        return
    end if
    
    ! Backend-specific frame preparation
    select case (trim(ui_state%active_backend))
    case ("tui")
        ! TUI: Event-driven with timeout
        call begin_tui_frame(timeout_ms)
    case ("gui")
        ! GUI: Frame timing controlled by target_fps, timeout ignored
        call begin_gui_frame()
    end select
end subroutine ui_frame_begin

subroutine ui_present(tree)
    class(node), intent(in) :: tree
    
    if (.not. ui_state%initialized) then
        print *, "ui_present: Error - UI not initialized. Call ui_init first."
        return
    end if
    
    ! Backend-specific presentation
    select case (trim(ui_state%active_backend))
    case ("tui")
        call present_tui(tree)
    case ("gui")
        call present_gui(tree)
    end select
end subroutine ui_present

logical function ui_should_close()
    ! Check if application should terminate
    ! Returns true for quit events (ESC key, window close, etc.)
    
    if (.not. ui_state%initialized) then
        ui_should_close = .true.  ! Force quit if not initialized
        return
    end if
    
    ! Check backend-specific quit conditions
    select case (trim(ui_state%active_backend))
    case ("tui")
        ui_should_close = check_tui_quit() .or. ui_state%should_quit
    case ("gui")
        ui_should_close = check_gui_quit() .or. ui_state%should_quit
    case default
        ui_should_close = .true.  ! Unknown backend, force quit
    end select
end function ui_should_close

subroutine ui_shutdown()
    ! Clean shutdown of UI backend
    
    if (.not. ui_state%initialized) then
        ! Safe to call multiple times
        return
    end if
    
    ! Backend-specific cleanup
    select case (trim(ui_state%active_backend))
    case ("tui")
        call shutdown_tui_backend()
    case ("gui")
        call shutdown_gui_backend()
    end select
    
    ! Reset all state
    ui_state%initialized = .false.
    ui_state%active_backend = ""
    ui_state%window_width = 0
    ui_state%window_height = 0
    ui_state%window_title = ""
    ui_state%target_fps = 60
    ui_state%vsync_enabled = .true.
    ui_state%idle_mode = "adaptive"
    ui_state%idle_fps = 12
    ui_state%should_quit = .false.
    
    print *, "ui_shutdown: cleaning up backend resources"
end subroutine ui_shutdown

! Internal backend resolution and management functions

function resolve_backend(requested) result(backend)
    character(*), intent(in) :: requested
    character(len=32) :: backend
    character(len=256) :: env_var
    integer :: ios
    logical :: gui_available
    
    ! Check for environment variable override
    call get_environment_variable("FORTUI_BACKEND", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        backend = trim(env_var)
        return
    end if
    
    ! Handle case sensitivity
    select case (trim(adjustl(requested)))
    case ("TUI", "tui", "terminal", "console")
        backend = "tui"
    case ("GUI", "gui", "window", "graphics")
        backend = "gui"
    case ("auto", "AUTO", "")
        ! Auto-detect best available backend
        if (is_gui_available() .and. .not. is_headless_environment()) then
            backend = "gui"
        else
            backend = "tui"
        end if
    case default
        ! Invalid backend - fall back to TUI
        print *, "resolve_backend: Warning - Unknown backend '", trim(requested), "', using TUI"
        backend = "tui"
    end select
    
    ! Validate that selected backend is actually available
    if (trim(backend) == "gui" .and. .not. is_gui_available()) then
        print *, "resolve_backend: GUI backend not available, falling back to TUI"
        backend = "tui"
    end if
end function resolve_backend

logical function is_gui_available()
    ! Check if GUI backend can be initialized
#ifdef ENABLE_GUI
    character(len=256) :: disable_gui
    integer :: ios
    
    ! Check DISABLE_GUI environment variable
    call get_environment_variable("DISABLE_GUI", disable_gui, status=ios)
    if (ios == 0 .and. trim(disable_gui) == "1") then
        is_gui_available = .false.
        return
    end if
    
    ! TODO: Add runtime raylib initialization check when backend modules available
    is_gui_available = .true.
#else
    is_gui_available = .false.
#endif
end function is_gui_available

logical function is_headless_environment()
    ! Detect headless environment (no display available)
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for explicit headless flag
    call get_environment_variable("FORTUI_HEADLESS", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for CI environment
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("GITHUB_ACTIONS", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for SSH session
    call get_environment_variable("SSH_CLIENT", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("SSH_TTY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for display availability
    call get_environment_variable("DISPLAY", env_var, status=ios)
    if (ios /= 0 .or. len_trim(env_var) == 0) then
        ! No X11 DISPLAY, check for Wayland
        call get_environment_variable("WAYLAND_DISPLAY", env_var, status=ios)
        if (ios /= 0 .or. len_trim(env_var) == 0) then
            is_headless_environment = .true.
            return
        end if
    end if
    
    is_headless_environment = .false.
end function is_headless_environment

! Backend-specific initialization stubs (will be implemented when backend modules available)
subroutine init_tui_backend()
    ! Initialize TUI backend with termbox2
    use fortui_units, only: ui_get_context, ui_set_context, ui_context
    integer(c_int) :: init_result
    type(ui_context) :: ctx
    
    ! Initialize mock termbox2 for testing
    init_result = mock_tb_init()
    if (init_result /= 0) then
        print *, "init_tui_backend: Warning - termbox2 initialization failed with code:", init_result
        print *, "init_tui_backend: Continuing with mock terminal for testing"
        
        ! Set up mock terminal dimensions for testing
        tui_state%terminal_width = max(1, ui_state%window_width)
        tui_state%terminal_height = max(1, ui_state%window_height)
    else
        ! Get actual terminal dimensions from mock termbox2
        tui_state%terminal_width = mock_tb_width()
        tui_state%terminal_height = mock_tb_height()
        
        ! Clear the terminal
        call mock_tb_clear()
    end if
    
    ! Validate terminal dimensions
    if (tui_state%terminal_width <= 0 .or. tui_state%terminal_height <= 0) then
        print *, "init_tui_backend: Warning - Invalid terminal dimensions detected"
        tui_state%terminal_width = max(80, tui_state%terminal_width)
        tui_state%terminal_height = max(24, tui_state%terminal_height)
    end if
    
    ! Initialize cell buffers for front/back buffer system
    call allocate_cell_buffers()
    
    ! Update UI context with terminal cell dimensions
    call ui_get_context(ctx)
    ctx%cell_w_dp = 8.0   ! Standard terminal cell width in dp
    ctx%cell_h_dp = 16.0  ! Standard terminal cell height in dp
    ctx%dpi_scale = 1.0   ! TUI always uses 1.0 DPI scale
    call ui_set_context(ctx)
    
    tui_state%initialized = .true.
    tui_state%resize_pending = .false.
    tui_state%quit_requested = .false.
    
    print *, "init_tui_backend: TUI initialized, size=", &
             tui_state%terminal_width, "x", tui_state%terminal_height
end subroutine init_tui_backend

subroutine init_gui_backend()
    ! Initialize GUI backend
#ifdef ENABLE_GUI
    ! TODO: Initialize raylib when GUI module available
#endif
end subroutine init_gui_backend

! TUI backend helper functions
subroutine allocate_cell_buffers()
    ! Allocate front and back cell buffers for diff-based rendering
    integer :: width, height
    
    width = tui_state%terminal_width
    height = tui_state%terminal_height
    
    ! Deallocate existing buffers if present
    if (allocated(tui_state%front_buffer)) deallocate(tui_state%front_buffer)
    if (allocated(tui_state%back_buffer)) deallocate(tui_state%back_buffer)
    if (allocated(tui_state%line_hashes)) deallocate(tui_state%line_hashes)
    
    ! Allocate new buffers
    allocate(tui_state%front_buffer(width, height))
    allocate(tui_state%back_buffer(width, height))
    allocate(tui_state%line_hashes(height))
    
    ! Initialize buffers with default values
    call clear_cell_buffers()
end subroutine allocate_cell_buffers

subroutine clear_cell_buffers()
    ! Clear both front and back buffers
    integer :: x, y
    type(tb_cell) :: empty_cell
    
    ! Initialize empty cell
    empty_cell%ch = int(ichar(' '), c_int32_t)
    empty_cell%fg = 0
    empty_cell%bg = 0
    
    ! Clear both buffers
    do y = 1, tui_state%terminal_height
        do x = 1, tui_state%terminal_width
            tui_state%front_buffer(x, y) = empty_cell
            tui_state%back_buffer(x, y) = empty_cell
        end do
    end do
    
    ! Clear line hashes
    tui_state%line_hashes = 0
end subroutine clear_cell_buffers

integer function calculate_line_hash(line_cells) result(hash)
    ! Calculate hash for a line of cells for diff optimization
    type(tb_cell), intent(in) :: line_cells(:)
    integer :: i
    
    hash = 0
    do i = 1, size(line_cells)
        ! Simple hash combining character and colors
        hash = hash + line_cells(i)%ch + line_cells(i)%fg * 31 + line_cells(i)%bg * 97
        hash = mod(hash, 2147483647)  ! Keep within integer range
    end do
end function calculate_line_hash

subroutine dp_to_cell_coords(dp_x, dp_y, cell_x, cell_y)
    ! Convert dp coordinates to cell coordinates with snapping
    use fortui_units, only: ui_get_context, ui_context
    real, intent(in) :: dp_x, dp_y
    integer, intent(out) :: cell_x, cell_y
    type(ui_context) :: ctx
    
    call ui_get_context(ctx)
    
    ! Convert to cell coordinates and snap to cell boundaries
    cell_x = nint(dp_x / ctx%cell_w_dp)
    cell_y = nint(dp_y / ctx%cell_h_dp)
    
    ! Clamp to terminal boundaries
    cell_x = max(0, min(cell_x, tui_state%terminal_width - 1))
    cell_y = max(0, min(cell_y, tui_state%terminal_height - 1))
end subroutine dp_to_cell_coords

! Backend-specific frame management stubs
subroutine begin_tui_frame(timeout_ms)
    integer, intent(in) :: timeout_ms
    
    if (.not. tui_state%initialized) return
    
    ! Event polling with timeout for TUI responsiveness
    call poll_tui_events(timeout_ms)
    
    ! Handle any pending resize events
    if (tui_state%resize_pending) then
        call handle_terminal_resize()
        tui_state%resize_pending = .false.
    end if
    
    ! Clear back buffer for new frame
    call clear_back_buffer()
end subroutine begin_tui_frame

subroutine poll_tui_events(timeout_ms)
    ! Poll events with timeout handling for responsive TUI
    integer, intent(in) :: timeout_ms
    type(tb_event) :: event
    integer(c_int) :: event_result
    integer :: safe_timeout
    
    ! Validate timeout parameter
    safe_timeout = max(0, min(timeout_ms, 5000))  ! Cap at 5 seconds for safety
    
    ! Poll for events with timeout
    event_result = mock_tb_peek_event(event, int(safe_timeout, c_int))
    
    if (event_result > 0) then
        ! Process the event
        call process_tui_event(event)
    end if
    
    ! Coalesce rapid events by checking for more events with zero timeout
    do
        event_result = mock_tb_peek_event(event, 0_c_int)
        if (event_result <= 0) exit
        call process_tui_event(event)
    end do
end subroutine poll_tui_events

subroutine process_tui_event(event)
    ! Process individual TUI events
    type(tb_event), intent(in) :: event
    
    select case (event%type)
    case (TB_EVENT_KEY)
        call process_key_event(event)
    case (TB_EVENT_RESIZE)
        call process_resize_event(event)
    case (TB_EVENT_MOUSE)
        call process_mouse_event(event)
    end select
end subroutine process_tui_event

subroutine process_key_event(event)
    ! Process keyboard events for quit detection
    type(tb_event), intent(in) :: event
    
    ! Check for quit keys
    if (event%key == TB_KEY_ESC .or. &
        event%key == TB_KEY_CTRL_C .or. &
        event%key == TB_KEY_CTRL_D) then
        tui_state%quit_requested = .true.
    end if
end subroutine process_key_event

subroutine process_resize_event(event)
    ! Process terminal resize events
    type(tb_event), intent(in) :: event
    
    tui_state%resize_pending = .true.
end subroutine process_resize_event

subroutine process_mouse_event(event)
    ! Process mouse events (placeholder for future implementation)
    type(tb_event), intent(in) :: event
    
    ! Mouse events not implemented in current version
end subroutine process_mouse_event

subroutine handle_terminal_resize()
    ! Handle terminal resize by reallocating buffers
    integer :: new_width, new_height
    
    ! Get new terminal dimensions
    new_width = mock_tb_width()
    new_height = mock_tb_height()
    
    ! Validate dimensions
    if (new_width <= 0 .or. new_height <= 0) return
    
    ! Update state
    tui_state%terminal_width = new_width
    tui_state%terminal_height = new_height
    
    ! Reallocate buffers
    call allocate_cell_buffers()
    
    print *, "handle_terminal_resize: resized to ", new_width, "x", new_height
end subroutine handle_terminal_resize

subroutine clear_back_buffer()
    ! Clear only the back buffer for new frame rendering
    integer :: x, y
    type(tb_cell) :: empty_cell
    
    if (.not. allocated(tui_state%back_buffer)) return
    
    ! Initialize empty cell
    empty_cell%ch = int(ichar(' '), c_int32_t)
    empty_cell%fg = 0
    empty_cell%bg = 0
    
    ! Clear back buffer
    do y = 1, tui_state%terminal_height
        do x = 1, tui_state%terminal_width
            tui_state%back_buffer(x, y) = empty_cell
        end do
    end do
end subroutine clear_back_buffer

subroutine begin_gui_frame()
    ! TODO: GUI frame timing
end subroutine begin_gui_frame

! Backend-specific presentation stubs
subroutine present_tui(tree)
    class(node), intent(in) :: tree
    
    if (.not. tui_state%initialized) return
    
    ! Render widget tree to back buffer
    call render_node_to_buffer(tree, 0.0, 0.0)
    
    ! Apply diff-based updates to terminal
    call apply_buffer_diff()
    
    ! Present the changes to the terminal
    call mock_tb_present()
end subroutine present_tui

recursive subroutine render_node_to_buffer(tree, offset_x_dp, offset_y_dp)
    ! Render node tree to the back buffer using dp coordinates
    class(node), intent(in) :: tree
    real, intent(in) :: offset_x_dp, offset_y_dp
    
    integer :: i, child_offset_x_dp, child_offset_y_dp
    real :: current_offset_x_dp, current_offset_y_dp
    
    ! Start at the given offset
    current_offset_x_dp = offset_x_dp
    current_offset_y_dp = offset_y_dp
    
    ! Only process children if the array is allocated
    if (allocated(tree%children)) then
        select case (trim(tree%layout_type))
        case ("column")
            ! Vertical layout - children stacked vertically
            do i = 1, size(tree%children)
                call render_node_to_buffer(tree%children(i), current_offset_x_dp, current_offset_y_dp)
                ! Move down for next child (placeholder - would need proper sizing)
                current_offset_y_dp = current_offset_y_dp + DEFAULT_ROW_HEIGHT_DP
                if (tree%gap_dp > 0.0) then
                    current_offset_y_dp = current_offset_y_dp + tree%gap_dp
                end if
            end do
            
        case ("row")
            ! Horizontal layout - children placed side by side
            do i = 1, size(tree%children)
                call render_node_to_buffer(tree%children(i), current_offset_x_dp, current_offset_y_dp)
                ! Move right for next child (placeholder - would need proper sizing)
                current_offset_x_dp = current_offset_x_dp + DEFAULT_COLUMN_WIDTH_DP
                if (tree%gap_dp > 0.0) then
                    current_offset_x_dp = current_offset_x_dp + tree%gap_dp
                end if
            end do
            
        case default
            ! No specific layout - render children at same position (overlay)
            do i = 1, size(tree%children)
                call render_node_to_buffer(tree%children(i), current_offset_x_dp, current_offset_y_dp)
            end do
        end select
    end if
    
    ! Render this node's content (placeholder for widget rendering)
    call render_node_content(tree, offset_x_dp, offset_y_dp)
end subroutine render_node_to_buffer

subroutine render_node_content(tree, x_dp, y_dp)
    ! Render node content to back buffer (placeholder for widget rendering)
    class(node), intent(in) :: tree
    real, intent(in) :: x_dp, y_dp
    integer :: cell_x, cell_y
    type(tb_cell) :: cell
    
    ! Convert dp coordinates to cell coordinates
    call dp_to_cell_coords(x_dp, y_dp, cell_x, cell_y)
    
    ! Check bounds
    if (cell_x < 0 .or. cell_x >= tui_state%terminal_width .or. &
        cell_y < 0 .or. cell_y >= tui_state%terminal_height) return
    
    ! Render a simple marker for testing (would be replaced by actual widget rendering)
    cell%ch = int(ichar('*'), c_int32_t)
    cell%fg = 7  ! White foreground
    cell%bg = 0  ! Black background
    
    ! Set cell in back buffer (using 1-based indexing)
    tui_state%back_buffer(cell_x + 1, cell_y + 1) = cell
end subroutine render_node_content

subroutine apply_buffer_diff()
    ! Apply diff-based updates from back buffer to front buffer and terminal
    integer :: y, x, new_hash
    logical :: line_changed
    
    if (.not. allocated(tui_state%front_buffer) .or. &
        .not. allocated(tui_state%back_buffer) .or. &
        .not. allocated(tui_state%line_hashes)) return
    
    ! Process each line
    do y = 1, tui_state%terminal_height
        ! Calculate hash for current line in back buffer
        new_hash = calculate_line_hash(tui_state%back_buffer(:, y))
        
        ! Check if line has changed
        line_changed = (new_hash /= tui_state%line_hashes(y))
        
        if (line_changed) then
            ! Update line in terminal and front buffer
            do x = 1, tui_state%terminal_width
                ! Update terminal cell (using 0-based indexing for C interface)
                call mock_tb_set_cell(x - 1, y - 1, &
                                tui_state%back_buffer(x, y)%ch, &
                                tui_state%back_buffer(x, y)%fg, &
                                tui_state%back_buffer(x, y)%bg)
                
                ! Update front buffer
                tui_state%front_buffer(x, y) = tui_state%back_buffer(x, y)
            end do
            
            ! Update line hash
            tui_state%line_hashes(y) = new_hash
        end if
    end do
end subroutine apply_buffer_diff

subroutine present_gui(tree)
    class(node), intent(in) :: tree
    ! TODO: GUI rendering with raygui
end subroutine present_gui

! Backend-specific quit detection stubs
logical function check_tui_quit()
    ! Check for TUI quit events (ESC, Ctrl+C, etc.)
    check_tui_quit = tui_state%quit_requested .or. .not. tui_state%initialized
end function check_tui_quit

logical function check_gui_quit()
    ! Check for GUI quit events (window close, etc.)
    ! For now, return true after reasonable timeout to prevent infinite loop
    integer, save :: call_count = 0
    call_count = call_count + 1
    
    ! Auto-quit after 10 seconds (approximately 600 frames at 60fps)
    ! This prevents infinite loops during development/testing
    check_gui_quit = call_count > 600
end function check_gui_quit

! Backend-specific shutdown stubs
subroutine shutdown_tui_backend()
    ! Cleanup TUI backend resources
    
    if (.not. tui_state%initialized) return
    
    ! Shutdown termbox2 library
    call mock_tb_shutdown()
    
    ! Deallocate buffers
    if (allocated(tui_state%front_buffer)) deallocate(tui_state%front_buffer)
    if (allocated(tui_state%back_buffer)) deallocate(tui_state%back_buffer)
    if (allocated(tui_state%line_hashes)) deallocate(tui_state%line_hashes)
    
    ! Reset state
    tui_state%initialized = .false.
    tui_state%terminal_width = 0
    tui_state%terminal_height = 0
    tui_state%resize_pending = .false.
    tui_state%quit_requested = .false.
end subroutine shutdown_tui_backend

subroutine shutdown_gui_backend()
    ! TODO: GUI cleanup
#ifdef ENABLE_GUI
#endif
end subroutine shutdown_gui_backend

! Layout constructor implementations
function column(gap, children) result(n)
    use fortui_units, only: convert_to_dp, ui_get_context, ui_context
    class(*), intent(in), optional :: gap
    type(node), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    integer :: i
    
    ! Initialize column layout node
    n = node()
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    if (present(gap)) then
        call ui_get_context(ctx)
        gap_dp_value = convert_to_dp(gap, ctx)
        n%gap_dp = gap_dp_value
    else
        n%gap_dp = 0.0  ! Default gap per test specifications
    end if
    
    ! Handle children array
    if (present(children)) then
        allocate(n%children(size(children)))
        do i = 1, size(children)
            n%children(i) = children(i)
        end do
    else
        allocate(n%children(0))  ! Empty children array
    end if
end function column

function row(gap, children) result(n)
    use fortui_units, only: convert_to_dp, ui_get_context, ui_context
    class(*), intent(in), optional :: gap
    type(node), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    integer :: i
    
    ! Initialize row layout node
    n = node()
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    if (present(gap)) then
        call ui_get_context(ctx)
        gap_dp_value = convert_to_dp(gap, ctx)
        n%gap_dp = gap_dp_value
    else
        n%gap_dp = 0.0  ! Default gap per test specifications
    end if
    
    ! Handle children array
    if (present(children)) then
        allocate(n%children(size(children)))
        do i = 1, size(children)
            n%children(i) = children(i)
        end do
    else
        allocate(n%children(0))  ! Empty children array
    end if
end function row

! Assignment operator implementation for proper memory management
recursive subroutine assign_node(lhs, rhs)
    class(node), intent(out) :: lhs
    class(node), intent(in) :: rhs
    
    integer :: i
    
    ! Copy basic properties
    lhs%layout_type = rhs%layout_type
    lhs%gap_dp = rhs%gap_dp
    
    ! Deep copy children array
    if (allocated(rhs%children)) then
        if (allocated(lhs%children)) deallocate(lhs%children)
        allocate(lhs%children(size(rhs%children)))
        do i = 1, size(rhs%children)
            lhs%children(i) = rhs%children(i)
        end do
    else
        if (allocated(lhs%children)) deallocate(lhs%children)
    end if
end subroutine assign_node

! Mock termbox2 implementations for testing without actual library
integer(c_int) function mock_tb_init() result(ret)
    ! Mock termbox2 initialization
    mock_terminal%initialized = .true.
    mock_terminal%width = 80
    mock_terminal%height = 24
    mock_terminal%event_count = 0
    ret = 0  ! Success
end function mock_tb_init

subroutine mock_tb_shutdown()
    ! Mock termbox2 shutdown
    mock_terminal%initialized = .false.
end subroutine mock_tb_shutdown

integer(c_int) function mock_tb_width() result(width)
    ! Mock terminal width query
    width = mock_terminal%width
end function mock_tb_width

integer(c_int) function mock_tb_height() result(height)
    ! Mock terminal height query
    height = mock_terminal%height
end function mock_tb_height

integer(c_int) function mock_tb_peek_event(event, timeout_ms) result(ret)
    ! Mock event polling with timeout
    type(tb_event), intent(out) :: event
    integer(c_int), intent(in) :: timeout_ms
    
    mock_terminal%event_count = mock_terminal%event_count + 1
    
    ! Simulate different events based on call count for testing
    if (mock_terminal%event_count == 10) then
        ! Simulate ESC key after 10 calls for testing
        event%type = TB_EVENT_KEY
        event%key = TB_KEY_ESC
        event%ch = 27
        event%mod = 0
        event%x = 0
        event%y = 0
        event%w = 0
        event%h = 0
        ret = 1  ! Event available
    else if (mock_terminal%event_count > 50) then
        ! Stop generating events after 50 calls to prevent infinite loops
        ret = 0  ! No event
    else
        ! No event for most calls
        ret = 0
    end if
end function mock_tb_peek_event

subroutine mock_tb_set_cell(x, y, ch, fg, bg)
    ! Mock cell setting (no-op for testing)
    integer(c_int), intent(in) :: x, y
    integer(c_int32_t), intent(in) :: ch
    integer(c_int), intent(in) :: fg, bg
    
    ! No operation for mock - would update display in real implementation
end subroutine mock_tb_set_cell

subroutine mock_tb_clear()
    ! Mock terminal clear (no-op for testing)
    ! No operation for mock
end subroutine mock_tb_clear

subroutine mock_tb_present()
    ! Mock terminal present (no-op for testing)
    ! No operation for mock
end subroutine mock_tb_present

end module fortui_core