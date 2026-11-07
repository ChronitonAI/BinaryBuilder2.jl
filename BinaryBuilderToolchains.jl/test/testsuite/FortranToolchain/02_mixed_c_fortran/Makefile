PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include ../common.mk

CMAIN := $(PROJECT_DIR_BUILD)/cmain$(exeext)
FMAIN := $(PROJECT_DIR_BUILD)/fmain$(exeext)
CMAIN_SHARED := $(PROJECT_DIR_BUILD)/cmain_shared$(exeext)
LIBFFUNCS := $(PROJECT_DIR_BUILD)/libffuncs/libffuncs.$(dlext)
all: $(CMAIN) $(FMAIN) $(CMAIN_SHARED)

$(PROJECT_DIR_BUILD) $(PROJECT_DIR_BUILD)/libffuncs:
	mkdir -p $@

$(PROJECT_DIR_BUILD)/cfuncs.o: cfuncs.c | $(PROJECT_DIR_BUILD)
	$(CC) -c -o $@ $(CPPFLAGS) $(CFLAGS) -fPIC $<

# (`ffuncs.mod` goes to the build directory)
$(PROJECT_DIR_BUILD)/ffuncs.o: ffuncs.f90 | $(PROJECT_DIR_BUILD)
	$(FC) -c -o $@ $(FFLAGS) -fPIC -J$(PROJECT_DIR_BUILD) $<

# A C program, linked by the C compiler, which needs the Fortran runtime spelled out
$(CMAIN): cmain.c $(PROJECT_DIR_BUILD)/ffuncs.o $(PROJECT_DIR_BUILD)/cfuncs.o
	$(CC) -o $@ $(CPPFLAGS) $(CFLAGS) $^ $(LDFLAGS) -lgfortran -lm

# A Fortran program, linked by the Fortran compiler, calling C
$(FMAIN): fmain.f90 $(PROJECT_DIR_BUILD)/ffuncs.o $(PROJECT_DIR_BUILD)/cfuncs.o
	$(FC) -o $@ $(FFLAGS) -I$(PROJECT_DIR_BUILD) $^ $(LDFLAGS)

# A shared library built by the Fortran compiler, and a C program linked against it
$(LIBFFUNCS): $(PROJECT_DIR_BUILD)/ffuncs.o $(PROJECT_DIR_BUILD)/cfuncs.o | $(PROJECT_DIR_BUILD)/libffuncs
	$(FC) -shared -o $@ $(FFLAGS) $^ $(LDFLAGS)

$(CMAIN_SHARED): cmain.c $(LIBFFUNCS)
	$(CC) -o $@ $(CPPFLAGS) $(CFLAGS) $< -L$(dir $(LIBFFUNCS)) $(call rpath,libffuncs) -lffuncs $(LDFLAGS)

compile: $(CMAIN) $(FMAIN) $(CMAIN_SHARED)

clean:
	rm -rf $(PROJECT_DIR_BUILD)

run: compile
	@$(CMAIN)
	@$(FMAIN)
	@$(CMAIN_SHARED)

check: compile
	@[ "$$($(CMAIN))" = "$$(printf 'C got: 14.0\nfortran says: 14.0')" ]
	@[ "$$($(FMAIN))" = "$$(printf 'hello from C, n = 2\nsum of squares: 25.0')" ]
	@[ "$$($(CMAIN_SHARED))" = "$$(printf 'C got: 14.0\nfortran says: 14.0')" ]

.PHONY: compile
