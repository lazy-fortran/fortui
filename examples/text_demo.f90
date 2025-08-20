program text_demo
  ! Demonstrate text widget functionality
  use fortui_widgets
  use fortui_units
  implicit none


  print *, "=== Text Widget Demo ==="

  ! Basic text display
  call text("title", "fortui Text Widget Demo")
  print *, "✓ Basic text widget created"

  ! Custom sizing
  call text("sized", "Custom sized text", text_size=sp(18.0), width=dp(300.0))
  print *, "✓ Custom sized text widget created"

  ! Multiline content
  call text("multiline", "Line 1" // char(10) // "Line 2" // char(10) // "Line 3")
  print *, "✓ Multiline text widget created"

  ! TUI-friendly units
  call text("terminal", "Terminal-optimized text", width=cw(30.0), height=ch(2.0))
  print *, "✓ TUI-optimized text widget created"

  ! Auto-sizing demonstration
  call text("auto", "Auto-sized content adapts to text length")
  print *, "✓ Auto-sizing text widget created"

  ! Unit system showcase
  call text("units_dp", "Density-independent pixels", text_size=dp(14.0))
  call text("units_em", "Font-relative sizing", text_size=em(1.2))
  call text("units_sp", "Scaled pixels", text_size=sp(16.0))
  print *, "✓ Various unit types demonstrated"

  print *, ""
  print *, "Text widget demo completed successfully!"
  print *, "All widgets support ID-based state management"
  print *, "and cross-backend rendering compatibility."
end program