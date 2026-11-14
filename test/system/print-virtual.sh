#!/bin/sh
# System test of fortui_print through a real CUPS queue to a virtual IPP
# Everywhere printer (ippeveprinter), which keeps every job and the attributes
# it was asked to print with. Needs CUPS with ippeveprinter and sudo for
# lpadmin; nothing reaches a real printer. Run from the repository root:
#   test/system/print-virtual.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
port=${FORTUI_VIRTUAL_PORT:-8632}
queue=fortui-virtual-photo
spool=$(mktemp -d "${TMPDIR:-/tmp}/fortui-print-XXXXXX")

cleanup() {
    sudo lpadmin -x "$queue" 2>/dev/null || true
    [ -n "${printer:-}" ] && kill "$printer" 2>/dev/null || true
    rm -rf "$spool"
}
trap cleanup EXIT INT TERM

ippeveprinter -k -d "$spool" -p "$port" -c "$here/keep-job.sh" \
    -P "$here/photo-printer.ppd" "$queue" >"$spool/printer.log" 2>&1 &
printer=$!
i=0
until ipptool -q "ipp://localhost:$port/ipp/print" get-printer-attributes.test \
    2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 50 ] && { cat "$spool/printer.log"; exit 1; }
    sleep 0.2
done
sudo lpadmin -p "$queue" -E -v "ipp://localhost:$port/ipp/print" -m everywhere

FORTUI_PRINT_TEST_PRINTER=$queue FORTUI_PRINT_TEST_SPOOL=$spool \
    FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_PRINT=1" \
    FPM_LDFLAGS="${FPM_LDFLAGS:-} -lcups" fpm test test_print
