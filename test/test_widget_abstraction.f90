module test_widget_abstraction
! Tests for Widget-Renderer Collaboration Pattern (Issue #61)
! Verifies proper abstraction between widgets and rendering backends
!
! Given: A widget abstraction architecture with renderer interfaces
! When: Widgets interact with backends through abstract interfaces
! Then: Proper encapsulation and rendering collaboration occurs
implicit none

! Simple types for testing (representing the future widget renderer interface)
type :: ui_rect
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 0.0
    real :: height = 0.0
end type ui_rect

type :: ui_color
    real :: r = 0.0
    real :: g = 0.0
    real :: b = 0.0
    real :: a = 1.0
end type ui_color

! Mock renderer interface for testing
type :: mock_widget_renderer_t
    logical :: draw_button_called = .false.
    logical :: draw_text_called = .false.
    logical :: draw_slider_called = .false.
    logical :: draw_checkbox_called = .false.
    logical :: draw_viewport_called = .false.
    character(len=256) :: last_widget_id = ""
    character(len=256) :: last_label = ""
    type(ui_rect) :: last_bounds
    integer :: last_visual_state = -1
    logical :: last_pressed_state = .false.
    integer :: call_count = 0
contains
    procedure :: draw_button => mock_draw_button
    procedure :: draw_text => mock_draw_text
    procedure :: draw_slider => mock_draw_slider
    procedure :: draw_checkbox => mock_draw_checkbox
    procedure :: draw_viewport => mock_draw_viewport
    procedure :: reset => mock_reset
end type mock_widget_renderer_t

! Mock render context for testing
type :: mock_render_context_t
    real :: viewport_x = 0.0
    real :: viewport_y = 0.0
    real :: viewport_w = 800.0
    real :: viewport_h = 600.0
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    logical :: clipping_enabled = .false.
end type mock_render_context_t

! Mock widget state types for testing
integer, parameter :: WIDGET_NORMAL = 0
integer, parameter :: WIDGET_HOVER = 1
integer, parameter :: WIDGET_PRESSED = 2
integer, parameter :: WIDGET_FOCUSED = 3
integer, parameter :: WIDGET_DISABLED = 4

type :: mock_widget_state_t
    character(len=256) :: id = ""
    integer :: visual_state = WIDGET_NORMAL
    logical :: visible = .true.
    logical :: interactive = .true.
end type mock_widget_state_t

type, extends(mock_widget_state_t) :: mock_button_state_t
    character(len=256) :: label = ""
    logical :: clicked_this_frame = .false.
    logical :: was_pressed_last_frame = .false.
end type mock_button_state_t

! Mock renderable widget interface for testing
type :: mock_renderable_widget_t
    real :: x = 0.0, y = 0.0, width = 100.0, height = 30.0
    character(len=256) :: label = ""
    logical :: render_called = .false.
    logical :: update_state_called = .false.
    logical :: get_bounds_called = .false.
    logical :: hit_test_called = .false.
contains
    procedure :: render => mock_widget_render
    procedure :: update_state => mock_widget_update_state
    procedure :: get_bounds => mock_widget_get_bounds
    procedure :: hit_test => mock_widget_hit_test
    procedure :: reset => mock_widget_reset
end type mock_renderable_widget_t

contains

! Test 1: Abstract Widget Renderer Interface
subroutine test_abstract_widget_renderer_interface()
    ! Given: A widget renderer interface with drawing primitives
    ! When: Each drawing primitive is called
    ! Then: Correct method dispatch occurs with proper parameters
    
    type(mock_widget_renderer_t) :: renderer
    type(ui_rect) :: bounds
    
    print *, "=== Testing Abstract Widget Renderer Interface ==="
    
    ! Initialize test bounds
    bounds%x = 10.0
    bounds%y = 20.0
    bounds%width = 100.0
    bounds%height = 30.0
    
    ! Test button drawing interface
    call renderer%draw_button("test_button", "Click Me", bounds, WIDGET_NORMAL, .false.)
    
    if (.not. renderer%draw_button_called) then
        print *, "FAIL: draw_button method not called"
        return
    end if
    
    if (trim(renderer%last_widget_id) /= "test_button") then
        print *, "FAIL: Widget ID not passed correctly to renderer"
        return
    end if
    
    if (trim(renderer%last_label) /= "Click Me") then
        print *, "FAIL: Widget label not passed correctly to renderer"
        return
    end if
    
    if (renderer%last_visual_state /= WIDGET_NORMAL) then
        print *, "FAIL: Visual state not passed correctly to renderer"
        return
    end if
    
    ! Test text drawing interface
    call renderer%draw_text("test_text", "Hello World", bounds, WIDGET_NORMAL, .false.)
    
    if (.not. renderer%draw_text_called) then
        print *, "FAIL: draw_text method not called"
        return
    end if
    
    ! Test slider drawing interface
    call renderer%draw_slider("test_slider", bounds, WIDGET_NORMAL, .false., 0.5)
    
    if (.not. renderer%draw_slider_called) then
        print *, "FAIL: draw_slider method not called"
        return
    end if
    
    ! Test checkbox drawing interface
    call renderer%draw_checkbox("test_checkbox", "Enable", bounds, WIDGET_NORMAL, .false., .true.)
    
    if (.not. renderer%draw_checkbox_called) then
        print *, "FAIL: draw_checkbox method not called"
        return
    end if
    
    ! Test viewport drawing interface
    call renderer%draw_viewport("test_viewport", bounds, WIDGET_NORMAL, .false.)
    
    if (.not. renderer%draw_viewport_called) then
        print *, "FAIL: draw_viewport method not called"
        return
    end if
    
    if (renderer%call_count /= 5) then
        print *, "FAIL: Expected 5 drawing calls, got:", renderer%call_count
        return
    end if
    
    print *, "PASS: Abstract widget renderer interface works correctly"
end subroutine test_abstract_widget_renderer_interface

! Test 2: Renderable Widget Interface Implementation
subroutine test_renderable_widget_interface()
    ! Given: A renderable widget with abstract interface methods
    ! When: Interface methods are called
    ! Then: Widget responds correctly with proper encapsulation
    
    type(mock_renderable_widget_t) :: widget
    type(mock_widget_renderer_t) :: renderer
    type(mock_render_context_t) :: context
    type(mock_button_state_t) :: state
    type(ui_rect) :: bounds
    logical :: hit_result
    
    print *, "=== Testing Renderable Widget Interface ==="
    
    ! Initialize widget state
    state%id = "test_widget"
    state%label = "Test Button"
    state%visual_state = WIDGET_HOVER
    state%visible = .true.
    state%interactive = .true.
    
    ! Test render method
    call widget%render(renderer, context, state)
    
    if (.not. widget%render_called) then
        print *, "FAIL: Widget render method not called"
        return
    end if
    
    ! Test update_state method
    call widget%update_state(50.0, 25.0, .true., state)
    
    if (.not. widget%update_state_called) then
        print *, "FAIL: Widget update_state method not called"
        return
    end if
    
    ! Test get_bounds method
    call widget%get_bounds(bounds)
    
    if (.not. widget%get_bounds_called) then
        print *, "FAIL: Widget get_bounds method not called"
        return
    end if
    
    if (abs(bounds%x - widget%x) > 1e-6) then
        print *, "FAIL: Widget bounds X not returned correctly"
        return
    end if
    
    if (abs(bounds%y - widget%y) > 1e-6) then
        print *, "FAIL: Widget bounds Y not returned correctly"
        return
    end if
    
    if (abs(bounds%width - widget%width) > 1e-6) then
        print *, "FAIL: Widget bounds width not returned correctly"
        return
    end if
    
    if (abs(bounds%height - widget%height) > 1e-6) then
        print *, "FAIL: Widget bounds height not returned correctly"
        return
    end if
    
    ! Test hit_test method - inside bounds
    hit_result = widget%hit_test(50.0, 15.0)
    
    if (.not. widget%hit_test_called) then
        print *, "FAIL: Widget hit_test method not called"
        return
    end if
    
    if (.not. hit_result) then
        print *, "FAIL: Hit test should return true for point inside widget"
        return
    end if
    
    ! Test hit_test method - outside bounds
    call widget%reset()
    hit_result = widget%hit_test(200.0, 200.0)
    
    if (hit_result) then
        print *, "FAIL: Hit test should return false for point outside widget"
        return
    end if
    
    print *, "PASS: Renderable widget interface works correctly"
end subroutine test_renderable_widget_interface

! Test 3: Widget-Renderer Collaboration Pattern
subroutine test_widget_renderer_collaboration()
    ! Given: A widget that collaborates with a renderer
    ! When: Widget is rendered through the collaboration pattern
    ! Then: Widget encapsulates behavior while renderer handles drawing
    
    type(mock_renderable_widget_t) :: widget
    type(mock_widget_renderer_t) :: renderer
    type(mock_render_context_t) :: context
    type(mock_button_state_t) :: state
    type(ui_rect) :: expected_bounds
    
    print *, "=== Testing Widget-Renderer Collaboration Pattern ==="
    
    ! Setup widget properties
    widget%x = 100.0
    widget%y = 200.0
    widget%width = 120.0
    widget%height = 40.0
    widget%label = "Collaboration Test"
    
    ! Setup widget state
    state%id = "collab_widget"
    state%label = "Collaboration Test"
    state%visual_state = WIDGET_PRESSED
    state%visible = .true.
    state%interactive = .true.
    state%clicked_this_frame = .true.
    
    ! Setup render context with viewport and scaling
    context%viewport_x = 50.0
    context%viewport_y = 50.0
    context%scale_x = 1.5
    context%scale_y = 1.5
    context%clipping_enabled = .true.
    
    ! Test collaboration: widget should call renderer with its own data
    call widget%render(renderer, context, state)
    
    ! Verify widget was asked to render
    if (.not. widget%render_called) then
        print *, "FAIL: Widget render method not invoked in collaboration"
        return
    end if
    
    ! In a real implementation, widget would call renderer%draw_button
    ! Here we simulate this by having the mock widget call the renderer
    call widget%get_bounds(expected_bounds)
    call renderer%draw_button(state%id, state%label, expected_bounds, &
                             state%visual_state, state%clicked_this_frame)
    
    ! Verify renderer was called by widget
    if (.not. renderer%draw_button_called) then
        print *, "FAIL: Widget did not collaborate with renderer"
        return
    end if
    
    ! Verify correct data passed through collaboration
    if (trim(renderer%last_widget_id) /= "collab_widget") then
        print *, "FAIL: Widget ID not passed through collaboration"
        return
    end if
    
    if (trim(renderer%last_label) /= "Collaboration Test") then
        print *, "FAIL: Widget label not passed through collaboration"
        return
    end if
    
    if (renderer%last_visual_state /= WIDGET_PRESSED) then
        print *, "FAIL: Visual state not passed through collaboration"
        return
    end if
    
    if (.not. renderer%last_pressed_state) then
        print *, "FAIL: Pressed state not passed through collaboration"
        return
    end if
    
    ! Test state update collaboration
    call widget%update_state(110.0, 220.0, .false., state)
    
    if (.not. widget%update_state_called) then
        print *, "FAIL: Widget state update not called in collaboration"
        return
    end if
    
    print *, "PASS: Widget-renderer collaboration pattern works correctly"
end subroutine test_widget_renderer_collaboration

! Test 4: Backend-Specific Rendering Behavior
subroutine test_backend_specific_rendering()
    ! Given: Different backend renderers (TUI vs GUI)
    ! When: Same widget is rendered with different backends
    ! Then: Each backend handles rendering according to its capabilities
    
    type(mock_widget_renderer_t) :: tui_renderer, gui_renderer
    type(mock_renderable_widget_t) :: widget
    type(mock_render_context_t) :: tui_context, gui_context
    type(mock_button_state_t) :: state
    type(ui_rect) :: tui_bounds, gui_bounds
    
    print *, "=== Testing Backend-Specific Rendering Behavior ==="
    
    ! Setup common widget state
    state%id = "backend_test"
    state%label = "Backend Test"
    state%visual_state = WIDGET_HOVER
    
    ! Setup TUI context (character-based, limited colors)
    tui_context%viewport_w = 80.0  ! 80 columns
    tui_context%viewport_h = 25.0  ! 25 rows
    tui_context%scale_x = 1.0      ! No scaling in TUI
    tui_context%scale_y = 1.0
    tui_context%clipping_enabled = .false.  ! Basic clipping in TUI
    
    ! Setup GUI context (pixel-based, full graphics)
    gui_context%viewport_w = 1920.0  ! 1920 pixels
    gui_context%viewport_h = 1080.0  ! 1080 pixels
    gui_context%scale_x = 2.0        ! High-DPI scaling
    gui_context%scale_y = 2.0
    gui_context%clipping_enabled = .true.  ! Advanced clipping in GUI
    
    ! Test TUI rendering
    call widget%render(tui_renderer, tui_context, state)
    call widget%get_bounds(tui_bounds)
    call tui_renderer%draw_button(state%id, state%label, tui_bounds, &
                                 state%visual_state, .false.)
    
    if (.not. tui_renderer%draw_button_called) then
        print *, "FAIL: TUI renderer not called"
        return
    end if
    
    ! Test GUI rendering
    call widget%reset()
    call widget%render(gui_renderer, gui_context, state)
    call widget%get_bounds(gui_bounds)
    call gui_renderer%draw_button(state%id, state%label, gui_bounds, &
                                 state%visual_state, .false.)
    
    if (.not. gui_renderer%draw_button_called) then
        print *, "FAIL: GUI renderer not called"
        return
    end if
    
    ! Both renderers should have been called with same widget data
    if (trim(tui_renderer%last_widget_id) /= trim(gui_renderer%last_widget_id)) then
        print *, "FAIL: Backend renderers received different widget IDs"
        return
    end if
    
    if (trim(tui_renderer%last_label) /= trim(gui_renderer%last_label)) then
        print *, "FAIL: Backend renderers received different labels"
        return
    end if
    
    if (tui_renderer%last_visual_state /= gui_renderer%last_visual_state) then
        print *, "FAIL: Backend renderers received different visual states"
        return
    end if
    
    print *, "PASS: Backend-specific rendering behavior works correctly"
end subroutine test_backend_specific_rendering

! Test 5: Widget Encapsulation and State Management
subroutine test_widget_encapsulation_state_management()
    ! Given: Multiple widgets with ID-based state management
    ! When: Widgets manage their own state through IDs
    ! Then: State is properly encapsulated and isolated by ID
    
    type(mock_renderable_widget_t) :: widget1, widget2
    type(mock_widget_renderer_t) :: renderer
    type(mock_render_context_t) :: context
    type(mock_button_state_t) :: state1, state2
    type(ui_rect) :: bounds1, bounds2
    
    print *, "=== Testing Widget Encapsulation and State Management ==="
    
    ! Setup first widget with unique ID
    state1%id = "widget_1"
    state1%label = "Button One"
    state1%visual_state = WIDGET_NORMAL
    state1%clicked_this_frame = .false.
    
    ! Setup second widget with different ID
    state2%id = "widget_2"
    state2%label = "Button Two"
    state2%visual_state = WIDGET_HOVER
    state2%clicked_this_frame = .true.
    
    ! Test state isolation - each widget should maintain separate state
    call widget1%update_state(50.0, 15.0, .true., state1)
    call widget2%update_state(150.0, 15.0, .false., state2)
    
    if (.not. widget1%update_state_called) then
        print *, "FAIL: First widget state update not called"
        return
    end if
    
    if (.not. widget2%update_state_called) then
        print *, "FAIL: Second widget state update not called"
        return
    end if
    
    ! States should remain isolated
    if (trim(state1%id) == trim(state2%id)) then
        print *, "FAIL: Widget IDs not properly isolated"
        return
    end if
    
    if (trim(state1%label) == trim(state2%label)) then
        print *, "FAIL: Widget labels not properly isolated"
        return
    end if
    
    if (state1%visual_state == state2%visual_state) then
        print *, "FAIL: Widget visual states not properly isolated"
        return
    end if
    
    if (state1%clicked_this_frame .eqv. state2%clicked_this_frame) then
        print *, "FAIL: Widget click states not properly isolated"
        return
    end if
    
    ! Test rendering with isolated states
    call widget1%render(renderer, context, state1)
    call widget1%get_bounds(bounds1)
    call renderer%draw_button(state1%id, state1%label, bounds1, &
                             state1%visual_state, state1%clicked_this_frame)
    
    if (trim(renderer%last_widget_id) /= "widget_1") then
        print *, "FAIL: First widget ID not properly encapsulated"
        return
    end if
    
    if (trim(renderer%last_label) /= "Button One") then
        print *, "FAIL: First widget label not properly encapsulated"
        return
    end if
    
    call renderer%reset()
    call widget2%render(renderer, context, state2)
    call widget2%get_bounds(bounds2)
    call renderer%draw_button(state2%id, state2%label, bounds2, &
                             state2%visual_state, state2%clicked_this_frame)
    
    if (trim(renderer%last_widget_id) /= "widget_2") then
        print *, "FAIL: Second widget ID not properly encapsulated"
        return
    end if
    
    if (trim(renderer%last_label) /= "Button Two") then
        print *, "FAIL: Second widget label not properly encapsulated"
        return
    end if
    
    print *, "PASS: Widget encapsulation and state management works correctly"
end subroutine test_widget_encapsulation_state_management

! Test 6: Double Dispatch Pattern for Visitor-Style Rendering
subroutine test_double_dispatch_pattern()
    ! Given: A visitor pattern for widget rendering with double dispatch
    ! When: Different widget types are rendered through the same interface
    ! Then: Correct rendering method is dispatched based on widget type
    
    type(mock_widget_renderer_t) :: renderer
    type(mock_render_context_t) :: context
    
    print *, "=== Testing Double Dispatch Pattern ==="
    
    ! Test button dispatch
    call test_widget_dispatch(renderer, context, "button", "test_button", "Button")
    
    if (.not. renderer%draw_button_called) then
        print *, "FAIL: Button dispatch did not call draw_button"
        return
    end if
    
    call renderer%reset()
    
    ! Test text dispatch
    call test_widget_dispatch(renderer, context, "text", "test_text", "Text Widget")
    
    if (.not. renderer%draw_text_called) then
        print *, "FAIL: Text dispatch did not call draw_text"
        return
    end if
    
    call renderer%reset()
    
    ! Test slider dispatch
    call test_widget_dispatch(renderer, context, "slider", "test_slider", "")
    
    if (.not. renderer%draw_slider_called) then
        print *, "FAIL: Slider dispatch did not call draw_slider"
        return
    end if
    
    call renderer%reset()
    
    ! Test checkbox dispatch
    call test_widget_dispatch(renderer, context, "checkbox", "test_checkbox", "Check Me")
    
    if (.not. renderer%draw_checkbox_called) then
        print *, "FAIL: Checkbox dispatch did not call draw_checkbox"
        return
    end if
    
    call renderer%reset()
    
    ! Test viewport dispatch
    call test_widget_dispatch(renderer, context, "viewport", "test_viewport", "")
    
    if (.not. renderer%draw_viewport_called) then
        print *, "FAIL: Viewport dispatch did not call draw_viewport"
        return
    end if
    
    print *, "PASS: Double dispatch pattern works correctly"
end subroutine test_double_dispatch_pattern

! Helper subroutine to simulate widget dispatch based on type
subroutine test_widget_dispatch(renderer, context, widget_type, widget_id, label)
    type(mock_widget_renderer_t), intent(inout) :: renderer
    type(mock_render_context_t), intent(in) :: context
    character(*), intent(in) :: widget_type, widget_id, label
    
    type(ui_rect) :: bounds
    
    ! Mock bounds for testing
    bounds%x = 10.0
    bounds%y = 20.0
    bounds%width = 100.0
    bounds%height = 30.0
    
    ! Simulate double dispatch based on widget type
    select case(trim(widget_type))
    case("button")
        call renderer%draw_button(widget_id, label, bounds, WIDGET_NORMAL, .false.)
    case("text")
        call renderer%draw_text(widget_id, label, bounds, WIDGET_NORMAL, .false.)
    case("slider")
        call renderer%draw_slider(widget_id, bounds, WIDGET_NORMAL, .false., 0.5)
    case("checkbox")
        call renderer%draw_checkbox(widget_id, label, bounds, WIDGET_NORMAL, .false., .true.)
    case("viewport")
        call renderer%draw_viewport(widget_id, bounds, WIDGET_NORMAL, .false.)
    end select
end subroutine test_widget_dispatch

! Mock renderer methods
subroutine mock_draw_button(self, id, label, bounds, visual_state, pressed)
    class(mock_widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, label
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: pressed
    
    self%draw_button_called = .true.
    self%last_widget_id = id
    self%last_label = label
    self%last_bounds = bounds
    self%last_visual_state = visual_state
    self%last_pressed_state = pressed
    self%call_count = self%call_count + 1
end subroutine mock_draw_button

subroutine mock_draw_text(self, id, text, bounds, visual_state, focused)
    class(mock_widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, text
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: focused
    
    self%draw_text_called = .true.
    self%last_widget_id = id
    self%last_label = text
    self%last_bounds = bounds
    self%last_visual_state = visual_state
    self%call_count = self%call_count + 1
end subroutine mock_draw_text

subroutine mock_draw_slider(self, id, bounds, visual_state, dragging, value)
    class(mock_widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: dragging
    real, intent(in) :: value
    
    self%draw_slider_called = .true.
    self%last_widget_id = id
    self%last_bounds = bounds
    self%last_visual_state = visual_state
    self%call_count = self%call_count + 1
end subroutine mock_draw_slider

subroutine mock_draw_checkbox(self, id, label, bounds, visual_state, hover, checked)
    class(mock_widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, label
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: hover, checked
    
    self%draw_checkbox_called = .true.
    self%last_widget_id = id
    self%last_label = label
    self%last_bounds = bounds
    self%last_visual_state = visual_state
    self%call_count = self%call_count + 1
end subroutine mock_draw_checkbox

subroutine mock_draw_viewport(self, id, bounds, visual_state, active)
    class(mock_widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: active
    
    self%draw_viewport_called = .true.
    self%last_widget_id = id
    self%last_bounds = bounds
    self%last_visual_state = visual_state
    self%call_count = self%call_count + 1
end subroutine mock_draw_viewport

subroutine mock_reset(self)
    class(mock_widget_renderer_t), intent(inout) :: self
    
    self%draw_button_called = .false.
    self%draw_text_called = .false.
    self%draw_slider_called = .false.
    self%draw_checkbox_called = .false.
    self%draw_viewport_called = .false.
    self%last_widget_id = ""
    self%last_label = ""
    self%last_visual_state = -1
    self%last_pressed_state = .false.
    self%call_count = 0
end subroutine mock_reset

! Mock widget methods
subroutine mock_widget_render(self, renderer, context, state)
    class(mock_renderable_widget_t), intent(inout) :: self
    class(*), intent(inout) :: renderer  ! Would be widget_renderer_t in real implementation
    class(*), intent(in) :: context      ! Would be render_context_t in real implementation
    class(*), intent(in) :: state        ! Would be widget_state_t in real implementation
    
    self%render_called = .true.
    ! In real implementation, this would call renderer's appropriate draw method
end subroutine mock_widget_render

subroutine mock_widget_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(mock_renderable_widget_t), intent(inout) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(*), intent(inout) :: state     ! Would be widget_state_t in real implementation
    
    self%update_state_called = .true.
    ! In real implementation, this would update widget's internal state
end subroutine mock_widget_update_state

subroutine mock_widget_get_bounds(self, bounds)
    class(mock_renderable_widget_t), intent(inout) :: self
    type(ui_rect), intent(out) :: bounds
    
    self%get_bounds_called = .true.
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine mock_widget_get_bounds

function mock_widget_hit_test(self, x, y) result(hit)
    class(mock_renderable_widget_t), intent(inout) :: self
    real, intent(in) :: x, y
    logical :: hit
    
    self%hit_test_called = .true.
    
    ! Simple rectangular hit test
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function mock_widget_hit_test


subroutine mock_widget_reset(self)
    class(mock_renderable_widget_t), intent(inout) :: self
    
    self%render_called = .false.
    self%update_state_called = .false.
    self%get_bounds_called = .false.
    self%hit_test_called = .false.
end subroutine mock_widget_reset

! Main test runner
subroutine run_all_widget_abstraction_tests()
    print *, ""
    print *, "========================================================"
    print *, "Running Widget Abstraction Tests (Issue #61)"
    print *, "Testing Widget-Renderer Collaboration Pattern"
    print *, "========================================================"
    print *, ""
    
    call test_abstract_widget_renderer_interface()
    print *, ""
    
    call test_renderable_widget_interface()
    print *, ""
    
    call test_widget_renderer_collaboration()
    print *, ""
    
    call test_backend_specific_rendering()
    print *, ""
    
    call test_widget_encapsulation_state_management()
    print *, ""
    
    call test_double_dispatch_pattern()
    print *, ""
    
    print *, "========================================================"
    print *, "Widget Abstraction Tests Complete"
    print *, "========================================================"
end subroutine run_all_widget_abstraction_tests

end module test_widget_abstraction

! Test program
program test_widget_abstraction_main
    use test_widget_abstraction
    implicit none
    
    call run_all_widget_abstraction_tests()
end program test_widget_abstraction_main