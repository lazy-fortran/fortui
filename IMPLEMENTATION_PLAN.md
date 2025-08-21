# Implementation Plan for Manual Deallocation Removal (Issue #78)

## Current Status: RED Phase Complete

✅ **Phase 4 (RED) - Test Implementation Complete**
- 16 comprehensive memory safety tests implemented
- All tests correctly FAIL, identifying manual deallocation violations
- Tests validated with project test runner: 0/16 passing (expected)

## Next Phase: GREEN Implementation Required

🔄 **Phase 5.1 - sergei-perfectionist-coder Implementation**

### Required Changes

#### fortui_context.f90 (7 manual deallocates to remove)
- Line 140: `deallocate(ctx%backends%entries)` → Remove, use automatic cleanup
- Line 145: `deallocate(ctx%backend_state)` → Remove, use automatic cleanup  
- Line 152: `deallocate(ctx)` → Remove, use automatic cleanup
- Line 234: `deallocate(self%backends%entries)` → Remove, use automatic cleanup
- Line 239: `deallocate(self%backend_state)` → Remove, use automatic cleanup
- Line 408: `deallocate(self%entries(slot)%state)` → Remove, use automatic cleanup
- Line 424: `deallocate(self%entries(i)%state)` → Remove, use automatic cleanup

#### fortui_backend.f90 (2 manual deallocates to remove)
- Line 110: `deallocate(registered_backends(i)%backend)` → Remove, use nullify()
- Line 188: `deallocate(registry%entries(i)%backend)` → Remove, use nullify()

### Implementation Patterns

1. **Automatic Cleanup**: Let Fortran handle allocatable component deallocation
2. **Pointer Management**: Use `nullify()` instead of `deallocate()` for pointers
3. **Move Semantics**: Use `move_alloc()` for ownership transfer
4. **Proper Scoping**: Ensure variables clean up automatically at scope exit

### Success Criteria

- All 16 memory safety tests must PASS
- No functional regressions in context/backend operations
- Memory leaks eliminated through automatic management
- Fortran best practices compliance achieved

### Handoff to sergei-perfectionist-coder

Branch: `fix/manual-deallocation-removal`
Tests: `make test test_memory_safety` (should pass after implementation)
Files: `src/fortui_context.f90`, `src/fortui_backend.f90`