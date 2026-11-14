module fortui_theme
    !! Themes: design tokens (colours, metrics, type scale, fonts) and the
    !! painter style that realizes them.
    !!
    !! Widgets size themselves from the current theme's metrics; graphical
    !! backends paint with its colours and fonts. Built-in themes:
    !!
    !! - "classic": Windows 95 as the Chicago95 desktop theme draws it: grey
    !!   #C0C0C0 faces, two-pixel bevels, 11 px bitmap Helvetica (Chicago95 fonts),
    !!   More Perfect DOS VGA for code.
    !! - "material", "material-dark": Material Design 3 baseline colour schemes,
    !!   Roboto and Roboto Mono, the M3 type scale and component metrics.
    !! - "plain": the semantic default of headless and terminal backends.
    !!
    !! Fonts are never shipped: a theme names font families that fontconfig finds
    !! among the installed fonts, and backends fall back with a warning.
    !! Graphical backends take the theme from FORTUI_THEME, else from `theme =`
    !! in $XDG_CONFIG_HOME/fortui/config (~/.config/fortui/config), else the
    !! application's default (ui_init theme=, else "material").
    use iso_fortran_env, only: int32
    implicit none
    private

    integer, parameter, public :: STYLE_PLAIN = 0, STYLE_CLASSIC = 1, STYLE_MATERIAL = 2

    ! Text roles, the order of style tokens UI_BODY .. UI_CODE in fortui_frame.
    integer, parameter, public :: ROLE_BODY = 1, ROLE_CAPTION = 2, ROLE_HEADING = 3, &
        ROLE_TITLE = 4, ROLE_CODE = 5, ROLE_LABEL = 6
    integer, parameter, public :: ROLE_COUNT = 6

    ! Font faces a theme names (regular, bold/medium, monospaced).
    integer, parameter, public :: FACE_REGULAR = 1, FACE_STRONG = 2, FACE_MONO = 3

    type, public :: ui_font_t
        !! fontconfig families tried in order; `pixel` fonts are bitmap or pixel
        !! designs drawn without hinting changes at whole multiples of `grid`.
        character(len=64) :: families(4) = ""
        character(len=32) :: style = ""
        logical :: pixel = .false.
        real :: grid = 0.0
        character(len=64) :: package = ""
    end type ui_font_t

    type, public :: ui_theme_t
        character(len=32) :: name = "plain"
        integer :: kind = STYLE_PLAIN
        logical :: dark = .false.

        ! Type scale: logical size and face of each text role.
        real :: text_size(ROLE_COUNT) = [20.0, 15.0, 17.0, 26.0, 15.0, 20.0]
        integer :: text_face(ROLE_COUNT) = [FACE_REGULAR, FACE_REGULAR, FACE_STRONG, &
            FACE_STRONG, FACE_MONO, FACE_REGULAR]
        ! Line height as a multiple of the text size.
        real :: line_factor = 1.25
        type(ui_font_t) :: fonts(3)

        ! Metrics in logical units.
        real :: control_height = 32.0
        real :: control_padding = 12.0
        real :: control_min_width = 72.0
        real :: input_padding = 6.0
        real :: scroll_padding = 8.0
        real :: scrollbar_width = 10.0
        logical :: scroll_arrows = .false.
        real :: check_size = 20.0
        real :: check_gap = 10.0
        real :: tab_height = 32.0
        real :: slider_thumb = 10.0
        real :: control_radius = 0.0
        real :: field_radius = 0.0
        real :: gap = 8.0
        ! Free space between the window edge and the content.
        real :: margin = 0.0

        ! Colours, packed like ui_rgba.
        integer(int32) :: window = 0, surface = 0, surface_low = 0, surface_high = 0
        integer(int32) :: on_surface = 0, on_surface_muted = 0, disabled = 0
        integer(int32) :: primary = 0, on_primary = 0
        integer(int32) :: tonal = 0, on_tonal = 0
        integer(int32) :: outline = 0, outline_variant = 0
        integer(int32) :: field = 0, on_field = 0
        integer(int32) :: selection = 0, on_selection = 0
        integer(int32) :: focus = 0, link = 0
        integer(int32) :: positive = 0, negative = 0, attention = 0
        ! Classic bevel colours (COLOR_3DFACE, 3DHILIGHT, 3DLIGHT, 3DSHADOW,
        ! 3DDKSHADOW) and the active caption.
        integer(int32) :: face = 0, hilight = 0, light = 0, shadow = 0, dark_shadow = 0
        integer(int32) :: caption = 0, on_caption = 0
        ! Code tokens and diff lines (UI_TONE_KEYWORD .. UI_TONE_HUNK).
        integer(int32) :: code(9) = 0
    end type ui_theme_t

    !! The current theme; read it here, change it with theme_set or theme_select.
    type(ui_theme_t), public, protected, save, target :: theme

    public :: theme_plain, theme_classic, theme_material, theme_named
    public :: theme_current, theme_set, theme_select, theme_requested
    public :: theme_rgb, theme_names

contains

    pure integer(int32) function theme_rgb(hex, alpha) result(c)
        !! Colour from 0xRRGGBB (and alpha 0..255), packed like ui_rgba.
        integer, intent(in) :: hex
        integer, intent(in), optional :: alpha
        integer :: r, g, b, a

        r = iand(ishft(hex, -16), 255)
        g = iand(ishft(hex, -8), 255)
        b = iand(hex, 255)
        a = 255
        if (present(alpha)) a = iand(alpha, 255)
        c = int(ior(ior(r, ishft(g, 8)), ior(ishft(b, 16), ishft(iand(a, 127), 24))), int32)
        if (a > 127) c = ior(c, ishft(1_int32, 31))
    end function theme_rgb

    function theme_names() result(names)
        character(len=16) :: names(3)
        names = [character(16) :: "classic", "material", "material-dark"]
    end function theme_names

    pure function theme_plain() result(t)
        !! The metric defaults of headless and terminal backends.
        type(ui_theme_t) :: t
        t%name = "plain"
        t%kind = STYLE_PLAIN
        t%window = theme_rgb(int(z'1E1E1E'))
        t%surface = t%window
        t%on_surface = theme_rgb(int(z'EBEBEB'))
        t%on_surface_muted = theme_rgb(int(z'A0A6B2'))
        t%primary = theme_rgb(int(z'374B69'))
        t%on_primary = t%on_surface
        t%focus = theme_rgb(int(z'FFDC5A'))
        t%link = theme_rgb(int(z'6CB6FF'))
    end function theme_plain

    pure function theme_classic() result(t)
        !! Windows 95 standard colours and dialog metrics: 11 px text, 23 px
        !! buttons, 13 px check boxes, 16 px scroll bars with arrows.
        type(ui_theme_t) :: t
        t%name = "classic"
        t%kind = STYLE_CLASSIC
        t%text_size = [11.0, 11.0, 11.0, 11.0, 16.0, 11.0]
        t%text_face = [FACE_REGULAR, FACE_REGULAR, FACE_STRONG, FACE_STRONG, FACE_MONO, &
            FACE_REGULAR]
        t%line_factor = 13.0 / 11.0
        t%fonts(FACE_REGULAR) = ui_font_t(families=[character(64) :: "MS Sans Serif", &
            "Helvetica", "", ""], style="Regular", pixel=.true., grid=11.0, &
            package="chicago95 fonts (chicago95-fonts)")
        t%fonts(FACE_STRONG) = ui_font_t(families=[character(64) :: "MS Sans Serif", &
            "Helvetica", "", ""], style="Bold", pixel=.true., grid=11.0, &
            package="chicago95 fonts (chicago95-fonts)")
        t%fonts(FACE_MONO) = ui_font_t(families=[character(64) :: &
            "More Perfect DOS VGA", "Courier", "", ""], style="Regular", pixel=.true., &
            grid=16.0, package="More Perfect DOS VGA (ttf-perfectdos)")
        t%control_height = 23.0
        t%control_padding = 10.0
        t%control_min_width = 75.0
        t%input_padding = 4.0
        t%scroll_padding = 4.0
        t%scrollbar_width = 16.0
        t%scroll_arrows = .true.
        t%check_size = 13.0
        t%check_gap = 6.0
        t%tab_height = 21.0
        t%slider_thumb = 11.0
        t%gap = 6.0
        t%margin = 8.0
        t%face = theme_rgb(int(z'C0C0C0'))
        t%hilight = theme_rgb(int(z'FFFFFF'))
        t%light = theme_rgb(int(z'DFDFDF'))
        t%shadow = theme_rgb(int(z'808080'))
        t%dark_shadow = theme_rgb(int(z'000000'))
        t%caption = theme_rgb(int(z'000080'))
        t%on_caption = theme_rgb(int(z'FFFFFF'))
        t%window = t%face
        t%surface = t%face
        t%surface_low = t%face
        t%surface_high = t%face
        t%on_surface = theme_rgb(int(z'000000'))
        t%on_surface_muted = t%on_surface
        t%disabled = t%shadow
        t%primary = t%face
        t%on_primary = t%on_surface
        t%tonal = t%face
        t%on_tonal = t%on_surface
        t%outline = t%dark_shadow
        t%outline_variant = t%shadow
        t%field = theme_rgb(int(z'FFFFFF'))
        t%on_field = t%on_surface
        t%selection = t%caption
        t%on_selection = t%on_caption
        t%focus = t%dark_shadow
        t%link = theme_rgb(int(z'0000FF'))
        t%positive = theme_rgb(int(z'008000'))
        t%negative = theme_rgb(int(z'800000'))
        t%attention = theme_rgb(int(z'808000'))
        ! keyword, string, comment, number, type, preproc, added, removed, hunk
        t%code = [theme_rgb(int(z'000080')), theme_rgb(int(z'800000')), &
            theme_rgb(int(z'008000')), theme_rgb(int(z'008080')), theme_rgb(int(z'800080')), &
            theme_rgb(int(z'808000')), theme_rgb(int(z'008000')), theme_rgb(int(z'800000')), &
            theme_rgb(int(z'000080'))]
    end function theme_classic

    pure function theme_material(dark) result(t)
        !! Material Design 3 baseline scheme (seed #6750A4) with the M3 type
        !! scale: Body Medium 14, Body Small 12, Title Medium 16, Title Large 22,
        !! Label Large 14; 40 dp buttons, 18 dp check boxes, 48 dp tabs.
        logical, intent(in) :: dark
        type(ui_theme_t) :: t
        t%kind = STYLE_MATERIAL
        t%dark = dark
        t%name = merge("material-dark", "material     ", dark)
        t%text_size = [14.0, 12.0, 16.0, 22.0, 13.0, 14.0]
        t%text_face = [FACE_REGULAR, FACE_REGULAR, FACE_STRONG, FACE_REGULAR, FACE_MONO, &
            FACE_STRONG]
        t%line_factor = 20.0 / 14.0
        t%fonts(FACE_REGULAR) = ui_font_t(families=[character(64) :: "Roboto", "", "", ""], &
            style="Regular", package="Roboto (ttf-roboto)")
        t%fonts(FACE_STRONG) = ui_font_t(families=[character(64) :: "Roboto", "", "", ""], &
            style="Medium", package="Roboto (ttf-roboto)")
        t%fonts(FACE_MONO) = ui_font_t(families=[character(64) :: "Roboto Mono", "", "", ""], &
            style="Regular", package="Roboto Mono (ttf-roboto-mono)")
        t%control_height = 40.0
        t%control_padding = 24.0
        t%control_min_width = 64.0
        t%input_padding = 16.0
        t%scroll_padding = 12.0
        t%scrollbar_width = 12.0
        t%check_size = 18.0
        t%check_gap = 12.0
        t%tab_height = 48.0
        t%slider_thumb = 20.0
        t%control_radius = 20.0
        t%field_radius = 4.0
        t%gap = 8.0
        t%margin = 16.0
        if (.not. dark) then
            t%window = theme_rgb(int(z'FEF7FF'))
            t%surface = t%window
            t%surface_low = theme_rgb(int(z'F7F2FA'))
            t%surface_high = theme_rgb(int(z'ECE6F0'))
            t%on_surface = theme_rgb(int(z'1D1B20'))
            t%on_surface_muted = theme_rgb(int(z'49454F'))
            t%primary = theme_rgb(int(z'6750A4'))
            t%on_primary = theme_rgb(int(z'FFFFFF'))
            t%tonal = theme_rgb(int(z'E8DEF8'))
            t%on_tonal = theme_rgb(int(z'1D192B'))
            t%outline = theme_rgb(int(z'79747E'))
            t%outline_variant = theme_rgb(int(z'CAC4D0'))
            t%focus = theme_rgb(int(z'625B71'))
            t%link = t%primary
            t%positive = theme_rgb(int(z'386A20'))
            t%negative = theme_rgb(int(z'B3261E'))
            t%attention = theme_rgb(int(z'7D5700'))
            t%code = [theme_rgb(int(z'6750A4')), theme_rgb(int(z'386A20')), &
                theme_rgb(int(z'79747E')), theme_rgb(int(z'7D5260')), &
                theme_rgb(int(z'006A6A')), theme_rgb(int(z'7D5700')), &
                theme_rgb(int(z'386A20')), theme_rgb(int(z'B3261E')), &
                theme_rgb(int(z'625B71'))]
        else
            t%window = theme_rgb(int(z'141218'))
            t%surface = t%window
            t%surface_low = theme_rgb(int(z'1D1B20'))
            t%surface_high = theme_rgb(int(z'2B2930'))
            t%on_surface = theme_rgb(int(z'E6E0E9'))
            t%on_surface_muted = theme_rgb(int(z'CAC4D0'))
            t%primary = theme_rgb(int(z'D0BCFF'))
            t%on_primary = theme_rgb(int(z'381E72'))
            t%tonal = theme_rgb(int(z'4A4458'))
            t%on_tonal = theme_rgb(int(z'E8DEF8'))
            t%outline = theme_rgb(int(z'938F99'))
            t%outline_variant = theme_rgb(int(z'49454F'))
            t%focus = theme_rgb(int(z'CCC2DC'))
            t%link = t%primary
            t%positive = theme_rgb(int(z'9CD67D'))
            t%negative = theme_rgb(int(z'F2B8B5'))
            t%attention = theme_rgb(int(z'FFB95C'))
            t%code = [theme_rgb(int(z'D0BCFF')), theme_rgb(int(z'9CD67D')), &
                theme_rgb(int(z'938F99')), theme_rgb(int(z'EFB8C8')), &
                theme_rgb(int(z'4CDADA')), theme_rgb(int(z'FFB95C')), &
                theme_rgb(int(z'9CD67D')), theme_rgb(int(z'F2B8B5')), &
                theme_rgb(int(z'CCC2DC'))]
        end if
        t%disabled = theme_rgb(rgb_of(t%on_surface), 97)
        t%field = t%surface
        t%on_field = t%on_surface
        t%selection = theme_rgb(rgb_of(t%primary), 64)
        t%on_selection = t%on_surface
        t%face = t%surface
        t%hilight = t%surface
        t%light = t%surface
        t%shadow = t%outline
        t%dark_shadow = t%outline
        t%caption = t%primary
        t%on_caption = t%on_primary
    end function theme_material

    pure integer function rgb_of(c)
        !! 0xRRGGBB of a packed colour.
        integer(int32), intent(in) :: c
        rgb_of = ior(ior(ishft(int(iand(c, 255_int32)), 16), &
            ishft(int(iand(ishft(c, -8), 255_int32)), 8)), int(iand(ishft(c, -16), 255_int32)))
    end function rgb_of

    subroutine theme_named(name, t, ok)
        !! The built-in theme called `name` (case-insensitive).
        character(*), intent(in) :: name
        type(ui_theme_t), intent(out) :: t
        logical, intent(out) :: ok

        ok = .true.
        select case (lower(trim(adjustl(name))))
        case ("classic", "windows95", "win95", "chicago95")
            t = theme_classic()
        case ("material", "material-light")
            t = theme_material(.false.)
        case ("material-dark")
            t = theme_material(.true.)
        case ("plain")
            t = theme_plain()
        case default
            ok = .false.
            t = theme_plain()
        end select
    end subroutine theme_named

    function theme_current() result(t)
        !! The theme widgets and backends use now.
        type(ui_theme_t), pointer :: t
        t => theme
    end function theme_current

    subroutine theme_set(t)
        type(ui_theme_t), intent(in) :: t
        theme = t
    end subroutine theme_set

    function theme_requested(fallback) result(name)
        !! The theme the user asked for: FORTUI_THEME, else `theme =` in the
        !! FortUI config file, else `fallback`.
        character(*), intent(in) :: fallback
        character(len=:), allocatable :: name
        character(len=512) :: value, path
        integer :: n, status, u, ios, eq

        call get_environment_variable("FORTUI_THEME", value, n, status)
        if (status == 0 .and. len_trim(value) > 0) then
            name = trim(value)
            return
        end if
        name = fallback
        call get_environment_variable("XDG_CONFIG_HOME", path, n, status)
        if (status /= 0 .or. n == 0) then
            call get_environment_variable("HOME", path, n, status)
            if (status /= 0 .or. n == 0) return
            path = trim(path) // "/.config"
        end if
        path = trim(path) // "/fortui/config"
        open (newunit=u, file=trim(path), status="old", action="read", iostat=ios)
        if (ios /= 0) return
        do
            read (u, '(a)', iostat=ios) value
            if (ios /= 0) exit
            value = adjustl(value)
            if (value(1:1) == "#") cycle
            eq = index(value, "=")
            if (eq == 0) cycle
            if (lower(trim(value(1:eq - 1))) == "theme") then
                if (len_trim(value(eq + 1:)) > 0) name = trim(adjustl(value(eq + 1:)))
            end if
        end do
        close (u)
    end function theme_requested

    subroutine theme_select(name, ok)
        !! Make the built-in theme `name` current.
        character(*), intent(in) :: name
        logical, intent(out) :: ok
        type(ui_theme_t) :: t
        call theme_named(name, t, ok)
        if (ok) call theme_set(t)
    end subroutine theme_select

    pure function lower(s) result(t)
        character(*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k, c
        t = s
        do k = 1, len(s)
            c = iachar(s(k:k))
            if (c >= iachar("A") .and. c <= iachar("Z")) t(k:k) = achar(c + 32)
        end do
    end function lower

end module fortui_theme
