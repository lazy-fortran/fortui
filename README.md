# FortUI

FortUI is an experimental cross-platform user-interface library for modern Fortran. Its mission is to let one Fortran UI description drive graphical, terminal, headless, native-mobile, and WebAssembly frontends without forcing applications to depend on a heavyweight widget toolkit.

The public API is intentionally immediate and Fortran-native:

```fortran
call ui_frame_begin()

call text("title", "Settings")
call row_begin(8.0)
if (button("save", "Save")) call save_document()
if (button("quit", "Quit")) call ui_request_quit()
call row_end()

if (slider("volume", 0.0, 100.0, 1.0, volume)) call volume_changed()
if (checkbox("autosave", autosave, "Auto-save")) call preferences_changed()

call ui_present()
```

This is **not** a pure immediate-mode renderer. Application code composes the current UI each frame, while FortUI retains the previous semantic frame, interaction identity, focus, and other runtime state. Input is routed against retained geometry before the next composition. Widgets emit backend-neutral semantic nodes; only backend adapters render them.

See [DESIGN.md](DESIGN.md) for the architecture and [PLAN.md](PLAN.md) for the platform roadmap.

## Why this model

FortUI combines the strongest parts of several UI traditions:

- immediate/declarative application code: no widget-object lifecycle, callbacks, reflection, or UI/model synchronization layer;
- retained runtime semantics: stable identity, focus, interaction state, layout caches, accessibility, and future incremental rendering;
- backend-neutral controls: the same button or slider can become a graphical control, a terminal representation, or a native platform control;
- deterministic headless execution for tests and AI agents.

The embedded Fortran API is the primary DSL. An external declarative format may be added later as an optional frontend, but it must lower to the same semantic model rather than create a second UI architecture.

## Current backends

- **headless**: deterministic semantic-frame backend for tests and automation;
- **TUI**: termbox2, embedded through a small C ABI;
- **GUI**: raylib bootstrap backend, optional at build time.

Raylib and termbox2 are backend implementations, not FortUI's abstraction. Future backends can target Win32/Direct3D, Cocoa/Metal, UIKit/Metal, Android/Vulkan or OpenGL ES, WebGPU/WebAssembly, or another thin platform layer without changing application code.

## Build

TUI + headless:

```sh
fpm build
fpm test
```

Optional raylib GUI:

```sh
make build-gui
```

Run the terminal demo in a real terminal:

```sh
fpm run --example tui_demo
```

The GUI demo uses `ui_init("auto", ...)` and chooses an available graphical backend first, then TUI.

## Status

FortUI is pre-1.0 and its API may change aggressively. The current revision establishes the semantic architecture; production-quality text editing, Unicode shaping, IME, accessibility bridges, scrolling/virtualization, native-platform backends, and WebAssembly are roadmap work.

License: MIT.
