VERILATOR ?= verilator

all: lint

lint: *.v
	for file in $^; do \
		$(VERILATOR) -lint-only -Wall -Wno-PINCONNECTEMPTY --quiet $$file; \
	done

.PHONY: all lint
