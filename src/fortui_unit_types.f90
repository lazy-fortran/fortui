module fortui_unit_types
! CONCRETE unit value system - NO POLYMORPHISM OR INHERITANCE  
! All unit conversions handled procedurally through fortui_units module
use fortui_units, only: ui_context, unit_value
implicit none
private

! NO ABSTRACT TYPES - CONCRETE ONLY
! unit_value from fortui_units is the ONLY type needed

! Re-export concrete unit_value type
public :: unit_value

! Public constructor functions for unit_value creation
public :: dp_unit, em_unit, sp_unit, px_unit, cw_unit, ch_unit
public :: inches_unit, cm_unit, mm_unit, points_unit

! Physical unit conversion constants (DPI-independent base values)
real, parameter :: INCHES_TO_DP_BASE = 96.0    ! 96 dp per inch at base DPI
real, parameter :: CM_TO_DP_BASE = 37.795      ! ~96/2.54 dp per cm
real, parameter :: MM_TO_DP_BASE = 3.7795      ! ~96/25.4 dp per mm
real, parameter :: POINTS_TO_DP_BASE = 1.333   ! ~96/72 dp per point

contains

! CONCRETE CONSTRUCTOR FUNCTIONS - NO INHERITANCE

function dp_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "dp"
end function dp_unit

function em_unit(value) result(unit)
    real, intent(in) :: value  
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "em"
end function em_unit

function sp_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "sp"
end function sp_unit

function px_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "px"
end function px_unit

function cw_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "cw"
end function cw_unit

function ch_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "ch"
end function ch_unit

function inches_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "inches"
end function inches_unit

function cm_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "cm"
end function cm_unit

function mm_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "mm"
end function mm_unit

function points_unit(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "points"
end function points_unit

end module fortui_unit_types