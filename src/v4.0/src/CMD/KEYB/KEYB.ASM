
        PAGE    ,132
        TITLE   DOS - KEYB Command  -  Root Module

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DOS - NLS Support - KEYB Command
;; (c) Copyright 1988 Microsoft
;;
;; File Name:  KEYB.ASM
;; ----------
;;
;; Description:
;; ------------
;;       Contains root module for KEYB command.  This module is the
;;       KEYB command entry point.  KEYB is an external command included
;;       with PC DOS 3.3 to provide keyboard support for 14 languages.
;;       KEYB will jump immediately into the command processing in
;;       file KEYBCMD.  All resident code is included before KEYBCMD
;;       in the linkage list.
;;
;; Documentation Reference:
;; ------------------------
;;       PC DOS 3.3 NLS Interface Specification - May ?? 1986
;;       PC DOS 3.3 Detailed Design Document - May ?? 1986
;;
;; Procedures Contained in This File:
;; ----------------------------------
;;
;;
;; Include Files Required:
;; -----------------------
;;       KEYBCMD.INC - External declarations for transient command
;;           processing routines
;;
;; External Procedure References:
;; ------------------------------
;;       FROM FILE  KEYCMD.ASM:
;;            KEYB_COMMAND - Main routine for transient command processing.
;;
;; Linkage Instructions:
;; --------------------
;;       Link in .COM format.  Resident code/data is in files KEYB thru
;;       KEYBCPSD.
;;
;;       LINK KEYB+KEYBI9+KEYBI9C+KEYBI2F+KEYBI48+KEYBCPSD+KEYBMSG+
;;            COMMSUBS+KEYBTBBL+KEYBCMD;
;;       EXE2BIN KEYB.EXE KEYB.COM
;;
;; Change History:
;; ---------------
;;
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                                       ;;
                                       ;;
CODE    SEGMENT PUBLIC 'CODE' BYTE     ;;
                                       ;;
        INCLUDE KEYBCMD.INC            ;; Bring in external declarations
                                       ;;  for transient command processing
        ASSUME  CS:CODE,DS:CODE        ;;
        ORG   100H                     ;; required for .COM
                                       ;;
                                       ;;
START:                                 ;;
        MOV   SI, 081H                 ;; point to command-line args
KB_SKIP_SP:                            ;;
        CMP   BYTE PTR [SI], ' '       ;; skip leading spaces
        JNE   KB_CHK_SL               ;;
        INC   SI                       ;;
        JMP   SHORT KB_SKIP_SP         ;;
KB_CHK_SL:                             ;;
        CMP   BYTE PTR [SI], '/'       ;; check for /
        JNE   KB_NO_HELP               ;;
        CMP   BYTE PTR [SI+1], '?'     ;; check for ?
        JNE   KB_NO_HELP               ;;
        MOV   DX, OFFSET KB_HELP_STR   ;;
        MOV   AH, 09H                  ;;
        INT   21H                      ;;
        MOV   AX, 4C00H                ;;
        INT   21H                      ;;
KB_NO_HELP:                            ;;
        JMP   KEYB_COMMAND             ;;
KB_HELP_STR DB "KEYB [xx[,[yyy][,[drive:][path]filename]]] [/E] [/ID:nnn]",0Dh,0Ah
            DB 0Dh,0Ah
            DB "  xx        Two-letter keyboard code",0Dh,0Ah
            DB "  yyy       Code page",0Dh,0Ah
            DB "  filename  Keyboard definition file",0Dh,0Ah
            DB "  /E        Enhanced keyboard",0Dh,0Ah
            DB "  /ID:nnn   Keyboard ID number",0Dh,0Ah,"$"
                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CODE   ENDS
       END    START
