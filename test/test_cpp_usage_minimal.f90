program test_cpp_usage_minimal
implicit none

integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

call test_case("CPP manifest stays small", test_cpp_manifest_small())
call test_case("Only the TUI macro is configured", test_cpp_macros_minimal())
call test_case("CPP directories match the active source roots", test_cpp_directories())
call test_case("Platform #elif use stays isolated", test_platform_elif_scope())
call test_case("No #include directives appear in library Fortran sources", &
    command_fails( &
    "sh -c ""find src app example -type f \\( -name '*.f90' -o -name '*.F90' \\) " // &
    "-exec grep -q '#include' {} +"""))

write(*, "(A)") ""
write(*, "(A,I0,A,I0)") "Minimal CPP usage tests: ", tests_passed, " / ", tests_run

if (.not. all_tests_passed) stop 1

contains

logical function test_cpp_manifest_small() result(passed)
    passed = file_contains("fpm.toml", '[preprocess]') .and. &
        file_contains("fpm.toml", 'cpp.suffixes = ["F90", "f90"]') .and. &
        file_contains("fpm.toml", 'cpp.macros = ["ENABLE_TUI=1"]')
end function test_cpp_manifest_small

logical function test_cpp_macros_minimal() result(passed)
    passed = file_contains("fpm.toml", 'cpp.macros = ["ENABLE_TUI=1"]') .and. &
        .not. file_contains("fpm.toml", "ENABLE_GUI")
end function test_cpp_macros_minimal

logical function test_cpp_directories() result(passed)
    passed = file_contains("fpm.toml", &
        'cpp.directories = ["src", "app", "test", "example"]')
end function test_cpp_directories

logical function test_platform_elif_scope() result(passed)
    passed = file_contains("src/fortui_platform_measurement.f90", "#elif") .and. &
        command_fails( &
        "sh -c ""find src app example -type f \\( -name '*.f90' -o -name '*.F90' \\) " // &
        "! -path 'src/fortui_platform_measurement.f90' " // &
        "-exec grep -q '#elif' {} +""")
end function test_platform_elif_scope

logical function command_fails(command) result(passed)
    character(*), intent(in) :: command
    character(len=512) :: cmdmsg
    integer :: cmdstat, status

    call execute_command_line(command, exitstat=status, cmdstat=cmdstat, cmdmsg=cmdmsg)
    passed = cmdstat == 0 .and. status /= 0
end function command_fails

logical function file_contains(path, needle) result(found)
    character(*), intent(in) :: path, needle
    character(len=512) :: line
    integer :: ios, unit
    logical :: exists

    found = .false.
    inquire(file=path, exist=exists)
    if (.not. exists) return

    open(newunit=unit, file=path, status="old", action="read", iostat=ios)
    if (ios /= 0) return

    do
        read(unit, "(A)", iostat=ios) line
        if (ios /= 0) exit
        if (index(line, needle) > 0) then
            found = .true.
            exit
        end if
    end do

    close(unit)
end function file_contains

subroutine test_case(name, passed)
    character(*), intent(in) :: name
    logical, intent(in) :: passed

    tests_run = tests_run + 1
    if (passed) then
        tests_passed = tests_passed + 1
        write(*, "(A)") "PASS: " // trim(name)
    else
        all_tests_passed = .false.
        write(*, "(A)") "FAIL: " // trim(name)
    end if
end subroutine test_case

end program test_cpp_usage_minimal
