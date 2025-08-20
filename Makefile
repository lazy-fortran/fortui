# Makefile for fortui project
# Integrates dependency management with FPM build system

# Configuration
BUILD_SCRIPT := tools/build_fortui.sh
FPM := fpm
SHELL := /bin/bash

# Default target
.PHONY: all
all: build

# Build dependencies and then the project
.PHONY: build
build: deps
	@echo "Building fortui with FPM..."
	@CPP_FLAGS=$$($(BUILD_SCRIPT) flags) && \
	if [[ "$$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI"; \
	else \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY"; \
	fi && \
	export FPM_LDFLAGS="$${FPM_LDFLAGS:-} $$($(BUILD_SCRIPT) ldflags)" && \
	echo "FPM flags: $$FPM_FFLAGS" && \
	echo "FPM ldflags: $$FPM_LDFLAGS" && \
	$(FPM) build

# Build dependencies only
.PHONY: deps
deps:
	@echo "Building dependencies..."
	@$(BUILD_SCRIPT) build

# Run tests
.PHONY: test
test: deps
	@echo "Running tests with FPM..."
	@CPP_FLAGS=$$($(BUILD_SCRIPT) flags) && \
	if [[ "$$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI"; \
	else \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY"; \
	fi && \
	export FPM_LDFLAGS="$${FPM_LDFLAGS:-} $$($(BUILD_SCRIPT) ldflags)" && \
	$(FPM) test

# Run specific example
.PHONY: run
run: deps
	@echo "Running fortui with FPM..."
	@CPP_FLAGS=$$($(BUILD_SCRIPT) flags) && \
	if [[ "$$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_GUI"; \
	else \
		export FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DTUI_ONLY"; \
	fi && \
	export FPM_LDFLAGS="$${FPM_LDFLAGS:-} $$($(BUILD_SCRIPT) ldflags)" && \
	$(FPM) run

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@$(FPM) clean
	@rm -rf build/

# Clean everything including dependencies
.PHONY: distclean
distclean: clean
	@echo "Cleaning dependencies..."
	@$(BUILD_SCRIPT) clean

# Show configuration
.PHONY: config
config:
	@$(BUILD_SCRIPT) config

# Show help
.PHONY: help
help:
	@echo "Fortui build system"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build the project (default)"
	@echo "  build     - Build dependencies and project"
	@echo "  deps      - Build dependencies only"
	@echo "  test      - Run tests"
	@echo "  run       - Run the application"
	@echo "  clean     - Clean build artifacts"
	@echo "  distclean - Clean everything including dependencies"
	@echo "  config    - Show build configuration"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  DISABLE_GUI=1  - Build TUI-only version"
	@echo "  DEBUG=1        - Enable debug output"
	@echo "  RAYLIB_ROOT    - Path to custom raylib installation"
	@echo ""
	@echo "Examples:"
	@echo "  make              # Build with auto-detected backends"
	@echo "  DISABLE_GUI=1 make  # Build TUI-only version"
	@echo "  DEBUG=1 make      # Build with debug output"