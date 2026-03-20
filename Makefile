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

.PHONY: all messages mapper boot inc bios dos cmd dev select memm clean test gen-checksums deploy run-boot test-sys test-help-qemu test-misc-qemu test-backup-restore test-diskcomp-diskcopy test-share-nlsfunc-exe2bin test-append test-format test-format-one test-format-parallel test-label test-fdisk test-recover test-assign-subst-join test-debug-qemu test-edlin-b-qemu test-chkdsk-fix test-prompt-yesno

# Build kvikdos-soft (software CPU) if /dev/kvm is unavailable.
# dos-run automatically selects the right binary at runtime.
#
# kvikdos/mini_kvm.h's non-Linux __u64 typedef uses uint64_t (= unsigned long
# on x86-64) which conflicts with Linux kernel headers' unsigned long long.
# Fix: inject mk/mini_kvm_compat.h via -include; its MINI_KVM_H guard
# prevents the real mini_kvm.h from being processed.
KVIKDOS_SOFT_SRCS := kvikdos/kvikdos.c kvikdos/cpu8086.c
KVIKDOS_SOFT_DEPS := $(KVIKDOS_SOFT_SRCS) kvikdos/mini_kvm.h kvikdos/cpu8086.h \
                     kvikdos/cpu8086_xt.h kvikdos/XTulator/XTulator/cpu/cpu.c \
                     mk/mini_kvm_compat.h
KVIKDOS_SOFT_BIN  := kvikdos/kvikdos-soft

ifeq ($(wildcard /dev/kvm),)
all: $(KVIKDOS_SOFT_BIN) messages mapper boot inc bios dos cmd dev select memm
else
# Build kvikdos-soft alongside KVM binary so tests can fall back to software
# CPU for programs that trigger #GP on KVM (e.g. XCOPY segment limit issues).
all: $(KVIKDOS_SOFT_BIN) messages mapper boot inc bios dos cmd dev select memm
endif

$(KVIKDOS_SOFT_BIN): $(KVIKDOS_SOFT_DEPS)
	gcc -std=c99 -O2 -W -Wall -Wextra -fno-strict-aliasing \
	    -Wno-error=incompatible-pointer-types \
	    -D_GNU_SOURCE -U__linux__ -include $(CURDIR)/mk/mini_kvm_compat.h \
	    -I kvikdos/ \
	    -o $@ $(KVIKDOS_SOFT_SRCS)

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
    DEV/SMARTDRV/FLUSH13.EXE \
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
    CMD/ATTRIB/ATTRIB.EXE \
    CMD/EDLIN/EDLIN.COM \
    CMD/NLSFUNC/NLSFUNC.EXE \
    CMD/ASSIGN/ASSIGN.COM \
    CMD/XCOPY/XCOPY.EXE \
    CMD/DISKCOMP/DISKCOMP.COM \
    CMD/DISKCOPY/DISKCOPY.COM \
    CMD/APPEND/APPEND.EXE \
    CMD/RECOVER/RECOVER.COM \
    CMD/FASTOPEN/FASTOPEN.EXE \
    CMD/PRINT/PRINT.COM \
    CMD/FILESYS/FILESYS.EXE \
    CMD/REPLACE/REPLACE.EXE \
    CMD/JOIN/JOIN.EXE \
    CMD/SUBST/SUBST.EXE \
    CMD/BACKUP/BACKUP.COM \
    CMD/RESTORE/RESTORE.COM \
    CMD/GRAFTABL/GRAFTABL.COM \
    CMD/KEYB/KEYB.COM \
    CMD/SHARE/SHARE.EXE \
    CMD/EXE2BIN/EXE2BIN.EXE \
    CMD/GRAPHICS/GRAPHICS.COM \
    CMD/IFSFUNC/IFSFUNC.EXE \
    CMD/MODE/MODE.COM \
    MEMM/MEMM/EMM386.SYS

test:
	bash tests/run_tests.sh

gen-checksums: all
	cd $(SRC) && sha256sum $(ARTIFACTS) > $(CURDIR)/tests/golden.sha256
	@echo "Checksums written to tests/golden.sha256"

test-sys: deploy
	bash tests/test_sys.sh

test-help-qemu: deploy
	bash tests/test_help_qemu.sh

test-misc-qemu: deploy
	bash tests/test_misc_qemu.sh

test-backup-restore: deploy
	bash tests/test_backup_restore.sh

test-diskcomp-diskcopy: deploy
	bash tests/test_diskcomp_diskcopy.sh

test-share-nlsfunc-exe2bin: deploy
	bash tests/test_share_nlsfunc_exe2bin.sh

test-append: deploy
	bash tests/test_append.sh

test-format: deploy
	bash tests/test_format.sh

# Run a single FORMAT variant for quick debugging, e.g.: make test-format-one VARIANT=VLABEL
test-format-one: deploy
	bash tests/test_format.sh $(VARIANT)

# Run FORMAT variants in parallel (4 groups, each in its own QEMU + workdir).
# Much faster than test-format (sequential).  Results: out/format-parallel-*.log
test-format-parallel: deploy
	@mkdir -p $(OUT)
	@echo "=== FORMAT parallel test (5 groups) ==="
	@FAIL=0; \
	FORMAT_WORKDIR=$(OUT)/format-p-vlabel bash tests/test_format.sh VLABEL        > $(OUT)/format-parallel-vlabel.log 2>&1 & P1=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-s      bash tests/test_format.sh S             > $(OUT)/format-parallel-s.log     2>&1 & P2=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-b      bash tests/test_format.sh B             > $(OUT)/format-parallel-b.log     2>&1 & P3=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-rest   bash tests/test_format.sh F720 TN FOUR ONE EIGHT > $(OUT)/format-parallel-rest.log 2>&1 & P4=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-undoc  bash tests/test_format.sh SWITCHC SWITCHZ SELECT AUTOTEST > $(OUT)/format-parallel-undoc.log 2>&1 & P5=$$!; \
	for JOB in "vlabel:$$P1" "s:$$P2" "b:$$P3" "rest:$$P4" "undoc:$$P5"; do \
	    NAME=$${JOB%%:*}; PID=$${JOB##*:}; \
	    if wait $$PID; then echo "  PASS group: $$NAME"; \
	    else echo "  FAIL group: $$NAME (see out/format-parallel-$$NAME.log)"; FAIL=$$((FAIL+1)); fi; \
	done; \
	echo "=== FORMAT parallel done: $$FAIL group(s) failed ==="; \
	exit $$FAIL

test-label: deploy
	bash tests/test_label.sh

test-fdisk: deploy
	bash tests/test_fdisk.sh

test-recover: deploy
	bash tests/test_recover.sh

test-assign-subst-join: deploy
	bash tests/test_assign_subst_join.sh

test-debug-qemu: deploy
	bash tests/test_debug_qemu.sh

test-edlin-b-qemu: deploy
	bash tests/test_edlin_b_qemu.sh

test-chkdsk-fix: deploy
	bash tests/test_chkdsk_fix.sh

test-prompt-yesno: deploy
	bash tests/test_prompt_yesno.sh

test-drivers-qemu: deploy
	bash tests/test_drivers_qemu.sh

# ---------------------------------------------------------------------------
# DEPLOY — bootable 1.44MB floppy image
# ---------------------------------------------------------------------------
FLOPPY      := $(OUT)/floppy.img
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
ATTRIB_EXE  := $(SRC)/CMD/ATTRIB/ATTRIB.EXE
EDLIN_COM   := $(SRC)/CMD/EDLIN/EDLIN.COM
FC_EXE      := $(SRC)/CMD/FC/FC.EXE
NLSFUNC_EXE := $(SRC)/CMD/NLSFUNC/NLSFUNC.EXE
ASSIGN_COM  := $(SRC)/CMD/ASSIGN/ASSIGN.COM
XCOPY_EXE   := $(SRC)/CMD/XCOPY/XCOPY.EXE
DISKCOMP_COM := $(SRC)/CMD/DISKCOMP/DISKCOMP.COM
DISKCOPY_COM := $(SRC)/CMD/DISKCOPY/DISKCOPY.COM
APPEND_EXE   := $(SRC)/CMD/APPEND/APPEND.EXE
RECOVER_COM  := $(SRC)/CMD/RECOVER/RECOVER.COM
FASTOPEN_EXE := $(SRC)/CMD/FASTOPEN/FASTOPEN.EXE
PRINT_COM    := $(SRC)/CMD/PRINT/PRINT.COM
FILESYS_EXE  := $(SRC)/CMD/FILESYS/FILESYS.EXE
REPLACE_EXE  := $(SRC)/CMD/REPLACE/REPLACE.EXE
JOIN_EXE     := $(SRC)/CMD/JOIN/JOIN.EXE
SUBST_EXE    := $(SRC)/CMD/SUBST/SUBST.EXE
BACKUP_COM   := $(SRC)/CMD/BACKUP/BACKUP.COM
RESTORE_COM  := $(SRC)/CMD/RESTORE/RESTORE.COM
GRAFTABL_COM := $(SRC)/CMD/GRAFTABL/GRAFTABL.COM
KEYB_COM     := $(SRC)/CMD/KEYB/KEYB.COM
KEYBOARD_SYS := $(SRC)/DEV/KEYBOARD/KEYBOARD.SYS
SHARE_EXE    := $(SRC)/CMD/SHARE/SHARE.EXE
EXE2BIN_SRC  := $(SRC)/CMD/EXE2BIN/EXE2BIN.EXE
GRAPHICS_COM := $(SRC)/CMD/GRAPHICS/GRAPHICS.COM
GRAPHICS_PRO := $(SRC)/CMD/GRAPHICS/GRAPHICS.PRO
IFSFUNC_EXE  := $(SRC)/CMD/IFSFUNC/IFSFUNC.EXE
MODE_COM     := $(SRC)/CMD/MODE/MODE.COM
ANSI_SYS     := $(SRC)/DEV/ANSI/ANSI.SYS
RAMDRIVE_SYS := $(SRC)/DEV/RAMDRIVE/RAMDRIVE.SYS
VDISK_SYS    := $(SRC)/DEV/VDISK/VDISK.SYS
DISPLAY_SYS  := $(SRC)/DEV/DISPLAY/DISPLAY.SYS
COUNTRY_SYS  := $(SRC)/DEV/COUNTRY/COUNTRY.SYS
SMARTDRV_SYS := $(SRC)/DEV/SMARTDRV/SMARTDRV.SYS
DRIVER_SYS   := $(SRC)/DEV/DRIVER/DRIVER.SYS

$(FLOPPY): $(BOOT_BIN) $(IO_SYS) $(MSDOS_SYS) $(COMMAND_COM) $(SYS_COM) $(FORMAT_COM) $(CHKDSK_COM) $(DEBUG_COM) $(MEM_EXE) $(FDISK_EXE) \
           $(MORE_COM) $(SORT_EXE) $(LABEL_COM) $(FIND_EXE) $(TREE_COM) $(COMP_COM) \
           $(ATTRIB_EXE) $(EDLIN_COM) $(FC_EXE) \
           $(NLSFUNC_EXE) $(ASSIGN_COM) $(XCOPY_EXE) $(DISKCOMP_COM) $(DISKCOPY_COM) \
           $(APPEND_EXE) $(RECOVER_COM) $(FASTOPEN_EXE) $(PRINT_COM) \
           $(FILESYS_EXE) $(REPLACE_EXE) $(JOIN_EXE) $(SUBST_EXE) \
           $(BACKUP_COM) $(RESTORE_COM) $(GRAFTABL_COM) $(KEYB_COM) $(SHARE_EXE) \
           $(EXE2BIN_SRC) $(GRAPHICS_COM) \
           $(IFSFUNC_EXE) $(MODE_COM) \
           $(ANSI_SYS) $(RAMDRIVE_SYS) \
           $(VDISK_SYS) $(DISPLAY_SYS) $(COUNTRY_SYS) \
           $(SMARTDRV_SYS) $(DRIVER_SYS)
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
	# mattrib -i is broken in mtools >=4.0.49; use MTOOLSRC drive mapping
	echo 'drive a: file="$@"' > $(OUT)/.mtoolsrc
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/IO.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/MSDOS.SYS
	rm -f $(OUT)/.mtoolsrc
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
	mcopy -i $@ $(ATTRIB_EXE) ::ATTRIB.EXE
	mcopy -i $@ $(EDLIN_COM) ::EDLIN.COM
	mcopy -i $@ $(FC_EXE) ::FC.EXE
	mcopy -i $@ $(NLSFUNC_EXE) ::NLSFUNC.EXE
	mcopy -i $@ $(ASSIGN_COM) ::ASSIGN.COM
	mcopy -i $@ $(XCOPY_EXE) ::XCOPY.EXE
	mcopy -i $@ $(DISKCOMP_COM) ::DISKCOMP.COM
	mcopy -i $@ $(DISKCOPY_COM) ::DISKCOPY.COM
	mcopy -i $@ $(APPEND_EXE) ::APPEND.EXE
	mcopy -i $@ $(RECOVER_COM) ::RECOVER.COM
	mcopy -i $@ $(FASTOPEN_EXE) ::FASTOPEN.EXE
	mcopy -i $@ $(PRINT_COM) ::PRINT.COM
	mcopy -i $@ $(FILESYS_EXE) ::FILESYS.EXE
	mcopy -i $@ $(REPLACE_EXE) ::REPLACE.EXE
	mcopy -i $@ $(JOIN_EXE) ::JOIN.EXE
	mcopy -i $@ $(SUBST_EXE) ::SUBST.EXE
	mcopy -i $@ $(BACKUP_COM) ::BACKUP.COM
	mcopy -i $@ $(RESTORE_COM) ::RESTORE.COM
	mcopy -i $@ $(GRAFTABL_COM) ::GRAFTABL.COM
	mcopy -i $@ $(KEYB_COM) ::KEYB.COM
	mcopy -i $@ $(KEYBOARD_SYS) ::KEYBOARD.SYS
	mcopy -i $@ $(SHARE_EXE) ::SHARE.EXE
	mcopy -i $@ $(EXE2BIN_SRC) ::EXE2BIN.EXE
	mcopy -i $@ $(GRAPHICS_COM) ::GRAPHICS.COM
	mcopy -i $@ $(GRAPHICS_PRO) ::GRAPHICS.PRO
	mcopy -i $@ $(IFSFUNC_EXE) ::IFSFUNC.EXE
	mcopy -i $@ $(MODE_COM) ::MODE.COM
	mcopy -i $@ $(ANSI_SYS) ::ANSI.SYS
	mcopy -i $@ $(RAMDRIVE_SYS) ::RAMDRIVE.SYS
	mcopy -i $@ $(VDISK_SYS) ::VDISK.SYS
	mcopy -i $@ $(DISPLAY_SYS) ::DISPLAY.SYS
	mcopy -i $@ $(COUNTRY_SYS) ::COUNTRY.SYS
	mcopy -i $@ $(SMARTDRV_SYS) ::SMARTDRV.SYS
	mcopy -i $@ $(DRIVER_SYS) ::DRIVER.SYS

deploy: all $(FLOPPY)

# run-boot: interactive QEMU session (graphical)
run-boot: deploy
	qemu-system-i386 -fda $(FLOPPY) -boot a -m 4

# ---------------------------------------------------------------------------
clean:
	find $(SRC) -name "*.obj" -o -name "*.exe" -o -name "*.bin" \
	    -o -name "*.com" -o -name "*.sys" -o -name "*.lib" \
	    -o -name "*.cl1" -o -name "*.idx" | xargs rm -f
	rm -f $(FLOPPY) $(OUT)/serial.log
