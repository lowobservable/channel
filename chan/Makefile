CFLAGS = -Wall -I../libhack

all: test_mock test_wrap

test_mock: test_mock.c chan.o mock_cu.o ../libhack/libhack.a
test_wrap: test_wrap.c ../libhack/libhack.a

clean:
	rm -f *.o test_mock test_wrap

.PHONY: all clean
