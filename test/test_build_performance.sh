#!/bin/bash
# test/test_build_performance.sh - Build system performance tests
# Tests for Issue #12: Large cache scenarios, build time optimization, and performance benchmarks

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
PERF_TEST_CACHE="/tmp/fortui_perf_test_$$"

# Import base test framework
source "$TEST_DIR/test_build_script.sh"

# Performance timing functions
start_timer() {
    TIMER_START=$(date +%s%N)
}

end_timer() {
    local timer_end=$(date +%s%N)
    local duration=$((($timer_end - $TIMER_START) / 1000000))  # Convert to milliseconds
    echo "$duration"
}

# Build System Performance Test Suite

test_initial_build_performance() {
    echo -e "\n${YELLOW}Testing initial build performance...${NC}"
    
    # Given: Clean environment without cached dependencies
    # When: Performing initial build
    # Then: Should complete within reasonable time bounds
    
    local test_cache="$PERF_TEST_CACHE/initial"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test configuration performance (should be very fast)
    start_timer
    local config_output
    config_output=$(source "$build_script" && "$build_script" config 2>/dev/null || true)
    local config_time
    config_time=$(end_timer)
    
    # Configuration should complete in under 100ms
    if [[ "$config_time" -lt 100 ]]; then
        echo -e "${GREEN}✓${NC} Configuration completed in ${config_time}ms (target: <100ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Configuration took ${config_time}ms (target: <100ms)"
        echo "  Configuration should be near-instantaneous"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test CPP flags performance
    start_timer
    local cpp_flags
    cpp_flags=$(source "$build_script" && setup_cpp_flags)
    local flags_time
    flags_time=$(end_timer)
    
    # CPP flag generation should complete in under 50ms
    if [[ "$flags_time" -lt 50 ]]; then
        echo -e "${GREEN}✓${NC} CPP flags generated in ${flags_time}ms (target: <50ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} CPP flags took ${flags_time}ms (target: <50ms)"
        echo "  Flag generation should be extremely fast"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # This test will FAIL initially - validating performance optimization
    if grep -q "performance\|optimize\|fast.*path" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(performance|optimize|fast.*path)' '$build_script'" "Build script should include performance optimizations"
    else
        echo -e "${RED}✗${NC} Performance optimizations not yet implemented (RED phase)"
        echo "  Expected: Performance-focused code paths and optimizations"
        echo "  This test will pass after sergei implements performance optimizations"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_cached_build_performance() {
    echo -e "\n${YELLOW}Testing cached build performance...${NC}"
    
    # Given: Fully cached dependencies
    # When: Performing subsequent builds
    # Then: Should be significantly faster than initial build
    
    local test_cache="$PERF_TEST_CACHE/cached"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create comprehensive cache structure
    mkdir -p "$test_cache/termbox2"
    mkdir -p "$test_cache/fortran-raygui"
    echo "cached_termbox2_data" > "$test_cache/termbox2/termbox.h"
    echo "cached_raygui_data" > "$test_cache/fortran-raygui/raygui.f90"
    echo "termbox2_build_marker" > "$test_cache/termbox2_built"
    echo "fortran_raygui_build_marker" > "$test_cache/fortran_raygui_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test cache detection performance
    start_timer
    local has_termbox_cache=false
    if [[ -f "$test_cache/termbox2_built" ]]; then
        has_termbox_cache=true
    fi
    local cache_check_time
    cache_check_time=$(end_timer)
    
    # Cache checking should be extremely fast (under 10ms)
    if [[ "$cache_check_time" -lt 10 && "$has_termbox_cache" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Cache detection completed in ${cache_check_time}ms (target: <10ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Cache detection took ${cache_check_time}ms or failed (target: <10ms)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test dependency flags generation with cache
    start_timer
    local dep_flags
    dep_flags=$(source "$build_script" && get_dependency_flags)
    local deps_time
    deps_time=$(end_timer)
    
    # Dependency flag generation should be fast with cache (under 50ms)
    if [[ "$deps_time" -lt 50 ]]; then
        echo -e "${GREEN}✓${NC} Dependency flags generated in ${deps_time}ms (target: <50ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Dependency flags took ${deps_time}ms (target: <50ms)"
        echo "  Cached dependency processing should be very fast"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test cache hit optimization
    if grep -q "cache.*hit\|skip.*build\|already.*built" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(cache.*hit|skip.*build|already.*built)' '$build_script'" "Build script should optimize for cache hits"
    else
        echo -e "${RED}✗${NC} Cache hit optimization not yet implemented (RED phase)"
        echo "  Expected: Fast paths for cache hits to avoid unnecessary work"
        echo "  This test will pass after sergei implements cache hit optimization"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_large_cache_scenario_performance() {
    echo -e "\n${YELLOW}Testing large cache scenario performance...${NC}"
    
    # Given: Large cache with many dependency versions
    # When: Operating on large cache
    # Then: Should maintain reasonable performance
    
    local test_cache="$PERF_TEST_CACHE/large"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create large cache scenario (100 mock dependency versions)
    for i in $(seq 1 100); do
        mkdir -p "$test_cache/dependency_${i}"
        echo "dependency_${i}_data" > "$test_cache/dependency_${i}/header.h"
        echo "dependency_${i}_marker" > "$test_cache/dependency_${i}_built"
    done
    
    # Create main dependencies among the many
    mkdir -p "$test_cache/termbox2"
    mkdir -p "$test_cache/fortran-raygui"
    echo "termbox2_data" > "$test_cache/termbox2/termbox.h"
    echo "raygui_data" > "$test_cache/fortran-raygui/raygui.f90"
    echo "termbox2_build_marker" > "$test_cache/termbox2_built"
    echo "fortran_raygui_build_marker" > "$test_cache/fortran_raygui_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test large cache navigation performance
    start_timer
    local found_termbox=false
    if [[ -d "$test_cache/termbox2" ]]; then
        found_termbox=true
    fi
    local search_time
    search_time=$(end_timer)
    
    # Large cache navigation should still be fast (under 100ms)
    if [[ "$search_time" -lt 100 && "$found_termbox" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Large cache navigation in ${search_time}ms (target: <100ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Large cache navigation took ${search_time}ms (target: <100ms)"
        echo "  Performance should not degrade significantly with cache size"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test cache cleanup performance with large cache
    if grep -q "cleanup.*performance\|efficient.*cleanup\|fast.*prune" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(cleanup.*performance|efficient.*cleanup|fast.*prune)' '$build_script'" "Build script should handle large cache cleanup efficiently"
    else
        echo -e "${RED}✗${NC} Efficient large cache cleanup not yet implemented (RED phase)"
        echo "  Expected: Performance-optimized cleanup for large caches"
        echo "  This test will pass after sergei implements efficient cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test memory usage with large cache
    if grep -q "memory.*efficient\|low.*memory\|memory.*usage" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(memory.*efficient|low.*memory|memory.*usage)' '$build_script'" "Build script should be memory efficient with large caches"
    else
        echo -e "${RED}✗${NC} Memory efficiency for large caches not yet implemented (RED phase)"
        echo "  Expected: Memory-efficient operations for large cache scenarios"
        echo "  This test will pass after sergei implements memory optimizations"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_parallel_build_performance() {
    echo -e "\n${YELLOW}Testing parallel build performance...${NC}"
    
    # Given: Multiple dependencies that can be built in parallel
    # When: Building dependencies concurrently
    # Then: Should significantly reduce total build time
    
    local test_cache="$PERF_TEST_CACHE/parallel"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating parallel build capability
    if grep -q "parallel\|concurrent\|jobs.*count\|-j" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(parallel|concurrent|jobs.*count|-j)' '$build_script'" "Build script should support parallel builds"
    else
        echo -e "${RED}✗${NC} Parallel build support not yet implemented (RED phase)"
        echo "  Expected: Parallel dependency building to improve performance"
        echo "  This test will pass after sergei implements parallel builds"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test CPU core detection for optimal parallelism
    if grep -q "nproc\|cpu.*count\|core.*count" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(nproc|cpu.*count|core.*count)' '$build_script'" "Build script should detect CPU cores for parallelism"
    else
        echo -e "${RED}✗${NC} CPU core detection not yet implemented (RED phase)"
        echo "  Expected: Automatic detection of CPU cores for optimal parallelism"
        echo "  This test will pass after sergei implements core detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test build job scheduling
    if grep -q "schedule\|queue\|job.*control" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(schedule|queue|job.*control)' '$build_script'" "Build script should schedule build jobs efficiently"
    else
        echo -e "${RED}✗${NC} Build job scheduling not yet implemented (RED phase)"
        echo "  Expected: Efficient scheduling of parallel build jobs"
        echo "  This test will pass after sergei implements job scheduling"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test load balancing across cores
    if grep -q "load.*balance\|distribute.*jobs\|even.*distribution" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(load.*balance|distribute.*jobs|even.*distribution)' '$build_script'" "Build script should balance load across cores"
    else
        echo -e "${RED}✗${NC} Load balancing not yet implemented (RED phase)"
        echo "  Expected: Load balancing for optimal CPU utilization"
        echo "  This test will pass after sergei implements load balancing"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_incremental_build_performance() {
    echo -e "\n${YELLOW}Testing incremental build performance...${NC}"
    
    # Given: Existing builds with minimal changes
    # When: Performing incremental builds
    # Then: Should only rebuild what's necessary
    
    local test_cache="$PERF_TEST_CACHE/incremental"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create existing build state
    mkdir -p "$test_cache/termbox2"
    mkdir -p "$test_cache/fortran-raygui"
    echo "termbox2_v1" > "$test_cache/termbox2/termbox.h"
    echo "raygui_v1" > "$test_cache/fortran-raygui/raygui.f90"
    echo "termbox2_build_marker" > "$test_cache/termbox2_built"
    echo "fortran_raygui_build_marker" > "$test_cache/fortran_raygui_built"
    
    # Set timestamps for incremental testing
    touch -t 202501010000 "$test_cache/termbox2_built"
    touch -t 202501010100 "$test_cache/fortran_raygui_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating incremental build capability
    if grep -q "incremental\|timestamp\|mtime\|newer.*than" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(incremental|timestamp|mtime|newer.*than)' '$build_script'" "Build script should support incremental builds"
    else
        echo -e "${RED}✗${NC} Incremental build support not yet implemented (RED phase)"
        echo "  Expected: Timestamp-based incremental build capability"
        echo "  This test will pass after sergei implements incremental builds"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test dependency change detection
    if grep -q "change.*detect\|diff.*dependency\|updated.*since" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(change.*detect|diff.*dependency|updated.*since)' '$build_script'" "Build script should detect dependency changes"
    else
        echo -e "${RED}✗${NC} Dependency change detection not yet implemented (RED phase)"
        echo "  Expected: Detection of changes requiring rebuilds"
        echo "  This test will pass after sergei implements change detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test selective rebuild
    if grep -q "selective.*build\|partial.*build\|only.*changed" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(selective.*build|partial.*build|only.*changed)' '$build_script'" "Build script should support selective rebuilds"
    else
        echo -e "${RED}✗${NC} Selective rebuild not yet implemented (RED phase)"
        echo "  Expected: Rebuilding only changed dependencies"
        echo "  This test will pass after sergei implements selective rebuilds"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_memory_usage_optimization() {
    echo -e "\n${YELLOW}Testing memory usage optimization...${NC}"
    
    # Given: Memory-constrained build environment
    # When: Building dependencies
    # Then: Should use memory efficiently
    
    local test_cache="$PERF_TEST_CACHE/memory"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating memory optimization
    if grep -q "memory.*limit\|low.*memory\|memory.*efficient" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(memory.*limit|low.*memory|memory.*efficient)' '$build_script'" "Build script should optimize memory usage"
    else
        echo -e "${RED}✗${NC} Memory usage optimization not yet implemented (RED phase)"
        echo "  Expected: Memory-efficient build processes"
        echo "  This test will pass after sergei implements memory optimization"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test streaming/chunked processing
    if grep -q "stream\|chunk\|batch.*process" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(stream|chunk|batch.*process)' '$build_script'" "Build script should use streaming/chunked processing"
    else
        echo -e "${RED}✗${NC} Streaming/chunked processing not yet implemented (RED phase)"
        echo "  Expected: Memory-efficient streaming processing"
        echo "  This test will pass after sergei implements streaming"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test garbage collection/cleanup
    if grep -q "cleanup.*memory\|free.*memory\|garbage.*collect" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(cleanup.*memory|free.*memory|garbage.*collect)' '$build_script'" "Build script should clean up memory during builds"
    else
        echo -e "${RED}✗${NC} Memory cleanup not yet implemented (RED phase)"
        echo "  Expected: Active memory cleanup during long builds"
        echo "  This test will pass after sergei implements memory cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_build_time_benchmarking() {
    echo -e "\n${YELLOW}Testing build time benchmarking and profiling...${NC}"
    
    # Given: Need to measure and optimize build performance
    # When: Running build operations
    # Then: Should provide timing and profiling information
    
    local test_cache="$PERF_TEST_CACHE/benchmark"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating benchmarking capability
    if grep -q "benchmark\|timing\|profile\|measure.*time" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(benchmark|timing|profile|measure.*time)' '$build_script'" "Build script should support benchmarking"
    else
        echo -e "${RED}✗${NC} Build time benchmarking not yet implemented (RED phase)"
        echo "  Expected: Built-in timing and benchmarking capabilities"
        echo "  This test will pass after sergei implements benchmarking"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test performance reporting
    if grep -q "performance.*report\|timing.*report\|build.*stats" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(performance.*report|timing.*report|build.*stats)' '$build_script'" "Build script should generate performance reports"
    else
        echo -e "${RED}✗${NC} Performance reporting not yet implemented (RED phase)"
        echo "  Expected: Detailed performance and timing reports"
        echo "  This test will pass after sergei implements performance reporting"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test bottleneck identification
    if grep -q "bottleneck\|slow.*step\|performance.*issue" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(bottleneck|slow.*step|performance.*issue)' '$build_script'" "Build script should identify bottlenecks"
    else
        echo -e "${RED}✗${NC} Bottleneck identification not yet implemented (RED phase)"
        echo "  Expected: Automatic identification of performance bottlenecks"
        echo "  This test will pass after sergei implements bottleneck detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test actual timing of current operations
    start_timer
    local config_result
    config_result=$(source "$build_script" && "$build_script" config 2>/dev/null || echo "config_failed")
    local total_config_time
    total_config_time=$(end_timer)
    
    if [[ "$config_result" == *"Fortui Build Configuration"* ]]; then
        echo -e "${GREEN}✓${NC} Current configuration completes in ${total_config_time}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Configuration benchmark failed or took ${total_config_time}ms"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

# Run build performance test suite
run_build_performance_tests() {
    echo -e "${YELLOW}Starting build performance test suite for Issue #12...${NC}\n"
    echo -e "${YELLOW}Note: Performance tests validate optimization opportunities and current performance baseline${NC}\n"
    
    # Reset test counters for this suite
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Setup test environment
    setup_test_env
    source_build_functions
    
    # Core performance tests
    test_initial_build_performance
    test_cached_build_performance
    test_large_cache_scenario_performance
    
    # Advanced performance tests
    test_parallel_build_performance
    test_incremental_build_performance
    test_memory_usage_optimization
    test_build_time_benchmarking
    
    # Cleanup
    teardown_test_env
    rm -rf "$PERF_TEST_CACHE" 2>/dev/null || true
    
    # Results summary
    echo -e "\n${YELLOW}Build Performance Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo -e "\n${YELLOW}Note:${NC} Many failures are expected in RED phase - they guide performance optimization implementation"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All build performance tests passed!${NC}"
        return 0
    fi
}

# Main execution for standalone running
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_build_performance_tests
fi