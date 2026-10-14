# VelvetDOS -- GNU GPLv3. Cross-builds on Linux using GNU binutils.
AS ?= as
LD ?= ld
PYTHON ?= python3
BUILD := build
IMAGE := $(BUILD)/velvetdos-0.10.0.img

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

$(BUILD)/memory.o: programs/memory.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/memory.padded: $(BUILD)/memory.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/MEMORY.COM: $(BUILD)/memory.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/exedemo.o: programs/exedemo.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/exedemo.raw: $(BUILD)/exedemo.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/EXEDEMO.EXE: $(BUILD)/exedemo.raw tools/mkmz.py
	$(PYTHON) tools/mkmz.py $< $@

$(BUILD)/exechk.o: programs/exechk.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/exechk.raw: $(BUILD)/exechk.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/EXECHK.EXE: $(BUILD)/exechk.raw tools/mkmz.py
	$(PYTHON) tools/mkmz.py $< $@

$(BUILD)/BADMZ.EXE: $(BUILD)/EXECHK.EXE tools/mkbadmz.py
	$(PYTHON) tools/mkbadmz.py $< $@

$(BUILD)/read.o: programs/read.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/read.padded: $(BUILD)/read.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/READ.COM: $(BUILD)/read.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

# Each 8086 .COM is linked at offset zero with a 0x100-byte origin.
$(BUILD)/%.o: programs/%.s | $(BUILD)
	$(AS) --32 -o $@ $<
$(BUILD)/%.padded: $(BUILD)/%.o
	$(LD) -m elf_i386 --oformat binary -Ttext 0 -o $@ $<
$(BUILD)/WRITE.COM: $(BUILD)/write.padded
	dd if=$< of=$@ bs=1 skip=256 status=none
$(BUILD)/APPEND.COM: $(BUILD)/append.padded
	dd if=$< of=$@ bs=1 skip=256 status=none
$(BUILD)/DELETE.COM: $(BUILD)/delete.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/PATHS.COM: $(BUILD)/paths.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/RECHECK.COM: $(BUILD)/recheck.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/FINDTEST.COM: $(BUILD)/findtest.padded
	dd if=$< of=$@ bs=1 skip=256 status=none
$(BUILD)/VLIST.COM: $(BUILD)/vlist.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/DIRGROW.COM: $(BUILD)/dirgrow.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/EXECCHK.COM: $(BUILD)/execchk.padded
	dd if=$< of=$@ bs=1 skip=256 status=none
$(BUILD)/HNDCHILD.COM: $(BUILD)/hndchild.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/COMMAND.COM: $(BUILD)/command.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/PSPTEST.COM: $(BUILD)/psptest.padded
	dd if=$< of=$@ bs=1 skip=256 status=none
$(BUILD)/EXITTEST.COM: $(BUILD)/exittest.padded
	dd if=$< of=$@ bs=1 skip=256 status=none

$(BUILD)/README.TXT: | $(BUILD)
	$(PYTHON) -c "from pathlib import Path; Path('$@').write_bytes(b'VELVETDOS 0.10.0 PROGRAM API TEST\r\n' + b'FAT12 READ TEST DATA!\r\n' * 40)"

$(IMAGE): $(BUILD)/boot.bin $(BUILD)/kernel.bin $(BUILD)/HELLO.COM $(BUILD)/RETURN.COM $(BUILD)/CHAIN.COM $(BUILD)/EXEDEMO.EXE $(BUILD)/EXECHK.EXE $(BUILD)/BADMZ.EXE $(BUILD)/READ.COM $(BUILD)/MEMORY.COM $(BUILD)/README.TXT $(BUILD)/WRITE.COM $(BUILD)/APPEND.COM $(BUILD)/DELETE.COM $(BUILD)/RECHECK.COM $(BUILD)/PATHS.COM $(BUILD)/FINDTEST.COM $(BUILD)/VLIST.COM $(BUILD)/DIRGROW.COM $(BUILD)/PSPTEST.COM $(BUILD)/EXITTEST.COM $(BUILD)/COMMAND.COM $(BUILD)/EXECCHK.COM $(BUILD)/HNDCHILD.COM tools/mkfloppy.py
	$(PYTHON) tools/mkfloppy.py --boot $(BUILD)/boot.bin --kernel $(BUILD)/kernel.bin --file $(BUILD)/HELLO.COM --file $(BUILD)/RETURN.COM --file $(BUILD)/CHAIN.COM --file $(BUILD)/EXEDEMO.EXE --file $(BUILD)/EXECHK.EXE --file $(BUILD)/BADMZ.EXE --file $(BUILD)/READ.COM --file $(BUILD)/MEMORY.COM --file $(BUILD)/README.TXT --file $(BUILD)/WRITE.COM --file $(BUILD)/APPEND.COM --file $(BUILD)/DELETE.COM --file $(BUILD)/RECHECK.COM --file $(BUILD)/PATHS.COM --file $(BUILD)/FINDTEST.COM --file $(BUILD)/VLIST.COM --file $(BUILD)/DIRGROW.COM --file $(BUILD)/PSPTEST.COM --file $(BUILD)/EXITTEST.COM --file $(BUILD)/COMMAND.COM --file $(BUILD)/EXECCHK.COM --file $(BUILD)/HNDCHILD.COM --output $@

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
