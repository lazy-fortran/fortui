module fortui_pwg_sizes
    !! Names of paper sizes (PWG 5101.1 self-describing media names) for sizes
    !! in hundredths of a millimetre, chosen as libcups chooses them
    !! (pwgMediaForSize): a listed size within 0.5 mm, the later one of two
    !! equally close, else a custom name such as "custom_120x120mm_120x120mm".
    !! The table holds PWG 5101.1's standard sizes in the order libcups lists
    !! them (cups/pwg-media.c, CUPS 2.4, Apache-2.0).
    implicit none
    private
    public :: pwg_size_name, pwg_size_of

    integer, parameter :: N = 211
    character(len=26), parameter :: NAMES(N) = [character(len=26) :: &
        "na_index-3x5_3x5in", &
        "na_personal_3.625x6.5in", &
        "na_monarch_3.875x7.5in", &
        "na_number-9_3.875x8.875in", &
        "na_index-4x6_4x6in", &
        "na_number-10_4.125x9.5in", &
        "na_a2_4.375x5.75in", &
        "na_number-11_4.5x10.375in", &
        "na_number-12_4.75x11in", &
        "na_5x7_5x7in", &
        "na_index-5x8_5x8in", &
        "na_number-14_5x11.5in", &
        "na_invoice_5.5x8.5in", &
        "na_index-4x6-ext_6x8in", &
        "na_6x9_6x9in", &
        "na_c5_6.5x9.5in", &
        "na_7x9_7x9in", &
        "na_executive_7.25x10.5in", &
        "na_govt-letter_8x10in", &
        "na_govt-legal_8x13in", &
        "na_quarto_8.5x10.83in", &
        "na_letter_8.5x11in", &
        "na_fanfold-eur_8.5x12in", &
        "na_letter-plus_8.5x12.69in", &
        "na_foolscap_8.5x13in", &
        "na_oficio_8.5x13.4in", &
        "na_legal_8.5x14in", &
        "na_super-a_8.94x14in", &
        "na_9x11_9x11in", &
        "na_arch-a_9x12in", &
        "na_letter-extra_9.5x12in", &
        "na_legal-extra_9.5x15in", &
        "na_10x11_10x11in", &
        "na_10x13_10x13in", &
        "na_10x14_10x14in", &
        "na_10x15_10x15in", &
        "na_11x12_11x12in", &
        "na_edp_11x14in", &
        "na_fanfold-us_11x14.875in", &
        "na_11x15_11x15in", &
        "na_ledger_11x17in", &
        "na_eur-edp_12x14in", &
        "na_arch-b_12x18in", &
        "na_12x19_12x19in", &
        "na_b-plus_12x19.17in", &
        "na_super-b_13x19in", &
        "na_c_17x22in", &
        "na_arch-c_18x24in", &
        "na_d_22x34in", &
        "na_arch-d_24x36in", &
        "na_arch-e2_26x38in", &
        "na_arch-e3_27x39in", &
        "asme_f_28x40in", &
        "na_wide-format_30x42in", &
        "na_e_34x44in", &
        "na_arch-e_36x48in", &
        "na_f_44x68in", &
        "iso_a10_26x37mm", &
        "iso_a9_37x52mm", &
        "iso_a8_52x74mm", &
        "iso_a7_74x105mm", &
        "iso_a6_105x148mm", &
        "iso_a5_148x210mm", &
        "iso_a5-extra_174x235mm", &
        "iso_a4_210x297mm", &
        "iso_a4-tab_225x297mm", &
        "iso_a4-extra_235.5x322.3mm", &
        "iso_a3_297x420mm", &
        "iso_a4x3_297x630mm", &
        "iso_a4x4_297x841mm", &
        "iso_a4x5_297x1051mm", &
        "iso_a4x6_297x1261mm", &
        "iso_a4x7_297x1471mm", &
        "iso_a4x8_297x1682mm", &
        "iso_a4x9_297x1892mm", &
        "iso_a3-extra_322x445mm", &
        "iso_a2_420x594mm", &
        "iso_a3x3_420x891mm", &
        "iso_a3x4_420x1189mm", &
        "iso_a3x5_420x1486mm", &
        "iso_a3x6_420x1783mm", &
        "iso_a3x7_420x2080mm", &
        "iso_a1_594x841mm", &
        "iso_a2x3_594x1261mm", &
        "iso_a2x4_594x1682mm", &
        "iso_a2x5_594x2102mm", &
        "iso_a0_841x1189mm", &
        "iso_a1x3_841x1783mm", &
        "iso_a1x4_841x2378mm", &
        "iso_2a0_1189x1682mm", &
        "iso_a0x3_1189x2523mm", &
        "iso_b10_31x44mm", &
        "iso_b9_44x62mm", &
        "iso_b8_62x88mm", &
        "iso_b7_88x125mm", &
        "iso_b6_125x176mm", &
        "iso_b6c4_125x324mm", &
        "iso_b5_176x250mm", &
        "iso_b5-extra_201x276mm", &
        "iso_b4_250x353mm", &
        "iso_b3_353x500mm", &
        "iso_b2_500x707mm", &
        "iso_b1_707x1000mm", &
        "iso_b0_1000x1414mm", &
        "iso_c10_28x40mm", &
        "iso_c9_40x57mm", &
        "iso_c8_57x81mm", &
        "iso_c7_81x114mm", &
        "iso_c7c6_81x162mm", &
        "iso_c6_114x162mm", &
        "iso_c6c5_114x229mm", &
        "iso_c5_162x229mm", &
        "iso_c4_229x324mm", &
        "iso_c3_324x458mm", &
        "iso_c2_458x648mm", &
        "iso_c1_648x917mm", &
        "iso_c0_917x1297mm", &
        "iso_dl_110x220mm", &
        "iso_ra4_215x305mm", &
        "iso_sra4_225x320mm", &
        "iso_ra3_305x430mm", &
        "iso_sra3_320x450mm", &
        "iso_ra2_430x610mm", &
        "iso_sra2_450x640mm", &
        "iso_ra1_610x860mm", &
        "iso_sra1_640x900mm", &
        "iso_ra0_860x1220mm", &
        "iso_sra0_900x1280mm", &
        "jis_b10_32x45mm", &
        "jis_b9_45x64mm", &
        "jis_b8_64x91mm", &
        "jis_b7_91x128mm", &
        "jis_b6_128x182mm", &
        "jis_b5_182x257mm", &
        "jis_b4_257x364mm", &
        "jis_b3_364x515mm", &
        "jis_b2_515x728mm", &
        "jis_b1_728x1030mm", &
        "jis_b0_1030x1456mm", &
        "jis_exec_216x330mm", &
        "jpn_kaku1_270x382mm", &
        "jpn_kaku2_240x332mm", &
        "jpn_kaku3_216x277mm", &
        "jpn_kaku4_197x267mm", &
        "jpn_kaku5_190x240mm", &
        "jpn_kaku7_142x205mm", &
        "jpn_kaku8_119x197mm", &
        "jpn_chou4_90x205mm", &
        "jpn_hagaki_100x148mm", &
        "jpn_you4_105x235mm", &
        "jpn_you6_98x190mm", &
        "jpn_chou2_111.1x146mm", &
        "jpn_chou3_120x235mm", &
        "jpn_chou40_90x225mm", &
        "jpn_oufuku_148x200mm", &
        "jpn_kahu_240x322.1mm", &
        "prc_32k_97x151mm", &
        "prc_1_102x165mm", &
        "prc_2_102x176mm", &
        "prc_4_110x208mm", &
        "prc_8_120x309mm", &
        "prc_6_120x320mm", &
        "prc_16k_146x215mm", &
        "prc_7_160x230mm", &
        "om_juuro-ku-kai_198x275mm", &
        "om_pa-kai_267x389mm", &
        "om_dai-pa-kai_275x395mm", &
        "roc_16k_7.75x10.75in", &
        "roc_8k_10.75x15.5in", &
        "oe_business-card_2x3.5in", &
        "oe_photo-l_3.5x5in", &
        "oe_square-photo_4x4in", &
        "oe_square-photo_5x5in", &
        "oe_photo-s8r_8x12in", &
        "oe_photo-10r_10x12in", &
        "oe_photo-12r_12x15in", &
        "oe_12x16_12x16in", &
        "oe_14x17_14x17in", &
        "oe_photo-14x18_14x18in", &
        "oe_photo-16r_16x20in", &
        "oe_a2plus_17x24in", &
        "oe_18x22_18x22in", &
        "oe_photo-20r_20x24in", &
        "oe_photo-22x28_22x28in", &
        "oe_photo-22r_22x29.5in", &
        "oe_photo-24x30_24x30in", &
        "oe_photo-24r_24x31.5in", &
        "oe_photo-30r_30x40in", &
        "om_business-card_55x85mm", &
        "om_business-card_55x91mm", &
        "om_card_54x86mm", &
        "om_square-photo_89x89mm", &
        "om_dsc-photo_89x119mm", &
        "om_small-photo_100x150mm", &
        "om_wide-photo_100x200mm", &
        "om_italian_110x230mm", &
        "om_medium-photo_130x180mm", &
        "om_16k_184x260mm", &
        "om_16k_195x270mm", &
        "om_large-photo_200x300mm", &
        "om_folio_210x330mm", &
        "om_folio-sp_215x315mm", &
        "om_invite_220x220mm", &
        "om_photo-30x40_300x400mm", &
        "om_photo-30x45_300x450mm", &
        "om_photo-35x46_350x460mm", &
        "om_photo-40x60_400x600mm", &
        "om_photo-50x75_500x750mm", &
        "om_photo-50x76_500x760mm", &
        "om_photo-60x90_600x900mm", &
        "disc_standard_40x118mm"]
    integer, parameter :: WIDTHS(N) = [ &
        7620, 9207, 9842, 9842, 10160, 10477, 11112, 11430, 12065, 12700, &
        12700, 12700, 13970, 15240, 15240, 16510, 17780, 18415, 20320, 20320, &
        21590, 21590, 21590, 21590, 21590, 21590, 21590, 22707, 22860, 22860, &
        24130, 24130, 25400, 25400, 25400, 25400, 27940, 27940, 27940, 27940, &
        27940, 30480, 30480, 30480, 30480, 33020, 43180, 45720, 55880, 60960, &
        66040, 68580, 71120, 76200, 86360, 91440, 111760, 2600, 3700, 5200, &
        7400, 10500, 14800, 17400, 21000, 22500, 23550, 29700, 29700, 29700, &
        29700, 29700, 29700, 29700, 29700, 32200, 42000, 42000, 42000, 42000, &
        42000, 42000, 59400, 59400, 59400, 59400, 84100, 84100, 84100, 118900, &
        118900, 3100, 4400, 6200, 8800, 12500, 12500, 17600, 20100, 25000, &
        35300, 50000, 70700, 100000, 2800, 4000, 5700, 8100, 8100, 11400, &
        11400, 16200, 22900, 32400, 45800, 64800, 91700, 11000, 21500, 22500, &
        30500, 32000, 43000, 45000, 61000, 64000, 86000, 90000, 3200, 4500, &
        6400, 9100, 12800, 18200, 25700, 36400, 51500, 72800, 103000, 21600, &
        27000, 24000, 21600, 19700, 19000, 14200, 11900, 9000, 10000, 10500, &
        9800, 11110, 12000, 9000, 14800, 24000, 9700, 10200, 10200, 11000, &
        12000, 12000, 14600, 16000, 19800, 26700, 27500, 19685, 27305, 5080, &
        8890, 10160, 12700, 20320, 25400, 30480, 30480, 35560, 35560, 40640, &
        43180, 45720, 50800, 55880, 55880, 60960, 60960, 76200, 5500, 5500, &
        5400, 8900, 8900, 10000, 10000, 11000, 13000, 18400, 19500, 20000, &
        21000, 21500, 22000, 30000, 30000, 35000, 40000, 50000, 50000, 60000, &
        11800]
    integer, parameter :: LENGTHS(N) = [ &
        12700, 16510, 19050, 22542, 15240, 24130, 14605, 26352, 27940, 17780, &
        20320, 29210, 21590, 20320, 22860, 24130, 22860, 26670, 25400, 33020, &
        27508, 27940, 30480, 32232, 33020, 34036, 35560, 35560, 27940, 30480, &
        30480, 38100, 27940, 33020, 35560, 38100, 30480, 35560, 37782, 38100, &
        43180, 35560, 45720, 48260, 48691, 48260, 55880, 60960, 86360, 91440, &
        96520, 99060, 101600, 106680, 111760, 121920, 172720, 3700, 5200, 7400, &
        10500, 14800, 21000, 23500, 29700, 29700, 32230, 42000, 63000, 84100, &
        105100, 126100, 147100, 168200, 189200, 44500, 59400, 89100, 118900, 148600, &
        178300, 208000, 84100, 126100, 168200, 210200, 118900, 178300, 237800, 168200, &
        252300, 4400, 6200, 8800, 12500, 17600, 32400, 25000, 27600, 35300, &
        50000, 70700, 100000, 141400, 4000, 5700, 8100, 11400, 16200, 16200, &
        22900, 22900, 32400, 45800, 64800, 91700, 129700, 22000, 30500, 32000, &
        43000, 45000, 61000, 64000, 86000, 90000, 122000, 128000, 4500, 6400, &
        9100, 12800, 18200, 25700, 36400, 51500, 72800, 103000, 145600, 33000, &
        38200, 33200, 27700, 26700, 24000, 20500, 19700, 20500, 14800, 23500, &
        19000, 14600, 23500, 22500, 20000, 32210, 15100, 16500, 17600, 20800, &
        30900, 32000, 21500, 23000, 27500, 38900, 39500, 27305, 39370, 8890, &
        12700, 10160, 12700, 30480, 30480, 38100, 40640, 43180, 45720, 50800, &
        60960, 55880, 60960, 71120, 74930, 76200, 80010, 101600, 8500, 9100, &
        8600, 8900, 11900, 15000, 20000, 23000, 18000, 26000, 27000, 30000, &
        33000, 31500, 22000, 40000, 45000, 46000, 60000, 75000, 76000, 90000, &
        11800]

contains

    function pwg_size_name(width, length) result(name)
        integer, intent(in) :: width, length
        character(len=:), allocatable :: name
        integer :: k, dw, dl, best, best_dw, best_dl
        best = 0
        best_dw = 999
        best_dl = 999
        do k = 1, N
            dw = abs(WIDTHS(k) - width)
            dl = abs(LENGTHS(k) - length)
            if (dw == 0 .and. dl == 0) then
                name = trim(NAMES(k))
                return
            else if (dw <= 50 .and. dl <= 50 .and. dw <= best_dw .and. dl <= best_dl) then
                best = k
                best_dw = dw
                best_dl = dl
            end if
        end do
        if (best > 0) then
            name = trim(NAMES(best))
            return
        end if
        if (mod(width, 635) == 0 .and. mod(length, 635) == 0) then
            name = inches(width) // "x" // inches(length) // "in"
        else
            name = millimetres(width) // "x" // millimetres(length) // "mm"
        end if
        name = "custom_" // name // "_" // name
    end function pwg_size_name

    subroutine pwg_size_of(name, width, length)
        !! Width and length of a self-describing name ("..._4x6in", "..._210x297mm"),
        !! 0 when it has none.
        character(*), intent(in) :: name
        integer, intent(out) :: width, length
        character(len=:), allocatable :: dims
        integer :: b, x, ios
        real(8) :: w, l, unit
        width = 0
        length = 0
        b = index(name, "_", back=.true.)
        if (b == 0 .or. len(name) - b < 5) return
        dims = name(b + 1:)
        select case (dims(len(dims) - 1:))
        case ("in")
            unit = 2540
        case ("mm")
            unit = 100
        case default
            return
        end select
        dims = dims(1:len(dims) - 2)
        x = index(dims, "x")
        if (x == 0) return
        read (dims(1:x - 1), *, iostat=ios) w
        if (ios /= 0) return
        read (dims(x + 1:), *, iostat=ios) l
        if (ios /= 0) return
        width = nint(w * unit)
        length = nint(l * unit)
    end subroutine pwg_size_of

    function inches(v) result(s)
        !! Thousandths of an inch, rounded, without trailing zeros.
        integer, intent(in) :: v
        character(len=:), allocatable :: s
        integer :: whole, frac
        whole = v / 2540
        frac = (mod(v, 2540) * 1000 + 1270) / 2540
        if (frac >= 1000) then
            whole = whole + 1
            frac = frac - 1000
        end if
        s = digits(whole, frac, 3)
    end function inches

    function millimetres(v) result(s)
        integer, intent(in) :: v
        character(len=:), allocatable :: s
        s = digits(v / 100, mod(v, 100), 2)
    end function millimetres

    function digits(whole, frac, places) result(s)
        integer, intent(in) :: whole, frac, places
        character(len=:), allocatable :: s
        character(len=24) :: buf
        character(len=8) :: f
        integer :: k
        write (buf, '(i0)') whole
        s = trim(buf)
        if (frac == 0) return
        write (f, '(i0.' // achar(48 + places) // ')') frac
        k = places
        do while (f(k:k) == "0")
            k = k - 1
        end do
        s = s // "." // f(1:k)
    end function digits

end module fortui_pwg_sizes
