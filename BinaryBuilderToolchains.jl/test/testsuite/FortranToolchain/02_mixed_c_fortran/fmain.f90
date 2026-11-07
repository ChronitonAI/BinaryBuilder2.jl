program fmain
    use iso_c_binding, only: c_double, c_int
    use ffuncs, only: f_sum_squares
    implicit none

    interface
        subroutine c_greet(n) bind(c, name='c_greet')
            import :: c_int
            integer(c_int), value :: n
        end subroutine c_greet
    end interface

    real(c_double) :: x(2) = [3.0_c_double, 4.0_c_double]

    call c_greet(2_c_int)
    write(*, '(a,f0.1)') 'sum of squares: ', f_sum_squares(x, 2_c_int)
end program fmain
