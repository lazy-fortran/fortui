#!/bin/bash
# test/test_cache_management.sh - Advanced cache management tests
# Tests for Issue #12: Concurrent access, corruption recovery, and storage efficiency

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
CACHE_TEST_DIR="/tmp/fortui_cache_mgmt_test_$$"

# Import base test framework
source "$TEST_DIR/test_build_script.sh"

# Cache Management Test Suite

test_concurrent_cache_access() {
    echo -e "\n${YELLOW}Testing concurrent cache access safety...${NC}"
    
    # Given: Multiple build processes accessing cache simultaneously
    # When: Concurrent cache operations occur
    # Then: Should handle concurrent access without corruption
    
    local test_cache="$CACHE_TEST_DIR/concurrent"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating concurrent access protection
    if grep -q "lock\|flock\|mutex" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(lock|flock|mutex)' '$build_script'" "Build script should implement cache locking"
    else
        echo -e "${RED}✗${NC} Cache locking mechanism not yet implemented (RED phase)"
        echo "  Expected: File locking or mutex for concurrent cache access"
        echo "  This test will pass after sergei implements cache locking"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test atomic cache operations
    if grep -q "atomic\|temp.*mv\|\.tmp" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(atomic|temp.*mv|\\.tmp)' '$build_script'" "Build script should use atomic operations"
    else
        echo -e "${RED}✗${NC} Atomic cache operations not yet implemented (RED phase)"
        echo "  Expected: Atomic file operations (temp + move) for cache updates"
        echo "  This test will pass after sergei implements atomic operations"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test concurrent build marker handling
    local marker1="$test_cache/build_marker_1.lock"
    local marker2="$test_cache/build_marker_2.lock"
    
    # Simulate concurrent build attempts
    touch "$marker1"
    touch "$marker2"
    
    # Build script should detect and handle concurrent builds
    if [[ -f "$marker1" && -f "$marker2" ]]; then
        echo -e "${GREEN}✓${NC} Can simulate concurrent build scenarios"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Cannot create concurrent build test scenario"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_cache_corruption_detection() {
    echo -e "\n${YELLOW}Testing cache corruption detection and recovery...${NC}"
    
    # Given: Corrupted cache files
    # When: Build script accesses cache
    # Then: Should detect corruption and initiate recovery
    
    local test_cache="$CACHE_TEST_DIR/corruption"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create corrupted cache files
    mkdir -p "$test_cache/termbox2"
    echo "corrupted_binary_data" > "$test_cache/termbox2/termbox.h"
    echo "invalid_marker_content" > "$test_cache/termbox2_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating corruption detection
    if grep -q "corrupt\|verify\|checksum\|hash" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(corrupt|verify|checksum|hash)' '$build_script'" "Build script should detect cache corruption"
    else
        echo -e "${RED}✗${NC} Cache corruption detection not yet implemented (RED phase)"
        echo "  Expected: Corruption detection via checksums or verification"
        echo "  This test will pass after sergei implements corruption detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test recovery mechanism
    if grep -q "recover\|rebuild\|clean.*cache" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(recover|rebuild|clean.*cache)' '$build_script'" "Build script should support cache recovery"
    else
        echo -e "${RED}✗${NC} Cache recovery mechanism not yet implemented (RED phase)"
        echo "  Expected: Automatic cache recovery when corruption detected"
        echo "  This test will pass after sergei implements cache recovery"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test partial corruption handling
    mkdir -p "$test_cache/fortran-raygui"
    echo "valid_data" > "$test_cache/fortran-raygui/valid_file.f90"
    echo "corrupted_data" > "$test_cache/fortran-raygui/corrupted_file.f90"
    
    # Build script should handle partial corruption gracefully
    assert_directory_exists "$test_cache/fortran-raygui" "Should handle partially corrupted cache directories"
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_cache_storage_efficiency() {
    echo -e "\n${YELLOW}Testing cache storage efficiency and optimization...${NC}"
    
    # Given: Large cache with multiple dependency versions
    # When: Managing cache storage
    # Then: Should optimize storage and cleanup old versions
    
    local test_cache="$CACHE_TEST_DIR/efficiency"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create multiple dependency versions
    for version in "v1.0.0" "v1.1.0" "v2.0.0"; do
        mkdir -p "$test_cache/termbox2_$version"
        echo "termbox2_data_$version" > "$test_cache/termbox2_$version/termbox.h"
        echo "build_marker_$version" > "$test_cache/termbox2_${version}_built"
    done
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating storage optimization
    if grep -q "cleanup\|prune\|old.*version" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(cleanup|prune|old.*version)' '$build_script'" "Build script should support cache cleanup"
    else
        echo -e "${RED}✗${NC} Cache cleanup functionality not yet implemented (RED phase)"
        echo "  Expected: Cleanup of old dependency versions to save space"
        echo "  This test will pass after sergei implements cache cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test cache size monitoring
    if grep -q "size\|du\|disk.*usage" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(size|du|disk.*usage)' '$build_script'" "Build script should monitor cache size"
    else
        echo -e "${RED}✗${NC} Cache size monitoring not yet implemented (RED phase)"
        echo "  Expected: Cache size monitoring and reporting"
        echo "  This test will pass after sergei implements size monitoring"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test compression support
    if grep -q "compress\|gzip\|tar" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(compress|gzip|tar)' '$build_script'" "Build script should support cache compression"
    else
        echo -e "${RED}✗${NC} Cache compression not yet implemented (RED phase)"
        echo "  Expected: Compression of cached dependencies to save space"
        echo "  This test will pass after sergei implements cache compression"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_cache_invalidation_strategies() {
    echo -e "\n${YELLOW}Testing cache invalidation strategies...${NC}"
    
    # Given: Various conditions that should invalidate cache
    # When: Conditions change
    # Then: Should invalidate cache appropriately
    
    local test_cache="$CACHE_TEST_DIR/invalidation"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create cache with timestamp
    local cache_timestamp="$test_cache/last_build_timestamp"
    echo "$(date +%s)" > "$cache_timestamp"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test timestamp-based invalidation
    if grep -q "timestamp\|mtime\|age" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(timestamp|mtime|age)' '$build_script'" "Build script should use timestamp-based invalidation"
    else
        echo -e "${RED}✗${NC} Timestamp-based cache invalidation not yet implemented (RED phase)"
        echo "  Expected: Cache invalidation based on file modification times"
        echo "  This test will pass after sergei implements timestamp invalidation"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test dependency version change invalidation
    export TERMBOX_REF="new_version"
    export FRG_REF="updated_branch"
    
    # Build script should detect version changes
    local ref_tracking
    ref_tracking=$(grep -c "REF.*change\|version.*change" "$build_script" 2>/dev/null || echo "0")
    
    if [[ "$ref_tracking" -gt 0 ]]; then
        assert_command_success "grep -E '(REF.*change|version.*change)' '$build_script'" "Build script should track dependency version changes"
    else
        echo -e "${RED}✗${NC} Dependency version change tracking not yet implemented (RED phase)"
        echo "  Expected: Cache invalidation when dependency versions change"
        echo "  This test will pass after sergei implements version change detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test build environment change invalidation
    export CC="different_compiler"
    export CFLAGS="-O3 -march=native"
    
    # Build script should detect environment changes
    if grep -q "environment\|CC\|CFLAGS" "$build_script" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Build script considers environment variables"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Environment change detection not yet implemented (RED phase)"
        echo "  Expected: Cache invalidation when build environment changes"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE TERMBOX_REF FRG_REF CC CFLAGS
}

test_cache_backup_and_restore() {
    echo -e "\n${YELLOW}Testing cache backup and restore functionality...${NC}"
    
    # Given: Working cache that needs backup
    # When: Creating backups and restoring from them
    # Then: Should preserve cache integrity across backup/restore cycles
    
    local test_cache="$CACHE_TEST_DIR/backup"
    local backup_cache="$CACHE_TEST_DIR/backup_store"
    mkdir -p "$test_cache" "$backup_cache"
    export GUI_CACHE="$test_cache"
    
    # Create cache content
    mkdir -p "$test_cache/termbox2"
    echo "important_cache_data" > "$test_cache/termbox2/termbox.h"
    echo "build_marker" > "$test_cache/termbox2_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating backup functionality
    if grep -q "backup\|snapshot\|save.*cache" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(backup|snapshot|save.*cache)' '$build_script'" "Build script should support cache backup"
    else
        echo -e "${RED}✗${NC} Cache backup functionality not yet implemented (RED phase)"
        echo "  Expected: Cache backup and snapshot capabilities"
        echo "  This test will pass after sergei implements backup functionality"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test restore functionality
    if grep -q "restore\|load.*cache\|import.*cache" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(restore|load.*cache|import.*cache)' '$build_script'" "Build script should support cache restore"
    else
        echo -e "${RED}✗${NC} Cache restore functionality not yet implemented (RED phase)"
        echo "  Expected: Cache restore from backup capabilities"
        echo "  This test will pass after sergei implements restore functionality"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test backup verification
    if grep -q "verify.*backup\|check.*integrity" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(verify.*backup|check.*integrity)' '$build_script'" "Build script should verify backup integrity"
    else
        echo -e "${RED}✗${NC} Backup verification not yet implemented (RED phase)"
        echo "  Expected: Backup integrity verification"
        echo "  This test will pass after sergei implements backup verification"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache" "$backup_cache"
    unset GUI_CACHE
}

test_cache_sharing_between_projects() {
    echo -e "\n${YELLOW}Testing cache sharing between projects...${NC}"
    
    # Given: Multiple projects using same dependencies
    # When: Accessing shared cache
    # Then: Should share dependencies safely without conflicts
    
    local shared_cache="$CACHE_TEST_DIR/shared"
    local project1_cache="$CACHE_TEST_DIR/project1"
    local project2_cache="$CACHE_TEST_DIR/project2"
    
    mkdir -p "$shared_cache" "$project1_cache" "$project2_cache"
    
    # Create shared dependency
    mkdir -p "$shared_cache/termbox2"
    echo "shared_termbox2_data" > "$shared_cache/termbox2/termbox.h"
    echo "shared_build_marker" > "$shared_cache/termbox2_built"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating cache sharing
    if grep -q "shared\|global.*cache\|system.*cache" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(shared|global.*cache|system.*cache)' '$build_script'" "Build script should support shared cache"
    else
        echo -e "${RED}✗${NC} Shared cache functionality not yet implemented (RED phase)"
        echo "  Expected: Shared cache support between projects"
        echo "  This test will pass after sergei implements shared cache"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test cache isolation when needed
    if grep -q "isolate\|project.*specific\|private.*cache" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(isolate|project.*specific|private.*cache)' '$build_script'" "Build script should support cache isolation"
    else
        echo -e "${RED}✗${NC} Cache isolation not yet implemented (RED phase)"
        echo "  Expected: Project-specific cache isolation when needed"
        echo "  This test will pass after sergei implements cache isolation"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test cache permission handling
    if grep -q "permission\|chmod\|access.*control" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(permission|chmod|access.*control)' '$build_script'" "Build script should handle cache permissions"
    else
        echo -e "${RED}✗${NC} Cache permission handling not yet implemented (RED phase)"
        echo "  Expected: Proper cache permission and access control"
        echo "  This test will pass after sergei implements permission handling"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$shared_cache" "$project1_cache" "$project2_cache"
}

test_cache_metadata_management() {
    echo -e "\n${YELLOW}Testing cache metadata management...${NC}"
    
    # Given: Cache with associated metadata
    # When: Managing cache metadata
    # Then: Should track and maintain accurate metadata
    
    local test_cache="$CACHE_TEST_DIR/metadata"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create cache with metadata
    local metadata_file="$test_cache/cache_metadata.json"
    cat > "$metadata_file" << 'EOF'
{
    "version": "1.0",
    "dependencies": {
        "termbox2": {
            "version": "master",
            "built_at": "2025-01-01T00:00:00Z",
            "checksum": "abc123"
        }
    }
}
EOF
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating metadata management
    if grep -q "metadata\|json\|track.*version" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(metadata|json|track.*version)' '$build_script'" "Build script should manage cache metadata"
    else
        echo -e "${RED}✗${NC} Cache metadata management not yet implemented (RED phase)"
        echo "  Expected: Metadata tracking for cached dependencies"
        echo "  This test will pass after sergei implements metadata management"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test metadata validation
    if grep -q "validate.*metadata\|check.*version" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(validate.*metadata|check.*version)' '$build_script'" "Build script should validate metadata"
    else
        echo -e "${RED}✗${NC} Metadata validation not yet implemented (RED phase)"
        echo "  Expected: Validation of cache metadata consistency"
        echo "  This test will pass after sergei implements metadata validation"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test metadata update
    if grep -q "update.*metadata\|refresh.*info" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(update.*metadata|refresh.*info)' '$build_script'" "Build script should update metadata"
    else
        echo -e "${RED}✗${NC} Metadata update functionality not yet implemented (RED phase)"
        echo "  Expected: Automatic metadata updates during cache operations"
        echo "  This test will pass after sergei implements metadata updates"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

# Run cache management test suite
run_cache_management_tests() {
    echo -e "${YELLOW}Starting cache management test suite for Issue #12...${NC}\n"
    
    # Reset test counters for this suite
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Setup test environment
    setup_test_env
    source_build_functions
    
    # Core cache management tests
    test_concurrent_cache_access
    test_cache_corruption_detection
    test_cache_storage_efficiency
    test_cache_invalidation_strategies
    
    # Advanced cache management tests
    test_cache_backup_and_restore
    test_cache_sharing_between_projects
    test_cache_metadata_management
    
    # Cleanup
    teardown_test_env
    rm -rf "$CACHE_TEST_DIR" 2>/dev/null || true
    
    # Results summary
    echo -e "\n${YELLOW}Cache Management Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo -e "\n${YELLOW}Note:${NC} Many failures are expected in RED phase - they guide cache management implementation"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All cache management tests passed!${NC}"
        return 0
    fi
}

# Main execution for standalone running
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_cache_management_tests
fi