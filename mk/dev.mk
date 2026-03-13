# ---------------------------------------------------------------------------
# DEV (device drivers)
# Built sub-modules: DRIVER, ANSI
# Include path for all DEV sub-dirs (2 levels deep: DEV/SUBDIR/)
# ---------------------------------------------------------------------------
DEV_DIR  := $(SRC)/DEV
DEV_AINC := -I. -ID:\\TOOLS\\INC -I..\\..\\INC -I..\\..\\DOS

dev: \
    $(DEV_DIR)/DRIVER/DRIVER.SYS \
    $(DEV_DIR)/ANSI/ANSI.SYS \
    $(DEV_DIR)/VDISK/VDISK.SYS \
    $(DEV_DIR)/COUNTRY/COUNTRY.SYS \
    $(DEV_DIR)/RAMDRIVE/RAMDRIVE.SYS \
    $(DEV_DIR)/KEYBOARD/KEYBOARD.SYS

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

# ---------------------------------------------------------------------------
# DEV/VDISK
# ---------------------------------------------------------------------------
VDISK_DIR := $(DEV_DIR)/VDISK

$(VDISK_DIR)/VDISK.CTL: $(VDISK_DIR)/VDISK.SKL $(MESSAGES_OUT)
	cd $(VDISK_DIR) && $(BUILDMSG) "..\\..\\MESSAGES\\USA-MS" VDISK.SKL

$(VDISK_DIR)/VDISKSYS.OBJ: $(VDISK_DIR)/VDISKSYS.ASM $(VDISK_DIR)/VDISK.CTL
	cd $(VDISK_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "VDISKSYS.ASM,VDISKSYS.OBJ;"

$(VDISK_DIR)/VDISK.EXE: $(VDISK_DIR)/VDISKSYS.OBJ
	cd $(VDISK_DIR) && $(LINK) "@VDISK.LNK"

$(VDISK_DIR)/VDISK.SYS: $(VDISK_DIR)/VDISK.EXE
	cd $(VDISK_DIR) && $(EXE2BIN) "VDISK.EXE VDISK.SYS"

# ---------------------------------------------------------------------------
# DEV/COUNTRY  (runs the built MKCNTRY.EXE tool to generate COUNTRY.SYS)
# ---------------------------------------------------------------------------
COUNTRY_DIR := $(DEV_DIR)/COUNTRY

$(COUNTRY_DIR)/MKCNTRY.OBJ: $(COUNTRY_DIR)/MKCNTRY.ASM
	cd $(COUNTRY_DIR) && $(MASM) "$(AFLAGS) $(DEV_AINC)" "MKCNTRY.ASM,MKCNTRY.OBJ;"

$(COUNTRY_DIR)/MKCNTRY.EXE: $(COUNTRY_DIR)/MKCNTRY.OBJ
	cd $(COUNTRY_DIR) && $(LINK) "MKCNTRY;"

$(COUNTRY_DIR)/COUNTRY.SYS: $(COUNTRY_DIR)/MKCNTRY.EXE
	cd $(COUNTRY_DIR) && $(BIN)/dos-run $(COUNTRY_DIR)/MKCNTRY.EXE

# ---------------------------------------------------------------------------
# DEV/RAMDRIVE (uses -I../../inc forward-slash style; no DOS dir needed)
# ---------------------------------------------------------------------------
RAMDRIVE_DIR := $(DEV_DIR)/RAMDRIVE

$(RAMDRIVE_DIR)/RAMDRIVE.OBJ: $(RAMDRIVE_DIR)/RAMDRIVE.ASM
	cd $(RAMDRIVE_DIR) && $(MASM) "$(AFLAGS) -I. -I..\\..\\INC" "RAMDRIVE.ASM,RAMDRIVE.OBJ;"

$(RAMDRIVE_DIR)/MESSAGES.OBJ: $(RAMDRIVE_DIR)/MESSAGES.ASM
	cd $(RAMDRIVE_DIR) && $(MASM) "$(AFLAGS) -I. -I..\\..\\INC" "MESSAGES.ASM,MESSAGES.OBJ;"

$(RAMDRIVE_DIR)/RAMDRIVE.EXE: \
    $(RAMDRIVE_DIR)/RAMDRIVE.OBJ $(RAMDRIVE_DIR)/MESSAGES.OBJ
	cd $(RAMDRIVE_DIR) && $(LINK) "@RAMDRIVE.LNK"

$(RAMDRIVE_DIR)/RAMDRIVE.SYS: $(RAMDRIVE_DIR)/RAMDRIVE.EXE
	cd $(RAMDRIVE_DIR) && $(EXE2BIN) "RAMDRIVE.EXE RAMDRIVE.SYS"

# ---------------------------------------------------------------------------
# DEV/KEYBOARD (20 KDF files)
# ---------------------------------------------------------------------------
KEYBOARD_DIR := $(DEV_DIR)/KEYBOARD
KB_AINC := -I. -I..\\..\\INC

KEYBOARD_OBJS := KDFNOW.OBJ KDFFR120.OBJ KDFFR189.OBJ KDFEOF.OBJ \
    KDFUK166.OBJ KDFUK168.OBJ KDFIT141.OBJ KDFIT142.OBJ \
    KDFGE.OBJ KDFSP.OBJ KDFNL.OBJ KDFNO.OBJ KDFDK.OBJ \
    KDFSG.OBJ KDFSF.OBJ KDFPO.OBJ KDFBE.OBJ KDFCF.OBJ \
    KDFLA.OBJ KDFSV.OBJ

KEYBOARD_OBJ_PATHS := $(addprefix $(KEYBOARD_DIR)/,$(KEYBOARD_OBJS))

$(KEYBOARD_DIR)/%.OBJ: $(KEYBOARD_DIR)/%.ASM
	cd $(KEYBOARD_DIR) && $(MASM) "$(AFLAGS) $(KB_AINC)" "$*.ASM,$*.OBJ;"

$(KEYBOARD_DIR)/KEYBOARD.EXE: $(KEYBOARD_OBJ_PATHS)
	cd $(KEYBOARD_DIR) && $(LINK) "@KEYBOARD.LNK"

$(KEYBOARD_DIR)/KEYBOARD.SYS: $(KEYBOARD_DIR)/KEYBOARD.EXE
	cd $(KEYBOARD_DIR) && $(EXE2BIN) "KEYBOARD.EXE KEYBOARD.SYS"
