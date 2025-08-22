program test_widgets_main
! Main widget test driver - orchestrates all widget test modules
! Replaces the oversized test_widgets.f90 with modular structure
use test_widgets_core
use test_widgets_units
use test_widgets_performance
use test_widgets_interaction
implicit none

print *, "=== Widget System Test Suite ==="
print *, "Running modular widget tests..."
print *, ""

call test_core_widgets()
print *, ""

call test_widget_units()
print *, ""

call test_widget_performance()
print *, ""

call test_widget_interactions()
print *, ""

print *, "=== All Widget Tests Completed ==="

end program test_widgets_main