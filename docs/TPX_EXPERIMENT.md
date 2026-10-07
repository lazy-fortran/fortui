# TPX as the architectural acceptance experiment

The experiment is recorded separately from the original TPX repository. This
page defines FortUI's participation; it does not authorize changing TPX or
implementing all ports as part of a documentation revision.

## Three independent hypotheses

| Track | Question | Constraint |
|---|---|---|
| Pascal/LCL | Can the classic component paradigm reach the full target matrix? | Preserve TPX/LCL's programming model; extend widgetsets underneath |
| C#/Avalonia | What does a mature cross-platform framework provide? | Independent idiomatic C#, AXAML, controls, bindings, platform heads |
| Fortran/FortUI | Can semantic composition with a retained runtime improve the result? | Independent idiomatic Fortran domain and FortUI frontend |

Share behavioral specifications, fixtures, expected results, scenarios, and
measurement procedures. Do not share document, geometry, export, renderer, or
UI-runtime implementation code between the applications in the first experiment.
Implementation-independent harness infrastructure is permissible. A shared Fortran
domain core would answer a different question and belongs to a later experiment.

The common target goals are Windows, macOS, Linux, iOS/iPadOS, Android, and Web.
TUI is an additional FortUI capability measured separately. Framework support and
compiler targets do not imply that the corresponding TPX build works.

## Preserve the Pascal track

The final preservation rule supersedes an earlier adaptive-semantic LCL redesign.
Keep TForm/TControl/TWinControl/TCustomControl, component ownership, published
properties/RTTI, LFM streaming, the designer/Object Inspector, normal events,
TAction/action lists, TCanvas and drawing types, Align/Anchors/AutoSize/Constraints,
Application.Run's conceptual lifecycle, and TPX's object model/forms.

Portability work uses existing TWSControl/TWSWinControl and RegisterWSComponent
machinery. Investigate iOS, Android, and browser widgetsets underneath LCL rather
than converting the application to a DSL, MVVM, reactive state, or semantic frames.
Try ordinary panels/pages/splitters and layout properties first. Any necessary
adaptive component remains an ordinary designer-supported LCL component.

Measure untouched source and unchanged LFM rather than assume portability is free.
Near-unchanged compilation is a demanding success criterion. Fresnel can inform
platform glue research; replacing LCL with Fresnel changes the experimental question.

## Common behavioral oracle

A separate prospective `tpx-conformance/` package contains documents, expected
semantic results, geometry fixtures, interaction scenarios, and platform suites.
It does not become a shared application runtime.

Derive intended behavior from working TPX, representative documents, independent
mathematics, and adjudicated requirements. Existing defects are not automatically
requirements. Version ambiguities, tolerances, fixture changes, and decisions before
scoring implementations against them.

- Documents: load hierarchy, geometry, styles, labels, transforms; save/reload
  semantically. State unknown-data and rounding policies.
- Geometry: independently expected Bezier evaluation, bounds, transforms,
  picking, selection, snapping, zoom, and coordinate conversion.
- Exports: TikZ compiled with real LaTeX, content/geometry checks, and SVG
  structure. Semantic equivalence need not mean byte-identical serialization.
- Interaction: each track adapts the same scenario intent to its test machinery;
  assert domain results, dirty/history state, and action execution.

For example, dragging a Bezier point then undoing and redoing has specified object
identity, coordinates, and history results at each step. Fix viewport units and
input intent explicitly. A headless operation test does not prove native pointer
routing; backend integration tests complement the same scenario.

Common scenarios cover open/save-as, line/Bezier creation, select/multiselect,
snap, zoom/pan, label editing, clipboard, undo/redo, and TikZ export. Additional
apple/android/windows/web/tui suites cover platform capabilities such as stylus,
Pencil, files, sharing, back/navigation, DOM accessibility, and keyboard conventions.
Mark unavailable hardware/permissions as explicit gaps rather than passing tests.

## Lockstep slices and probes

Run the common suite in all three tracks at each slice. Early toolchain/lifecycle
probes cover all target goals, with explicit unimplemented or blocked cells.
Do not wait for all new widgetsets to be complete before learning from a document
slice on an available backend. Publish a per-track/per-target evidence matrix.

| Slice | Application result | FortUI pressure |
|---|---|---|
| 0 | Launch, actions/toolbar, canvas placeholder, inspector, quit | Lifecycle, identity, commands, layout |
| 1 | Load TpX, hierarchy, save/reload | Object metadata, collections, services |
| 2 | Line/text/Bezier drawing, zoom/pan | Canvas transforms and caches |
| 3 | Pick/select/drag/snap | Capture, routing, coordinates |
| 4 | Insert/property edit/delete | Editing drafts and reconciliation |
| 5 | Undo/redo and shortcuts | Command ownership and history routing |
| 6 | Mathematical labels and preview | Unicode/IME and asynchronous TeX work |
| 7 | TikZ/SVG and actual LaTeX compile | Export conformance and diagnostics |
| 8 | Mobile layout, touch/stylus, files | Adaptive realization and lifecycle |
| 9 | Browser execution, files, DOM, canvas | WASM/host ABI and browser semantics |

This is an experimental sequence, not evidence that any port is complete.
FortUI's own milestones bring TPX slices forward; they do not put TPX after an
exhaustive framework implementation. Keep framework/application ownership separate.

## Measurement

Record application effort separately from LCL widgetset work, FortUI construction,
compiler/tool repairs, and pre-existing framework infrastructure. Compare equivalent
features and target versions; publish missing capabilities rather than hiding them.

Measures include total/UI/domain/platform-specific LOC, dependencies, binary and
download size, startup, idle CPU, memory, frame time/input latency, accessibility,
native/browser integration, headless coverage, files touched per feature, and defects.
Record agent turns, tool calls, tokens, CI repair iterations, and human interventions
with task/model definitions. One LOC count or agent iteration is not a quality score.

Pin exact application/framework/spec commits, compiler/linker versions, build flags,
hardware/OS/display scaling, fixtures, fonts, and TeX setup. Define warm/cold runs,
repeat timings, and report distributions. Separate first implementation from feature
maintenance; independent correctness checks precede performance comparison.

Strengths are hypotheses: LCL may preserve RAD and minimize source disruption;
Avalonia may minimize new platform infrastructure; FortUI may improve semantic
inspection, Fortran integration, TUI, native/custom choice, and DOM behavior.
Text, accessibility, lifecycle, deployment, and ecosystem gaps can defeat those
hypotheses. Report negative evidence and change bad abstractions.

## Source checks, 2026-10-07

[Avalonia's official matrix](https://docs.avaloniaui.net/docs/supported-platforms)
lists the six target families with version-specific support tiers and describes
browser Skia/CanvasKit/WebGL rendering. This makes it a useful established control.

[Lazarus source](https://gitlab.com/freepascal.org/lazarus/lazarus) provides the
existing widgetset machinery. The final protocol preserves that model; assess
experimental interfaces explicitly before claiming missing or production support.

[Fresnel's platform table](https://fresnel.freepascal.org/docs/platforms/) documents
Android and browser routes; its [LCL integration](https://fresnel.freepascal.org/docs/lcl/)
runs Fresnel inside LCL. It is research precedent, not proof that original TPX
already runs on those targets through LCL.
