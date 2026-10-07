FPM ?= fpm
SHELL := /bin/bash

.PHONY: all build test build-gui test-gui clean help

all: build

build:
	$(FPM) build

test:
	FORTUI_HEADLESS=1 $(FPM) test

build-gui:
	FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lraylib" \
	$(FPM) build

test-gui:
	FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lraylib" \
	FORTUI_HEADLESS=1 $(FPM) test

clean:
	$(FPM) clean --skip

help:
	@echo "build       headless + termbox2/TUI capable library"
	@echo "test        deterministic headless semantic tests"
	@echo "build-gui   additionally compile the optional raylib backend"
	@echo "test-gui    compile GUI backend and run headless semantic tests"
