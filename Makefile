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

$(BOOT_DIR)/boot.cl1: $(BOOT_DIR)/boot.skl $(MESSAGES_OUT)
	cd $(BOOT_DIR) && $(NOSRVBLD) boot.skl "..\MESSAGES\$(COUNTRY).msg"

$(BOOT_DIR)/msboot.obj: $(BOOT_DIR)/msboot.asm $(BOOT_DIR)/boot.cl1
	cd $(BOOT_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\INC" "msboot.asm,msboot.obj;"

$(BOOT_DIR)/msboot.exe: $(BOOT_DIR)/msboot.obj
	cd $(BOOT_DIR) && $(LINK) "msboot;"

$(BOOT_DIR)/msboot.bin: $(BOOT_DIR)/msboot.exe
	cd $(BOOT_DIR) && $(EXE2BIN) "msboot.exe msboot.bin"

$(BOOT_INC): $(BOOT_DIR)/msboot.bin
	cd $(BOOT_DIR) && $(DBOF) "msboot.bin boot.inc 7c00 200"
	cp $(BOOT_DIR)/boot.inc $(SRC)/INC/boot.inc

# ---------------------------------------------------------------------------
# INC (shared kernel objects)
# ---------------------------------------------------------------------------
INC_DIR  := $(SRC)/INC
HINC_DIR := $(SRC)/H
DOS_DIR  := $(SRC)/DOS

INC_OBJS := errtst.obj sysvar.obj cds.obj dpb.obj nibdos.obj \
            const2.obj msdata.obj msdosme.obj mstable.obj
INC_OBJ_PATHS := $(addprefix $(INC_DIR)/,$(INC_OBJS))

inc: $(INC_OBJ_PATHS)

# C source objects
$(INC_DIR)/errtst.obj: $(INC_DIR)/errtst.c
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -Foerrtst.obj errtst.c"

$(INC_DIR)/sysvar.obj: $(INC_DIR)/sysvar.c
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -Fosysvar.obj sysvar.c"

$(INC_DIR)/cds.obj: $(INC_DIR)/cds.c
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -Focds.obj cds.c"

$(INC_DIR)/dpb.obj: $(INC_DIR)/dpb.c
	cd $(INC_DIR) && $(CL) "-AS -Od -Zp -I. -I..\\H -c -Fodpb.obj dpb.c"

# ASM source objects
$(INC_DIR)/nibdos.obj: $(INC_DIR)/nibdos.asm
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "nibdos.asm,nibdos.obj;"

$(INC_DIR)/const2.obj: $(INC_DIR)/const2.asm
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "const2.asm,const2.obj;"

$(INC_DIR)/msdata.obj: $(INC_DIR)/msdata.asm
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "msdata.asm,msdata.obj;"

$(INC_DIR)/msdosme.obj: $(INC_DIR)/msdosme.asm
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "msdosme.asm,msdosme.obj;"

$(INC_DIR)/mstable.obj: $(INC_DIR)/mstable.asm
	cd $(INC_DIR) && $(MASM) "$(AFLAGS) -I. -ID:\\TOOLS\\INC -I..\\DOS" "mstable.asm,mstable.obj;"

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
