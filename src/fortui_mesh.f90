module fortui_mesh
    !! Filled 3D surfaces for canvases: a camera, the projection of world
    !! points to the canvas, a depth-buffered rasterizer for hosts that draw
    !! the mesh themselves (the browser draws it on the GPU), and builders for
    !! the usual shapes (surfaces on a grid, tubes along a path).
    !!
    !! A camera maps world coordinates to clip coordinates with one 4 x 4
    !! matrix; x and y of the normalized device coordinates span the canvas,
    !! smaller z is nearer. Triangles are shaded flat by the angle between
    !! their normal and `light` (both sides lit).
    use iso_fortran_env, only: int32
    implicit none
    private

    type, public :: canvas_camera_t
        !! World to clip coordinates (column-major as GPUs take it), and the
        !! direction towards the light in world coordinates.
        real :: m(4, 4) = reshape([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, &
            0.0, 0.0, 0.0, 1.0], [4, 4])
        real :: light(3) = [0.0, 0.0, 1.0]
    end type canvas_camera_t

    public :: camera_orbit, camera_project, mesh_raster, mesh_grid, mesh_tube, mesh_shade

    real, parameter :: PI = 3.14159265

contains

    pure function camera_orbit(yaw, pitch, distance, aspect, target, fov) result(cam)
        !! A perspective camera on a sphere around `target`: `yaw` about the
        !! vertical (z) axis and `pitch` above the horizontal plane (radians),
        !! at `distance`; `aspect` is width over height and `fov` the vertical
        !! field of view in degrees (default 35). The light comes from the camera.
        real, intent(in) :: yaw, pitch, distance, aspect
        real, intent(in), optional :: target(3), fov
        type(canvas_camera_t) :: cam
        real :: eye(3), at(3), f(3), s(3), u(3), view(4, 4), proj(4, 4), t, near, far, d
        at = 0.0
        if (present(target)) at = target
        d = max(1.0e-6, distance)
        eye = at + d * [cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch)]
        f = at - eye
        f = f / norm2(f)
        s = cross(f, [0.0, 0.0, 1.0])
        if (norm2(s) < 1.0e-6) s = cross(f, [0.0, 1.0, 0.0])
        s = s / norm2(s)
        u = cross(s, f)
        view = 0.0
        view(1, 1:3) = s
        view(2, 1:3) = u
        view(3, 1:3) = -f
        view(1, 4) = -dot_product(s, eye)
        view(2, 4) = -dot_product(u, eye)
        view(3, 4) = dot_product(f, eye)
        view(4, 4) = 1.0
        t = 35.0
        if (present(fov)) t = fov
        t = 1.0 / tan(0.5 * t * PI / 180.0)
        near = 0.05 * d
        far = 20.0 * d
        proj = 0.0
        proj(1, 1) = t / max(1.0e-6, aspect)
        proj(2, 2) = t
        proj(3, 3) = (far + near) / (near - far)
        proj(3, 4) = 2.0 * far * near / (near - far)
        proj(4, 3) = -1.0
        cam%m = matmul(proj, view)
        cam%light = -f
    end function camera_orbit

    pure function cross(a, b) result(c)
        real, intent(in) :: a(3), b(3)
        real :: c(3)
        c = [a(2) * b(3) - a(3) * b(2), a(3) * b(1) - a(1) * b(3), a(1) * b(2) - a(2) * b(1)]
    end function cross

    pure subroutine camera_project(cam, p, width, height, x, y, depth, visible)
        !! Where world point `p` shows on a canvas of `width` x `height`
        !! (canvas units from its top left), its depth (-1 near to 1 far) and
        !! whether it lies in front of the camera.
        type(canvas_camera_t), intent(in) :: cam
        real, intent(in) :: p(3), width, height
        real, intent(out) :: x, y, depth
        logical, intent(out) :: visible
        real :: c(4)
        c = matmul(cam%m, [p, 1.0])
        visible = c(4) > 1.0e-6
        if (.not. visible) then
            x = 0.0
            y = 0.0
            depth = 1.0
            return
        end if
        x = (0.5 * c(1) / c(4) + 0.5) * width
        y = (0.5 - 0.5 * c(2) / c(4)) * height
        depth = c(3) / c(4)
    end subroutine camera_project

    pure real function mesh_shade(normal, light) result(f)
        !! Brightness of a face: ambient plus diffuse from either side.
        real, intent(in) :: normal(3), light(3)
        real :: n
        n = norm2(normal) * max(1.0e-12, norm2(light))
        f = 0.3
        if (n > 1.0e-12) f = 0.3 + 0.7 * abs(dot_product(normal, light)) / n
    end function mesh_shade

    subroutine mesh_raster(xyz, rgba, tris, cam, width, height, pixels, depth, normals)
        !! Draw triangles tris(3, :) (0-based vertex numbers) of vertices
        !! xyz(3, :) with colours rgba(:) (ui_rgba) into pixels(width*height),
        !! row by row from the top, nearest in front. `depth` holds the depth of
        !! each pixel (1 where nothing was drawn); pixels left free keep their value.
        !! With `normals` (3, :) a vertex is shaded by its normal and the shade
        !! blends across the face; a zero normal takes the face's.
        real, intent(in), optional :: normals(:, :)
        real, intent(in) :: xyz(:, :)
        integer(int32), intent(in) :: rgba(:), tris(:, :)
        type(canvas_camera_t), intent(in) :: cam
        integer, intent(in) :: width, height
        integer(int32), intent(inout) :: pixels(:)
        real, intent(inout) :: depth(:)
        real, allocatable :: sx(:), sy(:), sz(:)
        logical, allocatable :: ok(:)
        integer :: n, t, a, b, c, x0, x1, y0, y1, px, py, k
        real :: area, w0, w1, w2, z, fx, fy, shade, col(4, 3), out(4), vs(3), face(3)
        real :: e(3)
        n = size(xyz, 2)
        allocate (sx(n), sy(n), sz(n), ok(n))
        do k = 1, n
            call camera_project(cam, xyz(:, k), real(width), real(height), sx(k), sy(k), sz(k), ok(k))
            ok(k) = ok(k) .and. sz(k) >= -1.0 .and. sz(k) <= 1.0
        end do
        do t = 1, size(tris, 2)
            a = tris(1, t) + 1
            b = tris(2, t) + 1
            c = tris(3, t) + 1
            if (min(a, b, c) < 1 .or. max(a, b, c) > n) cycle
            if (.not. (ok(a) .and. ok(b) .and. ok(c))) cycle
            area = (sx(b) - sx(a)) * (sy(c) - sy(a)) - (sy(b) - sy(a)) * (sx(c) - sx(a))
            if (abs(area) < 1.0e-12) cycle
            face = cross(xyz(:, b) - xyz(:, a), xyz(:, c) - xyz(:, a))
            shade = mesh_shade(face, cam%light)
            vs = shade
            if (present(normals)) then
                if (any(normals(:, a) /= 0.0)) vs(1) = mesh_shade(normals(:, a), cam%light)
                if (any(normals(:, b) /= 0.0)) vs(2) = mesh_shade(normals(:, b), cam%light)
                if (any(normals(:, c) /= 0.0)) vs(3) = mesh_shade(normals(:, c), cam%light)
            end if
            col(:, 1) = channels(rgba(min(a, size(rgba))))
            col(:, 2) = channels(rgba(min(b, size(rgba))))
            col(:, 3) = channels(rgba(min(c, size(rgba))))
            col(1:3, 1) = col(1:3, 1) * vs(1)
            col(1:3, 2) = col(1:3, 2) * vs(2)
            col(1:3, 3) = col(1:3, 3) * vs(3)
            x0 = max(0, floor(min(sx(a), sx(b), sx(c))))
            x1 = min(width - 1, ceiling(max(sx(a), sx(b), sx(c))))
            y0 = max(0, floor(min(sy(a), sy(b), sy(c))))
            y1 = min(height - 1, ceiling(max(sy(a), sy(b), sy(c))))
            do py = y0, y1
                fy = real(py) + 0.5
                do px = x0, x1
                    fx = real(px) + 0.5
                    w0 = ((sx(c) - sx(b)) * (fy - sy(b)) - (sy(c) - sy(b)) * (fx - sx(b))) / area
                    w1 = ((sx(a) - sx(c)) * (fy - sy(c)) - (sy(a) - sy(c)) * (fx - sx(c))) / area
                    w2 = 1.0 - w0 - w1
                    if (w0 < 0.0 .or. w1 < 0.0 .or. w2 < 0.0) cycle
                    z = w0 * sz(a) + w1 * sz(b) + w2 * sz(c)
                    k = py * width + px + 1
                    if (z >= depth(k)) cycle
                    depth(k) = z
                    e = [w0, w1, w2]
                    out = matmul(col, e)
                    pixels(k) = pack_channels(out)
                end do
            end do
        end do
    end subroutine mesh_raster

    pure function channels(c) result(v)
        integer(int32), intent(in) :: c
        real :: v(4)
        v = real([iand(c, 255_int32), iand(ishft(c, -8), 255_int32), iand(ishft(c, -16), 255_int32), &
            iand(ishft(c, -24), 255_int32)])
    end function channels

    pure integer(int32) function pack_channels(v) result(c)
        real, intent(in) :: v(4)
        integer :: r, g, b, a
        r = max(0, min(255, nint(v(1))))
        g = max(0, min(255, nint(v(2))))
        b = max(0, min(255, nint(v(3))))
        a = max(0, min(255, nint(v(4))))
        if (a > 127) a = a - 256
        c = int(r, int32) + ishft(int(g, int32), 8) + ishft(int(b, int32), 16) + ishft(int(a, int32), 24)
    end function pack_channels

    pure function mesh_grid(nu, nv, wrap_u, wrap_v) result(tris)
        !! Triangles of a surface sampled on an nu x nv grid, vertex (i, j) at
        !! number (j - 1) * nu + i - 1; `wrap_u`, `wrap_v` close the surface in
        !! that direction (a torus closes both).
        integer, intent(in) :: nu, nv
        logical, intent(in) :: wrap_u, wrap_v
        integer(int32), allocatable :: tris(:, :)
        integer :: i, j, k, cu, cv, i2, j2
        cu = nu - 1
        if (wrap_u) cu = nu
        cv = nv - 1
        if (wrap_v) cv = nv
        allocate (tris(3, 2 * max(0, cu) * max(0, cv)))
        k = 0
        do j = 1, cv
            j2 = mod(j, nv) + 1
            do i = 1, cu
                i2 = mod(i, nu) + 1
                tris(:, k + 1) = int([(j - 1) * nu + i - 1, (j - 1) * nu + i2 - 1, (j2 - 1) * nu + i2 - 1], int32)
                tris(:, k + 2) = int([(j - 1) * nu + i - 1, (j2 - 1) * nu + i2 - 1, (j2 - 1) * nu + i - 1], int32)
                k = k + 2
            end do
        end do
    end function mesh_grid

    subroutine mesh_tube(path, radius, sides, closed, xyz, tris, first)
        !! A tube of `radius` with `sides` faces around the polyline path(3, :)
        !! (`closed`: the last point joins the first), appended to xyz and tris;
        !! `first` is the number of its first vertex in xyz.
        real, intent(in) :: path(:, :), radius
        integer, intent(in) :: sides
        logical, intent(in) :: closed
        real, allocatable, intent(inout) :: xyz(:, :)
        integer(int32), allocatable, intent(inout) :: tris(:, :)
        integer, intent(out) :: first
        integer :: n, k, j, base
        real :: nrm(3), bin(3), ang, twist, c
        real, allocatable :: ring(:, :), tng(:, :), frame(:, :)
        integer(int32), allocatable :: grid(:, :)
        n = size(path, 2)
        if (.not. allocated(xyz)) allocate (xyz(3, 0))
        if (.not. allocated(tris)) allocate (tris(3, 0))
        first = size(xyz, 2)
        if (n < 2) return
        allocate (ring(3, sides * n), tng(3, n), frame(3, n))
        do k = 1, n
            if (closed) then
                tng(:, k) = path(:, mod(k, n) + 1) - path(:, mod(k - 2 + n, n) + 1)
            else
                tng(:, k) = path(:, min(n, k + 1)) - path(:, max(1, k - 1))
            end if
            tng(:, k) = tng(:, k) / max(1.0e-12, norm2(tng(:, k)))
        end do
        ! A frame fixed to a world axis flips where the path runs along that
        ! axis, which pinches the tube to a line there. Carrying the frame along
        ! the path (parallel transport) keeps it from turning about the path.
        nrm = cross(tng(:, 1), [0.0, 0.0, 1.0])
        if (norm2(nrm) < 1.0e-3) nrm = cross(tng(:, 1), [1.0, 0.0, 0.0])
        frame(:, 1) = nrm / norm2(nrm)
        do k = 2, n
            nrm = frame(:, k - 1) - dot_product(frame(:, k - 1), tng(:, k)) * tng(:, k)
            if (norm2(nrm) < 1.0e-6) nrm = cross(tng(:, k), cross(frame(:, k - 1), tng(:, k)))
            if (norm2(nrm) < 1.0e-6) nrm = cross(tng(:, k), [1.0, 0.0, 0.0])
            frame(:, k) = nrm / norm2(nrm)
        end do
        ! A closed path returns with the frame turned by its total torsion; that
        ! angle is undone in equal parts so the last ring meets the first.
        if (closed) then
            nrm = frame(:, n) - dot_product(frame(:, n), tng(:, 1)) * tng(:, 1)
            twist = atan2(dot_product(cross(nrm, frame(:, 1)), tng(:, 1)), dot_product(nrm, frame(:, 1)))
            do k = 2, n
                ang = twist * real(k - 1) / real(n)
                c = cos(ang)
                frame(:, k) = c * frame(:, k) + sin(ang) * cross(tng(:, k), frame(:, k))
            end do
        end if
        do k = 1, n
            nrm = frame(:, k)
            bin = cross(tng(:, k), nrm)
            do j = 1, sides
                ang = 2.0 * PI * real(j - 1) / real(sides)
                ring(:, (k - 1) * sides + j) = path(:, k) + radius * (cos(ang) * nrm + sin(ang) * bin)
            end do
        end do
        base = first
        xyz = reshape([xyz, ring], [3, size(xyz, 2) + size(ring, 2)])
        grid = mesh_grid(sides, n, .true., closed) + int(base, int32)
        tris = reshape([tris, grid], [3, size(tris, 2) + size(grid, 2)])
    end subroutine mesh_tube

end module fortui_mesh
