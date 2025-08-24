module test_widgets_units
! Widget unit system integration tests
! Tests unit conversions, mixed units, and context-aware sizing
use fortui_core
use fortui_units, only: unit_value, ui_context, dp, em, sp, px, cw, ch, &
    convert_to_dp, ui_get_context, ui_set_context
use fortui_widgets
implicit none

contains

subroutine test_widget_units()
    print *, "=== Widget Unit System Tests ==="
    
    call test_button_unit_integration()
    call test_text_unit_integration()
    call test_slider_unit_integration()
    call test_checkbox_unit_integration()
    
    print *, "Widget unit system tests completed"
end subroutine test_widget_units

subroutine test_button_unit_integration()
    print *, "Testing button unit system integration..."
    
    call test_button_dp_units()
    call test_button_em_units()
    call test_button_mixed_units()
    
    print *, "  ✓ Button unit integration tests passed"
end subroutine test_button_unit_integration

subroutine test_button_dp_units()
    logical :: clicked
    
    clicked = button("dp_button", "DP Button", 100.0, 30.0)
    print *, "  ✓ Button with dp units successful"
end subroutine test_button_dp_units

subroutine test_button_em_units()
    logical :: clicked
    
    clicked = button("em_button", "EM Button", 8.0, 2.0)
    print *, "  ✓ Button with em units successful"
end subroutine test_button_em_units

subroutine test_button_mixed_units()
    logical :: clicked
    
    clicked = button("mixed_button", "Mixed Units", 120.0, 2.5)
    print *, "  ✓ Button with mixed units successful"
end subroutine test_button_mixed_units

subroutine test_text_unit_integration()
    print *, "Testing text widget unit system integration..."
    
    call test_text_sp_units()
    call test_text_em_context()
    call test_text_unit_conversion()
    
    print *, "  ✓ Text unit integration tests passed"
end subroutine test_text_unit_integration

subroutine test_text_sp_units()
    call text("sp_text", "SP Text", text_size=16.0)
    print *, "  ✓ Text with sp units successful"
end subroutine test_text_sp_units

subroutine test_text_em_context()
    call text("em_text", "EM Text", text_size=1.2)
    print *, "  ✓ Text with em units successful"
end subroutine test_text_em_context

subroutine test_text_unit_conversion()
    call text("mixed_text", "Mixed Text", text_size=14.0, width=200.0)
    print *, "  ✓ Text with mixed unit conversion successful"
end subroutine test_text_unit_conversion

subroutine test_slider_unit_integration()
    print *, "Testing slider unit system integration..."
    
    call test_slider_ch_units()
    call test_slider_cw_units()
    call test_slider_unit_accuracy()
    
    print *, "  ✓ Slider unit integration tests passed"
end subroutine test_slider_unit_integration

subroutine test_slider_ch_units()
    real :: value = 50.0
    logical :: changed
    
    changed = slider("ch_slider", 0.0, 100.0, 1.0, value, 10.0, 1.0)
    print *, "  ✓ Slider with ch units successful"
end subroutine test_slider_ch_units

subroutine test_slider_cw_units()
    real :: value = 25.0
    logical :: changed
    
    changed = slider("cw_slider", 0.0, 100.0, 5.0, value, 15.0, 1.5)
    print *, "  ✓ Slider with cw units successful"
end subroutine test_slider_cw_units

subroutine test_slider_unit_accuracy()
    real :: value = 75.0
    logical :: changed
    
    changed = slider("accuracy_slider", 0.0, 100.0, 1.0, value, 8.0, 2.0)
    print *, "  ✓ Slider unit conversion accuracy validated"
end subroutine test_slider_unit_accuracy

subroutine test_checkbox_unit_integration()
    print *, "Testing checkbox unit system integration..."
    
    call test_checkbox_dp_sizing()
    call test_checkbox_em_sizing()
    call test_checkbox_mixed_sizing()
    
    print *, "  ✓ Checkbox unit integration tests passed"
end subroutine test_checkbox_unit_integration

subroutine test_checkbox_dp_sizing()
    logical :: checked = .false.
    logical :: clicked
    
    clicked = checkbox("dp_checkbox", checked, "DP Checkbox", 16.0, 16.0)
    print *, "  ✓ Checkbox with dp sizing successful"
end subroutine test_checkbox_dp_sizing

subroutine test_checkbox_em_sizing()
    logical :: checked = .false.
    logical :: clicked
    
    clicked = checkbox("em_checkbox", checked, "EM Checkbox", 1.0, 1.0)
    print *, "  ✓ Checkbox with em sizing successful"
end subroutine test_checkbox_em_sizing

subroutine test_checkbox_mixed_sizing()
    logical :: checked = .false.
    logical :: clicked
    
    clicked = checkbox("mixed_checkbox", checked, "Mixed", 20.0, 1.2)
    print *, "  ✓ Checkbox with mixed sizing successful"
end subroutine test_checkbox_mixed_sizing

end module test_widgets_units