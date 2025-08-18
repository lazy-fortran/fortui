# fortui — design doc (v0.3.2)

## Goal
Declarative UI for modern Fortran, one codebase, two backends:
- **TUI**: termbox2 (event-driven, diffed output).
- **GUI**: raygui/raylib (vsynced, target FPS).

Monospace-first for exact TUI/GUI parity. Proportional text is a future opt-in.

⸻

## 1) public api

### modules

```fortran
use fortui_core      ! init/shutdown, frame, present, pacing, node/view types
use fortui_widgets   ! column/row/viewport + button/slider/checkbox/text
```

### types

```fortran
type :: node
end type

type :: view                 ! pan/zoom for plot areas
  real :: scale_x = 1.0, scale_y = 1.0
  real :: off_x   = 0.0, off_y   = 0.0
end type
```

### lifecycle & pacing

```fortran
subroutine ui_init(backend, width, height, title, target_fps, vsync)
  character(*), intent(in) :: backend        ! "tui" | "gui"
  integer,      intent(in) :: width, height  ! grid units (gu)
  character(*), intent(in) :: title
  integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
  logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
end

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
  character(*), intent(in) :: mode                   ! "steady" | "adaptive"
  integer,      intent(in), optional :: idle_fps     ! e.g., 12
end

subroutine ui_frame_begin(timeout_ms)
  integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
end

subroutine ui_present(tree)
  class(node), intent(in) :: tree
end

logical function ui_should_close()
end

subroutine ui_shutdown()
end
```

### layout constructors

```fortran
function column(gap, children) result(n)
  integer,     intent(in), optional :: gap
  class(node), intent(in), optional :: children(:)
  type(node) :: n
end

function row(gap, children) result(n)
  integer,     intent(in), optional :: gap
  class(node), intent(in), optional :: children(:)
  type(node) :: n
end
```

### widgets (immediate-mode: declaration = draw = state update)

```fortran
logical function button(id, label)
  character(*), intent(in)           :: id
  character(*), intent(in), optional :: label   ! default: label=id
  ! returns .true. when clicked this frame
end

logical function slider(id, min, max, step, value)
  character(*), intent(in) :: id
  real,         intent(in) :: min, max, step
  real,         intent(inout) :: value
  ! draws slider and updates 'value' if interacted; returns .true. on change
end

subroutine checkbox(id, checked)
  character(*), intent(in) :: id
  logical,      intent(inout) :: checked
  ! toggles 'checked' in place if interacted
end

subroutine text(id, value)
  character(*), intent(in) :: id, value
end

logical function viewport(id, width, height, view)
  character(*), intent(in) :: id
  integer,      intent(in) :: width, height         ! in gu (cells)
  type(view),   intent(inout) :: view               ! wheel=zoom, drag=pan
  ! returns .true. if view changed
end
```

**ids** are stable strings per widget (state keyed by id).
**units**: gu = one terminal cell (tui) = one glyph size (gui).

⸻

## 2) example (single-call style)

```fortran
program demo
  use fortui_core
  use fortui_widgets
  implicit none

  real    :: gain = 1.0
  logical :: grid = .false.
  type(view) :: v
  class(node), allocatable :: ui
  logical :: running

  call ui_init(backend="tui", width=100, height=35, title="plot demo")
  ! gui option: call ui_set_idle_policy("adaptive", idle_fps=12)

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ui = column(gap=1, children=[ &
           row(gap=1, children=[ &
             button("zoom_in"), &
             button("zoom_out", "-"), &
             slider("gain", 0.1, 5.0, 0.1, gain), &
             checkbox("grid", grid) ]), &
           viewport("plot", 80, 24, v), &
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

⸻

## 3) backend behavior

### gui (raygui/raylib)
- **vsync**=.true (default), **target_fps** (default 60; 120 ok).
- **steady** mode (default) or **adaptive** idle via ui_set_idle_policy.
- gu → pixels via monospace metrics.

### tui (termbox2)
- **event-driven**: idle 250–1000 ms; coalesce 10–20 ms; dragging 16–33 ms.
- front/back cell buffers; per-line hashes; run diffs; coalesced writes.
- sgr1006 mouse; bracketed paste.

⸻

## 4) future work (kept open)
- **proportional text** (gui opt-in): ui_init(..., proportional=.true.), measure_text.
- **2d canvas** (tui+gui): canvas2d_begin/end, line/rect/polyline/text_at/image_gray, transform hook; basis for show().
- **3d canvas** (gui first): canvas3d_begin/end, tri_mesh/lines3d/bbox; optional ascii 3d later.
- **show()** (matplotlib-like): figure/axes model, modal/non-modal; uses canvases.
- **layout enrichment**: alignment, spacer(flex), padding/margin, theme tokens.
- **text input/listbox**: single-line editor, list selection.

⸻

## 5) invariants
- **small, stable public api**.
- **ids** own per-widget retained state.
- **tui** minimizes writes; **gui** respects target fps.
- **monospace** baseline; proportional is additive.