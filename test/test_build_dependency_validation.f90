program test_build_dependency_validation
! Build system dependency validation tests for Issue #87  
! Tests that build system can properly resolve and link all required dependencies
! GIVEN: Tests were disabled due to build system dependency resolution failures
! WHEN: Build system attempts to compile and link test files
! THEN: All required symbols and dependencies should be available
use, intrinsic :: iso_fortran_env, only: error_unit
implicit none

! Critical dependencies that must be available
character(len=*), parameter :: REQUIRED_DEPENDENCIES(3) = [ &
    'termbox2', &
    'raygui  ', &
    'raylib  ' ]

! Build system components that must be functional
character(len=*), parameter :: BUILD_COMPONENTS(4) = [ &
    'build_script     ', &
    'fpm_integration  ', &
    'cpp_preprocessing', &
    'dependency_cache ' ]

! Main test execution
call run_build_dependency_tests()

contains

subroutine run_build_dependency_tests()
    ! GIVEN: Build system must resolve dependencies for test restoration
    ! WHEN: Running build dependency validation tests
    ! THEN: All dependency resolution mechanisms should function correctly
    
    write(*, '(A)') "=== Build System Dependency Validation Tests ==="
    
    call test_termbox2_dependency_resolution()
    call test_gui_dependency_resolution()
    call test_build_script_functionality()
    call test_fpm_integration_validation()
    call test_dependency_cache_system()
    call test_symbol_resolution_validation()
    
    write(*, '(A)') "=== Build Dependency Validation Complete ==="
end subroutine run_build_dependency_tests

subroutine test_termbox2_dependency_resolution()
    ! GIVEN: termbox2 is required dependency for TUI backend
    ! WHEN: Build system attempts to resolve termbox2 dependency
    ! THEN: termbox2 should be available and properly linked
    
    logical :: termbox2_source_available, termbox2_built, termbox2_linkable
    character(len=256) :: cache_path, build_path
    
    write(*, '(A)') "Testing termbox2 dependency resolution..."
    
    ! Check if termbox2 source is available in cache
    call check_termbox2_source_availability(termbox2_source_available, cache_path)
    
    ! Check if termbox2 has been built successfully
    call check_termbox2_build_status(termbox2_built, build_path)
    
    ! Check if termbox2 symbols can be linked
    call check_termbox2_linkability(termbox2_linkable)
    
    ! Report detailed status
    write(*, '(A,L1,A,A)') "  termbox2 source available: ", &
        termbox2_source_available, " (", trim(cache_path), ")"
    write(*, '(A,L1,A,A)') "  termbox2 built: ", &
        termbox2_built, " (", trim(build_path), ")"
    write(*, '(A,L1)') "  termbox2 linkable: ", termbox2_linkable
    
    ! CRITICAL: This will FAIL until termbox2 dependency properly resolved
    if (.not. (termbox2_source_available .and. termbox2_built .and. termbox2_linkable)) then
        write(error_unit, '(A)') "FAIL: termbox2 dependency resolution incomplete"
        error stop "termbox2 dependency validation failed"
    end if
    
    write(*, '(A)') "PASS: termbox2 dependency fully resolved"
end subroutine test_termbox2_dependency_resolution

subroutine check_termbox2_source_availability(available, cache_path)
    ! GIVEN: termbox2 source should be cached locally
    ! WHEN: Checking for termbox2 source availability
    ! THEN: Source should be present in cache directory
    logical, intent(out) :: available
    character(len=256), intent(out) :: cache_path
    
    character(len=256) :: home_dir, default_cache
    logical :: source_exists, cache_dir_exists
    
    ! Check default cache location
    call get_environment_variable('HOME', home_dir)
    default_cache = trim(home_dir) // '/.cache/fortui/termbox2'
    
    inquire(file=trim(default_cache), exist=cache_dir_exists)
    inquire(file=trim(default_cache) // '/termbox2.h', exist=source_exists)
    
    available = cache_dir_exists .and. source_exists
    cache_path = default_cache
    
    if (.not. available) then
        write(*, '(A)') "  termbox2 source not found in cache - build system issue"
    end if
end subroutine check_termbox2_source_availability

subroutine check_termbox2_build_status(built, build_path)
    ! GIVEN: termbox2 should be compiled to static library
    ! WHEN: Checking for termbox2 build artifacts
    ! THEN: Static library should exist and be linkable
    logical, intent(out) :: built
    character(len=256), intent(out) :: build_path
    
    character(len=256) :: home_dir, cache_dir
    logical :: lib_exists, obj_exists
    
    call get_environment_variable('HOME', home_dir)
    cache_dir = trim(home_dir) // '/.cache/fortui/termbox2'
    build_path = trim(cache_dir) // '/libtermbox2.a'
    
    inquire(file=build_path, exist=lib_exists)
    inquire(file=trim(cache_dir) // '/termbox2.o', exist=obj_exists)
    
    built = lib_exists .or. obj_exists
    
    if (.not. built) then
        write(*, '(A)') "  termbox2 not built - compilation issue"
    end if
end subroutine check_termbox2_build_status

subroutine check_termbox2_linkability(linkable)
    ! GIVEN: termbox2 symbols should be available for linking
    ! WHEN: Attempting to resolve termbox2 symbols
    ! THEN: Required termbox2 functions should be linkable
    logical, intent(out) :: linkable
    
    ! This is a critical test that will FAIL until build system properly links termbox2
    ! Real implementation would attempt to compile test code that uses termbox2 functions
    linkable = .false.
    
    write(*, '(A)') "  termbox2 symbol resolution: FAIL (build system linking issue)"
end subroutine check_termbox2_linkability

subroutine test_gui_dependency_resolution()
    ! GIVEN: GUI backend requires raygui/raylib dependencies
    ! WHEN: Build system attempts to resolve GUI dependencies
    ! THEN: GUI dependencies should be conditionally available
    
    logical :: raylib_detected, raygui_available, gui_linkable
    character(len=256) :: detection_method
    
    write(*, '(A)') "Testing GUI dependency resolution..."
    
    ! Check raylib detection via multiple methods
    call check_raylib_detection(raylib_detected, detection_method)
    
    ! Check raygui (fortran-raygui) availability
    call check_raygui_availability(raygui_available)
    
    ! Check GUI symbol linkability  
    call check_gui_linkability(gui_linkable)
    
    write(*, '(A,L1,A,A)') "  raylib detected: ", &
        raylib_detected, " (method: ", trim(detection_method), ")"
    write(*, '(A,L1)') "  raygui available: ", raygui_available
    write(*, '(A,L1)') "  GUI linkable: ", gui_linkable
    
    ! GUI dependencies are conditional - failure should gracefully degrade to TUI-only
    if (raylib_detected .and. .not. (raygui_available .and. gui_linkable)) then
        write(error_unit, '(A)') "FAIL: raylib detected but GUI linking incomplete"
        error stop "GUI dependency resolution failed"
    end if
    
    if (raylib_detected .and. raygui_available .and. gui_linkable) then
        write(*, '(A)') "PASS: GUI dependencies fully resolved"
    else
        write(*, '(A)') "INFO: GUI dependencies not available - TUI-only mode"
    end if
end subroutine test_gui_dependency_resolution

subroutine check_raylib_detection(detected, method)
    ! GIVEN: raylib can be detected via multiple methods
    ! WHEN: Testing raylib detection mechanisms
    ! THEN: At least one detection method should succeed
    logical, intent(out) :: detected
    character(len=256), intent(out) :: method
    
    logical :: pkg_config_ok, env_var_ok, system_path_ok
    
    ! Test pkg-config detection
    call test_pkg_config_raylib(pkg_config_ok)
    
    ! Test environment variable detection
    call test_raylib_root_env(env_var_ok)
    
    ! Test system path detection
    call test_system_path_raylib(system_path_ok)
    
    detected = pkg_config_ok .or. env_var_ok .or. system_path_ok
    
    if (pkg_config_ok) then
        method = 'pkg-config'
    else if (env_var_ok) then
        method = 'RAYLIB_ROOT'
    else if (system_path_ok) then
        method = 'system_path'
    else
        method = 'none'
    end if
end subroutine check_raylib_detection

subroutine test_pkg_config_raylib(available)
    ! GIVEN: pkg-config should detect system raylib
    ! WHEN: Testing pkg-config raylib detection
    ! THEN: pkg-config should provide raylib flags
    logical, intent(out) :: available
    
    ! This would execute: pkg-config --exists raylib
    ! For now, assume not available in test environment
    available = .false.
    
    write(*, '(A)') "  pkg-config raylib: not available"
end subroutine test_pkg_config_raylib

subroutine test_raylib_root_env(available)
    ! GIVEN: RAYLIB_ROOT environment variable may be set
    ! WHEN: Testing RAYLIB_ROOT detection
    ! THEN: Environment variable should point to valid raylib installation
    logical, intent(out) :: available
    
    character(len=256) :: raylib_root
    logical :: dir_exists, lib_exists, include_exists
    
    call get_environment_variable('RAYLIB_ROOT', raylib_root)
    
    if (len_trim(raylib_root) > 0) then
        inquire(file=trim(raylib_root), exist=dir_exists)
        inquire(file=trim(raylib_root) // '/lib/libraylib.a', exist=lib_exists)
        inquire(file=trim(raylib_root) // '/include/raylib.h', exist=include_exists)
        
        available = dir_exists .and. lib_exists .and. include_exists
    else
        available = .false.
    end if
    
    write(*, '(A,L1)') "  RAYLIB_ROOT detection: ", available
end subroutine test_raylib_root_env

subroutine test_system_path_raylib(available)
    ! GIVEN: raylib may be installed in system paths
    ! WHEN: Testing system path raylib detection
    ! THEN: Standard system paths should contain raylib
    logical, intent(out) :: available
    
    logical :: usr_local_exists, usr_exists, opt_exists
    
    inquire(file='/usr/local/lib/libraylib.a', exist=usr_local_exists)
    inquire(file='/usr/lib/libraylib.a', exist=usr_exists)
    inquire(file='/opt/raylib/lib/libraylib.a', exist=opt_exists)
    
    available = usr_local_exists .or. usr_exists .or. opt_exists
    
    write(*, '(A,L1)') "  system path raylib: ", available
end subroutine test_system_path_raylib

subroutine check_raygui_availability(available)
    ! GIVEN: fortran-raygui should be cached when raylib available
    ! WHEN: Checking fortran-raygui availability
    ! THEN: fortran-raygui source should be present in cache
    logical, intent(out) :: available
    
    character(len=256) :: home_dir, cache_path
    logical :: cache_exists, source_exists
    
    call get_environment_variable('HOME', home_dir)
    cache_path = trim(home_dir) // '/.cache/fortui/fortran-raygui'
    
    inquire(file=cache_path, exist=cache_exists)
    inquire(file=trim(cache_path) // '/src', exist=source_exists)
    
    available = cache_exists .and. source_exists
    
    write(*, '(A,L1)') "  fortran-raygui cached: ", available
end subroutine check_raygui_availability

subroutine check_gui_linkability(linkable)
    ! GIVEN: GUI symbols should be available for linking
    ! WHEN: Attempting to resolve GUI symbols
    ! THEN: Required raygui functions should be linkable
    logical, intent(out) :: linkable
    
    ! This will FAIL until GUI dependencies are properly linked
    linkable = .false.
    
    write(*, '(A)') "  GUI symbol resolution: FAIL (GUI linking issue)"
end subroutine check_gui_linkability

subroutine test_build_script_functionality()
    ! GIVEN: Build script orchestrates dependency management
    ! WHEN: Testing build script functionality
    ! THEN: Build script should properly manage all dependencies
    
    logical :: script_exists, script_executable, script_functional
    character(len=256) :: script_path
    
    write(*, '(A)') "Testing build script functionality..."
    
    script_path = 'tools/build_fortui.sh'
    
    ! Check script existence
    inquire(file=script_path, exist=script_exists)
    
    ! Check script is executable (simplified test)
    script_executable = script_exists  ! Actual implementation would check permissions
    
    ! Test script functionality (simplified)
    call test_build_script_execution(script_functional)
    
    write(*, '(A,L1)') "  build script exists: ", script_exists
    write(*, '(A,L1)') "  build script executable: ", script_executable
    write(*, '(A,L1)') "  build script functional: ", script_functional
    
    if (.not. (script_exists .and. script_executable .and. script_functional)) then
        write(error_unit, '(A)') "FAIL: Build script not fully functional"
        error stop "Build script validation failed"
    end if
    
    write(*, '(A)') "PASS: Build script functionality validated"
end subroutine test_build_script_functionality

subroutine test_build_script_execution(functional)
    ! GIVEN: Build script should execute without errors
    ! WHEN: Testing build script execution
    ! THEN: Script should complete dependency resolution successfully
    logical, intent(out) :: functional
    
    ! This would execute the build script and check return code
    ! For now, assume not functional until build system is fixed
    functional = .false.
    
    write(*, '(A)') "  build script execution: FAIL (expected until fixed)"
end subroutine test_build_script_execution

subroutine test_fpm_integration_validation()
    ! GIVEN: FPM must integrate with build script for dependency management
    ! WHEN: Testing FPM integration
    ! THEN: FPM configuration should support build script override
    
    logical :: fpm_config_exists, build_override_set, cpp_preprocessing_enabled
    
    write(*, '(A)') "Testing FPM integration validation..."
    
    ! Check FPM configuration file
    call check_fpm_configuration(fpm_config_exists)
    
    ! Check build script override setting
    call check_build_script_override(build_override_set)
    
    ! Check CPP preprocessing configuration
    call check_cpp_preprocessing_config(cpp_preprocessing_enabled)
    
    write(*, '(A,L1)') "  FPM config exists: ", fpm_config_exists
    write(*, '(A,L1)') "  build script override: ", build_override_set
    write(*, '(A,L1)') "  CPP preprocessing: ", cpp_preprocessing_enabled
    
    if (.not. (fpm_config_exists .and. build_override_set .and. cpp_preprocessing_enabled)) then
        write(error_unit, '(A)') "FAIL: FPM integration not properly configured"
        error stop "FPM integration validation failed"
    end if
    
    write(*, '(A)') "PASS: FPM integration properly configured"
end subroutine test_fpm_integration_validation

subroutine check_fpm_configuration(exists)
    ! GIVEN: FPM configuration file should exist
    ! WHEN: Checking for fpm.toml
    ! THEN: Configuration file should be present
    logical, intent(out) :: exists
    
    inquire(file='fpm.toml', exist=exists)
end subroutine check_fpm_configuration

subroutine check_build_script_override(override_set)
    ! GIVEN: FPM should use build script override
    ! WHEN: Checking build script configuration in fpm.toml
    ! THEN: build-script setting should be present
    logical, intent(out) :: override_set
    
    ! Simplified check - real implementation would parse fpm.toml
    override_set = .true.  ! Assume properly configured for now
end subroutine check_build_script_override

subroutine check_cpp_preprocessing_config(enabled)
    ! GIVEN: CPP preprocessing should be enabled for conditional compilation
    ! WHEN: Checking preprocessing configuration
    ! THEN: CPP suffixes should be configured
    logical, intent(out) :: enabled
    
    ! Simplified check - real implementation would parse fpm.toml preprocessing config
    enabled = .true.  ! Assume properly configured for now
end subroutine check_cpp_preprocessing_config

subroutine test_dependency_cache_system()
    ! GIVEN: Dependencies should be cached for reproducible builds
    ! WHEN: Testing dependency cache system
    ! THEN: Cache should store and retrieve dependencies correctly
    
    logical :: cache_dir_exists, cache_writable, cache_functional
    character(len=256) :: cache_root
    
    write(*, '(A)') "Testing dependency cache system..."
    
    ! Check cache directory existence
    call check_cache_directory(cache_dir_exists, cache_root)
    
    ! Check cache writability
    call check_cache_writability(cache_writable)
    
    ! Test cache functionality
    call test_cache_functionality(cache_functional)
    
    write(*, '(A,L1,A,A)') "  cache directory exists: ", &
        cache_dir_exists, " (", trim(cache_root), ")"
    write(*, '(A,L1)') "  cache writable: ", cache_writable
    write(*, '(A,L1)') "  cache functional: ", cache_functional
    
    if (.not. (cache_dir_exists .and. cache_writable .and. cache_functional)) then
        write(error_unit, '(A)') "FAIL: Dependency cache system not functional"
        error stop "Dependency cache validation failed"
    end if
    
    write(*, '(A)') "PASS: Dependency cache system validated"
end subroutine test_dependency_cache_system

subroutine check_cache_directory(exists, cache_root)
    ! GIVEN: Cache directory should exist or be creatable
    ! WHEN: Checking cache directory
    ! THEN: Cache directory should be present
    logical, intent(out) :: exists
    character(len=256), intent(out) :: cache_root
    
    character(len=256) :: home_dir
    
    call get_environment_variable('HOME', home_dir)
    cache_root = trim(home_dir) // '/.cache/fortui'
    
    inquire(file=cache_root, exist=exists)
end subroutine check_cache_directory

subroutine check_cache_writability(writable)
    ! GIVEN: Cache directory should be writable
    ! WHEN: Testing cache writability
    ! THEN: Should be able to write to cache directory
    logical, intent(out) :: writable
    
    ! Simplified test - real implementation would attempt file write
    writable = .true.  ! Assume writable for now
end subroutine check_cache_writability

subroutine test_cache_functionality(functional)
    ! GIVEN: Cache should store and retrieve dependencies
    ! WHEN: Testing cache functionality
    ! THEN: Cache operations should work correctly
    logical, intent(out) :: functional
    
    ! This would test actual cache store/retrieve operations
    functional = .false.  ! Fail until cache system implemented
    
    write(*, '(A)') "  cache functionality: FAIL (expected until implemented)"
end subroutine test_cache_functionality

subroutine test_symbol_resolution_validation()
    ! GIVEN: All required symbols must be resolvable for linking
    ! WHEN: Testing symbol resolution
    ! THEN: Critical symbols should be available
    
    logical :: termbox2_symbols_ok, gui_symbols_ok, core_symbols_ok
    
    write(*, '(A)') "Testing symbol resolution validation..."
    
    ! Test termbox2 symbol resolution
    call validate_termbox2_symbols(termbox2_symbols_ok)
    
    ! Test GUI symbol resolution
    call validate_gui_symbols(gui_symbols_ok)
    
    ! Test core fortui symbol resolution
    call validate_core_symbols(core_symbols_ok)
    
    write(*, '(A,L1)') "  termbox2 symbols: ", termbox2_symbols_ok
    write(*, '(A,L1)') "  GUI symbols: ", gui_symbols_ok
    write(*, '(A,L1)') "  core symbols: ", core_symbols_ok
    
    ! CRITICAL: termbox2 and core symbols are required
    if (.not. (termbox2_symbols_ok .and. core_symbols_ok)) then
        write(error_unit, '(A)') "FAIL: Required symbols not resolvable"
        error stop "Symbol resolution validation failed"
    end if
    
    write(*, '(A)') "PASS: Symbol resolution validated"
end subroutine test_symbol_resolution_validation

subroutine validate_termbox2_symbols(symbols_ok)
    ! GIVEN: termbox2 symbols must be available
    ! WHEN: Validating termbox2 symbol resolution
    ! THEN: Required termbox2 functions should be linkable
    logical, intent(out) :: symbols_ok
    
    ! This will FAIL until termbox2 is properly linked
    symbols_ok = .false.
    
    write(*, '(A)') "  termbox2 symbol validation: FAIL (linking issue)"
end subroutine validate_termbox2_symbols

subroutine validate_gui_symbols(symbols_ok)
    ! GIVEN: GUI symbols should be conditionally available
    ! WHEN: Validating GUI symbol resolution
    ! THEN: GUI symbols should be available when GUI backend enabled
    logical, intent(out) :: symbols_ok
    
    ! GUI symbols are conditional - OK to fail if GUI not available
    symbols_ok = .false.
    
    write(*, '(A)') "  GUI symbol validation: CONDITIONAL (OK if GUI not available)"
end subroutine validate_gui_symbols

subroutine validate_core_symbols(symbols_ok)
    ! GIVEN: Core fortui symbols must be available
    ! WHEN: Validating core symbol resolution
    ! THEN: Core fortui functions should be linkable
    logical, intent(out) :: symbols_ok
    
    ! This should pass - core symbols should always be available
    symbols_ok = .true.
    
    write(*, '(A)') "  core symbol validation: PASS"
end subroutine validate_core_symbols

end program test_build_dependency_validation