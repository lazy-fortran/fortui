module fortui_gui_raylib
!! Graphical platform + renderer backend. Raylib/rlgl is a bootstrap backend, not
!! the FortUI abstraction. The backend owns all GPU resources: fonts, shaders and
!! retained canvas buffers keyed by canvas-store slot and serial.
!!
!! Rendering uses only raylib/rlgl APIs and GLSL 330 (OpenGL 3.3 core, also the
!! macOS core profile): instanced quads for points and lines, no point sprites,
!! no wide GL lines, no compute. Text uses a bundled DejaVu Sans subset unless
!! overridden (ui_set_font or FORTUI_FONT / FORTUI_FONT_BOLD).
use iso_c_binding
use iso_fortran_env, only: int32
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t
use fortui_canvas, only: canvas_store_t
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_text, only: text_use_fixed_metrics
#ifdef ENABLE_GUI
use fortui_frame, only: ui_node_t, ui_layer_ref_t, UI_TEXT, UI_BUTTON, UI_SLIDER, &
    UI_CHECKBOX, UI_VIEWPORT, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, &
    LAYER_POINTS, LAYER_LINES, SCROLL_PADDING, SCROLLBAR_WIDTH, INPUT_PADDING
use fortui_input, only: input_update_pointer, input_scroll, input_set_key, &
    input_type_text, input_set_time, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_SPACE, &
    KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_BACKSPACE, &
    KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGE_UP, KEY_PAGE_DOWN
use fortui_canvas, only: canvas_layer_t
use fortui_text, only: text_set_metrics, text_font_file, text_width, text_line_height, &
    utf8_encode, TEXT_MAX_CODEPOINT, TEXT_STYLE_REGULAR, TEXT_STYLE_BOLD
use fortui_error, only: report_error, report_warning
#endif
implicit none
private

#ifdef ENABLE_GUI
type, bind(C) :: rl_color
    integer(c_int8_t) :: r, g, b, a
end type rl_color

type, bind(C) :: rl_vector2
    real(c_float) :: x, y
end type rl_vector2

type, bind(C) :: rl_texture
    integer(c_int) :: id, width, height, mipmaps, format
end type rl_texture

type, bind(C) :: rl_font
    integer(c_int) :: base_size, glyph_count, glyph_padding
    type(rl_texture) :: texture
    type(c_ptr) :: recs, glyphs
end type rl_font

type :: gpu_layer_t
    integer :: serial = 0
    integer :: kind = 0
    integer(c_int) :: vao = 0
    integer(c_int) :: vbo_pos = 0, vbo_size = 0, vbo_col = 0, vbo_seg = 0
    integer(c_int) :: tex_pos = 0, tex_col = 0
    integer :: capacity = 0
    integer :: seg_capacity = 0
    integer :: tex_rows = 0
    integer :: segments = 0
end type gpu_layer_t

integer(c_int), parameter :: RL_FLAG_VSYNC = 64
integer(c_int), parameter :: RL_FLAG_RESIZABLE = 4
integer(c_int), parameter :: RL_FLAG_HIGHDPI = 8192
integer(c_int), parameter :: RL_MOUSE_LEFT = 0
integer(c_int), parameter :: RL_FLOAT = int(z'1406', c_int)
integer(c_int), parameter :: RL_UNSIGNED_BYTE = int(z'1401', c_int)
integer(c_int), parameter :: RL_UNIFORM_VEC4 = 3
integer(c_int), parameter :: RL_UNIFORM_INT = 4
integer(c_int), parameter :: RL_PIXEL_RGBA8 = 7
integer(c_int), parameter :: RL_PIXEL_RGBA32F = 10
integer(c_int), parameter :: TEX_FILTER_BILINEAR = 1
integer, parameter :: TEX_WIDTH = 2048
integer, parameter :: N_LADDER = 13
real, parameter :: LADDER(N_LADDER) = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, &
    28.0, 32.0, 40.0, 48.0, 64.0, 96.0]

logical, save :: active = .false.
real, save :: dpr = 1.0
type(rl_font), save :: fonts(N_LADDER, 2)
logical, save :: font_loaded(N_LADDER, 2) = .false.
integer(c_int), allocatable, target, save :: codepoints(:)
integer(c_int), save :: points_shader = 0, lines_shader = 0
integer(c_int), save :: loc_p_frame = -1, loc_p_view = -1, loc_p_style = -1
integer(c_int), save :: loc_l_frame = -1, loc_l_view = -1, loc_l_style = -1
integer(c_int), save :: loc_l_pos = -1, loc_l_col = -1
integer(c_int), save :: quad_points = 0, quad_lines = 0
logical, save :: shader_error_reported = .false.
type(gpu_layer_t), allocatable, save :: gpu(:)
real(c_float), allocatable, target, save :: scratch_f(:)
integer(int32), allocatable, target, save :: scratch_i(:)

interface
    subroutine rl_init_window(w, h, title) bind(C, name="InitWindow")
        import :: c_int, c_char
        integer(c_int), value :: w, h
        character(c_char), intent(in) :: title(*)
    end subroutine
    subroutine rl_close_window() bind(C, name="CloseWindow")
    end subroutine
    logical(c_bool) function rl_window_should_close() bind(C, name="WindowShouldClose")
        import :: c_bool
    end function
    logical(c_bool) function rl_is_window_resized() bind(C, name="IsWindowResized")
        import :: c_bool
    end function
    subroutine rl_begin_drawing() bind(C, name="BeginDrawing")
    end subroutine
    subroutine rl_end_drawing() bind(C, name="EndDrawing")
    end subroutine
    subroutine rl_clear_background(color) bind(C, name="ClearBackground")
        import :: rl_color
        type(rl_color), value :: color
    end subroutine
    subroutine rl_draw_rectangle(x, y, w, h, color) bind(C, name="DrawRectangle")
        import :: c_int, rl_color
        integer(c_int), value :: x, y, w, h
        type(rl_color), value :: color
    end subroutine
    subroutine rl_set_target_fps(fps) bind(C, name="SetTargetFPS")
        import :: c_int
        integer(c_int), value :: fps
    end subroutine
    subroutine rl_set_exit_key(key) bind(C, name="SetExitKey")
        import :: c_int
        integer(c_int), value :: key
    end subroutine
    integer(c_int) function rl_get_key_pressed() bind(C, name="GetKeyPressed")
        import :: c_int
    end function
    integer(c_int) function rl_get_char_pressed() bind(C, name="GetCharPressed")
        import :: c_int
    end function
    logical(c_bool) function rl_is_key_pressed_repeat(key) bind(C, name="IsKeyPressedRepeat")
        import :: c_int, c_bool
        integer(c_int), value :: key
    end function
    logical(c_bool) function rl_is_mouse_button_pressed(btn) bind(C, name="IsMouseButtonPressed")
        import :: c_int, c_bool
        integer(c_int), value :: btn
    end function
    logical(c_bool) function rl_is_mouse_button_down(btn) bind(C, name="IsMouseButtonDown")
        import :: c_int, c_bool
        integer(c_int), value :: btn
    end function
    integer(c_int) function rl_get_mouse_x() bind(C, name="GetMouseX")
        import :: c_int
    end function
    integer(c_int) function rl_get_mouse_y() bind(C, name="GetMouseY")
        import :: c_int
    end function
    real(c_float) function rl_get_mouse_wheel_move() bind(C, name="GetMouseWheelMove")
        import :: c_float
    end function
    subroutine rl_set_config_flags(flags) bind(C, name="SetConfigFlags")
        import :: c_int
        integer(c_int), value :: flags
    end subroutine
    real(c_double) function rl_get_time() bind(C, name="GetTime")
        import :: c_double
    end function
    integer(c_int) function rl_get_screen_width() bind(C, name="GetScreenWidth")
        import :: c_int
    end function
    integer(c_int) function rl_get_screen_height() bind(C, name="GetScreenHeight")
        import :: c_int
    end function
    integer(c_int) function rl_get_render_width() bind(C, name="GetRenderWidth")
        import :: c_int
    end function
    subroutine rl_enable_event_waiting() bind(C, name="EnableEventWaiting")
    end subroutine
    subroutine rl_disable_event_waiting() bind(C, name="DisableEventWaiting")
    end subroutine
    subroutine rl_begin_scissor(x, y, w, h) bind(C, name="BeginScissorMode")
        import :: c_int
        integer(c_int), value :: x, y, w, h
    end subroutine
    subroutine rl_end_scissor() bind(C, name="EndScissorMode")
    end subroutine
    logical(c_bool) function rl_file_exists(path) bind(C, name="FileExists")
        import :: c_bool, c_char
        character(c_char), intent(in) :: path(*)
    end function
    function rl_load_font_ex(path, size, cps, n) bind(C, name="LoadFontEx") result(f)
        import :: c_char, c_int, c_ptr, rl_font
        character(c_char), intent(in) :: path(*)
        integer(c_int), value :: size, n
        type(c_ptr), value :: cps
        type(rl_font) :: f
    end function
    function rl_load_font_mem(ftype, data, nbytes, size, cps, n) &
        bind(C, name="LoadFontFromMemory") result(f)
        import :: c_char, c_int, c_ptr, rl_font
        character(c_char), intent(in) :: ftype(*)
        type(c_ptr), value :: data, cps
        integer(c_int), value :: nbytes, size, n
        type(rl_font) :: f
    end function
    subroutine rl_unload_font(f) bind(C, name="UnloadFont")
        import :: rl_font
        type(rl_font), value :: f
    end subroutine
    subroutine rl_set_texture_filter(t, filter) bind(C, name="SetTextureFilter")
        import :: rl_texture, c_int
        type(rl_texture), value :: t
        integer(c_int), value :: filter
    end subroutine
    subroutine rl_draw_text_ex(f, text, pos, size, spacing, color) bind(C, name="DrawTextEx")
        import :: rl_font, c_char, rl_vector2, c_float, rl_color
        type(rl_font), value :: f
        character(c_char), intent(in) :: text(*)
        type(rl_vector2), value :: pos
        real(c_float), value :: size, spacing
        type(rl_color), value :: color
    end subroutine
    function rl_measure_text_ex(f, text, size, spacing) bind(C, name="MeasureTextEx") result(v)
        import :: rl_font, c_char, c_float, rl_vector2
        type(rl_font), value :: f
        character(c_char), intent(in) :: text(*)
        real(c_float), value :: size, spacing
        type(rl_vector2) :: v
    end function
    type(c_ptr) function fortui_font_data(style, nbytes) bind(C, name="fortui_font_data")
        import :: c_ptr, c_int
        integer(c_int), value :: style
        integer(c_int), intent(out) :: nbytes
    end function
    ! rlgl
    subroutine rl_draw_render_batch_active() bind(C, name="rlDrawRenderBatchActive")
    end subroutine
    integer(c_int) function rl_load_shader_program(vs, fs) bind(C, name="rlLoadShaderProgram")
        import :: c_int, c_char
        character(c_char), intent(in) :: vs(*), fs(*)
    end function
    subroutine rl_unload_shader_program(id) bind(C, name="rlUnloadShaderProgram")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    integer(c_int) function rl_get_location_uniform(id, name) bind(C, name="rlGetLocationUniform")
        import :: c_int, c_char
        integer(c_int), value :: id
        character(c_char), intent(in) :: name(*)
    end function
    subroutine rl_set_uniform(loc, value, utype, n) bind(C, name="rlSetUniform")
        import :: c_int, c_ptr
        integer(c_int), value :: loc, utype, n
        type(c_ptr), value :: value
    end subroutine
    subroutine rl_enable_shader(id) bind(C, name="rlEnableShader")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    subroutine rl_disable_shader() bind(C, name="rlDisableShader")
    end subroutine
    integer(c_int) function rl_load_vertex_array() bind(C, name="rlLoadVertexArray")
        import :: c_int
    end function
    integer(c_int) function rl_load_vertex_buffer(buf, nbytes, dynamic) bind(C, name="rlLoadVertexBuffer")
        import :: c_int, c_ptr, c_bool
        type(c_ptr), value :: buf
        integer(c_int), value :: nbytes
        logical(c_bool), value :: dynamic
    end function
    subroutine rl_update_vertex_buffer(id, buf, nbytes, offset) bind(C, name="rlUpdateVertexBuffer")
        import :: c_int, c_ptr
        integer(c_int), value :: id, nbytes, offset
        type(c_ptr), value :: buf
    end subroutine
    subroutine rl_unload_vertex_array(id) bind(C, name="rlUnloadVertexArray")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    subroutine rl_unload_vertex_buffer(id) bind(C, name="rlUnloadVertexBuffer")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    logical(c_bool) function rl_enable_vertex_array(id) bind(C, name="rlEnableVertexArray")
        import :: c_int, c_bool
        integer(c_int), value :: id
    end function
    subroutine rl_disable_vertex_array() bind(C, name="rlDisableVertexArray")
    end subroutine
    subroutine rl_enable_vertex_buffer(id) bind(C, name="rlEnableVertexBuffer")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    subroutine rl_set_vertex_attribute(idx, comps, gltype, normalized, stride, offset) &
        bind(C, name="rlSetVertexAttribute")
        import :: c_int, c_bool
        integer(c_int), value :: idx, comps, gltype, stride, offset
        logical(c_bool), value :: normalized
    end subroutine
    subroutine rl_enable_vertex_attribute(idx) bind(C, name="rlEnableVertexAttribute")
        import :: c_int
        integer(c_int), value :: idx
    end subroutine
    subroutine rl_set_vertex_attribute_divisor(idx, divisor) bind(C, name="rlSetVertexAttributeDivisor")
        import :: c_int
        integer(c_int), value :: idx, divisor
    end subroutine
    subroutine rl_draw_vertex_array_instanced(offset, n, instances) &
        bind(C, name="rlDrawVertexArrayInstanced")
        import :: c_int
        integer(c_int), value :: offset, n, instances
    end subroutine
    integer(c_int) function rl_load_texture(data, w, h, fmt, mips) bind(C, name="rlLoadTexture")
        import :: c_int, c_ptr
        type(c_ptr), value :: data
        integer(c_int), value :: w, h, fmt, mips
    end function
    subroutine rl_update_texture(id, ox, oy, w, h, fmt, data) bind(C, name="rlUpdateTexture")
        import :: c_int, c_ptr
        integer(c_int), value :: id, ox, oy, w, h, fmt
        type(c_ptr), value :: data
    end subroutine
    subroutine rl_unload_texture(id) bind(C, name="rlUnloadTexture")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    subroutine rl_active_texture_slot(slot) bind(C, name="rlActiveTextureSlot")
        import :: c_int
        integer(c_int), value :: slot
    end subroutine
    subroutine rl_enable_texture(id) bind(C, name="rlEnableTexture")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    subroutine rl_disable_texture() bind(C, name="rlDisableTexture")
    end subroutine
    subroutine rl_enable_backface_culling() bind(C, name="rlEnableBackfaceCulling")
    end subroutine
    subroutine rl_disable_backface_culling() bind(C, name="rlDisableBackfaceCulling")
    end subroutine
end interface
#endif

type, extends(ui_backend_t), public :: raylib_backend_t
    !! Raylib/rlgl bootstrap backend. Only usable when built with ENABLE_GUI.
contains
    procedure :: name => rl_name
    procedure :: init => rl_backend_init
    procedure :: shutdown => rl_backend_shutdown
    procedure :: poll => rl_backend_poll
    procedure :: present => rl_backend_present
    procedure :: should_close => rl_backend_should_close
    procedure :: install_text_metrics => rl_backend_metrics
    procedure :: capabilities => rl_caps
end type raylib_backend_t

public :: raylib_is_available

contains

function rl_name(self) result(name)
    class(raylib_backend_t), intent(in) :: self
    character(len=:), allocatable :: name
    name = "gui"
    if (.false.) name = merge("gui", "gui", same_type_as(self, self))
end function rl_name

logical function rl_backend_init(self, width, height, title, target_fps, vsync)
    class(raylib_backend_t), intent(inout) :: self
    integer, intent(in) :: width, height, target_fps
    character(*), intent(in) :: title
    logical, intent(in) :: vsync
    rl_backend_init = gui_init(width, height, title, target_fps, vsync)
    if (.false.) print *, same_type_as(self, self)
end function rl_backend_init

subroutine rl_backend_shutdown(self)
    class(raylib_backend_t), intent(inout) :: self
    call gui_shutdown()
    if (.false.) print *, same_type_as(self, self)
end subroutine rl_backend_shutdown

subroutine rl_backend_poll(self, input, width, height, scale, timeout_ms)
    !! Raylib waits for events inside presentation (see present), not here.
    class(raylib_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    integer, intent(inout) :: width, height
    real, intent(inout) :: scale
    integer, intent(in), optional :: timeout_ms
    call gui_poll(input, width, height, scale)
    if (.false.) print *, same_type_as(self, self), present(timeout_ms)
end subroutine rl_backend_poll

subroutine rl_backend_present(self, frame, store, wait_for_events)
    class(raylib_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(inout), target :: store
    logical, intent(in) :: wait_for_events
    call gui_render_frame(frame, store, wait_for_events)
    if (.false.) print *, same_type_as(self, self)
end subroutine rl_backend_present

logical function rl_backend_should_close(self)
    class(raylib_backend_t), intent(in) :: self
    rl_backend_should_close = gui_should_close()
    if (.false.) print *, same_type_as(self, self)
end function rl_backend_should_close

subroutine rl_backend_metrics(self)
    !! Advances measured from the font actually drawn (bundled DejaVu Sans
    !! subset or the configured override).
    class(raylib_backend_t), intent(inout) :: self
#ifdef ENABLE_GUI
    if (active) then
        call install_metrics()
        return
    end if
#endif
    call text_use_fixed_metrics()
    if (.false.) print *, same_type_as(self, self)
end subroutine rl_backend_metrics

function rl_caps(self) result(caps)
    class(raylib_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
#ifdef ENABLE_GUI
    caps%graphical = .true.
    caps%canvas_layers = .true.
    caps%proportional_text = .true.
    caps%event_waiting = .true.
    caps%high_dpi = .true.
    caps%pointer = .true.
    caps%text_entry = .true.
#endif
    if (.false.) caps%graphical = same_type_as(self, self)
end function rl_caps

logical function raylib_is_available()
    raylib_is_available = gui_is_available()
end function raylib_is_available

logical function gui_init(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height, target_fps
    character(*), intent(in) :: title
    logical, intent(in) :: vsync
#ifdef ENABLE_GUI
    integer(c_int) :: flags

    flags = ior(RL_FLAG_RESIZABLE, RL_FLAG_HIGHDPI)
    if (vsync) flags = ior(flags, RL_FLAG_VSYNC)
    call rl_set_config_flags(flags)
    call rl_init_window(int(width, c_int), int(height, c_int), cstr(title))
    call rl_set_target_fps(int(max(0, target_fps), c_int))
    call rl_set_exit_key(0_c_int)
    active = .true.
    call update_dpr()
    call build_codepoints()
    call load_shaders()
    gui_init = .true.
#else
    gui_init = .false.
    if (.false.) gui_init = width + height + target_fps + len(title) > 0 .and. vsync
#endif
end function gui_init

subroutine gui_shutdown()
#ifdef ENABLE_GUI
    integer :: i, s

    if (.not. active) return
    if (allocated(gpu)) then
        do i = 1, size(gpu)
            call free_gpu(gpu(i))
        end do
        deallocate(gpu)
    end if
    do s = 1, 2
        do i = 1, N_LADDER
            if (font_loaded(i, s)) call rl_unload_font(fonts(i, s))
            font_loaded(i, s) = .false.
        end do
    end do
    if (points_shader > 0) call rl_unload_shader_program(points_shader)
    if (lines_shader > 0) call rl_unload_shader_program(lines_shader)
    if (quad_points > 0) call rl_unload_vertex_buffer(quad_points)
    if (quad_lines > 0) call rl_unload_vertex_buffer(quad_lines)
    points_shader = 0
    lines_shader = 0
    quad_points = 0
    quad_lines = 0
    call rl_close_window()
    active = .false.
#endif
end subroutine gui_shutdown

subroutine gui_poll(input, width, height, scale)
    !! Read raylib input into the normalized snapshot; logical window size/scale.
    type(input_state_t), intent(inout) :: input
    integer, intent(inout) :: width, height
    real, intent(inout) :: scale
#ifdef ENABLE_GUI
    integer :: key, cp
    real(c_float) :: wheel
    integer, parameter :: repeat_keys(6) = [259, 261, 262, 263, 264, 265]
    integer :: k

    if (.not. active) return
    width = max(1, int(rl_get_screen_width()))
    height = max(1, int(rl_get_screen_height()))
    call update_dpr()
    scale = dpr
    input%resized = logical(rl_is_window_resized())
    call input_set_time(input, real(rl_get_time(), kind(1.0d0)))
    call input_update_pointer(input, real(rl_get_mouse_x()), real(rl_get_mouse_y()), &
        logical(rl_is_mouse_button_down(RL_MOUSE_LEFT)), &
        logical(rl_is_mouse_button_pressed(RL_MOUSE_LEFT)))

    wheel = rl_get_mouse_wheel_move()
    if (abs(wheel) > 0.0_c_float) call input_scroll(input, &
        nint(sign(1.0, real(wheel))), real(wheel))

    do
        key = int(rl_get_key_pressed())
        if (key == 0) exit
        call input_set_key(input, map_key(key), key)
    end do
    do k = 1, size(repeat_keys)
        if (rl_is_key_pressed_repeat(int(repeat_keys(k), c_int))) &
            call input_set_key(input, map_key(repeat_keys(k)), repeat_keys(k))
    end do
    do
        cp = int(rl_get_char_pressed())
        if (cp == 0) exit
        call input_type_text(input, utf8_encode(cp))
    end do
#else
    if (.false.) then
        width = 0
        height = 0
        scale = 1.0
        input%resized = .false.
    end if
#endif
end subroutine gui_poll

subroutine gui_render_frame(frame, store, wait_for_events)
    !! Draw a semantic frame. `wait_for_events` selects idle waiting for the
    !! event poll that raylib performs at the end of this presentation.
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(inout), target :: store
    logical, intent(in) :: wait_for_events
#ifdef ENABLE_GUI
    integer :: i

    if (.not. active) return
    call release_stale(store)
    call rl_begin_drawing()
    call rl_clear_background(color(30, 30, 30, 255))
    do i = 1, frame%count
        call draw_node(frame, store, frame%nodes(i))
    end do
    if (wait_for_events) then
        call rl_enable_event_waiting()
    else
        call rl_disable_event_waiting()
    end if
    call rl_end_drawing()
#else
    if (.false.) then
        if (wait_for_events .and. frame%count > 0) store%vertex_uploads = 0
    end if
#endif
end subroutine gui_render_frame

logical function gui_is_available()
#ifdef ENABLE_GUI
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        gui_is_available = .false.
        return
    end if
#ifdef __linux__
    call get_environment_variable("DISPLAY", value, status=status)
    if (status == 0 .and. len_trim(value) > 0) then
        gui_is_available = .true.
        return
    end if
    call get_environment_variable("WAYLAND_DISPLAY", value, status=status)
    gui_is_available = status == 0 .and. len_trim(value) > 0
#else
    gui_is_available = .true.
#endif
#else
    gui_is_available = .false.
#endif
end function gui_is_available

logical function gui_should_close()
#ifdef ENABLE_GUI
    gui_should_close = .not. active .or. logical(rl_window_should_close())
#else
    gui_should_close = .true.
#endif
end function gui_should_close

#ifdef ENABLE_GUI
subroutine update_dpr()
    integer :: sw
    sw = int(rl_get_screen_width())
    dpr = 1.0
    if (sw > 0) dpr = max(1.0, real(rl_get_render_width()) / real(sw))
end subroutine update_dpr

function cstr(s) result(out)
    character(*), intent(in) :: s
    character(len=:, kind=c_char), allocatable :: out
    out = s // c_null_char
end function cstr

subroutine build_codepoints()
    integer, parameter :: ranges(2, 8) = reshape([32, 126, 160, 383, 880, 1023, &
        8192, 8303, 8364, 8364, 8592, 8703, 8704, 8959, 65533, 65533], [2, 8])
    integer :: r, c, n

    n = sum(ranges(2, :) - ranges(1, :) + 1)
    if (allocated(codepoints)) deallocate(codepoints)
    allocate(codepoints(n))
    n = 0
    do r = 1, size(ranges, 2)
        do c = ranges(1, r), ranges(2, r)
            n = n + 1
            codepoints(n) = int(c, c_int)
        end do
    end do
end subroutine build_codepoints

function load_font(pixels, style) result(f)
    integer, intent(in) :: pixels, style
    type(rl_font) :: f
    character(len=:), allocatable :: path
    integer(c_int) :: nbytes
    type(c_ptr) :: data

    path = text_font_file(style)
    if (len(path) > 0) then
        if (rl_file_exists(cstr(path))) then
            f = rl_load_font_ex(cstr(path), int(pixels, c_int), c_loc(codepoints), &
                int(size(codepoints), c_int))
            if (f%glyph_count > 0) then
                call rl_set_texture_filter(f%texture, TEX_FILTER_BILINEAR)
                return
            end if
        end if
        call report_warning("fortui_gui_raylib", "load_font", &
            "cannot load font '" // path // "'; using bundled DejaVu Sans")
    end if
    data = fortui_font_data(int(style, c_int), nbytes)
    f = rl_load_font_mem(cstr(".ttf"), data, nbytes, int(pixels, c_int), &
        c_loc(codepoints), int(size(codepoints), c_int))
    call rl_set_texture_filter(f%texture, TEX_FILTER_BILINEAR)
end function load_font

integer function ladder_index(size) result(k)
    real, intent(in) :: size
    real :: px

    px = size * dpr
    do k = 1, N_LADDER
        if (LADDER(k) >= px - 0.5) return
    end do
    k = N_LADDER
end function ladder_index

function get_font(size, style) result(f)
    real, intent(in) :: size
    integer, intent(in) :: style
    type(rl_font) :: f
    integer :: k, s

    s = max(1, min(2, style))
    k = ladder_index(size)
    if (.not. font_loaded(k, s)) then
        fonts(k, s) = load_font(nint(LADDER(k)), s)
        font_loaded(k, s) = .true.
    end if
    f = fonts(k, s)
end function get_font

subroutine install_metrics()
    !! Measure per-code-point advances (per unit size) for layout and wrapping.
    real, allocatable :: table(:, :)
    real :: fallback(2), ref
    type(rl_font) :: f
    type(rl_vector2) :: v
    integer :: s, i, k

    k = N_LADDER - 1
    ref = LADDER(k)
    allocate(table(0:TEXT_MAX_CODEPOINT, 2))
    do s = 1, 2
        if (.not. font_loaded(k, s)) then
            fonts(k, s) = load_font(nint(ref), s)
            font_loaded(k, s) = .true.
        end if
        f = fonts(k, s)
        v = rl_measure_text_ex(f, cstr("?"), real(ref, c_float), 0.0_c_float)
        fallback(s) = real(v%x) / ref
        table(:, s) = fallback(s)
        do i = 1, size(codepoints)
            if (codepoints(i) > TEXT_MAX_CODEPOINT) cycle
            v = rl_measure_text_ex(f, cstr(utf8_encode(int(codepoints(i)))), &
                real(ref, c_float), 0.0_c_float)
            table(codepoints(i), s) = real(v%x) / ref
        end do
    end do
    call text_set_metrics(table, fallback, 1.25)
end subroutine install_metrics

subroutine draw_utf8(s, x, y, size, style, c)
    character(*), intent(in) :: s
    real, intent(in) :: x, y, size
    integer, intent(in) :: style
    type(rl_color), intent(in) :: c

    if (len(s) == 0) return
    call rl_draw_text_ex(get_font(size, style), cstr(s), &
        rl_vector2(real(x, c_float), real(y, c_float)), real(size, c_float), &
        0.0_c_float, c)
end subroutine draw_utf8

subroutine load_shaders()
    character(len=*), parameter :: nl = achar(10)
    character(len=*), parameter :: head = "#version 330" // nl // &
        "uniform vec4 u_frame;" // nl // "uniform vec4 u_view;" // nl // &
        "uniform vec4 u_style;" // nl
    character(len=*), parameter :: to_ndc = &
        "    gl_Position = vec4(2.0 * p.x / u_frame.z - 1.0, " // &
        "1.0 - 2.0 * p.y / u_frame.w, 0.0, 1.0);" // nl
    character(len=:), allocatable :: pvs, pfs, lvs, lfs
    real(c_float), target :: quad_p(12), quad_l(12)

    pvs = head // &
        "layout(location = 0) in vec2 a_corner;" // nl // &
        "layout(location = 1) in vec2 a_pos;" // nl // &
        "layout(location = 2) in float a_size;" // nl // &
        "layout(location = 3) in vec4 a_color;" // nl // &
        "out vec2 v_local; out vec4 v_color; out float v_radius;" // nl // &
        "void main() {" // nl // &
        "    float r = max(0.5 * a_size * u_style.x, 0.5 * u_style.y);" // nl // &
        "    float pad = r + 1.0 / u_view.w;" // nl // &
        "    vec2 c = u_frame.xy + a_pos * u_view.x + u_view.yz;" // nl // &
        "    vec2 p = c + a_corner * pad;" // nl // &
        "    v_local = a_corner * pad; v_radius = r; v_color = a_color;" // nl // &
        to_ndc // "}" // nl
    pfs = head // &
        "in vec2 v_local; in vec4 v_color; in float v_radius;" // nl // &
        "out vec4 frag;" // nl // &
        "void main() {" // nl // &
        "    float a = clamp((v_radius - length(v_local)) * u_view.w + 0.5, 0.0, 1.0);" // nl // &
        "    if (a <= 0.0) discard;" // nl // &
        "    frag = vec4(v_color.rgb, v_color.a * a);" // nl // "}" // nl
    lvs = head // &
        "layout(location = 0) in vec2 a_corner;" // nl // &
        "layout(location = 1) in vec2 a_seg;" // nl // &
        "uniform sampler2D u_pos; uniform sampler2D u_col;" // nl // &
        "out vec4 v_color; out float v_across; out float v_half;" // nl // &
        "ivec2 texel(float i) { int k = int(i + 0.5); return ivec2(k % 2048, k / 2048); }" // nl // &
        "void main() {" // nl // &
        "    ivec2 ta = texel(a_seg.x); ivec2 tb = texel(a_seg.y);" // nl // &
        "    vec2 sa = u_frame.xy + texelFetch(u_pos, ta, 0).xy * u_view.x + u_view.yz;" // nl // &
        "    vec2 sb = u_frame.xy + texelFetch(u_pos, tb, 0).xy * u_view.x + u_view.yz;" // nl // &
        "    vec2 d = sb - sa; float len = length(d);" // nl // &
        "    vec2 dir = len > 1e-6 ? d / len : vec2(1.0, 0.0);" // nl // &
        "    vec2 n = vec2(-dir.y, dir.x);" // nl // &
        "    float hw = u_style.x + 1.0 / u_view.w;" // nl // &
        "    vec2 p = mix(sa, sb, a_corner.x) + n * (a_corner.y * hw);" // nl // &
        "    v_across = a_corner.y * hw; v_half = u_style.x;" // nl // &
        "    v_color = mix(texelFetch(u_col, ta, 0), texelFetch(u_col, tb, 0), a_corner.x);" // nl // &
        to_ndc // "}" // nl
    lfs = head // &
        "in vec4 v_color; in float v_across; in float v_half;" // nl // &
        "out vec4 frag;" // nl // &
        "void main() {" // nl // &
        "    float a = clamp((v_half - abs(v_across)) * u_view.w + 0.5, 0.0, 1.0);" // nl // &
        "    if (a <= 0.0) discard;" // nl // &
        "    frag = vec4(v_color.rgb, v_color.a * a);" // nl // "}" // nl

    points_shader = rl_load_shader_program(cstr(pvs), cstr(pfs))
    lines_shader = rl_load_shader_program(cstr(lvs), cstr(lfs))
    if (points_shader == 0 .or. lines_shader == 0) then
        call report_error("fortui_gui_raylib", "load_shaders", &
            "canvas shaders failed to compile; canvas layers will not be drawn")
        shader_error_reported = .true.
    end if
    loc_p_frame = rl_get_location_uniform(points_shader, cstr("u_frame"))
    loc_p_view = rl_get_location_uniform(points_shader, cstr("u_view"))
    loc_p_style = rl_get_location_uniform(points_shader, cstr("u_style"))
    loc_l_frame = rl_get_location_uniform(lines_shader, cstr("u_frame"))
    loc_l_view = rl_get_location_uniform(lines_shader, cstr("u_view"))
    loc_l_style = rl_get_location_uniform(lines_shader, cstr("u_style"))
    loc_l_pos = rl_get_location_uniform(lines_shader, cstr("u_pos"))
    loc_l_col = rl_get_location_uniform(lines_shader, cstr("u_col"))

    quad_p = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0]
    quad_l = [0.0, -1.0, 1.0, -1.0, 1.0, 1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0]
    quad_points = rl_load_vertex_buffer(c_loc(quad_p), 48_c_int, .false._c_bool)
    quad_lines = rl_load_vertex_buffer(c_loc(quad_l), 48_c_int, .false._c_bool)
end subroutine load_shaders

subroutine free_gpu(g)
    type(gpu_layer_t), intent(inout) :: g

    if (g%vao /= 0) call rl_unload_vertex_array(g%vao)
    if (g%vbo_pos /= 0) call rl_unload_vertex_buffer(g%vbo_pos)
    if (g%vbo_size /= 0) call rl_unload_vertex_buffer(g%vbo_size)
    if (g%vbo_col /= 0) call rl_unload_vertex_buffer(g%vbo_col)
    if (g%vbo_seg /= 0) call rl_unload_vertex_buffer(g%vbo_seg)
    if (g%tex_pos /= 0) call rl_unload_texture(g%tex_pos)
    if (g%tex_col /= 0) call rl_unload_texture(g%tex_col)
    g = gpu_layer_t()
end subroutine free_gpu

subroutine release_stale(store)
    !! Free GPU resources whose store slot was released or reassigned.
    type(canvas_store_t), intent(in) :: store
    type(gpu_layer_t), allocatable :: grown(:)
    integer :: i, n

    n = 0
    if (allocated(store%layers)) n = size(store%layers)
    if (.not. allocated(gpu)) allocate(gpu(max(n, 8)))
    if (size(gpu) < n) then
        allocate(grown(n))
        grown(1:size(gpu)) = gpu
        call move_alloc(grown, gpu)
    end if
    do i = 1, size(gpu)
        if (gpu(i)%serial == 0) cycle
        if (i > n) then
            call free_gpu(gpu(i))
        else if (.not. store%layers(i)%in_use .or. &
            store%layers(i)%serial /= gpu(i)%serial) then
            call free_gpu(gpu(i))
        end if
    end do
end subroutine release_stale

subroutine attribute(idx, comps, gltype, normalized, divisor)
    integer, intent(in) :: idx, comps, divisor
    integer(c_int), intent(in) :: gltype
    logical, intent(in) :: normalized

    call rl_set_vertex_attribute(int(idx, c_int), int(comps, c_int), gltype, &
        logical(normalized, c_bool), 0_c_int, 0_c_int)
    call rl_enable_vertex_attribute(int(idx, c_int))
    call rl_set_vertex_attribute_divisor(int(idx, c_int), int(divisor, c_int))
end subroutine attribute

subroutine realize_points(store, slot)
    type(canvas_store_t), intent(inout), target :: store
    integer, intent(in) :: slot
    type(canvas_layer_t), pointer :: l
    logical :: fresh, vertices, indices, ok
    integer :: n, cap

    l => store%layers(slot)
    n = l%vertex_count
    fresh = gpu(slot)%serial /= l%serial .or. n > gpu(slot)%capacity
    if (fresh) then
        call free_gpu(gpu(slot))
        cap = max(16, n + n / 4)
        gpu(slot)%serial = l%serial
        gpu(slot)%kind = LAYER_POINTS
        gpu(slot)%capacity = cap
        gpu(slot)%vao = rl_load_vertex_array()
        ok = rl_enable_vertex_array(gpu(slot)%vao)
        call rl_enable_vertex_buffer(quad_points)
        call attribute(0, 2, RL_FLOAT, .false., 0)
        gpu(slot)%vbo_pos = rl_load_vertex_buffer(c_null_ptr, int(8 * cap, c_int), .true._c_bool)
        call attribute(1, 2, RL_FLOAT, .false., 1)
        gpu(slot)%vbo_size = rl_load_vertex_buffer(c_null_ptr, int(4 * cap, c_int), .true._c_bool)
        call attribute(2, 1, RL_FLOAT, .false., 1)
        gpu(slot)%vbo_col = rl_load_vertex_buffer(c_null_ptr, int(4 * cap, c_int), .true._c_bool)
        call attribute(3, 4, RL_UNSIGNED_BYTE, .true., 1)
        call rl_disable_vertex_array()
    end if
    call store%realize(slot, fresh, vertices, indices)
    if (vertices .and. n > 0) then
        call rl_update_vertex_buffer(gpu(slot)%vbo_pos, c_loc(l%xy), int(8 * n, c_int), 0_c_int)
        call rl_update_vertex_buffer(gpu(slot)%vbo_size, c_loc(l%sizes), int(4 * n, c_int), 0_c_int)
        call rl_update_vertex_buffer(gpu(slot)%vbo_col, c_loc(l%rgba), int(4 * n, c_int), 0_c_int)
    end if
end subroutine realize_points

subroutine realize_lines(store, slot)
    type(canvas_store_t), intent(inout), target :: store
    integer, intent(in) :: slot
    type(canvas_layer_t), pointer :: l
    logical :: fresh, vertices, indices, ok
    integer :: n, ns, rows, cap, i

    l => store%layers(slot)
    n = l%vertex_count
    ns = l%index_count / 2
    rows = max(1, (n + TEX_WIDTH - 1) / TEX_WIDTH)
    fresh = gpu(slot)%serial /= l%serial .or. rows > gpu(slot)%tex_rows .or. &
        ns > gpu(slot)%seg_capacity
    if (fresh) then
        call free_gpu(gpu(slot))
        gpu(slot)%serial = l%serial
        gpu(slot)%kind = LAYER_LINES
        gpu(slot)%tex_rows = rows + rows / 4
        call ensure_scratch(TEX_WIDTH * gpu(slot)%tex_rows)
        scratch_f(1:4 * TEX_WIDTH * gpu(slot)%tex_rows) = 0.0
        scratch_i(1:TEX_WIDTH * gpu(slot)%tex_rows) = 0
        gpu(slot)%tex_pos = rl_load_texture(c_loc(scratch_f), int(TEX_WIDTH, c_int), &
            int(gpu(slot)%tex_rows, c_int), RL_PIXEL_RGBA32F, 1_c_int)
        gpu(slot)%tex_col = rl_load_texture(c_loc(scratch_i), int(TEX_WIDTH, c_int), &
            int(gpu(slot)%tex_rows, c_int), RL_PIXEL_RGBA8, 1_c_int)
        cap = max(16, ns + ns / 4)
        gpu(slot)%seg_capacity = cap
        gpu(slot)%vao = rl_load_vertex_array()
        ok = rl_enable_vertex_array(gpu(slot)%vao)
        call rl_enable_vertex_buffer(quad_lines)
        call attribute(0, 2, RL_FLOAT, .false., 0)
        gpu(slot)%vbo_seg = rl_load_vertex_buffer(c_null_ptr, int(8 * cap, c_int), .true._c_bool)
        call attribute(1, 2, RL_FLOAT, .false., 1)
        call rl_disable_vertex_array()
    end if
    call store%realize(slot, fresh, vertices, indices)
    if (vertices .and. n > 0) then
        rows = (n + TEX_WIDTH - 1) / TEX_WIDTH
        call ensure_scratch(TEX_WIDTH * rows)
        do i = 1, n
            scratch_f(4 * i - 3) = l%xy(1, i)
            scratch_f(4 * i - 2) = l%xy(2, i)
            scratch_f(4 * i - 1) = 0.0
            scratch_f(4 * i) = 0.0
        end do
        scratch_i(1:n) = l%rgba(1:n)
        call rl_update_texture(gpu(slot)%tex_pos, 0_c_int, 0_c_int, int(TEX_WIDTH, c_int), &
            int(rows, c_int), RL_PIXEL_RGBA32F, c_loc(scratch_f))
        call rl_update_texture(gpu(slot)%tex_col, 0_c_int, 0_c_int, int(TEX_WIDTH, c_int), &
            int(rows, c_int), RL_PIXEL_RGBA8, c_loc(scratch_i))
    end if
    if (indices) then
        gpu(slot)%segments = ns
        if (ns > 0) then
            call ensure_scratch(ns)
            do i = 1, 2 * ns
                scratch_f(i) = real(l%indices(i))
            end do
            call rl_update_vertex_buffer(gpu(slot)%vbo_seg, c_loc(scratch_f), &
                int(8 * ns, c_int), 0_c_int)
        end if
    end if
end subroutine realize_lines

subroutine ensure_scratch(texels)
    integer, intent(in) :: texels
    if (allocated(scratch_f)) then
        if (size(scratch_f) >= 4 * texels) then
            if (size(scratch_i) >= texels) return
        end if
        deallocate(scratch_f, scratch_i)
    end if
    allocate(scratch_f(4 * texels), scratch_i(texels))
end subroutine ensure_scratch

subroutine set_vec4(loc, a, b, c, d)
    integer(c_int), intent(in) :: loc
    real, intent(in) :: a, b, c, d
    real(c_float), target :: v(4)
    v = [a, b, c, d]
    call rl_set_uniform(loc, c_loc(v), RL_UNIFORM_VEC4, 1_c_int)
end subroutine set_vec4

subroutine set_int(loc, value)
    integer(c_int), intent(in) :: loc
    integer, intent(in) :: value
    integer(c_int), target :: v
    v = int(value, c_int)
    call rl_set_uniform(loc, c_loc(v), RL_UNIFORM_INT, 1_c_int)
end subroutine set_int

subroutine draw_canvas(frame, store, node)
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(inout), target :: store
    type(ui_node_t), intent(in) :: node
    type(ui_layer_ref_t) :: ref
    real :: sw, sh, scale, sx, sy, w
    integer :: j, slot
    logical :: ok
    sw = real(rl_get_screen_width())
    sh = real(rl_get_screen_height())
    call rl_begin_scissor(nint(node%x), nint(node%y), max(1, nint(node%width)), &
        max(1, nint(node%height)))
    if (node%fill /= 0) call rl_draw_rectangle(nint(node%x), nint(node%y), &
        nint(node%width), nint(node%height), unpack_rgba(node%fill))
    call rl_draw_render_batch_active()
    ! Screen-space quads are emitted with y pointing down; winding is irrelevant.
    call rl_disable_backface_culling()
    do j = node%layer_first, node%layer_first + node%layer_count - 1
        ref = frame%layers(j)
        slot = ref%slot
        if (points_shader == 0 .or. lines_shader == 0) cycle
        if (ref%kind == LAYER_POINTS) then
            call realize_points(store, slot)
            if (ref%vertex_count == 0) cycle
            associate(l => store%layers(slot))
                scale = 1.0
                if (l%world_size) scale = node%canvas_view%zoom
                call rl_enable_shader(points_shader)
                call set_vec4(loc_p_frame, node%x, node%y, sw, sh)
                call set_vec4(loc_p_view, node%canvas_view%zoom, node%canvas_view%pan_x, &
                    node%canvas_view%pan_y, dpr)
                call set_vec4(loc_p_style, scale, l%min_pixels, 0.0, 0.0)
            end associate
            ok = rl_enable_vertex_array(gpu(slot)%vao)
            call rl_draw_vertex_array_instanced(0_c_int, 6_c_int, int(ref%vertex_count, c_int))
            call rl_disable_vertex_array()
            call rl_disable_shader()
        else if (ref%kind == LAYER_LINES) then
            call realize_lines(store, slot)
            if (gpu(slot)%segments == 0) cycle
            call rl_enable_shader(lines_shader)
            call set_vec4(loc_l_frame, node%x, node%y, sw, sh)
            call set_vec4(loc_l_view, node%canvas_view%zoom, node%canvas_view%pan_x, &
                node%canvas_view%pan_y, dpr)
            call set_vec4(loc_l_style, 0.5 * store%layers(slot)%line_width, 0.0, 0.0, 0.0)
            call rl_active_texture_slot(1_c_int)
            call rl_enable_texture(gpu(slot)%tex_pos)
            call set_int(loc_l_pos, 1)
            call rl_active_texture_slot(2_c_int)
            call rl_enable_texture(gpu(slot)%tex_col)
            call set_int(loc_l_col, 2)
            ok = rl_enable_vertex_array(gpu(slot)%vao)
            call rl_draw_vertex_array_instanced(0_c_int, 6_c_int, int(gpu(slot)%segments, c_int))
            call rl_disable_vertex_array()
            call rl_disable_texture()
            call rl_active_texture_slot(1_c_int)
            call rl_disable_texture()
            call rl_active_texture_slot(0_c_int)
            call rl_disable_shader()
        end if
    end do
    call rl_enable_backface_culling()
    do j = node%label_first, node%label_first + node%label_count - 1
        associate(lab => frame%labels(j))
            sx = node%x + lab%x * node%canvas_view%zoom + node%canvas_view%pan_x
            sy = node%y + lab%y * node%canvas_view%zoom + node%canvas_view%pan_y
            w = text_width(lab%text, lab%size)
            call draw_utf8(lab%text, sx - 0.5 * w, sy + 2.0, lab%size, &
                TEXT_STYLE_REGULAR, unpack_rgba(lab%rgba))
        end associate
    end do
    call rl_end_scissor()
end subroutine draw_canvas

subroutine draw_scroll_text(node, fg)
    type(ui_node_t), intent(in) :: node
    type(rl_color), intent(in) :: fg
    integer :: i, x, y, w, h, thumb_h, thumb_y
    real :: top, ly, lh, total, max_scroll

    x = nint(node%x)
    y = nint(node%y)
    w = max(1, nint(node%width))
    h = max(1, nint(node%height))
    call rl_draw_rectangle(x, y, w, h, color(24, 24, 27, 255))
    call rl_begin_scissor(x, y, w, h)
    top = node%y + SCROLL_PADDING - node%scroll
    do i = 1, node%line_count
        associate(line => node%lines(i))
            lh = text_line_height(line%size)
            ly = top + line%y
            if (ly + lh < node%y) cycle
            if (ly > node%y + node%height) exit
            if (line%last >= line%first) call draw_utf8(node%body(line%first:line%last), &
                node%x + SCROLL_PADDING, ly + 0.5 * (lh - line%size), line%size, &
                line%style, fg)
        end associate
    end do
    call rl_end_scissor()
    total = node%content_height + 2.0 * SCROLL_PADDING
    if (total > node%height) then
        max_scroll = total - node%height
        thumb_h = max(20, nint(node%height * node%height / total))
        thumb_y = y + nint(node%scroll / max_scroll * real(h - thumb_h))
        call rl_draw_rectangle(x + w - nint(SCROLLBAR_WIDTH), y, nint(SCROLLBAR_WIDTH), h, &
            color(40, 40, 44, 255))
        call rl_draw_rectangle(x + w - nint(SCROLLBAR_WIDTH) + 2, thumb_y, &
            nint(SCROLLBAR_WIDTH) - 4, thumb_h, color(110, 110, 120, 255))
    end if
end subroutine draw_scroll_text

subroutine draw_text_input(node, fg)
    type(ui_node_t), intent(in) :: node
    type(rl_color), intent(in) :: fg
    integer :: x, y, w, h
    real :: tx, caret_x, shift, ty

    x = nint(node%x)
    y = nint(node%y)
    w = max(1, nint(node%width))
    h = max(1, nint(node%height))
    call rl_draw_rectangle(x, y, w, h, color(20, 20, 22, 255))
    if (node%focused) then
        call draw_border(x, y, w, h, color(255, 220, 90, 255))
    else
        call draw_border(x, y, w, h, color(90, 90, 100, 255))
    end if
    call rl_begin_scissor(x + 1, y + 1, max(1, w - 2), max(1, h - 2))
    tx = node%x + INPUT_PADDING
    ty = node%y + 0.5 * (node%height - node%text_size)
    caret_x = 0.0
    if (node%caret > 0) caret_x = text_width(node%body(1:node%caret), node%text_size)
    shift = max(0.0, caret_x - (node%width - 2.0 * INPUT_PADDING))
    if (len(node%body) == 0) then
        if (.not. node%focused) call draw_utf8(trim(node%text), tx, ty, node%text_size, &
            TEXT_STYLE_REGULAR, color(120, 120, 130, 255))
    else
        call draw_utf8(node%body, tx - shift, ty, node%text_size, TEXT_STYLE_REGULAR, fg)
    end if
    if (node%focused) call rl_draw_rectangle(nint(tx - shift + caret_x), y + 6, 2, &
        max(1, h - 12), color(255, 220, 90, 255))
    call rl_end_scissor()
end subroutine draw_text_input

subroutine draw_node(frame, store, node)
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(inout), target :: store
    type(ui_node_t), intent(in) :: node
    type(rl_color) :: fg, fill
    integer :: x, y, w, h, knob
    real :: fraction, ty

    x = nint(node%x)
    y = nint(node%y)
    w = max(1, nint(node%width))
    h = max(1, nint(node%height))

    fg = color(235, 235, 235, 255)
    fill = color(55, 75, 105, 255)
    if (node%disabled) then
        fg = color(120, 120, 120, 255)
        fill = color(50, 50, 50, 255)
    else if (node%active) then
        fill = color(95, 125, 170, 255)
    else if (node%hovered) then
        fill = color(70, 95, 130, 255)
    end if
    ty = node%y + 0.5 * (node%height - node%text_size)

    select case (node%kind)
    case (UI_TEXT)
        if (node%focused) fg = color(255, 220, 90, 255)
        call draw_utf8(trim(node%text), node%x, ty, node%text_size, TEXT_STYLE_REGULAR, fg)
    case (UI_BUTTON)
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(x, y, w, h, fill)
        call draw_utf8(trim(node%text), node%x + 12.0, ty, node%text_size, &
            TEXT_STYLE_REGULAR, fg)
    case (UI_CHECKBOX)
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(x, y + (h - 20) / 2, 20, 20, fill)
        if (node%checked) call rl_draw_rectangle(x + 5, y + (h - 20) / 2 + 5, 10, 10, &
            color(120, 230, 140, 255))
        if (len_trim(node%text) > 0) call draw_utf8(trim(node%text), node%x + 30.0, ty, &
            node%text_size, TEXT_STYLE_REGULAR, fg)
    case (UI_SLIDER)
        call rl_draw_rectangle(x, y + h / 2 - 2, w, 4, color(80, 80, 80, 255))
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        knob = x + nint(fraction * real(w))
        call rl_draw_rectangle(knob - 5, y + 4, 10, max(8, h - 8), fg)
    case (UI_VIEWPORT)
        call draw_border(x, y, w, h, fg)
    case (UI_CANVAS)
        call draw_canvas(frame, store, node)
    case (UI_SCROLL_TEXT)
        call draw_scroll_text(node, fg)
    case (UI_TEXT_INPUT)
        call draw_text_input(node, fg)
    end select
end subroutine draw_node

subroutine draw_border(x, y, w, h, c)
    integer, intent(in) :: x, y, w, h
    type(rl_color), intent(in) :: c
    call rl_draw_rectangle(x, y, w, 1, c)
    call rl_draw_rectangle(x, y + h - 1, w, 1, c)
    call rl_draw_rectangle(x, y, 1, h, c)
    call rl_draw_rectangle(x + w - 1, y, 1, h, c)
end subroutine draw_border

pure function map_key(key) result(mapped)
    integer, intent(in) :: key
    integer :: mapped
    select case (key)
    case (256); mapped = KEY_ESCAPE
    case (257, 335); mapped = KEY_ENTER
    case (258); mapped = KEY_TAB
    case (32);  mapped = KEY_SPACE
    case (259); mapped = KEY_BACKSPACE
    case (261); mapped = KEY_DELETE
    case (262); mapped = KEY_ARROW_RIGHT
    case (263); mapped = KEY_ARROW_LEFT
    case (264); mapped = KEY_ARROW_DOWN
    case (265); mapped = KEY_ARROW_UP
    case (266); mapped = KEY_PAGE_UP
    case (267); mapped = KEY_PAGE_DOWN
    case (268); mapped = KEY_HOME
    case (269); mapped = KEY_END
    case default; mapped = key
    end select
end function map_key

pure function unpack_rgba(c) result(out)
    integer(int32), intent(in) :: c
    type(rl_color) :: out
    out = color(int(iand(c, 255_int32)), int(iand(ishft(c, -8), 255_int32)), &
        int(iand(ishft(c, -16), 255_int32)), int(iand(ishft(c, -24), 255_int32)))
end function unpack_rgba

pure function color(r, g, b, a) result(c)
    integer, intent(in) :: r, g, b, a
    type(rl_color) :: c
    c%r = byte(r)
    c%g = byte(g)
    c%b = byte(b)
    c%a = byte(a)
end function color

pure integer(c_int8_t) function byte(value)
    integer, intent(in) :: value
    if (value > 127) then
        byte = int(value - 256, c_int8_t)
    else
        byte = int(value, c_int8_t)
    end if
end function byte
#endif

end module fortui_gui_raylib
