IVERILOG ?= iverilog
VERILATOR ?= verilator

RTL = ../rtl
MACROS = assert.v
TESTS = $(patsubst %.v,%.vvp,$(wildcard *_tb.v))

all: lint tests

lint: *_tb.v
	for file in $^; do \
		$(VERILATOR) -lint-only --timing -Wall -Wno-PINCONNECTEMPTY -Wno-PINMISSING -y $(RTL) $$file; \
	done

tests: $(TESTS)
	./run_tests.sh

channel_tb.vvp: channel_tb.v $(RTL)/channel.v $(RTL)/mock_cu.v $(MACROS)

%_tb.vvp:
	$(IVERILOG) -o $@ $^

clean:
	rm -f *.vvp *.vcd

.PHONY: all lint tests clean
