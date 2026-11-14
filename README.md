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
call ui_run(settings)        ! loops natively; the browser calls it per frame

contains

subroutine settings()
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
end subroutine settings
```

The frame procedure composes one frame. Native hosts loop in `ui_run`; in the
browser `ui_run` returns and the browser calls the frame when something happened,
so state the frame uses belongs in a module. The explicit loop with
`ui_frame_begin` and `ui_present` still works on native hosts.

Keyboard shortcuts are asked for while composing: `if (ui_shortcut("mod+k"))
call open_palette()`, with chords such as `"j"`, `"?"`, `"Enter"` or `"g o"` (two
keys in a row). A text field keeps what is typed into it and gives up only
ArrowUp, ArrowDown, Enter and Escape, which is what a command palette needs.
`ui_focus(id)` moves the keyboard focus to a control and `ui_reveal(id)` scrolls a
widget into view in the browser.

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

Optional printing service (`-DENABLE_PRINT=1`, link `-lcups`):

```sh
make build-print
make test-print   # libcups decodes the pages; FORTUI_PRINT_TEST_PRINTER=QUEUE
                  # also submits a held job to that queue and cancels it
make test-print-system  # prints through a CUPS queue to a virtual printer
                        # (ippeveprinter, sudo for lpadmin) and checks the
                        # tray, media type, quality and margins it receives
```

Browser (LFortran with target `wasm32-unknown-emscripten` and an emscripten SDK
in `EMSDK_PATH`):

```sh
web/build.sh                                  # the demo into build/web
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

## Images and printing

`canvas_image(key, generation, rgba, x, y, width, height)` draws a retained
image into a world rectangle of a canvas; its pixels are uploaded once per
generation (raylib texture, terminal raster).

`fortui_print` is a printing service over CUPS. It lists printers and reports a
printer's paper sizes with their margins and borderless variants, media types,
trays, print qualities and raster resolution; from an IPP printer it also learns
which paper is loaded where, the ink levels and the printer's own names for its
media. The application composes each page as an sRGB raster of the whole sheet,
which is sent as PWG raster (`fortui_pwg`), so the page raster alone decides
scaling, cropping and borders. Without `-DENABLE_PRINT=1` every request returns
`PRINT_UNSUPPORTED`. Requests block until CUPS has answered.

## Dependencies and licences

FortUI is MIT licensed ([LICENSE](LICENSE)). Each optional part links its
dependency only when its build flag is given, so the core stays free of them.

| Part | Needs | Licence |
|---|---|---|
| Core, headless, terminal | a Fortran 2008 compiler; termbox2 (bundled in `src/c`) | MIT |
| GUI (`-DENABLE_GUI=1`) | raylib 5 or later; DejaVu fonts (bundled, embedded) | zlib; DejaVu/Bitstream Vera |
| Printing (`-DENABLE_PRINT=1`) | libcups 2.3 or later | Apache-2.0 |
| Browser | LFortran, emscripten | BSD-3-Clause; MIT/NCSA |

The API may change before 1.0.

AI assistance: this architecture documentation was prepared with GPT assistance;
project maintainers retain responsibility for its content and technical decisions.
