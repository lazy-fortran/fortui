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
    !! - "fluent", "fluent-dark": Microsoft Fluent 2 (Fluent UI web themes):
    !!   Segoe UI or its open counterpart Selawik, Cascadia Mono, 32 px controls with
    !!   visible strokes, the default for desktop apps.
    !! - "plain": the semantic default of headless and terminal backends.
    !!
    !! Fonts are never shipped: a theme names font families that fontconfig finds
    !! among the installed fonts, and backends fall back with a warning.
    !! Graphical backends take the theme from FORTUI_THEME, else from `theme =`
    !! in $XDG_CONFIG_HOME/fortui/config (~/.config/fortui/config), else the
    !! application's default (ui_init theme=, else "fluent").
    use iso_fortran_env, only: int32
    implicit none
    private

    integer, parameter, public :: STYLE_PLAIN = 0, STYLE_CLASSIC = 1, STYLE_FLUENT = 3

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

    public :: theme_plain, theme_classic, theme_fluent, theme_named
    public :: theme_current, theme_set, theme_select, theme_requested
    public :: theme_rgb, theme_names, tui_theme_requested

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
        names = [character(16) :: "fluent", "fluent-dark", "classic"]
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

    pure function theme_fluent(dark) result(t)
        !! Microsoft Fluent 2 as the Fluent UI web themes define it (webLightTheme,
        !! webDarkTheme): neutral greys with visible 1 px strokes, brand blue
        !! #0F6CBD, 4 px corners, 32 px controls, Body1 14/20, Caption1 12,
        !! Subtitle2 16 semibold, Subtitle1 20 semibold.
        logical, intent(in) :: dark
        type(ui_theme_t) :: t
        t%kind = STYLE_FLUENT
        t%dark = dark
        t%name = merge("fluent-dark", "fluent     ", dark)
        t%text_size = [14.0, 12.0, 16.0, 20.0, 13.0, 14.0]
        t%text_face = [FACE_REGULAR, FACE_REGULAR, FACE_STRONG, FACE_STRONG, FACE_MONO, &
            FACE_STRONG]
        t%line_factor = 20.0 / 14.0
        t%fonts(FACE_REGULAR) = ui_font_t(families=[character(64) :: &
            "Segoe UI Variable Text", "Segoe UI", "Selawik", ""], style="Regular", &
            package="Selawik (github.com/microsoft/Selawik)")
        t%fonts(FACE_STRONG) = ui_font_t(families=[character(64) :: &
            "Segoe UI Variable Text", "Segoe UI", "Selawik", ""], style="Semibold", &
            package="Selawik (github.com/microsoft/Selawik)")
        t%fonts(FACE_MONO) = ui_font_t(families=[character(64) :: "Cascadia Mono", "", "", &
            ""], style="Regular", package="Cascadia Mono (ttf-cascadia-code)")
        t%control_height = 32.0
        t%control_padding = 12.0
        t%control_min_width = 96.0
        t%input_padding = 10.0
        t%scroll_padding = 10.0
        t%scrollbar_width = 10.0
        t%check_size = 16.0
        t%check_gap = 8.0
        t%tab_height = 44.0
        t%slider_thumb = 20.0
        t%control_radius = 4.0
        t%field_radius = 4.0
        t%gap = 8.0
        t%margin = 16.0
        if (.not. dark) then
            t%window = theme_rgb(int(z'F5F5F5'))
            t%surface = theme_rgb(int(z'FFFFFF'))
            t%surface_low = theme_rgb(int(z'FFFFFF'))
            t%surface_high = theme_rgb(int(z'F0F0F0'))
            t%on_surface = theme_rgb(int(z'242424'))
            t%on_surface_muted = theme_rgb(int(z'616161'))
            t%disabled = theme_rgb(int(z'BDBDBD'))
            t%primary = theme_rgb(int(z'0F6CBD'))
            t%on_primary = theme_rgb(int(z'FFFFFF'))
            t%tonal = theme_rgb(int(z'FFFFFF'))
            t%on_tonal = theme_rgb(int(z'242424'))
            t%outline = theme_rgb(int(z'616161'))
            t%outline_variant = theme_rgb(int(z'D1D1D1'))
            t%field = theme_rgb(int(z'FFFFFF'))
            t%focus = theme_rgb(int(z'000000'))
            t%link = theme_rgb(int(z'115EA3'))
            t%positive = theme_rgb(int(z'107C10'))
            t%negative = theme_rgb(int(z'C50F1F'))
            t%attention = theme_rgb(int(z'BC4B09'))
            ! hover, pressed, selected fills of neutral controls
            t%hilight = theme_rgb(int(z'F5F5F5'))
            t%light = theme_rgb(int(z'E0E0E0'))
            t%shadow = theme_rgb(int(z'C7C7C7'))
            t%dark_shadow = theme_rgb(int(z'115EA3'))
            t%caption = theme_rgb(int(z'0C3B5E'))
            t%code = [theme_rgb(int(z'0F6CBD')), theme_rgb(int(z'A31515')), &
                theme_rgb(int(z'107C10')), theme_rgb(int(z'098658')), &
                theme_rgb(int(z'267F99')), theme_rgb(int(z'AF00DB')), &
                theme_rgb(int(z'107C10')), theme_rgb(int(z'C50F1F')), &
                theme_rgb(int(z'616161'))]
        else
            t%window = theme_rgb(int(z'1F1F1F'))
            t%surface = theme_rgb(int(z'292929'))
            t%surface_low = theme_rgb(int(z'292929'))
            t%surface_high = theme_rgb(int(z'333333'))
            t%on_surface = theme_rgb(int(z'FFFFFF'))
            t%on_surface_muted = theme_rgb(int(z'ADADAD'))
            t%disabled = theme_rgb(int(z'5C5C5C'))
            t%primary = theme_rgb(int(z'115EA3'))
            t%on_primary = theme_rgb(int(z'FFFFFF'))
            t%tonal = theme_rgb(int(z'292929'))
            t%on_tonal = theme_rgb(int(z'FFFFFF'))
            t%outline = theme_rgb(int(z'ADADAD'))
            t%outline_variant = theme_rgb(int(z'666666'))
            t%field = theme_rgb(int(z'292929'))
            t%focus = theme_rgb(int(z'FFFFFF'))
            t%link = theme_rgb(int(z'479EF5'))
            t%positive = theme_rgb(int(z'54B054'))
            t%negative = theme_rgb(int(z'DC626D'))
            t%attention = theme_rgb(int(z'FAA06B'))
            t%hilight = theme_rgb(int(z'3D3D3D'))
            t%light = theme_rgb(int(z'1F1F1F'))
            t%shadow = theme_rgb(int(z'757575'))
            t%dark_shadow = theme_rgb(int(z'0F6CBD'))
            t%caption = theme_rgb(int(z'0C3B5E'))
            t%code = [theme_rgb(int(z'479EF5')), theme_rgb(int(z'CE9178')), &
                theme_rgb(int(z'6A9955')), theme_rgb(int(z'B5CEA8')), &
                theme_rgb(int(z'4EC9B0')), theme_rgb(int(z'C586C0')), &
                theme_rgb(int(z'54B054')), theme_rgb(int(z'DC626D')), &
                theme_rgb(int(z'ADADAD'))]
        end if
        t%on_field = t%on_surface
        t%selection = theme_rgb(rgb_of(t%primary), 80)
        t%on_selection = t%on_surface
        t%face = t%surface
        t%on_caption = theme_rgb(int(z'FFFFFF'))
    end function theme_fluent

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
        case ("fluent", "fluent-light", "fluent2")
            t = theme_fluent(.false.)
        case ("fluent-dark")
            t = theme_fluent(.true.)
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
        name = setting("FORTUI_THEME", "theme", fallback)
    end function theme_requested

    function tui_theme_requested() result(name)
        !! The terminal look: FORTUI_TUI_THEME, else `tui_theme =` in the config
        !! file, else "cua" (IBM Common User Access colours on white panels);
        !! "dark" keeps the same structure in dark colours.
        character(len=:), allocatable :: name
        name = lower(setting("FORTUI_TUI_THEME", "tui_theme", "cua"))
    end function tui_theme_requested

    function setting(env_name, key, fallback) result(value)
        !! An environment variable, else `key = value` in
        !! $XDG_CONFIG_HOME/fortui/config (~/.config/fortui/config), else `fallback`.
        character(*), intent(in) :: env_name, key, fallback
        character(len=:), allocatable :: value
        character(len=512) :: line, path
        integer :: n, status, u, ios, eq

        call get_environment_variable(env_name, line, n, status)
        if (status == 0 .and. len_trim(line) > 0) then
            value = trim(line)
            return
        end if
        value = fallback
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
            read (u, '(a)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (line(1:1) == "#") cycle
            eq = index(line, "=")
            if (eq == 0) cycle
            if (lower(trim(line(1:eq - 1))) == key) then
                if (len_trim(line(eq + 1:)) > 0) value = trim(adjustl(line(eq + 1:)))
            end if
        end do
        close (u)
    end function setting

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
