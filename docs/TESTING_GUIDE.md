# fortui Test Validation Guide

ULTRA-CONCISE guide for running and understanding the enhanced test validation system with restored test coverage.

## Running Tests

```bash
# Run comprehensive test suite (includes test restoration validation)
fpm test

# Expected output:
# - 440+ core functionality validations
# - Test restoration infrastructure validation (Issue #87)
# - Build system dependency checks
```

## Test Restoration Status (Issue #87)

**4 of 5 disabled tests successfully restored** with comprehensive validation infrastructure.
**Coverage impact**: ~70% of disabled test functionality restored.

**See [TEST_RESTORATION_GUIDE.md](TEST_RESTORATION_GUIDE.md) for complete restoration documentation.**

## Test Coverage

**Core Components (440+ Validations):**
- **Core Types (17)**: `node`/`view` initialization, memory management, backend compatibility
- **Lifecycle (18)**: `ui_init`/shutdown, backend selection, frame management, error handling
- **Units System (15)**: dp/em/sp/px/cw/ch conversion, `class(*)` polymorphism, context management
- **Layout System (12)**: `column()`/`row()` constructors, gap processing, children arrays
- **TUI Backend (87)**: termbox2 integration, event polling, coordinate conversion, cell rendering
- **C Interface (20)**: termbox2 bindings, memory safety, error handling, callback integration

## Key Features

- **Actual Validation**: All tests use real validation logic, not placeholders
- **Edge Cases**: Boundary conditions, parameter validation, error recovery
- **Performance**: 500+ layouts/frame, 1000+ conversions, 20+ nesting levels
- **Memory Safety**: Allocation cycles, leak prevention, corruption detection
- **Cross-Backend**: TUI cell snapping vs GUI subpixel precision

## Test Output Pattern

```
=== TUI Backend Test Suite ===
--- TUI Initialization Tests ---
  ✓ Terminal setup: dimension detection works
  ✓ Terminal mode: SGR1006 mouse tracking enabled
  ✓ Cell buffer: front buffer allocated correctly
✓ TUI initialization tests passed
```

## Adding Your Tests

```fortran
subroutine test_my_component()
  integer :: test_count = 0
  logical :: result
  
  ! Actual validation - NOT placeholder
  result = my_function_works()
  if (.not. result) then
    print *, "  ✗ FAILED: validation failed"
    stop 1
  end if
  test_count = test_count + 1
  
  print *, "  ✓ My component: validated", test_count, "behaviors"
end subroutine
```

## Test Categories

**Validation Levels:**
- **Unit Tests**: Individual functions and types
- **Integration Tests**: Component interactions
- **Performance Tests**: Throughput and memory efficiency
- **Edge Case Tests**: Boundary conditions and error handling
- **Cross-Backend Tests**: TUI/GUI consistency validation

**Coverage Areas:**
- Memory management and safety
- Parameter validation and type checking
- Error handling and recovery
- Performance characteristics
- API contract compliance
- **Test restoration infrastructure** (Issue #87)
- **Build dependency validation**
- **Widget system immediate-mode API compatibility**

## Advanced Test Infrastructure

**For detailed test development and maintenance:**
- **[TEST_INFRASTRUCTURE_GUIDE.md](TEST_INFRASTRUCTURE_GUIDE.md)** - Test writing patterns and infrastructure utilities
- **[TEST_RESTORATION_GUIDE.md](TEST_RESTORATION_GUIDE.md)** - Test restoration process and coverage analysis