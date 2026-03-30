module fortui_units
    use fortui_error, only: report_warning
    implicit none
    private

    public :: ui_context, ui_get_context, ui_set_context

    type :: ui_context
        real :: dpi_scale = 1.0
        real :: em_dp = 16.0
        real :: text_scale = 1.0
        real :: cell_w_dp = 8.0
        real :: cell_h_dp = 16.0
    end type ui_context

    type(ui_context), save :: global_context = ui_context()

contains

    subroutine ui_get_context(ctx)
        type(ui_context), intent(out) :: ctx

        ctx = global_context
    end subroutine ui_get_context

    subroutine ui_set_context(ctx)
        type(ui_context), intent(in) :: ctx

        if (ctx%dpi_scale > 0.0 .and. ctx%em_dp > 0.0 .and. &
            ctx%text_scale > 0.0 .and. ctx%cell_w_dp > 0.0 .and. &
            ctx%cell_h_dp > 0.0) then
            global_context = ctx
        else
            call report_warning("fortui_units", "ui_set_context", &
                "Invalid context values, keeping current context")
        end if
    end subroutine ui_set_context

end module fortui_units
