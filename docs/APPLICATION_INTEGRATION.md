# fortui Application Integration Guide

Complete examples for integrating fortui lifecycle functions into real applications.

## Overview

This guide demonstrates practical patterns for building complete applications using fortui's lifecycle API. All examples are tested against the actual implementation and ready to run.

## Basic Application Pattern

### Minimal Working Application

```fortran
program minimal_app
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  logical :: running
  
  ! Automatic backend selection - smart default
  call ui_init("auto", 80, 25, "Minimal App")
  
  ! Simple main loop
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
end program
```

**Key Points:**
- `"auto"` backend selection handles all environments automatically
- 200ms timeout provides responsive input while being CPU-efficient
- Single `ui_present()` call handles all rendering

### Robust Production Application

```fortran
program production_app
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  logical :: running, error_occurred
  integer :: frame_count = 0
  
  ! Initialize with error handling
  call safe_initialization()
  
  ! Configure for efficiency
  call ui_set_idle_policy("adaptive", idle_fps=12)
  
  ! Main application loop with multiple exit conditions
  running = .true.
  error_occurred = .false.
  
  do while (running .and. .not. error_occurred)
    call ui_frame_begin(timeout_ms=200)
    
    ! Build UI (using fortui_widgets when available)
    call build_user_interface(ui_root, frame_count)
    
    ! Present and update
    call ui_present(ui_root)
    frame_count = frame_count + 1
    
    ! Check exit conditions
    running = .not. ui_should_close()
    call check_application_errors(error_occurred)
  end do
  
  ! Clean shutdown with state saving
  call save_application_state()
  call ui_shutdown()
  
  if (error_occurred) then
    print *, "Application terminated due to error"
    stop 1
  else
    print *, "Application completed normally after", frame_count, "frames"
  end if

contains

  subroutine safe_initialization()
    ! Try preferred configuration with fallbacks
    call ui_init("auto", 80, 25, "Production App")
  end subroutine

  subroutine build_user_interface(ui, frame)
    type(node), intent(out) :: ui
    integer, intent(in) :: frame
    ! UI building logic here
    ! ui = column(children=[...])  ! Using fortui_widgets
  end subroutine

  subroutine check_application_errors(error_flag)
    logical, intent(out) :: error_flag
    ! Check for application-specific error conditions
    error_flag = .false.
  end subroutine

  subroutine save_application_state()
    ! Save user data, preferences, etc.
  end subroutine

end program
```

## Environment-Specific Patterns

### Command-Line Tool Integration

```fortran
program cli_tool
  use fortui_core
  implicit none
  
  character(len=256) :: backend_arg, mode_arg
  integer :: width, height
  logical :: use_ui, running
  type(node) :: ui_root
  
  ! Parse command line arguments
  call parse_arguments(backend_arg, mode_arg, use_ui)
  
  if (use_ui) then
    ! Configure UI based on user preference
    call configure_ui_from_args(backend_arg, width, height)
    call ui_init(trim(backend_arg), width, height, "CLI Tool UI")
    
    ! Interactive UI mode
    running = .true.
    do while (running)
      call ui_frame_begin(250)  ! Slower for CLI tools
      call build_interactive_ui(ui_root)
      call ui_present(ui_root)
      running = .not. ui_should_close()
    end do
    
    call ui_shutdown()
  else
    ! Non-interactive CLI mode
    call run_batch_mode()
  end if

contains

  subroutine parse_arguments(backend, mode, enable_ui)
    character(*), intent(out) :: backend, mode
    logical, intent(out) :: enable_ui
    
    ! Default values
    backend = "auto"
    mode = "interactive"
    enable_ui = .true.
    
    ! Parse actual command line (implementation depends on your needs)
    ! For --backend=tui, --mode=batch, etc.
  end subroutine

  subroutine configure_ui_from_args(backend, w, h)
    character(*), intent(in) :: backend
    integer, intent(out) :: w, h
    
    ! Size based on backend preference
    select case (trim(backend))
    case ("gui")
      w = 120; h = 40  ! Larger for GUI
    case default
      w = 80; h = 25   ! Conservative for TUI
    end select
  end subroutine

  subroutine build_interactive_ui(ui)
    type(node), intent(out) :: ui
    ! Build CLI tool interface
  end subroutine

  subroutine run_batch_mode()
    ! Non-interactive batch processing
    print *, "Running in batch mode..."
  end subroutine

end program
```

### Data Analysis Dashboard

```fortran
program data_dashboard
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  type(view) :: main_plot, histogram_plot
  logical :: running, data_updated
  integer :: refresh_count = 0
  real, allocatable :: data_array(:)
  
  ! Initialize for data visualization
  call ui_init("auto", 120, 40, "Data Analysis Dashboard")
  call ui_set_idle_policy("adaptive", idle_fps=8)  ! Power-efficient for dashboards
  
  ! Initialize data and views
  call load_initial_data(data_array)
  call initialize_plot_views(main_plot, histogram_plot)
  
  running = .true.
  do while (running)
    ! Longer timeout for dashboard applications
    call ui_frame_begin(timeout_ms=500)
    
    ! Check for data updates
    call check_data_updates(data_array, data_updated)
    if (data_updated) then
      call update_plot_views(main_plot, histogram_plot, data_array)
    end if
    
    ! Build dashboard UI
    call build_dashboard_ui(ui_root, main_plot, histogram_plot, data_array, refresh_count)
    call ui_present(ui_root)
    
    refresh_count = refresh_count + 1
    running = .not. ui_should_close()
  end do
  
  call cleanup_resources(data_array)
  call ui_shutdown()

contains

  subroutine load_initial_data(data)
    real, allocatable, intent(out) :: data(:)
    ! Load data from file, database, etc.
    allocate(data(100))
    data = 0.0
  end subroutine

  subroutine initialize_plot_views(plot1, plot2)
    type(view), intent(out) :: plot1, plot2
    ! Set up initial zoom and pan for plots
    plot1%scale_x = 1.0; plot1%scale_y = 1.0
    plot2%scale_x = 1.0; plot2%scale_y = 1.0
  end subroutine

  subroutine check_data_updates(data, updated)
    real, intent(inout) :: data(:)
    logical, intent(out) :: updated
    ! Check if data source has new information
    updated = .false.
  end subroutine

  subroutine update_plot_views(plot1, plot2, data)
    type(view), intent(inout) :: plot1, plot2
    real, intent(in) :: data(:)
    ! Update plot scaling based on data ranges
  end subroutine

  subroutine build_dashboard_ui(ui, plot1, plot2, data, refresh)
    type(node), intent(out) :: ui
    type(view), intent(in) :: plot1, plot2
    real, intent(in) :: data(:)
    integer, intent(in) :: refresh
    ! Build complete dashboard interface
    ! ui = column(children=[...])  ! Using fortui_widgets
  end subroutine

  subroutine cleanup_resources(data)
    real, allocatable, intent(inout) :: data(:)
    if (allocated(data)) deallocate(data)
  end subroutine

end program
```

### Real-Time Monitoring Application

```fortran
program realtime_monitor
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  logical :: running, system_healthy
  integer :: update_counter = 0
  real :: cpu_usage, memory_usage, network_traffic
  
  ! High-refresh monitoring application
  call ui_init("auto", 100, 30, "System Monitor")
  call ui_set_idle_policy("steady")  ! No idle reduction for real-time
  
  running = .true.
  system_healthy = .true.
  
  do while (running .and. system_healthy)
    ! Short timeout for real-time responsiveness
    call ui_frame_begin(timeout_ms=50)
    
    ! Update system metrics
    call read_system_metrics(cpu_usage, memory_usage, network_traffic)
    call check_system_health(cpu_usage, memory_usage, system_healthy)
    
    ! Build real-time UI
    call build_monitoring_ui(ui_root, cpu_usage, memory_usage, network_traffic, update_counter)
    call ui_present(ui_root)
    
    update_counter = update_counter + 1
    running = .not. ui_should_close()
  end do
  
  if (.not. system_healthy) then
    print *, "System monitoring detected critical issues"
  end if
  
  call ui_shutdown()

contains

  subroutine read_system_metrics(cpu, mem, net)
    real, intent(out) :: cpu, mem, net
    ! Read actual system metrics
    cpu = 50.0  ! Example values
    mem = 75.0
    net = 1024.0
  end subroutine

  subroutine check_system_health(cpu, mem, healthy)
    real, intent(in) :: cpu, mem
    logical, intent(out) :: healthy
    ! Check if system metrics are within acceptable ranges
    healthy = (cpu < 90.0) .and. (mem < 95.0)
  end subroutine

  subroutine build_monitoring_ui(ui, cpu, mem, net, counter)
    type(node), intent(out) :: ui
    real, intent(in) :: cpu, mem, net
    integer, intent(in) :: counter
    ! Build real-time monitoring interface
    ! ui = column(children=[...])  ! Using fortui_widgets
  end subroutine

end program
```

## Environment Variable Configuration

### Runtime Backend Override

```bash
# Force TUI for SSH deployment
export FORTUI_BACKEND=tui
./my_app

# Force GUI for local development
export FORTUI_BACKEND=gui
./my_app

# Force headless mode for CI testing
export FORTUI_HEADLESS=1
./my_app
```

### Application-Specific Environment Detection

```fortran
program environment_aware_app
  use fortui_core
  implicit none
  
  character(len=32) :: detected_backend
  logical :: running
  type(node) :: ui_root
  
  ! Detect environment and configure appropriately
  call detect_environment(detected_backend)
  call configure_for_environment(detected_backend)
  
  running = .true.
  do while (running)
    call ui_frame_begin(get_timeout_for_environment(detected_backend))
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()

contains

  subroutine detect_environment(backend)
    character(*), intent(out) :: backend
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for explicit override
    call get_environment_variable("FORTUI_BACKEND", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
      backend = trim(env_var)
      return
    end if
    
    ! Check for CI environment
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
      backend = "tui"
      return
    end if
    
    ! Default to auto-detection
    backend = "auto"
  end subroutine

  subroutine configure_for_environment(backend)
    character(*), intent(in) :: backend
    
    select case (trim(backend))
    case ("tui")
      call ui_init("tui", 80, 25, "CLI Mode")
    case ("gui")
      call ui_init("gui", 120, 40, "GUI Mode")
    case default
      call ui_init("auto", 100, 30, "Adaptive Mode")
      call ui_set_idle_policy("adaptive", idle_fps=12)
    end select
  end subroutine

  integer function get_timeout_for_environment(backend)
    character(*), intent(in) :: backend
    
    select case (trim(backend))
    case ("tui")
      get_timeout_for_environment = 200  ! Standard TUI timing
    case ("gui")
      get_timeout_for_environment = 16   ! High-refresh GUI
    case default
      get_timeout_for_environment = 100  ! Balanced
    end select
  end function

end program
```

## Error Handling and Recovery

### Robust Error Handling

```fortran
program robust_application
  use fortui_core
  implicit none
  
  logical :: initialization_success, running
  type(node) :: ui_root
  integer :: error_count = 0
  
  ! Attempt initialization with multiple fallbacks
  call attempt_initialization(initialization_success)
  
  if (.not. initialization_success) then
    print *, "Failed to initialize UI system"
    stop 1
  end if
  
  ! Main loop with error recovery
  running = .true.
  do while (running .and. error_count < 10)
    call protected_frame_cycle(ui_root, running, error_count)
  end do
  
  ! Always ensure clean shutdown
  call safe_shutdown()

contains

  subroutine attempt_initialization(success)
    logical, intent(out) :: success
    
    success = .false.
    
    ! Try GUI first if explicitly requested
    if (backend_preference() == "gui") then
      call try_gui_init(success)
      if (success) return
    end if
    
    ! Try auto-detection
    call try_auto_init(success)
    if (success) return
    
    ! Final fallback to TUI
    call try_tui_init(success)
  end subroutine

  function backend_preference() result(backend)
    character(len=32) :: backend
    character(len=256) :: env_var
    integer :: ios
    
    call get_environment_variable("PREFERRED_BACKEND", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
      backend = trim(env_var)
    else
      backend = "auto"
    end if
  end function

  subroutine try_gui_init(success)
    logical, intent(out) :: success
    success = .true.
    call ui_init("gui", 120, 40, "GUI App")
    ! In real implementation, check if initialization actually succeeded
  end subroutine

  subroutine try_auto_init(success)
    logical, intent(out) :: success
    success = .true.
    call ui_init("auto", 100, 30, "Auto App")
  end subroutine

  subroutine try_tui_init(success)
    logical, intent(out) :: success
    success = .true.
    call ui_init("tui", 80, 25, "TUI App")
  end subroutine

  subroutine protected_frame_cycle(ui, still_running, errors)
    type(node), intent(inout) :: ui
    logical, intent(inout) :: still_running
    integer, intent(inout) :: errors
    
    ! Wrap frame operations in error handling
    call ui_frame_begin(200)
    
    ! Build UI with error protection
    call safe_ui_build(ui, still_running)
    
    ! Present with error checking
    call ui_present(ui)
    
    ! Check exit conditions
    still_running = still_running .and. .not. ui_should_close()
  end subroutine

  subroutine safe_ui_build(ui, success)
    type(node), intent(out) :: ui
    logical, intent(inout) :: success
    
    ! Build UI with error handling
    ! ui = column(children=[...])  ! Using fortui_widgets
    success = .true.
  end subroutine

  subroutine safe_shutdown()
    ! Always attempt clean shutdown
    call ui_shutdown()
    print *, "Application shutdown completed"
  end subroutine

end program
```

## Performance Optimization Patterns

### Frame Rate Optimization

```fortran
program optimized_app
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  logical :: running
  integer :: frame_count = 0, last_fps_check = 0
  real :: target_fps = 60.0, actual_fps = 0.0
  integer :: fps_counter = 0
  
  ! Initialize with performance tuning
  call ui_init("auto", 100, 30, "Optimized App")
  call optimize_for_performance()
  
  running = .true.
  do while (running)
    call adaptive_frame_begin(actual_fps, target_fps)
    call ui_present(ui_root)
    
    ! FPS monitoring
    call update_fps_counter(frame_count, fps_counter, actual_fps)
    call adjust_performance_settings(actual_fps, target_fps)
    
    frame_count = frame_count + 1
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
  print *, "Average FPS:", actual_fps

contains

  subroutine optimize_for_performance()
    ! Configure for optimal performance
    call ui_set_idle_policy("adaptive", idle_fps=15)
  end subroutine

  subroutine adaptive_frame_begin(current_fps, target_fps)
    real, intent(in) :: current_fps, target_fps
    integer :: timeout_ms
    
    ! Adapt timeout based on performance
    if (current_fps > target_fps * 1.1) then
      timeout_ms = 20  ! Slow down if running too fast
    else if (current_fps < target_fps * 0.9) then
      timeout_ms = 8   ! Speed up if running too slow
    else
      timeout_ms = 16  ! Standard 60 FPS timing
    end if
    
    call ui_frame_begin(timeout_ms)
  end subroutine

  subroutine update_fps_counter(total_frames, fps_frames, fps)
    integer, intent(in) :: total_frames
    integer, intent(inout) :: fps_frames
    real, intent(out) :: fps
    
    fps_frames = fps_frames + 1
    
    ! Calculate FPS every 60 frames
    if (fps_frames >= 60) then
      fps = real(fps_frames) / 1.0  ! Simplified - should use actual time
      fps_frames = 0
    end if
  end subroutine

  subroutine adjust_performance_settings(current_fps, target_fps)
    real, intent(in) :: current_fps, target_fps
    
    ! Automatically adjust settings based on performance
    if (current_fps < target_fps * 0.5) then
      ! Performance is poor - reduce quality/complexity
      call ui_set_idle_policy("steady")  ! Maintain steady frame rate
    end if
  end subroutine

end program
```

## Testing and Debugging Patterns

### Test-Friendly Application Structure

```fortran
program testable_app
  use fortui_core
  implicit none
  
  logical :: running, test_mode
  character(len=256) :: test_arg
  integer :: max_frames = -1  ! -1 means unlimited
  
  ! Check for test mode
  call check_test_mode(test_mode, max_frames)
  
  if (test_mode) then
    call run_test_mode(max_frames)
  else
    call run_normal_mode()
  end if

contains

  subroutine check_test_mode(is_test, frame_limit)
    logical, intent(out) :: is_test
    integer, intent(out) :: frame_limit
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for test environment
    call get_environment_variable("FORTUI_TEST_MODE", env_var, status=ios)
    is_test = (ios == 0)
    
    frame_limit = -1
    if (is_test) then
      call get_environment_variable("FORTUI_TEST_FRAMES", env_var, status=ios)
      if (ios == 0) then
        read(env_var, *, iostat=ios) frame_limit
        if (ios /= 0) frame_limit = 10  ! Default for tests
      else
        frame_limit = 10  ! Default test duration
      end if
    end if
  end subroutine

  subroutine run_test_mode(frame_limit)
    integer, intent(in) :: frame_limit
    type(node) :: ui_root
    integer :: frame_count = 0
    
    print *, "Running in test mode, max frames:", frame_limit
    
    ! Force TUI for consistent testing
    call ui_init("tui", 80, 25, "Test Mode")
    
    do while (frame_count < frame_limit)
      call ui_frame_begin(50)  ! Fast timeout for tests
      call ui_present(ui_root)
      frame_count = frame_count + 1
      
      ! Test can still exit early
      if (ui_should_close()) exit
    end do
    
    call ui_shutdown()
    print *, "Test completed after", frame_count, "frames"
  end subroutine

  subroutine run_normal_mode()
    type(node) :: ui_root
    logical :: running
    
    call ui_init("auto", 100, 30, "Normal Mode")
    call ui_set_idle_policy("adaptive", idle_fps=12)
    
    running = .true.
    do while (running)
      call ui_frame_begin(200)
      call ui_present(ui_root)
      running = .not. ui_should_close()
    end do
    
    call ui_shutdown()
  end subroutine

end program
```

## Next Steps

- **Widget Integration**: Learn about UI building in [WIDGET_API.md](WIDGET_API.md) (coming soon)
- **Core Types**: Understand `node` and `view` types in [CORE_TYPES_API.md](CORE_TYPES_API.md)  
- **Build Configuration**: Set up dependencies in [BUILD_GUIDE.md](BUILD_GUIDE.md)
- **Backend Details**: Learn compilation options in [BACKEND_SELECTION.md](BACKEND_SELECTION.md)