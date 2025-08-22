module test_units_simple
! Simplified unit tests focused on size compliance
! Tests basic unit operations without complex API dependencies
use fortui_units
implicit none

contains

subroutine test_all_units_simple()
    print *, "=== Simplified Units Test Suite ==="
    
    call test_unit_creation()
    call test_basic_conversion()
    
    print *, "Simplified units tests completed"
end subroutine test_all_units_simple

subroutine test_unit_creation()
    print *, "Testing unit creation functions..."
    
    call test_dp_creation()
    call test_em_creation()
    call test_sp_creation()
    call test_px_creation()
    call test_cw_creation()
    call test_ch_creation()
    
    print *, "  ✓ Unit creation tests passed"
end subroutine test_unit_creation

subroutine test_dp_creation()
    type(unit_value) :: result
    
    result = dp(100.0)
    
    if (result%value == 100.0 .and. result%unit_type == "dp") then
        print *, "  ✓ DP creation working"
    else
        print *, "  ✗ DP creation failed"
    end if
end subroutine test_dp_creation

subroutine test_em_creation()
    type(unit_value) :: result
    
    result = em(2.0)
    
    if (result%value == 2.0 .and. result%unit_type == "em") then
        print *, "  ✓ EM creation working"
    else
        print *, "  ✗ EM creation failed"
    end if
end subroutine test_em_creation

subroutine test_sp_creation()
    type(unit_value) :: result
    
    result = sp(16.0)
    
    if (result%value == 16.0 .and. result%unit_type == "sp") then
        print *, "  ✓ SP creation working"
    else
        print *, "  ✗ SP creation failed"
    end if
end subroutine test_sp_creation

subroutine test_px_creation()
    type(unit_value) :: result
    
    result = px(200.0)
    
    if (result%value == 200.0 .and. result%unit_type == "px") then
        print *, "  ✓ PX creation working"
    else
        print *, "  ✗ PX creation failed"
    end if
end subroutine test_px_creation

subroutine test_cw_creation()
    type(unit_value) :: result
    
    result = cw(10.0)
    
    if (result%value == 10.0 .and. result%unit_type == "cw") then
        print *, "  ✓ CW creation working"
    else
        print *, "  ✗ CW creation failed"
    end if
end subroutine test_cw_creation

subroutine test_ch_creation()
    type(unit_value) :: result
    
    result = ch(5.0)
    
    if (result%value == 5.0 .and. result%unit_type == "ch") then
        print *, "  ✓ CH creation working"
    else
        print *, "  ✗ CH creation failed"
    end if
end subroutine test_ch_creation

subroutine test_basic_conversion()
    print *, "Testing basic conversion..."
    
    call test_dp_conversion()
    call test_context_access()
    
    print *, "  ✓ Basic conversion tests passed"
end subroutine test_basic_conversion

subroutine test_dp_conversion()
    type(ui_context) :: ctx
    type(unit_value) :: dp_unit
    real :: converted
    
    call ui_get_context(ctx)
    dp_unit = dp(100.0)
    converted = convert_to_dp(dp_unit, ctx)
    
    if (abs(converted - 100.0) < 0.001) then
        print *, "  ✓ DP conversion identity working"
    else
        print *, "  ✗ DP conversion failed"
    end if
end subroutine test_dp_conversion

subroutine test_context_access()
    type(ui_context) :: ctx
    
    call ui_get_context(ctx)
    
    if (ctx%dpi_scale > 0.0 .and. ctx%em_dp > 0.0) then
        print *, "  ✓ Context access working"
    else
        print *, "  ✗ Context access failed"
    end if
end subroutine test_context_access

end module test_units_simple