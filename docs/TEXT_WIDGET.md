# Text Widget API

Display text content with auto-sizing and cross-backend rendering.

## Usage

```fortran
call text(id, value [, text_size] [, width] [, height])
```

### Parameters

- `id` - Unique widget identifier (string)
- `value` - Text content to display (string)
- `text_size` - Font size (optional, class(*) unit)
- `width` - Widget width (optional, class(*) unit, 0=auto)
- `height` - Widget height (optional, class(*) unit, 0=auto)

### Examples

```fortran
use fortui_widgets
use fortui_units

! Basic text display
call text("label", "Hello World!")

! Custom size and dimensions
call text("title", "Title Text", text_size=sp(18.0), width=dp(200.0))

! Auto-sizing with multiline content
call text("info", "Line 1" // char(10) // "Line 2" // char(10) // "Line 3")

! TUI-friendly units
call text("tui_text", "Terminal Text", width=cw(20.0), height=ch(3.0))
```

## Auto-sizing Behavior

- **Width**: Based on longest line length + padding
- **Height**: Based on line count and wrapping estimation
- **Wrapping**: Automatic for long text exceeding width
- **Clipping**: Text clipped at widget boundaries

## Unit Support

All unit types via `class(*)` parameters:
- `dp()` - density-independent pixels
- `em()` - relative to font size
- `sp()` - scaled pixels (accessibility)
- `px()` - physical pixels
- `cw()` - cell widths (TUI-friendly)
- `ch()` - cell heights (TUI-friendly)
- Bare real - treated as dp

## Content Processing

- **Unicode**: Full Unicode character support
- **Newlines**: ASCII 10 (char(10)) for line breaks
- **Wrapping**: Character-based wrapping estimation
- **State**: ID-based state management with automatic cleanup

## Integration

Works with layout system:
```fortran
ui = column(children=[ &
  text("header", "Application Title"), &
  text("content", "Main content area") ])
```