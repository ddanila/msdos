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

.PHONY: all messages mapper boot inc bios dos cmd dev select memm clean

all: messages mapper boot inc bios

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
clean:
	find $(SRC) -name "*.obj" -o -name "*.exe" -o -name "*.bin" \
	    -o -name "*.com" -o -name "*.sys" -o -name "*.lib" \
	    -o -name "*.cl1" -o -name "*.idx" | xargs rm -f
