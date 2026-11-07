subroutine lock_march(x)
    implicit none
    real, intent(inout) :: x
    x = 2.0 * x
end subroutine lock_march
