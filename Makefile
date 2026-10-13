FPM ?= fpm
SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
GUI_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI=1" \
	FPM_CFLAGS="$${FPM_CFLAGS:-} -DENABLE_GUI=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lraylib"

.PHONY: all build test build-gui test-gui install clean help

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

install:
	$(FPM) install --prefix "$(PREFIX)"
	install -Dm644 assets/fonts/LICENSE-DejaVu \
		"$(PREFIX)/share/licenses/fortui/LICENSE-DejaVu"

clean:
	$(FPM) clean --skip

help:
	@echo "build       headless + termbox2/TUI capable library"
	@echo "test        deterministic headless semantic tests"
	@echo "build-gui   additionally compile the raylib backend and bundled fonts"
	@echo "test-gui    GUI build; conformance scenario also on raylib with a display"
	@echo "install     library, modules and the DejaVu font licence under PREFIX"
