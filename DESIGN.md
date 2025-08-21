# fortui — design doc (v0.6.0)

## Goal
Declarative UI for modern Fortran, one codebase, two backends:
- **TUI**: termbox2 (event-driven, diffed output) - **ALWAYS AVAILABLE**
- **GUI**: raygui/raylib (vsynced, target FPS) - **CONDITIONAL ENHANCEMENT**

Monospace-first for exact TUI/GUI parity. Proportional text is a future opt-in.

## Build System Architecture

### Single Package Design
- One `fortui` package (no submodules or package splits)
- Custom build script `tools/build_fortui.sh` orchestrates dependency management
- FPM integration with build-script override and CPP preprocessing support
- **Fail-safe guarantee**: TUI backend always builds, GUI only when dependencies available
- **Zero external dependencies in repo**: All dependencies fetched and cached locally

### Dependency Management Strategy

#### TUI Backend Dependencies (Always Required)
- **termbox2**: Clone from `github.com/termbox/termbox2` on demand
- **Build process**: Compile `termbox2.h` to static library
- **Cache location**: `${GUI_CACHE:-$HOME/.cache/fortui}/termbox2/`
- **Version pinning**: Use specific commit SHA for reproducible builds
- **Cross-platform**: Linux first, extensible to macOS/Windows

#### GUI Backend Dependencies (Conditional)
- **Primary**: `lazy-fortran/fortran-raygui` Fortran bindings
- **System raylib**: Detect via pkg-config or RAYLIB_ROOT environment
- **Build process**: Clone fortran-raygui only when raylib available
- **Cache location**: `${GUI_CACHE:-$HOME/.cache/fortui}/fortran-raygui/`
- **Graceful degradation**: Missing raylib → TUI-only build (no failure)

#### Detection and Probing System
```bash
# Multi-method raylib detection (ordered by reliability):
1. pkg-config --exists raylib && pkg-config --cflags --libs raylib
2. RAYLIB_ROOT environment variable with lib/include validation
3. Standard system paths (/usr/local, /usr, /opt/raylib)
4. Homebrew paths (macOS: /opt/homebrew, /usr/local)
5. Development builds (./raylib, ../raylib relative to project)

# Headless environment detection:
- Check DISPLAY, WAYLAND_DISPLAY environment variables
- Probe for X11/Wayland libraries at runtime
- Fallback to TUI when GUI not possible
```

### Developer Control Interface

#### Environment Variables
```bash
# Force text-only build (skip GUI entirely)
DISABLE_GUI=1 fpm build

# Use prebuilt raylib installation
RAYLIB_ROOT=/usr/local fpm build

# Override fortran-raygui source and branch
FRG_URL=https://github.com/user/fork.git FRG_REF=feature-branch fpm build

# Control dependency cache location
GUI_CACHE=/tmp/fortui_deps fpm build

# Force dependency refresh (ignore cached builds)
FORCE_REBUILD=1 fpm build

# Verbose build output for debugging
FORTUI_VERBOSE=1 fpm build
```

#### Build Script Integration
- **FPM override**: `build-script = "tools/build_fortui.sh"`
- **CPP preprocessing**: `preprocess.cpp.suffixes = ["F90", "f90"]`
- **Conditional sources**: Backend files included based on available dependencies
- **Library linking**: Dynamic link flags set by build script

### Conditional Compilation Architecture

#### CPP Macro Strategy
```fortran
! Core compilation flags set by build system:
#ifdef ENABLE_GUI
  ! GUI backend implementation
  use raygui_bindings
#endif

#ifdef ENABLE_TUI  
  ! TUI backend implementation (always enabled)
  use termbox2_bindings
#endif

! Runtime backend selection:
#if defined(ENABLE_GUI) && defined(ENABLE_TUI)
  ! Dual backend support - runtime selection
#elif defined(ENABLE_TUI)
  ! TUI-only build
#else
  #error "At least TUI backend must be available"
#endif
```

#### Backend Runtime Detection
```fortran
function is_gui_available() result(available)
  logical :: available
  
#ifdef ENABLE_GUI
  ! Check if we're in a graphical environment
  available = check_display_environment()
#else
  available = .false.
#endif
end function

function check_display_environment() result(has_display)
  logical :: has_display
  character(len=256) :: display_var
  
  ! Check for X11 or Wayland display
  call get_environment_variable("DISPLAY", display_var)
  if (len_trim(display_var) > 0) then
    has_display = .true.
    return
  end if
  
  call get_environment_variable("WAYLAND_DISPLAY", display_var)
  has_display = len_trim(display_var) > 0
end function
```

### Build Process Flow

#### Phase 1: Environment Assessment
1. Detect operating system and architecture
2. Check for GUI environment (DISPLAY, WAYLAND_DISPLAY)
3. Probe for raylib installation
4. Determine available backends
5. Set compilation mode (TUI-only or TUI+GUI)

#### Phase 2: Dependency Resolution
1. **termbox2** (always required):
   - Check cache or clone from GitHub
   - Build static library with appropriate flags
   - Verify successful compilation

2. **fortran-raygui** (if GUI enabled):
   - Verify raylib availability first
   - Check cache or clone fortran-raygui
   - Build with detected raylib paths
   - Handle failure gracefully (fallback to TUI-only)

#### Phase 3: FPM Configuration Generation
1. Generate preprocessor definitions:
   - `-DENABLE_TUI=1` (always)
   - `-DENABLE_GUI=1` (if available)
   
2. Set include paths:
   - termbox2 headers
   - fortran-raygui modules (if GUI)
   
3. Configure link flags:
   - `-ltermbox2` (static)
   - `-lraylib -lraygui` (if GUI)

4. Write temporary FPM response file

#### Phase 4: Compilation with Backend Selection
1. Preprocess Fortran sources with CPP
2. Compile backend-specific implementations
3. Link appropriate libraries
4. Validate executable

### Error Handling and Fallback

#### Graceful Degradation Path
```
GUI requested → raylib not found → Build TUI-only (warning)
GUI requested → headless environment → Runtime TUI fallback
TUI requested → termbox2 build fails → Fatal error (required)
```

#### Build Diagnostics
```bash
# Verbose output shows:
[fortui] Detecting environment...
[fortui] Found raylib via pkg-config: -lraylib -lGL -lm -lpthread -ldl -lrt -lX11
[fortui] GUI backend enabled
[fortui] Building termbox2...
[fortui] termbox2 built successfully
[fortui] Fetching fortran-raygui...
[fortui] fortran-raygui ready
[fortui] Configuring FPM with dual backends...
[fortui] Build configuration complete
```

### Testing Infrastructure

#### Multi-Backend Test Suite
```fortran
program test_backends
  use fortui
  implicit none
  
  ! Test TUI backend (always available)
  call test_tui_backend()
  
  ! Test GUI backend (if available)
  if (is_gui_available()) then
    call test_gui_backend()
  else
    print *, "GUI backend not available - skipping GUI tests"
  end if
  
  ! Test backend switching
  call test_backend_selection()
  
contains
  
  subroutine test_tui_backend()
    call ui_init("tui", 80.0, 24.0, "TUI Test")
    ! ... test TUI functionality
    call ui_shutdown()
  end subroutine
  
  subroutine test_gui_backend()
    call ui_init("gui", 800.0, 600.0, "GUI Test")
    ! ... test GUI functionality
    call ui_shutdown()
  end subroutine
  
end program
```

### CI/CD Integration

#### GitHub Actions Workflow
```yaml
jobs:
  test-tui-only:
    runs-on: ubuntu-latest
    env:
      DISABLE_GUI: 1
    steps:
      - uses: actions/checkout@v3
      - run: ./tools/build_fortui.sh
      - run: fpm test
  
  test-with-gui:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          # Install raylib
          sudo apt-get update
          sudo apt-get install -y libraylib-dev
      - run: ./tools/build_fortui.sh
      - run: |
          # Run with virtual display for GUI tests
          xvfb-run -a fpm test
```

### Platform-Specific Considerations

#### Linux
- Primary development platform
- Both X11 and Wayland support
- Package manager integration (apt, dnf, pacman)

#### macOS
- Homebrew for raylib installation
- Framework linking considerations
- Accelerate framework for performance

#### Windows
- MSYS2/MinGW64 environment
- Windows Terminal for TUI
- Native Windows GUI via raylib

### Performance Optimization

#### Build Caching
- Compiled dependencies cached in `~/.cache/fortui/`
- Incremental rebuilds when dependencies unchanged
- Parallel compilation where possible

#### Link-Time Optimization
- LTO enabled for release builds
- Dead code elimination
- Symbol visibility control

### Implementation Roadmap

#### Phase 1: Core Build Infrastructure (Critical MVP)
- [x] Basic build script with termbox2 compilation
- [x] TUI-only build working
- [x] FPM integration with preprocessor
- [ ] Cache management for dependencies
- [ ] Error handling and diagnostics

#### Phase 2: Robustness and Developer Experience
- [ ] Multi-method raylib detection
- [ ] Verbose build diagnostics
- [ ] Dependency version pinning
- [ ] Cross-platform testing
- [ ] CI/CD integration

#### Phase 3: Optimization and Polish
- [ ] Parallel dependency builds
- [ ] Incremental compilation
- [ ] Binary distribution support
- [ ] Performance profiling
- [ ] Documentation generation

⸻

## Backend Abstraction Architecture (Issues #3, #10, #12)

### Overview

The backend abstraction layer enables fortui to support multiple rendering backends (TUI via termbox2, GUI via raylib/raygui) through a clean, extensible interface. The architecture uses a registration pattern where backends self-register with the core system, eliminating compile-time dependencies and enabling runtime backend selection.

### Design Goals

**Modularity**: Backends are independent modules that can be compiled conditionally based on available dependencies.

**Extensibility**: New backends can be added without modifying core code, following the Open/Closed Principle.

**Runtime Selection**: Backend choice happens at runtime based on environment capabilities and user preference.

**Zero Overhead**: Abstract interface adds no runtime cost through proper use of Fortran's type-bound procedures.

**Type Safety**: Full compile-time type checking despite runtime polymorphism.

### Core Components

#### Backend Interface (fortui_backend.f90)
```fortran
module fortui_backend
  implicit none
  private
  
  public :: backend_interface, register_backend, get_backend
  public :: list_backends, backend_available
  
  ! Abstract backend interface - all backends must implement
  type, abstract :: backend_interface
    character(len=32) :: name = ""
    logical :: active = .false.
  contains
    procedure(init_interface), deferred :: init
    procedure(shutdown_interface), deferred :: shutdown
    procedure(begin_frame_interface), deferred :: begin_frame
    procedure(render_interface), deferred :: render
    procedure(should_quit_interface), deferred :: should_quit
    procedure(is_available_interface), deferred :: is_available
    procedure(get_screen_size_interface), deferred :: get_screen_size
  end type backend_interface
  
  ! Interface definitions
  abstract interface
    subroutine init_interface(self, width, height, title)
      import :: backend_interface
      class(backend_interface), intent(inout) :: self
      integer, intent(in) :: width, height
      character(*), intent(in) :: title
    end subroutine
    
    subroutine shutdown_interface(self)
      import :: backend_interface
      class(backend_interface), intent(inout) :: self
    end subroutine
    
    subroutine begin_frame_interface(self)
      import :: backend_interface
      class(backend_interface), intent(inout) :: self
    end subroutine
    
    subroutine render_interface(self, tree)
      import :: backend_interface
      class(backend_interface), intent(inout) :: self
      class(*), intent(in) :: tree
    end subroutine
    
    logical function should_quit_interface(self)
      import :: backend_interface
      class(backend_interface), intent(in) :: self
    end function
    
    logical function is_available_interface(self)
      import :: backend_interface
      class(backend_interface), intent(in) :: self
    end function
    
    subroutine get_screen_size_interface(self, width, height)
      import :: backend_interface
      class(backend_interface), intent(in) :: self
      integer, intent(out) :: width, height
    end subroutine
  end interface
  
  ! Backend registry
  type :: backend_entry
    class(backend_interface), pointer :: backend => null()
    character(len=32) :: name = ""
  end type backend_entry
  
  integer, parameter :: MAX_BACKENDS = 8
  type(backend_entry) :: registry(MAX_BACKENDS)
  integer :: backend_count = 0
  
contains
  
  ! Register a backend with the system
  subroutine register_backend(name, backend)
    character(*), intent(in) :: name
    class(backend_interface), target :: backend
    
    if (backend_count >= MAX_BACKENDS) then
      error stop "Backend registry full"
    end if
    
    backend_count = backend_count + 1
    registry(backend_count)%name = name
    registry(backend_count)%backend => backend
    backend%name = name
  end subroutine
  
  ! Get backend by name
  function get_backend(name) result(backend)
    character(*), intent(in) :: name
    class(backend_interface), pointer :: backend
    integer :: i
    
    backend => null()
    do i = 1, backend_count
      if (registry(i)%name == name) then
        backend => registry(i)%backend
        return
      end if
    end do
  end function
  
  ! Check if backend is available
  logical function backend_available(name)
    character(*), intent(in) :: name
    class(backend_interface), pointer :: backend
    
    backend => get_backend(name)
    if (associated(backend)) then
      backend_available = backend%is_available()
    else
      backend_available = .false.
    end if
  end function
  
  ! List all registered backends
  subroutine list_backends(names, count)
    character(len=32), intent(out) :: names(:)
    integer, intent(out) :: count
    integer :: i
    
    count = min(backend_count, size(names))
    do i = 1, count
      names(i) = registry(i)%name
    end do
  end subroutine
  
end module fortui_backend
```

#### TUI Backend Implementation (fortui_tui.f90)
```fortran
module fortui_tui
  use fortui_backend
  use termbox2_bindings
  implicit none
  private
  
  public :: tui_backend_t, register_tui_backend
  
  ! TUI backend implementation
  type, extends(backend_interface) :: tui_backend_t
    integer :: tb_initialized = 0
    integer :: width = 0
    integer :: height = 0
  contains
    procedure :: init => tui_init
    procedure :: shutdown => tui_shutdown
    procedure :: begin_frame => tui_begin_frame
    procedure :: render => tui_render
    procedure :: should_quit => tui_should_quit
    procedure :: is_available => tui_is_available
    procedure :: get_screen_size => tui_get_screen_size
  end type tui_backend_t
  
  ! Module-level instance for registration
  type(tui_backend_t), target :: tui_instance
  
contains
  
  ! Self-registration function
  subroutine register_tui_backend()
    call register_backend("tui", tui_instance)
  end subroutine
  
  subroutine tui_init(self, width, height, title)
    class(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    
    ! Initialize termbox2
    self%tb_initialized = tb_init()
    if (self%tb_initialized < 0) then
      error stop "Failed to initialize termbox2"
    end if
    
    ! Enable mouse support
    call tb_set_input_mode(TB_INPUT_ESC + TB_INPUT_MOUSE)
    
    ! Get actual terminal size
    self%width = tb_width()
    self%height = tb_height()
    
    self%active = .true.
  end subroutine
  
  subroutine tui_shutdown(self)
    class(tui_backend_t), intent(inout) :: self
    
    if (self%tb_initialized >= 0) then
      call tb_shutdown()
      self%tb_initialized = -1
    end if
    self%active = .false.
  end subroutine
  
  subroutine tui_begin_frame(self)
    class(tui_backend_t), intent(inout) :: self
    call tb_clear()
  end subroutine
  
  subroutine tui_render(self, tree)
    class(tui_backend_t), intent(inout) :: self
    class(*), intent(in) :: tree
    
    ! Render tree to termbox2 cells
    call render_tree_to_cells(tree)
    
    ! Present to terminal
    call tb_present()
  end subroutine
  
  logical function tui_should_quit(self)
    class(tui_backend_t), intent(in) :: self
    type(tb_event) :: event
    integer :: poll_result
    
    ! Non-blocking poll for quit events
    poll_result = tb_peek_event(event, 0)
    tui_should_quit = (event%type == TB_EVENT_KEY .and. &
                      (event%key == TB_KEY_ESC .or. event%key == TB_KEY_CTRL_C))
  end function
  
  logical function tui_is_available(self)
    class(tui_backend_t), intent(in) :: self
    ! TUI is always available (terminal assumed)
    tui_is_available = .true.
  end function
  
  subroutine tui_get_screen_size(self, width, height)
    class(tui_backend_t), intent(in) :: self
    integer, intent(out) :: width, height
    
    if (self%active) then
      width = tb_width()
      height = tb_height()
    else
      width = 80
      height = 24
    end if
  end subroutine
  
end module fortui_tui
```

#### Core Integration (fortui_core.f90)
```fortran
module fortui_core
  use fortui_backend
  implicit none
  private
  
  public :: ui_init, ui_shutdown, ui_frame_begin, ui_present
  public :: ui_should_close
  
  ! Current active backend
  class(backend_interface), pointer :: current_backend => null()
  
contains
  
  subroutine ui_init(backend_name, width, height, title)
    character(*), intent(in), optional :: backend_name
    real, intent(in) :: width, height
    character(*), intent(in), optional :: title
    
    character(len=32) :: backend_to_use
    character(len=256) :: window_title
    integer :: width_cells, height_cells
    
    ! Determine backend
    if (present(backend_name)) then
      backend_to_use = backend_name
    else
      backend_to_use = select_best_backend()
    end if
    
    ! Get backend from registry
    current_backend => get_backend(backend_to_use)
    
    if (.not. associated(current_backend)) then
      error stop "Backend not found: " // backend_to_use
    end if
    
    if (.not. current_backend%is_available()) then
      error stop "Backend not available: " // backend_to_use
    end if
    
    ! Set title
    if (present(title)) then
      window_title = title
    else
      window_title = "Fortui Application"
    end if
    
    ! Convert dimensions
    width_cells = int(width)
    height_cells = int(height)
    
    ! Initialize backend
    call current_backend%init(width_cells, height_cells, window_title)
  end subroutine
  
  subroutine ui_shutdown()
    if (associated(current_backend)) then
      call current_backend%shutdown()
      current_backend => null()
    end if
  end subroutine
  
  subroutine ui_frame_begin()
    if (associated(current_backend)) then
      call current_backend%begin_frame()
    end if
  end subroutine
  
  subroutine ui_present()
    if (associated(current_backend)) then
      ! Build tree from current frame
      ! ... tree construction ...
      
      ! Render through backend
      call current_backend%render(tree)
    end if
  end subroutine
  
  logical function ui_should_close()
    if (associated(current_backend)) then
      ui_should_close = current_backend%should_quit()
    else
      ui_should_close = .true.
    end if
  end function
  
  ! Select best available backend
  function select_best_backend() result(name)
    character(len=32) :: name
    
    ! Prefer GUI if available
    if (backend_available("gui")) then
      name = "gui"
    else if (backend_available("tui")) then
      name = "tui"
    else
      error stop "No backends available"
    end if
  end function
  
end module fortui_core
```

### Backend Registration Pattern

#### Automatic Registration
Backends register themselves when their modules are loaded:

```fortran
! In fortui_main.f90 or initialization
program fortui_app
  use fortui_core
  
  ! Conditional backend registration based on compilation
#ifdef ENABLE_TUI
  use fortui_tui, only: register_tui_backend
#endif

#ifdef ENABLE_GUI
  use fortui_gui, only: register_gui_backend
#endif
  
  implicit none
  
  ! Register available backends
#ifdef ENABLE_TUI
  call register_tui_backend()
#endif

#ifdef ENABLE_GUI  
  call register_gui_backend()
#endif
  
  ! Now initialize with desired backend
  call ui_init("auto", 80.0, 24.0, "My App")
  
  ! ... application code ...
  
end program
```

### Tree Rendering Architecture

#### Widget Tree Structure
```fortran
! Generic tree node for backend-agnostic representation
type :: render_node
  integer :: type  ! CONTAINER, BUTTON, TEXT, etc.
  real :: x, y, width, height  ! Normalized coordinates
  character(len=256) :: text
  integer :: style_flags
  type(render_node), pointer :: children(:) => null()
  type(render_node), pointer :: next => null()
end type
```

#### Backend-Specific Rendering
Each backend traverses the tree and renders using its native primitives:

```fortran
! TUI: Convert to terminal cells
subroutine render_tree_to_cells(tree)
  ! Walk tree, convert to tb_cell operations
end subroutine

! GUI: Convert to raylib draw calls  
subroutine render_tree_to_gui(tree)
  ! Walk tree, convert to DrawRectangle, DrawText, etc.
end subroutine
```

### Event Handling Architecture

#### Unified Event Model
```fortran
type :: ui_event
  integer :: type  ! KEY, MOUSE, RESIZE, etc.
  integer :: key
  integer :: mouse_x, mouse_y
  integer :: mouse_button
  logical :: shift, ctrl, alt
end type
```

#### Backend Event Translation
```fortran
! TUI backend translates termbox events
subroutine tui_poll_events(self, event)
  class(tui_backend_t), intent(inout) :: self
  type(ui_event), intent(out) :: event
  type(tb_event) :: tb_ev
  
  if (tb_poll_event(tb_ev) > 0) then
    event%type = translate_tb_event_type(tb_ev%type)
    ! ... translation logic
  end if
end subroutine

! GUI backend translates raylib events
subroutine gui_poll_events(self, event)
  class(gui_backend_t), intent(inout) :: self
  type(ui_event), intent(out) :: event
  
  if (IsKeyPressed(KEY_ANY)) then
    event%type = EVENT_KEY
    ! ... translation logic
  end if
end subroutine
```

### Context and State Management

#### Backend-Specific Context
Each backend maintains its own state and context:

```fortran
type, extends(backend_interface) :: tui_backend_t
  ! TUI-specific state
  integer :: cursor_x = 0, cursor_y = 0
  type(tb_cell), allocatable :: front_buffer(:,:)
  type(tb_cell), allocatable :: back_buffer(:,:)
  integer, allocatable :: line_hashes(:)
end type

type, extends(backend_interface) :: gui_backend_t
  ! GUI-specific state
  integer :: window_handle
  type(Font) :: default_font
  real :: dpi_scale = 1.0
  integer :: frame_count = 0
end type
```

### Performance Optimizations

#### TUI Optimizations
- **Diff-based rendering**: Only update changed cells
- **Line hashing**: Quick detection of unchanged lines
- **Batch updates**: Coalesce multiple updates into single write

#### GUI Optimizations
- **Dirty rectangles**: Track and redraw only changed regions
- **Texture caching**: Cache rendered text and complex widgets
- **VSync alignment**: Align updates with display refresh

### Testing Strategy

#### Backend Isolation Testing
```fortran
module test_backend_isolation
  use fortui_backend
  use fortui_test_utils
  implicit none
  
  ! Mock backend for testing
  type, extends(backend_interface) :: mock_backend_t
    integer :: init_calls = 0
    integer :: render_calls = 0
  contains
    procedure :: init => mock_init
    procedure :: render => mock_render
    ! ... other procedures
  end type
  
contains
  
  subroutine test_backend_registration()
    type(mock_backend_t), target :: mock
    class(backend_interface), pointer :: retrieved
    
    call register_backend("mock", mock)
    retrieved => get_backend("mock")
    
    call assert_associated(retrieved, "Backend should be registered")
    call assert_equals(retrieved%name, "mock", "Backend name should match")
  end subroutine
  
end module
```

### Migration Strategy

#### Phase 1: Backend Abstraction Layer
1. Create `fortui_backend.f90` with abstract interface
2. Implement backend registry
3. Add registration/retrieval functions
4. Write comprehensive tests

#### Phase 2: Registration System
1. Implement self-registration pattern
2. Add conditional compilation for backends
3. Update build system to handle registration
4. Validate with multiple backend configurations

#### Phase 3: Migration and Testing
1. Migrate TUI backend to new architecture
2. Migrate GUI backend to new architecture
3. Update all examples to use new system
4. Performance validation and optimization

### Success Criteria

**Architecture**:
- [ ] Clean separation between core and backends
- [ ] No compile-time dependencies from core to backends
- [ ] Runtime backend selection working
- [ ] Easy addition of new backends

**Functionality**:
- [ ] All existing features work with new architecture
- [ ] Seamless backend switching
- [ ] Proper cleanup on backend shutdown
- [ ] Event handling works across backends

**Performance**:
- [ ] No performance regression
- [ ] Efficient tree traversal
- [ ] Optimized rendering paths
- [ ] Memory usage within bounds

⸻

## GUI Backend Implementation (Issue #11)

### Overview

Implement the GUI backend using raylib/raygui to provide graphical rendering while maintaining exact parity with the TUI backend. The implementation leverages conditional compilation to include GUI support only when raylib is available, falling back to TUI-only operation when needed.

### Architecture Design
#### Conditional Compilation Structure
```fortran
! fortui_gui.f90
module fortui_gui
#ifdef ENABLE_GUI
  use fortui_backend
  use raygui_bindings
  use raylib_bindings
  implicit none
  private
  
  public :: gui_backend_t, register_gui_backend
  
  type, extends(backend_interface) :: gui_backend_t
    logical :: window_created = .false.
    integer :: window_width = 800
    integer :: window_height = 600
    real :: dpi_scale = 1.0
  contains
    procedure :: init => gui_init
    procedure :: shutdown => gui_shutdown
    procedure :: begin_frame => gui_begin_frame
    procedure :: render => gui_render
    procedure :: should_quit => gui_should_quit
    procedure :: is_available => gui_is_available
    procedure :: get_screen_size => gui_get_screen_size
  end type gui_backend_t
  
  type(gui_backend_t), target :: gui_instance
  
contains
  
  subroutine register_gui_backend()
    call register_backend("gui", gui_instance)
  end subroutine
  
  subroutine gui_init(self, width, height, title)
    class(gui_backend_t), intent(inout) :: self
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    
    ! Detect DPI for high-resolution displays
    self%dpi_scale = GetMonitorDPI(GetCurrentMonitor()) / 96.0
    
    ! Calculate window size from grid units
    self%window_width = int(width * 8.0 * self%dpi_scale)
    self%window_height = int(height * 16.0 * self%dpi_scale)
    
    ! Configure window before creation
    call SetConfigFlags(FLAG_WINDOW_RESIZABLE + FLAG_VSYNC_HINT)
    
    ! Create window
    call InitWindow(self%window_width, self%window_height, title // c_null_char)
    
    if (IsWindowReady()) then
      self%window_created = .true.
      self%active = .true.
      
      ! Set target FPS
      call SetTargetFPS(60)
      
      ! Initialize raygui
      call GuiSetStyle(DEFAULT, TEXT_SIZE, int(16 * self%dpi_scale))
    else
      error stop "Failed to create GUI window"
    end if
  end subroutine
  
  logical function gui_is_available(self)
    class(gui_backend_t), intent(in) :: self
    character(len=256) :: display_var
    
    ! Check for display environment
    call get_environment_variable("DISPLAY", display_var)
    if (len_trim(display_var) > 0) then
      gui_is_available = .true.
      return
    end if
    
    call get_environment_variable("WAYLAND_DISPLAY", display_var)
    gui_is_available = len_trim(display_var) > 0
  end function
  
#else
  ! Stub implementation when GUI not available
  implicit none
  private
  public :: register_gui_backend
  
contains
  
  subroutine register_gui_backend()
    ! No-op when GUI not compiled
  end subroutine
  
#endif
end module fortui_gui
```

### Widget Rendering Implementation

#### Unified Rendering Interface
```fortran
! Backend-agnostic widget rendering
subroutine render_button(backend_type, id, label, x, y, width, height, pressed)
  character(*), intent(in) :: backend_type
  character(*), intent(in) :: id, label
  real, intent(in) :: x, y, width, height
  logical, intent(out) :: pressed
  
  select case(backend_type)
#ifdef ENABLE_GUI
    case("gui")
      call render_button_gui(id, label, x, y, width, height, pressed)
#endif
    case("tui")
      call render_button_tui(id, label, x, y, width, height, pressed)
  end select
end subroutine

#ifdef ENABLE_GUI
subroutine render_button_gui(id, label, x, y, width, height, pressed)
  ! GUI implementation using raygui
  Rectangle :: bounds
  bounds%x = real(x)
  bounds%y = real(y)
  bounds%width = real(width)
  bounds%height = real(height)
  
  pressed = GuiButton(bounds, label // c_null_char) /= 0
end subroutine
#endif
```

### Build System Integration

#### Dependency Management
```bash
# tools/build_fortui.sh additions for GUI backend
fetch_fortran_raygui() {
    local cache_dir="${GUI_CACHE}/fortran-raygui"
    
    if [[ ! -d "$cache_dir" ]] || [[ "${FORCE_REBUILD}" == "1" ]]; then
        echo "Fetching fortran-raygui..."
        git clone "${FRG_URL}" "$cache_dir"
        cd "$cache_dir"
        git checkout "${FRG_REF}"
        
        # Build fortran-raygui
        make lib
    fi
    
    # Set include and library paths
    export FRG_INCLUDE="-I${cache_dir}/build/include"
    export FRG_LIBS="-L${cache_dir}/build/lib -lfortran-raygui"
}

# Enhanced raylib detection with fortran-raygui integration
setup_gui_backend() {
    if detect_raylib; then
        fetch_fortran_raygui
        
        # Set CPP flags for conditional compilation
        export FPM_FFLAGS="${FPM_FFLAGS} -DENABLE_GUI"
        export FPM_LDFLAGS="${FPM_LDFLAGS} ${FRG_LIBS} $(pkg-config --libs raylib)"
        
        echo "GUI backend enabled with raylib/raygui"
        return 0
    else
        echo "GUI backend disabled (raylib not found)"
        return 1
    fi
}
```

### Testing Strategy

#### Cross-Backend Validation
```fortran
! Test that both backends produce equivalent results
program test_backend_parity
  use fortui
  implicit none
  
  type(view) :: test_view
  logical :: tui_result, gui_result
  
  ! Test with TUI backend
  call ui_init("tui", 80.0 .cw., 24.0 .ch., "Test TUI")
  call ui_frame_begin()
  tui_result = button("test_btn", "Click Me")
  call ui_present()
  call ui_shutdown()
  
  ! Test with GUI backend (if available)
  if (check_gui_available()) then
    call ui_init("gui", 640.0, 480.0, "Test GUI")
    call ui_frame_begin()
    gui_result = button("test_btn", "Click Me")
    call ui_present()
    call ui_shutdown()
    
    ! Results should be functionally equivalent
    call assert_equivalent_behavior(tui_result, gui_result)
  end if
end program
```

### Success Criteria

**Build System**:
- [ ] GUI backend builds only when raylib detected
- [ ] fortran-raygui fetched and cached automatically
- [ ] CPP preprocessing correctly enables/disables GUI code
- [ ] Build succeeds with TUI-only when GUI unavailable

**Runtime Behavior**:
- [ ] Automatic backend selection based on environment
- [ ] Headless environment detection works correctly
- [ ] Graceful fallback from GUI to TUI when needed
- [ ] User can force TUI mode via backend parameter

**Visual Parity**:
- [ ] Monospace grid alignment identical between backends
- [ ] Widget dimensions match exactly (in grid units)
- [ ] Color schemes translate appropriately
- [ ] Input behavior consistent across backends

**Performance**:
- [ ] GUI respects target FPS (default 60)
- [ ] VSync enabled by default
- [ ] Idle policy (steady/adaptive) configurable
- [ ] No performance regression in TUI mode

### Dependencies

**Requires**:
- Build system with dependency management (Issue #17) ✓
- System capability detection (Issue #15) ✓
- CPP preprocessing support in FPM ✓

**External**:
- raylib system installation (detected via pkg-config)
- fortran-raygui (fetched automatically when GUI possible)

**Priority**: **HIGH** - Enables full dual-backend architecture and cross-platform GUI support.

⸻

## Viewport Widget Architecture (Issue #9)

### Overview

Implement viewport widget with unified class(*) interface for pan/zoom functionality with cross-backend rendering support, providing immediate-mode view updates and consistent interaction behavior. The viewport widget is a essential component for data visualization and interactive content.

### Core Design Principles

**Unified Interface**: Single viewport() function accepting class(*) dimensions for maximum API simplicity and consistency with other widgets.

**Required Dimensions**: Width and height must be specified (no auto-sizing) to ensure deterministic viewport behavior.

**View State Management**: Direct update of view parameter during interaction with frame-based change detection.

**Cross-Backend Parity**: Consistent viewport behavior in TUI (cell-based) and GUI (pixel-based) with appropriate rendering strategies.

### API Design

#### Viewport Function Signature
```fortran
logical function viewport(id, width, height, view)
  character(*), intent(in) :: id
  class(*), intent(in) :: width, height     ! any unit type or real
  type(view), intent(inout) :: view         ! wheel=zoom, drag=pan
  ! returns .true. if view changed this frame
end function
```

#### View Type Definition
```fortran
type :: view
  real :: scale_x = 1.0, scale_y = 1.0  ! zoom factors
  real :: off_x = 0.0, off_y = 0.0      ! pan offsets in view coordinates
end type
```

#### Usage Examples
```fortran
! Simple viewport with cell units (TUI-friendly)
if (viewport("plot", 80.0 .cw., 24.0 .ch., plot_view)) then
  call redraw_plot_content()
end if

! Viewport with dp units (cross-backend)
if (viewport("chart", 400.0, 300.0, chart_view)) then
  call update_chart_display()
end if

! Mixed unit viewport
if (viewport("mini", 20.0 .em., 15.0 .em., mini_view)) then
  call render_minimap()
end if
```

### Implementation Architecture

#### Size Processing with class(*)
```fortran
subroutine process_viewport_size(width_arg, height_arg, ctx, w_dp, h_dp)
  class(*), intent(in) :: width_arg, height_arg
  type(ui_context), intent(in) :: ctx
  real, intent(out) :: w_dp, h_dp
  
  ! Convert to dp using runtime type checking
  w_dp = convert_to_dp(width_arg, ctx)
  h_dp = convert_to_dp(height_arg, ctx)
  
  ! Ensure minimum size
  w_dp = max(w_dp, MIN_VIEWPORT_WIDTH_DP)
  h_dp = max(h_dp, MIN_VIEWPORT_HEIGHT_DP)
end subroutine
```

#### Interaction State Management
```fortran
type :: viewport_state
  logical :: dragging = .false.
  real :: drag_start_x, drag_start_y
  real :: last_mouse_x, last_mouse_y
  logical :: hovered = .false.
  integer :: frame_last_changed = 0
end type

! State storage by ID
type(viewport_state), allocatable, save :: viewport_states(:)
character(len=256), allocatable, save :: viewport_ids(:)
integer, save :: viewport_count = 0
```

#### Mouse Interaction Handling
```fortran
subroutine handle_viewport_interaction(id, bounds, view, changed)
  character(*), intent(in) :: id
  type(rect), intent(in) :: bounds
  type(view), intent(inout) :: view
  logical, intent(out) :: changed
  
  type(viewport_state), pointer :: state
  real :: mouse_x, mouse_y
  logical :: mouse_down
  real :: wheel_delta
  
  ! Get or create state
  state => get_viewport_state(id)
  changed = .false.
  
  ! Get mouse position
  call get_mouse_position(mouse_x, mouse_y)
  state%hovered = point_in_rect(mouse_x, mouse_y, bounds)
  
  if (state%hovered) then
    ! Handle zoom (mouse wheel)
    wheel_delta = get_mouse_wheel_delta()
    if (abs(wheel_delta) > 0.001) then
      ! Zoom centered on mouse position
      call apply_zoom(view, wheel_delta, mouse_x - bounds%x, mouse_y - bounds%y)
      changed = .true.
    end if
    
    ! Handle pan (mouse drag)
    mouse_down = is_mouse_button_down(MOUSE_LEFT)
    
    if (mouse_down .and. .not. state%dragging) then
      ! Start drag
      state%dragging = .true.
      state%drag_start_x = mouse_x
      state%drag_start_y = mouse_y
    else if (state%dragging .and. mouse_down) then
      ! Continue drag
      view%off_x = view%off_x + (mouse_x - state%last_mouse_x) / view%scale_x
      view%off_y = view%off_y + (mouse_y - state%last_mouse_y) / view%scale_y
      changed = .true.
    else if (state%dragging .and. .not. mouse_down) then
      ! End drag
      state%dragging = .false.
    end if
  end if
  
  state%last_mouse_x = mouse_x
  state%last_mouse_y = mouse_y
  
  if (changed) then
    state%frame_last_changed = get_frame_count()
  end if
end subroutine
```

### Backend-Specific Rendering

#### TUI Viewport Rendering
```fortran
subroutine render_viewport_tui(id, x, y, width, height, view)
  character(*), intent(in) :: id
  integer, intent(in) :: x, y, width, height
  type(view), intent(in) :: view
  
  ! Draw border
  call draw_box_tui(x, y, width, height)
  
  ! Draw viewport info in corner
  character(len=32) :: info
  write(info, '("Z:", F4.2, " P:", I3, ",", I3)') &
    view%scale_x, int(view%off_x), int(view%off_y)
  call draw_text_tui(x + 1, y, info)
  
  ! Set clipping region for content
  call set_clip_region_tui(x + 1, y + 1, width - 2, height - 2)
  
  ! Content rendered by caller with transformed coordinates
end subroutine
```

#### GUI Viewport Rendering
```fortran
subroutine render_viewport_gui(id, x, y, width, height, view)
  character(*), intent(in) :: id
  real, intent(in) :: x, y, width, height
  type(view), intent(in) :: view
  
  ! Draw viewport background
  call DrawRectangle(int(x), int(y), int(width), int(height), LIGHTGRAY)
  
  ! Draw border
  call DrawRectangleLines(int(x), int(y), int(width), int(height), DARKGRAY)
  
  ! Enable scissor mode for clipping
  call BeginScissorMode(int(x), int(y), int(width), int(height))
  
  ! Apply transformation matrix
  call rlPushMatrix()
  call rlTranslatef(x + view%off_x, y + view%off_y, 0.0)
  call rlScalef(view%scale_x, view%scale_y, 1.0)
  
  ! Content rendered by caller
end subroutine

subroutine end_viewport_gui()
  call rlPopMatrix()
  call EndScissorMode()
end subroutine
```

### Coordinate Transformation

#### View-to-Screen Transformation
```fortran
subroutine view_to_screen(view, bounds, vx, vy, sx, sy)
  type(view), intent(in) :: view
  type(rect), intent(in) :: bounds
  real, intent(in) :: vx, vy  ! view coordinates
  real, intent(out) :: sx, sy ! screen coordinates
  
  sx = bounds%x + (vx + view%off_x) * view%scale_x
  sy = bounds%y + (vy + view%off_y) * view%scale_y
end subroutine

subroutine screen_to_view(view, bounds, sx, sy, vx, vy)
  type(view), intent(in) :: view
  type(rect), intent(in) :: bounds
  real, intent(in) :: sx, sy  ! screen coordinates
  real, intent(out) :: vx, vy ! view coordinates
  
  vx = (sx - bounds%x) / view%scale_x - view%off_x
  vy = (sy - bounds%y) / view%scale_y - view%off_y
end subroutine
```

### Integration with Widget System

#### Viewport Node Type
```fortran
type, extends(ui_element) :: viewport_node_t
  character(len=256) :: id
  real :: width_dp, height_dp
  type(view) :: view
  logical :: changed
  
  ! Content rendering callback
  procedure(render_content_interface), pointer :: render_content => null()
end type
```

#### Example: Plot with Viewport
```fortran
program plot_example
  use fortui
  implicit none
  
  type(view) :: plot_view
  real :: data_x(100), data_y(100)
  integer :: i
  
  ! Generate sample data
  do i = 1, 100
    data_x(i) = real(i - 1) * 0.1
    data_y(i) = sin(data_x(i))
  end do
  
  call ui_init("auto", 80.0 .cw., 24.0 .ch., "Plot Viewer")
  
  do while (.not. ui_should_close())
    call ui_frame_begin()
    
    ! Viewport for plot
    if (viewport("plot", 70.0 .cw., 20.0 .ch., plot_view)) then
      ! View changed, update if needed
    end if
    
    ! Render plot content with transformation
    call render_plot(plot_view, data_x, data_y)
    
    ! Controls
    if (button("reset", "Reset View")) then
      plot_view = view()  ! Reset to default
    end if
    
    call ui_present()
  end do
  
  call ui_shutdown()
  
contains
  
  subroutine render_plot(v, x, y)
    type(view), intent(in) :: v
    real, intent(in) :: x(:), y(:)
    integer :: i
    real :: sx1, sy1, sx2, sy2
    
    do i = 1, size(x) - 1
      ! Transform data coordinates to screen
      call view_to_screen(v, viewport_bounds, x(i), y(i), sx1, sy1)
      call view_to_screen(v, viewport_bounds, x(i+1), y(i+1), sx2, sy2)
      
      ! Draw line segment
      call draw_line(sx1, sy1, sx2, sy2)
    end do
  end subroutine
  
end program
```

### Performance Considerations

**Interaction Throttling**: Limit pan/zoom updates to maintain target FPS.

**Dirty Region Tracking**: Only redraw viewport content when view changes.

**Coordinate Caching**: Cache transformed coordinates for static content.

**Level-of-Detail**: Adjust rendering detail based on zoom level.

### Testing Strategy

#### Interaction Testing
```fortran
subroutine test_viewport_zoom()
  type(view) :: test_view
  logical :: changed
  
  ! Initial state
  test_view = view()
  
  ! Simulate wheel zoom
  call simulate_mouse_wheel(1.0)
  changed = viewport("test", 100.0, 100.0, test_view)
  
  call assert_true(changed, "Zoom should trigger change")
  call assert_greater(test_view%scale_x, 1.0, "Zoom in should increase scale")
end subroutine

subroutine test_viewport_pan()
  type(view) :: test_view
  logical :: changed
  
  test_view = view()
  
  ! Simulate drag
  call simulate_mouse_drag(10.0, 10.0, 20.0, 20.0)
  changed = viewport("test", 100.0, 100.0, test_view)
  
  call assert_true(changed, "Pan should trigger change")
  call assert_not_equals(test_view%off_x, 0.0, "Pan should change offset")
end subroutine
```

### Success Criteria

**Core Functionality**:
- [ ] Pan with mouse drag working
- [ ] Zoom with mouse wheel working
- [ ] View state persists between frames
- [ ] Coordinate transformations accurate

**Cross-Backend**:
- [ ] TUI viewport with keyboard controls
- [ ] GUI viewport with smooth interaction
- [ ] Consistent behavior across backends
- [ ] Proper clipping in both modes

**Integration**:
- [ ] Works with all unit types
- [ ] Integrates with existing widgets
- [ ] State management by ID
- [ ] Change detection reliable

**Performance**:
- [ ] No lag during interaction
- [ ] Efficient rendering updates
- [ ] Memory usage reasonable
- [ ] Scales to multiple viewports

### Dependencies

**Required Components**:
- Widget state management system
- Mouse/keyboard input handling  
- Coordinate transformation utilities
- Clipping/scissor support in backends

**Priority**: **HIGH** - Essential for data visualization and interactive applications.

⸻

## Context Architecture Design
### Abstract Type Integration Framework
```fortran
! Core context type with flexible backend integration
type :: ui_context
  ! Display metrics
  real :: dpi_scale = 1.0
  real :: display_width_dp = 800.0
  real :: display_height_dp = 600.0
  
  ! Unit conversion factors
  real :: cell_w_dp = 8.0   ! Terminal cell width in dp
  real :: cell_h_dp = 16.0  ! Terminal cell height in dp
  real :: em_dp = 16.0      ! Em size in dp
  real :: ex_dp = 8.0       ! Ex height in dp
  
  ! Text metrics
  real :: text_scale = 1.0  ! Global text scaling factor
  logical :: proportional = .false.  ! Proportional text mode (future)
  
  ! Backend-specific data (polymorphic)
  class(*), allocatable :: backend_data
end type
```

### Context-Aware Rendering Integration
#### TUI Rendering with Context
```fortran
subroutine render_widget_tui(widget, ctx)
  class(ui_element), intent(in) :: widget
  type(ui_context), intent(in) :: ctx
  
  ! Convert widget dp coordinates to cells
  integer :: cell_x, cell_y, cell_w, cell_h
  
  cell_x = int(widget%x_dp / ctx%cell_w_dp)
  cell_y = int(widget%y_dp / ctx%cell_h_dp)
  cell_w = int(widget%width_dp / ctx%cell_w_dp)
  cell_h = int(widget%height_dp / ctx%cell_h_dp)
  
  ! Render with cell-based positioning
  call draw_widget_cells(cell_x, cell_y, cell_w, cell_h)
end subroutine
```

#### GUI Rendering with Context
```fortran
subroutine render_widget_gui(widget, ctx)
  class(ui_element), intent(in) :: widget
  type(ui_context), intent(in) :: ctx
  
  ! Apply DPI scaling to dp coordinates
  real :: pixel_x, pixel_y, pixel_w, pixel_h
  
  pixel_x = widget%x_dp * ctx%dpi_scale
  pixel_y = widget%y_dp * ctx%dpi_scale
  pixel_w = widget%width_dp * ctx%dpi_scale
  pixel_h = widget%height_dp * ctx%dpi_scale
  
  ! Render with pixel-perfect positioning
  call draw_widget_pixels(pixel_x, pixel_y, pixel_w, pixel_h)
end subroutine
```

### Context Lifecycle Management
#### Runtime Context Updates
```fortran
subroutine update_context_from_environment(ctx)
  type(ui_context), intent(inout) :: ctx
  
  ! Update display metrics
  call get_display_size(ctx%display_width_dp, ctx%display_height_dp)
  ctx%dpi_scale = get_system_dpi() / 96.0
  
  ! Backend-specific updates
  select type(backend => ctx%backend_data)
  type is (tui_context_data)
    ! Measure actual terminal cell dimensions
    call measure_terminal_cell_size(ctx%cell_w_dp, ctx%cell_h_dp)
  type is (gui_context_data)
    ! Update font metrics for current DPI
    ctx%em_dp = get_font_size() * ctx%dpi_scale
  end select
end subroutine
```

#### Context Validation and Error Handling
```fortran
subroutine validate_context(ctx, is_valid)
  type(ui_context), intent(in) :: ctx
  logical, intent(out) :: is_valid
  
  is_valid = .true.
  
  ! Check basic constraints
  if (ctx%dpi_scale <= 0.0 .or. ctx%dpi_scale > 10.0) then
    is_valid = .false.
    call log_error("Invalid DPI scale: " // str(ctx%dpi_scale))
  end if
  
  if (ctx%cell_w_dp <= 0.0 .or. ctx%cell_h_dp <= 0.0) then
    is_valid = .false.
    call log_error("Invalid cell dimensions")
  end if
  
  ! Validate backend-specific data if present
  if (allocated(ctx%backend_data)) then
    ! Backend-specific validation...
  end if
end subroutine
```

⸻

### Architecture Solution: Backend Registry Pattern
Implement a backend abstraction layer using a registration pattern where backends register themselves with the core, rather than core importing backends directly. This eliminates compile-time dependencies and enables runtime backend selection.

#### Implementation Structure
```fortran
! fortui_backend.f90 - Abstract interface all backends must implement
module fortui_backend
  implicit none
  private
  
  public :: backend_interface, register_backend, get_backend
  
  type, abstract :: backend_interface
  contains
    procedure(init_proc), deferred :: init
    procedure(shutdown_proc), deferred :: shutdown
    procedure(render_proc), deferred :: render_tree
    procedure(should_quit_proc), deferred :: should_quit
  end type
  
  ! Backend registry
  type(backend_entry), allocatable :: registry(:)
  integer :: backend_count = 0
  
contains
  subroutine register_backend(name, backend)
    ! Backends self-register at startup
  end subroutine
end module

! fortui_tui.f90 - TUI backend self-registers
module fortui_tui
  use fortui_backend
  type, extends(backend_interface) :: tui_backend
    ! Implementation
  end type
  
  ! Self-registration on module load
  logical :: registered = register_tui()
  
contains
  function register_tui() result(success)
    type(tui_backend) :: backend
    call register_backend("tui", backend)
    success = .true.
  end function
end module
```

⸻

## minimal api (v0.4.0)

## 1) types

```fortran
type :: view
  real :: scale_x=1, scale_y=1  ! zoom
  real :: off_x=0, off_y=0      ! pan (view coords)
end type
```

⸻

## 2) procedures

**lifecycle**: `ui_init ui_shutdown ui_frame_begin ui_present ui_should_close`  
**layout**: `row() column()` with `class(*)` width/height  
**widgets**: `button(id,label?) slider(id,val,lo,hi) checkbox(id,checked) text(id,str)`  
**viewport**: `viewport(id,w,h,view)` → `.true.` if view changed

⸻

## 3) example

```fortran
program demo
  use fortui
  type(view) :: v
  real :: g=0.5
  logical :: show=.false.
  character(256) :: s

  call ui_init  ! auto-selects backend

  do while (.not.ui_should_close())
    call ui_frame_begin

    ! ui tree
    n = column(20.dp(), [                      &
      slider("gain", g, 0., 1.),               &
      checkbox("grid", show),                  &
      row(100.pct(), [                         &
        button("reset"),                        &
        button("quit")                          &
      ]),                                       &
      viewport("vp", 100.pct(), 15.ch(), v),   &
      text("info", info_str())                 &
    ])

    call ui_present(n)

    ! actions
    if (button("reset")) v=view()
    if (button("quit")) exit
  end do

  call ui_shutdown

contains
  function info_str() result(s)
    character(256) :: s, buf
    write(buf,'("gain=",F4.2,"  scale=(",F4.2,",",F4.2,")  off=(",F5.1,",",F5.1,")  grid=",L1)') &
      g, v%scale_x, v%scale_y, v%off_x, v%off_y, show
    s=trim(buf)
  end
end program
```

**note**: each widget call is the single source of truth.
- **slider** updates gain directly.
- **checkbox** toggles grid.
- **viewport** updates v.
- Only **button** needs an if to trigger actions.
- All units automatically convert to dp for consistent backend behavior.

⸻

## 4) backend behavior

### gui (raygui/raylib)
- **vsync**=.true (default), **target_fps** (default 60; 120 ok).
- **steady** mode (default) or **adaptive** idle via ui_set_idle_policy.
- **units**: dp → pixels via ui_context (dpi_scale, em_dp, text_scale)
- **precision**: subpixel positioning and rendering
- **context setup**: auto-detect system DPI, font metrics

### tui (termbox2)
- **event-driven**: idle 250–1000 ms; coalesce 10–20 ms; dragging 16–33 ms.
- front/back cell buffers; per-line hashes; run diffs; coalesced writes.
- sgr1006 mouse; bracketed paste.
- **units**: dp → cells via ui_context (cell_w_dp, cell_h_dp)
- **snapping**: automatic snap to cell boundaries (integer coordinates)
- **context setup**: measure terminal cell dimensions

⸻

## 5) future work (kept open)
- **proportional text** (gui opt-in): ui_init(..., proportional=.true.), measure_text.
- **2d canvas** (tui+gui): canvas2d_begin/end, line/rect/polyline/text_at/image_gray, transform hook; basis for show().
- **3d canvas** (gui first): canvas3d_begin/end, tri_mesh/lines3d/bbox; optional ascii 3d later.
- **show()** (matplotlib-like): figure/axes model, modal/non-modal; uses canvases.
- **layout enrichment**: alignment, spacer(flex), padding/margin, theme tokens.
- **text input/listbox**: single-line editor, list selection.

⸻

## 6) invariants
- **small, stable public api**.
- **ids** own per-widget retained state.
- **tui** minimizes writes; **gui** respects target fps.
- **monospace** baseline; proportional is additive.

⸻

## 7) Global State Refactoring Architecture (Issue #64)

### Problem Analysis
The current architecture uses extensive global mutable state throughout the codebase:
- **fortui_core**: `ui_state` (ui_state_t), `tui_state` (tui_state_t) 
- **fortui_tui**: Backend-specific state embedded in module
- **fortui_gui**: `gui_state` (gui_backend_t)
- **fortui_widgets**: Multiple widget states with SAVE attributes
- **fortui_units**: `global_context` (ui_context)
- **fortui_platform_measurement**: Context caching with SAVE

This creates critical issues:
1. **Thread safety**: No synchronization, concurrent access unsafe
2. **Reentrancy**: Cannot have multiple UI instances
3. **Testing**: State bleeds between tests, causes flakiness
4. **Hidden dependencies**: Functions implicitly depend on global state
5. **Architectural violations**: Breaks SRP, no dependency injection

### Architecture Solution: Context Object Pattern

#### Phase 1: Context Encapsulation Design
Create a unified context object that encapsulates all mutable state:

```fortran
! fortui_context.f90 - New module for context management
module fortui_context
  use fortui_backend
  use fortui_units
  implicit none
  private
  
  ! Public types
  public :: fortui_context_t, create_context, destroy_context
  public :: get_default_context, set_default_context
  
  ! Master context object containing all state
  type :: fortui_context_t
    ! Core state
    logical :: initialized = .false.
    character(len=32) :: active_backend = ""
    class(backend_interface), pointer :: backend => null()
    
    ! Window/display state
    integer :: window_width = 80
    integer :: window_height = 24
    character(len=256) :: window_title = "Fortui"
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    
    ! Unit system context
    type(ui_context) :: units
    
    ! Backend-specific state (polymorphic)
    class(*), allocatable :: backend_state
    
    ! Widget state storage (hash table for scalability)
    type(widget_state_map) :: widget_states
    
    ! Frame state
    logical :: in_frame = .false.
    integer :: frame_count = 0
    logical :: should_quit = .false.
    
    ! Thread safety
    integer :: lock_count = 0  ! For recursive locking if needed
  contains
    procedure :: init => context_init
    procedure :: shutdown => context_shutdown
    procedure :: begin_frame => context_begin_frame
    procedure :: end_frame => context_end_frame
    procedure :: is_valid => context_is_valid
  end type fortui_context_t
  
  ! Widget state map for efficient lookup
  type :: widget_state_map
    type(widget_state_entry), allocatable :: entries(:)
    integer :: count = 0
    integer :: capacity = 0
  contains
    procedure :: get => map_get_state
    procedure :: set => map_set_state
    procedure :: clear => map_clear
  end type widget_state_map
  
  ! Individual widget state entry
  type :: widget_state_entry
    character(len=256) :: id
    class(*), allocatable :: state
  end type widget_state_entry
  
  ! Thread-local default context (for backward compatibility)
  type(fortui_context_t), pointer :: default_context => null()
  !$OMP THREADPRIVATE(default_context)
  
contains
  
  ! Create a new context instance
  function create_context() result(ctx)
    type(fortui_context_t), pointer :: ctx
    
    allocate(ctx)
    ctx%initialized = .false.
    ctx%widget_states%capacity = 64
    allocate(ctx%widget_states%entries(ctx%widget_states%capacity))
  end function
  
  ! Destroy a context and free resources
  subroutine destroy_context(ctx)
    type(fortui_context_t), pointer :: ctx
    
    if (.not. associated(ctx)) return
    
    if (ctx%initialized) then
      call ctx%shutdown()
    end if
    
    call ctx%widget_states%clear()
    if (allocated(ctx%backend_state)) deallocate(ctx%backend_state)
    
    deallocate(ctx)
    ctx => null()
  end subroutine
  
end module fortui_context
```

#### Phase 2: API Migration Strategy

##### Option A: Explicit Context Passing (Recommended)
All functions accept an optional context parameter, using thread-local default if not provided:

```fortran
! Updated fortui_core API
module fortui_core
  use fortui_context
  implicit none
  
  ! Lifecycle with explicit context
  interface ui_init
    module procedure ui_init_default
    module procedure ui_init_with_context
  end interface
  
contains
  
  ! Initialize with default context (backward compatible)
  subroutine ui_init_default(backend, width, height, title)
    character(*), intent(in) :: backend
    real, intent(in) :: width, height
    character(*), intent(in) :: title
    
    type(fortui_context_t), pointer :: ctx
    
    ! Get or create default context
    ctx => get_default_context()
    if (.not. associated(ctx)) then
      ctx => create_context()
      call set_default_context(ctx)
    end if
    
    call ui_init_with_context(ctx, backend, width, height, title)
  end subroutine
  
  ! Initialize with explicit context (new API)
  subroutine ui_init_with_context(ctx, backend, width, height, title)
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: backend
    real, intent(in) :: width, height
    character(*), intent(in) :: title
    
    ! Implementation works on provided context
    call ctx%init(backend, width, height, title)
  end subroutine
  
end module fortui_core

! Updated widget API
module fortui_widgets
  use fortui_context
  implicit none
  
  ! Widgets with optional context
  interface button
    module procedure button_default
    module procedure button_with_context
  end interface
  
contains
  
  logical function button_default(id, label) result(clicked)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    
    if (associated(ctx)) then
      clicked = button_with_context(ctx, id, label)
    else
      clicked = .false.
    end if
  end function
  
  logical function button_with_context(ctx, id, label) result(clicked)
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    
    type(button_state), pointer :: state
    
    ! Get or create widget state from context
    state => ctx%widget_states%get(id, "button")
    if (.not. associated(state)) then
      allocate(state)
      state%pressed = .false.
      state%hover = .false.
      call ctx%widget_states%set(id, "button", state)
    end if
    
    ! Widget implementation using context state
    ! ...
  end function
  
end module fortui_widgets
```

##### Option B: Handle-Based Context Management
Use opaque handles for contexts, maintaining full encapsulation:

```fortran
module fortui_context_manager
  use iso_c_binding
  implicit none
  
  ! Opaque handle type
  type :: fortui_handle
    private
    integer :: id = -1
  end type fortui_handle
  
  ! Invalid handle constant
  type(fortui_handle), parameter :: FORTUI_INVALID_HANDLE = fortui_handle(-1)
  
  interface
    ! Context management
    function fortui_create_context() result(handle)
      type(fortui_handle) :: handle
    end function
    
    subroutine fortui_destroy_context(handle)
      type(fortui_handle), intent(in) :: handle
    end subroutine
    
    ! Operations on contexts
    subroutine fortui_init(handle, backend, width, height, title)
      type(fortui_handle), intent(in) :: handle
      character(*), intent(in) :: backend
      real, intent(in) :: width, height
      character(*), intent(in) :: title
    end subroutine
  end interface
  
end module fortui_context_manager
```

#### Phase 3: Backend State Encapsulation

Each backend maintains its state within the context:

```fortran
! Updated TUI backend
module fortui_tui
  use fortui_backend
  use fortui_context
  implicit none
  
  type, extends(backend_interface) :: tui_backend_t
    ! No module-level state!
  contains
    procedure :: init => tui_init
    procedure :: shutdown => tui_shutdown
    procedure :: begin_frame => tui_begin_frame
    procedure :: render => tui_render
  end type tui_backend_t
  
  ! TUI-specific state stored in context
  type :: tui_backend_state_t
    logical :: initialized = .false.
    integer :: terminal_width = 0
    integer :: terminal_height = 0
    logical :: mouse_enabled = .false.
    logical :: bracketed_paste = .false.
    logical :: using_real_termbox = .false.
    ! Cell buffers, etc.
  end type tui_backend_state_t
  
contains
  
  subroutine tui_init(self, ctx, width, height, title)
    class(tui_backend_t), intent(inout) :: self
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    
    type(tui_backend_state_t), pointer :: state
    
    ! Allocate backend-specific state in context
    if (.not. allocated(ctx%backend_state)) then
      allocate(tui_backend_state_t :: ctx%backend_state)
    end if
    
    ! Get typed reference to state
    select type(s => ctx%backend_state)
    type is (tui_backend_state_t)
      state => s
    end select
    
    ! Initialize using context-stored state
    state%initialized = .true.
    state%terminal_width = width
    state%terminal_height = height
    ! ... rest of initialization
  end subroutine
  
end module fortui_tui
```

#### Phase 4: Implementation Plan

##### Step 1: Create Context Module (Non-Breaking)
1. Implement `fortui_context.f90` with full context management
2. Add thread-local default context support
3. Create context lifecycle functions
4. Add widget state map implementation

##### Step 2: Update Core Module (Backward Compatible)
1. Add context-aware versions of all functions
2. Keep existing functions as wrappers using default context
3. Migrate internal state to context object
4. Update backend interface to accept context

##### Step 3: Migrate Backends (Incremental)
1. Update TUI backend to use context state
2. Update GUI backend to use context state
3. Remove all module-level SAVE variables
4. Test each backend independently

##### Step 4: Update Widgets (Gradual)
1. Add context-aware widget functions
2. Migrate widget state to context storage
3. Keep backward compatibility layer
4. Update examples to show both APIs

##### Step 5: Testing and Validation
1. Create multi-context test suite
2. Test thread safety with OpenMP
3. Verify no state leakage between contexts
4. Performance benchmarking

#### Phase 5: Migration Examples

##### Single Context (Backward Compatible)
```fortran
program single_ui
  use fortui
  implicit none
  
  ! Works exactly as before - uses default context
  call ui_init("tui", 80.0, 24.0, "My App")
  
  do while (.not. ui_should_close())
    call ui_frame_begin()
    
    if (button("quit", "Exit")) exit
    
    call ui_present()
  end do
  
  call ui_shutdown()
end program
```

##### Multiple Contexts (New Capability)
```fortran
program multi_window
  use fortui
  use fortui_context
  implicit none
  
  type(fortui_context_t), pointer :: ctx1, ctx2
  
  ! Create two independent UI contexts
  ctx1 => create_context()
  ctx2 => create_context()
  
  ! Initialize different backends/windows
  call ui_init_with_context(ctx1, "tui", 80.0, 24.0, "Terminal UI")
  call ui_init_with_context(ctx2, "gui", 640.0, 480.0, "Graphical UI")
  
  ! Run both UIs (would need threading in practice)
  do while (.not. ctx1%should_quit .and. .not. ctx2%should_quit)
    ! Update first context
    call ctx1%begin_frame()
    if (button_with_context(ctx1, "quit1", "Exit TUI")) ctx1%should_quit = .true.
    call ctx1%end_frame()
    
    ! Update second context
    call ctx2%begin_frame()
    if (button_with_context(ctx2, "quit2", "Exit GUI")) ctx2%should_quit = .true.
    call ctx2%end_frame()
  end do
  
  ! Clean up
  call destroy_context(ctx1)
  call destroy_context(ctx2)
end program
```

##### Thread-Safe Parallel UI
```fortran
program parallel_ui
  use fortui
  use fortui_context
  use omp_lib
  implicit none
  
  integer :: thread_id
  type(fortui_context_t), pointer :: contexts(4)
  
  ! Create contexts for each thread
  do thread_id = 1, 4
    contexts(thread_id) => create_context()
  end do
  
  !$OMP PARALLEL PRIVATE(thread_id)
  thread_id = omp_get_thread_num() + 1
  
  ! Each thread has its own UI context
  call ui_init_with_context(contexts(thread_id), "tui", &
                            80.0, 24.0, "Thread " // char(thread_id + 48))
  
  do while (.not. contexts(thread_id)%should_quit)
    call contexts(thread_id)%begin_frame()
    
    ! Thread-safe widget calls
    if (button_with_context(contexts(thread_id), "quit", "Exit")) then
      contexts(thread_id)%should_quit = .true.
    end if
    
    call contexts(thread_id)%end_frame()
  end do
  
  call contexts(thread_id)%shutdown()
  !$OMP END PARALLEL
  
  ! Clean up
  do thread_id = 1, 4
    call destroy_context(contexts(thread_id))
  end do
end program
```

### Success Criteria

**Architecture Goals**:
- [ ] All global state encapsulated in context objects
- [ ] No module-level SAVE variables remain
- [ ] Thread-safe operation with multiple contexts
- [ ] Full backward compatibility maintained
- [ ] Zero performance regression

**Testing Requirements**:
- [ ] Multi-context test suite passes
- [ ] Thread safety verified with OpenMP tests
- [ ] No state leakage between contexts
- [ ] Memory leak detection clean
- [ ] Performance within 5% of original

**Implementation Milestones**:
1. [ ] Context module implemented and tested
2. [ ] Core module migrated with compatibility layer
3. [ ] TUI backend uses context state
4. [ ] GUI backend uses context state
5. [ ] All widgets migrated to context storage
6. [ ] Examples updated to demonstrate new capabilities
7. [ ] Documentation updated with context patterns

### Risk Mitigation

**Backward Compatibility**:
- Maintain default context with thread-local storage
- All existing APIs continue to work unchanged
- Gradual opt-in to explicit context passing
- Deprecation warnings for future removal

**Performance Concerns**:
- Widget state lookup optimized with hash table
- Context pointer passing has minimal overhead
- Lazy allocation of backend-specific state
- Profile-guided optimization after implementation

**Testing Strategy**:
- Parallel test execution to catch race conditions
- Valgrind/AddressSanitizer for memory safety
- Automated regression testing for all examples
- Stress testing with many contexts/widgets