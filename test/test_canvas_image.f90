program test_canvas_image
    !! Image layers: the store copies pixels only for a new generation or size,
    !! the software raster puts each image pixel where its rectangle says, and a
    !! composed canvas uploads an image once per version on every buildable
    !! backend (raylib too when a display is reachable).
    use iso_fortran_env, only: int32
    use fortui
    use fortui_backend, only: ui_backend_t
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_stats, ui_stats_t, ui_layer_uploads
    use fortui_frame, only: ui_frame_t, ui_node_t, UI_CANVAS, LAYER_IMAGE
    use fortui_canvas, only: canvas_store_t
    use fortui_raster, only: raster_t, raster_map_t, raster_resize, raster_canvas, rgb_pack
    ! Empty unless built with -DENABLE_GUI=1 (raylib_backend_t, raylib_is_available).
    use fortui_gui_raylib
    implicit none

    integer :: failures = 0
    integer(int32) :: pixels(2, 2)
    integer :: gen
    real :: rect_x

    call test_store()
    call test_raster()
    call scenario(headless_backend_t(), "headless")
#ifdef ENABLE_GUI
    if (raylib_is_available()) then
        call scenario(raylib_backend_t(), "gui")
    else
        print '(a)', "canvas image: raylib backend skipped (no display or FORTUI_HEADLESS=1)"
    end if
#endif

    if (failures > 0) then
        print '(i0,a)', failures, " canvas image checks failed"
        error stop 1
    end if
    print '(a)', " fortui canvas image tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

    function test_pixels() result(p)
        !! Red, green in the top row; blue, half-transparent white below.
        integer(int32) :: p(2, 2)
        p(1, 1) = ui_rgba(255, 0, 0)
        p(2, 1) = ui_rgba(0, 255, 0)
        p(1, 2) = ui_rgba(0, 0, 255)
        p(2, 2) = ui_rgba(255, 255, 255, 128)
    end function test_pixels

    subroutine test_store()
        type(canvas_store_t) :: store
        integer :: slot, v, iv
        integer(int32) :: big(3, 2)

        slot = store%submit_image("c/img", 1, test_pixels(), [0.0, 0.0, 4.0, 4.0], 1)
        call check(slot > 0, "image layer acquired")
        v = store%layers(slot)%version
        call check(store%layers(slot)%kind == LAYER_IMAGE .and. &
            store%layers(slot)%image_width == 2 .and. &
            store%layers(slot)%image_height == 2, "image kind and size recorded")
        call check(store%layers(slot)%rgba(2) == ui_rgba(0, 255, 0) .and. &
            store%layers(slot)%rgba(3) == ui_rgba(0, 0, 255), "pixels stored row by row")
        iv = store%layers(slot)%index_version
        slot = store%submit_image("c/img", 1, test_pixels(), [1.0, 2.0, 8.0, 8.0], 2)
        call check(store%layers(slot)%version == v, "same generation: no copy")
        call check(all(store%layers(slot)%rect == [1.0, 2.0, 8.0, 8.0]), &
            "rectangle follows every frame")
        call check(store%layers(slot)%index_version == iv + 1, &
            "a moved rectangle is a geometry change")
        slot = store%submit_image("c/img", 1, test_pixels(), [1.0, 2.0, 8.0, 8.0], 3)
        call check(store%layers(slot)%index_version == iv + 1, "same place: no change")
        big = ui_rgba(9, 9, 9)
        slot = store%submit_image("c/img", 1, big, [0.0, 0.0, 3.0, 2.0], 4)
        call check(store%layers(slot)%version == v + 1 .and. &
            store%layers(slot)%image_width == 3, "new size copies despite same generation")
        slot = store%submit_image("c/img", 2, big, [0.0, 0.0, 3.0, 2.0], 5)
        call check(store%layers(slot)%version == v + 2, "new generation copies")
    end subroutine test_store

    subroutine test_raster()
        !! The 2x2 image fills world (1, 1)..(5, 5) of a canvas with zoom 1 at the
        !! frame origin; one logical unit is one raster pixel on an 8x8 black raster.
        type(canvas_store_t) :: store
        type(ui_frame_t) :: frame
        type(ui_node_t) :: node
        type(raster_t) :: r
        integer :: slot, k

        slot = store%submit_image("c/img", 1, test_pixels(), [1.0, 1.0, 4.0, 4.0], 1)
        call frame%reset()
        node%kind = UI_CANVAS
        node%id = "c"
        node%width = 8.0
        node%height = 8.0
        node%fill = ui_rgba(0, 0, 0)
        node%layer_first = 1
        node%layer_count = 1
        k = frame%append_layer(store%ref(slot))
        k = frame%append(node)
        call raster_resize(r, 8, 8)
        call raster_canvas(r, store, frame, node, raster_map_t())
        call check(px(r, 0, 0) == 0 .and. px(r, 5, 5) == 0 .and. px(r, 7, 1) == 0, &
            "outside the rectangle stays the fill")
        call check(px(r, 1, 1) == rgb_pack(255, 0, 0) .and. &
            px(r, 2, 2) == rgb_pack(255, 0, 0), "top-left image pixel")
        call check(px(r, 3, 1) == rgb_pack(0, 255, 0) .and. &
            px(r, 4, 2) == rgb_pack(0, 255, 0), "top-right image pixel")
        call check(px(r, 1, 3) == rgb_pack(0, 0, 255) .and. &
            px(r, 2, 4) == rgb_pack(0, 0, 255), "bottom-left image pixel")
        call check(px(r, 4, 4) == rgb_pack(128, 128, 128), &
            "half-transparent white over black is mid grey")
        ! Zoom 2 with a pan of (-2, 0): world x 1..5 lands on pixels 0..7.
        frame%nodes(1)%canvas_view = canvas_view_t(zoom=2.0, pan_x=-2.0, pan_y=-2.0)
        call raster_canvas(r, store, frame, frame%nodes(1), raster_map_t())
        call check(px(r, 0, 0) == rgb_pack(255, 0, 0) .and. &
            px(r, 3, 3) == rgb_pack(255, 0, 0) .and. &
            px(r, 4, 0) == rgb_pack(0, 255, 0) .and. &
            px(r, 0, 4) == rgb_pack(0, 0, 255), "view zoom and pan apply to images")
    end subroutine test_raster

    integer(int32) function px(r, x, y)
        type(raster_t), intent(in) :: r
        integer, intent(in) :: x, y
        px = r%rgb(1 + x + y * r%width)
    end function px

    subroutine scenario(backend, name)
        class(ui_backend_t), intent(in) :: backend
        character(*), intent(in) :: name
        type(ui_stats_t) :: s0, s
        integer :: stat, u, iu

        call ui_init(backend, 320, 240, "FortUI image", target_fps=0, vsync=.false., &
            stat=stat)
        call check(stat == 0, name // ": init")
        if (stat /= 0) return
        call ui_set_continuous(.true.)
        pixels = test_pixels()
        gen = 1
        rect_x = 0.0
        s0 = ui_stats()
        call compose()
        s = ui_stats()
        call check(s%attribute_uploads - s0%attribute_uploads == 1, &
            name // ": first frame uploads the image once")
        rect_x = 10.0
        call compose()
        call compose()
        call ui_layer_uploads("photo", "img", u, iu)
        call check(u == 1, name // ": moving the image uploads nothing")
        pixels(1, 1) = ui_rgba(0, 0, 0)
        gen = 2
        call compose()
        call ui_layer_uploads("photo", "img", u, iu)
        call check(u == 2, name // ": a new generation uploads once more")
        call ui_shutdown()
        print '(a)', "canvas image: " // name // " done"
    end subroutine scenario

    subroutine compose()
        type(canvas_view_t) :: view
        type(canvas_events_t) :: ev

        call ui_frame_begin()
        call canvas_begin("photo", view, ev, width=200.0, height=150.0, &
            fill=ui_rgba(20, 20, 20))
        call canvas_image("img", gen, pixels, rect_x, 0.0, 100.0, 100.0)
        call canvas_end(view)
        call ui_present()
    end subroutine compose

end program test_canvas_image
