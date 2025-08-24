# Development Backlog

## CURRENT SPRINT (Detailed GitHub Issues)
- [ ] #119: EPIC: Restore pure immediate-mode API by removing OO contamination
- [ ] #117: refactor: Remove unnecessary documentation and bloat
- [ ] #115: refactor: Simplify ui_init to single-step initialization
- [ ] #114: refactor: Remove renderer abstraction from public API
- [ ] #128: test: Convert build system simplification placeholders to actual tests
- [ ] #113: refactor: Remove backend registration and interface exposure
- [ ] #112: refactor: Simplify widget API to pure immediate-mode functions
- [ ] #111: refactor: Remove class-based polymorphism from public API
- [ ] #110: refactor: Remove context object from public API
- [ ] #109: refactor: Remove exposed widget types from public API

## DOING (Current Work)
- [x] #121: [CRITICAL] Class-based polymorphism violates immediate-mode design (branch: fix-class-polymorphism-121)

## FUTURE SPRINTS (High-level Planning)
### Sprint 2: API Cleanup Completion
- Goal: Complete removal of OO patterns from public API
- Approach: Systematic refactoring of each component
- Key decisions: Pure immediate-mode functions only

## DONE (Completed Sprints)
- [x] #116: refactor: Clean up build system to remove unnecessary complexity