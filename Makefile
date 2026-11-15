FPM ?= fpm
SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
TERM_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_TERM=1" \
	FPM_CFLAGS="$${FPM_CFLAGS:-} -DENABLE_TERM=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lutil -lpthread"
PRINT_ENV = FPM_FFLAGS="$${FPM_FFLAGS:-} -cpp -DENABLE_PRINT=1" \
	FPM_LDFLAGS="$${FPM_LDFLAGS:-} -lcups"

.PHONY: all build test build-term test-term build-print test-print test-print-system install clean help

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
	@echo "build       the library: headless, terminal and graphical backends"
	@echo "test        semantic tests and the graphical backend offscreen (Vulkan or CPU)"
	@echo "build-print additionally compile the CUPS printing service (-lcups)"
	@echo "test-print  headless tests with printing; libcups decodes the pages"
	@echo "test-print-system  print through CUPS to a virtual printer (sudo)"
	@echo "install     library and modules under PREFIX"
