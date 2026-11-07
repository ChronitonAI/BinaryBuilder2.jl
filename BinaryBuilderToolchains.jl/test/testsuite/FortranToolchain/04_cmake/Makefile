PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include ../common.mk

FHELLO := $(PROJECT_DIR_BUILD)/fhello$(exeext)
all: $(FHELLO)

$(PROJECT_DIR_BUILD):
	mkdir -p $@

$(PROJECT_DIR_BUILD)/Makefile: $(PROJECT_DIR)/CMakeLists.txt | $(PROJECT_DIR_BUILD)
	$(CMAKE) -B$(PROJECT_DIR_BUILD) -S$(PROJECT_DIR) >$(PROJECT_DIR_BUILD)/cmake_log.txt

$(FHELLO): $(PROJECT_DIR)/fhello.f90 $(PROJECT_DIR)/cpart.c $(PROJECT_DIR_BUILD)/Makefile
	$(MAKE) -C $(PROJECT_DIR_BUILD)
compile: $(FHELLO)

clean:
	rm -rf $(PROJECT_DIR_BUILD)

run: $(FHELLO)
	@$(FHELLO)

# The Fortran compiler CMake chose is our wrapper
check: $(FHELLO)
	@grep -q 'set(CMAKE_Fortran_COMPILER ".*/wrappers/$(FC)")' $(PROJECT_DIR_BUILD)/CMakeFiles/*/CMakeFortranCompiler.cmake
	@[ "$$($(FHELLO))" = "Hello from CMake, the answer is 42" ]

.PHONY: compile
