program widget_examples_test
  use fortui_core
use fortui_widgets
  implicit none

  logical :: save_clicked, big_clicked, volume_changed, temp_changed
  logical :: sound_enabled = .true., enabled = .false.
  real :: volume = 50.0, temperature = 20.0
  ! All widget variables removed - widgets return status/nodes as needed
  ! Widget variables removed - text now works immediate-mode

  print *, "=== Testing README Widget Examples ==="

  ! Initialize with GUI backend (will fallback to TUI or error gracefully)
  call ui_init("auto", 640, 480, "Widget Examples Test")

  ! Test button examples from README
  save_clicked = button("save_btn", label="Save")
  if (save_clicked) then
      print *, "Save button clicked!"
  end if

  big_clicked = button("big_btn", width=80.0, height=40.0)
  if (big_clicked) then
      print *, "Big button clicked!"
  end if

  ! Test text widget examples (immediate-mode)
  call text("label", "Hello World!")
  call text("info", "Line 1" // char(10) // "Line 2", text_size=16.0)
  call text("terminal", "Terminal Text", width=25.0)

  ! Test slider examples
  volume_changed = slider("volume", 0.0, 100.0, 5.0, volume, width=120.0)
  if (volume_changed) then
      print *, "Volume changed to:", volume
  end if

  temp_changed = slider("temp", 15.0, 30.0, 0.0, temperature)
  if (temp_changed) then
      print *, "Temperature:", temperature, "°C"
  end if

  ! Test checkbox examples
  if (checkbox("sound", sound_enabled, "Enable Sound")) then
      sound_enabled = .not. sound_enabled
  end if
  if (sound_enabled) then
      print *, "Sound is enabled"
  end if

  if (checkbox("notifications", enabled, "Email Notifications")) then
      enabled = .not. enabled
  end if

  call ui_shutdown()
  print *, "All widget examples compiled and executed successfully!"
end program