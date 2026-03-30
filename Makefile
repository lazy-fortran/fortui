# Makefile for fortui project
# Pure FPM-based build with embedded termbox2 backend

FPM := fpm
SHELL := /bin/bash

# TUI-only build flags (default)
TUI_FLAGS := -cpp -DTUI_ONLY -DENABLE_TUI=1

# GUI build flags (requires: sudo pacman -S raylib)
GUI_FLAGS := -cpp -DENABLE_TUI=1 -DENABLE_GUI=1
GUI_LDFLAGS := -lraylib

# Default target
.PHONY: all
all: build

# Build project (TUI-only)
.PHONY: build
build:
	@echo "Building fortui (TUI)..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} $(TUI_FLAGS)" && \
	$(FPM) build

# Build project with GUI backend
.PHONY: build-gui
build-gui:
	@echo "Building fortui (TUI + GUI)..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} $(GUI_FLAGS)" && \
	export FPM_LDFLAGS="$${FPM_LDFLAGS:-} $(GUI_LDFLAGS)" && \
	$(FPM) build

# Run tests (TUI-only)
.PHONY: test
test:
	@echo "Running tests (TUI)..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} $(TUI_FLAGS)" && \
	$(FPM) test

# Run tests with GUI backend compiled
.PHONY: test-gui
test-gui:
	@echo "Running tests (TUI + GUI)..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} $(GUI_FLAGS)" && \
	export FPM_LDFLAGS="$${FPM_LDFLAGS:-} $(GUI_LDFLAGS)" && \
	$(FPM) test

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@$(FPM) clean --skip
	@rm -rf build/

# Show help
.PHONY: help
help:
	@echo "Fortui build system"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build the project (default, TUI-only)"
	@echo "  build      - Build project (TUI-only)"
	@echo "  build-gui  - Build project with GUI backend (requires raylib)"
	@echo "  test       - Run tests (TUI-only)"
	@echo "  test-gui   - Run tests with GUI backend compiled"
	@echo "  clean      - Clean build artifacts"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "GUI backend requires: sudo pacman -S raylib"
