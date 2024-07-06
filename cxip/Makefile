CFLAGS = -Wall -I../libchan -I../libhack

all: cxip

cxip: cxip.c ../libchan/libchan.a ../libhack/libhack.a

lint:
	cppcheck --enable=all --check-level=exhaustive --std=c11 --suppress=missingIncludeSystem *.c *.h

clean:
	rm -f cxip

.PHONY: all lint clean
