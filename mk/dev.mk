# ---------------------------------------------------------------------------
# DEV (device drivers)
# Built sub-modules: DRIVER, ANSI
# Include path for all DEV sub-dirs (2 levels deep: DEV/SUBDIR/)
# ---------------------------------------------------------------------------
DEV_DIR  := $(SRC)/DEV
DEV_AINC := -I. -ID:\\TOOLS\\INC -I..\\..\\INC -I..\\..\\DOS

dev: \
    $(DEV_DIR)/DRIVER/DRIVER.SYS \
    $(DEV_DIR)/ANSI/ANSI.SYS

# ---------------------------------------------------------------------------
# DEV/DRIVER
# ---------------------------------------------------------------------------
DRIVER_DIR := $(DEV_DIR)/DRIVER

$(DRIVER_DIR)/DRIVER.CTL: $(DRIVER_DIR)/DRIVER.SKL $(MESSAGES_OUT)
	cd $(DRIVER_DIR) && $(BUILDMSG) "..\\..\\MESSAGES\\USA-MS" DRIVER.SKL

$(DRIVER_DIR)/DRIVER.OBJ: $(DRIVER_DIR)/DRIVER.ASM $(DRIVER_DIR)/DRIVER.CTL
	cd $(DRIVER_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "DRIVER.ASM,DRIVER.OBJ;"

$(DRIVER_DIR)/DRIVER.EXE: $(DRIVER_DIR)/DRIVER.OBJ
	cd $(DRIVER_DIR) && $(LINK) "@DRIVER.LNK"

$(DRIVER_DIR)/DRIVER.SYS: $(DRIVER_DIR)/DRIVER.EXE
	cd $(DRIVER_DIR) && $(EXE2BIN) "DRIVER.EXE DRIVER.SYS"

# ---------------------------------------------------------------------------
# DEV/ANSI
# ---------------------------------------------------------------------------
ANSI_DIR := $(DEV_DIR)/ANSI

$(ANSI_DIR)/ANSI.CTL: $(ANSI_DIR)/ANSI.SKL $(MESSAGES_OUT)
	cd $(ANSI_DIR) && $(BUILDMSG) "..\\..\\MESSAGES\\USA-MS" ANSI.SKL

$(ANSI_DIR)/ANSI.OBJ: $(ANSI_DIR)/ANSI.ASM
	cd $(ANSI_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "ANSI.ASM,ANSI.OBJ;"

$(ANSI_DIR)/IOCTL.OBJ: $(ANSI_DIR)/IOCTL.ASM
	cd $(ANSI_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "IOCTL.ASM,IOCTL.OBJ;"

$(ANSI_DIR)/ANSIINIT.OBJ: $(ANSI_DIR)/ANSIINIT.ASM
	cd $(ANSI_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "ANSIINIT.ASM,ANSIINIT.OBJ;"

$(ANSI_DIR)/PARSER.OBJ: $(ANSI_DIR)/PARSER.ASM $(ANSI_DIR)/ANSI.CTL
	cd $(ANSI_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "PARSER.ASM,PARSER.OBJ;"

$(ANSI_DIR)/ANSI.EXE: \
    $(ANSI_DIR)/ANSI.OBJ $(ANSI_DIR)/IOCTL.OBJ \
    $(ANSI_DIR)/ANSIINIT.OBJ $(ANSI_DIR)/PARSER.OBJ
	cd $(ANSI_DIR) && $(LINK) "@ANSI.LNK"

$(ANSI_DIR)/ANSI.SYS: $(ANSI_DIR)/ANSI.EXE
	cd $(ANSI_DIR) && $(EXE2BIN) "ANSI.EXE ANSI.SYS"
