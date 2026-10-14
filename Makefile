# VelvetDOS -- GNU GPLv3. Cross-builds on Linux using GNU binutils.
AS ?= as
LD ?= ld
PYTHON ?= python3
BUILD := build
IMAGE := $(BUILD)/velvetdos-0.1.0.img

.PHONY: all image run test clean help
all: image
image: $(IMAGE)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/boot.o: boot/boot.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/boot.bin: $(BUILD)/boot.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0x7c00 -o $@ $<

$(BUILD)/kernel.o: kernel/kernel.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/kernel.bin: $(BUILD)/kernel.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<

$(BUILD)/hello.o: programs/hello.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/hello.padded: $(BUILD)/hello.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/HELLO.COM: $(BUILD)/hello.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/return.o: programs/return.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/return.padded: $(BUILD)/return.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/RETURN.COM: $(BUILD)/return.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/chain.o: programs/chain.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/chain.padded: $(BUILD)/chain.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/CHAIN.COM: $(BUILD)/chain.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(IMAGE): $(BUILD)/boot.bin $(BUILD)/kernel.bin $(BUILD)/HELLO.COM $(BUILD)/RETURN.COM $(BUILD)/CHAIN.COM tools/mkfloppy.py
	$(PYTHON) tools/mkfloppy.py --boot $(BUILD)/boot.bin --kernel $(BUILD)/kernel.bin --file $(BUILD)/HELLO.COM --file $(BUILD)/RETURN.COM --file $(BUILD)/CHAIN.COM --output $@

run: image
	qemu-system-i386 -drive file=$(IMAGE),format=raw,if=floppy -boot a -m 16 -no-reboot

test: image
	$(PYTHON) -m unittest discover -s tests -v

clean:
	rm -rf $(BUILD)

help:
	@echo 'make image : build bootable FAT12 floppy image'
	@echo 'make test  : structural/checksum/FAT file integrity tests'
	@echo 'make run   : launch floppy in QEMU (must be installed)'
