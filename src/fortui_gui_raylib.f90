module fortui_gui_raylib
!! Graphical platform + renderer backend. Raylib/rlgl is a bootstrap backend, not
!! the FortUI abstraction. The backend value owns all GPU resources: fonts,
!! shaders and retained canvas buffers keyed by canvas-store slot and serial.
!! Compiled only with ENABLE_GUI (otherwise this module is empty).
!!
!! Rendering uses only raylib/rlgl APIs and GLSL 330 (OpenGL 3.3 core, also the
!! macOS core profile): one position texture per shared vertex layer, read by
!! instanced quads for points and lines; no point sprites, no wide GL lines.
!! Text uses a bundled DejaVu Sans subset unless the options `font_regular` /
!! `font_bold` (or FORTUI_FONT / FORTUI_FONT_BOLD) name TTF files:
!!
!!   call ui_init(raylib_backend_t(font_regular="/path/Inter.ttf"), 1200, 800, "app")
! Dependencies stay visible to build tools that do not preprocess (fpm scans
! sources without -D flags); everything else needs -DENABLE_GUI=1.
use iso_c_binding
use iso_fortran_env, only: int32
use fortui_frame, only: ui_frame_t, ui_node_t, ui_layer_ref_t, UI_TEXT, UI_BUTTON, UI_LINK, &
    UI_SLIDER, UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, &
    UI_CAPTION, LAYER_POINTS, LAYER_LINES, SCROLL_PADDING, SCROLLBAR_WIDTH, &
    INPUT_PADDING, CONTROL_PADDING, style_weight
use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
    input_set_key, input_type_text, input_set_time, input_has_events, KEY_NONE, &
    KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_SPACE, KEY_ARROW_UP, KEY_ARROW_DOWN, &
    KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, &
    KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_INSERT
use fortui_canvas, only: canvas_store_t
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_text, only: text_set_metrics, text_width, text_line_height, text_fit, &
    utf8_encode, TEXT_MAX_CODEPOINT, TEXT_STYLE_REGULAR
use fortui_error, only: report_error, report_warning
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
    !! GPU resources of one store slot: a position texture (vertex layers),
    !! instanced size/colour buffers (points) or a segment buffer and colour
    !! texture (lines).
    integer :: serial = 0
    integer :: kind = 0
    integer(c_int) :: vao = 0
    integer(c_int) :: vbo_size = 0, vbo_col = 0, vbo_seg = 0
    integer(c_int) :: tex = 0
    integer :: capacity = 0
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
integer, parameter :: REPEAT_KEYS(6) = [259, 261, 262, 263, 264, 265]

type, extends(ui_backend_t), public :: raylib_backend_t
    !! Raylib/rlgl backend. Options: TTF files replacing the bundled fonts.
    character(len=:), allocatable :: font_regular
    character(len=:), allocatable :: font_bold
    logical :: active = .false.
    ! raylib resets its close flag on every event poll; latch it here.
    logical :: close_requested = .false.
    real :: dpr = 1.0
    type(rl_font), allocatable :: fonts(:, :)
    logical :: font_loaded(N_LADDER, 2) = .false.
    integer(c_int), allocatable :: codepoints(:)
    integer(c_int) :: points_shader = 0, lines_shader = 0
    integer(c_int) :: loc_p_frame = -1, loc_p_view = -1, loc_p_style = -1
    integer(c_int) :: loc_p_pos = -1
    integer(c_int) :: loc_l_frame = -1, loc_l_view = -1, loc_l_style = -1
    integer(c_int) :: loc_l_pos = -1, loc_l_col = -1
    integer(c_int) :: quad_points = 0, quad_lines = 0
    type(gpu_layer_t), allocatable :: gpu(:)
    real(c_float), allocatable :: scratch_f(:)
    integer(int32), allocatable :: scratch_i(:)
contains
    procedure :: name => rl_name
    procedure :: init => rl_init
    procedure :: shutdown => rl_shutdown
    procedure :: poll => rl_poll
    procedure :: present => rl_present
    procedure :: should_close => rl_should_close
    procedure :: install_text_metrics => rl_metrics
    procedure :: capabilities => rl_caps
end type raylib_backend_t

public :: raylib_is_available

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
    logical(c_bool) function rl_is_key_pressed_repeat(key) bind(C, &
        name="IsKeyPressedRepeat")
        import :: c_int, c_bool
        integer(c_int), value :: key
    end function
    logical(c_bool) function rl_is_mouse_button_pressed(btn) bind(C, &
        name="IsMouseButtonPressed")
        import :: c_int, c_bool
        integer(c_int), value :: btn
    end function
    logical(c_bool) function rl_is_mouse_button_down(btn) bind(C, &
        name="IsMouseButtonDown")
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
    subroutine rl_wait_time(seconds) bind(C, name="WaitTime")
        import :: c_double
        real(c_double), value :: seconds
    end subroutine rl_wait_time
    subroutine rl_enable_event_waiting() bind(C, name="EnableEventWaiting")
    end subroutine
    subroutine rl_disable_event_waiting() bind(C, name="DisableEventWaiting")
    end subroutine
    subroutine rl_poll_input_events() bind(C, name="PollInputEvents")
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
    subroutine rl_draw_text_ex(f, text, pos, size, spacing, color) bind(C, &
        name="DrawTextEx")
        import :: rl_font, c_char, rl_vector2, c_float, rl_color
        type(rl_font), value :: f
        character(c_char), intent(in) :: text(*)
        type(rl_vector2), value :: pos
        real(c_float), value :: size, spacing
        type(rl_color), value :: color
    end subroutine
    function rl_measure_text_ex(f, text, size, spacing) bind(C, name="MeasureTextEx") &
        result(v)
        import :: rl_font, c_char, c_float, rl_vector2
        type(rl_font), value :: f
        character(c_char), intent(in) :: text(*)
        real(c_float), value :: size, spacing
        type(rl_vector2) :: v
    end function
    type(c_ptr) function fortui_font_data(style, nbytes) bind(C, &
        name="fortui_font_data")
        import :: c_ptr, c_int
        integer(c_int), value :: style
        integer(c_int), intent(out) :: nbytes
    end function
    ! rlgl
    subroutine rl_draw_render_batch_active() bind(C, name="rlDrawRenderBatchActive")
    end subroutine
    integer(c_int) function rl_load_shader_program(vs, fs) bind(C, &
        name="rlLoadShaderProgram")
        import :: c_int, c_char
        character(c_char), intent(in) :: vs(*), fs(*)
    end function
    subroutine rl_unload_shader_program(id) bind(C, name="rlUnloadShaderProgram")
        import :: c_int
        integer(c_int), value :: id
    end subroutine
    integer(c_int) function rl_get_location_uniform(id, name) bind(C, &
        name="rlGetLocationUniform")
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
    integer(c_int) function rl_load_vertex_buffer(buf, nbytes, dynamic) bind(C, &
        name="rlLoadVertexBuffer")
        import :: c_int, c_ptr, c_bool
        type(c_ptr), value :: buf
        integer(c_int), value :: nbytes
        logical(c_bool), value :: dynamic
    end function
    subroutine rl_update_vertex_buffer(id, buf, nbytes, offset) bind(C, &
        name="rlUpdateVertexBuffer")
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
    logical(c_bool) function rl_enable_vertex_array(id) bind(C, &
        name="rlEnableVertexArray")
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
    subroutine rl_set_vertex_attribute_divisor(idx, divisor) bind(C, &
        name="rlSetVertexAttributeDivisor")
        import :: c_int
        integer(c_int), value :: idx, divisor
    end subroutine
    subroutine rl_draw_vertex_array_instanced(offset, n, instances) &
        bind(C, name="rlDrawVertexArrayInstanced")
        import :: c_int
        integer(c_int), value :: offset, n, instances
    end subroutine
    integer(c_int) function rl_load_texture(data, w, h, fmt, mips) bind(C, &
        name="rlLoadTexture")
        import :: c_int, c_ptr
        type(c_ptr), value :: data
        integer(c_int), value :: w, h, fmt, mips
    end function
    subroutine rl_update_texture(id, ox, oy, w, h, fmt, data) bind(C, &
        name="rlUpdateTexture")
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

contains

function rl_name(self) result(name)
    class(raylib_backend_t), intent(in) :: self
    character(len=:), allocatable :: name
    name = "gui"
end function rl_name

logical function rl_init(self)
    class(raylib_backend_t), intent(inout) :: self
    integer(c_int) :: flags

    rl_init = .false.
    if (.not. raylib_is_available()) then
        call report_error("fortui_gui_raylib", "init", "no graphical display " // &
            "(DISPLAY/WAYLAND_DISPLAY unset or FORTUI_HEADLESS=1)")
        return
    end if
    flags = ior(RL_FLAG_RESIZABLE, RL_FLAG_HIGHDPI)
    if (self%config%vsync) flags = ior(flags, RL_FLAG_VSYNC)
    call rl_set_config_flags(flags)
    call rl_init_window(int(self%config%width, c_int), int(self%config%height, c_int), &
        cstr(trim(self%config%title)))
    call rl_set_target_fps(int(max(0, self%config%target_fps), c_int))
    call rl_set_exit_key(0_c_int)
    self%active = .true.
    self%close_requested = .false.
    allocate(self%fonts(N_LADDER, 2))
    self%font_loaded = .false.
    call update_dpr(self)
    call build_codepoints(self)
    call load_shaders(self)
    rl_init = .true.
end function rl_init

subroutine rl_shutdown(self)
    class(raylib_backend_t), intent(inout) :: self
    integer :: i, s

    if (.not. self%active) return
    if (allocated(self%gpu)) then
        do i = 1, size(self%gpu)
            call free_gpu(self%gpu(i))
        end do
        deallocate(self%gpu)
    end if
    do s = 1, 2
        do i = 1, N_LADDER
            if (self%font_loaded(i, s)) call rl_unload_font(self%fonts(i, s))
            self%font_loaded(i, s) = .false.
        end do
    end do
    if (self%points_shader > 0) call rl_unload_shader_program(self%points_shader)
    if (self%lines_shader > 0) call rl_unload_shader_program(self%lines_shader)
    if (self%quad_points > 0) call rl_unload_vertex_buffer(self%quad_points)
    if (self%quad_lines > 0) call rl_unload_vertex_buffer(self%quad_lines)
    self%points_shader = 0
    self%lines_shader = 0
    self%quad_points = 0
    self%quad_lines = 0
    call rl_close_window()
    self%active = .false.
end subroutine rl_shutdown

subroutine rl_poll(self, input, wait)
    !! Read the events raylib gathered at the end of the last present; when the
    !! runtime allows idle waiting and nothing arrived, block for the next event.
    class(raylib_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    logical, intent(in) :: wait

    if (.not. self%active) return
    if (rl_window_should_close()) self%close_requested = .true.
    call read_input(self, input)
    if (wait .and. .not. input_has_events(input) .and. .not. self%close_requested) then
        self%waits = self%waits + 1
        if (self%wake_in >= 0.0) then
            ! raylib has no event wait with a timeout: sleep until the timer.
            call rl_wait_time(real(self%wake_in, c_double))
            call rl_poll_input_events()
        else
            call rl_enable_event_waiting()
            call rl_poll_input_events()
            call rl_disable_event_waiting()
        end if
        if (rl_window_should_close()) self%close_requested = .true.
        call read_input(self, input)
    end if
end subroutine rl_poll

subroutine read_input(self, input)
    !! Normalize raylib input state; logical window size and scale.
    class(raylib_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    integer :: key, cp, k
    real(c_float) :: wheel

    input%width = max(1, int(rl_get_screen_width()))
    input%height = max(1, int(rl_get_screen_height()))
    call update_dpr(self)
    input%scale = self%dpr
    if (rl_is_window_resized()) input%resized = .true.
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
        call input_set_key(input, map_key(key))
    end do
    do k = 1, size(REPEAT_KEYS)
        if (rl_is_key_pressed_repeat(int(REPEAT_KEYS(k), c_int))) &
            call input_set_key(input, map_key(REPEAT_KEYS(k)))
    end do
    do
        cp = int(rl_get_char_pressed())
        if (cp == 0) exit
        call input_type_text(input, utf8_encode(cp))
    end do
end subroutine read_input

subroutine rl_present(self, frame, store)
    !! Draw a semantic frame; never blocks for events (see rl_poll).
    class(raylib_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    integer :: i

    self%presents = self%presents + 1
    if (.not. self%active) return
    call self%canvas%sync(store)
    call release_stale(self, store)
    call rl_begin_drawing()
    call rl_clear_background(color(30, 30, 30, 255))
    do i = 1, frame%count
        call draw_node(self, frame, store, frame%nodes(i))
    end do
    call rl_disable_event_waiting()
    call rl_end_drawing()
end subroutine rl_present

logical function rl_should_close(self)
    class(raylib_backend_t), intent(in) :: self
    rl_should_close = .not. self%active .or. self%close_requested
    if (.not. rl_should_close) rl_should_close = logical(rl_window_should_close())
end function rl_should_close

subroutine rl_metrics(self)
    !! Advances measured from the fonts actually drawn (bundled DejaVu Sans
    !! subset or the configured TTF files).
    class(raylib_backend_t), intent(inout) :: self
    real, allocatable :: table(:, :)
    real :: fallback(2), ref
    type(rl_vector2) :: v
    integer :: s, i, k

    k = N_LADDER - 1
    ref = LADDER(k)
    allocate(table(0:TEXT_MAX_CODEPOINT, 2))
    do s = 1, 2
        call ensure_font(self, k, s)
        v = rl_measure_text_ex(self%fonts(k, s), cstr("?"), real(ref, c_float), &
            0.0_c_float)
        fallback(s) = real(v%x) / ref
        table(:, s) = fallback(s)
        do i = 1, size(self%codepoints)
            if (self%codepoints(i) > TEXT_MAX_CODEPOINT) cycle
            v = rl_measure_text_ex(self%fonts(k, s), &
                cstr(utf8_encode(int(self%codepoints(i)))), real(ref, c_float), &
                0.0_c_float)
            table(self%codepoints(i), s) = real(v%x) / ref
        end do
    end do
    call text_set_metrics(table, fallback, 1.25)
end subroutine rl_metrics

function rl_caps(self) result(caps)
    class(raylib_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
    caps%graphical = .true.
    caps%canvas_layers = .true.
    caps%proportional_text = .true.
    caps%event_waiting = .true.
    caps%high_dpi = .true.
    caps%pointer = .true.
    caps%text_entry = .true.
end function rl_caps

logical function raylib_is_available()
    !! A display server is reachable (Linux) and FORTUI_HEADLESS is not set.
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        raylib_is_available = .false.
        return
    end if
#ifdef __linux__
    call get_environment_variable("DISPLAY", value, status=status)
    if (status == 0 .and. len_trim(value) > 0) then
        raylib_is_available = .true.
        return
    end if
    call get_environment_variable("WAYLAND_DISPLAY", value, status=status)
    raylib_is_available = status == 0 .and. len_trim(value) > 0
#else
    raylib_is_available = .true.
#endif
end function raylib_is_available

subroutine update_dpr(rl)
    class(raylib_backend_t), intent(inout) :: rl
    integer :: sw
    sw = int(rl_get_screen_width())
    rl%dpr = 1.0
    if (sw > 0) rl%dpr = max(1.0, real(rl_get_render_width()) / real(sw))
end subroutine update_dpr

function cstr(s) result(out)
    character(*), intent(in) :: s
    character(len=:, kind=c_char), allocatable :: out
    out = s // c_null_char
end function cstr

subroutine build_codepoints(rl)
    class(raylib_backend_t), intent(inout) :: rl
    integer, parameter :: ranges(2, 8) = reshape([32, 126, 160, 383, 880, 1023, &
        8192, 8303, 8364, 8364, 8592, 8703, 8704, 8959, 65533, 65533], [2, 8])
    integer :: r, c, n

    n = sum(ranges(2, :) - ranges(1, :) + 1)
    if (allocated(rl%codepoints)) deallocate(rl%codepoints)
    allocate(rl%codepoints(n))
    n = 0
    do r = 1, size(ranges, 2)
        do c = ranges(1, r), ranges(2, r)
            n = n + 1
            rl%codepoints(n) = int(c, c_int)
        end do
    end do
end subroutine build_codepoints

function font_file(rl, style) result(path)
    !! TTF override for `style`: backend option, else FORTUI_FONT[_BOLD]; empty
    !! means the bundled DejaVu Sans subset.
    type(raylib_backend_t), intent(in) :: rl
    integer, intent(in) :: style
    character(len=:), allocatable :: path
    character(len=1024) :: env
    integer :: status

    path = ""
    if (style == 2) then
        if (allocated(rl%font_bold)) path = trim(rl%font_bold)
        if (len(path) > 0) return
        call get_environment_variable("FORTUI_FONT_BOLD", env, status=status)
    else
        if (allocated(rl%font_regular)) path = trim(rl%font_regular)
        if (len(path) > 0) return
        call get_environment_variable("FORTUI_FONT", env, status=status)
    end if
    if (status == 0 .and. len_trim(env) > 0) path = trim(env)
end function font_file

subroutine ensure_font(rl, k, style)
    !! Rasterize ladder size k of `style` on first use.
    type(raylib_backend_t), intent(inout), target :: rl
    integer, intent(in) :: k, style
    character(len=:), allocatable :: path
    integer(c_int) :: nbytes
    type(c_ptr) :: data
    type(rl_font) :: f
    logical :: loaded

    if (rl%font_loaded(k, style)) return
    loaded = .false.
    path = font_file(rl, style)
    if (len(path) > 0) then
        if (rl_file_exists(cstr(path))) then
            f = rl_load_font_ex(cstr(path), int(nint(LADDER(k)), c_int), &
                c_loc(rl%codepoints), int(size(rl%codepoints), c_int))
            loaded = f%glyph_count > 0
        end if
        if (.not. loaded) call report_warning("fortui_gui_raylib", "load_font", &
            "cannot load font '" // path // "'; using bundled DejaVu Sans")
    end if
    if (.not. loaded) then
        data = fortui_font_data(int(style, c_int), nbytes)
        f = rl_load_font_mem(cstr(".ttf"), data, nbytes, int(nint(LADDER(k)), c_int), &
            c_loc(rl%codepoints), int(size(rl%codepoints), c_int))
    end if
    call rl_set_texture_filter(f%texture, TEX_FILTER_BILINEAR)
    rl%fonts(k, style) = f
    rl%font_loaded(k, style) = .true.
end subroutine ensure_font

integer function ladder_index(rl, size) result(k)
    type(raylib_backend_t), intent(in) :: rl
    real, intent(in) :: size
    real :: px

    px = size * rl%dpr
    do k = 1, N_LADDER
        if (LADDER(k) >= px - 0.5) return
    end do
    k = N_LADDER
end function ladder_index

subroutine draw_utf8(rl, s, x, y, size, style, c)
    type(raylib_backend_t), intent(inout) :: rl
    character(*), intent(in) :: s
    real, intent(in) :: x, y, size
    integer, intent(in) :: style
    type(rl_color), intent(in) :: c
    integer :: k, st

    if (len(s) == 0) return
    st = max(1, min(2, style))
    k = ladder_index(rl, size)
    call ensure_font(rl, k, st)
    call rl_draw_text_ex(rl%fonts(k, st), cstr(s), &
        rl_vector2(real(x, c_float), real(y, c_float)), real(size, c_float), &
        0.0_c_float, c)
end subroutine draw_utf8

subroutine load_shaders(rl)
    type(raylib_backend_t), intent(inout) :: rl
    character(len=*), parameter :: nl = achar(10)
    character(len=*), parameter :: head = "#version 330" // nl // &
        "uniform vec4 u_frame;" // nl // "uniform vec4 u_view;" // nl // &
        "uniform vec4 u_style;" // nl // "uniform sampler2D u_pos;" // nl // &
        "ivec2 texel(int k) { return ivec2(k % 2048, k / 2048); }" // nl
    character(len=*), parameter :: to_ndc = &
        "    gl_Position = vec4(2.0 * p.x / u_frame.z - 1.0, " // &
        "1.0 - 2.0 * p.y / u_frame.w, 0.0, 1.0);" // nl
    character(len=:), allocatable :: pvs, pfs, lvs, lfs
    real(c_float), target :: quad_p(12), quad_l(12)

    pvs = head // &
        "layout(location = 0) in vec2 a_corner;" // nl // &
        "layout(location = 2) in float a_size;" // nl // &
        "layout(location = 3) in vec4 a_color;" // nl // &
        "out vec2 v_local; out vec4 v_color; out float v_radius;" // nl // &
        "void main() {" // nl // &
        "    vec2 pos = texelFetch(u_pos, texel(gl_InstanceID), 0).xy;" // nl // &
        "    float r = max(0.5 * a_size * u_style.x, 0.5 * u_style.y);" // nl // &
        "    float pad = r + 1.0 / u_view.w;" // nl // &
        "    vec2 c = u_frame.xy + pos * u_view.x + u_view.yz;" // nl // &
        "    vec2 p = c + a_corner * pad;" // nl // &
        "    v_local = a_corner * pad; v_radius = r; v_color = a_color;" // nl // &
        to_ndc // "}" // nl
    pfs = "#version 330" // nl // &
        "in vec2 v_local; in vec4 v_color; in float v_radius;" // nl // &
        "uniform vec4 u_view;" // nl // "out vec4 frag;" // nl // &
        "void main() {" // nl // &
        "    float a = clamp((v_radius - length(v_local)) * u_view.w + 0.5, " // &
        "0.0, 1.0);" // nl // "    if (a <= 0.0) discard;" // nl // &
        "    frag = vec4(v_color.rgb, v_color.a * a);" // nl // "}" // nl
    lvs = head // &
        "layout(location = 0) in vec2 a_corner;" // nl // &
        "layout(location = 1) in vec2 a_seg;" // nl // &
        "uniform sampler2D u_col;" // nl // &
        "out vec4 v_color; out float v_across; out float v_half;" // nl // &
        "void main() {" // nl // &
        "    ivec2 ta = texel(int(a_seg.x + 0.5));" // nl // &
        "    ivec2 tb = texel(int(a_seg.y + 0.5));" // nl // &
        "    vec2 sa = u_frame.xy + texelFetch(u_pos, ta, 0).xy * u_view.x" // &
        " + u_view.yz;" // nl // &
        "    vec2 sb = u_frame.xy + texelFetch(u_pos, tb, 0).xy * u_view.x" // &
        " + u_view.yz;" // nl // &
        "    vec2 d = sb - sa; float len = length(d);" // nl // &
        "    vec2 dir = len > 1e-6 ? d / len : vec2(1.0, 0.0);" // nl // &
        "    vec2 n = vec2(-dir.y, dir.x);" // nl // &
        "    float hw = u_style.x + 1.0 / u_view.w;" // nl // &
        "    vec2 p = mix(sa, sb, a_corner.x) + n * (a_corner.y * hw);" // nl // &
        "    v_across = a_corner.y * hw; v_half = u_style.x;" // nl // &
        "    v_color = mix(texelFetch(u_col, ta, 0), texelFetch(u_col, tb, 0), " // &
        "a_corner.x);" // nl // to_ndc // "}" // nl
    lfs = "#version 330" // nl // &
        "in vec4 v_color; in float v_across; in float v_half;" // nl // &
        "uniform vec4 u_view;" // nl // "out vec4 frag;" // nl // &
        "void main() {" // nl // &
        "    float a = clamp((v_half - abs(v_across)) * u_view.w + 0.5, " // &
        "0.0, 1.0);" // nl // "    if (a <= 0.0) discard;" // nl // &
        "    frag = vec4(v_color.rgb, v_color.a * a);" // nl // "}" // nl

    rl%points_shader = rl_load_shader_program(cstr(pvs), cstr(pfs))
    rl%lines_shader = rl_load_shader_program(cstr(lvs), cstr(lfs))
    if (rl%points_shader == 0 .or. rl%lines_shader == 0) then
        call report_error("fortui_gui_raylib", "load_shaders", &
            "canvas shaders failed to compile; canvas layers will not be drawn")
    end if
    rl%loc_p_frame = rl_get_location_uniform(rl%points_shader, cstr("u_frame"))
    rl%loc_p_view = rl_get_location_uniform(rl%points_shader, cstr("u_view"))
    rl%loc_p_style = rl_get_location_uniform(rl%points_shader, cstr("u_style"))
    rl%loc_p_pos = rl_get_location_uniform(rl%points_shader, cstr("u_pos"))
    rl%loc_l_frame = rl_get_location_uniform(rl%lines_shader, cstr("u_frame"))
    rl%loc_l_view = rl_get_location_uniform(rl%lines_shader, cstr("u_view"))
    rl%loc_l_style = rl_get_location_uniform(rl%lines_shader, cstr("u_style"))
    rl%loc_l_pos = rl_get_location_uniform(rl%lines_shader, cstr("u_pos"))
    rl%loc_l_col = rl_get_location_uniform(rl%lines_shader, cstr("u_col"))

    quad_p = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0]
    quad_l = [0.0, -1.0, 1.0, -1.0, 1.0, 1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0]
    rl%quad_points = rl_load_vertex_buffer(c_loc(quad_p), 48_c_int, .false._c_bool)
    rl%quad_lines = rl_load_vertex_buffer(c_loc(quad_l), 48_c_int, .false._c_bool)
end subroutine load_shaders

subroutine free_gpu(g)
    type(gpu_layer_t), intent(inout) :: g

    if (g%vao /= 0) call rl_unload_vertex_array(g%vao)
    if (g%vbo_size /= 0) call rl_unload_vertex_buffer(g%vbo_size)
    if (g%vbo_col /= 0) call rl_unload_vertex_buffer(g%vbo_col)
    if (g%vbo_seg /= 0) call rl_unload_vertex_buffer(g%vbo_seg)
    if (g%tex /= 0) call rl_unload_texture(g%tex)
    g = gpu_layer_t()
end subroutine free_gpu

subroutine release_stale(rl, store)
    !! Free GPU resources whose store slot was released or reassigned.
    type(raylib_backend_t), intent(inout) :: rl
    type(canvas_store_t), intent(in) :: store
    type(gpu_layer_t), allocatable :: grown(:)
    integer :: i, n

    n = 0
    if (allocated(store%layers)) n = size(store%layers)
    if (.not. allocated(rl%gpu)) allocate(rl%gpu(max(n, 8)))
    if (size(rl%gpu) < n) then
        allocate(grown(n))
        grown(1:size(rl%gpu)) = rl%gpu
        call move_alloc(grown, rl%gpu)
    end if
    do i = 1, size(rl%gpu)
        if (rl%gpu(i)%serial == 0) cycle
        if (i > n) then
            call free_gpu(rl%gpu(i))
        else if (.not. store%layers(i)%in_use .or. &
            store%layers(i)%serial /= rl%gpu(i)%serial) then
            call free_gpu(rl%gpu(i))
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

subroutine realize_vertices(rl, store, slot)
    !! Position texture of a shared vertex layer (uploaded once per version).
    type(raylib_backend_t), intent(inout), target :: rl
    type(canvas_store_t), intent(in), target :: store
    integer, intent(in) :: slot
    integer :: n, rows, i
    logical :: fresh

    associate(l => store%layers(slot), g => rl%gpu(slot))
        n = l%vertex_count
        rows = max(1, (n + TEX_WIDTH - 1) / TEX_WIDTH)
        fresh = g%serial /= l%serial .or. rows > g%tex_rows
        if (fresh) then
            call free_gpu(g)
            g%serial = l%serial
            g%kind = l%kind
            g%tex_rows = rows + rows / 4
            call ensure_scratch(rl, TEX_WIDTH * g%tex_rows)
            rl%scratch_f(1:4 * TEX_WIDTH * g%tex_rows) = 0.0
            g%tex = rl_load_texture(c_loc(rl%scratch_f), int(TEX_WIDTH, c_int), &
                int(g%tex_rows, c_int), RL_PIXEL_RGBA32F, 1_c_int)
        end if
        if (.not. rl%canvas%vertices(store, slot, fresh) .or. n == 0) return
        call ensure_scratch(rl, TEX_WIDTH * rows)
        do i = 1, n
            rl%scratch_f(4 * i - 3) = l%xy(1, i)
            rl%scratch_f(4 * i - 2) = l%xy(2, i)
            rl%scratch_f(4 * i - 1) = 0.0
            rl%scratch_f(4 * i) = 0.0
        end do
        call rl_update_texture(g%tex, 0_c_int, 0_c_int, int(TEX_WIDTH, c_int), &
            int(rows, c_int), RL_PIXEL_RGBA32F, c_loc(rl%scratch_f))
    end associate
end subroutine realize_vertices

subroutine realize_points(rl, store, ref)
    type(raylib_backend_t), intent(inout), target :: rl
    type(canvas_store_t), intent(in), target :: store
    type(ui_layer_ref_t), intent(in) :: ref
    logical :: fresh, attributes, indices, ok
    integer :: n

    n = ref%vertex_count
    associate(g => rl%gpu(ref%slot), l => store%layers(ref%slot))
        fresh = g%serial /= ref%serial .or. n > g%capacity
        if (fresh) then
            call free_gpu(g)
            g%serial = ref%serial
            g%kind = LAYER_POINTS
            g%capacity = max(16, n + n / 4)
            g%vao = rl_load_vertex_array()
            ok = rl_enable_vertex_array(g%vao)
            call rl_enable_vertex_buffer(rl%quad_points)
            call attribute(0, 2, RL_FLOAT, .false., 0)
            g%vbo_size = rl_load_vertex_buffer(c_null_ptr, int(4 * g%capacity, c_int), &
                .true._c_bool)
            call attribute(2, 1, RL_FLOAT, .false., 1)
            g%vbo_col = rl_load_vertex_buffer(c_null_ptr, int(4 * g%capacity, c_int), &
                .true._c_bool)
            call attribute(3, 4, RL_UNSIGNED_BYTE, .true., 1)
            call rl_disable_vertex_array()
        end if
        call rl%canvas%layer(ref, fresh, attributes, indices)
        if (attributes .and. n > 0) then
            call rl_update_vertex_buffer(g%vbo_size, c_loc(l%sizes), &
                int(4 * n, c_int), 0_c_int)
            call rl_update_vertex_buffer(g%vbo_col, c_loc(l%rgba), int(4 * n, c_int), &
                0_c_int)
        end if
    end associate
end subroutine realize_points

subroutine realize_lines(rl, store, ref)
    type(raylib_backend_t), intent(inout), target :: rl
    type(canvas_store_t), intent(in), target :: store
    type(ui_layer_ref_t), intent(in) :: ref
    logical :: fresh, attributes, indices, ok
    integer :: n, ns, rows, i

    n = ref%vertex_count
    ns = ref%index_count / 2
    rows = max(1, (n + TEX_WIDTH - 1) / TEX_WIDTH)
    associate(g => rl%gpu(ref%slot), l => store%layers(ref%slot))
        fresh = g%serial /= ref%serial .or. rows > g%tex_rows .or. ns > g%capacity
        if (fresh) then
            call free_gpu(g)
            g%serial = ref%serial
            g%kind = LAYER_LINES
            g%tex_rows = rows + rows / 4
            call ensure_scratch(rl, TEX_WIDTH * g%tex_rows)
            rl%scratch_i(1:TEX_WIDTH * g%tex_rows) = 0
            g%tex = rl_load_texture(c_loc(rl%scratch_i), int(TEX_WIDTH, c_int), &
                int(g%tex_rows, c_int), RL_PIXEL_RGBA8, 1_c_int)
            g%capacity = max(16, ns + ns / 4)
            g%vao = rl_load_vertex_array()
            ok = rl_enable_vertex_array(g%vao)
            call rl_enable_vertex_buffer(rl%quad_lines)
            call attribute(0, 2, RL_FLOAT, .false., 0)
            g%vbo_seg = rl_load_vertex_buffer(c_null_ptr, int(8 * g%capacity, c_int), &
                .true._c_bool)
            call attribute(1, 2, RL_FLOAT, .false., 1)
            call rl_disable_vertex_array()
        end if
        call rl%canvas%layer(ref, fresh, attributes, indices)
        if (attributes .and. n > 0) then
            call ensure_scratch(rl, TEX_WIDTH * rows)
            rl%scratch_i(1:n) = l%rgba(1:n)
            call rl_update_texture(g%tex, 0_c_int, 0_c_int, int(TEX_WIDTH, c_int), &
                int(rows, c_int), RL_PIXEL_RGBA8, c_loc(rl%scratch_i))
        end if
        if (indices) then
            g%segments = ns
            if (ns > 0) then
                call ensure_scratch(rl, ns)
                do i = 1, 2 * ns
                    rl%scratch_f(i) = real(l%indices(i))
                end do
                call rl_update_vertex_buffer(g%vbo_seg, c_loc(rl%scratch_f), &
                    int(8 * ns, c_int), 0_c_int)
            end if
        end if
    end associate
end subroutine realize_lines

subroutine ensure_scratch(rl, texels)
    type(raylib_backend_t), intent(inout) :: rl
    integer, intent(in) :: texels
    if (allocated(rl%scratch_f)) then
        if (size(rl%scratch_f) >= 4 * texels .and. size(rl%scratch_i) >= texels) return
        deallocate(rl%scratch_f, rl%scratch_i)
    end if
    allocate(rl%scratch_f(4 * texels), rl%scratch_i(texels))
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

subroutine draw_canvas(rl, frame, store, node)
    type(raylib_backend_t), intent(inout), target :: rl
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    type(ui_node_t), intent(in) :: node
    real :: sw, sh, scale, sx, sy, w
    integer :: j
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
        associate(ref => frame%layers(j))
            if (rl%points_shader == 0 .or. rl%lines_shader == 0) cycle
            call realize_vertices(rl, store, ref%vertex_slot)
            if (ref%kind == LAYER_POINTS) then
                call realize_points(rl, store, ref)
                if (ref%vertex_count == 0) cycle
                scale = 1.0
                if (store%layers(ref%slot)%world_size) scale = node%canvas_view%zoom
                call rl_enable_shader(rl%points_shader)
                call set_vec4(rl%loc_p_frame, node%x, node%y, sw, sh)
                call set_vec4(rl%loc_p_view, node%canvas_view%zoom, &
                    node%canvas_view%pan_x, node%canvas_view%pan_y, rl%dpr)
                call set_vec4(rl%loc_p_style, scale, &
                    store%layers(ref%slot)%min_pixels, &
                    0.0, 0.0)
                call rl_active_texture_slot(1_c_int)
                call rl_enable_texture(rl%gpu(ref%vertex_slot)%tex)
                call set_int(rl%loc_p_pos, 1)
                ok = rl_enable_vertex_array(rl%gpu(ref%slot)%vao)
                call rl_draw_vertex_array_instanced(0_c_int, 6_c_int, &
                    int(ref%vertex_count, c_int))
                call rl_disable_vertex_array()
                call rl_disable_texture()
                call rl_active_texture_slot(0_c_int)
                call rl_disable_shader()
            else if (ref%kind == LAYER_LINES) then
                call realize_lines(rl, store, ref)
                if (rl%gpu(ref%slot)%segments == 0) cycle
                call rl_enable_shader(rl%lines_shader)
                call set_vec4(rl%loc_l_frame, node%x, node%y, sw, sh)
                call set_vec4(rl%loc_l_view, node%canvas_view%zoom, &
                    node%canvas_view%pan_x, node%canvas_view%pan_y, rl%dpr)
                call set_vec4(rl%loc_l_style, 0.5 * store%layers(ref%slot)%line_width, &
                    0.0, 0.0, 0.0)
                call rl_active_texture_slot(1_c_int)
                call rl_enable_texture(rl%gpu(ref%vertex_slot)%tex)
                call set_int(rl%loc_l_pos, 1)
                call rl_active_texture_slot(2_c_int)
                call rl_enable_texture(rl%gpu(ref%slot)%tex)
                call set_int(rl%loc_l_col, 2)
                ok = rl_enable_vertex_array(rl%gpu(ref%slot)%vao)
                call rl_draw_vertex_array_instanced(0_c_int, 6_c_int, &
                    int(rl%gpu(ref%slot)%segments, c_int))
                call rl_disable_vertex_array()
                call rl_disable_texture()
                call rl_active_texture_slot(1_c_int)
                call rl_disable_texture()
                call rl_active_texture_slot(0_c_int)
                call rl_disable_shader()
            end if
        end associate
    end do
    call rl_enable_backface_culling()
    do j = node%label_first, node%label_first + node%label_count - 1
        associate(lab => frame%labels(j))
            sx = node%x + lab%x * node%canvas_view%zoom + node%canvas_view%pan_x
            sy = node%y + lab%y * node%canvas_view%zoom + node%canvas_view%pan_y
            w = text_width(lab%text, lab%size)
            call draw_utf8(rl, lab%text, sx - 0.5 * w, sy + 2.0, lab%size, &
                TEXT_STYLE_REGULAR, unpack_rgba(lab%rgba))
        end associate
    end do
    call rl_end_scissor()
end subroutine draw_canvas

subroutine draw_scroll_text(rl, node, fg)
    type(raylib_backend_t), intent(inout) :: rl
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
            if (line%last >= line%first) call draw_utf8(rl, &
                node%body(line%first:line%last), node%x + SCROLL_PADDING, &
                ly + 0.5 * (lh - line%size), line%size, line%style, fg)
        end associate
    end do
    call rl_end_scissor()
    total = node%content_height + 2.0 * SCROLL_PADDING
    if (total > node%height) then
        max_scroll = total - node%height
        thumb_h = max(20, nint(node%height * node%height / total))
        thumb_y = y + nint(node%scroll / max_scroll * real(h - thumb_h))
        call rl_draw_rectangle(x + w - nint(SCROLLBAR_WIDTH), y, &
            nint(SCROLLBAR_WIDTH), h, color(40, 40, 44, 255))
        call rl_draw_rectangle(x + w - nint(SCROLLBAR_WIDTH) + 2, thumb_y, &
            nint(SCROLLBAR_WIDTH) - 4, thumb_h, color(110, 110, 120, 255))
    end if
end subroutine draw_scroll_text

subroutine draw_text_input(rl, node, fg)
    type(raylib_backend_t), intent(inout) :: rl
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
        if (.not. node%focused) call draw_utf8(rl, trim(node%text), tx, ty, &
            node%text_size, TEXT_STYLE_REGULAR, color(120, 120, 130, 255))
    else
        call draw_utf8(rl, node%body, tx - shift, ty, node%text_size, &
            TEXT_STYLE_REGULAR, fg)
    end if
    if (node%focused) call rl_draw_rectangle(nint(tx - shift + caret_x), y + 6, 2, &
        max(1, h - 12), color(255, 220, 90, 255))
    call rl_end_scissor()
end subroutine draw_text_input

function shown(node, avail, weight) result(s)
    !! Node text, shortened with an ellipsis to `avail` when the node asks for it.
    type(ui_node_t), intent(in) :: node
    real, intent(in) :: avail
    integer, intent(in) :: weight
    character(len=:), allocatable :: s
    if (node%ellipsis) then
        s = text_fit(trim(node%text), node%text_size, avail, weight)
    else
        s = trim(node%text)
    end if
end function shown

subroutine draw_node(rl, frame, store, node)
    type(raylib_backend_t), intent(inout), target :: rl
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    type(ui_node_t), intent(in) :: node
    type(rl_color) :: fg, fill
    integer :: x, y, w, h, knob, weight
    real :: fraction, ty, tw
    character(len=:), allocatable :: s

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
    ! Raylib draws monospaced text with the regular font.
    weight = min(style_weight(node%style), 2)

    select case (node%kind)
    case (UI_TEXT, UI_LINK)
        if (node%style == UI_CAPTION) fg = color(160, 166, 178, 255)
        call draw_utf8(rl, shown(node, node%width, weight), node%x, ty, &
            node%text_size, weight, fg)
    case (UI_BUTTON)
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(x, y, w, h, fill)
        call draw_utf8(rl, shown(node, node%width - 2.0 * CONTROL_PADDING, weight), &
            node%x + CONTROL_PADDING, ty, node%text_size, weight, fg)
    case (UI_TAB)
        if (node%checked) then
            fill = color(62, 84, 120, 255)
        else if (node%hovered) then
            fill = color(50, 58, 72, 255)
        else
            fill = color(38, 42, 50, 255)
            fg = color(175, 180, 190, 255)
        end if
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(x, y, w, h, fill)
        if (node%checked) call rl_draw_rectangle(x, y + h - 3, w, 3, &
            color(255, 220, 90, 255))
        s = text_fit(trim(node%text), node%text_size, &
            node%width - 2.0 * CONTROL_PADDING)
        tw = text_width(s, node%text_size)
        call draw_utf8(rl, s, node%x + 0.5 * (node%width - tw), ty, node%text_size, &
            TEXT_STYLE_REGULAR, fg)
    case (UI_CHECKBOX)
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(x, y + (h - 20) / 2, 20, 20, fill)
        if (node%checked) call rl_draw_rectangle(x + 5, y + (h - 20) / 2 + 5, 10, 10, &
            color(120, 230, 140, 255))
        if (len_trim(node%text) > 0) call draw_utf8(rl, text_fit(trim(node%text), &
            node%text_size, node%width - 30.0), node%x + 30.0, ty, node%text_size, &
            TEXT_STYLE_REGULAR, fg)
    case (UI_SLIDER)
        call rl_draw_rectangle(x, y + h / 2 - 2, w, 4, color(80, 80, 80, 255))
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        knob = x + nint(fraction * real(w))
        if (node%focused) fg = color(255, 220, 90, 255)
        call rl_draw_rectangle(knob - 5, y + 4, 10, max(8, h - 8), fg)
    case (UI_CANVAS)
        call draw_canvas(rl, frame, store, node)
    case (UI_SCROLL_TEXT)
        call draw_scroll_text(rl, node, fg)
    case (UI_TEXT_INPUT)
        call draw_text_input(rl, node, fg)
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

pure integer function map_key(key) result(mapped)
    !! Backend-neutral KEY_* for a raylib key code (KEY_NONE if unnamed).
    integer, intent(in) :: key
    select case (key)
    case (256); mapped = KEY_ESCAPE
    case (257, 335); mapped = KEY_ENTER
    case (258); mapped = KEY_TAB
    case (32); mapped = KEY_SPACE
    case (259); mapped = KEY_BACKSPACE
    case (260); mapped = KEY_INSERT
    case (261); mapped = KEY_DELETE
    case (262); mapped = KEY_ARROW_RIGHT
    case (263); mapped = KEY_ARROW_LEFT
    case (264); mapped = KEY_ARROW_DOWN
    case (265); mapped = KEY_ARROW_UP
    case (266); mapped = KEY_PAGE_UP
    case (267); mapped = KEY_PAGE_DOWN
    case (268); mapped = KEY_HOME
    case (269); mapped = KEY_END
    case default; mapped = KEY_NONE
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
