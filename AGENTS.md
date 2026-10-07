# FortUI agent rules

## Load the task contract

Before architectural work, read [DESIGN.md](DESIGN.md) as the project map,
[PLAN.md](PLAN.md) for current evidence and the next bounded task, and
[CI](.github/workflows/ci.yml) plus the relevant registered tests as verifiers.
Load the linked transaction, semantic, platform, or TPX contract when its subsystem
is involved. Review/evidence/escalation rules apply when their trigger arises.
Do not treat the target architecture as already implemented.

## Mission invariants

1. Ordinary Fortran is the primary authoring DSL. Preserve conditionals, loops,
   functions, types, and simple inline control ergonomics.
2. User code describes semantic intent; a retained incremental runtime maintains
   identities, editing sessions, resources, and realized presentation.
3. Composition runs once per scheduled semantic transaction, never speculatively
   during layout, painting, reconciliation, or accessibility queries. It is nonreentrant.
4. An activation is consumed at most once. Inline mutation can request a separate
   refresh transaction; commands have one execution owner. No exactly-once I/O claims.
5. The application owns committed domain state. Runtime drafts/caret/IME and caches
   are explicit UI-local state. Backends own platform resources and lifecycle.
6. Frames/events own their values. Never retain borrowed caller arguments across
   composition or async callbacks. Scoped keys and generations protect identity.
7. Widgets emit semantics; they never import/call GUI/TUI/render/native/WASM code.
8. Native, custom, and hybrid realization are per-control/backend policies. Ordinary
   browser controls use DOM; scientific graphics use a suitable custom surface.
9. TUI adapts meaning rather than graphical pixels. Canvas metadata must support
   structural editing, accessibility, and semantic inspection.
10. Accessibility roles/states/actions and text/IME ownership are core contracts;
    actual bridges and host behavior require executed platform evidence.
11. Platform services are asynchronous owned requests alongside the widget tree.
    Capabilities/extensions preserve host-specific functionality explicitly.
12. Logical graphical units, presentation tokens, and bounded multipass layout are
    separate from terminal cells and host pixels. Routing uses realized geometry.
13. Incremental rendering is demonstrated by invalidation and measurement. Do not
    silently memoize arbitrary application composition or compose every refresh.
14. Headless is a first-class semantic oracle; it does not prove native text,
    accessibility, browser permissions, or rendering quality.
15. FortUI owns UI semantics. FortGen supplies generic generation mechanics only
    after genuine reuse. Optional external formats lower to the same runtime.

## Application and scope rules

TPX is a three-track controlled experiment with independent Pascal/LCL, C#/Avalonia,
and Fortran/FortUI implementations. Share behavior/fixtures, not application
implementation code. Preserve the original TPX repository and the Pascal/LCL
programming model; widgetset work belongs underneath it. FortUI contains reusable
UI contracts, not TPX document/geometry/export code or another track's port.

Make the smallest complete change for the current slice. Report adjacent work.
Discover abstractions through consumers rather than framework hierarchies. Preserve
unrelated edits, stage explicit paths, and keep one controller responsible for
integration/promotion. Generated source is reproducible and carries provenance.

Use English for technical communication. Sign PR descriptions/comments and other
messages on Chris's behalf with `Chris&AI` on their own final line.

## Development and evidence

Use the Fortran skill and pinned resident `fo gremlin` feedback for Fortran code
work. Keep fpm tests, or project CMake presets/CTest when applicable, authoritative.
Repair reproducible development-tool/shared-dependency defects at their owner with
a focused behavioral reproducer, then recheck the consumer. Preserve existing work.

Tests need an independent behavioral oracle. No tests that simply check repository
text agrees with the patch. Run focused gates and required CI checks; broaden only
for unresolved evidence. Documentation uses prose/link/diff checks.

Before review, freeze an exact base commit and patch digest if uncommitted. Review
ownership, event delivery, freshness, failure, platform claims, and required behavior.
Record limitations and next actions explicitly; do not hide failing checks.

Do not add public widget-object lifecycles, reflection/string bindings, duplicated
authoritative domain values, a CSS clone, mandatory markup, a second runtime,
silent fallback from an explicit backend, dead compatibility, or unsupported
thread/multi-window/mobile/WASM/accessibility/performance claims. Keep CI strict.
Small C/Objective-C/JNI/JavaScript platform shims are acceptable; framework and
application semantics remain Fortran.
