# Mixed C and Fortran

C and Fortran calling each other through `bind(c)`, linked three ways: a C program linked by
`$CC` (with `-lgfortran`), a Fortran program linked by `$FC`, and a C program linked against a
shared library built by `$FC`.
