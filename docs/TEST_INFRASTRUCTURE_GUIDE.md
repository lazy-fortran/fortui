# Test Infrastructure Developer Guide

**ULTRA-CONCISE guide for using the enhanced test validation infrastructure.**

## Test Infrastructure Overview

**440+ comprehensive validations** across core functionality with **systematic restoration validation** for disabled tests.

## Core Test Infrastructure Components

### Test Runner Integration

```fortran
! Enhanced test/check.f90 with restoration validation
call run_fortran_tests()        ! Core functionality tests
call run_build_script_tests()   ! Build system validation
call run_test_restoration_tests()  ! Issue #87 restoration infrastructure
```

### Test Categories and Coverage

```fortran
! Core functionality (440+ validations)
use test_core_types           ! 17 validations: node/view lifecycle
use test_lifecycle_functions  ! 18 validations: ui_init/shutdown cycles
use test_units_system        ! 15 validations: dp/em/sp conversion
use test_layout_constructors ! 12 validations: column/row creation
use test_tui_backend         ! 87 validations: termbox2 integration

! Widget system (restored)
use test_widgets             ! Widget immediate-mode API testing
use test_viewport_widget     ! Viewport pan/zoom functionality

! Backend system (restored)  
use test_gui_backend         ! GUI backend rendering pipeline
use test_demo_application    ! Demo application scenarios
use test_demo_integration    ! Cross-backend integration

! Infrastructure validation (Issue #87)
use test_restoration_infrastructure      ! Core restoration validation
use test_build_dependency_validation    ! Build system dependencies
use test_disabled_test_restoration      ! Individual test restoration
use test_coverage_gap_assessment        ! Coverage analysis
use test_ci_integration_validation      ! CI/CD integration
```

## Test Writing Patterns

### Immediate-Mode Widget Testing

```fortran
! Test pattern for immediate-mode widgets
module test_my_widget
use fortui_widgets, only: button, slider, checkbox
implicit none

! Widget state tracking for tests
type :: widget_test_state_t
    logical :: clicked = .false.
    logical :: hovered = .false.
    integer :: interaction_count = 0
end type widget_test_state_t

contains

subroutine test_my_widget_interactions()
    type(widget_test_state_t) :: state
    logical :: result
    
    ! Test immediate-mode interaction
    result = button("test_widget", "Test Button")
    if (result) then
        state%clicked = .true.
        state%interaction_count = state%interaction_count + 1
    end if
    
    ! Validate state changes
    if (.not. state%clicked) then
        print *, "FAILED: Widget interaction not detected"
        stop 1
    end if
    
    print *, "✓ Widget interaction validated"
end subroutine test_my_widget_interactions

end module test_my_widget
```

### Mathematical Validation Pattern

```fortran
! Mathematical validation with tolerance checking
subroutine test_unit_conversion()
    real, parameter :: TOLERANCE = 1.0e-6
    real :: expected, actual
    
    ! Test conversion formula
    expected = 16.0 * 1.5  ! em_value * em_dp
    actual = convert_to_dp(em(16.0), context)
    
    if (abs(actual - expected) > TOLERANCE) then
        print *, "FAILED: Conversion error:", actual, "expected", expected
        stop 1
    end if
    
    print *, "✓ Unit conversion validated with precision"
end subroutine test_unit_conversion
```

### State Transition Validation

```fortran
! State transition testing pattern
subroutine test_lifecycle_states()
    logical :: initial_state, final_state
    
    ! Capture initial state
    initial_state = ui_state%initialized
    
    ! Perform state transition
    call ui_init("tui", 80, 24, "Test")
    
    ! Validate state change
    final_state = ui_state%initialized
    if (initial_state .eqv. final_state) then
        print *, "FAILED: State transition not detected"
        stop 1
    end if
    
    call ui_shutdown()
    print *, "✓ State transition validated"
end subroutine test_lifecycle_states
```

## Test Infrastructure Utilities

### Test State Management

```fortran
! Widget test state tracking (from test_widgets.f90)
type :: button_test_state_t
    logical :: clicked = .false.
    logical :: hovered = .false.
    logical :: active = .false.
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    integer :: click_count = 0
end type button_test_state_t

! Global state storage for test scenarios
type(button_test_state_t), save :: test_button_states(100)
integer, save :: state_count = 0
```

### Backend Simulation Support

```fortran
! Backend simulation for testing (from restored tests)
subroutine simulate_backend_interaction(widget_id, interaction_type)
    character(*), intent(in) :: widget_id
    character(*), intent(in) :: interaction_type
    
    ! Simulate user interaction for testing
    select case (interaction_type)
    case ("click")
        call simulate_mouse_click(widget_id)
    case ("hover") 
        call simulate_mouse_hover(widget_id)
    case ("key")
        call simulate_key_press(widget_id)
    end select
end subroutine simulate_backend_interaction
```

## Restoration Infrastructure Usage

### Build Dependency Validation

```fortran
! Check if dependencies are available for testing
use test_build_dependency_validation

! Test termbox2 availability
logical :: termbox2_available
call test_termbox2_symbols_available(termbox2_available)

if (.not. termbox2_available) then
    print *, "SKIP: termbox2 not available in test environment"
    return
end if
```

### Coverage Gap Assessment

```fortran
! Analyze test coverage gaps
use test_coverage_gap_assessment

character(len=50) :: coverage_gaps(10)
integer :: gap_count

call identify_coverage_gaps(coverage_gaps, gap_count)

do integer :: i = 1, gap_count
    print *, "Coverage gap:", trim(coverage_gaps(i))
end do
```

### Test Restoration Readiness

```fortran
! Check if tests can be restored
use test_disabled_test_restoration

logical :: can_restore_widgets, can_restore_gui

call check_widget_test_restoration(can_restore_widgets)
call check_gui_backend_restoration(can_restore_gui)

if (can_restore_widgets .and. can_restore_gui) then
    print *, "Ready to restore disabled tests"
else
    print *, "Prerequisites not met for test restoration"
end if
```

## Test Execution Modes

### Full Test Suite

```bash
# Run complete test suite with restoration validation
fpm test

# Expected sections:
# - Core Fortran functionality tests (440+ validations)
# - Build script integration tests
# - Test restoration infrastructure tests (Issue #87)
```

### Targeted Test Execution

```bash
# Run specific test categories (use targeted compilation)
fpm test --target specific_test_module

# For restoration infrastructure specifically:
# Tests are integrated into main test runner
```

### CI/CD Integration

```bash
# Headless test execution (for CI environments)
# Tests automatically detect non-TTY environments
# GUI backend tests skip gracefully when display unavailable
# termbox2 tests handle initialization failures appropriately
```

## Test Quality Standards

### Validation Requirements

**All tests must include:**
- **Actual validation logic** (not placeholder prints)
- **Mathematical verification** where applicable
- **State transition checking** for lifecycle tests
- **Error condition handling** for robustness
- **Cross-backend compatibility** validation

### Test Failure Handling

```fortran
! Proper test failure pattern
if (.not. validation_passes) then
    write(error_unit, '(A,A)') "FAIL: ", error_message
    error stop "Test validation failed"
end if

! Success reporting
print *, "✓ Test category: validated N behaviors"
```

### Performance Test Guidelines

```fortran
! Performance validation example
integer, parameter :: TEST_ITERATIONS = 1000
real :: start_time, end_time, throughput

start_time = cpu_time()
do integer :: i = 1, TEST_ITERATIONS
    call function_under_test()
end do
end_time = cpu_time()

throughput = real(TEST_ITERATIONS) / (end_time - start_time)

if (throughput < MINIMUM_THROUGHPUT) then
    print *, "FAILED: Performance below threshold"
    stop 1
end if
```

## Integration with Restoration Work

**Test infrastructure serves dual purpose:**
1. **Validate current functionality** with 440+ meaningful tests
2. **Guide restoration efforts** with systematic requirement validation

**When adding new tests:**
- Follow immediate-mode API patterns from restored tests
- Use state tracking patterns for widget testing
- Include mathematical validation where applicable
- Add to appropriate test runner integration
- Document test purpose and validation approach

The enhanced test infrastructure provides comprehensive validation while supporting systematic restoration of disabled functionality.