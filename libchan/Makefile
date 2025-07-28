CFLAGS = -Wall -I../libhack

all: libchan.a test_3174 test_mock

libchan.a: chan_out.o chan.o mock_cu.o
	$(AR) rcs $@ $^

test_3174: test_3174.c libchan.a ../libhack/libhack.a
test_mock: test_mock.c libchan.a ../libhack/libhack.a

lint:
	cppcheck --enable=all --check-level=exhaustive --std=c11 --suppress=missingIncludeSystem *.c *.h

clean:
	rm -f *.o libchan.a test_3174 test_mock

.PHONY: all lint clean
