# Makefile for fortui project
# Pure FPM-based build with embedded termbox2 backend

FPM := fpm
SHELL := /bin/bash

# Default target
.PHONY: all
all: build

# Build project
.PHONY: build
build:
	@echo "Building fortui with FPM..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY -DENABLE_TUI=1" && \
	echo "FPM flags: $$FPM_FFLAGS" && \
	$(FPM) build

# Run tests
.PHONY: test
test:
	@echo "Running tests with FPM..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY -DENABLE_TUI=1" && \
	$(FPM) test

# Run specific example
.PHONY: run
run:
	@echo "Running fortui with FPM..."
	@export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY -DENABLE_TUI=1" && \
	$(FPM) run

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
	@echo "  all       - Build the project (default)"
	@echo "  build     - Build project"
	@echo "  test      - Run tests"
	@echo "  run       - Run the application"
	@echo "  clean     - Clean build artifacts"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Note: This project uses embedded termbox2 backend (TUI-only)."
	@echo "All dependencies are self-contained within the FPM build."