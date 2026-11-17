# FortUI

FortUI is a Fortran-native semantic UI framework with declarative/immediate
composition over a retained incremental runtime. Its design aims to realize the
same application intent through native controls, custom graphics, web DOM,
terminals, and headless automation while preserving platform-specific capabilities.

The current implementation is an experimental pre-1.0 prototype: basic semantic
controls, previous-frame input routing, headless tests, a terminal backend, a desktop
backend in Fortran (an X11 window drawn with Vulkan), and a browser backend with
DOM controls. Desktop apps choose between two themes drawn the same
on every backend: Fluent (Microsoft Fluent 2, light and dark, the default) and
Classic (Windows 95 as the Chicago95 desktop shows it). Native widgets, browser canvas,
mobile, full text/IME/accessibility, commands, and incremental transaction
scheduling are roadmap work.

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
`call ui_init(gui_backend_t(), 1200, 800, "app", theme_name="classic")`.
`fortui_testing` provides synthetic input and frame queries for automation.
Buttons take an `emphasis`: `UI_EMPHASIS_PRIMARY` for a view's main action (the
Fluent primary button, the Classic default button), `UI_EMPHASIS_QUIET` for a
subtle button.

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

The desktop backend (`fortui_gui`) needs no build flag and links no library:
the window comes from [fortwin](https://github.com/lazy-fortran/fortwin)
(libxcb, opened at run time), drawing from
[fortgfx](https://github.com/lazy-fortran/fortgfx) (Vulkan, opened at run time;
offscreen frames fall back to its CPU renderer), text from
[fortfont](https://github.com/lazy-fortran/fortfont) with the installed fonts it
finds, images from [fortimg](https://github.com/lazy-fortran/fortimg). The tests
render it offscreen and check pixels.

```sh
FORTUI_THEME=classic fpm run --example theme_gallery
make install      # library and modules under PREFIX
```

The print tests compare with libcups and talk to a virtual printer
(ippeveprinter), both from CUPS, when they are installed; neither is needed by
the library. `FORTUI_PRINT_TEST_PRINTER=QUEUE fpm test test_print` also submits
a held job to a real queue and cancels it.

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

Canvases render in the terminal as pixels with the kitty graphics protocol
(kitty, WezTerm, Ghostty, fortterm) or as sixel images (xterm, foot, tmux built
with sixel, fortterm), also over ssh, and otherwise as braille cells; inside tmux
the sixel path is the one that works. `FORTUI_TUI_GRAPHICS=braille|kitty|sixel`
and `FORTUI_TUI_COLOR=truecolor|256` force a choice. `fpm run --example
tui_canvas_bench` measures the terminal raster cost.

`ui_init("auto", ...)` and `ui_init("gui", ...)` take the desktop backend when an
X display is there, and "auto" then the terminal; `FORTUI_BACKEND=gui|tui|headless`
chooses. An explicit backend request must not silently fall back. The window,
GPU and terminal layers are replaceable adapters rather than framework semantics.

## Themes

The theme decides colours, metrics, type scale and fonts; the theme painter
(`fortui_paint`) turns the semantic frame into a display list of pixel-aligned
rectangles, lines and text that the desktop backend draws with Vulkan or on the
CPU alike. Square edges sit on whole pixels and glyphs are drawn
1:1 from atlases rasterized at the exact pixel size, so the interface stays sharp.

- `classic`: Windows 95 as the Chicago95 desktop theme draws it: #C0C0C0 faces,
  two-pixel bevels, default buttons with a black frame, dotted focus rectangles,
  sunken fields, 16 px scroll bars with arrows, 11 px bitmap Helvetica from the
  Chicago95 fonts and More Perfect DOS VGA for code.
- `fluent` (default), `fluent-light`, `fluent-dark`: Microsoft Fluent 2 as the Fluent UI web
  themes define it: neutral greys with visible 1 px strokes, brand blue, 4 px
  corners, 32 px controls, fields with a darker underline that turns into a brand
  underline with the focus, the Fluent type ramp and two-tone focus outlines;
  Segoe UI where installed, else its open metric twin Selawik, Cascadia Mono for
  code.

The user chooses with `FORTUI_THEME`, else `theme = classic` in
`~/.config/fortui/config` (`$XDG_CONFIG_HOME/fortui/config`); otherwise the
application's `theme_name`, else `fluent`. `ui_set_theme(name)` switches at
run time. `fluent` follows the desktop light/dark preference, including schedules
managed by the desktop. `fluent-light` and `fluent-dark` stay fixed. The browser
uses its preferred color scheme. Classic stays fixed.

FortUI ships no fonts: themes find their fonts among the installed ones
(fortfont reads the font folders, no fontconfig) and fall back with a warning
naming the package to install. Text is laid out as SDL_ttf with HarfBuzz did, so
layouts keep their positions; a character the face lacks comes from a fallback
font set on the face's own baseline.

In the browser a theme applies only when the application passes `theme_name`
(desktop-like web apps); otherwise the page keeps its own look and fonts, as a web
page should.

The terminal has its own look in the text-mode tradition: push buttons, entry
fields and bands in solid colour, the focused control in a highlight colour,
`[X]` check boxes, and a function key line at the bottom that lists the
shortcuts the application labels (`ui_shortcut("ctrl+s", label="Save")` shows
`Ctrl+S=Save`). Its colours are `tui_theme = auto` (the default: dark on a
terminal with a dark background, which FortUI asks the terminal for), `light`
or `dark`, in the config file or `FORTUI_TUI_THEME`. Every cell gets an
explicit colour, so the look does not depend on the terminal's own palette.

## Terminal emulator

With `-DENABLE_TERM=1` (link `-lutil -lpthread`) the `terminal` widget runs a
program on a pseudo-terminal and shows its screen. The terminal engine
(`fortui_vt`) is Fortran: an xterm-compatible parser and a screen whose
scrollback is a ring of lines, so scrolling copies no cells, with colours
resolved when text is written; a reader thread drains the program's output into
a ring buffer so the program never waits for drawing. It parses about 330 MB/s
of coloured text on one core. Images are decoded in Fortran too (kitty graphics
with raw, zlib and PNG data, and sixel). It draws the same character cells on every host: glyph by
glyph on the desktop and one terminal cell per cell inside another terminal.

```fortran
use fortui_term, only: term_t           ! native hosts only, not in `use fortui`
use fortui_terminal, only: terminal, terminal_view_t
type(term_t), target, save :: t      ! stays in place while it runs
type(terminal_view_t), save :: v
call terminal("term", t, v, 14.0, UI_FILL, UI_FILL)   ! the user's shell
```

The widget takes every key while focused (Tab included; Ctrl+Shift chords stay
with the application), copies the pointer selection with Ctrl+Shift+C, pastes
with Ctrl+Shift+V, scrolls back with the wheel and Shift+Page Up/Down, forwards
the pointer to programs that ask for mouse reports, and answers the device
attributes query with sixel support, so tmux passes images through.
`canvas_cells` draws such a grid of cells for any application.
[fortterm](https://github.com/lazy-fortran/fortterm) is the terminal emulator
built on it.

```sh
make build-term
make test-term    # real programs on a pseudo-terminal: text, colours, images,
                  # scrollback, keys and the widget on the headless host
```

## Images and printing

`canvas_image(key, generation, rgba, x, y, width, height)` draws a retained
image into a world rectangle of a canvas; its pixels are uploaded once per
generation (GPU texture, terminal raster).

`fortui_print` is a printing service over IPP, written in Fortran
(`fortui_ipp`): it talks to the local CUPS server, or straight to a printer
given by its `ipp://` URI. It lists printers and reports a printer's paper sizes
with their margins and borderless variants (named and ordered as libcups does),
media types, trays, print qualities and raster resolution; from an IPP printer
it also learns which paper is loaded where, the ink levels and the printer's own
names for its media. The application composes each page as an sRGB raster of
the whole sheet, which is sent as PWG raster (`fortui_pwg`), so the page raster
alone decides scaling, cropping and borders. Requests block until the server has
answered; encrypted connections (ipps) are not made.

## Dependencies and licences

FortUI is MIT licensed ([LICENSE](LICENSE)). The desktop backend's packages are
Fortran (fortzip, fortimg, fortfont, fortwin, fortgfx, all MIT); libxcb and the
Vulkan loader are opened at run time only. The remaining optional parts link their
dependency only when their build flag is given.

| Part | Needs | Licence |
|---|---|---|
| Core, headless, terminal | a Fortran 2008 compiler and a C compiler for the POSIX terminal and socket helpers in `src/c` | MIT |
| Desktop | at run time: an X server with libxcb, a Vulkan 1.3 driver | MIT; Apache-2.0 |
| Printing | a CUPS server or an IPP printer on the network | (none linked) |
| Terminal emulator (`-DENABLE_TERM=1`) | a POSIX pseudo-terminal (`forkpty`) and threads | (system) |
| Browser | LFortran, emscripten | BSD-3-Clause; MIT/NCSA |

Theme fonts are used from the system at run time, never shipped or linked:

| Theme | Fonts (Arch Linux package) | Licence |
|---|---|---|
| classic | Chicago95 fonts (`chicago95-fonts`), More Perfect DOS VGA (`ttf-perfectdos`) | GPL-3.0-or-later; free |
| fluent | Segoe UI if installed, else Selawik ([microsoft/Selawik](https://github.com/microsoft/Selawik)); Cascadia Mono (`ttf-cascadia-code`) | Microsoft; OFL-1.1; OFL-1.1 |
| (all, desktop) | for characters a face lacks, where installed: DejaVu Sans Mono (`ttf-dejavu`), Noto Sans Symbols 2 and Noto Color Emoji (`noto-fonts`, `noto-fonts-emoji`) | Bitstream Vera; OFL-1.1; OFL-1.1 |

The API may change before 1.0.

AI assistance: this architecture documentation was prepared with GPT assistance;
project maintainers retain responsibility for its content and technical decisions.

## File selection

`file_open_button` opens the desktop's native file chooser: the XDG desktop
portal on Linux, the Windows common dialog, or an Open sheet on macOS. The
terminal uses FortUI's themed chooser, which also serves as the desktop fallback
when the native service is unavailable. The browser opens its own file picker
directly from the button's user gesture. A selection owns either a desktop path
or browser bytes and a display name.

```fortran
type(file_dialog_t) :: picker
call file_dialog_poll(picker)
! Only the in-window fallback replaces document composition.
if (picker%active) then
    call file_dialog_show(picker)
    return
end if
call file_open_button("open", "Open photo...", picker, extensions=".png,.jpg,.jpeg")
if (picker%status == FILE_ACCEPTED) then
    ! Read picker%path on desktop, or picker%bytes in the browser.
    picker%status = FILE_IDLE
end if
```

Native requests are asynchronous. Keep composing the document while the system
dialog is open, and call `file_dialog_poll` each frame to collect its result.
`file_dialog_cancel` cancels a pending request. Closing the backend cancels its
native dialog too. Cancellation keeps the current document.

Linux loads `libdbus-1.so.3` at runtime and uses `xdg-desktop-portal` with a
FileChooser provider, such as the GTK or KDE portal. No GTK, Qt or D-Bus development
libraries are needed to build or link FortUI. Windows and macOS use system APIs.

The in-window chooser supports folders, location entry (Ctrl+L or Cmd+L), filename
filtering, hidden files, keyboard selection, Enter to open and Escape to cancel.
Errors keep the chooser open. Keep the current document until a
replacement has loaded successfully.

Native Windows and macOS windows use CPU bitmap presentation through Win32 and
AppKit. Linux retains X11/Vulkan. Build native platforms with fpm 0.13 or later,
whose default platform features select the required preprocessing macros. The
custom-drawn controls do not yet provide native IME or accessibility bridges.
