module fortui_gui_sdl
    !! SDL3 backend: window, input events and platform services from SDL3,
    !! drawing with the SDL GPU API (Vulkan SPIR-V shaders), text with SDL_ttf
    !! (FreeType and HarfBuzz) from fonts found with fontconfig.
    !!
    !! The frame is painted by the current theme's painter (fortui_paint) into a
    !! display list in physical pixels: rectangles, lines and points become
    !! instances of one signed-distance shader (exact pixels for square edges,
    !! antialiased for rounded ones), text and images become textured quads drawn
    !! 1:1 with nearest sampling for glyphs, so text stays sharp. Canvas point and
    !! line layers live in GPU buffers uploaded once per data version and drawn
    !! with the view as a transform. Input arrives as SDL's event queue, so every
    !! button change reaches the frame, also a press and release between two
    !! frames (quick clicks and touchpad taps).
    !!
    !! Compiled with -DENABLE_SDL=1 and linked with -lSDL3 -lSDL3_ttf -lfontconfig
    !! (otherwise this module is empty).
    use iso_c_binding
    use iso_fortran_env, only: int8, int32, int64
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t, ui_layer_ref_t, LAYER_POINTS, LAYER_IMAGE
    use fortui_canvas, only: canvas_store_t
    use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
        input_type_text, input_set_time, input_key_press, input_has_events, KEY_NONE, &
        KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, &
        KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, &
        KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_META
    use fortui_paint, only: paint_list_t, paint_frame, paint_face, PAINT_RECT, PAINT_LINE, &
        PAINT_TEXT, PAINT_CLIP, PAINT_UNCLIP, PAINT_CANVAS, PATTERN_CHECKER
    use fortui_theme, only: theme, FACE_REGULAR
    use fortui_text, only: text_use_measurement
    use fortui_fontconfig, only: font_for
    use fortui_sdl_shaders, only: shape_vert_spv, shape_frag_spv, textured_vert_spv, &
        textured_frag_spv
    use fortui_error, only: report_error
    implicit none
    private
#ifdef ENABLE_SDL

    public :: sdl_backend_t, sdl_is_available, sdl_read_pixels

    ! --- SDL constants -------------------------------------------------------------
    integer(c_int32_t), parameter :: SDL_INIT_VIDEO = int(z'20', c_int32_t)
    integer(c_int64_t), parameter :: WIN_RESIZABLE = int(z'20', c_int64_t), &
        WIN_HIGH_DENSITY = int(z'2000', c_int64_t)
    integer, parameter :: EV_QUIT = int(z'100'), EV_WIN_RESIZED = int(z'206'), &
        EV_WIN_PIXELS = int(z'207'), EV_WIN_CLOSE = int(z'210'), &
        EV_WIN_SCALE = int(z'214'), EV_WIN_EXPOSED = int(z'204'), &
        EV_WIN_LEAVE = int(z'20d'), EV_KEY_DOWN = int(z'300'), EV_TEXT = int(z'303'), &
        EV_MOTION = int(z'400'), EV_BUTTON_DOWN = int(z'401'), EV_BUTTON_UP = int(z'402'), &
        EV_WHEEL = int(z'403')
    integer(c_int32_t), parameter :: FORMAT_SPIRV = 2, STAGE_VERTEX = 0, STAGE_FRAGMENT = 1
    integer(c_int32_t), parameter :: TEX_RGBA8 = 4, TEX_2D = 0, TEXUSE_SAMPLER = 1, &
        TEXUSE_TARGET = 2
    integer(c_int32_t), parameter :: BUF_VERTEX = 1, BUF_INDEX = 2, BUF_STORAGE = 8
    integer(c_int32_t), parameter :: XFER_UPLOAD = 0, XFER_DOWNLOAD = 1
    integer(c_int32_t), parameter :: BLEND_ONE = 2, BLEND_ONE_MINUS_SRC_ALPHA = 8, &
        BLEND_ADD = 1
    integer(c_int32_t), parameter :: VFMT_FLOAT2 = 10, VFMT_FLOAT4 = 12
    integer(c_int32_t), parameter :: LOAD_CLEAR = 1, STORE_STORE = 0
    integer(c_int32_t), parameter :: FILTER_NEAREST = 0, FILTER_LINEAR = 1, ADDR_CLAMP = 2
    integer(c_int32_t), parameter :: INDEX_32 = 1
    integer(c_int), parameter :: HINT_LIGHT = 1, HINT_MONO = 2

    ! --- SDL structures (layouts checked against the C headers) ----------------------
    type, bind(C) :: shader_info_t
        integer(c_size_t) :: code_size = 0
        type(c_ptr) :: code = c_null_ptr, entrypoint = c_null_ptr
        integer(c_int32_t) :: format = 0, stage = 0, num_samplers = 0, &
            num_storage_textures = 0, num_storage_buffers = 0, num_uniform_buffers = 0, &
            props = 0
    end type
    type, bind(C) :: vb_desc_t
        integer(c_int32_t) :: slot = 0, pitch = 0, input_rate = 0, step = 0
    end type
    type, bind(C) :: vattr_t
        integer(c_int32_t) :: location = 0, buffer_slot = 0, format = 0, offset = 0
    end type
    type, bind(C) :: vinput_t
        type(c_ptr) :: descs = c_null_ptr
        integer(c_int32_t) :: ndescs = 0
        type(c_ptr) :: attrs = c_null_ptr
        integer(c_int32_t) :: nattrs = 0
    end type
    type, bind(C) :: raster_t
        integer(c_int32_t) :: fill_mode = 0, cull_mode = 0, front_face = 0
        real(c_float) :: bias_const = 0.0, bias_clamp = 0.0, bias_slope = 0.0
        logical(c_bool) :: enable_bias = .false., enable_clip = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0
    end type
    type, bind(C) :: multisample_t
        integer(c_int32_t) :: sample_count = 0, sample_mask = 0
        logical(c_bool) :: enable_mask = .false., alpha_to_coverage = .false.
        integer(c_int8_t) :: pad2 = 0, pad3 = 0
    end type
    type, bind(C) :: stencil_t
        integer(c_int32_t) :: fail_op = 0, pass_op = 0, depth_fail_op = 0, compare_op = 0
    end type
    type, bind(C) :: depth_t
        integer(c_int32_t) :: compare_op = 0
        type(stencil_t) :: back, front
        integer(c_int8_t) :: compare_mask = 0, write_mask = 0
        logical(c_bool) :: depth_test = .false., depth_write = .false., stencil_test = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0, pad3 = 0
    end type
    type, bind(C) :: blend_t
        integer(c_int32_t) :: src_color = 0, dst_color = 0, color_op = 0, src_alpha = 0, &
            dst_alpha = 0, alpha_op = 0
        integer(c_int8_t) :: write_mask = 0
        logical(c_bool) :: enable_blend = .false., enable_write_mask = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0
    end type
    type, bind(C) :: ct_desc_t
        integer(c_int32_t) :: format = 0
        type(blend_t) :: blend
    end type
    type, bind(C) :: target_info_t
        type(c_ptr) :: descs = c_null_ptr
        integer(c_int32_t) :: ndescs = 0, depth_format = 0
        logical(c_bool) :: has_depth = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0, pad3 = 0
    end type
    type, bind(C) :: pipeline_info_t
        type(c_ptr) :: vs = c_null_ptr, fs = c_null_ptr
        type(vinput_t) :: vinput
        integer(c_int32_t) :: primitive = 0
        type(raster_t) :: raster
        type(multisample_t) :: multisample
        type(depth_t) :: depth
        type(target_info_t) :: target
        integer(c_int32_t) :: props = 0
    end type
    type, bind(C) :: color_target_t
        type(c_ptr) :: texture = c_null_ptr
        integer(c_int32_t) :: mip = 0, layer = 0
        real(c_float) :: clear(4) = 0.0
        integer(c_int32_t) :: load_op = 0, store_op = 0
        type(c_ptr) :: resolve = c_null_ptr
        integer(c_int32_t) :: resolve_mip = 0, resolve_layer = 0
        logical(c_bool) :: cycle = .false., cycle_resolve = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0
    end type
    type, bind(C) :: buffer_info_t
        integer(c_int32_t) :: usage = 0, size = 0, props = 0
    end type
    type, bind(C) :: xfer_location_t
        type(c_ptr) :: buffer = c_null_ptr
        integer(c_int32_t) :: offset = 0
    end type
    type, bind(C) :: buffer_region_t
        type(c_ptr) :: buffer = c_null_ptr
        integer(c_int32_t) :: offset = 0, size = 0
    end type
    type, bind(C) :: texture_info_t
        integer(c_int32_t) :: type = 0, format = 0, usage = 0, width = 0, height = 0, &
            layers = 1, levels = 1, samples = 0, props = 0
    end type
    type, bind(C) :: texture_xfer_t
        type(c_ptr) :: buffer = c_null_ptr
        integer(c_int32_t) :: offset = 0, pixels_per_row = 0, rows_per_layer = 0
    end type
    type, bind(C) :: texture_region_t
        type(c_ptr) :: texture = c_null_ptr
        integer(c_int32_t) :: mip = 0, layer = 0, x = 0, y = 0, z = 0, w = 0, h = 0, d = 1
    end type
    type, bind(C) :: sampler_info_t
        integer(c_int32_t) :: min_filter = 0, mag_filter = 0, mipmap_mode = 0, &
            address_u = 0, address_v = 0, address_w = 0
        real(c_float) :: lod_bias = 0.0, max_anisotropy = 1.0
        integer(c_int32_t) :: compare_op = 0
        real(c_float) :: min_lod = 0.0, max_lod = 0.0
        logical(c_bool) :: enable_anisotropy = .false., enable_compare = .false.
        integer(c_int8_t) :: pad1 = 0, pad2 = 0
        integer(c_int32_t) :: props = 0
    end type
    type, bind(C) :: sampler_binding_t
        type(c_ptr) :: texture = c_null_ptr, sampler = c_null_ptr
    end type
    type, bind(C) :: buffer_binding_t
        type(c_ptr) :: buffer = c_null_ptr
        integer(c_int32_t) :: offset = 0
    end type
    type, bind(C) :: viewport_t
        real(c_float) :: x = 0.0, y = 0.0, w = 0.0, h = 0.0, min_depth = 0.0, max_depth = 1.0
    end type
    type, bind(C) :: sdl_rect_t
        integer(c_int) :: x = 0, y = 0, w = 0, h = 0
    end type
    type, bind(C) :: draw_seq_t
        type(c_ptr) :: atlas = c_null_ptr, xy = c_null_ptr, uv = c_null_ptr
        integer(c_int) :: num_vertices = 0
        type(c_ptr) :: indices = c_null_ptr
        integer(c_int) :: num_indices = 0, image_type = 0
        type(c_ptr) :: next = c_null_ptr
    end type

    ! --- backend state ---------------------------------------------------------------
    integer, parameter :: SHAPE_FLOATS = 16, VERTEX_FLOATS = 8
    integer, parameter :: BATCH_SHAPES = 1, BATCH_TEXTURED = 2, BATCH_LAYER = 3

    type :: font_slot_t
        integer :: face = 0, px = 0
        type(c_ptr) :: font = c_null_ptr
        integer :: height = 0, ascent = 0
    end type

    type :: text_entry_t
        integer(int64) :: hash = 0
        integer :: slot = 0, last = -1000
        character(len=:), allocatable :: str
        type(c_ptr) :: text = c_null_ptr
    end type

    type :: gpu_layer_t
        integer :: serial = 0, version = -1, index_version = -1, vertex_version = -1
        integer :: count = 0, capacity = 0
        integer :: width = 0, height = 0
        type(c_ptr) :: buffer = c_null_ptr
        type(c_ptr) :: texture = c_null_ptr
        logical :: pending = .false.
        real(c_float), allocatable :: data(:, :)
    end type

    type :: batch_t
        integer :: kind = 0, first = 0, count = 0, slot = 0
        type(c_ptr) :: texture = c_null_ptr, sampler = c_null_ptr
        integer :: clip(4) = 0
        real(c_float) :: view(12) = 0.0
    end type

    type, extends(ui_backend_t), public :: sdl_backend_t
        !! `offscreen` renders into a texture of the configured size without a
        !! window (tests read it back with sdl_read_pixels).
        logical :: offscreen = .false.
        logical :: active = .false.
        logical :: close_requested = .false.
        type(c_ptr) :: window = c_null_ptr, device = c_null_ptr, engine = c_null_ptr
        type(c_ptr) :: shape_pipe = c_null_ptr, tex_pipe = c_null_ptr
        type(c_ptr) :: nearest = c_null_ptr, linear = c_null_ptr
        type(c_ptr) :: target = c_null_ptr
        integer(c_int32_t) :: format = TEX_RGBA8
        type(c_ptr) :: shape_buf = c_null_ptr, vtx_buf = c_null_ptr, idx_buf = c_null_ptr
        type(c_ptr) :: upload = c_null_ptr
        integer :: shape_cap = 0, vtx_cap = 0, idx_cap = 0, upload_cap = 0
        integer :: pw = 1, ph = 1
        real :: scale = 1.0
        integer :: frame_no = 0
        type(paint_list_t) :: list
        type(text_entry_t), allocatable :: texts(:)
        type(gpu_layer_t), allocatable :: layers(:)
        real(c_float), allocatable :: shapes(:, :), verts(:, :)
        integer(c_int32_t), allocatable :: idx(:)
        integer :: nshapes = 0, nverts = 0, nidx = 0
        type(batch_t), allocatable :: batches(:)
        integer :: nbatches = 0
        integer :: clip(4) = 0
        integer :: clip_stack(4, 32) = 0
        integer :: clip_depth = 0
        ! Events not yet given to a frame.
        integer(c_int8_t), allocatable :: queue(:, :)
        integer :: qhead = 1, qcount = 0
        real :: pointer_x = -1.0, pointer_y = -1.0
        logical :: pointer_down = .false.
    contains
        procedure :: name => sb_name
        procedure :: init => sb_init
        procedure :: shutdown => sb_shutdown
        procedure :: poll => sb_poll
        procedure :: present => sb_present
        procedure :: should_close => sb_should_close
        procedure :: install_text_metrics => sb_metrics
        procedure :: capabilities => sb_caps
    end type sdl_backend_t

    ! Fonts of the SDL backend (one at a time), shared with text measurement.
    type(font_slot_t), save :: fonts(48)
    integer, save :: nfonts = 0
    character(len=32), save :: font_theme = ""
    real, save :: px_scale = 1.0
    logical, save :: measuring = .false.

    interface
        logical(c_bool) function SDL_Init(flags) bind(C, name="SDL_Init")
            import :: c_bool, c_int32_t
            integer(c_int32_t), value :: flags
        end function
        subroutine SDL_QuitSubSystem(flags) bind(C, name="SDL_QuitSubSystem")
            import :: c_int32_t
            integer(c_int32_t), value :: flags
        end subroutine
        type(c_ptr) function SDL_GetError() bind(C, name="SDL_GetError")
            import :: c_ptr
        end function
        type(c_ptr) function SDL_CreateWindow(title, w, h, flags) bind(C, name="SDL_CreateWindow")
            import :: c_ptr, c_char, c_int, c_int64_t
            character(kind=c_char), intent(in) :: title(*)
            integer(c_int), value :: w, h
            integer(c_int64_t), value :: flags
        end function
        subroutine SDL_DestroyWindow(w) bind(C, name="SDL_DestroyWindow")
            import :: c_ptr
            type(c_ptr), value :: w
        end subroutine
        logical(c_bool) function SDL_GetWindowSize(win, w, h) bind(C, name="SDL_GetWindowSize")
            import :: c_ptr, c_bool, c_int
            type(c_ptr), value :: win
            integer(c_int) :: w, h
        end function
        logical(c_bool) function SDL_GetWindowSizeInPixels(win, w, h) &
                bind(C, name="SDL_GetWindowSizeInPixels")
            import :: c_ptr, c_bool, c_int
            type(c_ptr), value :: win
            integer(c_int) :: w, h
        end function
        real(c_float) function SDL_GetWindowDisplayScale(win) &
                bind(C, name="SDL_GetWindowDisplayScale")
            import :: c_ptr, c_float
            type(c_ptr), value :: win
        end function
        logical(c_bool) function SDL_StartTextInput(win) bind(C, name="SDL_StartTextInput")
            import :: c_ptr, c_bool
            type(c_ptr), value :: win
        end function
        logical(c_bool) function SDL_PollEvent(ev) bind(C, name="SDL_PollEvent")
            import :: c_bool, c_int8_t
            integer(c_int8_t) :: ev(128)
        end function
        logical(c_bool) function SDL_WaitEvent(ev) bind(C, name="SDL_WaitEvent")
            import :: c_bool, c_int8_t
            integer(c_int8_t) :: ev(128)
        end function
        logical(c_bool) function SDL_WaitEventTimeout(ev, ms) bind(C, name="SDL_WaitEventTimeout")
            import :: c_bool, c_int8_t, c_int32_t
            integer(c_int8_t) :: ev(128)
            integer(c_int32_t), value :: ms
        end function
        integer(c_int64_t) function SDL_GetTicksNS() bind(C, name="SDL_GetTicksNS")
            import :: c_int64_t
        end function
        type(c_ptr) function SDL_CreateGPUDevice(formats, debug, name) &
                bind(C, name="SDL_CreateGPUDevice")
            import :: c_ptr, c_int32_t, c_bool
            integer(c_int32_t), value :: formats
            logical(c_bool), value :: debug
            type(c_ptr), value :: name
        end function
        subroutine SDL_DestroyGPUDevice(d) bind(C, name="SDL_DestroyGPUDevice")
            import :: c_ptr
            type(c_ptr), value :: d
        end subroutine
        logical(c_bool) function SDL_ClaimWindowForGPUDevice(d, w) &
                bind(C, name="SDL_ClaimWindowForGPUDevice")
            import :: c_ptr, c_bool
            type(c_ptr), value :: d, w
        end function
        subroutine SDL_ReleaseWindowFromGPUDevice(d, w) &
                bind(C, name="SDL_ReleaseWindowFromGPUDevice")
            import :: c_ptr
            type(c_ptr), value :: d, w
        end subroutine
        integer(c_int32_t) function SDL_GetGPUSwapchainTextureFormat(d, w) &
                bind(C, name="SDL_GetGPUSwapchainTextureFormat")
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: d, w
        end function
        type(c_ptr) function SDL_CreateGPUShader(d, info) bind(C, name="SDL_CreateGPUShader")
            import :: c_ptr, shader_info_t
            type(c_ptr), value :: d
            type(shader_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUShader(d, s) bind(C, name="SDL_ReleaseGPUShader")
            import :: c_ptr
            type(c_ptr), value :: d, s
        end subroutine
        type(c_ptr) function SDL_CreateGPUGraphicsPipeline(d, info) &
                bind(C, name="SDL_CreateGPUGraphicsPipeline")
            import :: c_ptr, pipeline_info_t
            type(c_ptr), value :: d
            type(pipeline_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUGraphicsPipeline(d, p) &
                bind(C, name="SDL_ReleaseGPUGraphicsPipeline")
            import :: c_ptr
            type(c_ptr), value :: d, p
        end subroutine
        type(c_ptr) function SDL_CreateGPUBuffer(d, info) bind(C, name="SDL_CreateGPUBuffer")
            import :: c_ptr, buffer_info_t
            type(c_ptr), value :: d
            type(buffer_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUBuffer(d, b) bind(C, name="SDL_ReleaseGPUBuffer")
            import :: c_ptr
            type(c_ptr), value :: d, b
        end subroutine
        type(c_ptr) function SDL_CreateGPUTransferBuffer(d, info) &
                bind(C, name="SDL_CreateGPUTransferBuffer")
            import :: c_ptr, buffer_info_t
            type(c_ptr), value :: d
            type(buffer_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUTransferBuffer(d, b) bind(C, name="SDL_ReleaseGPUTransferBuffer")
            import :: c_ptr
            type(c_ptr), value :: d, b
        end subroutine
        type(c_ptr) function SDL_MapGPUTransferBuffer(d, b, cycle) &
                bind(C, name="SDL_MapGPUTransferBuffer")
            import :: c_ptr, c_bool
            type(c_ptr), value :: d, b
            logical(c_bool), value :: cycle
        end function
        subroutine SDL_UnmapGPUTransferBuffer(d, b) bind(C, name="SDL_UnmapGPUTransferBuffer")
            import :: c_ptr
            type(c_ptr), value :: d, b
        end subroutine
        type(c_ptr) function SDL_CreateGPUTexture(d, info) bind(C, name="SDL_CreateGPUTexture")
            import :: c_ptr, texture_info_t
            type(c_ptr), value :: d
            type(texture_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUTexture(d, t) bind(C, name="SDL_ReleaseGPUTexture")
            import :: c_ptr
            type(c_ptr), value :: d, t
        end subroutine
        type(c_ptr) function SDL_CreateGPUSampler(d, info) bind(C, name="SDL_CreateGPUSampler")
            import :: c_ptr, sampler_info_t
            type(c_ptr), value :: d
            type(sampler_info_t) :: info
        end function
        subroutine SDL_ReleaseGPUSampler(d, s) bind(C, name="SDL_ReleaseGPUSampler")
            import :: c_ptr
            type(c_ptr), value :: d, s
        end subroutine
        type(c_ptr) function SDL_AcquireGPUCommandBuffer(d) &
                bind(C, name="SDL_AcquireGPUCommandBuffer")
            import :: c_ptr
            type(c_ptr), value :: d
        end function
        logical(c_bool) function SDL_SubmitGPUCommandBuffer(c) &
                bind(C, name="SDL_SubmitGPUCommandBuffer")
            import :: c_ptr, c_bool
            type(c_ptr), value :: c
        end function
        type(c_ptr) function SDL_SubmitGPUCommandBufferAndAcquireFence(c) &
                bind(C, name="SDL_SubmitGPUCommandBufferAndAcquireFence")
            import :: c_ptr
            type(c_ptr), value :: c
        end function
        logical(c_bool) function SDL_WaitForGPUFences(d, all, fences, n) &
                bind(C, name="SDL_WaitForGPUFences")
            import :: c_ptr, c_bool, c_int32_t
            type(c_ptr), value :: d
            logical(c_bool), value :: all
            type(c_ptr) :: fences(*)
            integer(c_int32_t), value :: n
        end function
        subroutine SDL_ReleaseGPUFence(d, f) bind(C, name="SDL_ReleaseGPUFence")
            import :: c_ptr
            type(c_ptr), value :: d, f
        end subroutine
        logical(c_bool) function SDL_WaitForGPUIdle(d) bind(C, name="SDL_WaitForGPUIdle")
            import :: c_ptr, c_bool
            type(c_ptr), value :: d
        end function
        logical(c_bool) function SDL_WaitAndAcquireGPUSwapchainTexture(c, w, tex, tw, th) &
                bind(C, name="SDL_WaitAndAcquireGPUSwapchainTexture")
            import :: c_ptr, c_bool, c_int32_t
            type(c_ptr), value :: c, w
            type(c_ptr) :: tex
            integer(c_int32_t) :: tw, th
        end function
        type(c_ptr) function SDL_BeginGPUCopyPass(c) bind(C, name="SDL_BeginGPUCopyPass")
            import :: c_ptr
            type(c_ptr), value :: c
        end function
        subroutine SDL_UploadToGPUBuffer(p, src, dst, cycle) bind(C, name="SDL_UploadToGPUBuffer")
            import :: c_ptr, xfer_location_t, buffer_region_t, c_bool
            type(c_ptr), value :: p
            type(xfer_location_t) :: src
            type(buffer_region_t) :: dst
            logical(c_bool), value :: cycle
        end subroutine
        subroutine SDL_UploadToGPUTexture(p, src, dst, cycle) &
                bind(C, name="SDL_UploadToGPUTexture")
            import :: c_ptr, texture_xfer_t, texture_region_t, c_bool
            type(c_ptr), value :: p
            type(texture_xfer_t) :: src
            type(texture_region_t) :: dst
            logical(c_bool), value :: cycle
        end subroutine
        subroutine SDL_DownloadFromGPUTexture(p, src, dst) &
                bind(C, name="SDL_DownloadFromGPUTexture")
            import :: c_ptr, texture_region_t, texture_xfer_t
            type(c_ptr), value :: p
            type(texture_region_t) :: src
            type(texture_xfer_t) :: dst
        end subroutine
        subroutine SDL_EndGPUCopyPass(p) bind(C, name="SDL_EndGPUCopyPass")
            import :: c_ptr
            type(c_ptr), value :: p
        end subroutine
        type(c_ptr) function SDL_BeginGPURenderPass(c, targets, n, depth) &
                bind(C, name="SDL_BeginGPURenderPass")
            import :: c_ptr, color_target_t, c_int32_t
            type(c_ptr), value :: c
            type(color_target_t) :: targets(*)
            integer(c_int32_t), value :: n
            type(c_ptr), value :: depth
        end function
        subroutine SDL_EndGPURenderPass(p) bind(C, name="SDL_EndGPURenderPass")
            import :: c_ptr
            type(c_ptr), value :: p
        end subroutine
        subroutine SDL_BindGPUGraphicsPipeline(p, pipe) bind(C, name="SDL_BindGPUGraphicsPipeline")
            import :: c_ptr
            type(c_ptr), value :: p, pipe
        end subroutine
        subroutine SDL_SetGPUViewport(p, vp) bind(C, name="SDL_SetGPUViewport")
            import :: c_ptr, viewport_t
            type(c_ptr), value :: p
            type(viewport_t) :: vp
        end subroutine
        subroutine SDL_SetGPUScissor(p, r) bind(C, name="SDL_SetGPUScissor")
            import :: c_ptr, sdl_rect_t
            type(c_ptr), value :: p
            type(sdl_rect_t) :: r
        end subroutine
        subroutine SDL_BindGPUVertexStorageBuffers(p, first, bufs, n) &
                bind(C, name="SDL_BindGPUVertexStorageBuffers")
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: p
            integer(c_int32_t), value :: first, n
            type(c_ptr) :: bufs(*)
        end subroutine
        subroutine SDL_BindGPUVertexBuffers(p, first, b, n) bind(C, name="SDL_BindGPUVertexBuffers")
            import :: c_ptr, c_int32_t, buffer_binding_t
            type(c_ptr), value :: p
            integer(c_int32_t), value :: first, n
            type(buffer_binding_t) :: b(*)
        end subroutine
        subroutine SDL_BindGPUIndexBuffer(p, b, size) bind(C, name="SDL_BindGPUIndexBuffer")
            import :: c_ptr, c_int32_t, buffer_binding_t
            type(c_ptr), value :: p
            type(buffer_binding_t) :: b
            integer(c_int32_t), value :: size
        end subroutine
        subroutine SDL_BindGPUFragmentSamplers(p, first, b, n) &
                bind(C, name="SDL_BindGPUFragmentSamplers")
            import :: c_ptr, c_int32_t, sampler_binding_t
            type(c_ptr), value :: p
            integer(c_int32_t), value :: first, n
            type(sampler_binding_t) :: b(*)
        end subroutine
        subroutine SDL_PushGPUVertexUniformData(c, slot, data, length) &
                bind(C, name="SDL_PushGPUVertexUniformData")
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: c, data
            integer(c_int32_t), value :: slot, length
        end subroutine
        subroutine SDL_DrawGPUPrimitives(p, nv, ni, fv, fi) bind(C, name="SDL_DrawGPUPrimitives")
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: p
            integer(c_int32_t), value :: nv, ni, fv, fi
        end subroutine
        subroutine SDL_DrawGPUIndexedPrimitives(p, nidx, ni, fidx, voff, fi) &
                bind(C, name="SDL_DrawGPUIndexedPrimitives")
            import :: c_ptr, c_int32_t
            type(c_ptr), value :: p
            integer(c_int32_t), value :: nidx, ni, fidx, voff, fi
        end subroutine
        logical(c_bool) function TTF_Init() bind(C, name="TTF_Init")
            import :: c_bool
        end function
        type(c_ptr) function TTF_OpenFont(file, size) bind(C, name="TTF_OpenFont")
            import :: c_ptr, c_char, c_float
            character(kind=c_char), intent(in) :: file(*)
            real(c_float), value :: size
        end function
        subroutine TTF_CloseFont(f) bind(C, name="TTF_CloseFont")
            import :: c_ptr
            type(c_ptr), value :: f
        end subroutine
        subroutine TTF_SetFontHinting(f, h) bind(C, name="TTF_SetFontHinting")
            import :: c_ptr, c_int
            type(c_ptr), value :: f
            integer(c_int), value :: h
        end subroutine
        integer(c_int) function TTF_GetFontHeight(f) bind(C, name="TTF_GetFontHeight")
            import :: c_ptr, c_int
            type(c_ptr), value :: f
        end function
        integer(c_int) function TTF_GetFontAscent(f) bind(C, name="TTF_GetFontAscent")
            import :: c_ptr, c_int
            type(c_ptr), value :: f
        end function
        logical(c_bool) function TTF_GetStringSize(f, text, length, w, h) &
                bind(C, name="TTF_GetStringSize")
            import :: c_ptr, c_bool, c_char, c_size_t, c_int
            type(c_ptr), value :: f
            character(kind=c_char), intent(in) :: text(*)
            integer(c_size_t), value :: length
            integer(c_int) :: w, h
        end function
        logical(c_bool) function TTF_GetGlyphMetrics(f, ch, minx, maxx, miny, maxy, adv) &
                bind(C, name="TTF_GetGlyphMetrics")
            import :: c_ptr, c_bool, c_int32_t, c_int
            type(c_ptr), value :: f
            integer(c_int32_t), value :: ch
            integer(c_int) :: minx, maxx, miny, maxy, adv
        end function
        type(c_ptr) function TTF_CreateGPUTextEngine(d) bind(C, name="TTF_CreateGPUTextEngine")
            import :: c_ptr
            type(c_ptr), value :: d
        end function
        subroutine TTF_DestroyGPUTextEngine(e) bind(C, name="TTF_DestroyGPUTextEngine")
            import :: c_ptr
            type(c_ptr), value :: e
        end subroutine
        type(c_ptr) function TTF_CreateText(e, f, text, length) bind(C, name="TTF_CreateText")
            import :: c_ptr, c_char, c_size_t
            type(c_ptr), value :: e, f
            character(kind=c_char), intent(in) :: text(*)
            integer(c_size_t), value :: length
        end function
        subroutine TTF_DestroyText(t) bind(C, name="TTF_DestroyText")
            import :: c_ptr
            type(c_ptr), value :: t
        end subroutine
        type(c_ptr) function TTF_GetGPUTextDrawData(t) bind(C, name="TTF_GetGPUTextDrawData")
            import :: c_ptr
            type(c_ptr), value :: t
        end function
        integer(c_size_t) function c_strlen(s) bind(C, name="strlen")
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
        end function
    end interface

contains

    function sb_name(self) result(name)
        class(sdl_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
        name = "sdl"
        if (self%offscreen) name = "sdl-offscreen"
    end function sb_name

    function sb_caps(self) result(caps)
        class(sdl_backend_t), intent(in) :: self
        type(ui_backend_caps_t) :: caps
        caps%graphical = .true.
        caps%canvas_layers = .true.
        caps%proportional_text = .true.
        caps%event_waiting = .not. self%offscreen
        caps%high_dpi = .true.
        caps%pointer = .true.
        caps%text_entry = .true.
    end function sb_caps

    logical function sdl_is_available()
        !! A GPU device can be created (and a display reached, unless headless
        !! tests ask for none with FORTUI_HEADLESS=1).
        character(len=8) :: v
        integer :: n, st
        type(c_ptr) :: d
        sdl_is_available = .false.
        call get_environment_variable("FORTUI_HEADLESS", v, n, st)
        if (st == 0 .and. trim(v) == "1") return
        if (.not. SDL_Init(SDL_INIT_VIDEO)) return
        d = SDL_CreateGPUDevice(FORMAT_SPIRV, .false._c_bool, c_null_ptr)
        sdl_is_available = c_associated(d)
        if (c_associated(d)) call SDL_DestroyGPUDevice(d)
    end function sdl_is_available

    function sdl_error() result(msg)
        character(len=:), allocatable :: msg
        msg = f_str(SDL_GetError())
    end function sdl_error

    logical function sb_init(self)
        class(sdl_backend_t), intent(inout) :: self
        integer(c_int) :: w, h

        sb_init = .false.
        if (.not. SDL_Init(SDL_INIT_VIDEO)) then
            call report_error("fortui_gui_sdl", "init", "SDL_Init: " // sdl_error())
            return
        end if
        if (.not. TTF_Init()) then
            call report_error("fortui_gui_sdl", "init", "TTF_Init: " // sdl_error())
            return
        end if
        self%device = SDL_CreateGPUDevice(FORMAT_SPIRV, .false._c_bool, c_null_ptr)
        if (.not. c_associated(self%device)) then
            call report_error("fortui_gui_sdl", "init", "no GPU device: " // sdl_error())
            return
        end if
        if (self%offscreen) then
            self%pw = self%config%width
            self%ph = self%config%height
            self%format = TEX_RGBA8
            self%target = SDL_CreateGPUTexture(self%device, texture_info_t(type=TEX_2D, &
                format=TEX_RGBA8, usage=ior(TEXUSE_TARGET, TEXUSE_SAMPLER), &
                width=self%pw, height=self%ph))
        else
            self%window = SDL_CreateWindow(trim(self%config%title) // c_null_char, &
                int(self%config%width, c_int), int(self%config%height, c_int), &
                ior(WIN_RESIZABLE, WIN_HIGH_DENSITY))
            if (.not. c_associated(self%window)) then
                call report_error("fortui_gui_sdl", "init", "window: " // sdl_error())
                return
            end if
            if (.not. SDL_ClaimWindowForGPUDevice(self%device, self%window)) then
                call report_error("fortui_gui_sdl", "init", "swapchain: " // sdl_error())
                return
            end if
            self%format = SDL_GetGPUSwapchainTextureFormat(self%device, self%window)
            if (SDL_StartTextInput(self%window)) continue
            if (SDL_GetWindowSizeInPixels(self%window, w, h)) then
                self%pw = int(w)
                self%ph = int(h)
            end if
        end if
        self%engine = TTF_CreateGPUTextEngine(self%device)
        if (.not. make_pipelines(self)) return
        self%nearest = SDL_CreateGPUSampler(self%device, sampler_info_t(min_filter= &
            FILTER_NEAREST, mag_filter=FILTER_NEAREST, address_u=ADDR_CLAMP, &
            address_v=ADDR_CLAMP, address_w=ADDR_CLAMP))
        self%linear = SDL_CreateGPUSampler(self%device, sampler_info_t(min_filter= &
            FILTER_LINEAR, mag_filter=FILTER_LINEAR, address_u=ADDR_CLAMP, &
            address_v=ADDR_CLAMP, address_w=ADDR_CLAMP))
        allocate(self%queue(128, 256), self%texts(1024), self%layers(8), self%batches(64))
        allocate(self%shapes(SHAPE_FLOATS, 1024), self%verts(VERTEX_FLOATS, 4096), &
            self%idx(6144))
        call update_scale(self)
        self%active = .true.
        sb_init = .true.
    end function sb_init

    subroutine sb_shutdown(self)
        class(sdl_backend_t), intent(inout) :: self
        integer :: k
        if (.not. self%active) return
        if (SDL_WaitForGPUIdle(self%device)) continue
        do k = 1, size(self%texts)
            if (c_associated(self%texts(k)%text)) call TTF_DestroyText(self%texts(k)%text)
        end do
        do k = 1, nfonts
            call TTF_CloseFont(fonts(k)%font)
        end do
        nfonts = 0
        do k = 1, size(self%layers)
            call free_layer(self, self%layers(k))
        end do
        if (c_associated(self%engine)) call TTF_DestroyGPUTextEngine(self%engine)
        call release_buffer(self, self%shape_buf)
        call release_buffer(self, self%vtx_buf)
        call release_buffer(self, self%idx_buf)
        if (c_associated(self%upload)) call SDL_ReleaseGPUTransferBuffer(self%device, self%upload)
        if (c_associated(self%shape_pipe)) call SDL_ReleaseGPUGraphicsPipeline(self%device, &
            self%shape_pipe)
        if (c_associated(self%tex_pipe)) call SDL_ReleaseGPUGraphicsPipeline(self%device, &
            self%tex_pipe)
        call SDL_ReleaseGPUSampler(self%device, self%nearest)
        call SDL_ReleaseGPUSampler(self%device, self%linear)
        if (c_associated(self%target)) call SDL_ReleaseGPUTexture(self%device, self%target)
        if (c_associated(self%window)) then
            call SDL_ReleaseWindowFromGPUDevice(self%device, self%window)
            call SDL_DestroyWindow(self%window)
        end if
        call SDL_DestroyGPUDevice(self%device)
        measuring = .false.
        self%active = .false.
    end subroutine sb_shutdown

    subroutine release_buffer(self, b)
        type(sdl_backend_t), intent(inout) :: self
        type(c_ptr), intent(inout) :: b
        if (c_associated(b)) call SDL_ReleaseGPUBuffer(self%device, b)
        b = c_null_ptr
    end subroutine release_buffer

    logical function sb_should_close(self)
        class(sdl_backend_t), intent(in) :: self
        sb_should_close = self%close_requested
    end function sb_should_close

    ! --- pipelines -----------------------------------------------------------------

    type(c_ptr) function make_shader(self, code, stage, samplers, storage, uniforms) result(sh)
        type(sdl_backend_t), intent(inout) :: self
        integer(int8), intent(in), target :: code(:)
        integer(c_int32_t), intent(in) :: stage, samplers, storage, uniforms
        character(kind=c_char, len=5), target :: entry
        type(shader_info_t) :: info
        entry = "main" // c_null_char
        info%code_size = size(code, kind=c_size_t)
        info%code = c_loc(code)
        info%entrypoint = c_loc(entry)
        info%format = FORMAT_SPIRV
        info%stage = stage
        info%num_samplers = samplers
        info%num_storage_buffers = storage
        info%num_uniform_buffers = uniforms
        sh = SDL_CreateGPUShader(self%device, info)
        if (.not. c_associated(sh)) call report_error("fortui_gui_sdl", "shader", sdl_error())
    end function make_shader

    logical function make_pipelines(self) result(ok)
        type(sdl_backend_t), intent(inout) :: self
        integer(int8), allocatable, target :: sv(:), sf(:), tv(:), tf(:)
        type(c_ptr) :: vs, fs
        type(pipeline_info_t), target :: info
        type(ct_desc_t), target :: ct(1)
        type(vb_desc_t), target :: vb(1)
        type(vattr_t), target :: va(3)

        ok = .false.
        sv = shape_vert_spv
        sf = shape_frag_spv
        tv = textured_vert_spv
        tf = textured_frag_spv
        ct(1)%format = self%format
        ct(1)%blend = blend_t(src_color=BLEND_ONE, dst_color=BLEND_ONE_MINUS_SRC_ALPHA, &
            color_op=BLEND_ADD, src_alpha=BLEND_ONE, dst_alpha=BLEND_ONE_MINUS_SRC_ALPHA, &
            alpha_op=BLEND_ADD, write_mask=15_c_int8_t, enable_blend=.true._c_bool)
        info%target%descs = c_loc(ct)
        info%target%ndescs = 1

        vs = make_shader(self, sv, STAGE_VERTEX, 0, 1, 1)
        fs = make_shader(self, sf, STAGE_FRAGMENT, 0, 0, 0)
        if (.not. (c_associated(vs) .and. c_associated(fs))) return
        info%vs = vs
        info%fs = fs
        self%shape_pipe = SDL_CreateGPUGraphicsPipeline(self%device, info)
        call SDL_ReleaseGPUShader(self%device, vs)
        call SDL_ReleaseGPUShader(self%device, fs)

        vs = make_shader(self, tv, STAGE_VERTEX, 0, 0, 1)
        fs = make_shader(self, tf, STAGE_FRAGMENT, 1, 0, 0)
        if (.not. (c_associated(vs) .and. c_associated(fs))) return
        vb(1) = vb_desc_t(slot=0, pitch=4 * VERTEX_FLOATS)
        va(1) = vattr_t(location=0, buffer_slot=0, format=VFMT_FLOAT2, offset=0)
        va(2) = vattr_t(location=1, buffer_slot=0, format=VFMT_FLOAT2, offset=8)
        va(3) = vattr_t(location=2, buffer_slot=0, format=VFMT_FLOAT4, offset=16)
        info%vs = vs
        info%fs = fs
        info%vinput = vinput_t(descs=c_loc(vb), ndescs=1, attrs=c_loc(va), nattrs=3)
        self%tex_pipe = SDL_CreateGPUGraphicsPipeline(self%device, info)
        call SDL_ReleaseGPUShader(self%device, vs)
        call SDL_ReleaseGPUShader(self%device, fs)
        ok = c_associated(self%shape_pipe) .and. c_associated(self%tex_pipe)
        if (.not. ok) call report_error("fortui_gui_sdl", "pipeline", sdl_error())
    end function make_pipelines

    ! --- scale and fonts -----------------------------------------------------------

    subroutine update_scale(self)
        !! Pixels per logical unit: the display scale (the desktop's UI scale).
        type(sdl_backend_t), intent(inout) :: self
        integer(c_int) :: w, h
        real :: sc
        if (self%offscreen) then
            self%scale = 1.0
            return
        end if
        if (SDL_GetWindowSizeInPixels(self%window, w, h)) then
            self%pw = max(1, int(w))
            self%ph = max(1, int(h))
        end if
        sc = real(SDL_GetWindowDisplayScale(self%window))
        if (sc <= 0.0) sc = 1.0
        self%scale = sc
        px_scale = sc
    end subroutine update_scale

    integer function font_slot(face, px) result(k)
        !! Font of a theme face at `px` pixels (opened once, kept).
        integer, intent(in) :: face, px
        character(len=:), allocatable :: path
        logical :: pixel
        integer :: size_px

        if (font_theme /= theme%name) call close_font_cache()
        size_px = max(1, px)
        do k = 1, nfonts
            if (fonts(k)%face == face .and. fonts(k)%px == size_px) return
        end do
        if (nfonts == size(fonts)) call close_font_cache()
        call font_for(theme%fonts(face), face, size_px, theme%name, path, pixel)
        k = nfonts + 1
        fonts(k)%face = face
        fonts(k)%px = size_px
        if (len(path) > 0) fonts(k)%font = TTF_OpenFont(path // c_null_char, &
            real(size_px, c_float))
        if (.not. c_associated(fonts(k)%font)) then
            call report_error("fortui_gui_sdl", "font", "cannot open '" // path // "': " // &
                sdl_error())
            k = 0
            return
        end if
        if (pixel .or. theme%fonts(face)%pixel) then
            call TTF_SetFontHinting(fonts(k)%font, HINT_MONO)
        else
            call TTF_SetFontHinting(fonts(k)%font, HINT_LIGHT)
        end if
        fonts(k)%height = int(TTF_GetFontHeight(fonts(k)%font))
        fonts(k)%ascent = int(TTF_GetFontAscent(fonts(k)%font))
        nfonts = k
        font_theme = theme%name
    end function font_slot

    subroutine close_fonts(self)
        !! Forget the backend's text objects, then the fonts.
        type(sdl_backend_t), intent(inout) :: self
        integer :: k
        if (allocated(self%texts)) then
            do k = 1, size(self%texts)
                if (c_associated(self%texts(k)%text)) call TTF_DestroyText(self%texts(k)%text)
                self%texts(k) = text_entry_t()
            end do
        end if
        call close_font_cache()
    end subroutine close_fonts

    subroutine close_font_cache()
        integer :: k
        do k = 1, nfonts
            if (c_associated(fonts(k)%font)) call TTF_CloseFont(fonts(k)%font)
            fonts(k) = font_slot_t()
        end do
        nfonts = 0
        font_theme = theme%name
    end subroutine close_font_cache

    integer function face_px(face, size) result(px)
        !! Pixel size for a logical size: pixel fonts snap to their design grid.
        integer, intent(in) :: face
        real, intent(in) :: size
        real :: grid
        px = max(1, nint(size))
        grid = theme%fonts(face)%grid
        if (theme%fonts(face)%pixel .and. grid > 0.0) px = nint(grid) * max(1, nint(size / grid))
    end function face_px

    subroutine sb_metrics(self)
        class(sdl_backend_t), intent(inout) :: self
        measuring = .true.
        px_scale = self%scale
        call close_fonts(self)
        call text_use_measurement(measure_width, measure_advance, theme%line_factor)
    end subroutine sb_metrics

    real function measure_width(s, size, style) result(w)
        character(*), intent(in) :: s
        real, intent(in) :: size
        integer, intent(in) :: style
        integer :: k, face
        integer(c_int) :: pw, ph
        w = 0.0
        if (.not. measuring .or. len(s) == 0) return
        face = paint_face(style)
        k = font_slot(face, face_px(face, size * px_scale))
        if (k == 0) return
        if (TTF_GetStringSize(fonts(k)%font, s, int(len(s), c_size_t), pw, ph)) &
            w = real(pw) / px_scale
    end function measure_width

    real function measure_advance(cp, size, style) result(adv)
        integer, intent(in) :: cp, style
        real, intent(in) :: size
        integer :: k, face
        integer(c_int) :: a, b, c, d, e
        adv = 0.0
        if (.not. measuring) return
        face = paint_face(style)
        k = font_slot(face, face_px(face, size * px_scale))
        if (k == 0) return
        if (TTF_GetGlyphMetrics(fonts(k)%font, int(cp, c_int32_t), a, b, c, d, e)) &
            adv = real(e) / px_scale
    end function measure_advance

    ! --- input ---------------------------------------------------------------------

    subroutine sb_poll(self, input, wait)
        !! Give the queued events to the frame; block for the next one when the
        !! runtime allows idle waiting and nothing is queued.
        class(sdl_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait
        integer(c_int8_t) :: ev(128)
        integer :: ms

        if (.not. self%active) return
        call input_set_time(input, real(SDL_GetTicksNS(), kind(1.0d0)) * 1.0d-9)
        do while (SDL_PollEvent(ev))
            call enqueue(self, ev)
        end do
        if (wait .and. self%qcount == 0 .and. .not. self%close_requested .and. &
            .not. self%offscreen) then
            self%waits = self%waits + 1
            if (self%wake_in >= 0.0) then
                ms = max(0, nint(self%wake_in * 1000.0))
                if (SDL_WaitEventTimeout(ev, int(ms, c_int32_t))) call enqueue(self, ev)
            else
                if (SDL_WaitEvent(ev)) call enqueue(self, ev)
            end if
            do while (SDL_PollEvent(ev))
                call enqueue(self, ev)
            end do
            call input_set_time(input, real(SDL_GetTicksNS(), kind(1.0d0)) * 1.0d-9)
        end if
        call apply_events(self, input)
        input%width = max(1, nint(real(self%pw) / self%scale))
        input%height = max(1, nint(real(self%ph) / self%scale))
        input%scale = self%scale
    end subroutine sb_poll

    subroutine enqueue(self, ev)
        type(sdl_backend_t), intent(inout) :: self
        integer(c_int8_t), intent(in) :: ev(128)
        integer :: slot
        if (self%qcount == size(self%queue, 2)) then
            ! Full: drop the oldest motion-like event.
            self%qhead = modulo(self%qhead, size(self%queue, 2)) + 1
            self%qcount = self%qcount - 1
        end if
        slot = modulo(self%qhead - 1 + self%qcount, size(self%queue, 2)) + 1
        self%queue(:, slot) = ev
        self%qcount = self%qcount + 1
    end subroutine enqueue

    subroutine apply_events(self, input)
        type(sdl_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        integer :: kind, button
        logical :: down
        real :: x, y

        do while (self%qcount > 0)
            associate(ev => self%queue(:, self%qhead))
                kind = u32(ev, 0)
                select case (kind)
                case (EV_QUIT, EV_WIN_CLOSE)
                    self%close_requested = .true.
                case (EV_WIN_RESIZED, EV_WIN_PIXELS, EV_WIN_SCALE)
                    call update_scale(self)
                    input%resized = .true.
                case (EV_WIN_EXPOSED)
                    input%resized = .true.
                case (EV_MOTION)
                    call to_logical(self, f32(ev, 28), f32(ev, 32), x, y)
                    call input_update_pointer(input, x, y, self%pointer_down)
                case (EV_BUTTON_DOWN, EV_BUTTON_UP)
                    ! Button at byte 24: only the left button drives widgets.
                    button = iand(int(ev(25)), 255)
                    if (button /= 1) then
                        call drop_head(self)
                        cycle
                    end if
                    down = kind == EV_BUTTON_DOWN
                    call to_logical(self, f32(ev, 28), f32(ev, 32), x, y)
                    self%pointer_down = down
                    call input_update_pointer(input, x, y, down)
                case (EV_WIN_LEAVE)
                    if (.not. self%pointer_down) call input_update_pointer(input, -1.0, -1.0, &
                        .false.)
                case (EV_WHEEL)
                    if (abs(f32(ev, 28)) > 0.0) call input_scroll(input, &
                        nint(sign(1.0, f32(ev, 28))), f32(ev, 28))
                case (EV_KEY_DOWN)
                    call key_event(input, ev)
                case (EV_TEXT)
                    call input_type_text(input, f_str(ptr_at(ev, 24)))
                end select
            end associate
            call drop_head(self)
        end do
    end subroutine apply_events

    subroutine drop_head(self)
        type(sdl_backend_t), intent(inout) :: self
        self%qhead = modulo(self%qhead, size(self%queue, 2)) + 1
        self%qcount = self%qcount - 1
    end subroutine drop_head

    subroutine to_logical(self, wx, wy, x, y)
        !! Window coordinates (points) to logical units.
        type(sdl_backend_t), intent(in) :: self
        real, intent(in) :: wx, wy
        real, intent(out) :: x, y
        integer(c_int) :: w, h
        real :: density
        density = 1.0
        if (c_associated(self%window)) then
            if (SDL_GetWindowSize(self%window, w, h)) then
                if (w > 0) density = real(self%pw) / real(w)
            end if
        end if
        x = wx * density / self%scale
        y = wy * density / self%scale
    end subroutine to_logical

    subroutine key_event(input, ev)
        type(input_state_t), intent(inout) :: input
        integer(c_int8_t), intent(in) :: ev(128)
        integer :: key, sym, mods, m
        logical :: rep
        sym = u32(ev, 28)
        m = u16(ev, 32)
        rep = ev(38) /= 0
        mods = 0
        if (iand(m, int(z'00C0')) /= 0) mods = ior(mods, MOD_CTRL)
        if (iand(m, int(z'0003')) /= 0) mods = ior(mods, MOD_SHIFT)
        if (iand(m, int(z'0300')) /= 0) mods = ior(mods, MOD_ALT)
        if (iand(m, int(z'0C00')) /= 0) mods = ior(mods, MOD_META)
        select case (sym)
        case (int(z'0D'), int(z'40000058')); key = KEY_ENTER
        case (int(z'1B')); key = KEY_ESCAPE
        case (int(z'08')); key = KEY_BACKSPACE
        case (int(z'09')); key = KEY_TAB
        case (int(z'20')); key = KEY_SPACE
        case (int(z'7F')); key = KEY_DELETE
        case (int(z'4000004F')); key = KEY_ARROW_RIGHT
        case (int(z'40000050')); key = KEY_ARROW_LEFT
        case (int(z'40000051')); key = KEY_ARROW_DOWN
        case (int(z'40000052')); key = KEY_ARROW_UP
        case (int(z'4000004A')); key = KEY_HOME
        case (int(z'4000004D')); key = KEY_END
        case (int(z'4000004B')); key = KEY_PAGE_UP
        case (int(z'4000004E')); key = KEY_PAGE_DOWN
        case (int(z'40000049')); key = KEY_INSERT
        case default; key = KEY_NONE
        end select
        if (key /= KEY_NONE) then
            call input_key_press(input, key, 0, mods, repeat=rep, widgets=.true.)
        else if (sym > 32 .and. sym < int(z'40000000') .and. &
                iand(mods, MOD_CTRL + MOD_ALT + MOD_META) /= 0) then
            call input_key_press(input, KEY_NONE, sym, mods, repeat=rep)
        end if
    end subroutine key_event

    ! --- frame ---------------------------------------------------------------------

    subroutine sb_present(self, frame, store)
        class(sdl_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        type(c_ptr) :: cmd, swap, pass
        integer(c_int32_t) :: tw, th
        integer :: k

        self%presents = self%presents + 1
        if (.not. self%active) return
        self%frame_no = self%frame_no + 1
        if (.not. self%offscreen) call update_scale(self)
        measuring = .true.
        call self%canvas%sync(store)
        call sync_layers(self, store)
        call paint_frame(frame, self%scale, real(self%pw), real(self%ph), self%list)
        self%nshapes = 0
        self%nverts = 0
        self%nidx = 0
        self%nbatches = 0
        self%clip = [0, 0, self%pw, self%ph]
        self%clip_depth = 0
        do k = 1, self%list%n
            call record(self, frame, store, k)
        end do
        call sweep_texts(self)

        cmd = SDL_AcquireGPUCommandBuffer(self%device)
        if (.not. c_associated(cmd)) return
        call upload_frame(self, cmd, store)
        if (self%offscreen) then
            swap = self%target
            tw = int(self%pw, c_int32_t)
            th = int(self%ph, c_int32_t)
        else
            swap = c_null_ptr
            if (.not. SDL_WaitAndAcquireGPUSwapchainTexture(cmd, self%window, swap, tw, th)) &
                swap = c_null_ptr
        end if
        if (c_associated(swap)) then
            pass = begin_pass(cmd, swap, self%list%background)
            call draw_batches(self, cmd, pass, real(tw), real(th))
            call SDL_EndGPURenderPass(pass)
        end if
        if (SDL_SubmitGPUCommandBuffer(cmd)) continue
    end subroutine sb_present

    type(c_ptr) function begin_pass(cmd, texture, background) result(pass)
        type(c_ptr), intent(in) :: cmd, texture
        integer(int32), intent(in) :: background
        type(color_target_t) :: t(1)
        real :: c(4)
        call unpack(background, c)
        t(1)%texture = texture
        t(1)%clear = real(c, c_float)
        t(1)%load_op = LOAD_CLEAR
        t(1)%store_op = STORE_STORE
        pass = SDL_BeginGPURenderPass(cmd, t, 1_c_int32_t, c_null_ptr)
    end function begin_pass

    subroutine record(self, frame, store, k)
        !! One display-list command into the frame's batches.
        type(sdl_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        integer, intent(in) :: k
        real :: c(4), d(4)

        associate(cm => self%list%cmds(k))
            select case (cm%kind)
            case (PAINT_RECT)
                call unpack(cm%fill, c)
                call unpack(cm%stroke, d)
                call add_shape(self, [cm%x, cm%y, cm%w, cm%h], c, d, &
                    [cm%radius, cm%border, 0.0, merge(1.0, 0.0, cm%pattern == PATTERN_CHECKER)])
            case (PAINT_LINE)
                call unpack(cm%fill, c)
                call add_shape(self, [cm%x, cm%y, cm%w, cm%h], c, c, [0.0, cm%border, 1.0, 0.0])
            case (PAINT_TEXT)
                call add_text(self, self%list%text_of(k), cm%x, cm%y, cm%h, cm%face, cm%size, &
                    cm%fill)
            case (PAINT_CLIP)
                if (self%clip_depth < size(self%clip_stack, 2)) then
                    self%clip_depth = self%clip_depth + 1
                    self%clip_stack(:, self%clip_depth) = self%clip
                end if
                self%clip = intersect(self%clip, [nint(cm%x), nint(cm%y), nint(cm%w), &
                    nint(cm%h)])
            case (PAINT_UNCLIP)
                if (self%clip_depth > 0) then
                    self%clip = self%clip_stack(:, self%clip_depth)
                    self%clip_depth = self%clip_depth - 1
                end if
            case (PAINT_CANVAS)
                call record_canvas(self, frame, store, cm%node, cm%x, cm%y, cm%w, cm%h, cm%fill)
            end select
        end associate
    end subroutine record

    pure function intersect(a, b) result(r)
        integer, intent(in) :: a(4), b(4)
        integer :: r(4), x0, y0, x1, y1
        x0 = max(a(1), b(1))
        y0 = max(a(2), b(2))
        x1 = min(a(1) + a(3), b(1) + b(3))
        y1 = min(a(2) + a(4), b(2) + b(4))
        r = [x0, y0, max(0, x1 - x0), max(0, y1 - y0)]
    end function intersect

    subroutine unpack(c, out)
        !! ui_rgba to 0..1 floats.
        integer(int32), intent(in) :: c
        real, intent(out) :: out(4)
        integer :: k
        do k = 1, 4
            out(k) = real(iand(ishft(c, -8 * (k - 1)), 255_int32)) / 255.0
        end do
    end subroutine unpack

    integer function open_batch(self, kind, texture, sampler) result(b)
        !! The current batch when it matches, else a new one.
        type(sdl_backend_t), intent(inout) :: self
        integer, intent(in) :: kind
        type(c_ptr), intent(in) :: texture, sampler
        type(batch_t), allocatable :: grown(:)
        logical :: same
        b = self%nbatches
        if (b > 0) then
            same = self%batches(b)%kind == kind .and. all(self%batches(b)%clip == self%clip) &
                .and. kind /= BATCH_LAYER
            if (same .and. kind == BATCH_TEXTURED) same = &
                c_associated(self%batches(b)%texture, texture) .and. &
                c_associated(self%batches(b)%sampler, sampler)
            if (same) return
        end if
        if (self%nbatches == size(self%batches)) then
            allocate(grown(2 * size(self%batches)))
            grown(1:self%nbatches) = self%batches(1:self%nbatches)
            call move_alloc(grown, self%batches)
        end if
        b = self%nbatches + 1
        self%nbatches = b
        self%batches(b) = batch_t(kind=kind, texture=texture, sampler=sampler, clip=self%clip)
        if (kind == BATCH_SHAPES) self%batches(b)%first = self%nshapes
        if (kind == BATCH_TEXTURED) self%batches(b)%first = self%nidx
        self%batches(b)%view = real([real(self%pw), real(self%ph), 0.0, 0.0, 1.0, 0.0, 0.0, &
            1.0, 0.0, 1.0, 0.0, 0.0], c_float)
    end function open_batch

    subroutine add_shape(self, geo, fill, stroke, p)
        type(sdl_backend_t), intent(inout) :: self
        real, intent(in) :: geo(4), fill(4), stroke(4), p(4)
        real(c_float), allocatable :: grown(:, :)
        integer :: b
        b = open_batch(self, BATCH_SHAPES, c_null_ptr, c_null_ptr)
        if (self%nshapes == size(self%shapes, 2)) then
            allocate(grown(SHAPE_FLOATS, 2 * size(self%shapes, 2)))
            grown(:, 1:self%nshapes) = self%shapes(:, 1:self%nshapes)
            call move_alloc(grown, self%shapes)
        end if
        self%nshapes = self%nshapes + 1
        self%shapes(:, self%nshapes) = real([geo, fill, stroke, p], c_float)
        self%batches(b)%count = self%batches(b)%count + 1
    end subroutine add_shape

    subroutine add_quad(self, texture, sampler, xy, uv, color)
        !! Two triangles with corners xy(:, 1..4) (clockwise from top-left).
        type(sdl_backend_t), intent(inout) :: self
        type(c_ptr), intent(in) :: texture, sampler
        real, intent(in) :: xy(2, 4), uv(2, 4), color(4)
        integer :: b, k, base
        b = open_batch(self, BATCH_TEXTURED, texture, sampler)
        call grow_vertices(self, 4, 6)
        base = self%nverts
        do k = 1, 4
            self%verts(:, base + k) = real([xy(:, k), uv(:, k), color], c_float)
        end do
        self%idx(self%nidx + 1:self%nidx + 6) = int(base + [0, 1, 2, 0, 2, 3], c_int32_t)
        self%nverts = base + 4
        self%nidx = self%nidx + 6
        self%batches(b)%count = self%batches(b)%count + 6
    end subroutine add_quad

    subroutine grow_vertices(self, nv, ni)
        type(sdl_backend_t), intent(inout) :: self
        integer, intent(in) :: nv, ni
        real(c_float), allocatable :: gv(:, :)
        integer(c_int32_t), allocatable :: gi(:)
        if (self%nverts + nv > size(self%verts, 2)) then
            allocate(gv(VERTEX_FLOATS, 2 * (size(self%verts, 2) + nv)))
            gv(:, 1:self%nverts) = self%verts(:, 1:self%nverts)
            call move_alloc(gv, self%verts)
        end if
        if (self%nidx + ni > size(self%idx)) then
            allocate(gi(2 * (size(self%idx) + ni)))
            gi(1:self%nidx) = self%idx(1:self%nidx)
            call move_alloc(gi, self%idx)
        end if
    end subroutine grow_vertices

    subroutine add_text(self, str, x, y, line_h, face, size_px, colour)
        !! Glyph quads of `str` with its line box at (x, y), whole pixels, drawn
        !! 1:1 from the glyph atlas.
        type(sdl_backend_t), intent(inout) :: self
        character(*), intent(in) :: str
        real, intent(in) :: x, y, line_h, size_px
        integer, intent(in) :: face
        integer(int32), intent(in) :: colour
        type(c_ptr) :: text, p
        type(draw_seq_t), pointer :: seq
        real(c_float), pointer :: xy(:, :), uv(:, :)
        integer(c_int), pointer :: ind(:)
        integer :: k, slot, b, base, i
        real :: top, c(4)

        slot = font_slot(face, face_px(face, size_px))
        if (slot == 0) return
        text = cached_text(self, slot, str)
        if (.not. c_associated(text)) return
        top = real(nint(y + 0.5 * (line_h - real(fonts(slot)%height))))
        call unpack(colour, c)
        p = TTF_GetGPUTextDrawData(text)
        do while (c_associated(p))
            call c_f_pointer(p, seq)
            call c_f_pointer(seq%xy, xy, [2, int(seq%num_vertices)])
            call c_f_pointer(seq%uv, uv, [2, int(seq%num_vertices)])
            call c_f_pointer(seq%indices, ind, [int(seq%num_indices)])
            b = open_batch(self, BATCH_TEXTURED, seq%atlas, self%nearest)
            call grow_vertices(self, int(seq%num_vertices), int(seq%num_indices))
            base = self%nverts
            do i = 1, int(seq%num_vertices)
                self%verts(:, base + i) = real([x + real(xy(1, i)), top - real(xy(2, i)), &
                    real(uv(1, i)), real(uv(2, i)), c], c_float)
            end do
            do k = 1, int(seq%num_indices)
                self%idx(self%nidx + k) = int(base + ind(k), c_int32_t)
            end do
            self%nverts = base + int(seq%num_vertices)
            self%nidx = self%nidx + int(seq%num_indices)
            self%batches(b)%count = self%batches(b)%count + int(seq%num_indices)
            p = seq%next
        end do
    end subroutine add_text

    recursive type(c_ptr) function cached_text(self, slot, str) result(text)
        !! The SDL_ttf text object of `str` in font `slot`, kept while it is drawn.
        type(sdl_backend_t), intent(inout) :: self
        integer, intent(in) :: slot
        character(*), intent(in) :: str
        integer(int64) :: h
        integer :: k, n, probe, free
        type(text_entry_t), allocatable :: old(:)

        h = hash(str, slot)
        n = size(self%texts)
        k = int(modulo(h, int(n, int64))) + 1
        free = 0
        do probe = 1, n
            if (.not. c_associated(self%texts(k)%text)) then
                free = k
                exit
            end if
            if (self%texts(k)%hash == h .and. self%texts(k)%slot == slot) then
                if (self%texts(k)%str == str) then
                    self%texts(k)%last = self%frame_no
                    text = self%texts(k)%text
                    return
                end if
            end if
            k = modulo(k, n) + 1
        end do
        if (free == 0) then
            ! Full: start over with a larger table.
            call move_alloc(self%texts, old)
            allocate(self%texts(2 * n))
            do k = 1, n
                if (c_associated(old(k)%text)) call TTF_DestroyText(old(k)%text)
            end do
            text = cached_text(self, slot, str)
            return
        end if
        text = TTF_CreateText(self%engine, fonts(slot)%font, str, int(len(str), c_size_t))
        self%texts(free)%hash = h
        self%texts(free)%slot = slot
        self%texts(free)%str = str
        self%texts(free)%text = text
        self%texts(free)%last = self%frame_no
    end function cached_text

    subroutine sweep_texts(self)
        !! Forget text not drawn for a few frames (rebuilding the probe chains).
        type(sdl_backend_t), intent(inout) :: self
        type(text_entry_t), allocatable :: keep(:)
        integer :: k, n, j
        logical :: any_old
        n = size(self%texts)
        any_old = .false.
        do k = 1, n
            if (c_associated(self%texts(k)%text) .and. self%frame_no - self%texts(k)%last > 120) &
                any_old = .true.
        end do
        if (.not. any_old) return
        call move_alloc(self%texts, keep)
        allocate(self%texts(n))
        do k = 1, n
            if (.not. c_associated(keep(k)%text)) cycle
            if (self%frame_no - keep(k)%last > 120) then
                call TTF_DestroyText(keep(k)%text)
                cycle
            end if
            j = int(modulo(keep(k)%hash, int(n, int64))) + 1
            do while (c_associated(self%texts(j)%text))
                j = modulo(j, n) + 1
            end do
            call move_alloc(keep(k)%str, self%texts(j)%str)
            self%texts(j)%hash = keep(k)%hash
            self%texts(j)%slot = keep(k)%slot
            self%texts(j)%text = keep(k)%text
            self%texts(j)%last = keep(k)%last
        end do
    end subroutine sweep_texts

    pure integer(int64) function hash(s, slot) result(h)
        character(*), intent(in) :: s
        integer, intent(in) :: slot
        integer :: k
        h = 1469598103934665603_int64 + slot
        do k = 1, len(s)
            h = ieor(h, int(ichar(s(k:k)), int64))
            h = h * 1099511628211_int64
        end do
        h = iand(h, huge(h))
    end function hash

    ! --- canvas --------------------------------------------------------------------

    subroutine sync_layers(self, store)
        !! GPU resources follow the store slots (released or reassigned slots).
        type(sdl_backend_t), intent(inout) :: self
        type(canvas_store_t), intent(in) :: store
        type(gpu_layer_t), allocatable :: grown(:)
        integer :: k, n
        n = 0
        if (allocated(store%layers)) n = size(store%layers)
        if (size(self%layers) < n) then
            allocate(grown(n))
            do k = 1, size(self%layers)
                call move_layer(self%layers(k), grown(k))
            end do
            call move_alloc(grown, self%layers)
        end if
        do k = 1, size(self%layers)
            if (self%layers(k)%serial == 0) cycle
            if (k > n) then
                call free_layer(self, self%layers(k))
            else if (.not. store%layers(k)%in_use .or. &
                    store%layers(k)%serial /= self%layers(k)%serial) then
                call free_layer(self, self%layers(k))
            end if
        end do
    end subroutine sync_layers

    subroutine move_layer(from, to)
        type(gpu_layer_t), intent(inout) :: from, to
        to%serial = from%serial
        to%version = from%version
        to%index_version = from%index_version
        to%vertex_version = from%vertex_version
        to%count = from%count
        to%capacity = from%capacity
        to%width = from%width
        to%height = from%height
        to%buffer = from%buffer
        to%texture = from%texture
        to%pending = from%pending
        if (allocated(from%data)) call move_alloc(from%data, to%data)
    end subroutine move_layer

    subroutine free_layer(self, g)
        type(sdl_backend_t), intent(inout) :: self
        type(gpu_layer_t), intent(inout) :: g
        if (c_associated(g%buffer)) call SDL_ReleaseGPUBuffer(self%device, g%buffer)
        if (c_associated(g%texture)) call SDL_ReleaseGPUTexture(self%device, g%texture)
        g = gpu_layer_t()
    end subroutine free_layer

    subroutine record_canvas(self, frame, store, index, x, y, w, h, fill)
        !! A canvas: fill, then its layers in order (images as textured quads,
        !! points and lines from their retained GPU buffers), then its labels.
        type(sdl_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        integer, intent(in) :: index
        real, intent(in) :: x, y, w, h
        integer(int32), intent(in) :: fill
        integer :: j, b, saved(4)
        real :: c(4), z, ox, oy, sx, sy, sw, sh
        logical :: fresh, attributes, indices, upload

        saved = self%clip
        self%clip = intersect(self%clip, [nint(x), nint(y), nint(w), nint(h)])
        if (fill /= 0) then
            call unpack(fill, c)
            call add_shape(self, [x, y, w, h], c, c, [0.0, 0.0, 0.0, 0.0])
        end if
        associate(node => frame%nodes(index))
            z = node%canvas_view%zoom * self%scale
            ox = (node%x + node%canvas_view%pan_x) * self%scale
            oy = (node%y + node%canvas_view%pan_y) * self%scale
            do j = node%layer_first, node%layer_first + node%layer_count - 1
                associate(ref => frame%layers(j))
                    if (ref%vertex_slot > 0) upload = self%canvas%vertices(store, &
                        ref%vertex_slot, .false.)
                    fresh = self%layers(ref%slot)%serial /= ref%serial
                    call self%canvas%layer(ref, fresh, attributes, indices)
                    call prepare_layer(self, store, ref)
                    if (ref%kind == LAYER_IMAGE) then
                        associate(l => store%layers(ref%slot))
                            sx = ox + l%rect(1) * z
                            sy = oy + l%rect(2) * z
                            sw = l%rect(3) * z
                            sh = l%rect(4) * z
                        end associate
                        if (c_associated(self%layers(ref%slot)%texture)) call add_quad(self, &
                            self%layers(ref%slot)%texture, self%linear, reshape([sx, sy, &
                            sx + sw, sy, sx + sw, sy + sh, sx, sy + sh], [2, 4]), &
                            reshape([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0], [2, 4]), &
                            [1.0, 1.0, 1.0, 1.0])
                    else if (self%layers(ref%slot)%count > 0) then
                        b = open_batch(self, BATCH_LAYER, c_null_ptr, c_null_ptr)
                        self%batches(b)%slot = ref%slot
                        self%batches(b)%count = self%layers(ref%slot)%count
                        self%batches(b)%view = real([real(self%pw), real(self%ph), 0.0, 0.0, &
                            z, ox, oy, z, store%layers(ref%slot)%min_pixels * self%scale, &
                            self%scale, 0.0, 0.0], c_float)
                    end if
                end associate
            end do
            do j = node%label_first, node%label_first + node%label_count - 1
                associate(lab => frame%labels(j))
                    call add_label(self, lab%text, ox + lab%x * z, oy + lab%y * z, &
                        lab%size, lab%rgba, fill)
                end associate
            end do
        end associate
        self%clip = saved
    end subroutine record_canvas

    subroutine add_label(self, str, cx, y, size, rgba, fill)
        !! Canvas label centred below its anchor; without a colour of its own it
        !! contrasts with the canvas fill.
        type(sdl_backend_t), intent(inout) :: self
        character(*), intent(in) :: str
        real, intent(in) :: cx, y, size
        integer(int32), intent(in) :: rgba, fill
        integer :: slot, face
        integer(c_int) :: pw, ph
        real :: px
        face = FACE_REGULAR
        px = size * self%scale
        slot = font_slot(face, face_px(face, px))
        if (slot == 0) return
        if (.not. TTF_GetStringSize(fonts(slot)%font, str, int(len(str), c_size_t), &
            pw, ph)) return
        call add_text(self, str, real(nint(cx - 0.5 * real(pw))), y + 2.0 * self%scale, &
            real(fonts(slot)%height), face, px, merge(rgba, contrast(fill), rgba /= -1))
    end subroutine add_label

    integer(int32) function contrast(fill) result(c)
        !! Near-black on light fills, near-white on dark ones (the theme's text
        !! colour where the canvas has no fill).
        integer(int32), intent(in) :: fill
        real :: f(4), lum
        if (fill == 0) then
            c = theme%on_surface
            return
        end if
        call unpack(fill, f)
        lum = 0.2126 * f(1) + 0.7152 * f(2) + 0.0722 * f(3)
        c = merge(int(z'FF202020', int32), int(z'FFF0F0F0', int32), lum > 0.5)
    end function contrast

    subroutine prepare_layer(self, store, ref)
        !! Rebuild the instances (or image) of a layer whose data changed; the
        !! upload happens with the frame's copy pass.
        type(sdl_backend_t), intent(inout) :: self
        type(canvas_store_t), intent(in), target :: store
        type(ui_layer_ref_t), intent(in) :: ref
        integer :: i, n, ia, ib, vs
        real :: c(4), d(4)

        associate(g => self%layers(ref%slot), l => store%layers(ref%slot))
            if (g%serial == ref%serial .and. g%version == ref%version .and. &
                g%index_version == ref%index_version .and. &
                g%vertex_version == ref%vertex_version .and. ref%kind /= LAYER_IMAGE) return
            if (ref%kind == LAYER_IMAGE .and. g%serial == ref%serial .and. &
                g%version == ref%version) return
            if (g%serial /= ref%serial) call free_layer(self, g)
            g%serial = ref%serial
            g%version = ref%version
            g%index_version = ref%index_version
            g%vertex_version = ref%vertex_version
            g%pending = .true.
            if (ref%kind == LAYER_IMAGE) then
                ! The texture exists before the frame is recorded; its pixels
                ! arrive with this frame's copy pass.
                if (c_associated(g%texture) .and. (g%width /= l%image_width .or. &
                    g%height /= l%image_height)) then
                    call SDL_ReleaseGPUTexture(self%device, g%texture)
                    g%texture = c_null_ptr
                end if
                g%width = l%image_width
                g%height = l%image_height
                if (.not. c_associated(g%texture)) g%texture = SDL_CreateGPUTexture( &
                    self%device, texture_info_t(type=TEX_2D, format=TEX_RGBA8, &
                    usage=TEXUSE_SAMPLER, width=g%width, height=g%height))
                return
            end if
            vs = ref%vertex_slot
            if (ref%kind == LAYER_POINTS) then
                n = min(ref%vertex_count, size(l%rgba), size(l%sizes))
                call ensure_data(g, n)
                do i = 1, n
                    call unpack(l%rgba(i), c)
                    g%data(:, i) = real([store%layers(vs)%xy(1, i), store%layers(vs)%xy(2, i), &
                        l%sizes(i), 0.0, c, c, 0.0, 0.0, 2.0, merge(1.0, 0.0, l%world_size)], &
                        c_float)
                end do
            else
                n = min(l%index_count, size(l%indices)) / 2
                call ensure_data(g, n)
                do i = 1, n
                    ia = int(l%indices(2 * i - 1)) + 1
                    ib = int(l%indices(2 * i)) + 1
                    call unpack(l%rgba(ia), c)
                    call unpack(l%rgba(ib), d)
                    g%data(:, i) = real([store%layers(vs)%xy(:, ia), store%layers(vs)%xy(:, ib), &
                        c, d, 0.0, l%line_width, 1.0, 1.0], c_float)
                end do
            end if
            g%count = n
        end associate
    end subroutine prepare_layer

    subroutine ensure_data(g, n)
        type(gpu_layer_t), intent(inout) :: g
        integer, intent(in) :: n
        if (allocated(g%data)) then
            if (size(g%data, 2) >= n) return
            deallocate(g%data)
        end if
        allocate(g%data(SHAPE_FLOATS, max(16, n + n / 4)))
    end subroutine ensure_data

    ! --- upload and draw -----------------------------------------------------------

    integer function align(n)
        integer, intent(in) :: n
        align = 256 * ((n + 255) / 256)
    end function align

    subroutine ensure_buffer(self, b, cap, needed, usage)
        type(sdl_backend_t), intent(inout) :: self
        type(c_ptr), intent(inout) :: b
        integer, intent(inout) :: cap
        integer, intent(in) :: needed
        integer(c_int32_t), intent(in) :: usage
        if (needed <= cap .and. c_associated(b)) return
        call release_buffer(self, b)
        cap = max(65536, 2 * needed)
        b = SDL_CreateGPUBuffer(self%device, buffer_info_t(usage=usage, size=int(cap, c_int32_t)))
    end subroutine ensure_buffer

    subroutine upload_frame(self, cmd, store)
        !! Frame shapes, glyph/image vertices and changed layer data through one
        !! transfer buffer and copy pass.
        type(sdl_backend_t), intent(inout), target :: self
        type(c_ptr), intent(in) :: cmd
        type(canvas_store_t), intent(in), target :: store
        integer :: total, off_shapes, off_verts, off_idx, off, k, nbytes
        type(c_ptr) :: mapped, pass
        integer, allocatable :: offsets(:)

        nbytes = 4 * SHAPE_FLOATS * self%nshapes
        call ensure_buffer(self, self%shape_buf, self%shape_cap, max(64, nbytes), BUF_STORAGE)
        call ensure_buffer(self, self%vtx_buf, self%vtx_cap, max(64, 4 * VERTEX_FLOATS * &
            self%nverts), BUF_VERTEX)
        call ensure_buffer(self, self%idx_buf, self%idx_cap, max(64, 4 * self%nidx), BUF_INDEX)
        off_shapes = 0
        off_verts = align(nbytes)
        off_idx = off_verts + align(4 * VERTEX_FLOATS * self%nverts)
        total = off_idx + align(4 * self%nidx)
        allocate(offsets(size(self%layers)))
        offsets = -1
        do k = 1, size(self%layers)
            if (.not. self%layers(k)%pending) cycle
            offsets(k) = total
            if (c_associated(self%layers(k)%texture) .or. self%layers(k)%width > 0) then
                total = total + align(4 * self%layers(k)%width * self%layers(k)%height)
            else
                total = total + align(4 * SHAPE_FLOATS * self%layers(k)%count)
            end if
        end do
        if (total == 0) return
        if (total > self%upload_cap) then
            if (c_associated(self%upload)) call SDL_ReleaseGPUTransferBuffer(self%device, &
                self%upload)
            self%upload_cap = max(1048576, 2 * total)
            self%upload = SDL_CreateGPUTransferBuffer(self%device, buffer_info_t( &
                usage=XFER_UPLOAD, size=int(self%upload_cap, c_int32_t)))
        end if
        mapped = SDL_MapGPUTransferBuffer(self%device, self%upload, .true._c_bool)
        if (.not. c_associated(mapped)) return
        call copy_floats(mapped, off_shapes, self%shapes, SHAPE_FLOATS * self%nshapes)
        call copy_floats(mapped, off_verts, self%verts, VERTEX_FLOATS * self%nverts)
        call copy_ints(mapped, off_idx, self%idx, self%nidx)
        do k = 1, size(self%layers)
            if (offsets(k) < 0) cycle
            if (self%layers(k)%width > 0) then
                call copy_ints(mapped, offsets(k), store%layers(k)%rgba, &
                    self%layers(k)%width * self%layers(k)%height)
            else if (self%layers(k)%count > 0) then
                call copy_floats(mapped, offsets(k), self%layers(k)%data, &
                    SHAPE_FLOATS * self%layers(k)%count)
            end if
        end do
        call SDL_UnmapGPUTransferBuffer(self%device, self%upload)

        pass = SDL_BeginGPUCopyPass(cmd)
        if (self%nshapes > 0) call SDL_UploadToGPUBuffer(pass, xfer_location_t(self%upload, &
            int(off_shapes, c_int32_t)), buffer_region_t(self%shape_buf, 0, &
            int(nbytes, c_int32_t)), .true._c_bool)
        if (self%nverts > 0) call SDL_UploadToGPUBuffer(pass, xfer_location_t(self%upload, &
            int(off_verts, c_int32_t)), buffer_region_t(self%vtx_buf, 0, &
            int(4 * VERTEX_FLOATS * self%nverts, c_int32_t)), .true._c_bool)
        if (self%nidx > 0) call SDL_UploadToGPUBuffer(pass, xfer_location_t(self%upload, &
            int(off_idx, c_int32_t)), buffer_region_t(self%idx_buf, 0, &
            int(4 * self%nidx, c_int32_t)), .true._c_bool)
        do k = 1, size(self%layers)
            if (offsets(k) < 0) cycle
            associate(g => self%layers(k))
                if (g%width > 0) then
                    call SDL_UploadToGPUTexture(pass, texture_xfer_t(self%upload, &
                        int(offsets(k), c_int32_t), int(g%width, c_int32_t), &
                        int(g%height, c_int32_t)), texture_region_t(texture=g%texture, &
                        w=int(g%width, c_int32_t), h=int(g%height, c_int32_t)), &
                        .true._c_bool)
                else if (g%count > 0) then
                    if (g%count > g%capacity) then
                        if (c_associated(g%buffer)) call SDL_ReleaseGPUBuffer(self%device, &
                            g%buffer)
                        g%capacity = size(g%data, 2)
                        g%buffer = SDL_CreateGPUBuffer(self%device, buffer_info_t( &
                            usage=BUF_STORAGE, size=int(4 * SHAPE_FLOATS * g%capacity, &
                            c_int32_t)))
                    end if
                    call SDL_UploadToGPUBuffer(pass, xfer_location_t(self%upload, &
                        int(offsets(k), c_int32_t)), buffer_region_t(g%buffer, 0, &
                        int(4 * SHAPE_FLOATS * g%count, c_int32_t)), .false._c_bool)
                end if
                g%pending = .false.
            end associate
        end do
        call SDL_EndGPUCopyPass(pass)
        off = 0
    end subroutine upload_frame

    subroutine copy_floats(mapped, offset, a, n)
        type(c_ptr), intent(in) :: mapped
        integer, intent(in) :: offset, n
        real(c_float), intent(in), contiguous, target :: a(:, :)
        real(c_float), pointer :: dst(:), src(:)
        if (n <= 0) return
        call c_f_pointer(byte_offset(mapped, offset), dst, [n])
        call c_f_pointer(c_loc(a), src, [n])
        dst = src
    end subroutine copy_floats

    subroutine copy_ints(mapped, offset, a, n)
        type(c_ptr), intent(in) :: mapped
        integer, intent(in) :: offset, n
        integer(c_int32_t), intent(in), contiguous, target :: a(:)
        integer(c_int32_t), pointer :: dst(:)
        if (n <= 0) return
        call c_f_pointer(byte_offset(mapped, offset), dst, [n])
        dst = a(1:n)
    end subroutine copy_ints

    type(c_ptr) function byte_offset(p, n) result(q)
        type(c_ptr), intent(in) :: p
        integer, intent(in) :: n
        q = transfer(transfer(p, 0_c_intptr_t) + int(n, c_intptr_t), q)
    end function byte_offset

    subroutine draw_batches(self, cmd, pass, tw, th)
        type(sdl_backend_t), intent(inout), target :: self
        type(c_ptr), intent(in) :: cmd, pass
        real, intent(in) :: tw, th
        integer :: b
        type(c_ptr), target :: bufs(1)
        type(buffer_binding_t) :: vb(1), ib
        type(sampler_binding_t) :: sb(1)
        real(c_float), target :: view(12)

        call SDL_SetGPUViewport(pass, viewport_t(w=real(tw, c_float), h=real(th, c_float)))
        do b = 1, self%nbatches
            associate(bt => self%batches(b))
                if (bt%count == 0 .or. bt%clip(3) <= 0 .or. bt%clip(4) <= 0) cycle
                call SDL_SetGPUScissor(pass, sdl_rect_t(bt%clip(1), bt%clip(2), bt%clip(3), &
                    bt%clip(4)))
                view = bt%view
                view(1) = real(tw, c_float)
                view(2) = real(th, c_float)
                call SDL_PushGPUVertexUniformData(cmd, 0_c_int32_t, c_loc(view), 48_c_int32_t)
                select case (bt%kind)
                case (BATCH_SHAPES)
                    call SDL_BindGPUGraphicsPipeline(pass, self%shape_pipe)
                    bufs(1) = self%shape_buf
                    call SDL_BindGPUVertexStorageBuffers(pass, 0_c_int32_t, bufs, 1_c_int32_t)
                    call SDL_DrawGPUPrimitives(pass, 6_c_int32_t, int(bt%count, c_int32_t), &
                        0_c_int32_t, int(bt%first, c_int32_t))
                case (BATCH_LAYER)
                    if (.not. c_associated(self%layers(bt%slot)%buffer)) cycle
                    call SDL_BindGPUGraphicsPipeline(pass, self%shape_pipe)
                    bufs(1) = self%layers(bt%slot)%buffer
                    call SDL_BindGPUVertexStorageBuffers(pass, 0_c_int32_t, bufs, 1_c_int32_t)
                    call SDL_DrawGPUPrimitives(pass, 6_c_int32_t, int(bt%count, c_int32_t), &
                        0_c_int32_t, 0_c_int32_t)
                case (BATCH_TEXTURED)
                    call SDL_BindGPUGraphicsPipeline(pass, self%tex_pipe)
                    vb(1) = buffer_binding_t(self%vtx_buf, 0)
                    call SDL_BindGPUVertexBuffers(pass, 0_c_int32_t, vb, 1_c_int32_t)
                    ib = buffer_binding_t(self%idx_buf, 0)
                    call SDL_BindGPUIndexBuffer(pass, ib, INDEX_32)
                    sb(1) = sampler_binding_t(bt%texture, bt%sampler)
                    call SDL_BindGPUFragmentSamplers(pass, 0_c_int32_t, sb, 1_c_int32_t)
                    call SDL_DrawGPUIndexedPrimitives(pass, int(bt%count, c_int32_t), &
                        1_c_int32_t, int(bt%first, c_int32_t), 0_c_int32_t, 0_c_int32_t)
                end select
            end associate
        end do
    end subroutine draw_batches

    subroutine sdl_read_pixels(backend, rgba, width, height)
        !! The last frame of an offscreen backend as RGBA bytes (tests).
        class(ui_backend_t), intent(inout) :: backend
        integer(int8), allocatable, intent(out) :: rgba(:, :, :)
        integer, intent(out) :: width, height
        type(c_ptr) :: cmd, pass, tb, mapped, fence
        type(c_ptr), target :: fences(1)
        integer(int8), pointer :: src(:)
        width = 0
        height = 0
        select type (self => backend)
        type is (sdl_backend_t)
            if (.not. self%offscreen .or. .not. self%active) return
            width = self%pw
            height = self%ph
            tb = SDL_CreateGPUTransferBuffer(self%device, buffer_info_t(usage=XFER_DOWNLOAD, &
                size=int(4 * width * height, c_int32_t)))
            cmd = SDL_AcquireGPUCommandBuffer(self%device)
            pass = SDL_BeginGPUCopyPass(cmd)
            call SDL_DownloadFromGPUTexture(pass, texture_region_t(texture=self%target, &
                w=int(width, c_int32_t), h=int(height, c_int32_t)), texture_xfer_t(tb, 0, &
                int(width, c_int32_t), int(height, c_int32_t)))
            call SDL_EndGPUCopyPass(pass)
            fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd)
            fences(1) = fence
            if (SDL_WaitForGPUFences(self%device, .true._c_bool, fences, 1_c_int32_t)) continue
            call SDL_ReleaseGPUFence(self%device, fence)
            mapped = SDL_MapGPUTransferBuffer(self%device, tb, .false._c_bool)
            allocate(rgba(4, width, height))
            call c_f_pointer(mapped, src, [4 * width * height])
            rgba = reshape(src, [4, width, height])
            call SDL_UnmapGPUTransferBuffer(self%device, tb)
            call SDL_ReleaseGPUTransferBuffer(self%device, tb)
        end select
    end subroutine sdl_read_pixels

    ! --- helpers -------------------------------------------------------------------

    integer function u32(ev, offset)
        integer(c_int8_t), intent(in) :: ev(128)
        integer, intent(in) :: offset
        u32 = int(transfer(ev(offset + 1:offset + 4), 0_c_int32_t))
    end function u32

    integer function u16(ev, offset)
        integer(c_int8_t), intent(in) :: ev(128)
        integer, intent(in) :: offset
        u16 = iand(int(transfer([ev(offset + 1:offset + 2), 0_c_int8_t, 0_c_int8_t], &
            0_c_int32_t)), 65535)
    end function u16

    real function f32(ev, offset)
        integer(c_int8_t), intent(in) :: ev(128)
        integer, intent(in) :: offset
        f32 = transfer(ev(offset + 1:offset + 4), 0.0_c_float)
    end function f32

    type(c_ptr) function ptr_at(ev, offset)
        integer(c_int8_t), intent(in) :: ev(128)
        integer, intent(in) :: offset
        ptr_at = transfer(ev(offset + 1:offset + 8), c_null_ptr)
    end function ptr_at

    function f_str(p) result(s)
        type(c_ptr), intent(in) :: p
        character(len=:), allocatable :: s
        character(kind=c_char), pointer :: chars(:)
        integer :: n, k
        if (.not. c_associated(p)) then
            s = ""
            return
        end if
        n = int(c_strlen(p))
        call c_f_pointer(p, chars, [n])
        allocate(character(len=n) :: s)
        do k = 1, n
            s(k:k) = chars(k)
        end do
    end function f_str
#endif
end module fortui_gui_sdl
