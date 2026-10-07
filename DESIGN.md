# FortUI design

## Mission

Build a small, fast, portable UI system whose *application-facing* code is ordinary modern Fortran and whose semantic controls can run as GUI, TUI, headless automation, native mobile/desktop UI, and WebAssembly.

FortUI optimizes for four things simultaneously:

1. excellent application ergonomics;
2. deterministic semantics and testability;
3. minimal platform dependencies;
4. easy inspection and modification by AI coding agents.

No single implementation technique is allowed to become ideology.

## The model: immediate composition, retained runtime

"Immediate vs retained" conflates several independent choices. FortUI fixes them separately.

| Concern | FortUI choice |
|---|---|
| Application authoring | Immediate, compositional Fortran DSL |
| Application state | Caller-owned by default |
| UI interaction state | Retained by FortUI and keyed by stable semantic IDs |
| Current UI description | Re-composed from application state |
| Previous UI geometry | Retained for input routing and reconciliation |
| Layout/render caches | Retained when measurement proves useful |
| Rendering | Semantic frame lowered by a backend |
| Repainting | Event/dirty driven as backends mature |
| Native widgets | Backend option, not a core requirement |

The intended frame pipeline is:

```text
platform events
      |
      v
normalized input
      |
      v
route against previous semantic frame
      |
      v
Fortran composition DSL
      |
      v
current semantic frame
      |
      +--> layout / semantics / accessibility
      |
      v
backend renderer or native-control reconciler
```

This keeps the simple immediate API without forcing an immediate renderer.

## State

FortUI is not stateless.

The application owns domain state such as a selected TPX object, a file name, or a physical parameter. FortUI owns only UI state that cannot sensibly live in the model: focus, active pointer capture, hover, scroll positions, text-editing composition, animation state, cached measurement, and platform resources.

A control ID is semantic identity, not a rendering address. IDs must remain stable across frames when the logical control remains the same.

## Semantic frame

Widgets may not draw. They emit semantic nodes such as text, button, slider, checkbox, viewport, list, table, or text editor. A semantic node carries stable identity, role/kind, content and current value, geometry, interaction flags, accessibility semantics, styling/theme tokens, and backend-independent capabilities.

The current prototype implements the first subset. Accessibility roles and theme tokens are mandatory before 1.0.

## Layout and units

Application layout uses logical device-independent units. A graphical backend maps them to pixels using platform scale and font metrics. A terminal backend quantizes the same semantic geometry to character cells.

A GUI backend must never be constrained to a terminal grid merely to keep the source code shared.

Future layout work should add intrinsic sizing, grow/shrink constraints, scrolling, virtualization, overlays, and multipass measurement. Do not invent a general CSS clone.

## Backend boundary

A backend has two responsibilities:

1. convert platform events into normalized FortUI input;
2. present a semantic frame.

A backend may draw FortUI controls itself, reconcile them to native platform widgets, mix native widgets with custom drawing, serialize/remote the semantic frame, or render a terminal representation. Native appearance is therefore a backend policy instead of a permanent framework decision.

Raylib is a bootstrap graphical backend. termbox2 is the bootstrap terminal backend. Neither defines FortUI semantics.

## TUI and GUI from one code base

Controls preserve meaning, not pixels. A checkbox can render as a box in a GUI, `[x]` in a terminal, or a platform switch when a native backend decides that is the idiomatic representation.

Some graphical controls degrade on TUI. For example, a scientific canvas can become a textual summary, object list, coordinate inspector, or Braille/ASCII preview. Backends expose capabilities when application behavior genuinely must differ.

## Declarative languages and FortGen

The primary DSL is embedded Fortran. This follows the same ecosystem pattern as FortSym expressions and FortFEM weak forms: Fortran itself expresses the domain.

Do not add XAML/QML/JSON merely because other frameworks have markup. If an external declarative frontend earns its keep, it must compile into the same FortUI semantic model or generated FortUI calls.

FortUI owns UI semantics. FortGen may eventually provide shared source-emission mechanics after a real second producer demonstrates duplicated nontrivial code-generation logic. FortGen must not learn what a button or layout is.

## Agent-first API rules

The preferred API has a small vocabulary, regular named arguments, explicit stable IDs, no hidden reflection, no stringly-typed bindings to model properties, no code-behind lifecycle, deterministic semantic output, a headless backend, and machine-checkable diagnostics.

An agent should be able to infer the whole UI of a small application from one routine and test it without opening a window.

## Performance

Immediate composition is not permission to redo expensive work blindly. Retained runtime data may cache shaped text and glyph runs, layout measurements, large-list visibility/virtualization, tessellated vector paths, GPU resources, accessibility trees, and native control handles.

The semantic layer should support dirty/invalidation tracking so idle UIs do no work and complex applications need not fully re-layout or redraw every display refresh. Optimize only with measurements and behavioral oracles.

## Portability target

| Target | Preferred route |
|---|---|
| Linux | thin Wayland/X11/SDL-class platform adapter + renderer |
| Windows | Win32 platform adapter + D3D/WebGPU/Vulkan-class renderer |
| macOS | Cocoa adapter + Metal |
| iOS/iPadOS | UIKit adapter + Metal |
| Android | native activity/input adapter + Vulkan/OpenGL ES |
| Web | WebAssembly + WebGPU/Canvas bootstrap |
| Terminal | termbox2-class cell backend |
| Tests/agents | headless semantic backend |

Small C/Objective-C platform shims are acceptable where the OS ABI requires them. Application and framework semantics remain Fortran.

## Non-goals

- cloning Qt, GTK, CSS, or the DOM;
- preserving old FortUI APIs that contradict the mission;
- fake thread-safety or multi-window claims without backend evidence;
- abstraction layers created before two real implementations need them;
- platform-specific branches inside widgets.
