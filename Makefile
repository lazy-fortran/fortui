FPM ?= fpm
SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
TERM_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_TERM=1" \
	FPM_CFLAGS="$${FPM_CFLAGS:-} -DENABLE_TERM=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lutil -lpthread"

.PHONY: all build test build-term test-term install clean help

all: build

build:
	$(FPM) build

test:
	FORTUI_HEADLESS=1 $(FPM) test

build-term:
	$(TERM_ENV) $(FPM) build

# Headless tests plus the terminal emulator against real programs on a
# pseudo-terminal (libvterm).
test-term:
	FORTUI_HEADLESS=1 $(TERM_ENV) $(FPM) test

install:
	$(FPM) install --prefix "$(PREFIX)"

clean:
	$(FPM) clean --skip

help:
	@echo "build       the library: headless, terminal and graphical backends"
	@echo "test        semantic tests and the graphical backend offscreen (Vulkan or CPU)"
	@echo "install     library and modules under PREFIX"
