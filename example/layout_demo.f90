program layout_demo
! Demonstrates layout constructor functions with real UI tree building
! Shows column() and row() usage with gap parameters and nested structures
use fortui
implicit none

type(node) :: ui_root, header_section, content_area, footer_section
type(node) :: sidebar, main_content, button_row
type(node), allocatable :: children(:), buttons(:), nav_items(:)
type(node), allocatable :: content_items(:)
logical :: running
integer :: frame_count = 0

call ui_init(backend="auto", width=80, height=25, title="Layout Demo")

call ui_set_idle_policy("adaptive", idle_fps=12)

print *, "Layout Demo: Press ESC or close window to exit"
print *, "Demonstrating column() and row() layout functions"

running = .true.
do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame_count = frame_count + 1

    allocate(children(1))
    children(1) = node()
    header_section = column(gap=0.0, children=children)
    deallocate(children)

    allocate(nav_items(4))
    nav_items(1) = node()
    nav_items(2) = node()
    nav_items(3) = node()
    nav_items(4) = node()
    sidebar = column(gap=16.0, children=nav_items)
    deallocate(nav_items)

    allocate(content_items(3))
    content_items(1) = node()
    content_items(2) = node()
    content_items(3) = node()
    main_content = column(gap=16.0, children=content_items)
    deallocate(content_items)

    allocate(children(2))
    children(1) = sidebar
    children(2) = main_content
    content_area = row(gap=24.0, children=children)
    deallocate(children)

    allocate(buttons(3))
    buttons(1) = node()
    buttons(2) = node()
    buttons(3) = node()
    button_row = row(gap=12.0, children=buttons)
    deallocate(buttons)

    allocate(children(1))
    children(1) = button_row
    footer_section = column(gap=8.0, children=children)
    deallocate(children)

    allocate(children(3))
    children(1) = header_section
    children(2) = content_area
    children(3) = footer_section
    ui_root = column(gap=32.0, children=children)
    deallocate(children)

    call ui_present(ui_root)

    running = .not. ui_should_close()

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
print *, "  Memory management: Automatic cleanup"

end program layout_demo
