# Semantic frame and retained runtime

This is the target model. Current `ui_node_t` uses a small fixed-size prototype
record; its existing fields are not a completed implementation of this contract.
Introduce each extension through the milestone and consumer that needs it.

## Representation and authority

Maintain three distinct representations:

1. Application domain state: authoritative documents, properties, operations,
   and document selection/history.
2. An owned semantic description: desired controls, relationships, values,
   actions, layout constraints, and presentation hints for one transaction.
3. Runtime/realized state: interaction sessions, caches, native resources,
   host geometry, and an accessibility projection for a published revision.

A semantic frame may use compact records and parent/range references rather than
heap-allocated OO widgets. Containers must nevertheless have explicit structure;
flat draw order alone cannot represent ownership, accessibility relationships,
scopes, overlays, or adaptive realization. The representation stays replaceable.

The facade exposes Fortran procedures, while internal data has explicit types.
No reflection, property-name string bindings, or `class(*)` value bag is required.
Variable-length owned UTF-8 replaces silent truncation of keys/text. Numeric
geometry and conformance tolerances use deliberately selected precision; pixel
snapping belongs to rendering and cannot corrupt stored scientific coordinates.

## Minimum semantic vocabulary

| Group | Contract information |
|---|---|
| Identity | Scoped stable key, logical owner, compatible role, generation |
| Structure | Parent/scope, ordering, label/control relationships, collection membership |
| Meaning | Role, label, description, value, range, selected/checked/enabled state |
| Operations | Available action IDs, owned typed parameters, update/commit intent |
| Layout | Intrinsic/min/preferred/max constraints, grow/shrink, alignment, spacing |
| Presentation | Theme/style tokens and optional host realization preference |
| Accessibility | Name, role, value/state, relationships, actions, focus order |
| Inspection | Transaction/semantic revision, diagnostics, provenance when generated |

A role is semantic, not a promise of identical appearance. Button and toggle are
not interchangeable merely because both can render as a rectangle. Disabled state
must agree across interaction, accessibility, and host realization.

## Identity and lifecycle

Keys are unique within an explicit scope. A collection key derives from its domain
object identity, never its current index or display label. A document/window scope
prevents accidental collisions between identical local keys. Strings and structured
keys are API options; hashing must detect collisions rather than equating them.

Reconciliation classifies unchanged, changed, moved, created, removed, and
incompatible-role replacements. Compatible identity retains UI-local state and
resources. Incompatible role or a changed owner creates a new generation even
when the visible key spelling is reused.

Removal cancels capture, editing, and owned callbacks/requests; releases resources;
and selects an explicit focus fallback. Visibility, offscreen virtualization, and
removal are distinct lifecycle conditions. A virtualized editor can keep a session
alive or commit/cancel before disposal according to a declared policy. Native popup
or drag ownership cannot disappear silently during reconciliation.

The application owns document selection if it affects operations or serialization.
Runtime owns caret and temporary selection within an editor. Hover/capture are UI
state; neither overwrites domain selection without an application operation.

## Editing sessions and values

A text session has key/generation, draft UTF-8, base domain revision/value,
caret/selection, composing range, validation status, and commit/cancel policy.
The platform text service may represent offsets in UTF-16 or another convention;
the adapter explicitly converts them without splitting a code point or grapheme.

A number field can contain `-`, `1e`, or an out-of-range draft while the application
still owns a valid number. Specify whether commit occurs on Enter, focus change,
or each valid edit. Invalid commit reports a validation error; it cannot silently
replace the domain value. Escape/cancellation and text undo have explicit behavior.

External changes during editing select an application policy: replace the draft,
preserve it with conflict indication, or reject the pending commit against its
base revision. Do not hide an authoritative second document value in a control.
Labels and ordinary committed controls update from application state directly.

Composition receives owned edit events for the target key; it need not expose a
persistent pointer to a caller's variable. Any convenient `intent(inout)` API
updates the caller only during composition, never from a later native callback.
Full IME handling is defined with the [platform boundary](PLATFORM_BOUNDARY.md).

## Layout and realized geometry

Logical graphical units are independent of terminal cells and device pixels.
Layouts support row/column, intrinsic/min/max, grow/shrink, alignment, spacing,
padding, overlay, scroll, split, and useful grid constraints. Theme/font/user-scale
inputs affect measurement. A multipass algorithm must have bounded convergence
and diagnose unsatisfiable constraints without rerunning user composition.

Separate desired constraints from realized host geometry. Native/DOM adapters can
measure and lay out their controls; report bounds, clipping, transforms, baseline,
and scale tagged with a realized revision. Pointer routing, focus visuals,
accessibility bounds, and inspection read that revision. Do not route input against
hypothetical canonical rectangles while a host displays something else.

A TUI adapter can present an inspector as pages or a list rather than quantizing a
wide desktop inspector into tiny cells. Semantic relationships and command access
survive adaptation; exact graphical parentage and pixels need not. Applications
can provide capability-aware composition without moving portable meaning into a
backend. A backend must report meaningful unsupported operations.

## Virtual collections and canvas

Virtual lists expose item count, stable key lookup, requested ranges, and bounded
item composition. A runtime requests visible/overscan ranges plus pinned active
items. Range changes schedule a transaction when new descriptions are needed;
measurement itself never calls arbitrary application composition. Building all
items and discarding most afterwards is not virtualization.

A TPX canvas has two interfaces: custom graphics/input and a semantic object/action
projection. The application supplies object IDs, kinds, labels, selected state,
editable properties, supported actions, and optional geometric bounds. Runtime
accessibility and TUI can traverse requested object ranges without decoding pixels.
A keyboard user must be able to select and manipulate relevant objects.

Canvas coordinate conversion uses explicit document/viewport transforms. Pan/zoom
are UI-local unless the application deliberately makes them domain values. Picking,
snapping, and history remain application behavior tested by TPX conformance.
Renderer primitive caches are derived data, keyed by document/object revisions.

## Accessibility and inspection

Accessibility is part of the semantic vocabulary from the first new control.
The host bridge maps roles/actions/relationships and bounds into actual platform
accessibility APIs or native DOM. It reconciles incremental changes and emits
appropriate notifications. Semantically exposing an action does not prove that
an OS screen reader can reach it; each host needs executed evidence.

Headless inspection reports frame/transaction IDs, keys, roles, values, enabled
states, commands, focus/capture, draft state, realized geometry, capabilities,
and event traces. Use stable structured records for assertions and agents.
Inspection of private application values must be an explicit application opt-in;
labels and text fields are not automatically a complete domain-state dump.

A future inspector edits constraints, labels, actions, theme tokens, or accessibility
metadata and emits reviewable ordinary Fortran changes. Generated edits carry source
provenance; the runtime tree is an inspection model, not an alternative authoritative
program. Screenshot tests still verify backend visual correctness.

## Invalidation and caches

Track semantic property changes separately from layout, paint, text-shaping,
accessibility, and host-resource dirtiness. Cache dependencies include role/key,
content revision, font/fallback, locale/direction, theme, user scale, constraints,
clip/transform, and device generation as appropriate. Resource loss invalidates
GPU caches without inventing a domain change.

A button's enabled change need not reshape unrelated text or tessellate the canvas.
Caret blink and backend animation can invalidate presentation without composition.
An idle runtime waits for events or deadlines; it does not automatically compose
on every display refresh. Explicit application invalidation is required when
arbitrary Fortran domain values change outside event delivery.

Do not skip arbitrary user composition subroutines as though they were pure.
Start with a whole semantic description per scheduled transaction and incremental
runtime work; introduce selective composition only under a new explicit, tested
contract. Measure allocations, text/layout work, dirty bounds, latency, and CPU.

## Source boundaries and acceptance

Existing files anchor incremental implementation: `fortui_core` owns orchestration,
`fortui_context` runtime context, `fortui_frame` semantic storage, `fortui_input`
normalized routing, `fortui_layout` constraints/measurement, `fortui_widgets`
composition procedures, `fortui_text` UTF-8/metrics/wrapping, and `fortui_canvas`
the retained canvas layer store. `fortui_backend` defines the backend interface
and `fortui_backend_registry` is the only module naming concrete backends
(`fortui_backend_headless`, `fortui_tui`, `fortui_gui_raylib`). The facade is
`fortui`. Extract commands, services, or reconciliation modules only as a slice
requires them.

Behavioral oracles cover reorder retaining focus, duplicate-key rejection,
incompatible-role cleanup, Unicode editing/IME persistence, invalid numeric draft,
external edit conflict, native realized-bound routing, bounded list emission,
canvas structural editing, and selective invalidation counts. Tests must observe
results independently of the implementation under test.
