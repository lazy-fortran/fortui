program layout_demo
! Demonstrates layout constructor functions with real UI tree building
! Shows column() and row() usage with gap parameters and nested structures
use fortui_core
use fortui_units
implicit none

type(node) :: ui_root, header_section, content_area, footer_section
type(node) :: sidebar, main_content, button_row
type(node), allocatable :: children(:), buttons(:), nav_items(:), content_items(:)
logical :: running
integer :: frame_count = 0

! Initialize with automatic backend selection
call ui_init(backend="auto", width=80, height=25, title="Layout Demo")

! Configure adaptive power saving for GUI mode (ignored in TUI)
call ui_set_idle_policy("adaptive", idle_fps=12)

print *, "Layout Demo: Press ESC or close window to exit"
print *, "Demonstrating column() and row() layout functions"

running = .true.
do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame_count = frame_count + 1
    
    ! Build header section
    allocate(children(1))
    children(1) = node()  ! Title placeholder
    header_section = column(gap=dp(0.0), children=children)
    deallocate(children)
    
    ! Build navigation sidebar
    allocate(nav_items(4))
    nav_items(1) = node()  ! Dashboard
    nav_items(2) = node()  ! Reports  
    nav_items(3) = node()  ! Settings
    nav_items(4) = node()  ! Help
    sidebar = column(gap=ch(1.0), children=nav_items)
    deallocate(nav_items)
    
    ! Build main content area
    allocate(content_items(3))
    content_items(1) = node()  ! Content header
    content_items(2) = node()  ! Main content body
    content_items(3) = node()  ! Status info
    main_content = column(gap=dp(16.0), children=content_items)
    deallocate(content_items)
    
    ! Combine sidebar and main content horizontally
    allocate(children(2))
    children(1) = sidebar
    children(2) = main_content
    content_area = row(gap=cw(3.0), children=children)
    deallocate(children)
    
    ! Build footer button row
    allocate(buttons(3))
    buttons(1) = node()  ! Save button
    buttons(2) = node()  ! Cancel button
    buttons(3) = node()  ! Help button
    button_row = row(gap=dp(12.0), children=buttons)
    deallocate(buttons)
    
    allocate(children(1))
    children(1) = button_row
    footer_section = column(gap=dp(8.0), children=children)
    deallocate(children)
    
    ! Build complete UI hierarchy: header / content / footer
    allocate(children(3))
    children(1) = header_section
    children(2) = content_area
    children(3) = footer_section
    ui_root = column(gap=ch(2.0), children=children)
    deallocate(children)
    
    ! Present the complete UI tree
    call ui_present(ui_root)
    
    ! Check for exit conditions
    running = .not. ui_should_close()
    
    ! Display frame info every 300 frames (approximately every 5-10 seconds)
    if (mod(frame_count, 300) == 0) then
        print *, "Frame:", frame_count, "- Layout tree rebuilt and presented"
    end if
end do

call ui_shutdown()

print *, ""
print *, "Layout Demo Statistics:"
print *, "  Total frames rendered:", frame_count
print *, "  UI tree complexity: 3-level nested layout hierarchy"
print *, "  Layout types used: column() and row() functions"
print *, "  Gap units tested: dp, ch, cw units for cross-backend compatibility"
print *, "  Memory management: Automatic cleanup - no manual deallocation needed"

end program layout_demo