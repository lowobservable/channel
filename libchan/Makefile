CFLAGS = -Wall -I../libhack

all: test_3174 test_mock test_wrap

test_3174: test_3174.c chan.o ../libhack/libhack.a
test_mock: test_mock.c chan.o mock_cu.o ../libhack/libhack.a
test_wrap: test_wrap.c ../libhack/libhack.a

clean:
	rm -f *.o test_3174 test_mock test_wrap

.PHONY: all clean
