program test_mesh
    !! Filled 3D surfaces: the camera's projection, depth (the nearer of two
    !! overlapping triangles shows whichever comes first), flat shading, the
    !! grid and tube builders, and the retained mesh layer (moving the camera
    !! copies no geometry).
    use iso_fortran_env, only: int32
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_mesh, only: mesh_raster, mesh_shade
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_frame, only: LAYER_MESH
    implicit none
    integer :: fails = 0, stat, k, slot, version, view_version
    type(canvas_camera_t) :: cam
    real :: x, y, d, xyz(3, 6)
    logical :: seen
    integer(int32) :: rgba(6), tris(3, 2), pixels(64 * 64)
    real :: depth(64 * 64)
    real, allocatable :: tube(:, :)
    integer(int32), allocatable :: grid(:, :), tube_tris(:, :)
    integer(int32) :: red, blue
    type(canvas_view_t) :: view
    type(canvas_events_t) :: ev
    type(fortui_context_t), pointer :: ctx

    ! Looking at the origin from +x: the target is the canvas centre, a point
    ! towards the camera is nearer, +y shows to the right, +z up.
    cam = camera_orbit(0.0, 0.0, 5.0, 1.0)
    call camera_project(cam, [0.0, 0.0, 0.0], 100.0, 100.0, x, y, d, seen)
    call check(seen .and. abs(x - 50.0) < 1e-3 .and. abs(y - 50.0) < 1e-3, 'the target shows at the centre')
    block
        real :: d2, x2, y2
        call camera_project(cam, [1.0, 0.0, 0.0], 100.0, 100.0, x2, y2, d2, seen)
        call check(d2 < d, 'a point towards the camera is nearer')
        call camera_project(cam, [0.0, 1.0, 0.0], 100.0, 100.0, x2, y2, d2, seen)
        call check(x2 > 50.0, 'seen from +x with +z up, +y lies to the right')
        call camera_project(cam, [0.0, 0.0, 1.0], 100.0, 100.0, x2, y2, d2, seen)
        call check(y2 < 50.0, '+z lies up')
        call camera_project(cam, [10.0, 0.0, 0.0], 100.0, 100.0, x2, y2, d2, seen)
        call check(.not. seen, 'a point behind the camera is not seen')
    end block

    ! Two big triangles across the view: red nearer (x = 1), blue farther (x = -1).
    red = ui_rgba(255, 0, 0)
    blue = ui_rgba(0, 0, 255)
    xyz(:, 1:3) = reshape([1.0, -3.0, -3.0, 1.0, 3.0, -3.0, 1.0, 0.0, 3.0], [3, 3])
    xyz(:, 4:6) = reshape([-1.0, -3.0, -3.0, -1.0, 3.0, -3.0, -1.0, 0.0, 3.0], [3, 3])
    rgba(1:3) = red
    rgba(4:6) = blue
    do k = 1, 2
        tris(:, 1) = [0, 1, 2]
        tris(:, 2) = [3, 4, 5]
        if (k == 2) tris = tris(:, [2, 1])
        pixels = 0
        depth = 1.0
        call mesh_raster(xyz, rgba, tris, cam, 64, 64, pixels, depth)
        call check(iand(pixels(32 * 64 + 32), 255_int32) > 150 .and. &
            iand(ishft(pixels(32 * 64 + 32), -16), 255_int32) == 0, &
            'the nearer triangle shows, drawn ' // merge('first ', 'second', k == 1))
    end do
    call check(pixels(1) == 0 .and. depth(1) == 1.0, 'pixels outside every triangle stay free')
    call check(abs(mesh_shade([1.0, 0.0, 0.0], [1.0, 0.0, 0.0]) - 1.0) < 1e-6 .and. &
        abs(mesh_shade([0.0, 1.0, 0.0], [1.0, 0.0, 0.0]) - 0.3) < 1e-6 .and. &
        abs(mesh_shade([-1.0, 0.0, 0.0], [1.0, 0.0, 0.0]) - 1.0) < 1e-6, &
        'faces towards the light are bright, edge-on ones ambient, both sides lit')

    ! Vertex normals shade across the face: a face seen at a slant, with
    ! normals towards the light, is as bright as a face towards it.
    block
        real :: tilt(3, 3), nrm(3, 3)
        integer(int32) :: one(3, 1), white(3)
        tilt = reshape([0.0, -2.0, -2.0, 2.0, 2.0, -2.0, 0.0, 0.0, 2.0], [3, 3])
        nrm = spread([1.0, 0.0, 0.0], 2, 3)
        white = ui_rgba(200, 200, 200)
        one(:, 1) = [0, 1, 2]
        pixels = 0
        depth = 1.0
        call mesh_raster(tilt, white, one, cam, 64, 64, pixels, depth)
        k = iand(pixels(32 * 64 + 32), 255_int32)
        pixels = 0
        depth = 1.0
        call mesh_raster(tilt, white, one, cam, 64, 64, pixels, depth, nrm)
        call check(iand(pixels(32 * 64 + 32), 255_int32) == 200 .and. k < 190, &
            'vertex normals shade a slanted face as their own direction')
    end block

    grid = mesh_grid(4, 3, .true., .false.)
    call check(size(grid, 2) == 2 * 4 * 2 .and. maxval(grid) == 11 .and. minval(grid) == 0, &
        'a grid closed in one direction has 2 nu (nv - 1) triangles')
    call mesh_tube(reshape([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0], [3, 3]), 0.1, 6, .false., &
        tube, tube_tris, k)
    call check(k == 0 .and. size(tube, 2) == 18 .and. size(tube_tris, 2) == 2 * 6 * 2, &
        'a tube of 3 points and 6 sides')
    call check(all(abs(norm2(tube(2:3, :), dim=1) - 0.1) < 1e-5), 'its rings lie at its radius')

    ! The retained layer: geometry copies on a new generation only.
    call ui_init(headless_backend_t(), 200, 200, 'mesh', stat=stat)
    ctx => get_default_context()
    do k = 1, 3
        call ui_frame_begin()
        call canvas_begin('view', view, ev, width=100.0, height=100.0)
        cam = camera_orbit(0.1 * k, 0.2, 5.0, 1.0)
        call canvas_mesh('m', 1, xyz, rgba, tris, cam)
        call canvas_end()
        call ui_present()
        slot = ctx%previous_frame%layers(1)%slot
        if (k == 1) then
            version = ctx%canvas%layers(slot)%version
            view_version = ctx%canvas%layers(slot)%index_version
        end if
    end do
    call check(ctx%previous_frame%layers(1)%kind == LAYER_MESH, 'the canvas holds a mesh layer')
    call check(ctx%canvas%layers(slot)%version == version, 'moving the camera copies no geometry')
    call check(ctx%canvas%layers(slot)%index_version == view_version + 2, 'but marks the view changed')

    if (fails > 0) error stop 1
    print '(a)', 'test_mesh: all passed'

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            fails = fails + 1
            print '(a)', 'FAIL: ' // what
        end if
    end subroutine check

end program test_mesh
