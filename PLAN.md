# FortUI plan

## P0 — architectural reset

- [x] Keep Fortran as the primary embedded UI DSL.
- [x] Keep immediate composition ergonomics.
- [x] Introduce a backend-neutral semantic frame.
- [x] Retain the previous frame for identity and input routing.
- [x] Remove backend rendering from widgets.
- [x] Remove the unused retained `node` tree API.
- [x] Add an explicit headless backend.
- [x] Stop expressing graphical layout as terminal cells.
- [x] Make raylib and termbox2 backend details rather than framework semantics.
- [x] Replace drift-era tests with semantic behavioral tests.
- [x] Rewrite project rules and CI around the mission.

## P1 — interaction and text quality

- [ ] UTF-8 throughout the public API and semantic frame.
- [ ] Text input control with selection, cursor, clipboard, undo/redo.
- [ ] IME composition contract and platform adapters.
- [ ] Semantic accessibility roles, labels, values, actions, and focus order.
- [ ] Theme tokens separated from control semantics.
- [ ] Pointer/touch/stylus normalization, capture, hover, gestures.
- [ ] Keyboard shortcuts and command routing.

## P2 — layout and scale

- [ ] Intrinsic measurement and min/preferred/max sizing.
- [ ] grow/shrink constraints for rows/columns.
- [ ] overlays, dialogs, menus, tabs, split views.
- [ ] scrolling with retained offsets.
- [ ] virtualized lists/tables/trees.
- [ ] deterministic multipass layout where one pass cannot know intrinsic size.
- [ ] dirty tracking and cached text/layout/vector work.

## P3 — platform architecture

Implement a thin platform boundary and at least two independent graphical backends before extracting more shared backend abstractions.

- [ ] Windows native platform adapter.
- [ ] macOS Cocoa adapter.
- [ ] Linux Wayland/X11 or SDL-class adapter.
- [ ] accessibility bridge for each supported desktop platform.
- [ ] renderer abstraction validated by at least two real renderers.
- [ ] keep raylib as a bootstrap/reference backend if it remains useful.

## P4 — mobile and WebAssembly

- [ ] Android native lifecycle/input/IME/accessibility adapter.
- [ ] iOS/iPadOS UIKit lifecycle/input/IME/accessibility adapter.
- [ ] native ARM64 Fortran build probes.
- [ ] LFortran/WASM compile gate for the semantic core.
- [ ] browser host shim kept minimal and outside application code.
- [ ] WebGPU renderer or a small portable fallback.
- [ ] web accessibility semantics bridge.

## P5 — TPX vertical slice

Use TPX as the first serious application oracle: open a TPX document, render its object model in a canvas, select and snap, create/move a curve, edit a math label, undo/redo, save/reload, and export TikZ and compile it.

Run the same application semantics through GUI, TUI/headless, and eventually native mobile/web backends. This vertical slice decides which abstractions are actually needed.

## P6 — optional declarative frontend

Only after the embedded DSL has real TPX experience:

- [ ] decide whether external declarative source solves a measured problem;
- [ ] if yes, define a small syntax that lowers to the FortUI semantic model;
- [ ] do not expose a second runtime or binding model;
- [ ] reuse FortGen only for genuinely shared code-emission mechanics.

## Required gates

Every architectural change must preserve headless semantic tests, no backend import in `fortui_widgets`, one application-facing semantic API for GUI/TUI, deterministic IDs and frame contents, strict compiler warnings in CI, no ignored test failures, no performance claim without a benchmark, and no platform-support claim without executed evidence.
