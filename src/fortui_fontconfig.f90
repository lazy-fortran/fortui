module fortui_fontconfig
    !! Installed fonts for a theme, found with fontconfig (iso_c_binding).
    !!
    !! A theme font names families in order of preference; the first one that
    !! fontconfig has (the same family, not a substitute) is used. Without any,
    !! the system's sans-serif or monospace font is used and a warning names the
    !! font package the theme wants. FortUI ships no fonts.
    use iso_c_binding
    use fortui_theme, only: ui_font_t, FACE_MONO
    implicit none
    private

    integer(c_int), parameter :: FC_MATCH_PATTERN = 0, FC_RESULT_MATCH = 0

#if defined(ENABLE_GUI) || defined(ENABLE_SDL)
    interface
        type(c_ptr) function FcNameParse(name) bind(C, name="FcNameParse")
            import :: c_ptr, c_char
            character(kind=c_char), intent(in) :: name(*)
        end function
        integer(c_int) function FcConfigSubstitute(config, pattern, kind) &
                bind(C, name="FcConfigSubstitute")
            import :: c_ptr, c_int
            type(c_ptr), value :: config, pattern
            integer(c_int), value :: kind
        end function
        subroutine FcDefaultSubstitute(pattern) bind(C, name="FcDefaultSubstitute")
            import :: c_ptr
            type(c_ptr), value :: pattern
        end subroutine
        type(c_ptr) function FcFontMatch(config, pattern, result) bind(C, name="FcFontMatch")
            import :: c_ptr, c_int
            type(c_ptr), value :: config, pattern
            integer(c_int) :: result
        end function
        integer(c_int) function FcPatternGetString(pattern, object, n, s) &
                bind(C, name="FcPatternGetString")
            import :: c_ptr, c_int, c_char
            type(c_ptr), value :: pattern
            character(kind=c_char), intent(in) :: object(*)
            integer(c_int), value :: n
            type(c_ptr) :: s
        end function
        subroutine FcPatternDestroy(pattern) bind(C, name="FcPatternDestroy")
            import :: c_ptr
            type(c_ptr), value :: pattern
        end subroutine
        integer(c_size_t) function c_strlen(s) bind(C, name="strlen")
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
        end function
    end interface
#endif

    character(len=512), save :: warned(16) = ""
    integer, save :: n_warned = 0

    public :: font_lookup, font_for

contains

    subroutine font_lookup(family, style, pixel_size, path, matched)
        !! File of `family` in `style` (at `pixel_size` for bitmap strikes, 0 for
        !! any); `path` is empty unless fontconfig has that very family.
        character(*), intent(in) :: family, style
        integer, intent(in) :: pixel_size
        character(len=:), allocatable, intent(out) :: path
        character(len=:), allocatable, intent(out), optional :: matched
        character(len=:), allocatable :: query, got
        type(c_ptr) :: pat, match, sp
        integer(c_int) :: res, ok
        character(len=16) :: num

        path = ""
        if (present(matched)) matched = ""
#if defined(ENABLE_GUI) || defined(ENABLE_SDL)
        query = trim(family)
        if (len_trim(style) > 0) query = query // ":style=" // trim(style)
        if (pixel_size > 0) then
            write (num, '(i0)') pixel_size
            query = query // ":pixelsize=" // trim(num)
        end if
        pat = FcNameParse(query // c_null_char)
        if (.not. c_associated(pat)) return
        ok = FcConfigSubstitute(c_null_ptr, pat, FC_MATCH_PATTERN)
        call FcDefaultSubstitute(pat)
        match = FcFontMatch(c_null_ptr, pat, res)
        call FcPatternDestroy(pat)
        if (.not. c_associated(match)) return
        if (FcPatternGetString(match, "family" // c_null_char, 0_c_int, sp) == FC_RESULT_MATCH) then
            got = f_str(sp)
            if (present(matched)) matched = got
            if (lower(got) == lower(trim(family)) .or. lower(trim(family)) == "sans-serif" &
                .or. lower(trim(family)) == "monospace") then
                if (FcPatternGetString(match, "file" // c_null_char, 0_c_int, sp) == &
                    FC_RESULT_MATCH) path = f_str(sp)
            end if
        end if
        call FcPatternDestroy(match)
#else
        if (len(family) + len(style) + pixel_size < 0) query = ""
#endif
    end subroutine font_lookup

    subroutine font_for(font, face, pixel_size, theme_name, path, pixel)
        !! The font file for a theme face; falls back with a warning (once).
        type(ui_font_t), intent(in) :: font
        integer, intent(in) :: face, pixel_size
        character(*), intent(in) :: theme_name
        character(len=:), allocatable, intent(out) :: path
        logical, intent(out) :: pixel
        character(len=:), allocatable :: generic, matched, note
        integer :: k

        pixel = font%pixel
        do k = 1, size(font%families)
            if (len_trim(font%families(k)) == 0) cycle
            call font_lookup(font%families(k), font%style, merge(pixel_size, 0, font%pixel), &
                path)
            if (len(path) > 0) return
        end do
        pixel = .false.
        generic = merge("monospace ", "sans-serif", face == FACE_MONO)
        call font_lookup(trim(generic), font%style, 0, path, matched)
        if (len(path) == 0) call font_lookup(trim(generic), "", 0, path, matched)
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

#if defined(ENABLE_GUI) || defined(ENABLE_SDL)
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

end module fortui_fontconfig
