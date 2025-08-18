# fortui Project Instructions

## Project Overview
**fortui** is a declarative UI library for modern Fortran with dual backends:
- **TUI**: termbox2-based terminal interface
- **GUI**: raygui/raylib-based graphical interface

**Core Philosophy**: One codebase, exact TUI/GUI parity through monospace-first design.

## Technical Approach

### Architecture Principles
- **Immediate-mode UI**: Declaration = drawing = state update in single call
- **Retained state by ID**: Widgets maintain state keyed by stable string identifiers
- **Dual backend abstraction**: Same API works for both TUI and GUI with backend-specific optimizations
- **Monospace baseline**: Grid units (gu) = terminal cell (TUI) = glyph size (GUI)
- **Performance-first**: TUI minimizes terminal writes via diffing, GUI respects target FPS

### API Design Standards
- **Small, stable public API**: Two modules only (`fortui_core`, `fortui_widgets`)
- **Immediate-mode pattern**: Functions return interaction status, procedures update state in-place
- **Optional parameters**: Sensible defaults, minimal required parameters
- **Consistent naming**: `ui_` prefix for lifecycle, widget names directly

### Code Quality Standards
- **Fortran Best Practices**:
  - Use `typename_t` convention for derived types
  - Prefer allocatable arrays/objects, NEVER manually deallocate
  - Use `move_alloc()` when no copy needed
  - Avoid large stack allocations - use allocatable for large arrays/objects
  - No transfer for allocatables, use subroutines with `intent(out)`
  - Overload assignment operators where appropriate
- **Git Hygiene**: 
  - NEVER use `git add .` or `git add -A`
  - Manually specify files with `git add <file>`
  - NEVER commit binary files, build artifacts, or temporary files
- **Code Style**:
  - 88 character line limit
  - 4-space indentation
  - Self-documenting code, no commented-out code
  - NO defensive programming - clean, straightforward implementation

### Implementation Constraints
- **MVP Focus**: Core functionality first (node types, basic widgets, TUI backend)
- **No feature creep**: Resist unnecessary complexity, implement minimal viable features
- **Performance requirements**:
  - TUI: Event-driven with smart timeouts (idle 250-1000ms, coalesce 10-20ms, dragging 16-33ms)
  - GUI: Respect target FPS (default 60), vsync by default, adaptive idle policy support
- **Cross-platform**: Linux first, extensible to other platforms

### Module Structure
- **fortui_core**: Lifecycle management, types, frame/present cycle
- **fortui_widgets**: Layout containers (column/row/viewport) and controls (button/slider/checkbox/text)
- **Internal modules**: Backend-specific implementations, not exposed to users

### Widget Implementation Pattern
```fortran
! Immediate-mode: function call includes declaration, rendering, and state management
logical function button(id, label)
  character(*), intent(in)           :: id     ! stable identifier for state
  character(*), intent(in), optional :: label  ! display text (default: id)
  ! Implementation stores state by id, renders widget, returns interaction status
end function
```

### State Management
- **ID-based keying**: Each widget maintains state using stable string identifier
- **Immediate updates**: State changes applied directly during widget call
- **View type**: Encapsulates pan/zoom state for viewport widgets

### Backend Considerations
- **TUI (termbox2)**: 
  - Cell-based rendering with front/back buffers
  - Hash-based diff system to minimize terminal writes
  - SGR1006 mouse support, bracketed paste
- **GUI (raygui/raylib)**:
  - Pixel-based rendering mapped from grid units
  - VSync and FPS management
  - Steady or adaptive idle policies

### Testing Strategy
- **Unit tests**: Individual widget functionality and state management
- **Integration tests**: Backend switching, lifecycle management
- **Example programs**: Demonstrate API usage patterns
- **Cross-backend validation**: Ensure TUI/GUI parity

### Documentation Standards
- **API documentation**: Clear function signatures with parameter descriptions
- **Usage examples**: Minimal working examples for each widget
- **Architecture docs**: Backend implementation details for contributors
- **README**: Installation, basic usage, key examples

### Future Architecture Considerations
- **Proportional text**: Optional GUI enhancement with measure_text support
- **Canvas system**: 2D/3D drawing primitives built on core widget system
- **Layout enrichment**: Alignment, padding, themes as additive features
- **Text input**: Single-line editor and list selection widgets

## Development Workflow
1. **TUI backend first**: Establish core patterns with simpler terminal backend
2. **Widget-by-widget**: Implement and test each widget independently
3. **GUI backend**: Port established patterns to graphical backend
4. **Integration testing**: Validate cross-backend consistency
5. **Performance optimization**: Profile and optimize hot paths

## Quality Gates
- All examples compile and run correctly
- TUI and GUI backends produce equivalent visual results
- No memory leaks or stack overflows
- Performance targets met (TUI responsiveness, GUI frame rate)
- Clean public API with stable interface