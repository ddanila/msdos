
SHELL    := /bin/bash
SRC      := $(CURDIR)/src
BIN      := $(CURDIR)/bin
OUT      := $(CURDIR)/out

MASM     := $(BIN)/jwasm-masm
NASM     := nasm
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

.PHONY: all build-all messages mapper boot inc bios dos cmd cmd_command dev select memm clean test test-native-build-tools test-batch-oracles test-oracle-mutation-coverage test-coverage-manifest test-int21-error-coverage-manifest test-runtime-coverage-manifest test-command-coverage-manifest test-utility-parser-coverage-manifest test-program-interface-coverage-manifest test-dos-interrupt-coverage-manifest test-device-request-coverage-manifest deploy minimal-floppy run-boot test-sys test-help-qemu test-command-startup-qemu test-more-paging-qemu test-misc-qemu test-graftabl-qemu test-mode-redirect-qemu test-keyb-layout-qemu test-backup-restore test-diskcomp-diskcopy test-setver-qemu test-doskey-qemu test-share-nlsfunc-exe2bin test-append test-format test-format-hdd-qemu test-format-one test-format-parallel test-label test-fdisk test-recover test-assign-subst-join test-debug-qemu test-edlin-qemu test-chkdsk-fix test-prompt-yesno test-screen-expect test-select test-drivers-qemu test-ansi-driver-qemu test-display-chain-qemu test-driver-sys-qemu test-driver-geometry-qemu test-printer-driver-qemu test-smartdrv-flush-qemu test-smartdrv-reboot-qemu test-xma-drivers-qemu test-himem-qemu test-himem-xms3-qemu test-himem-286-dosbox test-himem-286-86box test-286-acceptance test-hardware-matrix test-hma-qemu test-pre386-dosbox test-mem-umb-qemu test-loadhigh-qemu test-devicehigh-qemu test-installhigh-qemu test-root-exhaustion-qemu test-disk-exhaustion-qemu test-config-state-qemu test-config-switches-qemu test-config-stacks-qemu test-config-dos-qemu test-xms-umb-transaction-qemu test-config-ifs-qemu test-ifsfunc-filesys-qemu test-config-multitrack-qemu test-emm386-qemu test-emm386-address-phases-qemu test-int21-file-memory-qemu test-int21-path-errors-qemu test-int21-system-qemu test-int21-fcb-qemu test-int21-compat-qemu test-int21-console-qemu test-int21-process-qemu test-int21-tsr-qemu test-int21-media-qemu test-int21-readonly-media-qemu test-dos-interrupt-qemu test-dos-async-interrupt-qemu
.PHONY: test-utility-parser-coverage-manifest test-keyboard-records test-country-records test-country-matrix-qemu test-internal-structure-coverage-manifest test-internal-structures-qemu
.PHONY: test-program-interface-coverage-manifest test-debug-command-coverage-manifest test-help-coverage-manifest test-expand test-choice test-loadfix-qemu test-deltree-qemu test-move-qemu test-szdd-tool distribution test-distribution test-setup-qemu test-setup-floppy-qemu test-mirror-unformat-qemu test-undelete-qemu
.PHONY: test-command-step-qemu test-msd-qemu test-scandisk-qemu test-defrag-qemu test-defrag-fat16-qemu test-mem-dos6-qemu test-memmaker-qemu test-memmaker-rollback-qemu test-power-qemu test-power-api-qemu test-config-menu-qemu test-config-menu-input-qemu
.PHONY: test-copy-policy-qemu test-86box-286-boot test-platform-286-86box test-pre386-memory-86box test-startup-reboot-286-86box test-himem-residency
.PHONY: test-xcopy-dos6-qemu test-ega-qemu test-help-ui-qemu test-command-residency
.PHONY: test-config-numlock-qemu
.PHONY: test-config-set-qemu
.PHONY: test-startup-keys-qemu
.PHONY: test-smartdrv-runtime-qemu
.PHONY: test-supplemental-locale-qemu
.PHONY: test-ems40-coverage-manifest test-ems40-extended-qemu
.PHONY: test-vc-memory-report
.PHONY: test-dos-bios-residency

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

$(INC_DIR)/NIBDOS.OBJ: $(INC_DIR)/NIBDOS.ASM $(INC_DIR)/MSHEAD.ASM $(DOS_DIR)/MSCONST.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "NIBDOS.ASM,NIBDOS.OBJ;"

$(INC_DIR)/CONST2.OBJ: $(INC_DIR)/CONST2.ASM
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "CONST2.ASM,CONST2.OBJ;"

$(INC_DIR)/MSDATA.OBJ: $(INC_DIR)/MSDATA.ASM $(INC_DIR)/MS_DATA.ASM $(DOS_DIR)/MSINIT.ASM $(INC_DIR)/SETVER62.INC
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDATA.ASM,MSDATA.OBJ;"

$(INC_DIR)/MSDOSME.OBJ: $(INC_DIR)/MSDOSME.ASM $(DOS_DIR)/DOSMES.ASM $(DOS_DIR)/MSDOS.CL1
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "MSDOSME.ASM,MSDOSME.OBJ;"

$(INC_DIR)/MSTABLE.OBJ: $(INC_DIR)/MSTABLE.ASM $(DOS_DIR)/MS_TABLE.ASM $(INC_DIR)/SETVER62.INC
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
    BIOS/SYSMENU.OVL \
    DOS/MSDOS.SYS \
    DEV/HIMEM/HIMEM.SYS \
    DEV/EGA/EGA.SYS \
    CMD/COMMAND/COMMAND.COM \
    CMD/SYS/SYS.COM \
    CMD/FORMAT/FORMAT.COM \
    CMD/EXPAND/EXPAND.EXE \
    CMD/SETUP/SETUP.EXE \
    CMD/CHKDSK/CHKDSK.COM \
    DEV/ANSI/ANSI.SYS \
    DEV/VDISK/VDISK.SYS \
    DEV/COUNTRY/COUNTRY.SYS \
    DEV/RAMDRIVE/RAMDRIVE.SYS \
    DEV/KEYBOARD/KEYBOARD.SYS \
    DEV/PRINTER/PRINTER.SYS \
    DEV/DISPLAY/DISPLAY.SYS \
    DEV/SMARTDRV/SMARTDRV.EXE \
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
    CMD/SETVER/SETVER.COM \
    CMD/SETVER/SETVER.EXE \
    CMD/DOSKEY/DOSKEY.COM \
    CMD/HELP/HELP.COM \
    CMD/HELP/HELP.HLP \
    CMD/MIRROR/MIRROR.COM \
    CMD/UNDELETE/UNDELETE.COM \
    CMD/UNFORMAT/UNFORMAT.COM \
    CMD/CHOICE/CHOICE.COM \
    CMD/LOADFIX/LOADFIX.COM \
    CMD/DELTREE/DELTREE.EXE \
    CMD/DEFRAG/DEFRAG.EXE \
    CMD/MOVE/MOVE.EXE \
    CMD/SCANDISK/SCANDISK.EXE \
    CMD/SCANDISK/SCANDISK.INI \
    CMD/MEMMAKER/MEMMAKER.EXE \
    CMD/SIZER/SIZER.EXE \
    CMD/POWER/POWER.EXE \
    CMD/MSCDEX/MSCDEX.EXE \
    CMD/INTERLNK/INTERLNK.EXE \
    CMD/INTERSVR/INTERSVR.EXE \
    MEMM/MEMM/EMM386.EXE

test: $(KVIKDOS_SOFT_BIN) test-native-build-tools test-keyboard-records test-country-records test-szdd-tool test-drdos-capture test-distribution test-expand test-choice test-loadfix-qemu test-deltree-qemu test-move-qemu test-scandisk-qemu test-defrag-qemu test-defrag-fat16-qemu test-mem-dos6-qemu test-memmaker-qemu test-memmaker-rollback-qemu test-smartdrv-reboot-qemu test-power-qemu test-power-api-qemu test-mscdex-qemu test-interlnk-qemu test-setup-qemu test-setup-floppy-qemu test-ega-qemu test-help-ui-qemu test-himem-options-qemu test-himem-xms3-qemu test-ems40-extended-qemu test-emm386-address-phases-qemu test-internal-structures-qemu test-supplemental-locale-qemu test-vc-memory-report test-dos-bios-residency test-command-residency test-himem-residency test-batch-oracles test-oracle-mutation-coverage test-coverage-manifest test-int21-error-coverage-manifest test-runtime-coverage-manifest test-command-coverage-manifest test-utility-parser-coverage-manifest test-program-interface-coverage-manifest test-debug-command-coverage-manifest test-help-coverage-manifest test-dos-interrupt-coverage-manifest test-internal-structure-coverage-manifest test-ems40-coverage-manifest test-device-request-coverage-manifest
	bash tests/run_tests.sh

test-native-build-tools:
	bash tests/test_native_build_tools.sh

test-vc-memory-report:
	python3 tests/test_vc_memory_comparison.py

test-drdos-capture:
	python3 tests/test_capture_drdos_memory.py
	python3 tests/test_opendos_sda.py
	python3 tests/test_uma_topology.py

.PHONY: test-emm-init-phases
.PHONY: test-move-block-abi-qemu
test-move-block-abi-qemu:
	python3 tests/test_move_block_abi_qemu.py

.PHONY: test-move-block-cleanup-qemu
test-move-block-cleanup-qemu: memm
	python3 tests/test_move_block_cleanup_qemu.py
	python3 tests/test_move_block_cleanup_qemu.py --a20-off

.PHONY: test-xms-copy-windows-qemu
test-xms-copy-windows-qemu:
	python3 tests/test_xms_copy_windows_qemu.py
	python3 tests/test_xms_copy_windows_qemu.py --fail-after-map
	python3 tests/test_xms_copy_windows_qemu.py --mapped

.PHONY: test-emm-xms-owner-qemu
test-emm-xms-owner-qemu:
	python3 tests/test_emm_xms_owner_qemu.py

test-emm-init-phases:
	python3 tests/test_emm_init_phases.py
	python3 tests/test_emm_loader_rebase.py

.PHONY: test-dos-sda-qemu
test-dos-sda-qemu: dos
	python3 tests/test_dos_sda_qemu.py

# Uses existing built objects; rebuild/deploy explicitly before this isolated fixture.
.PHONY: test-umb-subpage-discovery-qemu
test-umb-subpage-discovery-qemu:
	python3 tests/test_umb_subpage_discovery_qemu.py

.PHONY: test-umb-subpage-mapping-qemu
test-umb-subpage-mapping-qemu:
	python3 tests/test_umb_subpage_mapping_qemu.py
	python3 tests/test_umb_subpage_mapping_qemu.py --warm-reset

.PHONY: test-umb-subpage-composition
test-umb-subpage-composition:
	python3 tests/test_umb_subpage_composition.py

.PHONY: test-high-cds-qemu test-high-cds-composition
test-high-cds-qemu: $(ASSIGN_OUT) $(JOIN_OUT)
	python3 tests/test_high_cds_qemu.py

test-high-cds-composition:
	python3 tests/test_umb_subpage_composition.py --high-cds

test-dos-bios-residency: dos bios
	python3 tests/test_dos_copy_size.py
	python3 tests/test_system_owners.py
	python3 tests/test_hma_layout_budget.py
	python3 tests/test_bios_character_partition.py
	python3 tests/test_dos_swap_contract.py
	python3 tests/report_dos_bios_residency.py --check \
		src/DOS/MSDOS.MAP src/BIOS/msBIO.map

.PHONY: test-bios-service-crossings
test-bios-service-crossings: bios
	python3 tests/test_bios_service_crossings.py
	python3 tests/test_bios_data_segment.py
	python3 tests/report_bios_service_crossings.py

.PHONY: test-bios-high-rom-qemu
.PHONY: test-bios-high-payload
test-bios-high-payload: bios
	python3 tests/test_bios_high_payload.py
	python3 tests/build_bios_high_payload.py out/bios-high-payload

.PHONY: test-bios-payload-qemu
.PHONY: test-bios-low-boot-qemu
test-bios-low-boot-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py

.PHONY: test-bios-rebase-qemu
test-bios-rebase-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --scan
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --scan
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --scan --fail-reservation
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --warm-reset --mode himem-high --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --stale-cds-control --mode himem-high --mode emm-high
	python3 tests/test_vc_memory_comparison.py

.PHONY: test-bios-buffer-capacity-qemu
.PHONY: test-bios-upper-tables-qemu
test-bios-upper-tables-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --files 8
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --files 30
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --fail-table-allocation
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --upper-access-control --mode emm-high

.PHONY: test-bios-share-tables-qemu
test-bios-share-tables-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --share
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --share --fcb-keep 1

.PHONY: test-bios-umb-io-qemu
test-bios-umb-io-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-last --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-last --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --reverse-umb-backing --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --reverse-umb-backing --umb-last --warm-reset --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-ems --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-ems --reverse-umb-backing --umb-last --warm-reset --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-ems --ansi-high --share --fcb-keep 1 --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-ems --fail-reservation --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --umb-span 32 --umb-ems --fail-reservation --reverse-umb-backing --umb-last --warm-reset --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --ansi-high --share --fcb-keep 1 --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --umb-read --warm-reset --mode emm-high

.PHONY: test-bios-ansi-tables-qemu
test-bios-ansi-tables-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --ansi-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --ansi-high --share --fcb-keep 1
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --ansi-high --fail-table-allocation --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --ansi-high --warm-reset --mode emm-high

test-bios-buffer-capacity-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --buffers 1
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --buffers 38 --mode himem-high --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --buffers 39 --mode himem-high --mode emm-high
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --buffers 40
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --rebase --compact --buffers 99

.PHONY: test-bios-rebase-scan-qemu
test-bios-rebase-scan-qemu: deploy
	python3 tests/test_bios_rebase_scan.py
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --scan
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --scan --fail-reservation

.PHONY: test-bios-tail-boot-qemu
test-bios-tail-boot-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --tail-body
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early
	python3 tests/test_bios_low_boot_qemu.py --tail-body --early --fail-reservation

.PHONY: test-bios-early-boot-qemu
test-bios-early-boot-qemu: deploy
	python3 tests/test_bios_low_boot_qemu.py --early
	python3 tests/test_bios_low_boot_qemu.py --early --fail-reservation

test-bios-payload-qemu: deploy
	python3 tests/test_bios_payload_qemu.py

test-bios-high-rom-qemu: deploy
	bash tests/test_bios_high_rom_qemu.sh

test-command-residency: cmd_command
	python3 tests/report_command_residency.py --check \
		src/CMD/COMMAND/COMMAND.MAP src/CMD/COMMAND/COMMAND.COM

.PHONY: test-emm-relocation-budget
test: test-emm-relocation-budget
test-emm-relocation-budget: memm
	python3 tests/test_emm_relocation_budget.py
	python3 tests/test_emm_live_owners.py
	python3 tests/report_emm386_residency.py --check src/MEMM/MEMM/EMM386.MAP
	python3 tests/report_emm386_residency.py --check --page-assignments 20 \
		src/MEMM/MEMM/EMM386.MAP
	python3 tests/report_emm386_residency.py --check --handles 255 \
		--alternate-registers 254 --ems-pages 2048 --physical-pages 52 \
		--page-assignments 20 --dma-pages 16 src/MEMM/MEMM/EMM386.MAP

test-himem-residency: $(BIN)/jwasm-bin
	python3 tests/test_himem_ownership.py
	mkdir -p $(OUT)
	$(BIN)/jwasm-bin -q -bin -Sa -Fl=$(OUT)/himem-residency.lst \
		-Fo$(OUT)/himem-residency.sys $(SRC)/DEV/HIMEM/HIMEM.ASM
	python3 tests/report_himem_residency.py --check \
		$(OUT)/himem-residency.lst $(OUT)/himem-residency.sys

test-keyboard-records: $(KEYBOARD_SYS)
	python3 tests/test_keyboard_records.py

test-country-records: $(COUNTRY_SYS)
	python3 tests/test_country_records.py

test-country-matrix-qemu: deploy
	bash tests/test_country_matrix_qemu.sh

test-ega-qemu: deploy
	bash tests/test_ega_qemu.sh

test-help-ui-qemu: deploy
	bash tests/test_help_ui_qemu.sh

test-expand: deploy $(KVIKDOS_SOFT_BIN)
	bash tests/test_expand.sh

test-choice: $(CHOICE_OUT) $(KVIKDOS_SOFT_BIN)
	bash tests/test_choice.sh

test-loadfix-qemu: deploy
	bash tests/test_loadfix_qemu.sh

test-deltree-qemu: deploy
	bash tests/test_deltree_qemu.sh

test-move-qemu: deploy
	bash tests/test_move_qemu.sh

test-szdd-tool:
	python3 tests/test_szdd_tool.py

distribution: deploy
	python3 tools/build_distribution.py

test-distribution: deploy
	python3 tests/test_distribution.py

test-setup-qemu: distribution
	bash tests/test_setup_qemu.sh

test-setup-floppy-qemu: distribution
	bash tests/test_setup_floppy_qemu.sh

test-himem-options-qemu: deploy
	bash tests/test_himem_options_qemu.sh

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

test-internal-structure-coverage-manifest:
	python3 tests/test_internal_structure_coverage.py --require-complete

test-internal-structures-qemu: deploy
	bash tests/test_internal_structures_qemu.sh

test-supplemental-locale-qemu: deploy
	bash tests/test_supplemental_locale_qemu.sh

test-ems40-coverage-manifest:
	python3 tests/test_ems40_coverage.py --require-complete

test-ems40-extended-qemu: deploy
	python3 tests/test_emm_table_ownership.py
	bash tests/test_ems40_extended_qemu.sh

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
	mcopy -i $(FLOPPY) $(SYSMENU_OVL) ::SYSMENU.OVL
	echo 'drive a: file="$(FLOPPY)"' > $(OUT)/.mtoolsrc
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/IO.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/MSDOS.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/SYSMENU.OVL
	rm -f $(OUT)/.mtoolsrc
	@echo "Minimal floppy built: $(FLOPPY)"

test-sys: deploy
	bash tests/test_sys.sh
	bash tests/test_sys_hdd_qemu.sh

test-sys-hdd-qemu: deploy
	bash tests/test_sys_hdd_qemu.sh

test-help-qemu: deploy
	bash tests/test_help_qemu.sh

test-mirror-unformat-qemu: deploy cmd
	bash tests/test_mirror_unformat_qemu.sh

test-undelete-qemu: deploy cmd
	bash tests/test_undelete_qemu.sh

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

test-format-hdd-qemu: deploy
	bash tests/test_format_hdd_qemu.sh

test-msd-qemu: deploy
	bash tests/test_msd_qemu.sh

test-scandisk-qemu: deploy
	bash tests/test_scandisk_qemu.sh
	bash tests/test_scandisk_errors_qemu.sh
	bash tests/test_scandisk_interactive_qemu.sh
	bash tests/test_scandisk_fat16_qemu.sh

test-defrag-qemu: deploy
	bash tests/test_defrag_qemu.sh
	bash tests/test_defrag_errors_qemu.sh
	bash tests/test_defrag_interactive_qemu.sh

test-defrag-fat16-qemu: deploy
	bash tests/test_defrag_fat16_qemu.sh

test-memmaker-qemu: deploy
	bash tests/test_memmaker_qemu.sh
	bash tests/test_memmaker_optimizer_qemu.sh

test-mem-dos6-qemu: deploy
	bash tests/test_mem_dos6_qemu.sh

test-memmaker-rollback-qemu: deploy
	bash tests/test_memmaker_rollback_qemu.sh

test-power-qemu: deploy
	bash tests/test_power_qemu.sh

test-power-api-qemu: deploy
	bash tests/test_power_api_qemu.sh

test-mscdex-qemu: deploy
	bash tests/test_mscdex_qemu.sh

test-interlnk-qemu: deploy
	bash tests/test_interlnk_qemu.sh
	bash tests/test_intersvr_rcopy_qemu.sh

test-config-menu-qemu: deploy
	bash tests/test_config_menu_qemu.sh

test-config-menu-input-qemu: deploy
	bash tests/test_config_menu_input_qemu.sh

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

.PHONY: test-command-critical-abi-qemu
test: test-command-critical-abi-qemu
test-command-critical-abi-qemu: deploy
	COMMAND_CRITICAL_ABI=1 bash tests/test_command_startup_qemu.sh
	COMMAND_CRITICAL_ABI=1 COMMAND_CRITICAL_ACTION=retry bash tests/test_command_startup_qemu.sh

.PHONY: test-command-critical-split-qemu
test-command-critical-split-qemu: deploy
	bash tests/test_command_critical_split_qemu.sh

.PHONY: test-command-critical-reclaim-qemu
test-command-critical-reclaim-qemu: deploy
	COMMAND_CRITICAL_RECLAIM=1 bash tests/test_command_critical_split_qemu.sh

.PHONY: test-command-int2e-owner-qemu
test-command-int2e-owner-qemu: deploy
	bash tests/test_command_int2e_owner_qemu.sh

.PHONY: test-command-resident-binding-qemu
test-command-resident-binding-qemu: deploy
	python3 tests/test_command_resident_bindings.py
	bash tests/test_command_resident_binding_qemu.sh

test-command-step-qemu: deploy
	bash tests/test_command_step_qemu.sh

test-copy-policy-qemu: deploy
	bash tests/test_copy_policy_qemu.sh

test-xcopy-dos6-qemu: deploy
	bash tests/test_xcopy_dos6_qemu.sh

test-config-numlock-qemu: deploy
	bash tests/test_config_numlock_qemu.sh

test-config-set-qemu: deploy
	bash tests/test_config_set_qemu.sh

test-startup-keys-qemu: deploy
	bash tests/test_startup_keys_qemu.sh

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

test-driver-geometry-qemu: deploy
	bash tests/test_driver_geometry_qemu.sh

test-printer-driver-qemu: deploy
	bash tests/test_printer_driver_qemu.sh

test-print-spooler-qemu: deploy
	bash tests/test_print_spooler_qemu.sh

test-smartdrv-flush-qemu: deploy
	bash tests/test_smartdrv_flush_qemu.sh

test-smartdrv-dos6-qemu: deploy
	bash tests/test_smartdrv_dos6_qemu.sh

test-smartdrv-runtime-qemu: deploy
	bash tests/test_smartdrv_runtime_qemu.sh

test-smartdrv-reboot-qemu: deploy
	bash tests/test_smartdrv_reboot_qemu.sh

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

test-himem-xms3-qemu: deploy
	bash tests/test_himem_xms3_qemu.sh

test-himem-286-dosbox: deploy
	bash tests/test_himem_286_dosbox.sh

test-86box-286-boot:
	bash tests/test_86box_286_boot.sh

test-himem-286-86box: deploy
	bash tests/test_himem_286_86box.sh

test-platform-286-86box: deploy
	bash tests/test_platform_286_86box.sh

test-pre386-memory-86box: deploy
	bash tests/test_pre386_memory_86box.sh

test-startup-reboot-286-86box: deploy
	bash tests/test_startup_reboot_286_86box.sh

# Deliberately local-only while hosted CI is disabled.
test-286-acceptance: deploy
	bash tests/test_86box_286_boot.sh
	bash tests/test_himem_286_86box.sh
	bash tests/test_platform_286_86box.sh
	bash tests/test_pre386_memory_86box.sh
	bash tests/test_startup_reboot_286_86box.sh

test-hardware-matrix: deploy
	bash tests/test_hardware_matrix.sh

test-hma-qemu: deploy
	bash tests/test_hma_qemu.sh

test-pre386-dosbox: deploy
	bash tests/test_pre386_dosbox.sh

test-mem-umb-qemu: deploy
	bash tests/test_mem_umb_qemu.sh

test-loadhigh-qemu: deploy
	bash tests/test_loadhigh_qemu.sh

test-devicehigh-qemu: deploy
	bash tests/test_devicehigh_qemu.sh

test-installhigh-qemu: deploy
	bash tests/test_installhigh_qemu.sh

test-config-ifs-qemu: deploy
	bash tests/test_config_ifs_qemu.sh

test-ifsfunc-filesys-qemu: deploy
	bash tests/test_ifsfunc_filesys_qemu.sh

test-config-multitrack-qemu: deploy
	bash tests/test_config_multitrack_qemu.sh

test-setver-qemu: deploy
	bash tests/test_setver_qemu.sh

test-doskey-qemu: deploy
	bash tests/test_doskey_qemu.sh

FLOPPY      := $(OUT)/floppy.img
BOOT_BIN    := $(SRC)/BOOT/MSBOOT.BIN
BOOT_OFF    := 31744

IO_SYS      := $(SRC)/BIOS/IO.SYS
MSDOS_SYS   := $(SRC)/DOS/MSDOS.SYS
SYSMENU_OVL := $(SRC)/BIOS/SYSMENU.OVL
COMMAND_COM := $(SRC)/CMD/COMMAND/COMMAND.COM
SYS_COM     := $(SRC)/CMD/SYS/SYS.COM
FORMAT_COM  := $(SRC)/CMD/FORMAT/FORMAT.COM
EXPAND_COM  := $(SRC)/CMD/EXPAND/EXPAND.EXE
SETUP_EXE   := $(SRC)/CMD/SETUP/SETUP.EXE
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
SETVER_COM := $(SRC)/CMD/SETVER/SETVER.COM
SETVER_EXE := $(SRC)/CMD/SETVER/SETVER.EXE
DOSKEY_COM := $(SRC)/CMD/DOSKEY/DOSKEY.COM
HELP_COM   := $(SRC)/CMD/HELP/HELP.COM
FASTHELP_COM := $(SRC)/CMD/HELP/FASTHELP.COM
HELP_HLP   := $(SRC)/CMD/HELP/HELP.HLP
MIRROR_COM := $(SRC)/CMD/MIRROR/MIRROR.COM
UNDELETE_COM := $(SRC)/CMD/UNDELETE/UNDELETE.COM
CHOICE_COM   := $(SRC)/CMD/CHOICE/CHOICE.COM
LOADFIX_COM  := $(SRC)/CMD/LOADFIX/LOADFIX.COM
DELTREE_EXE  := $(SRC)/CMD/DELTREE/DELTREE.EXE
MOVE_EXE     := $(SRC)/CMD/MOVE/MOVE.EXE
MSD_EXE      := $(SRC)/CMD/MSD/MSD.EXE
SCANDISK_EXE := $(SRC)/CMD/SCANDISK/SCANDISK.EXE
SCANDISK_INI := $(SRC)/CMD/SCANDISK/SCANDISK.INI
DEFRAG_EXE   := $(SRC)/CMD/DEFRAG/DEFRAG.EXE
MEMMAKER_EXE := $(SRC)/CMD/MEMMAKER/MEMMAKER.EXE
SIZER_EXE    := $(SRC)/CMD/SIZER/SIZER.EXE
POWER_EXE    := $(SRC)/CMD/POWER/POWER.EXE
MSCDEX_EXE   := $(SRC)/CMD/MSCDEX/MSCDEX.EXE
INTERLNK_EXE := $(SRC)/CMD/INTERLNK/INTERLNK.EXE
INTERSVR_EXE := $(SRC)/CMD/INTERSVR/INTERSVR.EXE
UNFORMAT_COM := $(SRC)/CMD/UNFORMAT/UNFORMAT.COM
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
PRINTER_4208_CPI := $(SRC)/DEV/PRINTER/4208/4208.CPI
PRINTER_5202_CPI := $(SRC)/DEV/PRINTER/5202/5202.CPI
SMARTDRV_EXE := $(SRC)/DEV/SMARTDRV/SMARTDRV.EXE
FLUSH13_EXE  := $(SRC)/DEV/SMARTDRV/FLUSH13.EXE
DRIVER_SYS   := $(SRC)/DEV/DRIVER/DRIVER.SYS
XMA2EMS_SYS  := $(SRC)/DEV/XMA2EMS/XMA2EMS.SYS
XMAEM_SYS    := $(SRC)/DEV/XMAEM/XMAEM.SYS
SELECT_COM   := $(SRC)/SELECT/SELECT.COM
SELECT_EXE   := $(SRC)/SELECT/SELECT.EXE
SELECT_DAT   := $(SRC)/SELECT/SELECT.DAT
SELECT_HLP   := $(SRC)/SELECT/SELECT.HLP
EGA_CPI      := $(SRC)/DEV/DISPLAY/EGA/EGA.CPI
LCD_CPI      := $(SRC)/DEV/DISPLAY/LCD/LCD.CPI
EGA_SYS      := $(SRC)/DEV/EGA/EGA.SYS
HIMEM_SYS    := $(SRC)/DEV/HIMEM/HIMEM.SYS
EMM386_EXE   := $(MEMM_DIR)/EMM386.EXE

$(FLOPPY): $(BOOT_BIN) $(IO_SYS) $(MSDOS_SYS) $(SYSMENU_OVL) $(COMMAND_COM) $(SYS_COM) $(FORMAT_COM) $(EXPAND_COM) $(SETUP_EXE) $(CHKDSK_COM) $(DEBUG_COM) $(MEM_EXE) $(FDISK_EXE) \
           $(MORE_COM) $(SORT_EXE) $(LABEL_COM) $(FIND_EXE) $(TREE_COM) $(COMP_COM) \
           $(ATTRIB_EXE) $(EDLIN_COM) $(FC_EXE) \
           $(NLSFUNC_EXE) $(ASSIGN_COM) $(XCOPY_EXE) $(DISKCOMP_COM) $(DISKCOPY_COM) $(SETVER_COM) $(SETVER_EXE) $(DOSKEY_COM) \
           $(APPEND_EXE) $(RECOVER_COM) $(FASTOPEN_EXE) $(PRINT_COM) $(HELP_COM) $(FASTHELP_COM) $(HELP_HLP) \
           $(MIRROR_COM) $(UNDELETE_COM) $(UNFORMAT_COM) $(CHOICE_COM) $(LOADFIX_COM) $(DELTREE_EXE) $(DEFRAG_EXE) $(MOVE_EXE) $(MSD_EXE) $(SCANDISK_EXE) $(SCANDISK_INI) $(MEMMAKER_EXE) $(SIZER_EXE) $(POWER_EXE) $(MSCDEX_EXE) $(INTERLNK_EXE) $(INTERSVR_EXE) \
           $(FILESYS_EXE) $(REPLACE_EXE) $(JOIN_EXE) $(SUBST_EXE) \
           $(BACKUP_COM) $(RESTORE_COM) $(GRAFTABL_COM) $(KEYB_COM) $(KEYBOARD_SYS) $(SHARE_EXE) \
           $(EXE2BIN_SRC) $(GRAPHICS_COM) $(GRAPHICS_PRO) \
           $(IFSFUNC_EXE) $(MODE_COM) \
           $(ANSI_SYS) $(RAMDRIVE_SYS) \
           $(VDISK_SYS) $(DISPLAY_SYS) $(COUNTRY_SYS) $(PRINTER_SYS) $(PRINTER_CPI) $(PRINTER_4208_CPI) $(PRINTER_5202_CPI) \
           $(SMARTDRV_SYS) $(SMARTDRV_EXE) $(FLUSH13_EXE) $(DRIVER_SYS) $(XMA2EMS_SYS) $(XMAEM_SYS) \
           $(SELECT_COM) $(SELECT_EXE) $(SELECT_DAT) $(SELECT_HLP) \
           $(EGA_CPI) $(LCD_CPI) $(EGA_SYS) $(HIMEM_SYS) $(EMM386_EXE)
	mkdir -p $(OUT)
	# The complete developer image needs room for test probes and the growing
	# DOS 6.22 tool set.  The minimal-floppy target remains a 1.44 MB image.
	dd if=/dev/zero of=$@ bs=512 count=5760 status=none
	dd if=$(BOOT_BIN) of=$@ bs=1 skip=$(BOOT_OFF) count=512 conv=notrunc status=none
	$(BIN)/patch-bpb $@
	mformat -i $@ -k ::
	# IO.SYS must be the first root-directory entry because the boot sector assumes it.
	mcopy -i $@ $(IO_SYS) ::IO.SYS
	mcopy -i $@ $(MSDOS_SYS) ::MSDOS.SYS
	mcopy -i $@ $(COMMAND_COM) ::COMMAND.COM
	mcopy -i $@ $(SYSMENU_OVL) ::SYSMENU.OVL
	# mtools 4.0.49 broke mattrib's -i handling, so expose the image through MTOOLSRC.
	echo 'drive a: file="$@"' > $(OUT)/.mtoolsrc
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/IO.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/MSDOS.SYS
	MTOOLSRC=$(OUT)/.mtoolsrc mattrib +h +s +r a:/SYSMENU.OVL
	rm -f $(OUT)/.mtoolsrc
	mcopy -i $@ $(SYS_COM) ::SYS.COM
	mcopy -i $@ $(FORMAT_COM) ::FORMAT.COM
	mcopy -i $@ $(EXPAND_COM) ::EXPAND.EXE
	mcopy -i $@ $(SETUP_EXE) ::SETUP.EXE
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
	mcopy -i $@ $(SETVER_COM) ::SETVER.COM
	mcopy -i $@ $(SETVER_EXE) ::SETVER.EXE
	mcopy -i $@ $(DOSKEY_COM) ::DOSKEY.COM
	mcopy -i $@ $(HELP_COM) ::HELP.COM
	mcopy -i $@ $(FASTHELP_COM) ::FASTHELP.COM
	mcopy -i $@ $(HELP_HLP) ::HELP.HLP
	mcopy -i $@ $(MIRROR_COM) ::MIRROR.COM
	mcopy -i $@ $(UNDELETE_COM) ::UNDELETE.COM
	mcopy -i $@ $(UNFORMAT_COM) ::UNFORMAT.COM
	mcopy -i $@ $(CHOICE_COM) ::CHOICE.COM
	mcopy -i $@ $(LOADFIX_COM) ::LOADFIX.COM
	mcopy -i $@ $(DELTREE_EXE) ::DELTREE.EXE
	mcopy -i $@ $(DEFRAG_EXE) ::DEFRAG.EXE
	mcopy -i $@ $(MOVE_EXE) ::MOVE.EXE
	mcopy -i $@ $(MSD_EXE) ::MSD.EXE
	mcopy -i $@ $(SCANDISK_EXE) ::SCANDISK.EXE
	mcopy -i $@ $(SCANDISK_INI) ::SCANDISK.INI
	mcopy -i $@ $(MEMMAKER_EXE) ::MEMMAKER.EXE
	mcopy -i $@ $(SIZER_EXE) ::SIZER.EXE
	mcopy -i $@ $(POWER_EXE) ::POWER.EXE
	mcopy -i $@ $(MSCDEX_EXE) ::MSCDEX.EXE
	mcopy -i $@ $(INTERLNK_EXE) ::INTERLNK.EXE
	mcopy -i $@ $(INTERSVR_EXE) ::INTERSVR.EXE
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
	mcopy -i $@ $(PRINTER_4208_CPI) ::4208.CPI
	mcopy -i $@ $(PRINTER_5202_CPI) ::5202.CPI
	mcopy -i $@ $(SMARTDRV_EXE) ::SMARTDRV.EXE
	mcopy -i $@ $(FLUSH13_EXE) ::FLUSH13.EXE
	mcopy -i $@ $(DRIVER_SYS) ::DRIVER.SYS
	mcopy -i $@ $(XMA2EMS_SYS) ::XMA2EMS.SYS
	mcopy -i $@ $(XMAEM_SYS) ::XMAEM.SYS
	mcopy -i $@ $(SELECT_COM) ::SELECT.COM
	mcopy -i $@ $(SELECT_EXE) ::SELECT.EXE
	mcopy -i $@ $(SELECT_DAT) ::SELECT.DAT
	mcopy -i $@ $(SELECT_HLP) ::SELECT.HLP
	mcopy -i $@ $(EGA_CPI) ::EGA.CPI
	mcopy -i $@ $(LCD_CPI) ::LCD.CPI
	mcopy -i $@ $(EGA_SYS) ::EGA.SYS
	mcopy -i $@ $(HIMEM_SYS) ::HIMEM.SYS
	mcopy -i $@ $(EMM386_EXE) ::EMM386.EXE

deploy:
	# A single jobserver-aware submake prevents parallel image and build paths
	# from racing on their shared generated message and include files.
	+$(MAKE) $(FLOPPY)

run-boot: deploy
	qemu-system-i386 -fda $(FLOPPY) -boot a -m 4

test-emm386-qemu: deploy
	bash tests/test_emm386_qemu.sh

.PHONY: test-xms-emm-mode-qemu
test-xms-emm-mode-qemu: deploy
	bash tests/test_xms_emm_mode_qemu.sh

test-emm386-address-phases-qemu: deploy
	bash tests/test_emm386_address_phases_qemu.sh

test-emm386-frames-qemu: deploy
	bash tests/test_emm386_frames_qemu.sh

test-emm386-load-options-qemu: deploy
	bash tests/test_emm386_load_options_qemu.sh

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
	git clean -fXq -- src 2>/dev/null || true
	rm -f $(FLOPPY) $(OUT)/serial.log
