CFLAGS = -Wall

all: libhack.a

libhack.a: real.o udmabuf.o util.o
	$(AR) rcs $@ $^

lint:
	cppcheck --enable=all --check-level=exhaustive --std=c11 --suppress=missingIncludeSystem *.c *.h

clean:
	rm -f libhack.a *.o

.PHONY: all clean
