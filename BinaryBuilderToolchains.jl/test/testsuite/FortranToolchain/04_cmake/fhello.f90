program fhello
    use iso_c_binding, only: c_int
    implicit none
    interface
        function c_answer() bind(c, name='c_answer')
            import :: c_int
            integer(c_int) :: c_answer
        end function c_answer
    end interface
    write(*, '(a,i0)') 'Hello from CMake, the answer is ', c_answer()
end program fhello
