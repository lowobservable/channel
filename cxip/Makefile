CFLAGS = -Wall -W -I../libchan -I../libhack -I.

all: cxip

cxip: cxip.c cxip_protocol.c ../libchan/libchan.a ../libhack/libhack.a

lint:
	cppcheck --enable=all --check-level=exhaustive --std=c11 --inline-suppr --suppress=missingIncludeSystem *.c *.h

clean:
	rm -f cxip

.PHONY: all lint clean
