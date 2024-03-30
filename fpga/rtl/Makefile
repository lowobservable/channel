VERILATOR ?= verilator

all: lint

lint: *.v
	for file in $^; do \
		$(VERILATOR) -lint-only -Wall $$file; \
	done

.PHONY: all lint
