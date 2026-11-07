# The C toolchain test suite's settings (CC, AR, rpath, build directory, ...)
include $(dir $(lastword $(MAKEFILE_LIST)))../CToolchain/common.mk

# `make` has a default `FC` (`f77`): only use it if the environment gives us none
ifeq ($(origin FC),default)
FC := $(CC_TARGET)-gfortran
endif
FFLAGS ?= -g -O2
