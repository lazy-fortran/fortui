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
An application injects a backend value, `call ui_init(headless_backend_t(), ...)`
or `call ui_init(raylib_backend_t(font_regular="..."), ...)`; the runtime keeps
its own copy. The optional `fortui_backends` registry extends the same generic
with `ui_init(name, ...)` (`headless`, `tui`, `gui`, or `auto`; `FORTUI_BACKEND`
overrides) and is the only module that names several backends. The core,
widgets, and facade use neither a concrete backend nor the registry, so an
application links only the platforms it uses. An unknown or unavailable backend
is an error, never a fallback.

The runtime calls only these bindings:

| Binding | Responsibility |
|---|---|
| `name`, `capabilities` | Identity and an honest `ui_backend_caps_t` (graphical, canvas layers, proportional text, event waiting, high DPI, pointer, text entry) |
| `init`, `shutdown` | Create/release all platform resources for `self%config` (window size, title, frame rate, vsync) |
| `poll(input, wait)` | Normalize platform events into `input_state_t` (named `KEY_*` keys, typed UTF-8 text, pointer, wheel, logical window size and scale); block for the next event only when `wait` is set |
| `present(frame, store)` | Realize one semantic frame without blocking |
| `install_text_metrics` | Publish per-code-point advances and line height to `fortui_text` |
| `should_close` | Host close request |
| `stats` | Presents, waits, and canvas uploads the backend performed (inherited) |

Idle rule: `present` never blocks. The runtime decides at each present whether
the next frame may wait (nothing continuous, requested, or scheduled as a
follow-up) and passes that decision to the next `poll`. Raylib waits in `poll`
only when the events gathered after the last present are empty; the terminal
backend blocks in `tb_poll_event`; headless counts requested waits.

Backends receive only backend-neutral data: the semantic frame (nodes with
style tokens and ellipsis requests, drawable canvas layer descriptors, labels,
view transforms in logical units), the read-only canvas store, and the input
snapshot. Canvas data lives in store layers keyed by canvas identity and key:
shared vertex layers (positions) and point or line layers that reference one.
The store copies caller data only when a generation or the referenced vertex
count changes and then bumps an internal data version; it drops line segments
that reference missing vertices. Each backend owns a `canvas_realizer_t` that
records the realized serial and versions per store slot, so it uploads a layer
only after a real change or after recreating its own resource, and it frees
resources when a slot is released or reassigned. Packed colours are RGBA bytes in
memory; positions are world units, transformed by `local = world * zoom + pan`.
No GL, GLSL, or raylib type, handle, or convention appears in the frame, widgets,
or public API. The same conformance scenario (`test/test_backend_conformance.f90`)
runs against headless and, in GUI builds with a display, raylib.

Implemented backends: `fortui_backend_headless` (fixed text metrics, resource-free
canvas realization), `fortui_tui` (termbox2 with checked `int` results and the
32-bit attribute width verified at init; terminal size and resize events in
logical units; character-cell metrics, one cell per code point and line whatever
the text size; canvas layers rasterized in Fortran by `fortui_raster` and shown
as braille cells, 2x4 dots per cell with one colour per cell, or as kitty
graphics images; see below),
`fortui_gui_sdl` (SDL3 with the SDL GPU API, compiled only with
`-DENABLE_SDL=1`; Vulkan SPIR-V shaders from `shaders/`, embedded by
`tools/gen-shaders.sh`; an event queue that splits a press and release arriving in
one frame over two frames; text with SDL_ttf), and `fortui_gui_raylib` (raylib
6/rlgl, compiled only with `-DENABLE_GUI=1`; one position texture per vertex
layer read by GLSL 330 instanced quads for points and lines). Both graphical
backends draw the display list of the theme painter (`fortui_paint`) and take
the theme's fonts from the installed fonts through fontconfig; FortUI ships no
fonts. A wake-up from another thread is not implemented. Only the Linux/X11
(Vulkan) routes have executed evidence; Windows, macOS (which needs Metal shaders
for SDL GPU) and Wayland are unverified.

Terminal canvas realization (`fortui_tui`, `fortui_raster`, `fortui_kitty`,
`src/c/fortui_tty.c`): at init the backend asks the terminal in-band (kitty
graphics query, cell size `CSI 16 t`, SGR-pixel mouse `DECRQM 1016`, truecolor
by `DECRQSS` and `XTGETTCAP RGB`, terminated by device attributes), so detection
works over ssh where environment variables do not cross. `FORTUI_TUI_GRAPHICS`
(`auto`, `braille`, `kitty`; `sixel` is not implemented and fails init) and
`FORTUI_TUI_COLOR` (`auto`, `truecolor`, `256`) make the choice explicit; an
explicit choice that cannot be honoured (kitty inside tmux, sixel, an unknown
value) fails init with a reason. Automatic choices are reported by
`ui_backend_description()`, for example `256 colours: no truecolor reply`.
Every canvas is rasterized when its geometry, view, fill or a layer version
changed: points as discs honouring `min_pixels` (braille draws discs wider than
three dots as one-dot rings), indexed lines with interpolated colour and alpha,
both clipped to horizontal bands that OpenMP draws in parallel with a raster
independent of the thread count. Braille cells take the dot colour of highest
contrast, brightened by at most 2x so faint edges stay visible; labels are text
cells. Kitty images (RGB, zlib, base64 chunks of 4096 bytes, one image id per
canvas, replaced in place, deleted at shutdown) are sent after the cells only
when the canvas changed; termbox2 then writes only changed cells, so an idle
application writes nothing. Mouse input uses any-motion tracking for hover and
reports pixels when the terminal supports mode 1016, else cell centres;
`input_state_t%pointer_slop` and `canvas_events_t%pointer_slop` carry the
remaining position uncertainty. Executed evidence: kitty 0.49, WezTerm
20260716, xterm 411, Alacritty 0.17 and tmux 3.8 (braille only) on Linux,
locally and through `ssh localhost`.

The interface is meant to grow without breaking backends: semantic host events
(DOM activation, edited text), realized geometry reported by hosts that lay out
controls themselves, a `measure` binding replacing the global metric table, and
a non-blocking frame driver for browser hosts are planned as additional bindings
with defaults or additional `input_state_t` fields (issue #149).

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
