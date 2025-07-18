IVERILOG ?= iverilog
VERILATOR ?= verilator

RTL = ../rtl
MACROS = assert.v
TESTS = $(patsubst %.v,%.vvp,$(wildcard *_tb.v))

all: lint tests

lint: *_tb.v
	for file in $^; do \
		$(VERILATOR) -lint-only -Wall -Wno-PINCONNECTEMPTY -Wno-PINMISSING --timing --quiet -y $(RTL) $$file; \
	done

tests: $(TESTS)
	./run_tests.sh

channel_out_protocol_tb.vvp: channel_out_protocol_tb.v $(RTL)/channel_out_protocol.v $(RTL)/mock_cu.v $(RTL)/tee.v $(MACROS)
axi_mm_channel_out_tb.vvp: axi_mm_channel_out_tb.v $(RTL)/axi_mm_channel_out.v $(RTL)/channel_out_protocol.v $(RTL)/mock_cu.v $(RTL)/tee.v $(MACROS)

%_tb.vvp:
	$(IVERILOG) -o $@ $^

clean:
	rm -f *.vvp *.vcd

.PHONY: all lint tests clean
