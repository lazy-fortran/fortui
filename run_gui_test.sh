#!/bin/bash
# Compile and run GUI backend test

set -e

echo "Building fortui library..."
./tools/build_fortui.sh build

# Get build flags
CPP_FLAGS=$(./tools/build_fortui.sh flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    FPM_FFLAGS="-cpp -DENABLE_GUI"
else
    FPM_FFLAGS="-cpp -DTUI_ONLY"
fi

# Get linker flags
LDFLAGS=$(./tools/build_fortui.sh ldflags)

echo "Compiling test_gui_backend..."
gfortran $FPM_FFLAGS -I build/gfortran_*/fortui \
    test/test_gui_backend.f90 \
    build/gfortran_*/fortui/libfortui.a \
    $LDFLAGS \
    -o test_gui_backend_exe

echo "Running test_gui_backend..."
./test_gui_backend_exe