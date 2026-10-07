# FortUI instructions

The authoritative architecture is in `DESIGN.md`; the staged work is in `PLAN.md`; repository rules are in `AGENTS.md`.

FortUI is not a pure immediate-mode renderer. It exposes an immediate Fortran composition API over a retained semantic runtime. Input routes against the previous semantic frame; widgets emit backend-neutral nodes; backends present frames.

Never put backend tests or drawing calls in widget code. Never reintroduce the old unused `node` tree, unit-class hierarchies, fake context/thread-safety layers, or graphical layout expressed in terminal cells.

The current backends are headless, termbox2 TUI, and optional raylib GUI. Raylib is a bootstrap implementation, not the architecture.

Run `fpm test` for the headless semantic gate. GUI/TUI integration claims require real interactive execution in addition to unit tests.
