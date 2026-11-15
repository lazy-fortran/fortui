module fortui_fonts
    !! Installed fonts for the themes' faces, found by fortfont (no fontconfig):
    !! the families a theme names in order, then the system's sans-serif or
    !! monospace with a warning naming the font package the theme wants.
    !! FortUI ships no fonts.
    use fortui_theme, only: ui_font_t, FACE_MONO
    use fortfont_find, only: font_find
    implicit none
    private

    character(len=512), save :: warned(16) = ""
    integer, save :: n_warned = 0

    public :: font_lookup, font_for

contains

    subroutine font_lookup(family, style, pixel_size, path, matched, index)
        !! File of `family` in `style` (at `pixel_size` for bitmap strikes, 0 for
        !! any) and its face in a collection; `path` is empty unless that very
        !! family is installed ("sans-serif" and "monospace" name the defaults).
        character(*), intent(in) :: family, style
        integer, intent(in) :: pixel_size
        character(len=:), allocatable, intent(out) :: path
        character(len=:), allocatable, intent(out), optional :: matched
        integer, intent(out), optional :: index
        character(len=:), allocatable :: got
        integer :: face
        call font_find(trim(family), trim(style), pixel_size, path, face, got)
        if (present(matched)) matched = got
        if (present(index)) index = face
    end subroutine font_lookup

    subroutine font_for(font, face, pixel_size, theme_name, path, pixel, index)
        !! The font file for a theme face; falls back with a warning (once).
        type(ui_font_t), intent(in) :: font
        integer, intent(in) :: face, pixel_size
        character(*), intent(in) :: theme_name
        character(len=:), allocatable, intent(out) :: path
        logical, intent(out) :: pixel
        integer, intent(out), optional :: index
        character(len=:), allocatable :: generic, matched, note
        integer :: k, idx

        pixel = font%pixel
        do k = 1, size(font%families)
            if (len_trim(font%families(k)) == 0) cycle
            call font_lookup(font%families(k), font%style, merge(pixel_size, 0, font%pixel), &
                path, index=idx)
            if (present(index)) index = idx
            if (len(path) > 0) return
        end do
        pixel = .false.
        generic = merge("monospace ", "sans-serif", face == FACE_MONO)
        call font_lookup(trim(generic), font%style, 0, path, matched, idx)
        if (len(path) == 0) call font_lookup(trim(generic), "", 0, path, matched, idx)
        if (present(index)) index = idx
        note = "fortui: theme '" // trim(theme_name) // "' wants the font '" // &
            trim(font%families(first_named(font))) // "'"
        if (len_trim(font%style) > 0) note = note // " " // trim(font%style)
        if (len_trim(font%package) > 0) note = note // " from " // trim(font%package)
        note = note // "; using '" // matched // "' instead"
        call warn_once(note)
    end subroutine font_for

    integer function first_named(font)
        !! The theme's dependency: the last family it names.
        type(ui_font_t), intent(in) :: font
        integer :: k
        first_named = 1
        do k = size(font%families), 1, -1
            if (len_trim(font%families(k)) > 0) then
                first_named = k
                return
            end if
        end do
    end function first_named

    subroutine warn_once(note)
        character(*), intent(in) :: note
        integer :: k
        do k = 1, n_warned
            if (warned(k) == note) return
        end do
        if (n_warned < size(warned)) then
            n_warned = n_warned + 1
            warned(n_warned) = note
        end if
        write (0, '(a)') note
    end subroutine warn_once

end module fortui_fonts
