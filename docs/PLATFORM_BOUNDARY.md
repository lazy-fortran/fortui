# Platform boundary

This contract defines responsibilities, not a promise that the listed backends
exist. Implement and test a narrow consumer slice before generalizing its adapter.

## Realization policy

A backend can be native, custom-rendered, hybrid, semantic-hosted, terminal, or
headless. Choose per control where useful, with a declared backend policy.
The portable role does not select a universal rendering stack.

| Semantic intent | Possible realization |
|---|---|
| Toggle | UIKit switch, AppKit checkbox, Android switch, Windows control, HTML input, TUI marker |
| Text editor | Native editor, native editing service plus custom visuals, tested custom editor |
| Menu/action | Native menu, adaptive command surface, DOM controls, terminal commands |
| TPX canvas | Custom graphics plus semantic object/action projection |
| File/share/notification | Independent platform service request |

Hybrid controls need explicit shared coordinates, clipping, scroll, z-order,
focus, accessibility ownership, and lifecycle. Avoid duplicate accessibility
nodes when both a native editor and a custom visual surface represent one control.
Test overlays/popups above a canvas and transitions between native/custom focus.

Raylib and termbox2 remain bootstrap/reference implementations. Neither defines
portable semantics. Extract shared renderer machinery after two actual consumers
establish reuse; do not build all Metal/Vulkan/D3D/WebGPU implementations first.

## Platform services and extensions

Services include files, clipboard, drag/drop, sharing, notifications, URL handling,
application activation, permissions, and shortcuts. Widget descriptions reference
operations; services use independent asynchronous lifecycles.

A service request contains request kind/ID, owner/generation, origin transaction,
owned typed arguments, and cancellation metadata. Results distinguish success,
cancelled, denied, unsupported, and failed; include owned content or opaque handles.
A picker returns a platform document capability where appropriate, not an invented
portable absolute path. Browser blobs and mobile document handles need explicit
read/write operations and lifetimes.

Requests are routed through [transaction scheduling](TRANSACTIONS.md). Backend
callbacks enqueue events and never mutate borrowed application state. Document
replacement/window destruction cancels owned requests; delayed results are checked
against generation and domain revision before application dispatch.

Capability discovery reports unsupported, available, or permission-required and
relevant limits. Permission outcome can change availability and emits an update.
Examples include stylus hover, haptics, global shortcuts, file access, and sharing.
Capability tests should determine availability rather than scatter OS conditionals
through widgets. Backend-specific extension modules may expose genuinely unique
features without contaminating portable semantics.

Live Activities, Android App Widgets, Windows Jump Lists, or browser install prompts
are extensions, not artificial universal widgets. Portable services cover only
operations whose meaning genuinely matches. Platform lifecycle is separate from
window composition: activation, background/suspend/resume, termination, and resource
loss have explicit events. Mobile apps do not assume a perpetual desktop main loop.

## Text infrastructure

The editor contract connects a semantic editor, runtime editing session, and host
text service. The adapter handles IME/preedit/commit/cancel, dead keys, platform
selection, dictation, clipboard, keyboard prediction, handwriting, and applicable
spell checking. Availability differs by platform and control policy.

Use owned UTF-8 at the portable boundary and explicit conversion for platform
indices/encodings. Shaping, bidirectional layout, grapheme movement, fallback fonts,
selection rectangles, and candidate-window geometry cannot be replaced by iterating
bytes or drawing one code point per cell. TUI text width needs its own evidence.

Host-originated edits become typed events for a session generation. Reconciliation
updates committed state without destroying an active IME composition. Programmatic
mirror updates must not fire a second user edit/action through native callbacks.
Focus transfer, invalid drafts, external domain updates, and undo routing follow
explicit session policies. Fully custom text input is an implementation choice
requiring its own IME/accessibility evidence, not a purity requirement.

## Browser host

The intended browser backend uses Fortran/WASM for application execution,
semantic DOM/HTML for ordinary controls, and Canvas/WebGPU-class graphics for
scientific drawing. A small JavaScript host supplies browser lifecycle and APIs.

Prefer real buttons, inputs, textareas, links, labels, and semantic document
structure. Augment with ARIA only where native semantics do not express the intent.
Do not place an invisible duplicate UI behind a whole-application canvas and call
that equivalent browser integration.

Native DOM provides mature text/input behavior, but browser Find cannot discover
text drawn only inside the TPX canvas. Application URLs, navigation, Back/Forward,
selection, responsive flow, and hyperlink semantics need explicit design and tests.
Choose which state is navigable; do not serialize an entire mutable document into
history implicitly. Keep browser file access and storage capability-based.

Some APIs need transient trusted user activation or permissions. The trusted event
bridge must start/reserve eligible service interactions before an asynchronous
boundary loses activation. A later generic dispatcher cannot synthesize a browser
user gesture. Describe unsupported or denied outcomes honestly.

Allow DOM layout to determine realized geometry where suitable. Observe host layout
changes and feed bounded updates back to the runtime. Do not translate the whole
of CSS into the portable semantic IR. The API can expose presentation hints or
web-specific extensions without making CSS the core framework layout language.

WASM compiler qualification exercises real Fortran allocation, owned strings,
polymorphism where used, callbacks, numeric precision, and lifecycle. Pin exact
compiler/target/linker/browser versions. A hello-world demonstration is insufficient.
TeX preview is a separate local-engine/service capability; DOM rendering does not
compile arbitrary TeX documents.

## Implemented backend interface

`fortui_backend` defines the abstract `ui_backend_t` that every backend extends.
The runtime core owns one instance and only calls these bindings:

| Binding | Responsibility |
|---|---|
| `name`, `capabilities` | Identity and an honest `ui_backend_caps_t` (graphical, canvas layers, proportional text, event waiting, high DPI, pointer, text entry) |
| `init`, `shutdown` | Create/release all platform resources, including retained canvas resources |
| `poll` | Normalize platform events into `input_state_t`; report logical window size and framebuffer scale |
| `present` | Realize one semantic frame; may block for events afterwards when the runtime allows idle waiting |
| `install_text_metrics` | Publish per-code-point advances and line height to `fortui_text` for layout |
| `should_close` | Host close request |

Backends receive only backend-neutral data: the semantic frame (nodes, canvas
layer descriptors with key/kind/generation/count, labels, view transforms in
logical units), the canvas store with owned layer arrays, and the input
snapshot. Canvas layers are realized through `canvas_store_t%realize`, which
reports whether vertex or index data must be uploaded (generation changed or the
backend recreated its resource) and maintains backend-neutral upload counters.
A backend frees its resources when a store slot is released or reassigned
(slot `serial`). Packed colours are RGBA bytes in memory; positions are world
units, transformed by `local = world * zoom + pan`. No GL, GLSL, or raylib type,
handle, or convention appears in the frame, widgets, or public API.

`fortui_backend_registry` is the only module that names concrete backends.
`ui_init` takes an explicit name (`headless`, `tui`, `gui`, or `auto`;
`FORTUI_BACKEND` overrides); an unknown or unavailable backend is an error.
Implemented backends: `fortui_backend_headless` (fixed text metrics, resource-free
canvas realization), `fortui_tui` (termbox2; cell-mapped fixed metrics, canvas
shown as a semantic summary), and `fortui_gui_raylib` (raylib 6/rlgl, GLSL 330
instanced quads for points and lines, bundled DejaVu Sans subset with a font
override, idle waiting through raylib event waiting). A wake-up from another
thread is not implemented. Only the Linux/X11 raylib route has executed evidence;
the Windows and macOS raylib routes are unverified.

## ABI, threading, and ownership

Use `iso_c_binding` interoperable scalars and explicit pointer/length views at a
narrow foreign boundary. Do not expose allocatable/deferred-length strings or
polymorphic Fortran objects as though they were C structs. Document who allocates,
copies, frees, and retains each buffer, including callback payloads.

Prefer generation-checked opaque handles for windows, editors, services, graphics,
and callbacks. A native callback may reference an application handle only while
its owner remains registered. Release/disconnect callbacks before freeing owners.
No backend stores a pointer to a temporary argument or a stack-local widget value.

Composition, dispatch, and publication belong to the designated UI execution
context. Worker threads use owned messages/snapshots and marshal completions.
Coarrays or Fortran purity do not automatically make native widget access safe.
Do not advertise thread safety, multi-window support, or mobile lifecycle correctness
without tests. Define context selection explicitly before adding those APIs.

Foreign code is acceptable for OS lifecycle, ABI, and renderer bindings. Application
operations, semantic definitions, layout policy, and reconciliation remain Fortran.
Track glue responsibilities, dependencies, binary cost, and maintainability; a
language percentage alone does not prove architectural quality.

## Target routes and evidence

| Target | Candidate route | Evidence needed before support claims |
|---|---|---|
| Windows | Native/hybrid controls and a suitable custom canvas | Lifecycle, DPI, IME, shortcuts, UI Automation, services |
| macOS | AppKit/Cocoa plus custom canvas, potentially Metal | Focus, text, menus, accessibility, Retina, files |
| Linux | Lightweight/custom or native host plus portals | Selected window-system route, IME, AT-SPI, scale, services |
| iOS/iPadOS | UIKit integration plus custom canvas | ARM64/AOT build, lifecycle, text, touch/Pencil, accessibility |
| Android | Native controls/services plus custom graphics | Compiler/ABI, lifecycle, IME, back, stylus, accessibility |
| Web | DOM plus canvas and Fortran/WASM | Compiler features, trusted services, navigation, DOM semantics |
| Terminal | termbox2-class host | Input, resize, Unicode width, structural editing |
| Headless | Owned semantic/runtime state | Deterministic transactions and independent behavioral oracle |

AppKit/UIKit/WinUI/Metal/Vulkan/WebGPU are possible implementation routes, not
requirements to ship every toolkit or renderer. Headless, termbox2, and optional
raylib are the current adapters. Desktop-native, mobile, and DOM backends are planned.

Backend tests cover native control edit callbacks, IME composition, real keyboard
focus, clipboard/file cancellation, platform accessibility, canvas overlays,
scaling and transformed hit testing, lifecycle/resource loss, and actual deployment.
Screenshot checks validate rendering; independent semantic assertions validate
application results. No single headless suite proves those platform properties.

## Primary references

Verify the relevant host documentation again when implementing a versioned adapter.

- [Native HTML and ARIA](https://www.w3.org/TR/html-aria/).
- [Browser user activation](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/User_activation).
- [History integration](https://developer.mozilla.org/en-US/docs/Web/API/History_API/Working_with_the_History_API).
- [Composition events](https://developer.mozilla.org/en-US/docs/Web/API/Element/compositionend_event).
- [Apple accessibility](https://developer.apple.com/accessibility/).
- [Android accessibility](https://developer.android.com/guide/topics/ui/accessibility).
- [Windows UI Automation](https://learn.microsoft.com/en-us/windows/win32/winauto/entry-uiauto-win32).
- [AT-SPI](https://gitlab.gnome.org/GNOME/at-spi2-core).
