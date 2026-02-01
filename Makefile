ASM=nasm
LD=ld
ASMFLAGS=-f elf64 -g
LDFLAGS=

TARGET=asm-nano
SRC=main.asm
OBJ=main.o

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.asm
	$(ASM) $(ASMFLAGS) -o $@ $<

clean:
	rm -f $(OBJ) $(TARGET)

run: $(TARGET)
	./$(TARGET)
