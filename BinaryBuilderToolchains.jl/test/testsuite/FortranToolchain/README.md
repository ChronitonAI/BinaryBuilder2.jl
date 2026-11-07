# Fortran Toolchain test suite

Fortran programs that exercise the `gfortran` wrappers of a `FortranToolchain`, deployed next to
a `CToolchain` (and, for `04_cmake`, a `CMakeToolchain`) for the same platform.  It works like
the C toolchain's test suite (see `../CToolchain/README.md`): each test case has `run`, `check`
and `clean` targets, and the top-level `Makefile` runs `cleancheck-all`.

The programs that link against `libgfortran` dynamically need the toolchain's `libgfortran` at
run time, so the tests that run them put its directory on `LD_LIBRARY_PATH`.
