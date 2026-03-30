# fortui Project Instructions

## Core Philosophy

Pure immediate-mode UI library for modern Fortran. Dual backends: TUI (termbox2) and GUI (raylib).

**Rules:**
1. No object lifecycle - no create/destroy, no widget objects
2. No exposed state - state is internal only, keyed by string ID
3. Simple function calls - `if (button("id", "Label")) then`
4. No OO patterns in public API - no classes, no inheritance, no polymorphism
5. No procedure pointers - use integer dispatch (lfortran compatibility)
6. No class(*) - use flat discriminated unions for internal state

## Architecture (10 modules, ~3200 lines)

```
fortui.f90           Public API re-export
fortui_core.f90      Lifecycle, backend detection/dispatch
fortui_context.f90   Widget state map (flat struct), context types
fortui_render.f90    Color constants (RC_*), backend dispatch flag
fortui_input.f90     Input state, focus tracking, key constants
fortui_layout.f90    Layout stack, node type, column/row constructors
fortui_tui.f90       TUI backend (termbox2 C bindings)
fortui_gui.f90       GUI backend (raylib C bindings, conditional)
fortui_widgets.f90   button, text, slider, checkbox, viewport
fortui_error.f90     Error reporting utility
```

## Build

```bash
fpm build                    # TUI-only (default)
make build-gui               # TUI + GUI (requires raylib)
FORTUI_HEADLESS=1 fpm test   # Run tests in headless mode
```

## Widget State Pattern

Widgets use a flat discriminated union (no polymorphism):
```fortran
idx = ctx%widget_states%ensure(id, KIND_BUTTON)
ctx%widget_states%entries(idx)%hover = hover
```

No `select type`, no `class(*)`, no `allocate(source=)`.

## Backend Dispatch

Integer flag in fortui_render.f90: `render_backend = RENDER_TUI` or `RENDER_GUI`.
Dispatch via `select case` in trampolines. No procedure pointers.

## C Interop (termbox2)

The `tb_event` struct must match C exactly:
- type: `c_int8_t` (1 byte, uint8_t)
- mod: `c_int8_t` (1 byte, uint8_t)
- key: `c_int16_t` (2 bytes, uint16_t)
- ch: `c_int32_t` (4 bytes, uint32_t)
- w,h,x,y: `c_int32_t` (4 bytes each)

`uintattr_t` = `uint16_t` (TB_OPT_ATTR_W=16). Use `c_int16_t` for fg/bg in all tb_set_cell bindings.

## lfortran Compatibility

Target: all modules compile with lfortran for future WASM support. Current status: 9/10 modules compile. Blocker: lfortran/lfortran#10902.

Avoid these Fortran features (lfortran unsupported):
- Procedure pointers
- Abstract interfaces with deferred procedures
- class(*) unlimited polymorphism
- Type extension with extends()

These are OK (lfortran supports):
- Type-bound procedures
- Allocatable components in derived types
- Optional arguments with present()
- iso_c_binding with bind(C)
- select case
