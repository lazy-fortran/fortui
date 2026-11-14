FPM ?= fpm
SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
GUI_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI=1" \
	FPM_CFLAGS="$${FPM_CFLAGS:-} -DENABLE_GUI=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lraylib -lfontconfig"
SDL_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_SDL=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lSDL3 -lSDL3_ttf -lfontconfig"
PRINT_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_PRINT=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lcups"

.PHONY: all build test build-gui test-gui build-sdl test-sdl build-print test-print test-print-system install clean help

all: build

build:
	$(FPM) build

test:
	FORTUI_HEADLESS=1 $(FPM) test

build-gui:
	$(GUI_ENV) $(FPM) build

# Headless tests plus the backend conformance scenario in a real raylib window
# when a display is reachable (FORTUI_HEADLESS=1 skips the window).
test-gui:
	$(GUI_ENV) $(FPM) test

build-sdl:
	$(SDL_ENV) $(FPM) build

# Headless tests plus the SDL GPU scenarios (window and offscreen pixels) when a
# GPU and display are reachable.
test-sdl:
	$(SDL_ENV) $(FPM) test

build-print:
	$(PRINT_ENV) $(FPM) build

# Print tests against libcups; FORTUI_PRINT_TEST_PRINTER=QUEUE also submits a
# held job to that queue and cancels it.
test-print:
	FORTUI_HEADLESS=1 $(PRINT_ENV) $(FPM) test

# Through a real CUPS queue to a virtual printer (ippeveprinter; needs sudo for
# lpadmin): checks the tray, media type, quality and borderless margins it gets.
test-print-system:
	test/system/print-virtual.sh

install:
	$(FPM) install --prefix "$(PREFIX)"

clean:
	$(FPM) clean --skip

help:
	@echo "build       headless + termbox2/TUI capable library"
	@echo "test        deterministic headless semantic tests"
	@echo "build-gui   additionally compile the raylib backend and bundled fonts"
	@echo "test-gui    GUI build; conformance scenario also on raylib with a display"
	@echo "build-sdl   additionally compile the SDL3 GPU backend (SDL3, SDL3_ttf, fontconfig)"
	@echo "test-sdl    SDL GPU build; window and offscreen pixel checks with a GPU"
	@echo "build-print additionally compile the CUPS printing service (-lcups)"
	@echo "test-print  headless tests with printing; libcups decodes the pages"
	@echo "test-print-system  print through CUPS to a virtual printer (sudo)"
	@echo "install     library and modules under PREFIX"
