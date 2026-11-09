# FortUI

FortUI is a Fortran-native semantic UI framework with declarative/immediate
composition over a retained incremental runtime. Its design aims to realize the
same application intent through native controls, custom graphics, web DOM,
terminals, and headless automation while preserving platform-specific capabilities.

The current implementation is an experimental pre-1.0 prototype: basic semantic
controls, previous-frame input routing, headless tests, termbox2 TUI, optional
raylib GUI, and a first browser backend with DOM controls. Native widgets, browser
canvas, mobile, full text/IME/accessibility, commands,
and incremental transaction scheduling are roadmap work.

## Current authoring API

```fortran
use fortui
use fortui_backends, only: ui_init          ! optional: backends by name

call ui_init("auto", 900, 640, "Settings", stat=stat)
do while (.not. ui_should_close())
    call ui_frame_begin()
    if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
    call text("Settings", style=UI_TITLE)
    call row_begin(8.0)
    if (button("save", "Save")) call save_document()
    if (button("quit", "Quit")) call ui_request_quit()
    call row_end()
    if (slider("volume", 0, 100, volume)) call volume_changed()
    do k = 1, size(options)
        if (checkbox("option", enabled(k), options(k), key=k)) call preferences_changed()
    end do
    call ui_present()
end do
call ui_shutdown()
```

Applications can also inject a backend value without the registry, for example
`call ui_init(headless_backend_t(), 800, 600, "test")` in tests or
`call ui_init(raylib_backend_t(font_regular="Inter.ttf"), 1200, 800, "app")`.
`fortui_testing` provides synthetic input and frame queries for automation.

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
fpm test          # or: make test
```

Optional raylib GUI (Fortran and C need `-DENABLE_GUI=1`, link `-lraylib`):

```sh
make build-gui
make test-gui     # also runs the backend conformance scenario in a window
make install      # library, modules and the DejaVu font licence under PREFIX
```

Browser (LFortran with target `wasm32-unknown-emscripten` and an emscripten SDK
in `EMSDK_PATH`):

```sh
web/build.sh                                  # web/example/web_demo.f90 into build/web
node test/web_browser_test.mjs build/web      # drives it in headless Chromium
```

Serve `build/web` over HTTP and open `index.html`. Ordinary controls are DOM
elements; the application loop yields to the browser between frames.

Run the terminal demo in a real terminal:

```sh
fpm run --example tui_demo
```

Canvases render in the terminal as braille cells or, in terminals with the kitty
graphics protocol (kitty, WezTerm), as pixels, also over ssh;
`FORTUI_TUI_GRAPHICS=braille|kitty` and `FORTUI_TUI_COLOR=truecolor|256` force a
choice. `fpm run --example tui_canvas_bench` measures the terminal raster cost.

The GUI demo requests `ui_init("auto", ...)` and selects an available graphical
backend first, then TUI. An explicit backend request must not silently fall back.
Raylib and termbox2 are replaceable adapters rather than framework semantics.

License: MIT. The API may change before 1.0.

AI assistance: this architecture documentation was prepared with GPT assistance;
project maintainers retain responsibility for its content and technical decisions.
