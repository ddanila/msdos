# ---------------------------------------------------------------------------
# MEMM (EMM386.SYS — expanded memory manager)
# Two sub-dirs: EMM/ (EMMLIB.LIB) and MEMM/ (EMM386.EXE → EMM386.SYS)
# ---------------------------------------------------------------------------
MEMM_ROOT := $(SRC)/MEMM
EMM_DIR   := $(MEMM_ROOT)/EMM
MEMM_DIR  := $(MEMM_ROOT)/MEMM

memm: $(MEMM_DIR)/EMM386.SYS

# ---------------------------------------------------------------------------
# EMM sub-module: EMMLIB.LIB
# AFLAGS: -DI386 -DNOHIMEM; include path = ..\MEMM (from EMM/ dir)
# ---------------------------------------------------------------------------
EMM_AFLAGS := -Mx -t -DI386 -DNOHIMEM -I..\\MEMM
EMM_CFLAGS := /ASw /G2 /Oat /Gs /Ze /Zl /c

$(EMM_DIR)/EMMFUNCT.OBJ: $(EMM_DIR)/EMMFUNCT.C
	cd $(EMM_DIR) && $(CL) "$(EMM_CFLAGS) -I. -FoEMMFUNCT.OBJ EMMFUNCT.C"

$(EMM_DIR)/EMM40.OBJ: $(EMM_DIR)/EMM40.C
	cd $(EMM_DIR) && $(CL) "$(EMM_CFLAGS) -I. -FoEMM40.OBJ EMM40.C"

$(EMM_DIR)/EMMP.OBJ: $(EMM_DIR)/EMMP.ASM
	cd $(EMM_DIR) && $(MASM) "$(EMM_AFLAGS)" "EMMP.ASM,EMMP.OBJ;"

$(EMM_DIR)/EMMSUP.OBJ: $(EMM_DIR)/EMMSUP.ASM
	cd $(EMM_DIR) && $(MASM) "$(EMM_AFLAGS)" "EMMSUP.ASM,EMMSUP.OBJ;"

$(EMM_DIR)/EMMDISP.OBJ: $(EMM_DIR)/EMMDISP.ASM
	cd $(EMM_DIR) && $(MASM) "$(EMM_AFLAGS)" "EMMDISP.ASM,EMMDISP.OBJ;"

$(EMM_DIR)/EMMDATA.OBJ: $(EMM_DIR)/EMMDATA.ASM
	cd $(EMM_DIR) && $(MASM) "$(EMM_AFLAGS)" "EMMDATA.ASM,EMMDATA.OBJ;"

$(EMM_DIR)/EMMINC.OBJ: $(EMM_DIR)/EMMINC.ASM
	cd $(EMM_DIR) && $(MASM) "$(EMM_AFLAGS)" "EMMINC.ASM,EMMINC.OBJ;"

$(EMM_DIR)/EMMLIB.LIB: \
    $(EMM_DIR)/EMMFUNCT.OBJ $(EMM_DIR)/EMM40.OBJ \
    $(EMM_DIR)/EMMP.OBJ $(EMM_DIR)/EMMSUP.OBJ \
    $(EMM_DIR)/EMMDISP.OBJ $(EMM_DIR)/EMMDATA.OBJ \
    $(EMM_DIR)/EMMINC.OBJ
	rm -f $(EMM_DIR)/EMMLIB.LIB
	cd $(EMM_DIR) && $(LIB) "EMMLIB+EMMFUNCT.OBJ+EMM40.OBJ+EMMP.OBJ+EMMSUP.OBJ+EMMDISP.OBJ+EMMDATA.OBJ,;"

# ---------------------------------------------------------------------------
# MEMM sub-module: EMM386.EXE → EMM386.SYS
# AFLAGS: -DI386 -DNoBugMode -DNOHIMEM; include = ..\EMM (from MEMM/ dir)
# ---------------------------------------------------------------------------
MEMM_AFLAGS := -Mx -t -DI386 -DNoBugMode -DNOHIMEM -I..\\EMM
MEMM_CFLAGS := /ASw /G2 /Oat /Gs /Ze /Zl /c

# Pattern rule for all ASM objects in MEMM/
$(MEMM_DIR)/%.OBJ: $(MEMM_DIR)/%.ASM
	cd $(MEMM_DIR) && $(MASM) "$(MEMM_AFLAGS)" "$*.ASM,$*.OBJ;"

# C object (MAPDMA.C needs emm.h from EMM/ dir)
$(MEMM_DIR)/MAPDMA.OBJ: $(MEMM_DIR)/MAPDMA.C
	cd $(MEMM_DIR) && $(CL) "$(MEMM_CFLAGS) -I..\\EMM -FoMAPDMA.OBJ MAPDMA.C"

MEMM_OBJS := \
    $(MEMM_DIR)/MEMM386.OBJ $(MEMM_DIR)/ELIMFUNC.OBJ \
    $(MEMM_DIR)/EMM.OBJ $(MEMM_DIR)/EMMMES.OBJ \
    $(MEMM_DIR)/EMMINIT.OBJ $(MEMM_DIR)/MEMMONF.OBJ \
    $(MEMM_DIR)/INIT.OBJ $(MEMM_DIR)/M_STATE.OBJ \
    $(MEMM_DIR)/ROM_SRCH.OBJ $(MEMM_DIR)/PPAGE.OBJ \
    $(MEMM_DIR)/ALLOCMEM.OBJ $(MEMM_DIR)/INITTAB.OBJ \
    $(MEMM_DIR)/SHIPHI.OBJ $(MEMM_DIR)/EXTPOOL.OBJ \
    $(MEMM_DIR)/VDMINIT.OBJ $(MEMM_DIR)/I286.OBJ \
    $(MEMM_DIR)/I386.OBJ $(MEMM_DIR)/TABDEF.OBJ \
    $(MEMM_DIR)/TRAPDEF.OBJ $(MEMM_DIR)/VMTRAP.OBJ \
    $(MEMM_DIR)/VMINST.OBJ $(MEMM_DIR)/ELIMTRAP.OBJ \
    $(MEMM_DIR)/IOTRAP.OBJ $(MEMM_DIR)/A20TRAP.OBJ \
    $(MEMM_DIR)/OEMPROC.OBJ $(MEMM_DIR)/INITEPG.OBJ \
    $(MEMM_DIR)/VMINIT.OBJ $(MEMM_DIR)/EM286LL.OBJ \
    $(MEMM_DIR)/EM386LL.OBJ $(MEMM_DIR)/MOVEB.OBJ \
    $(MEMM_DIR)/MAPLIN.OBJ $(MEMM_DIR)/RETREAL.OBJ \
    $(MEMM_DIR)/RRTRAP.OBJ $(MEMM_DIR)/ERRHNDLR.OBJ \
    $(MEMM_DIR)/EKBD.OBJ $(MEMM_DIR)/UTIL.OBJ \
    $(MEMM_DIR)/INITDEB.OBJ $(MEMM_DIR)/MAPDMA.OBJ

$(MEMM_DIR)/EMM386.EXE: $(MEMM_OBJS) $(EMM_DIR)/EMMLIB.LIB
	cd $(MEMM_DIR) && $(LINK) "/NOI @EMM386.LNK"

$(MEMM_DIR)/EMM386.SYS: $(MEMM_DIR)/EMM386.EXE
	mv $(MEMM_DIR)/EMM386.EXE $(MEMM_DIR)/EMM386.SYS
