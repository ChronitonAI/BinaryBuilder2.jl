cmake_minimum_required(VERSION 3.13)
project(fortran_example LANGUAGES C Fortran)

add_executable(fhello fhello.f90 cpart.c)
