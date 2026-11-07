! Fortran procedures that C calls, and that call C
module ffuncs
    use iso_c_binding, only: c_double, c_int
    implicit none

    interface
        function c_square(x) bind(c, name='c_square')
            import :: c_double
            real(c_double), value :: x
            real(c_double) :: c_square
        end function c_square
    end interface

contains

    function f_sum_squares(x, n) bind(c, name='f_sum_squares') result(s)
        integer(c_int), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double) :: s
        integer :: i

        s = 0
        do i = 1, n
            s = s + c_square(x(i))
        end do
    end function f_sum_squares

    ! Uses the Fortran runtime (libgfortran) for its output
    subroutine f_report(s) bind(c, name='f_report')
        real(c_double), value :: s
        write(*, '(a,f0.1)') 'fortran says: ', s
    end subroutine f_report
end module ffuncs
