# ---------------------------------------------------------------------------
# BIOS (io.sys)
# ---------------------------------------------------------------------------
BIOS_DIR := $(SRC)/BIOS
BIOS_OUT := $(BIOS_DIR)/IO.SYS

bios: $(BIOS_OUT)

# BIOS include paths (relative to BIOS_DIR)
BIOS_AINC := -I. -ID:\\TOOLS\\INC -I..\\INC

# ---------------------------------------------------------------------------
# Step 1: Generate CL1..CL5 from MSBIO.SKL via NOSRVBLD
# ---------------------------------------------------------------------------
$(BIOS_DIR)/MSBIO.CL1: $(BIOS_DIR)/MSBIO.SKL $(MESSAGES_OUT)
	cd $(BIOS_DIR) && $(NOSRVBLD) MSBIO.SKL "..\MESSAGES\USA-MS.MSG"

# CL2..CL5 are side-effects of the same NOSRVBLD run
$(BIOS_DIR)/MSBIO.CL2 $(BIOS_DIR)/MSBIO.CL3 \
$(BIOS_DIR)/MSBIO.CL4 $(BIOS_DIR)/MSBIO.CL5: $(BIOS_DIR)/MSBIO.CL1

# ---------------------------------------------------------------------------
# Step 2: Assemble all BIOS objects
# ---------------------------------------------------------------------------
$(BIOS_DIR)/MSBIO1.OBJ: $(BIOS_DIR)/MSBIO1.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSBIO1.ASM,MSBIO1.OBJ;"

$(BIOS_DIR)/MSCON.OBJ: $(BIOS_DIR)/MSCON.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSCON.ASM,MSCON.OBJ;"

$(BIOS_DIR)/MSAUX.OBJ: $(BIOS_DIR)/MSAUX.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSAUX.ASM,MSAUX.OBJ;"

$(BIOS_DIR)/MSLPT.OBJ: $(BIOS_DIR)/MSLPT.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSLPT.ASM,MSLPT.OBJ;"

$(BIOS_DIR)/MSCLOCK.OBJ: $(BIOS_DIR)/MSCLOCK.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSCLOCK.ASM,MSCLOCK.OBJ;"

$(BIOS_DIR)/MSDISK.OBJ: $(BIOS_DIR)/MSDISK.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSDISK.ASM,MSDISK.OBJ;"

$(BIOS_DIR)/MSBIO2.OBJ: $(BIOS_DIR)/MSBIO2.ASM $(BIOS_DIR)/MSBIO.CL2
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSBIO2.ASM,MSBIO2.OBJ;"

$(BIOS_DIR)/MSHARD.OBJ: $(BIOS_DIR)/MSHARD.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSHARD.ASM,MSHARD.OBJ;"

$(BIOS_DIR)/MSINIT.OBJ: $(BIOS_DIR)/MSINIT.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSINIT.ASM,MSINIT.OBJ;"

$(BIOS_DIR)/SYSINIT1.OBJ: $(BIOS_DIR)/SYSINIT1.ASM \
    $(BIOS_DIR)/MSBIO.CL4 $(BIOS_DIR)/MSBIO.CL5
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "SYSINIT1.ASM,SYSINIT1.OBJ;"

$(BIOS_DIR)/SYSCONF.OBJ: $(BIOS_DIR)/SYSCONF.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "SYSCONF.ASM,SYSCONF.OBJ;"

$(BIOS_DIR)/SYSINIT2.OBJ: $(BIOS_DIR)/SYSINIT2.ASM
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "SYSINIT2.ASM,SYSINIT2.OBJ;"

$(BIOS_DIR)/SYSIMES.OBJ: $(BIOS_DIR)/SYSIMES.ASM $(BIOS_DIR)/MSBIO.CL3
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "SYSIMES.ASM,SYSIMES.OBJ;"

# ---------------------------------------------------------------------------
# Step 3: MSLOAD.COM (loader stub)
# ---------------------------------------------------------------------------
$(BIOS_DIR)/MSLOAD.OBJ: $(BIOS_DIR)/MSLOAD.ASM $(BIOS_DIR)/MSBIO.CL1
	cd $(BIOS_DIR) && $(MASM) "$(AFLAGS) $(BIOS_AINC)" "MSLOAD.ASM,MSLOAD.OBJ;"

$(BIOS_DIR)/MSLOAD.EXE: $(BIOS_DIR)/MSLOAD.OBJ
	cd $(BIOS_DIR) && $(LINK) "MSLOAD.OBJ,MSLOAD,,;"

$(BIOS_DIR)/MSLOAD.COM: $(BIOS_DIR)/MSLOAD.EXE
	cd $(BIOS_DIR) && $(EXE2BIN) "MSLOAD.EXE MSLOAD.COM"

# ---------------------------------------------------------------------------
# Step 4: MSBIO.BIN (main BIOS body)
# ---------------------------------------------------------------------------
BIOS_OBJS := MSBIO1.OBJ MSCON.OBJ MSAUX.OBJ MSLPT.OBJ MSCLOCK.OBJ MSDISK.OBJ \
             MSBIO2.OBJ MSHARD.OBJ MSINIT.OBJ SYSINIT1.OBJ SYSCONF.OBJ \
             SYSINIT2.OBJ SYSIMES.OBJ
BIOS_OBJ_PATHS := $(addprefix $(BIOS_DIR)/,$(BIOS_OBJS))

$(BIOS_DIR)/MSBIO.EXE: $(BIOS_OBJ_PATHS)
	cd $(BIOS_DIR) && $(LINK) "@MSBIO.LNK"

$(BIOS_DIR)/MSBIO.BIN: $(BIOS_DIR)/MSBIO.EXE
	cd $(BIOS_DIR) && $(EXE2BIN) "MSBIO.EXE MSBIO.BIN" <LOCSCR

# ---------------------------------------------------------------------------
# Step 5: IO.SYS = MSLOAD.COM + MSBIO.BIN
# ---------------------------------------------------------------------------
$(BIOS_OUT): $(BIOS_DIR)/MSLOAD.COM $(BIOS_DIR)/MSBIO.BIN
	cat $(BIOS_DIR)/MSLOAD.COM $(BIOS_DIR)/MSBIO.BIN > $(BIOS_OUT)
