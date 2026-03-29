program run_widget_test
use test_widgets_core
use test_widgets_interaction
use test_widgets_performance
use test_widgets_units
implicit none

print *, "=== Widget System Test Runner ==="
print *, "Testing fortui widget functionality..."
print *, ""

call test_core_widgets()
print *, ""

call test_widget_units()
print *, ""

call test_widget_performance()
print *, ""

call test_widget_interactions()

print *, ""
print *, "=== Widget Test Completed ==="

end program run_widget_test
