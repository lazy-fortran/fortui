module test_units_operators
! Unit operator tests - focused on postfix operators and basic unit creation
! Tests dp, em, sp, px, cw, ch operators and edge cases
use fortui_units
implicit none

contains

subroutine test_all_unit_operators()
    print *, "=== Unit Operators Test Suite ==="
    
    call test_unit_operators()
    
    print *, "Unit operators tests completed"
end subroutine test_all_unit_operators

subroutine test_unit_operators()
    print *, "Testing postfix unit operator API..."
    
    call test_dp_operator()
    call test_em_operator()
    call test_sp_operator()
    call test_px_operator()
    call test_cw_operator()
    call test_ch_operator()
    call test_operator_edge_cases()
    call test_operator_return_types()
    
    print *, "  ✓ Unit operators tests passed"
end subroutine test_unit_operators

subroutine test_dp_operator()
    type(unit_value) :: result_dp_int, result_dp_real
    
    result_dp_int = dp(100.0)
    result_dp_real = dp(100.5)
    
    if (result_dp_int%value == 100.0 .and. result_dp_int%unit_type == "dp" .and. &
        result_dp_real%value == 100.5 .and. result_dp_real%unit_type == "dp") then
        print *, "  ✓ dp operator: integer and real conversion working"
    else
        print *, "  ✗ dp operator test failed"
        stop 1
    end if
end subroutine test_dp_operator

subroutine test_em_operator()
    type(unit_value) :: result_em_small, result_em_large
    
    result_em_small = em(0.5)
    result_em_large = em(2.5)
    
    if (result_em_small%value == 0.5 .and. result_em_small%unit_type == "em" .and. &
        result_em_large%value == 2.5 .and. result_em_large%unit_type == "em") then
        print *, "  ✓ em operator: small and large values working"
    else
        print *, "  ✗ em operator test failed"
        stop 1
    end if
end subroutine test_em_operator

subroutine test_sp_operator()
    type(unit_value) :: result_sp_text
    
    result_sp_text = sp(16.0)
    
    if (result_sp_text%value == 16.0 .and. result_sp_text%unit_type == "sp") then
        print *, "  ✓ sp operator: text size units working"
    else
        print *, "  ✗ sp operator test failed"
        stop 1
    end if
end subroutine test_sp_operator

subroutine test_px_operator()
    type(unit_value) :: result_px_screen
    
    result_px_screen = px(1920.0)
    
    if (result_px_screen%value == 1920.0 .and. result_px_screen%unit_type == "px") then
        print *, "  ✓ px operator: screen pixel units working"
    else
        print *, "  ✗ px operator test failed"
        stop 1
    end if
end subroutine test_px_operator

subroutine test_cw_operator()
    type(unit_value) :: result_cw_width
    
    result_cw_width = cw(80.0)
    
    if (result_cw_width%value == 80.0 .and. result_cw_width%unit_type == "cw") then
        print *, "  ✓ cw operator: character width units working"
    else
        print *, "  ✗ cw operator test failed"
        stop 1
    end if
end subroutine test_cw_operator

subroutine test_ch_operator()
    type(unit_value) :: result_ch_height
    
    result_ch_height = ch(24.0)
    
    if (result_ch_height%value == 24.0 .and. result_ch_height%unit_type == "ch") then
        print *, "  ✓ ch operator: character height units working"
    else
        print *, "  ✗ ch operator test failed"
        stop 1
    end if
end subroutine test_ch_operator

subroutine test_operator_edge_cases()
    type(unit_value) :: zero_dp, negative_em, large_px
    
    zero_dp = dp(0.0)
    negative_em = em(-1.0)
    large_px = px(999999.0)
    
    if (zero_dp%value == 0.0 .and. zero_dp%unit_type == "dp" .and. &
        negative_em%value == -1.0 .and. negative_em%unit_type == "em" .and. &
        large_px%value == 999999.0 .and. large_px%unit_type == "px") then
        print *, "  ✓ Operator edge cases: zero, negative, large values working"
    else
        print *, "  ✗ Operator edge case test failed"
        stop 1
    end if
end subroutine test_operator_edge_cases

subroutine test_operator_return_types()
    type(unit_value) :: dp_val, em_val, sp_val, px_val, cw_val, ch_val
    
    dp_val = dp(100.0)
    em_val = em(1.5)
    sp_val = sp(14.0)
    px_val = px(200.0)
    cw_val = cw(40.0)
    ch_val = ch(20.0)
    
    if (dp_val%unit_type == "dp" .and. em_val%unit_type == "em" .and. &
        sp_val%unit_type == "sp" .and. px_val%unit_type == "px" .and. &
        cw_val%unit_type == "cw" .and. ch_val%unit_type == "ch") then
        print *, "  ✓ Operator return types: all unit types correct"
    else
        print *, "  ✗ Operator return type test failed"
        stop 1
    end if
end subroutine test_operator_return_types

end module test_units_operators
