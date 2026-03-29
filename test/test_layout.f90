module test_layout
! Tests for immediate-mode cursor-based layout positioning
use fortui_layout
implicit none

contains

subroutine test_all_layout()
    print *, "=== Layout Positioning Test Suite ==="

    call test_layout_reset()
    call test_default_vertical_stacking()
    call test_column_with_gap()
    call test_row_no_gap()
    call test_row_with_gap()
    call test_nested_column_in_row()
    call test_nested_row_in_column()
    call test_no_gap_on_first_item()
    call test_multiple_items_row()
    call test_deep_nesting()

    print *, "All layout positioning tests passed"
    print *, ""
end subroutine test_all_layout

subroutine test_layout_reset()
    real :: x, y

    call layout_reset()
    call layout_get_cursor(x, y)

    if (abs(x) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: reset cursor should be (0,0), got", x, y
        stop 1
    end if

    if (layout_get_depth() /= 1) then
        print *, "  FAILED: reset depth should be 1, got", &
            layout_get_depth()
        stop 1
    end if

    print *, "  ✓ layout_reset: cursor at (0,0), depth=1"
end subroutine test_layout_reset

subroutine test_default_vertical_stacking()
    real :: x, y

    call layout_reset()

    call layout_advance(10.0, 1.0)
    call layout_get_cursor(x, y)

    if (abs(x) > 1e-6 .or. abs(y - 1.0) > 1e-6) then
        print *, "  FAILED: after first item cursor should be (0,1), got", &
            x, y
        stop 1
    end if

    call layout_advance(8.0, 1.0)
    call layout_get_cursor(x, y)

    if (abs(x) > 1e-6 .or. abs(y - 2.0) > 1e-6) then
        print *, "  FAILED: after second item cursor should be (0,2), got", &
            x, y
        stop 1
    end if

    print *, "  ✓ default vertical stacking: items stack downward"
end subroutine test_default_vertical_stacking

subroutine test_column_with_gap()
    real :: x, y

    call layout_reset()
    call layout_push_column(1.0)

    call layout_advance(10.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y - 1.0) > 1e-6) then
        print *, "  FAILED: first item no gap, expected (0,1), got", x, y
        stop 1
    end if

    call layout_advance(10.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y - 3.0) > 1e-6) then
        print *, "  FAILED: second item with gap=1, expected (0,3), got", &
            x, y
        stop 1
    end if

    call layout_advance(10.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y - 5.0) > 1e-6) then
        print *, "  FAILED: third item with gap=1, expected (0,5), got", &
            x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ column with gap=1: correct vertical spacing"
end subroutine test_column_with_gap

subroutine test_row_no_gap()
    real :: x, y

    call layout_reset()
    call layout_push_row()

    call layout_advance(5.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x - 5.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: first row item, expected (5,0), got", x, y
        stop 1
    end if

    call layout_advance(8.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x - 13.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: second row item, expected (13,0), got", x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ row no gap: items placed side by side"
end subroutine test_row_no_gap

subroutine test_row_with_gap()
    real :: x, y

    call layout_reset()
    call layout_push_row(2.0)

    call layout_advance(5.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x - 5.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: first row item, expected (5,0), got", x, y
        stop 1
    end if

    call layout_advance(5.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(x - 12.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: second row item gap=2, expected (12,0), got", &
            x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ row with gap=2: correct horizontal spacing"
end subroutine test_row_with_gap

subroutine test_nested_column_in_row()
    real :: x, y

    call layout_reset()
    call layout_push_row(2.0)

    call layout_push_column(1.0)
    call layout_advance(5.0, 1.0)
    call layout_advance(5.0, 1.0)
    call layout_pop()

    call layout_get_cursor(x, y)
    if (abs(x - 5.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: after nested column in row, expected (5,0), got", &
            x, y
        stop 1
    end if

    call layout_push_column(1.0)
    call layout_advance(8.0, 1.0)
    call layout_advance(8.0, 1.0)
    call layout_pop()

    call layout_get_cursor(x, y)
    if (abs(x - 15.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: after second nested column, expected (15,0), got", &
            x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ nested column in row: correct composite layout"
end subroutine test_nested_column_in_row

subroutine test_nested_row_in_column()
    real :: x, y

    call layout_reset()
    call layout_push_column(1.0)

    call layout_advance(10.0, 1.0)

    call layout_push_row(1.0)
    call layout_advance(4.0, 1.0)
    call layout_advance(4.0, 1.0)
    call layout_pop()

    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y - 3.0) > 1e-6) then
        print *, "  FAILED: after row in column, expected (0,3), got", x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ nested row in column: correct composite layout"
end subroutine test_nested_row_in_column

subroutine test_no_gap_on_first_item()
    real :: x, y

    call layout_reset()
    call layout_push_column(5.0)

    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: before first item, expected (0,0), got", x, y
        stop 1
    end if

    call layout_advance(10.0, 1.0)
    call layout_get_cursor(x, y)
    if (abs(y - 1.0) > 1e-6) then
        print *, "  FAILED: first item should not have gap, expected y=1, got", y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ no gap on first item: gap only between items"
end subroutine test_no_gap_on_first_item

subroutine test_multiple_items_row()
    real :: x, y

    call layout_reset()
    call layout_push_row(1.0)

    call layout_advance(3.0, 1.0)
    call layout_advance(4.0, 1.0)
    call layout_advance(5.0, 1.0)

    call layout_get_cursor(x, y)
    if (abs(x - 14.0) > 1e-6 .or. abs(y) > 1e-6) then
        print *, "  FAILED: 3 items with gap=1, expected (14,0), got", x, y
        stop 1
    end if

    call layout_pop()

    print *, "  ✓ multiple row items: 3+1+4+1+5 = 14 width"
end subroutine test_multiple_items_row

subroutine test_deep_nesting()
    real :: x, y

    call layout_reset()
    call layout_push_column()
    call layout_push_row()
    call layout_push_column()

    call layout_advance(5.0, 2.0)
    call layout_get_cursor(x, y)
    if (abs(x) > 1e-6 .or. abs(y - 2.0) > 1e-6) then
        print *, "  FAILED: deep nesting cursor, expected (0,2), got", x, y
        stop 1
    end if

    if (layout_get_depth() /= 4) then
        print *, "  FAILED: depth should be 4, got", layout_get_depth()
        stop 1
    end if

    call layout_pop()
    call layout_pop()
    call layout_pop()

    if (layout_get_depth() /= 1) then
        print *, "  FAILED: after pop depth should be 1, got", &
            layout_get_depth()
        stop 1
    end if

    print *, "  ✓ deep nesting: 3 levels deep, pop back to root"
end subroutine test_deep_nesting

end module test_layout
