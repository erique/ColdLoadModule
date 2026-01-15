# Makefile for ColdLoadModule
#
# Amiga m68k cross-compilation using vasm and gcc

# Toolchain paths
AMIGA_BASE = /opt/amiga
CC = $(AMIGA_BASE)/bin/m68k-amigaos-gcc
AS = ../kickstart_build/tools/vbcc/bin/vasmm68k_mot #$(AMIGA_BASE)/bin/vasmm68k_mot
LD = $(AMIGA_BASE)/bin/m68k-amigaos-gcc
OBJDUMP = $(AMIGA_BASE)/bin/m68k-amigaos-objdump

# NDK paths
NDK = $(AMIGA_BASE)/m68k-amigaos/ndk-include
NDK_ASM = $(AMIGA_BASE)/m68k-amigaos/ndk-include

# Flags
ASFLAGS = -quiet -Fhunk -kick1hunks -nosym -I$(NDK_ASM) -DENABLE_KPRINTF -esc
CFLAGS = -O2 -Wall -fomit-frame-pointer -m68000 -mregparm -noixemul -I$(NDK) -DENABLE_KPRINTF
LDFLAGS = -noixemul -s

.PHONY: generate all clean

all: ColdLoadModule testmodule

ColdLoadModule: src/main.o src/module.o src/loadseg.o src/kprintf.o src/capture.o
	$(LD) $(LDFLAGS) -o $@ $^

testmodule: test/testmodule.o
	$(LD) -nostartfiles $(LDFLAGS) -o $@ $^

src/%.i: src/%.h
	./h2i.py $< -o $@ -- -I $(NDK)

src/capture.o: src/module.i
src/main.o: src/module.h

clean:
	rm -f src/*.o test/*.o ColdLoadModule testmodule
