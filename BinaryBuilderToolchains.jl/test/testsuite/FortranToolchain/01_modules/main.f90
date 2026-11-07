program main
    use shapes, only: rectangle, area
    implicit none
    type(rectangle) :: r
    integer :: i
    real :: total

    total = 0.0
    do i = 1, 4
        r = rectangle(real(i), 2.0)
        total = total + area(r)
    end do
    write(*, '(a,f0.1)') 'total area: ', total
end program main
