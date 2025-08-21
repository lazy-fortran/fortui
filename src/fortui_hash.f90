module fortui_hash
! Type-safe hash calculations for TUI diff optimization
! Addresses Issue #63: Hash calculation integer overflow due to missing type safety
use iso_fortran_env, only: int32, int64
use iso_c_binding, only: c_int, c_int32_t
implicit none
private

public :: line_hash_t, calculate_line_hash, hash_equal, tb_cell

! Hash type with overflow protection
type :: line_hash_t
    integer(int64) :: value = 0_int64
end type line_hash_t

! Terminal cell type (moved here to avoid circular dependency)
type, bind(C) :: tb_cell
    integer(c_int32_t) :: ch
    integer(c_int) :: bg
    integer(c_int) :: fg
end type tb_cell

! FNV-1a hash parameters (64-bit)
integer(int64), parameter :: FNV_OFFSET_BASIS = int(z'CBF29CE484222325', int64)
integer(int64), parameter :: FNV_PRIME = int(z'100000001B3', int64)

contains

pure function calculate_line_hash(line_cells) result(hash)
    ! Calculate type-safe hash for a line of cells using FNV-1a algorithm
    ! Resolves integer overflow vulnerability from Issue #63
    type(tb_cell), intent(in) :: line_cells(:)
    type(line_hash_t) :: hash
    
    integer :: i
    integer(int64) :: temp_hash
    integer(int32) :: ch, fg, bg
    
    ! Initialize with FNV offset basis
    temp_hash = FNV_OFFSET_BASIS
    
    do i = 1, size(line_cells)
        ! Extract cell components with type safety
        ch = int(line_cells(i)%ch, int32)
        fg = int(line_cells(i)%fg, int32)  
        bg = int(line_cells(i)%bg, int32)
        
        ! FNV-1a hash: hash = (hash XOR byte) * prime
        ! Process character
        temp_hash = ieor(temp_hash, int(ch, int64))
        temp_hash = temp_hash * FNV_PRIME
        
        ! Process foreground color
        temp_hash = ieor(temp_hash, int(fg, int64))
        temp_hash = temp_hash * FNV_PRIME
        
        ! Process background color  
        temp_hash = ieor(temp_hash, int(bg, int64))
        temp_hash = temp_hash * FNV_PRIME
    end do
    
    hash%value = temp_hash
end function calculate_line_hash

pure logical function hash_equal(hash1, hash2)
    ! Type-safe hash comparison
    type(line_hash_t), intent(in) :: hash1, hash2
    hash_equal = (hash1%value == hash2%value)
end function hash_equal

end module fortui_hash