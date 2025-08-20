# GUI Quick Start Guide

Get up and running with fortui's GUI backend in 5 minutes.

## 1. Install raylib

### Ubuntu/Debian
```bash
sudo apt update && sudo apt install libraylib-dev
```

### Fedora/RHEL  
```bash
sudo dnf install raylib-devel
```

### macOS
```bash
brew install raylib
```

### Arch Linux
```bash
sudo pacman -S raylib
```

### Windows (MSYS2)
```bash
pacman -S mingw-w64-x86_64-raylib
```

## 2. Clone and Build

```bash
git clone https://github.com/krystophny/fortui.git
cd fortui

# Automatic GUI detection and build
source fpm_env.sh
fmp build
```

**Expected output:**
```
Building dependencies...
GUI backend enabled with raylib/raygui
Configured for GUI+TUI build
FPM environment configured:
  FPM_FFLAGS: -cpp -DENABLE_GUI
  FPM_LDFLAGS: -lraylib -ltermbox2
```

## 3. Test GUI

```bash
# Run GUI demo
fpm run --example gui_demo

# Run tests
fpm test
```

## 4. Your First GUI App

Create `my_gui_app.f90`:

```fortran
program my_gui_app
  use fortui_core
  use fortui_widgets
  implicit none
  
  logical :: clicked
  integer :: count = 0
  
  ! Automatic backend selection
  call ui_init("auto", 400, 300, "My First GUI App")
  
  do while (.not. ui_should_close())
    call ui_frame_begin(0)
    
    ! Simple counter app  
    call text("title", "GUI Counter Demo")
    
    ! Format count as string
    character(len=32) :: count_str
    write(count_str, '("Count: ",I0)') count
    call text("count", trim(count_str))
    
    clicked = button("increment", "Click Me!", width=100.0, height=40.0)
    if (clicked) count = count + 1
    
    clicked = button("reset", "Reset", width=80.0, height=40.0)
    if (clicked) count = 0
    
    call ui_present()
  end do
  
  call ui_shutdown()
end program
```

Compile and run:
```bash
source fpm_env.sh
fpm run my_gui_app
```

## 5. Advanced Features

```fortran
program advanced_gui
  use fortui_core
  use fortui_widgets
  implicit none
  
  real :: volume = 50.0
  logical :: enabled = .true.
  type(view) :: plot_view
  
  ! High-performance GUI configuration
  call ui_init("gui", 800, 600, "Advanced GUI", target_fps=120, vsync=.false.)
  
  ! Power-efficient idle policy
  call ui_set_idle_policy("adaptive", idle_fps=15)
  
  do while (.not. ui_should_close())
    call ui_frame_begin(0)
    
    ! Interactive slider
    if (slider("volume", 0.0, 100.0, 1.0, volume, width=200.0)) then
      print *, "Volume changed to:", volume
    end if
    
    ! Toggle checkbox
    call checkbox("enable", enabled, "Enable Audio")
    
    ! Interactive viewport with pan/zoom
    if (viewport("plot", 400.0, 300.0, plot_view)) then
      ! Redraw plot content here
    end if
    
    call ui_present()
  end do
  
  call ui_shutdown()
end program
```

## Troubleshooting

**"GUI backend not available"**
```bash
# Check raylib installation
pkg-config --modversion raylib

# If missing, install raylib for your platform
# Then rebuild
FORCE_REBUILD=1 source fpm_env.sh
fpm build
```

**Window doesn't appear**
```bash
# Check display environment
echo $DISPLAY              # Should show :0 or similar (X11)
echo $WAYLAND_DISPLAY      # Should show wayland-0 (Wayland)

# Test raylib directly
cat > test.c << 'EOF'
#include <raylib.h>
int main() { InitWindow(400,300,"Test"); CloseWindow(); return 0; }
EOF
gcc test.c -lraylib && ./a.out
```

**TUI fallback instead of GUI**
```bash
# Force GUI mode for debugging
export FORTUI_BACKEND=gui
fpm run --example gui_demo

# Check environment detection
export DEBUG=1
source fpm_env.sh
```

## Next Steps

- **[GUI Backend Guide](GUI_BACKEND_GUIDE.md)**: Complete documentation
- **[Widget Examples](../examples/)**: More advanced GUI usage
- **[Developer Guide](DEVELOPER_GUIDE.md)**: Integration patterns