# fortui Units System Guide

## Abstract Unit Types (NEW)

fortui uses abstract unit types with polymorphic dispatch for type-safe, context-aware unit conversion:

```fortran
use fortui_unit_types

! Abstract unit types - polymorphic dispatch
call ui_init("auto", dp_unit(800.0), em_unit(30.0), "My App")

! All abstract unit constructors
width = dp_unit(40.0)         ! density-independent pixels
gap = em_unit(2.5)            ! relative to font size  
text_size = sp_unit(14.0)     ! scaled pixels (accessibility)
border = px_unit(2.0)         ! physical pixels
cols = cw_unit(10.0)          ! cell widths (TUI-friendly)
rows = ch_unit(3.0)           ! cell heights (TUI-friendly)

! Physical units with DPI awareness
paper_width = inches_unit(8.5)      ! physical inches
paper_height = cm_unit(21.0)        ! physical centimeters  
border_size = mm_unit(5.0)          ! millimeters
font_size = points_unit(12.0)       ! typography points (1/72 inch)
```

**Key Benefits:**
- **Type safety**: NO `class(*)` - only abstract `unit_type`
- **Polymorphic dispatch**: Context-aware conversion via abstract interface
- **Backend measurement**: Each unit type integrates with measurement system

## Unit Type Reference

| Type | Purpose | Conversion | Usage |
|------|---------|------------|-------|
| `dp_unit(val)` | Base density-independent pixels | `val` | `dp_unit(120.0)` |
| `em_unit(val)` | Font-relative size | `val * em_dp` | `em_unit(2.0)` |
| `sp_unit(val)` | Accessibility scaling | `val * text_scale` | `sp_unit(14.0)` |
| `px_unit(val)` | Physical pixels | `val / dpi_scale` | `px_unit(1.0)` |
| `cw_unit(val)` | Cell widths (TUI) | `val * cell_w_dp` | `cw_unit(12.0)` |
| `ch_unit(val)` | Cell heights (TUI) | `val * cell_h_dp` | `ch_unit(2.0)` |
| `inches_unit(val)` | Physical inches | `val * 96 * dpi_scale` | `inches_unit(8.5)` |
| `cm_unit(val)` | Physical centimeters | `val * 37.8 * dpi_scale` | `cm_unit(21.0)` |
| `mm_unit(val)` | Physical millimeters | `val * 3.78 * dpi_scale` | `mm_unit(5.0)` |
| `points_unit(val)` | Typography points | `val * 1.33 * dpi_scale` | `points_unit(12.0)` |

## UI Context Integration (NEW)

Abstract units use measurement-based context for accurate conversion:

```fortran
! Context setup is automatic during ui_init()
call ui_init("tui", cw_unit(80.0), ch_unit(25.0), "Terminal App")
! TUI: Measures actual terminal cell dimensions
! GUI: Detects system DPI, font metrics, accessibility scaling

! Mixed unit usage works everywhere
ui = column(gap=ch_unit(1.0), children=[ &
  button("ok", width=dp_unit(120.0), height=em_unit(2.5)), &
  slider("gain", width=px_unit(200.0), height=sp_unit(24.0)) ])
```

**Context Parameters:**
- `dpi_scale`: GUI DPI scaling factor (TUI always 1.0)
- `em_dp`: Font size in dp (measured from backend)
- `text_scale`: Accessibility text scaling (system detected)
- `cell_w_dp`, `cell_h_dp`: Terminal cell dimensions (measured)

## Cross-Backend Behavior

**TUI**: Units snap to integer cell boundaries for perfect terminal alignment  
**GUI**: Subpixel precision maintained for smooth graphics and HiDPI support

```fortran
! TUI example: 42.7 dp → 5 cells (snapped)
! GUI example: 42.7 dp → 64.05 pixels (precise)
```

## Usage Examples

```fortran
use fortui_core
use fortui_unit_types

! Mixed abstract units in ui_init()
call ui_init("auto", inches_unit(8.5), cm_unit(21.0), "Paper Size")

! Mixed units in widgets
ui = column(gap=ch_unit(1.0), children=[ &
  button("ok", width=dp_unit(120.0), height=em_unit(2.5)), &
  slider("gain", width=cw_unit(20.0), height=sp_unit(24.0)) ])
```

## Legacy Function Syntax

Legacy unit constructor functions remain supported for backward compatibility:

```fortran
use fortui_units

! Legacy syntax (still works)
width = dp(40.0)       ! equivalent to dp_unit(40.0)
gap = em(2.5)          ! equivalent to em_unit(2.5)
```

**Migration**: Replace `dp()` with `dp_unit()` etc. for abstract type support.

## Best Practices

1. **Use abstract types**: `dp_unit()` instead of `dp()` for type safety
2. **Mix units freely**: Different units work together seamlessly  
3. **Context is automatic**: No manual setup needed after `ui_init()`
4. **Physical units for print**: Use `inches_unit()`, `cm_unit()` for documents
5. **Cell units for TUI**: Use `cw_unit()`, `ch_unit()` for terminal alignment