        page    80,132
;******************* START OF SPECIFICATIONS ***********************************
;
; MODULE NAME:          SHARE.EXE     (a true EXE file)
;
; DESCRIPTIVE NAME:     SHARE resident service routines - part 1 - GSHARE.SAL
;                                                       - part 2 - GSHARE2.SAL
;                                                       - part 3 - SHARESR.SAL
;
; FUNCTION:             Provide file sharing services for DOS
;
; ENTRY POINT:          DOS Jump Table - installed by SHARE at initalization
;
;                             MFT_Enter          1
;                             MFTClose           2
;                             MFTClu             3
;                             MFTCloseP          4
;                             MFTCloN            5
;                             Set_Mult_Block     6
;                             Clr_Mult_Block     7
;                             Chk_Block          8
;                             MFT_Get            9
;
; INPUT:                See Prolog to individual entry points
;
; EXIT NORMAL:          CF = 0 and requested task performed.
;
; EXIT ERROR:           CF = 1 ans error code in AX
;
; INTERNAL REFERENCES:
;
;       ROUTINES:       Set_Block               BCS
;                       Clr_Block               CSL
;                       CLP                     CUC
;                       Load_Regs               CSI
;                       ASC                     GOM
;
;       DATA AREAS:
;
; EXTERNAL REFERENCES:  INT 21       INT 2F
;     together with:
;
;     fnm:near, rsc:near, rmn:near, cps:near, ofl:near, sle:near, interr:near
;
;       ROUTINES:
;
;       DATA AREAS:
;
; NOTES:                The second part of this utility is GSHARE2.ASM
;
