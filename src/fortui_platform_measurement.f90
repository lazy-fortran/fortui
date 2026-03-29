module fortui_platform_measurement
use fortui_units, only: ui_context, ui_set_context
implicit none
private

public :: measure_terminal_cells, detect_system_dpi, measure_font_metrics
public :: detect_text_scaling, validate_context, ui_update_context
public :: get_fallback_context

contains

subroutine measure_terminal_cells(cell_w_dp, cell_h_dp)
    real, intent(out) :: cell_w_dp, cell_h_dp

    cell_w_dp = 8.0
    cell_h_dp = 16.0
end subroutine measure_terminal_cells

subroutine detect_system_dpi(dpi_scale)
    real, intent(out) :: dpi_scale

    dpi_scale = 1.0
end subroutine detect_system_dpi

subroutine measure_font_metrics(em_dp)
    real, intent(out) :: em_dp

    em_dp = 16.0
end subroutine measure_font_metrics

subroutine detect_text_scaling(text_scale)
    real, intent(out) :: text_scale

    text_scale = 1.0
end subroutine detect_text_scaling

subroutine validate_context(ctx)
    type(ui_context), intent(inout) :: ctx

    if (ctx%dpi_scale <= 0.0 .or. ctx%dpi_scale > 10.0) ctx%dpi_scale = 1.0
    if (ctx%em_dp <= 0.0 .or. ctx%em_dp > 200.0) ctx%em_dp = 16.0
    if (ctx%text_scale <= 0.0 .or. ctx%text_scale > 10.0) ctx%text_scale = 1.0
    if (ctx%cell_w_dp <= 0.0 .or. ctx%cell_w_dp > 100.0) ctx%cell_w_dp = 8.0
    if (ctx%cell_h_dp <= 0.0 .or. ctx%cell_h_dp > 100.0) ctx%cell_h_dp = 16.0
end subroutine validate_context

subroutine ui_update_context(new_ctx)
    type(ui_context), intent(in) :: new_ctx

    type(ui_context) :: validated_ctx

    validated_ctx = new_ctx
    call validate_context(validated_ctx)
    call ui_set_context(validated_ctx)
end subroutine ui_update_context

function get_fallback_context() result(ctx)
    type(ui_context) :: ctx

    ctx = ui_context()
end function get_fallback_context

end module fortui_platform_measurement
