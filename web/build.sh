#!/bin/sh
# Builds the fortui library and a program for the browser with LFortran
# (target wasm32-unknown-emscripten) and links it with emcc and the web host.
#   web/build.sh [PROGRAM.f90] [OUTDIR]
# Defaults: the demo (example/web_demo_app.f90, web/example/web_demo.f90) into
# build/web. Needs lfortran and an
# emscripten SDK in EMSDK_PATH (the one LFortran itself uses).
# FORTUI_WEB_SOURCES: further Fortran sources of the application, in dependency
# order, compiled before PROGRAM. FORTUI_WEB_JS: further emscripten JavaScript
# libraries. FORTUI_WEB_LDFLAGS: further emcc link flags (e.g. --profiling-funcs).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
caller=$(pwd)
if [ -z "${1:-}" ] && [ -z "${FORTUI_WEB_SOURCES:-}" ]; then
    FORTUI_WEB_SOURCES=$top/example/web_demo_app.f90
fi
prog=${1:-$here/example/web_demo.f90}
prog=$(cd "$(dirname "$prog")" && pwd)/$(basename "$prog")
out=${2:-$top/build/web}
emcc=${EMCC:-${EMSDK_PATH:?set EMSDK_PATH to the emscripten SDK}/upstream/emscripten/emcc}
lf=${LFORTRAN:-lfortran}
runtime=$(dirname "$(command -v "$lf")")/../lib/lfortran_runtime_wasm_emcc.o
flags="--target=wasm32-unknown-emscripten --realloc-lhs-arrays"

rm -rf "$out/obj"
mkdir -p "$out/obj"
cd "$out/obj"
# Dependency order; the terminal and raylib backends and the backend registry
# are native only.
for m in fortui_error fortui_text fortui_layout fortui_frame fortui_canvas \
    fortui_raster fortui_input fortui_backend fortui_backend_headless \
    fortui_context fortui_core fortui_widgets fortui_testing fortui; do
    "$lf" -c $flags "$top/src/$m.f90" -o "$m.o"
done
"$lf" -c $flags "$here/fortui_web.f90" -o fortui_web.o
for src in ${FORTUI_WEB_SOURCES:-}; do
    case $src in /*) ;; *) src=$caller/$src ;; esac
    "$lf" -c $flags "$src" -o "$(basename "$src" .f90).o"
done
js="--js-library $here/fortui_web.js"
for lib in ${FORTUI_WEB_JS:-}; do
    case $lib in /*) ;; *) lib=$caller/$lib ;; esac
    js="$js --js-library $lib"
done
name=$(basename "$prog" .f90)
"$lf" -c $flags "$prog" -o "$name.o"
"$emcc" --target=wasm32-unknown-emscripten -O2 -sALLOW_MEMORY_GROWTH \
    -sSTACK_SIZE=8mb -sEXPORTED_FUNCTIONS=_main,_fortui_web_step,_fortui_web_key $js ${FORTUI_WEB_LDFLAGS:-} \
    -o "$out/$name.js" ./*.o "$runtime"
html=$(dirname "$prog")/index.html
if [ -f "$html" ]; then cp "$html" "$out/index.html"; fi
cp "$here/fortui.css" "$out/fortui.css"
echo "$out/$name.js"
