CFLAGS = -Wall -I../libchan -I../libhack

all: channel

channel: channel.c ../libchan/libchan.a ../libhack/libhack.a

lint:
	cppcheck --enable=all --check-level=exhaustive --std=c11 --suppress=missingIncludeSystem *.c *.h

clean:
	rm -f channel

.PHONY: all lint clean
