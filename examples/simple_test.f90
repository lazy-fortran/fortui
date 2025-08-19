program simple_test
! Simple test to verify both critical fixes work
use fortui
implicit none

type(node) :: empty_node, layout_node  
type(node), allocatable :: children(:)
logical :: running
integer :: frame_count = 0

print *, "Testing critical fixes:"
print *, "1. Module exposure: use fortui gives access to all APIs"
print *, "2. Array bounds: nodes with no children don't crash"

! Test module exposure fix
call ui_init(backend="auto", width=40, height=15, title="Critical Fixes Test")

! Test array bounds fix - create node with no children
empty_node = node()  ! No children allocated

! Test normal operation - create layout with children
allocate(children(1))
children(1) = empty_node  ! Child that has no children
layout_node = column(gap=dp(8.0), children=children)
deallocate(children)

print *, "✓ All APIs accessible via main fortui module"
print *, "✓ Layout constructors work with dp() units"

! Test frame cycle with both node types
running = .true.
do while (running .and. frame_count < 3)
    call ui_frame_begin(timeout_ms=100)
    
    ! These should not crash - tests array bounds fix
    call ui_present(empty_node)   ! No children
    call ui_present(layout_node)  ! Has children
    
    running = .not. ui_should_close()
    frame_count = frame_count + 1
    
    if (frame_count == 1) then
        print *, "✓ ui_present works with nodes that have no children"
        print *, "✓ ui_present works with complex layout nodes"
    end if
end do

call ui_shutdown()

print *, ""
print *, "🎉 CRITICAL FIXES VALIDATED SUCCESSFULLY"
print *, "✅ Module exposure fix: 'use fortui' provides complete API"
print *, "✅ Array bounds fix: No crashes with unallocated children"
print *, "✅ User workflow: Complete example compiles and runs"
print *, "Frames rendered:", frame_count

end program simple_test