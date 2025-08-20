program text_demo
  ! Demonstrate text widget functionality
  use fortui_widgets
  use fortui_units
  implicit none

  type(text_node_t) :: text_widget

  print *, "=== Text Widget Demo ==="

  ! Basic text display
  text_widget = text("title", "fortui Text Widget Demo")
  print *, "✓ Basic text widget created"

  ! Custom sizing (convert unit types to real values)
  text_widget = text("sized", "Custom sized text", text_size=18.0, width=300.0)
  print *, "✓ Custom sized text widget created"

  ! Multiline content
  text_widget = text("multiline", "Line 1" // char(10) // "Line 2" // char(10) // "Line 3")
  print *, "✓ Multiline text widget created"

  ! TUI-friendly units (convert to real values)
  text_widget = text("terminal", "Terminal-optimized text", width=240.0, height=32.0)  ! ~30 chars * 8px, 2 lines * 16px
  print *, "✓ TUI-optimized text widget created"

  ! Auto-sizing demonstration
  text_widget = text("auto", "Auto-sized content adapts to text length")
  print *, "✓ Auto-sizing text widget created"

  ! Various text sizes (using real values for current API)
  text_widget = text("units_dp", "Density-independent pixels", text_size=14.0)
  text_widget = text("units_em", "Font-relative sizing", text_size=19.2)  ! ~1.2em * 16px
  text_widget = text("units_sp", "Scaled pixels", text_size=16.0)
  print *, "✓ Various unit types demonstrated"

  print *, ""
  print *, "Text widget demo completed successfully!"
  print *, "All widgets support ID-based state management"
  print *, "and cross-backend rendering compatibility."
end program