module shapes
    implicit none
    private
    public :: rectangle, area

    type :: rectangle
        real :: width, height
    end type rectangle

contains

    pure real function area(r)
        type(rectangle), intent(in) :: r
        area = r%width * r%height
    end function area
end module shapes
