# fortui — design doc (v0.6.0)

## Goal
Declarative UI for modern Fortran, one codebase, two backends:
- **TUI**: termbox2 (event-driven, diffed output) - **ALWAYS AVAILABLE**
- **GUI**: raygui/raylib (vsynced, target FPS) - **CONDITIONAL ENHANCEMENT**

Monospace-first for exact TUI/GUI parity. Proportional text is a future opt-in.

## Build System Architecture

### Single Package Design
- One `fortui` package (no submodules)
- Custom build script `tools/build_fortui.sh` handles dependency management
- FPM integration with build-script override and CPP preprocessing
- **Never fails to build** - TUI is always available, GUI only when possible

### Dependency Management
- **GUI Backend**: Uses `lazy-fortran/fortran-raygui` (fetched on demand, not in repo)
- **TUI Backend**: Builds `termbox2.h` from source (fetched on demand, not in repo)
- **Auto-detection**: Probes system for raylib via pkg-config or RAYLIB_ROOT
- **Private cache**: Dependencies built in local cache, not committed to repo

### Conditional Compilation
- **CPP flags**: `#ifdef ENABLE_GUI` for conditional GUI compilation
- **Runtime detection**: Headless environment detection with fallback to TUI
- **Developer controls**:
  - `DISABLE_GUI=1` forces text-only build
  - `RAYLIB_ROOT=/path` uses prebuilt raylib
  - `FRG_URL`, `FRG_REF` override fortran-raygui source
  - `GUI_CACHE=...` controls cache location

### Build Process
1. **Probe system**: Check for raylib libraries and headers
2. **Fetch TUI deps**: Always build termbox2 for TUI backend
3. **Conditional GUI**: Clone and build fortran-raygui only if GUI is possible
4. **Set CPP flags**: Enable GUI compilation only when dependencies available
5. **Compile**: Single package with backend selection at compile time

⸻

## 1) units system

### unit types & ergonomic api

**Core principle**: One declarative UI works on GUI, Web, and TUI with consistent behavior.

**API Design Philosophy**: Prioritize client code readability and ease of use over pure type safety.

**Default Unit Behavior**: Bare `real` values automatically treated as `.dp.` (density-independent pixels) for maximum convenience - no need to write `.dp.` for basic usage.

```fortran
! Ergonomic unit operators returning class(*) for API simplicity
real :: width, gap, text_size, border, cols, rows

width = 40.0 .dp.      ! density-independent pixels
gap = 2.5 .em.         ! relative to base font size  
text_size = 14.0 .sp.  ! scaled pixels (accessibility)
border = 2.0 .px.      ! physical pixels
cols = 10.0 .cw.       ! cell widths (TUI-friendly)
rows = 3.0 .ch.        ! cell heights (TUI-friendly)

! Bare real values automatically default to .dp. for convenience
width = 40.0           ! equivalent to 40.0 .dp.
gap = 2.5 .em.         ! explicit unit overrides default
border = 320.0         ! equivalent to 320.0 .dp.

! Postfix operators return class(*) for maximum API flexibility
! Runtime type checking handles conversion safety
```

### context-aware conversion

All units normalize to **dp** (density-independent pixels) internally:

```fortran
type :: ui_context
  real :: dpi_scale = 1.0    ! GUI: system DPI scale; TUI: 1.0  
  real :: em_dp = 16.0       ! base font size in dp
  real :: text_scale = 1.0   ! accessibility text scaling
  real :: cell_w_dp = 8.0    ! TUI: cell width in dp
  real :: cell_h_dp = 16.0   ! TUI: cell height in dp
end type
```

**Conversion via runtime type checking**:
- `.dp.` values: direct (base unit)
- `.em.` values: `value * ctx%em_dp` 
- `.sp.` values: `value * ctx%text_scale`
- `.px.` values: `value / ctx%dpi_scale`
- `.cw.` values: `value * ctx%cell_w_dp` (TUI)
- `.ch.` values: `value * ctx%cell_h_dp` (TUI)
- Bare real values: treated as value .dp.

**Internal conversion function**:
```fortran
real function convert_to_dp(unit_value, ctx) result(dp_val)
  class(*), intent(in) :: unit_value
  type(ui_context), intent(in) :: ctx
  ! Runtime type checking determines conversion method
end function
```

### cross-backend placement strategy

**TUI snapping**: Final dp values snap to cell boundaries
```fortran
! 42.7 .dp. with cell_w_dp=8.0 → 5.34 cells → snap to 5 cells
real :: dp_value
dp_value = convert_to_dp(42.7 .dp., ctx)
cell_x = nint(dp_value / ctx%cell_w_dp)
```

**GUI/Web precision**: Subpixel positioning maintained
```fortran  
! 42.7 .dp. with dpi_scale=1.5 → 64.05 pixels (exact)
real :: dp_value
dp_value = convert_to_dp(42.7 .dp., ctx)
pixel_x = dp_value * ctx%dpi_scale
```

### mixed unit arguments

All layout and widget functions accept any unit type via class(*) polymorphism:

```fortran
ui = column(gap=1.0 .ch., children=[ &
       row(gap=2.0 .cw., children=[ &
         button("btn1"), &
         viewport("plot", 80.0 .cw., 24.0 .ch., view) ]), &
       text("status", "Mixed units work!") ])
```

**Unit construction syntax**:
- `40.0 .dp.` - density-independent pixels
- `2.5 .em.` - relative to base font size  
- `14.0 .sp.` - scaled pixels (accessibility)
- `320.0 .px.` - physical pixels
- `10.0 .cw.` - cell widths (TUI-friendly)
- `3.0 .ch.` - cell heights (TUI-friendly)
- `42.0` - bare real values treated as 42.0 .dp.

⸻

## 2) public api

### modules

```fortran
use fortui_core      ! init/shutdown, frame, present, pacing, ui_element/node/view types
use fortui_widgets   ! column/row/viewport + button/slider/checkbox/text interfaces
use fortui_units     ! unit types (dp, em, sp, px, cw, ch) and ui_context
```

### types

```fortran
! Abstract UI element hierarchy
type, abstract :: ui_element
end type

type, extends(ui_element) :: node
end type

type :: view                 ! pan/zoom for plot areas
  real :: scale_x = 1.0, scale_y = 1.0
  real :: off_x   = 0.0, off_y   = 0.0
end type

type :: ui_context           ! cross-backend unit conversion
  real :: dpi_scale = 1.0    ! GUI: system DPI scale; TUI: 1.0
  real :: em_dp = 16.0       ! base font size in dp
  real :: text_scale = 1.0   ! accessibility text scaling
  real :: cell_w_dp = 8.0    ! TUI: cell width in dp
  real :: cell_h_dp = 16.0   ! TUI: cell height in dp
end type

! Internal unit type for runtime identification (implementation detail)
type :: unit_value
  real :: value
  character(len=2) :: unit_type  ! "dp", "em", "sp", "px", "cw", "ch"
end type

! Unit operator interfaces returning class(*) for API simplicity
interface operator(.dp.); module procedure make_dp; end interface
interface operator(.em.); module procedure make_em; end interface  
interface operator(.sp.); module procedure make_sp; end interface
interface operator(.px.); module procedure make_px; end interface
interface operator(.cw.); module procedure make_cw; end interface
interface operator(.ch.); module procedure make_ch; end interface
```

### lifecycle & pacing

```fortran
subroutine ui_init(backend, width, height, title, target_fps, vsync)
  character(*), intent(in) :: backend        ! "tui" | "gui"
  class(*), intent(in) :: width, height      ! any unit type (dp, em, sp, px, cw, ch) or real
  character(*), intent(in) :: title
  integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
  logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
end

subroutine ui_get_context(ctx)
  type(ui_context), intent(out) :: ctx
end

subroutine ui_set_context(ctx)
  type(ui_context), intent(in) :: ctx
end

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
  character(*), intent(in) :: mode                   ! "steady" | "adaptive"
  integer,      intent(in), optional :: idle_fps     ! e.g., 12
end

subroutine ui_frame_begin(timeout_ms)
  integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
end

subroutine ui_present(tree)
  class(ui_element), intent(in) :: tree
end

logical function ui_should_close()
end

subroutine ui_shutdown()
end
```

### layout constructors

```fortran
! Layout constructors with abstract UI elements and mixed unit support
function column(gap, children) result(n)
  class(*), intent(in), optional :: gap               ! any unit type or real
  class(ui_element), intent(in), optional :: children(:)
  type(node) :: n
end

function row(gap, children) result(n)
  class(*), intent(in), optional :: gap               ! any unit type or real
  class(ui_element), intent(in), optional :: children(:)
  type(node) :: n
end
```

### widgets (immediate-mode: declaration = draw = state update)

**Unified Interface**: Single widget functions accept class(*) for maximum API simplicity.

```fortran
! Button widget with unified interface
logical function button(id, label, width, height)
  character(*), intent(in) :: id
  character(*), intent(in), optional :: label     ! default: label=id
  class(*), intent(in), optional :: width, height ! any unit type or real
  ! returns .true. when clicked this frame
end function

! Slider widget with unified interface
logical function slider(id, min, max, step, value, width, height)
  character(*), intent(in) :: id
  real, intent(in) :: min, max, step
  real, intent(inout) :: value
  class(*), intent(in), optional :: width, height  ! any unit type or real
  ! draws slider and updates 'value' if interacted; returns .true. on change
end function

! Checkbox widget with unified interface
subroutine checkbox(id, checked, width, height)
  character(*), intent(in) :: id
  logical, intent(inout) :: checked
  class(*), intent(in), optional :: width, height  ! any unit type or real
  ! toggles 'checked' in place if interacted
end subroutine

! Text widget with unified interface
subroutine text(id, value, text_size)
  character(*), intent(in) :: id, value
  class(*), intent(in), optional :: text_size  ! any unit type or real
end subroutine

! Viewport widget with unified interface
logical function viewport(id, width, height, view)
  character(*), intent(in) :: id
  class(*), intent(in) :: width, height            ! any unit type or real
  type(view), intent(inout) :: view                ! wheel=zoom, drag=pan
  ! returns .true. if view changed
end function
```

**ids** are stable strings per widget (state keyed by id).
**units**: All units normalize to dp internally via runtime conversion:
- `40.0 .dp.` - density-independent pixels (base unit)
- `2.5 .em.` - relative to base font size (em_dp * 2.5)
- `14.0 .sp.` - scaled pixels (dp * text_scale)
- `320.0 .px.` - physical pixels (px / dpi_scale)
- `10.0 .cw.` - cell widths (TUI: cw * cell_w_dp)
- `3.0 .ch.` - cell heights (TUI: ch * cell_h_dp)
- `42.0` - bare real values treated as 42.0 .dp. (default)

**Examples of equivalent widget calls**:
```fortran
! These are equivalent:
button("ok", width=120.0)           ! real defaults to dp
button("ok", width=120.0 .dp.)      ! explicit dp

! Mixed usage:
button("ok", width=120.0, height=2.5 .em.)  ! width=dp, height=em
```

**cross-backend placement**:
- **TUI**: snaps to cell boundaries (integer cells)
- **GUI/Web**: subpixel precision maintained

⸻

## 3) example (single-call style)

```fortran
program demo
  use fortui_core
  use fortui_widgets
  implicit none

  real    :: gain = 1.0
  logical :: grid = .false.
  type(view) :: v
  class(ui_element), allocatable :: ui
  logical :: running

  call ui_init(backend="tui", width=100.0 .cw., height=35.0 .ch., title="plot demo")
  ! gui option: call ui_set_idle_policy("adaptive", idle_fps=12)

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ui = column(gap=1.0 .ch., children=[ &
           row(gap=2.0 .cw., children=[ &
             button("zoom_in"), &
             button("zoom_out", "-"), &
             slider("gain", 0.1, 5.0, 0.1, gain), &
             checkbox("grid", grid) ]), &
           viewport("plot", 80.0 .cw., 24.0 .ch., v), &
           text("status", status_line(gain, v, grid)) ])

    ! react to button returns (others already updated their state)
    if (button("zoom_in"))       call zoom(v, 1.2)
    if (button("zoom_out", "-")) call zoom(v, 1.0/1.2)

    call ui_present(ui)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()

contains
  subroutine zoom(v,f); type(view),intent(inout)::v; real,intent(in)::f
    v%scale_x=v%scale_x*f; v%scale_y=v%scale_y*f
  end
  function status_line(g, v, show) result(s)
    real,intent(in)::g; type(view),intent(in)::v; logical,intent(in)::show
    character(len=:),allocatable::s; character(len=96)::buf
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