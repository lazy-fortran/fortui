program test_build_dependency_validation
use, intrinsic :: iso_fortran_env, only: error_unit
use fortui_termbox2_interface, only: TB_EVENT_KEY, TB_KEY_ENTER
implicit none

call run_build_dependency_tests()

contains

subroutine run_build_dependency_tests()
    logical :: manifest_ok, wrapper_ok, termbox_ok, legacy_ref_ok

    write(*, '(A)') "=== Build Dependency Validation Tests ==="

    call test_manifest_configuration(manifest_ok)
    call test_build_wrapper(wrapper_ok)
    call test_embedded_termbox_assets(termbox_ok)
    call test_legacy_script_removal(legacy_ref_ok)

    if (.not. (manifest_ok .and. wrapper_ok .and. termbox_ok .and. legacy_ref_ok)) then
        write(error_unit, '(A)') "FAIL: Current build configuration validation failed"
        error stop "build dependency validation failed"
    end if

    write(*, '(A)') "=== Build Dependency Validation Complete ==="
end subroutine run_build_dependency_tests

subroutine test_manifest_configuration(passed)
    logical, intent(out) :: passed
    logical :: file_exists

    inquire(file='fpm.toml', exist=file_exists)
    passed = file_exists .and. file_contains('fpm.toml', 'auto-tests = true') .and. &
        file_contains('fpm.toml', 'cpp.macros = ["ENABLE_TUI=1"]')

    write(*, '(A,L1)') "manifest declares test autobuild and TUI macro: ", passed
end subroutine test_manifest_configuration

subroutine test_build_wrapper(passed)
    logical, intent(out) :: passed
    logical :: file_exists
    integer :: status

    inquire(file='build.sh', exist=file_exists)
    if (.not. file_exists) then
        passed = .false.
        write(*, '(A,L1)') "build wrapper present and valid: ", passed
        return
    end if

    call execute_command_line('bash -n build.sh', exitstat=status)
    passed = status == 0 .and. file_contains('build.sh', 'exec fpm build "$@"')

    write(*, '(A,L1)') "build wrapper present and valid: ", passed
end subroutine test_build_wrapper

subroutine test_embedded_termbox_assets(passed)
    logical, intent(out) :: passed
    logical :: source_exists, header_exists

    inquire(file='src/c/termbox2.c', exist=source_exists)
    inquire(file='src/c/termbox2.h', exist=header_exists)

    passed = source_exists .and. header_exists .and. TB_KEY_ENTER == 13 .and. &
        TB_EVENT_KEY == 1

    write(*, '(A,L1)') "embedded termbox2 sources and bindings available: ", passed
end subroutine test_embedded_termbox_assets

subroutine test_legacy_script_removal(passed)
    logical, intent(out) :: passed

    passed = .not. file_contains('test/check.f90', 'tools/build_fortui.sh')
    write(*, '(A,L1)') "active build tests avoid deleted tools/build_fortui.sh: ", passed
end subroutine test_legacy_script_removal

logical function file_contains(path, needle) result(found)
    character(*), intent(in) :: path, needle
    character(len=512) :: line
    integer :: ios, unit
    logical :: exists

    found = .false.
    inquire(file=path, exist=exists)
    if (.not. exists) return

    open(newunit=unit, file=path, status='old', action='read', iostat=ios)
    if (ios /= 0) return

    do
        read(unit, '(A)', iostat=ios) line
        if (ios /= 0) exit
        if (index(line, needle) > 0) then
            found = .true.
            exit
        end if
    end do

    close(unit)
end function file_contains

end program test_build_dependency_validation
