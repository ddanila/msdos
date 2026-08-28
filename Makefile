
SHELL    := /bin/bash
SRC      := $(CURDIR)/MS-DOS/v4.0/src
BIN      := $(CURDIR)/bin
OUT      := $(CURDIR)/out

MASM     := $(BIN)/jwasm-masm
WCC      := $(BIN)/wcc
WLINK    := $(BIN)/wlink
WLIB     := $(BIN)/wlib
EXE2BIN  := $(BIN)/exe2bin
BUILDIDX := $(BIN)/buildidx
BUILDMSG := $(BIN)/buildmsg
NOSRVBLD := $(BIN)/nosrvbld
DBOF     := $(BIN)/dbof
MENUBLD  := $(BIN)/menubld
CONVERT  := $(BIN)/convert
ASC2HLP  := $(BIN)/asc2hlp
COMPRESS := $(BIN)/compress
MKCNTRY  := $(BIN)/mkcntry
MESSAGE_CATALOG := $(BIN)/message_catalog.py

COUNTRY  := usa-ms
AFLAGS   := -Mx -t
CFLAGS   := -AS -Os -Zp

AINC     := -I. -ID:\\TOOLS\\INC

.PHONY: all build-all messages mapper boot inc bios dos cmd cmd_command dev select memm clean test test-native-build-tools test-batch-oracles test-oracle-mutation-coverage test-coverage-manifest test-int21-error-coverage-manifest test-runtime-coverage-manifest test-command-coverage-manifest test-utility-parser-coverage-manifest test-program-interface-coverage-manifest test-dos-interrupt-coverage-manifest test-device-request-coverage-manifest deploy minimal-floppy run-boot test-sys test-help-qemu test-command-startup-qemu test-more-paging-qemu test-misc-qemu test-graftabl-qemu test-mode-redirect-qemu test-keyb-layout-qemu test-backup-restore test-diskcomp-diskcopy test-share-nlsfunc-exe2bin test-append test-format test-format-one test-format-parallel test-label test-fdisk test-recover test-assign-subst-join test-debug-qemu test-edlin-qemu test-chkdsk-fix test-prompt-yesno test-screen-expect test-select test-drivers-qemu test-ansi-driver-qemu test-display-chain-qemu test-driver-sys-qemu test-printer-driver-qemu test-smartdrv-flush-qemu test-xma-drivers-qemu test-himem-qemu test-root-exhaustion-qemu test-disk-exhaustion-qemu test-config-state-qemu test-config-switches-qemu test-config-stacks-qemu test-config-dos-qemu test-xms-umb-transaction-qemu test-config-ifs-qemu test-ifsfunc-filesys-qemu test-config-multitrack-qemu test-emm386-qemu test-int21-file-memory-qemu test-int21-path-errors-qemu test-int21-system-qemu test-int21-fcb-qemu test-int21-compat-qemu test-int21-console-qemu test-int21-process-qemu test-int21-tsr-qemu test-int21-media-qemu test-int21-readonly-media-qemu test-dos-interrupt-qemu test-dos-async-interrupt-qemu
.PHONY: test-utility-parser-coverage-manifest
.PHONY: test-program-interface-coverage-manifest test-debug-command-coverage-manifest test-help-coverage-manifest

KVIKDOS_SOFT_SRCS := kvikdos/kvikdos.c kvikdos/cpu8086.c
KVIKDOS_SOFT_DEPS := $(KVIKDOS_SOFT_SRCS) kvikdos/mini_kvm.h kvikdos/cpu8086.h \
                     kvikdos/cpu8086_xt.h kvikdos/XTulator/XTulator/cpu/cpu.c \
                     mk/mini_kvm_compat.h
KVIKDOS_SOFT_BIN  := kvikdos/kvikdos-soft

all: build-all

build-all: messages mapper boot inc bios dos cmd dev select memm

# Force kvikdos's portable path while predefining Linux-compatible KVM types;
# its portable uint64_t alias conflicts with Linux kernel headers on x86-64.
$(KVIKDOS_SOFT_BIN): $(KVIKDOS_SOFT_DEPS)
	gcc -std=c99 -O2 -W -Wall -Wextra -fno-strict-aliasing \
	    -Wno-error=incompatible-pointer-types \
	    -D_GNU_SOURCE -U__linux__ -include $(CURDIR)/mk/mini_kvm_compat.h \
	    -I kvikdos/ \
	    -o $@ $(KVIKDOS_SOFT_SRCS)

MESSAGES_DIR := $(SRC)/MESSAGES
MESSAGES_OUT := $(MESSAGES_DIR)/$(COUNTRY).IDX

messages: $(MESSAGES_OUT)

$(MESSAGES_OUT): $(MESSAGES_DIR)/USA-MS.MSG $(BUILDIDX)
	cd $(MESSAGES_DIR) && $(BUILDIDX) USA-MS.MSG

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
	cd $(MAPPER_DIR) && $(WLIB) @mapper.lbr

$(MAPPER_DIR)/%.OBJ: $(MAPPER_DIR)/%.ASM
	cd $(MAPPER_DIR) && $(MASM) "$(AFLAGS) $(AINC)" "$*.ASM,$*.OBJ;"

BOOT_DIR := $(SRC)/BOOT
BOOT_INC  := $(SRC)/INC/boot.inc

boot: $(BOOT_INC)

$(BOOT_DIR)/BOOT.CL1: $(BOOT_DIR)/BOOT.SKL $(MESSAGES_OUT) $(NOSRVBLD) $(MESSAGE_CATALOG)
	cd $(BOOT_DIR) && $(NOSRVBLD) BOOT.SKL "..\MESSAGES\USA-MS.MSG"

$(BOOT_DIR)/MSBOOT.OBJ: $(BOOT_DIR)/MSBOOT.ASM $(BOOT_DIR)/BOOT.CL1
	cd $(BOOT_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\INC" "MSBOOT.ASM,MSBOOT.OBJ;"

$(BOOT_DIR)/MSBOOT.EXE: $(BOOT_DIR)/MSBOOT.OBJ
	cd $(BOOT_DIR) && $(WLINK) "MSBOOT;"

$(BOOT_DIR)/MSBOOT.BIN: $(BOOT_DIR)/MSBOOT.EXE
	cd $(BOOT_DIR) && $(EXE2BIN) "MSBOOT.EXE MSBOOT.BIN"

$(BOOT_INC): $(BOOT_DIR)/MSBOOT.BIN
	cd $(BOOT_DIR) && $(DBOF) "MSBOOT.BIN BOOT.INC 7c00 200"
	cp $(BOOT_DIR)/BOOT.INC $(SRC)/INC/boot.inc

INC_DIR  := $(SRC)/INC
HINC_DIR := $(SRC)/H
DOS_DIR  := $(SRC)/DOS

$(DOS_DIR)/MSDOS.CL1: $(DOS_DIR)/MSDOS.SKL $(MESSAGES_OUT) $(NOSRVBLD) $(MESSAGE_CATALOG)
	cd $(DOS_DIR) && $(NOSRVBLD) MSDOS.SKL "..\MESSAGES\USA-MS.MSG"

INC_ASM_OBJS := NIBDOS.OBJ CONST2.OBJ MSDATA.OBJ MSDOSME.OBJ MSTABLE.OBJ
INC_ASM_OBJ_PATHS := $(addprefix $(INC_DIR)/,$(INC_ASM_OBJS))
OW_INC_C_OBJS := OWERRTST.OBJ OWSYSVAR.OBJ OWCDS.OBJ OWDPB.OBJ
OW_INC_C_OBJ_PATHS := $(addprefix $(INC_DIR)/,$(OW_INC_C_OBJS))

inc: $(INC_ASM_OBJ_PATHS) $(OW_INC_C_OBJ_PATHS)

$(INC_DIR)/OWERRTST.OBJ: $(INC_DIR)/ERRTST.C
	cd $(INC_DIR) && $(WCC) "-AS -Od -Zp -I. -I..\\H -c -FoOWERRTST.OBJ ERRTST.C"

$(INC_DIR)/OWSYSVAR.OBJ: $(INC_DIR)/SYSVAR.C
	cd $(INC_DIR) && $(WCC) "-AS -Od -Zp -I. -I..\\H -c -FoOWSYSVAR.OBJ SYSVAR.C"

$(INC_DIR)/OWCDS.OBJ: $(INC_DIR)/CDS.C
	cd $(INC_DIR) && $(WCC) "-AS -Od -Zp -I. -I..\\H -c -FoOWCDS.OBJ CDS.C"

$(INC_DIR)/OWDPB.OBJ: $(INC_DIR)/DPB.C
	cd $(INC_DIR) && $(WCC) "-AS -Od -Zp -I. -I..\\H -c -FoOWDPB.OBJ DPB.C"

$(INC_DIR)/NIBDOS.OBJ: $(INC_DIR)/NIBDOS.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "NIBDOS.ASM,NIBDOS.OBJ;"

$(INC_DIR)/CONST2.OBJ: $(INC_DIR)/CONST2.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "CONST2.ASM,CONST2.OBJ;"

$(INC_DIR)/MSDATA.OBJ: $(INC_DIR)/MSDATA.ASM $(DOS_DIR)/MSINIT.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDATA.ASM,MSDATA.OBJ;"

$(INC_DIR)/MSDOSME.OBJ: $(INC_DIR)/MSDOSME.ASM $(DOS_DIR)/MSDOS.CL1
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDOSME.ASM,MSDOSME.OBJ;"

$(INC_DIR)/MSTABLE.OBJ: $(INC_DIR)/MSTABLE.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSTABLE.ASM,MSTABLE.OBJ;"

include mk/bios.mk

include mk/dos.mk

include mk/cmd.mk

include mk/dev.mk

include mk/select.mk

include mk/memm.mk

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
    DEV/DISPLAY/EGA/EGA.CPI \
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

test: $(KVIKDOS_SOFT_BIN) test-native-build-tools test-batch-oracles test-oracle-mutation-coverage test-coverage-manifest test-int21-error-coverage-manifest test-runtime-coverage-manifest test-command-coverage-manifest test-utility-parser-coverage-manifest test-program-interface-coverage-manifest test-debug-command-coverage-manifest test-help-coverage-manifest test-dos-interrupt-coverage-manifest test-device-request-coverage-manifest
	bash tests/run_tests.sh

test-native-build-tools:
	bash tests/test_native_build_tools.sh

test-batch-oracles:
	python3 tests/test_batch_oracles.py

test-oracle-mutation-coverage:
	python3 tests/test_oracle_mutation_coverage.py --require-complete

test-coverage-manifest:
	python3 tests/test_coverage_manifest.py --require-complete

test-int21-error-coverage-manifest:
	python3 tests/test_int21_error_coverage.py --require-complete

test-runtime-coverage-manifest:
	python3 tests/test_runtime_coverage_manifest.py --require-complete

test-command-coverage-manifest:
	python3 tests/test_command_coverage.py --require-complete

test-utility-parser-coverage-manifest:
	python3 tests/test_utility_parser_coverage.py --require-complete

test-program-interface-coverage-manifest:
	python3 tests/test_program_interface_coverage.py --require-complete

test-debug-command-coverage-manifest:
	python3 tests/test_debug_command_coverage.py --require-complete

test-help-coverage-manifest:
	python3 tests/test_help_coverage.py --require-complete

test-dos-interrupt-coverage-manifest:
	python3 tests/test_dos_interrupt_coverage.py --require-complete

test-device-request-coverage-manifest:
	python3 tests/test_device_request_coverage.py --require-complete

minimal-floppy: boot bios dos cmd_command
	mkdir -p $(OUT)
	dd if=/dev/zero of=$(FLOPPY) bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$(FLOPPY) bs=1 skip=$(BOOT_OFF) count=512 conv=notrunc status=none
	$(BIN)/patch-bpb $(FLOPPY)
	mformat -i $(FLOPPY) -k ::
	mcopy -i $(FLOPPY) $(IO_SYS) ::IO.SYS
	mcopy -i $(FLOPPY) $(MSDOS_SYS) ::MSDOS.SYS
	mcopy -i $(FLOPPY) $(COMMAND_COM) ::COMMAND.COM
	echo 'drive a: file="$(FLOPPY)"' > $(OUT)/.mtoolsrc
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/IO.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/MSDOS.SYS
	rm -f $(OUT)/.mtoolsrc
	@echo "Minimal floppy built: $(FLOPPY)"

test-sys: deploy
	bash tests/test_sys.sh

test-help-qemu: deploy
	bash tests/test_help_qemu.sh

test-more-paging-qemu: deploy
	bash tests/test_more_paging_qemu.sh

test-misc-qemu: deploy
	bash tests/test_misc_qemu.sh

test-graftabl-qemu: deploy
	bash tests/test_graftabl_qemu.sh

test-graphics-print-qemu: deploy
	bash tests/test_graphics_print_qemu.sh

test-fastopen-cache-qemu: deploy
	bash tests/test_fastopen_cache_qemu.sh

test-mode-redirect-qemu: deploy
	bash tests/test_mode_redirect_qemu.sh

test-keyb-layout-qemu: deploy
	bash tests/test_keyb_layout_qemu.sh

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

test-format-one: deploy
	bash tests/test_format.sh $(VARIANT)

test-format-parallel: deploy
	@mkdir -p $(OUT)
	@echo "=== FORMAT parallel test (7 groups) ==="
	@FAIL=0; \
	FORMAT_WORKDIR=$(OUT)/format-p-vlabel bash tests/test_format.sh VLABEL        > $(OUT)/format-parallel-vlabel.log 2>&1 & P1=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-s      bash tests/test_format.sh S             > $(OUT)/format-parallel-s.log     2>&1 & P2=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-b      bash tests/test_format.sh B             > $(OUT)/format-parallel-b.log     2>&1 & P3=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-720k   bash tests/test_format.sh F720 TN       > $(OUT)/format-parallel-720k.log   2>&1 & P4=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-1200k  bash tests/test_format.sh FOUR ONE      > $(OUT)/format-parallel-1200k.log  2>&1 & P5=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-360k   bash tests/test_format.sh EIGHT         > $(OUT)/format-parallel-360k.log   2>&1 & P6=$$!; \
	FORMAT_WORKDIR=$(OUT)/format-p-undoc  bash tests/test_format.sh SWITCHC SWITCHZ SELECT AUTOTEST > $(OUT)/format-parallel-undoc.log 2>&1 & P7=$$!; \
	for JOB in "vlabel:$$P1" "s:$$P2" "b:$$P3" "720k:$$P4" "1200k:$$P5" "360k:$$P6" "undoc:$$P7"; do \
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

test-edlin-qemu: deploy
	bash tests/test_edlin_qemu.sh

test-chkdsk-fix: deploy
	bash tests/test_chkdsk_fix.sh

test-prompt-yesno: deploy
	bash tests/test_prompt_yesno.sh

test-command-startup-qemu: deploy
	bash tests/test_command_startup_qemu.sh

test-screen-expect: deploy
	bash tests/test_screen_expect.sh

test-select: deploy
	bash tests/test_select.sh

test-drivers-qemu: deploy
	bash tests/test_drivers_qemu.sh

test-ansi-driver-qemu: deploy
	bash tests/test_ansi_driver_qemu.sh

test-display-chain-qemu: deploy
	bash tests/test_display_chain_qemu.sh

test-driver-sys-qemu: deploy
	bash tests/test_driver_sys_qemu.sh

test-printer-driver-qemu: deploy
	bash tests/test_printer_driver_qemu.sh

test-print-spooler-qemu: deploy
	bash tests/test_print_spooler_qemu.sh

test-smartdrv-flush-qemu: deploy
	bash tests/test_smartdrv_flush_qemu.sh

test-xma-drivers-qemu: deploy
	bash tests/test_xma_drivers_qemu.sh

test-root-exhaustion-qemu: deploy
	bash tests/test_root_exhaustion_qemu.sh

test-disk-exhaustion-qemu: deploy
	bash tests/test_disk_exhaustion_qemu.sh

test-int21-path-errors-qemu: deploy
	bash tests/test_int21_path_errors_qemu.sh

test-config-state-qemu: deploy
	bash tests/test_config_state_qemu.sh

test-config-switches-qemu: deploy
	bash tests/test_config_switches_qemu.sh

test-config-stacks-qemu: deploy
	bash tests/test_config_stacks_qemu.sh

test-config-dos-qemu: deploy
	bash tests/test_config_dos_qemu.sh

test-xms-umb-transaction-qemu: deploy
	bash tests/test_xms_umb_transaction_qemu.sh

test-himem-qemu: deploy
	bash tests/test_himem_qemu.sh

test-hma-qemu: deploy
	bash tests/test_hma_qemu.sh

test-config-ifs-qemu: deploy
	bash tests/test_config_ifs_qemu.sh

test-ifsfunc-filesys-qemu: deploy
	bash tests/test_ifsfunc_filesys_qemu.sh

test-config-multitrack-qemu: deploy
	bash tests/test_config_multitrack_qemu.sh

FLOPPY      := $(OUT)/floppy.img
BOOT_BIN    := $(SRC)/BOOT/MSBOOT.BIN
BOOT_OFF    := 31744

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
PRINTER_SYS  := $(SRC)/DEV/PRINTER/PRINTER.SYS
PRINTER_CPI  := $(SRC)/DEV/PRINTER/4201/4201.CPI
SMARTDRV_SYS := $(SRC)/DEV/SMARTDRV/SMARTDRV.SYS
FLUSH13_EXE  := $(SRC)/DEV/SMARTDRV/FLUSH13.EXE
DRIVER_SYS   := $(SRC)/DEV/DRIVER/DRIVER.SYS
XMA2EMS_SYS  := $(SRC)/DEV/XMA2EMS/XMA2EMS.SYS
XMAEM_SYS    := $(SRC)/DEV/XMAEM/XMAEM.SYS
SELECT_COM   := $(SRC)/SELECT/SELECT.COM
SELECT_EXE   := $(SRC)/SELECT/SELECT.EXE
SELECT_DAT   := $(SRC)/SELECT/SELECT.DAT
SELECT_HLP   := $(SRC)/SELECT/SELECT.HLP
EGA_CPI      := $(SRC)/DEV/DISPLAY/EGA/EGA.CPI
EMM386_SYS   := $(MEMM_DIR)/EMM386.SYS

$(FLOPPY): $(BOOT_BIN) $(IO_SYS) $(MSDOS_SYS) $(COMMAND_COM) $(SYS_COM) $(FORMAT_COM) $(CHKDSK_COM) $(DEBUG_COM) $(MEM_EXE) $(FDISK_EXE) \
           $(MORE_COM) $(SORT_EXE) $(LABEL_COM) $(FIND_EXE) $(TREE_COM) $(COMP_COM) \
           $(ATTRIB_EXE) $(EDLIN_COM) $(FC_EXE) \
           $(NLSFUNC_EXE) $(ASSIGN_COM) $(XCOPY_EXE) $(DISKCOMP_COM) $(DISKCOPY_COM) \
           $(APPEND_EXE) $(RECOVER_COM) $(FASTOPEN_EXE) $(PRINT_COM) \
           $(FILESYS_EXE) $(REPLACE_EXE) $(JOIN_EXE) $(SUBST_EXE) \
           $(BACKUP_COM) $(RESTORE_COM) $(GRAFTABL_COM) $(KEYB_COM) $(KEYBOARD_SYS) $(SHARE_EXE) \
           $(EXE2BIN_SRC) $(GRAPHICS_COM) $(GRAPHICS_PRO) \
           $(IFSFUNC_EXE) $(MODE_COM) \
           $(ANSI_SYS) $(RAMDRIVE_SYS) \
           $(VDISK_SYS) $(DISPLAY_SYS) $(COUNTRY_SYS) $(PRINTER_SYS) $(PRINTER_CPI) \
           $(SMARTDRV_SYS) $(FLUSH13_EXE) $(DRIVER_SYS) $(XMA2EMS_SYS) $(XMAEM_SYS) \
           $(SELECT_COM) $(SELECT_EXE) $(SELECT_DAT) $(SELECT_HLP) \
           $(EGA_CPI) $(EMM386_SYS)
	mkdir -p $(OUT)
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$@ bs=1 skip=$(BOOT_OFF) count=512 conv=notrunc status=none
	$(BIN)/patch-bpb $@
	mformat -i $@ -k ::
	# IO.SYS must be the first root-directory entry because the boot sector assumes it.
	mcopy -i $@ $(IO_SYS) ::IO.SYS
	mcopy -i $@ $(MSDOS_SYS) ::MSDOS.SYS
	mcopy -i $@ $(COMMAND_COM) ::COMMAND.COM
	# mtools 4.0.49 broke mattrib's -i handling, so expose the image through MTOOLSRC.
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
	mcopy -i $@ $(PRINTER_SYS) ::PRINTER.SYS
	mcopy -i $@ $(PRINTER_CPI) ::4201.CPI
	mcopy -i $@ $(SMARTDRV_SYS) ::SMARTDRV.SYS
	mcopy -i $@ $(FLUSH13_EXE) ::FLUSH13.EXE
	mcopy -i $@ $(DRIVER_SYS) ::DRIVER.SYS
	mcopy -i $@ $(XMA2EMS_SYS) ::XMA2EMS.SYS
	mcopy -i $@ $(XMAEM_SYS) ::XMAEM.SYS
	mcopy -i $@ $(SELECT_COM) ::SELECT.COM
	mcopy -i $@ $(SELECT_EXE) ::SELECT.EXE
	mcopy -i $@ $(SELECT_DAT) ::SELECT.DAT
	mcopy -i $@ $(SELECT_HLP) ::SELECT.HLP
	mcopy -i $@ $(EGA_CPI) ::EGA.CPI
	mcopy -i $@ $(EMM386_SYS) ::EMM386.SYS

deploy:
	# A single jobserver-aware submake prevents parallel image and build paths
	# from racing on their shared generated message and include files.
	+$(MAKE) $(FLOPPY)

run-boot: deploy
	qemu-system-i386 -fda $(FLOPPY) -boot a -m 4

test-emm386-qemu: deploy
	bash tests/test_emm386_qemu.sh

test-int21-file-memory-qemu: deploy
	bash tests/test_int21_file_memory_qemu.sh

test-int21-system-qemu: deploy
	bash tests/test_int21_system_qemu.sh

test-int21-fcb-qemu: deploy
	bash tests/test_int21_fcb_qemu.sh

test-int21-compat-qemu: deploy
	bash tests/test_int21_compat_qemu.sh

test-int21-console-qemu: deploy
	bash tests/test_int21_console_qemu.sh

test-int21-process-qemu: deploy
	bash tests/test_int21_process_qemu.sh

test-int21-tsr-qemu: deploy
	bash tests/test_int21_tsr_qemu.sh

test-int21-media-qemu: deploy
	bash tests/test_int21_media_qemu.sh

test-int21-readonly-media-qemu: deploy
	bash tests/test_int21_readonly_media_qemu.sh

test-dos-interrupt-qemu: deploy
	bash tests/test_dos_interrupt_qemu.sh

test-dos-async-interrupt-qemu: deploy
	bash tests/test_dos_async_interrupt_qemu.sh

clean:
	git -C "$(CURDIR)/MS-DOS" clean -fXq 2>/dev/null || true
	rm -f $(FLOPPY) $(OUT)/serial.log
