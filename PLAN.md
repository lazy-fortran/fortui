# FortUI delivery plan

[DESIGN.md](DESIGN.md) is the principle layer. The detailed contracts define desired
behavior; unchecked milestones below are not shipping capabilities. Begin each
implementation task with this plan, the relevant contract, and existing CI/tests.

## Current evidence and next task

Base revision `8a0bc0872687e9a977e5e06fb503b2f40c837dab` established a prototype
semantic frame, previous-frame input routing, simple logical layout, basic controls,
headless tests, termbox2 TUI, and optional raylib GUI. The documentation redesign
adds contracts and a delivery sequence; it does not implement native/DOM/mobile,
commands, transaction scheduling, text services, or incremental invalidation.

Next implementation task: M1, a bounded headless transaction/command slice. Implement
one activation token, serialized dispatch, one composition invocation, and the
inline-refresh case. Preserve current controls and tests. Avoid building all action,
service, or platform abstractions at once. Record the exact evidence commit when done.

## Consumer slice: canvas resources, text, idle (branch `canvas-resources`)

Driven by the brainview graph viewer (~8k nodes/38k edges, 10x headroom). Evidence:
`test/test_canvas_text.f90` (headless) and `example/canvas_bench.f90` (raylib,
Linux/X11, RTX 5060 Ti). Windows/macOS routes are unverified.

- [x] Backend interface `ui_backend_t`; registry is the only module naming
      several backends.
- [x] Retained canvas layers (points, indexed lines) keyed by canvas/key with
      generations; upload only on generation change; backend-neutral counters.
- [x] Canvas view transform per frame (no re-upload); bounded canvas labels.
- [x] Canvas pointer semantics: hover, press, click, double click, drag with
      capture (released on button-up or widget removal), wheel; world coordinates.
- [x] UTF-8 text measurement via backend metrics; bundled DejaVu Sans subset.
- [x] Scrollable wrapped text (wheel, scrollbar drag, keys, light Markdown headings).
- [x] Single-line UTF-8 text input (caret, Backspace/Delete/Home/End, Enter).
- [x] Idle waiting with one-shot/continuous frame requests; split layout, resize.
- [ ] IME/preedit, selection, clipboard; wide-character TUI widths.
- [ ] Partial-range canvas uploads; canvas semantic object projection.

API cleanup after review R1 (brainview `handoff/R1-fortui-review.md`). Evidence:
`test_fortui`, `test_canvas_text` and `test_backend_conformance` (headless with the
CI flags; conformance also against raylib in a real X11 window via `make test-gui`),
LFortran 0.67.0-460 native build of all sources running `test_fortui` and
`test_canvas_text`, brainview headless tests and its real-display script.

- [x] Backend injection: `ui_init(backend_value, ...)`; the core, widgets and
      facade use no concrete backend; optional `fortui_backends` registry adds
      `ui_init(name, ...)`. Raylib module and bundled fonts compile only with
      `-DENABLE_GUI=1`; `make install` installs the DejaVu licence; CI checks the
      embedded font source against the font files.
- [x] One idle rule: `present` never blocks, `poll(input, wait)` waits only when
      the previous present allowed it; `ui_frame_begin` has no timeout.
- [x] Store read-only for backends; realized versions, upload counters and GPU
      resources live in backend components (`canvas_realizer_t`, `stats`).
- [x] Shared vertex layers (`canvas_vertices` + `canvas_points`/`canvas_lines`
      overloads; self-contained forms kept); segments revalidated when the vertex
      count shrinks; empty arrays; duplicate layer keys reported; kind change and
      slot growth covered.
- [x] Backend-neutral `KEY_*`; pure `tui_map_key`; terminal size and resize in
      logical units; termbox2 `int` results bound as functions and checked (#150).
- [x] Identity: static text without id, container scopes, `key=` in loops,
      duplicate ids reported and skipped; container balance checked at present.
- [x] Authoring: `style=`/`size=`, `UI_FILL`, `ellipsis=`, three-pane
      `split_begin(id, first=, last=, gap=)`, `tabs`, integer/real `slider`,
      `ui_str`; Escape is an ordinary key (`ui_set_escape_quits` removed);
      `view`/`viewport` removed.
- [x] Follow-up frame only after consumed input (activation, toggle, changed
      value, canvas click, handled shortcut); previous frame swapped, not copied.
- [x] `fortui_testing` holds injection, statistics and frame queries.
- [ ] Semantic host events (`input_state_t%events(:)` routed through widgets),
      realized-geometry feedback from hosts that lay out controls, and a
      non-blocking frame driver for browser hosts (#149, review F1).
- [ ] `measure(text, size, style)` backend binding replacing the global metric
      table (#149, review F3).
- [ ] Text field draft session or documented commit-per-edit policy in
      SEMANTIC_MODEL (review F5; `text_input` currently commits every edit).
- [ ] Owned variable-length node text, ids and layer keys instead of 512/96/128
      character fields (#149, review F7).
- [ ] Context-owned layout stack and text metrics instead of module state;
      `ui_shutdown` resetting all of it (#149, review F8).

## P0: completed architectural reset

- [x] Ordinary Fortran is the primary embedded DSL.
- [x] Immediate composition produces a backend-neutral semantic frame.
- [x] Previous frame retained for identity/input routing.
- [x] Backend rendering removed from widgets.
- [x] Unused retained `node` API removed.
- [x] Explicit headless backend and semantic behavioral tests.
- [x] Graphical layout expressed in logical units rather than terminal cells.
- [x] Raylib/termbox2 remain replaceable backend details.
- [x] Project rules and CI aligned with the semantic architecture.

These completed items do not imply the broader target contracts below are complete.

## M1: transaction and command correctness

- [ ] Owned normalized events, activation tokens, transaction/revision IDs.
- [ ] One composition per scheduled transaction; nonreentrant serialized execution.
- [ ] Preserve two discrete actions; consume one activation at most once.
- [x] Inline mutation schedules one activation-free follow-up; explicit invalidation.
      Evidence: widgets that consume input schedule one follow-up frame,
      `ui_request_frame` remains explicit (`test_fortui`, `test_canvas_text`).
- [ ] Optional command metadata and one dispatcher/handler owner, with live guards.
- [ ] Unified button/menu/shortcut intent without duplicate command execution.
- [x] Scoped keys and duplicate diagnostics (`test_fortui`).
- [ ] Generation-based stale-event rejection.
- [ ] Failure/publication/shutdown behavior from the transaction contract.

Acceptance: independent action/composition counters, stale-action rejection,
post-save status refresh, failure without repeated side effects, and an idle/wake
probe. Extend [existing tests](test/test_fortui.f90); do not test patch text.

## M2: first TPX shell and independent document fixture

- [ ] Establish external TPX/FortUI consumer scope and shared conformance version.
- [ ] Shell with actions, canvas placeholder, inspector, and lifecycle.
- [ ] Independent Fortran load/hierarchy/save/reload fixture in the application.
- [ ] Structural canvas/object metadata for headless and useful TUI inspection.
- [ ] Owned asynchronous file request/result with cancellation and generations.
- [ ] Narrow first native/hybrid or DOM host probe, alongside bootstrap adapters.

Application document/geometry/export code belongs to TPX/FortUI, not FortUI.
The Pascal and Avalonia tracks remain independent. Start target toolchain probes
now; publish unsupported cells without blocking all document work.

## M3: canvas interaction and layout

- [ ] Render lines/text/Bezier in the consumer; explicit document/view transforms.
- [x] Pointer capture, keyboard focus, hover, drag cancellation, zoom/pan.
- [ ] Independent pick/selection/snap/transform scenarios in the consumer oracle.
- [ ] Intrinsic/min/max sizing, grow/shrink, alignment, spacing, padding.
- [ ] Split/overlay/scroll and adaptive inspector only as the slice needs them.
- [ ] Host realized bounds and scale feed input/accessibility geometry.
- [ ] Measured canvas resource caching and selective paint invalidation.

Acceptance: known geometry results, capture released on removal/cancellation,
high-DPI transformed hit tests, and GUI/TUI access to the same document operations.
Multipass layout must not reexecute application composition.

## M4: property editing, history, text, accessibility

- [ ] Owned variable-length UTF-8 fields and semantic roles/relationships.
- [ ] Draft editor, selection/caret, valid commit/cancel, external-revision conflict.
- [ ] Native-integrated IME/preedit/commit and clipboard in the selected host.
- [ ] Document undo/redo command routing distinct from focused text-edit history.
- [ ] Semantic accessibility names/states/actions/focus order; first actual bridge.
- [ ] Theme tokens and user font/scale/preferences independent of semantics.
- [ ] TPX label edit/preview and asynchronous revision-safe completion.

Acceptance: partial numeric drafts, Unicode/IME persistence, stale completion,
actual host focus/text/accessibility, and independent document-history scenarios.
Do not defer semantic accessibility until after all controls are implemented.

## M5: export, incremental runtime, and scale

- [ ] Consumer TikZ/SVG exports checked against independent common expectations.
- [ ] Real LaTeX compilation with pinned fixture/package/font environment.
- [ ] Dependency invalidation for shaping/layout/paint/accessibility/host resources.
- [ ] Idle wait/deadline behavior; runtime-only caret/animation updates.
- [ ] Virtual collections request bounded ranges and retain active item identity.
- [ ] Benchmarks for allocations, memory, idle work, frame/input latency.

Acceptance: semantic export equivalence, no repeated unrelated shaping/layout,
bounded work for a large collection, and no unsupported performance claims.

## M6: native and DOM realization breadth

- [ ] First desktop adapter supports ordinary native/hybrid controls and custom canvas.
- [ ] Second independently implemented host validates shared abstractions.
- [ ] Platform-specific menus, services, text, and accessibility evidence per host.
- [ ] Browser semantic DOM controls plus custom canvas; explicit URL/history behavior.
- [ ] Actual Fortran/WASM feature probes and runtime, including strings/callbacks.
      Evidence 2026-10-13: LFortran main `0cd29dede1` (LLVM backend, target
      `wasm32-unknown-emscripten`) compiles all `src/` modules unchanged and
      `test_fortui` passes in Node and Chromium. `test_canvas_text` needs
      `--realloc-lhs-arrays` (off by default in LFortran) and then passes natively.
      Flang 23.1 cannot target wasm (`Target.cpp: target not implemented`, no
      wasm32 intrinsic modules or runtime). Callbacks are not yet probed.
- [ ] Browser `web` backend implementing `ui_backend_t`: WebGPU canvas through
      emscripten `webgpu.h` and `html5.h` events, ordinary controls as DOM
      elements, `requestAnimationFrame` frames with JSPI/Asyncify yielding at
      `ui_present`. No raylib or window library in the browser.
- [x] Correct termbox2 C binding signatures (C `int` results bound as
      subroutines); harmless on x86-64, a trap on wasm. Fixed for #150: all
      results are `integer(c_int)` functions and checked; `tb_attr_width` must
      report the 16-bit `uintattr_t` matching the Fortran binding.
- [ ] Optional: the same WebGPU backend on desktop through Dawn or wgpu-native.
- [ ] Trusted browser service activation, permission/file/storage behavior.
- [ ] Keep raylib as a useful reference; no explicit-backend silent fallback.
- [ ] SDL3 + SDL_GPU backend implementing `ui_backend_t`.
- [ ] Native hybrid hosts (GTK4, AppKit, Win32) with an embedded custom canvas.
- [ ] Optional direct Vulkan/Metal/D3D12 canvas renderers.
- [ ] Executed raylib evidence on Windows and macOS (GL 3.3/4.1 core, Retina).

Desktop routes include Windows, macOS, and selected Linux hosts. Renderer choice
follows measured consumer needs; do not require every GPU API before proving a slice.

## M7: mobile and full experiment target matrix

- [ ] Native ARM64/compiler/ABI/linker probes for actual application features.
- [ ] UIKit and Android lifecycle, suspend/resume/resource-loss handling.
- [ ] Adaptive inspector, touch, stylus/Pencil where available, system files/share.
- [ ] IME, accessibility, keyboard/modality transitions, back/navigation semantics.
- [ ] Execute common/platform conformance suites on real target builds/devices.
- [ ] Record per-track/per-target capabilities, failures, effort, and measurements.

Probe difficult compiler/lifecycle paths early in M2 rather than discovering all
feasibility gaps here. Only executed evidence promotes a target to supported.

## M8: optional tooling and frontends

- [ ] Semantic inspector edits emit ordinary Fortran with source provenance.
- [ ] External declarative frontend only after a measured application need.
- [ ] Lower optional frontends into one semantic IR/runtime.
- [ ] FortGen reuse only for proven generic emission/serialization infrastructure.

This milestone must not delay application correctness or essential platform quality.

## Verification and promotion

Existing [CI](.github/workflows/ci.yml) and fpm registered tests remain authoritative
for the current semantic core. Code changes preserve strict warnings and backend
import boundaries. Use the Fortran skill and pinned resident `fo gremlin` workflow
when developing Fortran; keep fpm/CMake registered checks authoritative.

Each implementation records exact commits/toolchains, its independent behavioral
oracle, focused test results, and any required host evidence. Review uncommitted
work against an exact base and patch digest. One controller owns integration and
promotion. Preserve unrelated work and stage explicit paths.

Documentation changes receive prose, link, and diff checks; they do not need
implementation-mirroring tests. Headless success does not establish IME/native/DOM
correctness. Do not weaken checks, hide failures, claim unexecuted platform support,
or present planned work as complete. Repair reproducible tool/dependency defects
at their owning repository under the applicable development rules.
