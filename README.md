# FortUI

FortUI is a Fortran-native semantic UI framework with declarative/immediate
composition over a retained incremental runtime. Its design aims to realize the
same application intent through native controls, custom graphics, web DOM,
terminals, and headless automation while preserving platform-specific capabilities.

The current implementation is an experimental pre-1.0 prototype: basic semantic
controls, previous-frame input routing, headless tests, termbox2 TUI, and optional
raylib GUI. Native widgets, DOM/WASM, mobile, full text/IME/accessibility, commands,
and incremental transaction scheduling are roadmap work.

## Current authoring API

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

Widgets describe semantics; adapters realize them. Application state remains
caller-owned, while FortUI retains UI-local interaction state and resources.
The design specifies one composition execution per scheduled transaction and
selective runtime updates; the prototype's explicit frame loop is the starting point.

[DESIGN.md](DESIGN.md) explains the architecture and links its detailed contracts.
[PLAN.md](PLAN.md) records completed foundations and the implementation sequence.
The [TPX experiment](docs/TPX_EXPERIMENT.md) is an early real-application acceptance
test alongside independent Pascal/LCL and C#/Avalonia implementations.

## Design principles

- Ordinary Fortran control flow describes UI intent with stable identity.
- Commands separate operations from menus, buttons, shortcuts, and other triggers.
- Domain, UI-local editing, and platform state have explicit owners.
- Native/custom realization adapts per control; ordinary web controls use DOM.
- TUI provides useful structural interaction rather than identical pixels.
- Accessibility and text/IME are semantic infrastructure.
- Headless inspection supports deterministic tests and agents; real host behavior
  still needs platform tests.

An optional external declarative frontend can later lower to the same semantic
model when a consumer needs it. FortGen may provide generic generation mechanics;
FortUI retains ownership of UI semantics.

## Build and run

TUI and headless:

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

The GUI demo requests `ui_init("auto", ...)` and selects an available graphical
backend first, then TUI. An explicit backend request must not silently fall back.
Raylib and termbox2 are replaceable adapters rather than framework semantics.

License: MIT. The API may change before 1.0.

AI assistance: this architecture documentation was prepared with GPT assistance;
project maintainers retain responsibility for its content and technical decisions.
