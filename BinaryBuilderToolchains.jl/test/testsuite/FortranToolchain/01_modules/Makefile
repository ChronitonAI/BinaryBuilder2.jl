PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include ../common.mk

MODDIR := $(PROJECT_DIR_BUILD)/include
LIBSHAPES := $(PROJECT_DIR_BUILD)/libshapes.a
MAIN := $(PROJECT_DIR_BUILD)/main$(exeext)
all: $(MAIN)

$(PROJECT_DIR_BUILD) $(MODDIR):
	mkdir -p $@

# `-J` writes `shapes.mod` to `$(MODDIR)` (instead of the current directory)
$(PROJECT_DIR_BUILD)/shapes.o: shapes.f90 | $(PROJECT_DIR_BUILD) $(MODDIR)
	$(FC) -c -o $@ $(FFLAGS) -J$(MODDIR) $<

$(LIBSHAPES): $(PROJECT_DIR_BUILD)/shapes.o
	$(AR) rcs $@ $^

# `-I` finds it there
$(MAIN): main.f90 $(LIBSHAPES)
	$(FC) -o $@ $(FFLAGS) -I$(MODDIR) $(LDFLAGS) $< -L$(PROJECT_DIR_BUILD) -lshapes
compile: $(MAIN)

clean:
	rm -rf $(PROJECT_DIR_BUILD)

run: $(MAIN)
	@$(MAIN)

check: $(MAIN)
	@[ -f $(MODDIR)/shapes.mod ]
	@[ ! -f $(PROJECT_DIR)/shapes.mod ]
	@[ "$$($(MAIN))" = "total area: 20.0" ]

.PHONY: compile
