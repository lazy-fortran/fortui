# FortUI agent rules

Read `DESIGN.md` and `PLAN.md` before changing architecture.

## Mission invariants

1. The primary user language is ordinary modern Fortran.
2. Public authoring is immediate/compositional; the runtime may and should retain semantic state and caches.
3. Widgets emit semantics. They never import or call TUI, GUI, raylib, termbox2, WebAssembly, or native platform code.
4. GUI and TUI share controls and application logic, not pixel geometry.
5. Application/domain state is caller-owned unless UI-local retention is necessary.
6. Stable IDs define UI identity across frames.
7. Headless behavior is a first-class oracle, not a CI workaround.
8. Raylib and termbox2 are replaceable backends.
9. Do not add full XAML/QML/CSS/DOM semantics without a concrete consumer and a measured reason.
10. FortGen owns generic source-generation mechanics only after reuse is real; FortUI owns UI semantics.

## Engineering rules

Apply KISS, YAGNI, DRY, SRP, dependency inversion, and Clean Architecture strictly. Discover abstractions from vertical slices rather than designing a framework hierarchy in advance.

Do not create widget object lifecycles in the public API, add reflection or string bindings to application fields, duplicate persistent values inside widgets when the caller already owns them, silently fall back from an explicitly requested backend, claim unsupported thread/mobile/WASM/accessibility features, keep dead pre-1.0 compatibility layers, or weaken CI to make a change green.

Prefer a small behavioral test over a new abstraction. Generated code must be reproducible and carry provenance. Platform shims may be C/Objective-C when required by the OS, but framework semantics stay in Fortran.
