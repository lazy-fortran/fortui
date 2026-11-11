module fortui_backends
    !! Optional backend registry: the only module that names every concrete
    !! backend. `ui_init(name, ...)` extends the generic `ui_init` of `fortui`:
    !!
    !!   use fortui
    !!   use fortui_backends, only: ui_init
    !!   call ui_init("auto", 900, 640, "demo", stat=stat)
    !!
    !! Names: "headless", "tui", "gui" (raylib, only in -DENABLE_GUI=1 builds) or
    !! "auto" (gui, then tui, then headless only with FORTUI_HEADLESS=1);
    !! FORTUI_BACKEND overrides the name.
    !! A requested backend that is unavailable is an error, never a fallback.
    !! Applications that inject a backend value do not need this module.
    use fortui_backend, only: ui_backend_t
    use fortui_core, only: ui_init_backend
    use fortui_backend_headless, only: headless_backend_t
    use fortui_tui, only: tui_backend_t, tui_is_available
    ! Empty unless built with -DENABLE_GUI=1 (raylib_backend_t, raylib_is_available).
    use fortui_gui_raylib
    use fortui_error, only: report_error
    implicit none
    private

    interface ui_init
        module procedure ui_init_named
    end interface ui_init

    public :: ui_init, ui_init_named, create_backend

contains

    subroutine ui_init_named(name, width, height, title, target_fps, vsync, stat)
        !! Start FortUI with the backend called `name` (see the module notes).
        character(*), intent(in) :: name
        integer, intent(in) :: width, height
        character(*), intent(in) :: title
        integer, intent(in), optional :: target_fps
        logical, intent(in), optional :: vsync
        integer, intent(out), optional :: stat
        class(ui_backend_t), allocatable :: backend

        call create_backend(name, backend)
        if (.not. allocated(backend)) then
            call report_error("fortui_backends", "ui_init", "backend '" // trim(name) // &
                "' is unknown or unavailable")
            if (present(stat)) stat = 1
            return
        end if
        call ui_init_backend(backend, width, height, title, target_fps, vsync, stat)
    end subroutine ui_init_named

    subroutine create_backend(requested, backend)
        !! Allocate the backend for `requested` (FORTUI_BACKEND overrides it).
        !! `backend` stays unallocated when the choice is unknown or unavailable.
        character(*), intent(in) :: requested
        class(ui_backend_t), allocatable, intent(out) :: backend
        character(len=64) :: choice, env_value
        integer :: status

        choice = lower(trim(requested))
        call get_environment_variable("FORTUI_BACKEND", env_value, status=status)
        if (status == 0 .and. len_trim(env_value) > 0) choice = lower(trim(env_value))

        select case (trim(choice))
        case ("headless")
            allocate(headless_backend_t :: backend)
        case ("tui", "terminal", "console")
            if (tui_is_available()) allocate(tui_backend_t :: backend)
        case ("gui", "graphics", "window", "raylib")
#ifdef ENABLE_GUI
            if (raylib_is_available()) allocate(raylib_backend_t :: backend)
#endif
        case ("auto", "")
#ifdef ENABLE_GUI
            if (raylib_is_available()) then
                allocate(raylib_backend_t :: backend)
                return
            end if
#endif
            if (tui_is_available()) then
                allocate(tui_backend_t :: backend)
            else
                call get_environment_variable("FORTUI_HEADLESS", env_value, status=status)
                if (status == 0 .and. trim(env_value) == "1") &
                    allocate(headless_backend_t :: backend)
            end if
        end select
    end subroutine create_backend

    pure function lower(value) result(out)
        character(*), intent(in) :: value
        character(len=len(value)) :: out
        integer :: i, code

        out = value
        do i = 1, len(value)
            code = iachar(out(i:i))
            if (code >= iachar('A') .and. code <= iachar('Z')) out(i:i) = achar(code + 32)
        end do
    end function lower

end module fortui_backends
