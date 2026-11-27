# FortUI delivery plan

[DESIGN.md](DESIGN.md) is the principle layer. The detailed contracts define desired
behavior; unchecked milestones below are not shipping capabilities. Begin each
implementation task with this plan, the relevant contract, and existing CI/tests.

## Current evidence and next task

Base revision `8a0bc0872687e9a977e5e06fb503b2f40c837dab` established a prototype
semantic frame, previous-frame input routing, simple logical layout, basic controls,
headless tests, termbox2 TUI, and optional raylib GUI. The documentation redesign
adds contracts and a delivery sequence; it does not implement native/DOM/mobile,
commands, transaction scheduling, text services, or incremental invalidation.

Next implementation task: B7 below. M1 stays open and is taken up by B7.

## B: best-of-breed through a demanding application (Chris, 2026-11-27)

Goal: the best user interface library there is, in Fortran, judged by what a
modern collaborative engineering application needs on Linux desktop and in the
browser. The acceptance application is stellim (a private multi-user design
model: 3D view, live edits, chat, review). Each item lands with headless tests,
a desktop check and a browser check, and replaces a workaround in stellim.
Redesigning existing APIs is allowed where an item needs it; all downstreams are
ours and move with the change.

- [x] B1 Network service: HTTP requests and server-sent event streams as owned
      asynchronous requests on every host (browser `fetch`/`EventSource`,
      native sockets), plus locale and URL query as platform information, so
      applications need no JavaScript of their own. Evidence: `test_http`
      (framing in pieces of every size), `test_net` (runtime semantics with a
      controlled transport; sockets against a forked server: Content-Length,
      chunked POST, error status, event stream, refused connection, HTTPS
      refused, wake-ups from the helper thread) and `web_browser_test.mjs`
      (Chromium: event stream, POST, page parameter, language). Open: name
      lookup waits; native TLS; the browser test stops earlier at the automatic
      dark theme check, which fails on main as well (B5).
- [x] B2 Focus and keys: `ui_focus` and `ui_reveal` reach a control from
      anywhere in the frame (its own id or the end of its scoped id, if
      unique); in the browser, characters typed right after a shortcut that
      moves the focus into a field are typed there. Layout: rows align to the
      top on every host (centred only with `height`), `row_begin(wrap=.true.)`
      continues on further lines, `ui_width_class()` gives the window width
      class (compact, medium, expanded, large), tab bars keep their labels
      whole and scroll in the browser. Evidence: `test_layout_focus`
      (headless), `test_html`, `web_browser_test.mjs` (type-ahead, row
      alignment). Scroll containers moved to B4 together with virtual lists.
- [x] B3 Pointer input: canvas events carry the pointer kind (mouse, pen,
      touch), pressure, tilt and every coalesced sample since the last frame
      (for ink); two fingers form a gesture with pinch factor and pan that
      never presses or clicks. Evidence: `test_pointer` (headless) and
      `web_browser_test.mjs` (Chromium: pen pressure, two-finger pinch). Open:
      pen and touch on the Linux desktop need XInput2 in fortwin; the desktop
      reports the mouse only.
- [x] B4 Widgets (`fortui_controls`, `fortui_icons`): symbols drawn from
      strokes (SVG in the browser, thick lines on painted hosts, a character
      in terminals) on icons, buttons and chips; chips and badges; segmented
      choices; drop-down lists (the platform picker in browsers, a popup
      list elsewhere); menus; notifications; modal dialogs; scroll
      containers that clip, take the wheel and can keep their end in view;
      virtual lists that compose only the rows in view; a data grid with
      sorting (numbers as numbers), filtering and selection. Nodes carry a
      clip and a layer: popups and notifications float, a modal dialog takes
      the pointer alone, clipped nodes take no clicks. Evidence:
      `test_controls` (headless), `web_browser_test.mjs` (Chromium: every
      control above), offscreen renders of the desktop backend in classic,
      fluent and fluent-dark.
- [x] B5 Themes in the library: light and dark following the system on every
      host; applications ship no styling of their own. The browser switches
      at once on the system's change event and keeps composing in hidden
      pages; Fluent in the browser has the semantic tones (positive, negative,
      muted, accent, diff and code colours, attention) for light and dark and
      colours the whole page. Evidence: Chromium run of the demo switching
      from light to dark without delay. Open: `web_browser_test.mjs` still
      fails its automatic dark theme step after the file picker steps, while
      the same sequence passes when driven through Playwright; the click
      there does not activate the button.
- [x] B6 Filled 3D surfaces with depth (`canvas_mesh`, `fortui_mesh`):
      triangles with vertex colours seen through a camera (`camera_orbit`,
      `camera_project` for picking), smooth shading from vertex normals or
      flat by face, builders for grid surfaces and tubes. Browsers draw them
      with WebGL2 and place the result among the canvas's 2D layers; the
      desktop backend rasterizes them in Fortran with a depth buffer into a
      texture, again only when geometry, camera or size changed. Evidence:
      `test_mesh` (projection, depth independent of order, shading, builders,
      a camera move copies no geometry), `test_gui` (offscreen pixels: the
      nearer face in front), `web_browser_test.mjs` (Chromium WebGL2 pixels).
      Open: terminals draw no meshes; lines are not depth-tested against
      meshes (draw 3D lines as tubes).
- [ ] B7 Commands with undo and redo (M1), presence of other users, deep links
      and local storage.

## Consumer slice: canvas resources, text, idle (branch `canvas-resources`)

Driven by the brainview graph viewer (~8k nodes/38k edges, 10x headroom). Evidence:
`test/test_canvas_text.f90` (headless) and `example/canvas_bench.f90` (raylib,
Linux/X11, RTX 5060 Ti). Windows/macOS routes are unverified.

- [x] Backend interface `ui_backend_t`; registry is the only module naming
      several backends.
- [x] Retained canvas layers (points, indexed lines) keyed by canvas/key with
      generations; upload only on generation change; backend-neutral counters.
- [x] Canvas view transform per frame (no re-upload); bounded canvas labels.
- [x] Canvas pointer semantics: hover, press, click, double click, drag with
      capture (released on button-up or widget removal), wheel; world coordinates.
- [x] UTF-8 text measurement via backend metrics; bundled DejaVu Sans subset.
- [x] Scrollable wrapped text (wheel, scrollbar drag, keys, light Markdown headings).
- [x] Single-line UTF-8 text input (caret, Backspace/Delete/Home/End, Enter).
- [x] Idle waiting with one-shot/continuous frame requests; split layout, resize.
- [ ] IME/preedit, selection, clipboard; wide-character TUI widths.
- [ ] Partial-range canvas uploads; canvas semantic object projection.

API cleanup after review R1 (brainview `handoff/R1-fortui-review.md`). Evidence:
`test_fortui`, `test_canvas_text` and `test_backend_conformance` (headless with the
CI flags; conformance also against raylib in a real X11 window via `make test-gui`),
LFortran 0.67.0-460 native build of all sources running `test_fortui` and
`test_canvas_text`, brainview headless tests and its real-display script.

- [x] Backend injection: `ui_init(backend_value, ...)`; the core, widgets and
      facade use no concrete backend; optional `fortui_backends` registry adds
      `ui_init(name, ...)`. Raylib module and bundled fonts compile only with
      `-DENABLE_GUI=1`; `make install` installs the DejaVu licence; CI checks the
      embedded font source against the font files.
- [x] One idle rule: `present` never blocks, `poll(input, wait)` waits only when
      the previous present allowed it; `ui_frame_begin` has no timeout.
- [x] Store read-only for backends; realized versions, upload counters and GPU
      resources live in backend components (`canvas_realizer_t`, `stats`).
- [x] Shared vertex layers (`canvas_vertices` + `canvas_points`/`canvas_lines`
      overloads; self-contained forms kept); segments revalidated when the vertex
      count shrinks; empty arrays; duplicate layer keys reported; kind change and
      slot growth covered.
- [x] Backend-neutral `KEY_*`; pure `tui_map_key`; terminal size and resize in
      logical units; termbox2 `int` results bound as functions and checked (#150).
- [x] Identity: static text without id, container scopes, `key=` in loops,
      duplicate ids reported and skipped; container balance checked at present.
- [x] Authoring: `style=`/`size=`, `UI_FILL`, `ellipsis=`, three-pane
      `split_begin(id, first=, last=, gap=)`, `tabs`, integer/real `slider`,
      `ui_str`; Escape is an ordinary key (`ui_set_escape_quits` removed);
      `view`/`viewport` removed.
- [x] Follow-up frame only after consumed input (activation, toggle, changed
      value, canvas click, handled shortcut); previous frame swapped, not copied.
- [x] `fortui_testing` holds injection, statistics and frame queries.
- [x] Semantic host events (activate, focus, blur, value, submit) from hosts
      whose controls handle input themselves, applied before pointer routing;
      `ui_run(frame)` with host-driven frames (`ui_run_step`); containers
      recorded in the frame as boxes (kind, gap, row height, pane width,
      position) for hosts that lay out themselves (#149, review F1).
- [ ] Realized-geometry feedback from hosts that lay out controls (needed for
      canvases inside host-laid-out pages beyond their own coordinates).
- [ ] `measure(text, size, style)` backend binding replacing the global metric
      table (#149, review F3).
- [ ] Text field draft session or documented commit-per-edit policy in
      SEMANTIC_MODEL (review F5; `text_input` currently commits every edit).
- [x] Variable-length node text (labels, code lines, paragraphs are never cut).
- [ ] Variable-length node ids and layer keys instead of 96/128 character
      fields (#149, review F7).
- [ ] Context-owned layout stack and text metrics instead of module state;
      `ui_shutdown` resetting all of it (#149, review F8).

## Consumer slice T1: terminal canvas over ssh (branch `tui-canvas`, #151)

Driven by brainview over `ssh localhost`. Evidence: `test/test_tui_canvas.f90`
(headless: braille cells and colours of known layers, clipping, disc edges and
rings, band invariance, colour conversion, kitty chunks decoded by an
independent base64/inflate, terminal reply parsing, mouse cell/pixel mapping),
`example/tui_canvas_bench.f90` (raster cost, thread-count-invariant checksums),
LFortran 0.67.0-460 native build of all sources running the three headless
tests, and brainview screenshots in kitty 0.49.2, WezTerm 20260716, xterm 411,
Alacritty 0.17 and tmux 3.8 (Linux/X11), locally and through ssh.

- [x] Canvas layers in the TUI: shared vertex layers, points (sizes, rgba,
      `min_pixels`), indexed lines (interpolated rgba), labels as text cells,
      fill and view transform; raster only when geometry, view or a layer
      version changed; buffers reused; OpenMP bands with identical results.
- [x] Braille realization (2x4 dots, per-cell colour of highest contrast,
      large discs as rings), truecolor or 256 colours; explicit screen
      background; character-cell text metrics.
- [x] Kitty graphics: in-band detection, zlib/base64 chunks, image replaced by
      id, deleted at shutdown; explicit `FORTUI_TUI_GRAPHICS`/`FORTUI_TUI_COLOR`;
      explicit choices that cannot be honoured fail init (sixel, kitty in tmux).
- [x] Truecolor detection by DECRQSS/XTGETTCAP replies, 256-colour fallback
      reported through `ui_backend_description()`.
- [x] Mouse: press/release/click/double click, drag with capture, wheel, hover
      (any-motion tracking); SGR-pixel positions (mode 1016) when supported,
      cell centres otherwise; `pointer_slop` for hit-test tolerance.
- [x] Idle: nothing written to the terminal without input (strace, 6 s).
- [ ] Sixel (explicitly unsupported); kitty through tmux (unicode placeholders).
- [ ] Semantic fallback: canvas object list when the canvas is too small or the
      application supplies object metadata (needs canvas semantic projection).
- [ ] Keyboard pan/zoom/pick semantics for canvases (no canvas key semantics yet).
- [ ] Wide-character label widths; partial kitty updates; macOS/Windows terminals.

## P0: completed architectural reset

- [x] Ordinary Fortran is the primary embedded DSL.
- [x] Immediate composition produces a backend-neutral semantic frame.
- [x] Previous frame retained for identity/input routing.
- [x] Backend rendering removed from widgets.
- [x] Unused retained `node` API removed.
- [x] Explicit headless backend and semantic behavioral tests.
- [x] Graphical layout expressed in logical units rather than terminal cells.
- [x] Raylib/termbox2 remain replaceable backend details.
- [x] Project rules and CI aligned with the semantic architecture.

These completed items do not imply the broader target contracts below are complete.

## M1: transaction and command correctness

- [ ] Owned normalized events, activation tokens, transaction/revision IDs.
- [ ] One composition per scheduled transaction; nonreentrant serialized execution.
- [ ] Preserve two discrete actions; consume one activation at most once.
- [x] Inline mutation schedules one activation-free follow-up; explicit invalidation.
      Evidence: widgets that consume input schedule one follow-up frame,
      `ui_request_frame` remains explicit (`test_fortui`, `test_canvas_text`).
- [ ] Optional command metadata and one dispatcher/handler owner, with live guards.
- [ ] Unified button/menu/shortcut intent without duplicate command execution.
- [x] Scoped keys and duplicate diagnostics (`test_fortui`).
- [ ] Generation-based stale-event rejection.
- [ ] Failure/publication/shutdown behavior from the transaction contract.

Acceptance: independent action/composition counters, stale-action rejection,
post-save status refresh, failure without repeated side effects, and an idle/wake
probe. Extend [existing tests](test/test_fortui.f90); do not test patch text.

## M2: first TPX shell and independent document fixture

- [ ] Establish external TPX/FortUI consumer scope and shared conformance version.
- [ ] Shell with actions, canvas placeholder, inspector, and lifecycle.
- [ ] Independent Fortran load/hierarchy/save/reload fixture in the application.
- [ ] Structural canvas/object metadata for headless and useful TUI inspection.
- [ ] Owned asynchronous file request/result with cancellation and generations.
- [ ] Narrow first native/hybrid or DOM host probe, alongside bootstrap adapters.

Application document/geometry/export code belongs to TPX/FortUI, not FortUI.
The Pascal and Avalonia tracks remain independent. Start target toolchain probes
now; publish unsupported cells without blocking all document work.

## M3: canvas interaction and layout

- [ ] Render lines/text/Bezier in the consumer; explicit document/view transforms.
- [x] Pointer capture, keyboard focus, hover, drag cancellation, zoom/pan.
- [ ] Independent pick/selection/snap/transform scenarios in the consumer oracle.
- [ ] Intrinsic/min/max sizing, grow/shrink, alignment, spacing, padding.
- [ ] Split/overlay/scroll and adaptive inspector only as the slice needs them.
- [ ] Host realized bounds and scale feed input/accessibility geometry.
- [ ] Measured canvas resource caching and selective paint invalidation.

Acceptance: known geometry results, capture released on removal/cancellation,
high-DPI transformed hit tests, and GUI/TUI access to the same document operations.
Multipass layout must not reexecute application composition.

## M4: property editing, history, text, accessibility

- [ ] Owned variable-length UTF-8 fields and semantic roles/relationships.
- [ ] Draft editor, selection/caret, valid commit/cancel, external-revision conflict.
- [ ] Native-integrated IME/preedit/commit and clipboard in the selected host.
- [ ] Document undo/redo command routing distinct from focused text-edit history.
- [ ] Semantic accessibility names/states/actions/focus order; first actual bridge.
- [ ] Theme tokens and user font/scale/preferences independent of semantics.
- [ ] TPX label edit/preview and asynchronous revision-safe completion.

Acceptance: partial numeric drafts, Unicode/IME persistence, stale completion,
actual host focus/text/accessibility, and independent document-history scenarios.
Do not defer semantic accessibility until after all controls are implemented.

## M5: export, incremental runtime, and scale

- [ ] Consumer TikZ/SVG exports checked against independent common expectations.
- [ ] Real LaTeX compilation with pinned fixture/package/font environment.
- [ ] Dependency invalidation for shaping/layout/paint/accessibility/host resources.
- [ ] Idle wait/deadline behavior; runtime-only caret/animation updates.
- [ ] Virtual collections request bounded ranges and retain active item identity.
- [ ] Benchmarks for allocations, memory, idle work, frame/input latency.

Acceptance: semantic export equivalence, no repeated unrelated shaping/layout,
bounded work for a large collection, and no unsupported performance claims.

## M6: native and DOM realization breadth

- [ ] First desktop adapter supports ordinary native/hybrid controls and custom canvas.
- [x] Second independently implemented host validates shared abstractions: the
      SDL3 GPU backend (`fortui_gui_sdl`) and raylib draw the same theme painter
      display list (`fortui_paint`). Evidence 2026-11-14 (Linux/X11, Vulkan, RTX
      5060 Ti): `test_sdl_gpu` reads back an offscreen frame with the Windows 95
      button bevel pixels, drawn glyphs, an antialiased Fluent corner and a
      quick click; A/B against Windows 95 screenshots matches bevel colours.
- [x] Themes (`fortui_theme`): fluent/fluent-dark (Fluent 2, the default;
      Selawik or Segoe UI, Cascadia Mono) and classic (Windows 95 via Chicago95
      fonts), both first class; Material was removed; user choice through
      FORTUI_THEME or ~/.config/fortui/config; installed fonts via fontconfig,
      none shipped; opt-in themes in the browser through data-theme.
- [ ] Group boxes, drop-down choices, scrolling containers and file dialogs
      (SDL dialogs) in both themes; tabs sized to their labels in classic.
- [x] Desktop backend in Fortran (Chris, 2026-11-15: no SDL, no other
      dependencies): `fortui_gui` on fortwin (X11 through libxcb opened at run
      time), fortgfx (Vulkan 1.3, CPU renderer for offscreen frames without a
      GPU) and fortfont (fonts found without fontconfig, SDL_ttf's HarfBuzz layout
      reproduced); the SDL3 and raylib backends are removed. Evidence 2026-11-15
      (Linux/X11, RTX 5060 Ti): `test_gui` (the former SDL pixel checks) passes;
      the theme gallery renders pixel-identical to the SDL backend in classic and
      differs only in glyph antialiasing in fluent (0.2 % of pixels; fortfont
      renders unhinted where FreeType hinted lightly).
- [ ] Wayland, Windows (Win32, Vulkan) and macOS (Cocoa, Metal) in fortwin and fortgfx.
- [ ] Light hinting in fortfont, so Fluent text matches FreeType's antialiasing.
- [ ] Fluent density (compact for dense scientific views) and Fluent system icons
      (MIT) with an icon widget.
- [x] Terminal look (`tui_theme = auto|light|dark`, auto from the terminal's
      background): push buttons, entry fields, `[X]` check boxes, tabs on a
      band, scroll bars and the function key line from labelled shortcuts.
- [ ] Terminal palettes after real text-mode programs (3270/ISPF, Turbo
      Vision), checked against screenshots.
- [ ] Action bar with pull-down menus and pop-up windows with shadows (needs a
      menu widget on every host).
- [x] Terminal emulator (`-DENABLE_TERM=1`): Fortran engine (fortui_vt, ring of
      lines, reader thread with ring buffer), pseudo-terminal,
      kitty graphics and sixel decoded in Fortran (inflate, PNG, sixel), images
      anchored to cells through scrolling and erasing, scrollback, selection and
      clipboard, mouse reports; `terminal` widget and `canvas_cells`; function
      keys; sixel output of the terminal host for tmux.
- [ ] Terminal: kitty Unicode placeholders (images through tmux without
      sixel), bold and italic faces, the cell grid in the browser (the web host
      ignores cell layers today), images and braille for cell layers on the
      terminal host, a waker for the terminal host (it polls at 60 Hz).
- [ ] Platform-specific menus, services, text, and accessibility evidence per host.
- [x] Printing service over IPP in Fortran (`fortui_print`, `fortui_ipp`; no
      libcups since 2026-11-15): printers,
      media with margins/borderless variants, media types, trays, qualities,
      raster resolution, live loaded paper and ink levels over IPP; pages as
      PWG raster encoded in Fortran (`fortui_pwg`). Evidence 2026-11-14: libcups
      2.4.20 decodes the encoder's pages unchanged; a held borderless job to a
      Canon TS8700 IPP Everywhere queue was accepted as image/pwg-raster and
      cancelled (`test_print` with `FORTUI_PRINT_TEST_PRINTER`). Since the IPP
      rewrite, `test_print` compares the sheets of a virtual printer
      (ippeveprinter) with libcups's list for it and checks the received jobs
      byte for byte; on the TS8700 queue every printer, sheet, label, margin,
      tray and media type equals what the libcups version reported.
- [ ] Printing requests as asynchronous owned service requests (now blocking).
- [x] Retained canvas images (`canvas_image`): GPU texture, terminal raster.
- [ ] Browser semantic DOM controls plus custom canvas; explicit URL/history behavior.
- [ ] Actual Fortran/WASM feature probes and runtime, including strings/callbacks.
      Evidence 2026-10-13: LFortran main `0cd29dede1` (LLVM backend, target
      `wasm32-unknown-emscripten`) compiles all `src/` modules unchanged and
      `test_fortui` passes in Node and Chromium. `test_canvas_text` needs
      `--realloc-lhs-arrays` (off by default in LFortran) and then passes natively.
      Flang 23.1 cannot target wasm (`Target.cpp: target not implemented`, no
      wasm32 intrinsic modules or runtime). Callbacks are not yet probed.
- [x] Browser `web` backend implementing `ui_backend_t` (`web/`): containers
      as flex boxes and controls as native elements laid out by the browser;
      native fields and sliders edit themselves and report values; frames
      driven by the browser through `ui_run` (no Asyncify, no text measuring);
      `web/fortui.css` as the page's base styles; stable `data-key`s so a
      server-rendered page is adopted. Checked in headless Chromium
      (`test/web_browser_test.mjs`). Evidence 2026-11-09: LFortran
      0.68.0-222-gf25f8f8542, emscripten 6.0.13, Chromium 156; LFortran keeps
      main-program variables on the stack, so frame state belongs in modules.
- [x] `fortui_html`: a composed frame as the HTML the browser host builds
      (same elements, classes, styles and keys), for pages a server renders
      with the headless backend before the WebAssembly starts.
- [x] `look=` and `anchor=` on `text`, `link`, `button`, `row_begin` and
      `column_begin`: the attribute `data-look` for page styles and the HTML
      `id`, so an address with a fragment scrolls the server's page before any
      script runs, both from `fortui_html` and the browser host; the terminal,
      raylib and headless hosts ignore them. Tone `UI_TONE_ATTENTION` (a
      person's turn) with its amber in `web/fortui.css`, the only colour the
      base styles bring, chosen by the `color-scheme` the page declares. Names
      lose control characters and are cut at whole characters; a second
      element with an anchor already given in the frame is reported and gets
      none. Checked in `test_html` and in headless Chromium.
- [x] Keyboard shortcuts and focus requests: `ui_shortcut(chord)` per frame
      ("j", "g o", "mod+k", "Enter"), `ui_focus(id)`, `ui_reveal(id)`. Key
      presses are sorted once in `fortui_input` against the chords of the last
      frame and against what the focused control uses itself; the browser host
      has every key sorted there at the moment it is pressed and the frames
      see that result, so it prevents the browser's action only for registered
      chords and never takes a key from a field, a select or an input method.
      A chord pressed again before a frame waits for the next frame. With a
      modifier, a key whose layout gives no ASCII character is the letter on
      the key (`KeyboardEvent.code`). Evidence: `test/test_keys_focus.f90` (headless) and
      `test/web_browser_test.mjs` (Chromium 156, real key events). The
      terminal presses unmodified keys and Ctrl with a letter, raylib
      unmodified keys; `fortui_html` marks the focused control `autofocus`
      and ignores reveal. Not yet run: Cmd on macOS, a real input method,
      shortcuts in a real terminal.
- [ ] Web backend: canvas layers (WebGPU through emscripten `webgpu.h`, or 2-D
      canvas first), DOM-realized geometry fed back to the runtime, IME through
      composition events, URL/history integration, and a CI job.
- [x] Correct termbox2 C binding signatures (C `int` results bound as
      subroutines); harmless on x86-64, a trap on wasm. Fixed for #150: all
      results are `integer(c_int)` functions and checked; `tb_attr_width` must
      report the 16-bit `uintattr_t` matching the Fortran binding.
- [x] termbox2 replaced by FortUI's own terminal layer (`fortui_tb`, 2026-11-15):
      raw mode and resize signal in `src/c/fortui_tty.c`, the cell grid sent
      as differences, keys and SGR/X10 mouse decoded in Fortran. `test_tb`
      checks output and input against FortUI's terminal emulator (`fortui_vt`);
      the scripted `tui_demo` session in tmux gives the same screens as the
      termbox2 build.
- [ ] Trusted browser service activation, permission/file/storage behavior.
- [ ] No explicit-backend silent fallback.
- [ ] Native hybrid hosts (GTK4, AppKit, Win32) with an embedded custom canvas.

Desktop routes include Windows, macOS, and selected Linux hosts. Renderer choice
follows measured consumer needs; do not require every GPU API before proving a slice.

## M7: mobile and full experiment target matrix

- [ ] Native ARM64/compiler/ABI/linker probes for actual application features.
- [ ] UIKit and Android lifecycle, suspend/resume/resource-loss handling.
- [ ] Adaptive inspector, touch, stylus/Pencil where available, system files/share.
- [ ] IME, accessibility, keyboard/modality transitions, back/navigation semantics.
- [ ] Execute common/platform conformance suites on real target builds/devices.
- [ ] Record per-track/per-target capabilities, failures, effort, and measurements.

Probe difficult compiler/lifecycle paths early in M2 rather than discovering all
feasibility gaps here. Only executed evidence promotes a target to supported.

## M8: optional tooling and frontends

- [ ] Semantic inspector edits emit ordinary Fortran with source provenance.
- [ ] External declarative frontend only after a measured application need.
- [ ] Lower optional frontends into one semantic IR/runtime.
- [ ] FortGen reuse only for proven generic emission/serialization infrastructure.

This milestone must not delay application correctness or essential platform quality.

## Verification and promotion

Existing [CI](.github/workflows/ci.yml) and fpm registered tests remain authoritative
for the current semantic core. Code changes preserve strict warnings and backend
import boundaries. Use the Fortran skill and pinned resident `fo gremlin` workflow
when developing Fortran; keep fpm/CMake registered checks authoritative.

Each implementation records exact commits/toolchains, its independent behavioral
oracle, focused test results, and any required host evidence. Review uncommitted
work against an exact base and patch digest. One controller owns integration and
promotion. Preserve unrelated work and stage explicit paths.

Documentation changes receive prose, link, and diff checks; they do not need
implementation-mirroring tests. Headless success does not establish IME/native/DOM
correctness. Do not weaken checks, hide failures, claim unexecuted platform support,
or present planned work as complete. Repair reproducible tool/dependency defects
at their owning repository under the applicable development rules.
