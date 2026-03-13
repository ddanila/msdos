# Linux GNU Makefile for building MS-DOS 4.0 from source using kvikdos
# Each DOS tool is invoked via a wrapper script in bin/ that calls kvikdos.

SHELL    := /bin/bash
SRC      := $(CURDIR)/MS-DOS/v4.0/src
BIN      := $(CURDIR)/bin
OUT      := $(CURDIR)/out

# Tool wrappers (all invoke kvikdos internally)
MASM     := $(BIN)/masm
CL       := $(BIN)/cl
LINK     := $(BIN)/link
LIB      := $(BIN)/lib
EXE2BIN  := $(BIN)/exe2bin
BUILDIDX := $(BIN)/buildidx
BUILDMSG := $(BIN)/buildmsg
NOSRVBLD := $(BIN)/nosrvbld
DBOF     := $(BIN)/dbof
MENUBLD  := $(BIN)/menubld
CONVERT  := $(BIN)/convert

# Common MASM/CL flags (from TOOLS.INI)
COUNTRY  := usa-ms
AFLAGS   := -Mx -t
CFLAGS   := -AS -Os -Zp

# Assembler include dirs relative to each module (overridden per-module)
AINC     := -I. -ID:\\TOOLS\\INC

.PHONY: all messages mapper boot inc bios dos cmd dev select memm clean test gen-checksums deploy run-boot verify test-sys

all: messages mapper boot inc bios dos cmd dev select memm

# ---------------------------------------------------------------------------
# MESSAGES
# ---------------------------------------------------------------------------
MESSAGES_DIR := $(SRC)/MESSAGES
MESSAGES_OUT := $(MESSAGES_DIR)/$(COUNTRY).idx

messages: $(MESSAGES_OUT)

$(MESSAGES_OUT): $(MESSAGES_DIR)/USA-MS.MSG
	cd $(MESSAGES_DIR) && $(BUILDIDX) USA-MS.MSG

# ---------------------------------------------------------------------------
# MAPPER
# ---------------------------------------------------------------------------
MAPPER_DIR := $(SRC)/MAPPER
MAPPER_LIB := $(MAPPER_DIR)/MAPPER.LIB

MAPPER_OBJS := \
  CHDIR.OBJ GETVER.OBJ F_FIRST.OBJ SET_TOD.OBJ WRITE.OBJ BEEP.OBJ \
  MKDIR.OBJ EXIT.OBJ DELETE.OBJ GETCNTRY.OBJ F_CLOSE.OBJ OPEN.OBJ \
  READ.OBJ RMDIR.OBJ QCURDIR.OBJ QCURDSK.OBJ QVERIFY.OBJ QFILEMOD.OBJ \
  SVERIFY.OBJ SFILEMOD.OBJ LSEEK.OBJ SFILEINF.OBJ CLOSE.OBJ ALLOCSEG.OBJ \
  FREESEG.OBJ SEL_DISK.OBJ QFSINFO.OBJ F_NEXT.OBJ GETMSG.OBJ GET_TOD.OBJ \
  CHARIN.OBJ FLUSHBUF.OBJ DEVCONFG.OBJ REALLSEG.OBJ PUTMSG.OBJ EXECPGM.OBJ \
  QHANDTYP.OBJ CWAIT.OBJ KBDGSTAT.OBJ KBDSSTAT.OBJ CASEMAP.OBJ DBCS.OBJ \
  IOCTL.OBJ SIGHAND.OBJ ERROR.OBJ SETINT24.OBJ QFILEINF.OBJ SCURPOS.OBJ \
  SCROLLUP.OBJ WCHSTRA.OBJ SCNTRY.OBJ SETFSINF.OBJ GMACHMOD.OBJ

MAPPER_OBJ_PATHS := $(addprefix $(MAPPER_DIR)/,$(MAPPER_OBJS))

mapper: $(MAPPER_LIB)

$(MAPPER_LIB): $(MAPPER_OBJ_PATHS)
	rm -f $(MAPPER_DIR)/mapper.lib $(MAPPER_DIR)/MAPPER.LIB
	cd $(MAPPER_DIR) && $(LIB) @mapper.lbr

# Pattern rule: assemble .ASM -> .OBJ in MAPPER dir (uppercase filenames)
$(MAPPER_DIR)/%.OBJ: $(MAPPER_DIR)/%.ASM
	cd $(MAPPER_DIR) && $(MASM) "$(AFLAGS) $(AINC)" "$*.ASM,$*.OBJ;"

# ---------------------------------------------------------------------------
# BOOT
# ---------------------------------------------------------------------------
BOOT_DIR := $(SRC)/BOOT
BOOT_INC  := $(SRC)/INC/boot.inc

boot: $(BOOT_INC)

$(BOOT_DIR)/BOOT.CL1: $(BOOT_DIR)/BOOT.SKL $(MESSAGES_OUT)
	cd $(BOOT_DIR) && $(NOSRVBLD) BOOT.SKL "..\MESSAGES\USA-MS.MSG"

$(BOOT_DIR)/MSBOOT.OBJ: $(BOOT_DIR)/MSBOOT.ASM $(BOOT_DIR)/BOOT.CL1
	cd $(BOOT_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\INC" "MSBOOT.ASM,MSBOOT.OBJ;"

$(BOOT_DIR)/MSBOOT.EXE: $(BOOT_DIR)/MSBOOT.OBJ
	cd $(BOOT_DIR) && $(LINK) "MSBOOT;"

$(BOOT_DIR)/MSBOOT.BIN: $(BOOT_DIR)/MSBOOT.EXE
	cd $(BOOT_DIR) && $(EXE2BIN) "MSBOOT.EXE MSBOOT.BIN"

$(BOOT_INC): $(BOOT_DIR)/MSBOOT.BIN
	cd $(BOOT_DIR) && $(DBOF) "MSBOOT.BIN BOOT.INC 7c00 200"
	cp $(BOOT_DIR)/BOOT.INC $(SRC)/INC/boot.inc

# ---------------------------------------------------------------------------
# INC (shared kernel objects)
# ---------------------------------------------------------------------------
INC_DIR  := $(SRC)/INC
HINC_DIR := $(SRC)/H
DOS_DIR  := $(SRC)/DOS

# msdos.cl1 is generated in DOS/ by NOSRVBLD and included by INC/DIVMES.ASM
# (via the -I..\\DOS path). It must be built before assembling MSDOSME.OBJ.
$(DOS_DIR)/MSDOS.CL1: $(DOS_DIR)/MSDOS.SKL $(MESSAGES_OUT)
	cd $(DOS_DIR) && $(NOSRVBLD) MSDOS.SKL "..\MESSAGES\USA-MS.MSG"

INC_OBJS := ERRTST.OBJ SYSVAR.OBJ CDS.OBJ DPB.OBJ NIBDOS.OBJ \
            CONST2.OBJ MSDATA.OBJ MSDOSME.OBJ MSTABLE.OBJ
INC_OBJ_PATHS := $(addprefix $(INC_DIR)/,$(INC_OBJS))

inc: $(INC_OBJ_PATHS)

# C source objects
$(INC_DIR)/ERRTST.OBJ: $(INC_DIR)/ERRTST.C
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -FoERRTST.OBJ ERRTST.C"

$(INC_DIR)/SYSVAR.OBJ: $(INC_DIR)/SYSVAR.C
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -FoSYSVAR.OBJ SYSVAR.C"

$(INC_DIR)/CDS.OBJ: $(INC_DIR)/CDS.C
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -FoCDS.OBJ CDS.C"

$(INC_DIR)/DPB.OBJ: $(INC_DIR)/DPB.C
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -FoDPB.OBJ DPB.C"

# ASM source objects
$(INC_DIR)/NIBDOS.OBJ: $(INC_DIR)/NIBDOS.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "NIBDOS.ASM,NIBDOS.OBJ;"

$(INC_DIR)/CONST2.OBJ: $(INC_DIR)/CONST2.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "CONST2.ASM,CONST2.OBJ;"

$(INC_DIR)/MSDATA.OBJ: $(INC_DIR)/MSDATA.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDATA.ASM,MSDATA.OBJ;"

$(INC_DIR)/MSDOSME.OBJ: $(INC_DIR)/MSDOSME.ASM $(DOS_DIR)/MSDOS.CL1
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDOSME.ASM,MSDOSME.OBJ;"

$(INC_DIR)/MSTABLE.OBJ: $(INC_DIR)/MSTABLE.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSTABLE.ASM,MSTABLE.OBJ;"

# ---------------------------------------------------------------------------
# BIOS (io.sys)
# ---------------------------------------------------------------------------
include mk/bios.mk

# ---------------------------------------------------------------------------
# DOS (msdos.sys)
# ---------------------------------------------------------------------------
include mk/dos.mk

# ---------------------------------------------------------------------------
# CMD (command.com)
# ---------------------------------------------------------------------------
include mk/cmd.mk

# ---------------------------------------------------------------------------
# DEV (device drivers)
# ---------------------------------------------------------------------------
include mk/dev.mk

# ---------------------------------------------------------------------------
# SELECT (select.exe, select.dat, select.com, select.hlp)
# ---------------------------------------------------------------------------
include mk/select.mk

# ---------------------------------------------------------------------------
# MEMM (emm386.sys)
# ---------------------------------------------------------------------------
include mk/memm.mk

# ---------------------------------------------------------------------------
# TESTS
# ---------------------------------------------------------------------------
ARTIFACTS := \
    MESSAGES/USA-MS.IDX \
    MAPPER/MAPPER.LIB \
    INC/boot.inc \
    BIOS/IO.SYS \
    DOS/MSDOS.SYS \
    CMD/COMMAND/COMMAND.COM \
    CMD/SYS/SYS.COM \
    CMD/FORMAT/FORMAT.COM \
    CMD/CHKDSK/CHKDSK.COM \
    DEV/ANSI/ANSI.SYS \
    DEV/VDISK/VDISK.SYS \
    DEV/COUNTRY/COUNTRY.SYS \
    DEV/RAMDRIVE/RAMDRIVE.SYS \
    DEV/KEYBOARD/KEYBOARD.SYS \
    DEV/PRINTER/PRINTER.SYS \
    DEV/DISPLAY/DISPLAY.SYS \
    DEV/SMARTDRV/SMARTDRV.SYS \
    DEV/XMA2EMS/XMA2EMS.SYS \
    DEV/XMAEM/XMAEM.SYS \
    SELECT/SELECT.EXE \
    SELECT/SELECT.COM \
    SELECT/SELECT.HLP \
    SELECT/SELECT.DAT \
    CMD/DEBUG/DEBUG.COM \
    CMD/MEM/MEM.EXE \
    CMD/FDISK/FDISK.EXE \
    CMD/MORE/MORE.COM \
    CMD/SORT/SORT.EXE \
    CMD/LABEL/LABEL.COM \
    CMD/FIND/FIND.EXE \
    CMD/TREE/TREE.COM \
    CMD/COMP/COMP.COM \
    MEMM/MEMM/EMM386.SYS

test: all
	bash tests/run_tests.sh

gen-checksums: all
	cd $(SRC) && sha256sum $(ARTIFACTS) > $(CURDIR)/tests/golden.sha256
	@echo "Checksums written to tests/golden.sha256"

test-sys: deploy
	bash tests/test_sys.sh

# ---------------------------------------------------------------------------
# DEPLOY — bootable 1.44MB floppy image
# ---------------------------------------------------------------------------
FLOPPY      := $(OUT)/floppy.img
FLOPPY_TEST := $(OUT)/floppy-test.img
BOOT_BIN    := $(SRC)/BOOT/MSBOOT.BIN
BOOT_OFF    := 31744   # boot sector lives at offset 0x7c00 in MSBOOT.BIN

IO_SYS      := $(SRC)/BIOS/IO.SYS
MSDOS_SYS   := $(SRC)/DOS/MSDOS.SYS
COMMAND_COM := $(SRC)/CMD/COMMAND/COMMAND.COM
SYS_COM     := $(SRC)/CMD/SYS/SYS.COM
FORMAT_COM  := $(SRC)/CMD/FORMAT/FORMAT.COM
CHKDSK_COM  := $(SRC)/CMD/CHKDSK/CHKDSK.COM
DEBUG_COM   := $(SRC)/CMD/DEBUG/DEBUG.COM
MEM_EXE     := $(SRC)/CMD/MEM/MEM.EXE
FDISK_EXE   := $(SRC)/CMD/FDISK/FDISK.EXE
MORE_COM    := $(SRC)/CMD/MORE/MORE.COM
SORT_EXE    := $(SRC)/CMD/SORT/SORT.EXE
LABEL_COM   := $(SRC)/CMD/LABEL/LABEL.COM
FIND_EXE    := $(SRC)/CMD/FIND/FIND.EXE
TREE_COM    := $(SRC)/CMD/TREE/TREE.COM
COMP_COM    := $(SRC)/CMD/COMP/COMP.COM

$(FLOPPY): $(BOOT_BIN) $(IO_SYS) $(MSDOS_SYS) $(COMMAND_COM) $(SYS_COM) $(FORMAT_COM) $(CHKDSK_COM) $(DEBUG_COM) $(MEM_EXE) $(FDISK_EXE) \
           $(MORE_COM) $(SORT_EXE) $(LABEL_COM) $(FIND_EXE) $(TREE_COM) $(COMP_COM)
	mkdir -p $(OUT)
	# blank 1.44MB image
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	# write MSBOOT.BIN's boot sector (sits at offset 0x7c00 in the .BIN)
	dd if=$(BOOT_BIN) of=$@ bs=1 skip=$(BOOT_OFF) count=512 conv=notrunc status=none
	# patch BPB fields for 1.44MB floppy geometry
	$(BIN)/patch-bpb $@
	# create FAT12 filesystem, keeping our patched boot sector
	mformat -i $@ -k ::
	# copy system files — IO.SYS must be the first directory entry
	mcopy -i $@ $(IO_SYS) ::IO.SYS
	mcopy -i $@ $(MSDOS_SYS) ::MSDOS.SYS
	mcopy -i $@ $(COMMAND_COM) ::COMMAND.COM
	mattrib +h +s +r -i $@ ::IO.SYS
	mattrib +h +s +r -i $@ ::MSDOS.SYS
	mcopy -i $@ $(SYS_COM) ::SYS.COM
	mcopy -i $@ $(FORMAT_COM) ::FORMAT.COM
	mcopy -i $@ $(CHKDSK_COM) ::CHKDSK.COM
	mcopy -i $@ $(DEBUG_COM) ::DEBUG.COM
	mcopy -i $@ $(MEM_EXE) ::MEM.EXE
	mcopy -i $@ $(FDISK_EXE) ::FDISK.EXE
	mcopy -i $@ $(MORE_COM) ::MORE.COM
	mcopy -i $@ $(SORT_EXE) ::SORT.EXE
	mcopy -i $@ $(LABEL_COM) ::LABEL.COM
	mcopy -i $@ $(FIND_EXE) ::FIND.EXE
	mcopy -i $@ $(TREE_COM) ::TREE.COM
	mcopy -i $@ $(COMP_COM) ::COMP.COM

deploy: all $(FLOPPY)

# run-boot: interactive QEMU session (graphical)
run-boot: deploy
	qemu-system-i386 -fda $(FLOPPY) -boot a -m 4

# floppy-test.img: same as floppy.img but with AUTOEXEC.BAT that redirects
# console to COM1 and prints the DOS version — used by verify target
$(FLOPPY_TEST): $(FLOPPY)
	cp $(FLOPPY) $@
	printf 'CTTY AUX\r\nVER\r\n' | mcopy -i $@ - ::AUTOEXEC.BAT

# verify: headless boot, capture COM1, check for "MS-DOS" in output
verify: all $(FLOPPY_TEST)
	@rm -f $(OUT)/serial.log
	timeout 15 qemu-system-i386 \
	    -display none \
	    -fda $(FLOPPY_TEST) \
	    -boot a -m 4 \
	    -serial file:$(OUT)/serial.log \
	    2>/dev/null; true
	@grep -q "MS-DOS" $(OUT)/serial.log \
	    && echo "PASS: MS-DOS booted successfully" \
	    || (echo "FAIL: MS-DOS boot not confirmed"; cat $(OUT)/serial.log; exit 1)

# ---------------------------------------------------------------------------
clean:
	find $(SRC) -name "*.obj" -o -name "*.exe" -o -name "*.bin" \
	    -o -name "*.com" -o -name "*.sys" -o -name "*.lib" \
	    -o -name "*.cl1" -o -name "*.idx" | xargs rm -f
	rm -f $(FLOPPY) $(FLOPPY_TEST) $(OUT)/serial.log
