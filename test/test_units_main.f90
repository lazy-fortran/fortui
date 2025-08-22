program test_units_main
! Main units test driver - orchestrates all units test modules
! Replaces the oversized test_units_system.f90 with modular structure
use test_units_operators
use test_units_simple
implicit none

print *, "=== Units System Test Suite ==="
print *, "Running modular units tests..."
print *, ""

call test_all_unit_operators()
print *, ""

call test_all_units_simple()
print *, ""

print *, "=== All Units Tests Completed ==="

end program test_units_main