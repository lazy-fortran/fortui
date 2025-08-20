# GUI Backend Guide

Graphical UI backend with raylib/raygui integration, pixel-perfect monospace rendering, and production-ready cross-platform support.

## Quick Setup

```bash
# Install raylib system dependency (required)
sudo apt install libraylib-dev    # Ubuntu/Debian
brew install raylib               # macOS
# Windows: Download from raylib.com

# Build with GUI backend enabled
source fmp_env.sh                 # Detects raylib automatically
fmp build
fmp run --example gui_demo
```

## Basic Usage

```fortran
program gui_app
  use fortui_core
  use fortui_widgets
  implicit none
  
  logical :: running, clicked
  type(view) :: plot_view
  
  ! GUI backend with pixel dimensions
  call ui_init("gui", 800, 600, "My GUI App", target_fps=60, vsync=.true.)
  
  running = .true.
  do while (running)
    call ui_frame_begin(0)  ! timeout ignored in GUI mode
    
    clicked = button("ok", "Click Me", width=120.0, height=40.0)
    if (clicked) print *, "Button clicked!"
    
    call ui_present()
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

## Environment Requirements

### System Dependencies

**raylib library** (required for GUI compilation):
```bash
# Check if raylib available
pkg-config --exists raylib && echo "raylib found" || echo "raylib missing"

# Ubuntu/Debian
sudo apt update && sudo apt install libraylib-dev

# Fedora/RHEL
sudo dnf install raylib-devel

# macOS
brew install raylib

# Arch Linux
sudo pacman -S raylib

# From source (if needed)
git clone https://github.com/raysan5/raylib.git
cd raylib/src && make PLATFORM=PLATFORM_DESKTOP
sudo make install
```

### Build Environment

The GUI backend uses **conditional compilation** - builds only when raylib is detected:

```bash
# Check build configuration
./tools/build_fortui.sh config
```

Example output:
```
Fortui Build Configuration:
  Platform: linux
  Cache: /home/user/.cache/fortui
  GUI Backend: ENABLED          # ← Raylib detected
  TUI Backend: ENABLED (always)
  Raylib: System (pkg-config)
```

## Compilation Methods

### Method 1: Automatic Detection (Recommended)

```bash
# Detects raylib automatically, sets flags, builds dependencies
source fpm_env.sh
fpm build                       # Includes GUI if raylib found
fpm run --example demo
```

### Method 2: Manual Configuration

```bash
# Build dependencies manually
./tools/build_fortui.sh build

# Get flags for manual compilation
CPP_FLAGS=$(./tools/build_fortui.sh flags)
LINK_FLAGS=$(./tools/build_fortui.sh ldflags)

# Compile with explicit flags
export FPM_FFLAGS="-cpp -DENABLE_GUI"  # Enable GUI backend
export FPM_LDFLAGS="$LINK_FLAGS"      # Link raylib
fpm build
```

### Method 3: TUI-Only Build

```bash
# Force TUI-only build (skip GUI even if raylib available)
DISABLE_GUI=1 source fpm_env.sh
fmp build                              # TUI backend only
```

## Backend Selection

### Automatic Selection

```fortran
! Intelligent backend selection
call ui_init("auto", 800, 600, "Auto Backend")
```
**Selection Logic:**
- GUI preferred when raylib available and display detected
- TUI fallback for headless environments (SSH, CI, no DISPLAY)
- User override via `FORTUI_BACKEND=tui` environment variable

### Explicit GUI Mode

```fortran
! Force GUI mode (falls back to TUI if GUI unavailable)
call ui_init("gui", 800, 600, "GUI Application", &
             target_fps=60, vsync=.true.)
```

### Runtime Configuration

```fortran
! Optional power-saving configuration (GUI only)
call ui_set_idle_policy("adaptive", idle_fps=12)
```

**Idle Policies:**
- `"steady"` (default): Constant frame rate, always responsive
- `"adaptive"`: Reduced frame rate when idle, power-efficient

## Environment Detection

The GUI backend automatically detects its environment:

### Display Detection
```fortran
! Checks for graphical display
! X11: DISPLAY environment variable
! Wayland: WAYLAND_DISPLAY environment variable
```

### Headless Detection
```fortran
! Automatically detected:
! - SSH sessions (SSH_CLIENT, SSH_TTY)
! - CI environments (CI, GITHUB_ACTIONS)
! - No display variables
! → Automatic TUI fallback
```

### Override Variables
```bash
# Force TUI mode even with GUI available
export DISABLE_GUI=1

# Force headless mode (testing)
export FORTUI_HEADLESS=1

# Backend selection override
export FORTUI_BACKEND=tui        # or "gui", "auto"
```

## Rendering System

### Monospace Grid Consistency

The GUI backend maintains **exact pixel alignment** with TUI cell grid:

```fortran
! Grid unit conversion
! TUI: 1 cell = 8x16 pixels (typical)
! GUI: 1 cell = font width x line height (measured)

call ui_init("gui", width=80*8, height=25*16, title="Pixel Perfect")
! Renders identically to:
call ui_init("tui", width=80, height=25, title="Cell Grid")
```

### Font and DPI Handling

```fortran
! GUI backend automatically detects:
! - System DPI scaling
! - Default font metrics  
! - Accessibility text scaling
! → Converts to consistent dp (density-independent pixel) units
```

### Performance Configuration

```fortran
program gui_performance
  use fortui_core
  implicit none
  
  ! High refresh rate
  call ui_init("gui", 1920, 1080, "High FPS", target_fps=120, vsync=.false.)
  
  ! Power-efficient
  call ui_init("gui", 800, 600, "Efficient", target_fps=60, vsync=.true.)
  call ui_set_idle_policy("adaptive", idle_fps=12)
end program
```

**Performance Features:**
- **VSync**: Prevents tearing (default enabled)
- **Target FPS**: Configurable frame rate (default 60)
- **Adaptive idle**: Reduces power consumption during inactivity

## Widget Rendering

All widgets render identically between TUI and GUI backends:

```fortran
program widget_demo
  use fortui_core
  use fortui_widgets
  implicit none
  
  logical :: clicked, changed
  real :: volume = 50.0
  logical :: enabled = .true.
  
  call ui_init("auto", 640, 480, "Widget Demo")
  
  do while (.not. ui_should_close())
    call ui_frame_begin(0)
    
    ! Button widget
    clicked = button("save", "Save File", width=100.0, height=30.0)
    
    ! Slider widget  
    changed = slider("vol", 0.0, 100.0, 1.0, volume, width=200.0)
    
    ! Checkbox widget
    call checkbox("enable", enabled, "Enable Feature")
    
    ! Text widget
    call text("status", "Volume: " // real_to_str(volume))
    
    call ui_present()
  end do
  
  call ui_shutdown()
end program
```

## Error Handling and Fallback

### Graceful Degradation

```fortran
! Safe initialization - never fails
call ui_init("gui", 800, 600, "My App")
! If GUI unavailable:
! 1. Prints warning message
! 2. Automatically falls back to TUI
! 3. Application continues normally
```

### Error Detection

```fortran
program error_handling
  use fortui_core
  implicit none
  
  call ui_init("gui", 800, 600, "Error Test")
  
  ! Check which backend actually initialized
  if (ui_get_active_backend() == "gui") then
    print *, "GUI backend active"
  else
    print *, "TUI fallback active"
  end if
  
  call ui_shutdown()
end program
```

## Troubleshooting

### Common Issues

**"GUI backend not available"**
```bash
# Check raylib installation
pkg-config --modversion raylib     # Should show version
sudo apt install libraylib-dev     # If missing

# Verify build configuration
./tools/build_fortui.sh config
```

**GUI starts but window doesn't appear**
```bash
# Check display environment
echo $DISPLAY                      # X11 display
echo $WAYLAND_DISPLAY             # Wayland display

# Test basic raylib
cat > test.c << 'EOF'
#include <raylib.h>
int main() { InitWindow(400,300,"Test"); CloseWindow(); return 0; }
EOF
gcc test.c -lraylib && ./a.out
```

**Build fails with linking errors**
```bash
# Check raylib development headers
ls /usr/include/raylib.h          # Should exist
ls /usr/lib/libraylib.so          # Should exist

# Rebuild dependencies
FORCE_REBUILD=1 ./tools/build_fortui.sh build
source fpm_env.sh
fpm build
```

**Performance issues**
```fortran
! Disable VSync for maximum performance
call ui_init("gui", 800, 600, "Fast", vsync=.false.)

! Or enable adaptive idle for power saving
call ui_set_idle_policy("adaptive", idle_fps=12)
```

### Debug Mode

```bash
# Enable verbose build output
DEBUG=1 ./tools/build_fortui.sh build
DEBUG=1 source fpm_env.sh
```

### Testing GUI Availability

```fortran
program test_gui
  use fortui_gui, only: is_gui_available_impl
  implicit none
  
  if (is_gui_available_impl()) then
    print *, "GUI backend available"
    call ui_init("gui", 400, 300, "Test")
    call ui_shutdown()
  else
    print *, "GUI backend not available, using TUI"
    call ui_init("tui", 80, 25, "Test")
    call ui_shutdown()
  end if
end program
```

## Advanced Configuration

### Multi-Monitor Support

```fortran
! GUI backend automatically handles:
! - Per-monitor DPI scaling
! - Window movement between monitors
! - High-DPI display support
```

### Custom Raylib Installation

```bash
# Use custom raylib installation
export RAYLIB_ROOT=/opt/raylib
source fmp_env.sh
fmp build
```

### Cross-Platform Builds

```bash
# Linux
sudo apt install libraylib-dev
source fmp_env.sh && fmp build

# macOS
brew install raylib
source fmp_env.sh && fmp build

# Windows (MSYS2)
pacman -S mingw-w64-x86_64-raylib
source fmp_env.sh && fmp build
```

## Integration Examples

### Mixed TUI/GUI Application

```fortran
program adaptive_app
  use fortui_core
  implicit none
  
  ! Automatic backend selection
  call ui_init("auto", 800, 600, "Adaptive App")
  
  select case (ui_get_active_backend())
    case ("gui")
      print *, "Running in GUI mode with raylib"
      call ui_set_idle_policy("adaptive", idle_fps=15)
    case ("tui") 
      print *, "Running in TUI mode with terminal"
  end select
  
  ! Same UI code works in both modes
  do while (.not. ui_should_close())
    call ui_frame_begin(200)  ! timeout only affects TUI
    
    ! Your UI code here - identical for both backends
    
    call ui_present()
  end do
  
  call ui_shutdown()
end program
```

### Deployment Scripts

```bash
#!/bin/bash
# deploy.sh - Deploy with backend detection

if pkg-config --exists raylib; then
    echo "Building with GUI support..."
    source fpm_env.sh
else
    echo "Building TUI-only version..."
    DISABLE_GUI=1 source fpm_env.sh
fi

fpm build --release
cp build/gfortran_*/app/myapp ./myapp-$(uname -s)
echo "Built: ./myapp-$(uname -s)"
```

## Performance Characteristics

### GUI Mode Performance
- **Target FPS**: 60 (configurable up to monitor refresh rate)
- **VSync**: Enabled by default (prevents tearing)
- **Frame timing**: Hardware-accelerated with GPU
- **Memory**: ~2-5MB additional for raylib context

### Power Management
```fortran
! Battery-friendly configuration
call ui_init("gui", 800, 600, "Battery App", target_fps=30, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=5)
```

## Summary

The GUI backend provides:
- ✅ **Conditional compilation**: Builds only when raylib available
- ✅ **Automatic detection**: Environment-aware backend selection
- ✅ **Graceful fallback**: Never fails, falls back to TUI
- ✅ **Pixel-perfect**: Monospace consistency with TUI
- ✅ **Cross-platform**: Linux, macOS, Windows support
- ✅ **Performance tuned**: VSync, target FPS, adaptive idle
- ✅ **Production ready**: Error handling, resource cleanup

**Next Steps:**
- [TUI Backend Guide](TUI_BACKEND_GUIDE.md) - Terminal UI backend
- [Developer Guide](DEVELOPER_GUIDE.md) - Integration patterns
- [Build Guide](../BUILD_GUIDE.md) - Dependency setup