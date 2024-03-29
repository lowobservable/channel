IVERILOG ?= iverilog

RTL = ../rtl
MACROS = assert.v
TESTS = $(patsubst %.v,%.vvp,$(wildcard *_tb.v))

all: lint tests

lint:
	echo "TODO"

tests: $(TESTS)
	./run_tests.sh

channel_tb.vvp: channel_tb.v $(RTL)/channel.v $(RTL)/mock_cu.v $(RTL)/terminator.v $(MACROS)

%_tb.vvp:
	$(IVERILOG) -o $@ $^

clean:
	rm -f *.vvp *.vcd

.PHONY: all lint tests clean
