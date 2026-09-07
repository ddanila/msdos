	PAGE	,132
	TITLE	DOS - GRAPHICS Command  -	Profile Load Modules #2
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRLOAD.ASM
;; ----------
;; Description:
;; ------------
;;   This file contains the modules used to load the
;;   GRAPHICS profile into resident memory.
;;   ************* The EGA Dynamic Save Area will be built (by
;;   **  NOTE	** CHAIN_INTERRUPTS in file GRINST.ASM) over top of these
;;   ************* modules to avoid having to relocate this save just before
;;   terminating.  This is safe since the maximum memory used is
;;   288 bytes and the profile loading modules are MUCH larger than
;;   this.  So GRLOAD.ASM MUST be linked before GRINST.ASM and after
;;   GRPRINT.ASM.
;; Documentation Reference:
;; ------------------------
;;	 PLACID Functional Specifications
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 LOAD_PROFILE - Main module for profile loading
;; Include Files Required:
;; -----------------------
;;	 ?????????? - Externals for profile loading modules
;; External Procedure References:
;; ------------------------------
;;	 None
;; Linkage Instructions:
;; ---------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE' BYTE     ;;
	INCLUDE STRUC.INC	       ;;
	INCLUDE GRINST.EXT	       ;; Bring in external declarations
				       ;;  for transient command processing
	INCLUDE GRSHAR.STR	       ;;
	INCLUDE GRMSG.EQU	       ;;
	INCLUDE GRINST.EXT	       ;;
	INCLUDE GRLOAD.EXT	       ;;
	INCLUDE GRPARSE.EXT	       ;;
	INCLUDE GRPATTRN.STR	       ;;
	INCLUDE GRPATTRN.EXT	       ;;
;; Public Symbols
   PUBLIC PARSE_VERB		       ;;
   PUBLIC PARSE_PRINTER 	       ;;
   PUBLIC PARSE_DISPLAYMODE	       ;;
   PUBLIC PARSE_PRINTBOX	       ;;
   PUBLIC PARSE_SETUP		       ;;
   PUBLIC PARSE_RESTORE 	       ;;
   PUBLIC TERMINATE_DISPLAYMODE        ;;
   PUBLIC TERMINATE_PRINTER	       ;;
   PUBLIC CUR_PRINTER_TYPE	       ;;
	ASSUME	CS:CODE,DS:CODE        ;;
;; Profile Load Variables
NO	      EQU   0		       ;;
YES	      EQU   1		       ;;
RESULT_BUFFER	LABEL BYTE	       ;; general purpose result buffer
		    DB	 ?	       ;; operand type
RESULT_TAG	    DB	 0	       ;; operand tag
		    DW	 ?	       ;; pointer to synonym/keyword
RESULT_VAL	    DB	 ?,?,?,?       ;; returned numeric value
;; Module Name:
;;   TERMINATE_DISPLAYMODE
TERMINATE_DISPLAYMODE	PROC	       ;;
  MOV  AX,STMTS_DONE		       ;;
 .IF <PTD_FOUND EQ YES> AND	       ;; For the matched PTD
 .IF <BIT AX NAND BOX> AND	       ;;  issue "Invalid parm value"
 .IF <PRT_BOX_ERROR EQ NO>	       ;;  message if PRINTBOX ID not
				       ;;  matched in each DISPLAYMODE section
	 PUSH AX		       ;; Save STMT_DONE flags
	 MOV  AX,INVALID_PB	       ;;
	 MOV  CX,0		       ;;
	 CALL DISP_ERROR	       ;;
	 MOV  BUILD_STATE,NO	       ;;
	 MOV  PRT_BOX_ERROR,YES        ;; Issue this message only once
	 POP  AX		       ;;
 .ENDIF 			       ;;
  AND  AX,GR			       ;; Check for missing statements is last
 .IF <AX NE GR> 		       ;;  DISPLAYMODE section:
     OR  STMT_ERROR,MISSING	       ;;    GRAPHICS stmt is required
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  RET				       ;;
TERMINATE_DISPLAYMODE	ENDP	       ;;
;; Module Name:
;;   TERMINATE_PRINTER
TERMINATE_PRINTER	PROC	       ;;
  MOV  AX,BLOCK_END		       ;;
 .IF <AX A MAX_BLOCK_END>	       ;; Keep track of the largest PRINTER
    MOV  MAX_BLOCK_END,AX	       ;;  section so we can allow space for
 .ENDIF 			       ;;  reload with a different printer
				       ;;  type.
				       ;; Check for missing statements
  MOV  AX,STMTS_DONE		       ;;
  AND  AX,DISP			       ;; At least one DISPLAYMODE
 .IF <AX NE DISP>		       ;;  must have been found in last
     OR  STMT_ERROR,MISSING	       ;;   PRINTER section
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  RET				       ;;
TERMINATE_PRINTER	ENDP	       ;;
;; Module Name:
;;   PARSE_PRINTER
PRINTER_PARSE_PARMS  LABEL WORD        ;; Parser control blocks
	    DW	 PRINTER_P	       ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
PRINTER_P   DB	 0,1		       ;; Required, max parms
	    DW	 PRINTER_P1	       ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
PRINTER_P1  DW	 2000H		       ;; simple string
	    DW	 0002H		       ;; Capitalize using character table
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 PRINTER_P1V	       ;; Value list
	    DB	 0		       ;; Synomyms
PRINTER_P1V    DB   3		       ;; # of value lists
	    DB	 0		       ;; # of range numerics
	    DB	 0		       ;; # of discrete numerics
	    DB	 1		       ;; # of strings
	    DB	 1		       ;; tag: index into verb jump table
PRINTER_P1V1  DW   ?		       ;; string offset
CUR_PRINTER_TYPE   DB  0	       ;; Type of printer currently being
				       ;;  parsed:  1-color 2-b&w
PARSE_PRINTER  PROC		       ;;
  MOV  CUR_STMT,PRT		       ;;
  MOV  CUR_PRINTER_TYPE,BLACK_WHITE    ;; Assume black & white until we hit
				       ;;  a COLORPRINT
 .IF <BIT STMTS_DONE AND PRT>	       ;; If not the first PRINTER section
     CALL  TERMINATE_DISPLAYMODE       ;;  then clean up the last one and
     CALL  TERMINATE_PRINTER	       ;;    the last DISPLAYMODE section.
 .ENDIF 			       ;;
 MOV  AX,FIRST_BLOCK		       ;;
 MOV  BLOCK_START,AX		       ;; Reset block pointers to start
 MOV  BLOCK_END,AX		       ;;  of variable area
  MOV  STMTS_DONE,PRT		       ;; Clear all bits except for PRT
  MOV  GROUPS_DONE,0		       ;; Clear
 .IF <PTD_FOUND EQ YES> 	       ;; PRINTER statement marks the end of
     MOV  PTD_FOUND,PROCESSED	       ;;  the previous PTD
     MOV  BUILD_STATE,NO	       ;; Stop building shared data
 .ENDIF 			       ;;
  MOV  CL,TAB_DIR_NB_ENTRIES	       ;; Reset the pattern table copy
  XOR  CH,CH			       ;;  pointers.  These pointers
  MOV  BX,OFFSET TAB_DIRECTORY	       ;;   are established when a pattern
 .REPEAT			       ;;    table is copied to the shared
    MOV [BX].TAB_COPY,-1	       ;;     data area.  Initially they
    ADD BX,SIZE TAB_ENTRY	       ;;      are -1.
 .LOOP				       ;;
  MOV  AX,OFFSET PRINTER_TYPE_PARM     ;; Store printer type from command
  MOV  PRINTER_P1V1,AX		       ;;  line in value list
  MOV  DI,OFFSET PRINTER_PARSE_PARMS   ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
 .REPEAT			       ;;
     XOR  CX,CX 		       ;; Don't worry about number of operands
     CALL SYSPARSE		       ;;
    .IF <AX EQ 9>		       ;; Syntax error is the only thing
	OR  STMT_ERROR,INVALID	       ;;  which can go wrong
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
    .ENDIF			       ;;
 .UNTIL <AX EQ 0> OR		       ;;
 .UNTIL <AX EQ -1>		       ;;
				       ;; Printer type parm matched one coded
				       ;;  on the PRINTER statement
 .IF <AX EQ 0>			       ;;
    .IF <PTD_FOUND EQ NO>	       ;;
	MOV  PTD_FOUND,YES	       ;; If the printer type matches and
       .IF <PARSE_ERROR EQ NO> AND     ;;  no errors have been found yet
       .IF <PRT_BOX_ERROR EQ NO> AND   ;;
       .IF <MEM_OVERFLOW EQ NO>        ;;
	   MOV BUILD_STATE,YES	       ;;   then start building the shared
       .ENDIF			       ;;    data
    .ENDIF			       ;;
 .ELSE				       ;; No match
    MOV  BUILD_STATE,NO 	       ;;
   .IF <AX NE -1>		       ;; Error during parse
      OR  STMT_ERROR,INVALID	       ;; set error flag for caller
      MOV PARSE_ERROR,YES	       ;; set error flag for caller
   .ENDIF			       ;;
 .ENDIF 			       ;;
  RET
PARSE_PRINTER  ENDP
;; Module Name:
;;   PARSE_DISPLAYMODE
DISPMODE_PARSE_PARMS  LABEL WORD       ;; Parser control blocks
	    DW	 DISPMODE_P	       ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
DISPMODE_P   DB   0,1		       ;; Required, max parms
	    DW	 DISPMODE_P1	       ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
DISPMODE_P1  DW   8000H 	       ;; Numeric
	    DW	 0		       ;; No Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 DISPMODE_P1V	       ;; Value list
	    DB	 0		       ;; Synomyms
DISPMODE_P1V	DB   1			;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 0,19		       ;; range 0..19
PARSE_DISPLAYMODE  PROC 	       ;;
  MOV  CUR_STMT,DISP		       ;;
				       ;; Check for a preceeding PRINTER
 .IF <BIT STMTS_DONE NAND PRT>	       ;;
     OR  STMT_ERROR,MISSING	       ;;
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE NAND DISP>        ;; If first DISPLAYMODE...
     .IF <BUILD_STATE EQ YES>	       ;;
	 MOV  AX,BLOCK_END	       ;;
	 MOV  [BP].DISPLAYMODE_PTR,AX  ;; Set pointer to first DISPLAYMODE
	 MOV  BLOCK_START,AX	       ;; New block starts after last one
     .ENDIF			       ;;
 .ELSE				       ;;
     CALL TERMINATE_DISPLAYMODE        ;; If not the first DISPLAYMODE then
				       ;;  clean up the last one.
     MOV  DI,BLOCK_START	       ;; DI=pointer to DISPLAYMODE block just
     MOV  AX,BLOCK_END		       ;;  built
    .IF <BUILD_STATE EQ YES>	       ;;
	MOV  [BP+DI].NEXT_DISP_MODE,AX ;; Add new block to DISPLAYMODE chain
    .ENDIF			       ;;
     MOV  BLOCK_START,AX	       ;; New block starts after last one
 .ENDIF 			       ;;
  MOV  AX,SIZE DISPLAYMODE_STR	       ;; Allocate space for new DISPLAYMODE
  CALL	GROW_SHARED_DATA	       ;;  block
 .IF <BUILD_STATE EQ YES>	       ;;
     MOV  DI,BLOCK_START	       ;; Start of new block
     MOV  [BP+DI].NUM_SETUP_ESC,0	  ;; SETUP, RESTORE are optional so set
     MOV  [BP+DI].NUM_RESTORE_ESC,0	  ;;  to defaults
     MOV  [BP+DI].SETUP_ESC_PTR,-1	  ;;
     MOV  [BP+DI].RESTORE_ESC_PTR,-1	  ;;
     MOV  [BP+DI].BOX_WIDTH,0		  ;;
     MOV  [BP+DI].BOX_HEIGHT,0		  ;;
     MOV  [BP+DI].PRINT_OPTIONS,0	  ;; Default to NO print options
     MOV  [BP+DI].NUM_DISP_MODE,0      ;; Get ready to INC this sucker
     MOV  [BP+DI].NEXT_DISP_MODE,-1    ;; This is the last DISPLAYMODE for now!
     MOV  AX,BLOCK_END		       ;;
     MOV  [BP+DI].DISP_MODE_LIST_PTR,AX;; Start mode list at end of new block
 .ENDIF 			       ;;
  OR   STMTS_DONE,DISP		       ;; Indicate DISPLAYMODE found
  AND  STMTS_DONE,NOT (BOX+GR+SET+REST) ;; Reset flags for PRINTBOX, GRAPHICS
				       ;;  stmts found
  AND  GROUPS_DONE,NOT (GR+SET+REST)   ;; Reset flags for GRAPHICS, SETUP,
				       ;;  RESTORE groups processed
  MOV  DI,OFFSET DISPMODE_PARSE_PARMS  ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
 .REPEAT			       ;;
    XOR  CX,CX			       ;;
    CALL SYSPARSE		       ;;
   .IF <AX EQ 0>		       ;; If mode is valid
	  PUSH AX		       ;;
	  MOV	AX,1		       ;; Add a mode to the list
	  CALL	GROW_SHARED_DATA       ;; Update block end
	 .IF <BUILD_STATE EQ YES>      ;;
	     PUSH DI		       ;;
	     MOV  DI,BLOCK_START       ;;
	     INC  [BP+DI].NUM_DISP_MODE   ;; Bump number of modes in list
	     MOV  DI,BLOCK_END	       ;;
	     MOV  AL,RESULT_VAL   ;; Get mode from result buffer
	     MOV  [BP+DI-1],AL	       ;; Store the mode at end of list
	     POP  DI		       ;;
	 .ENDIF 		       ;;
	  POP  AX		       ;;
   .ELSE			       ;;
      .IF <AX NE -1>		       ;;
	  OR   STMT_ERROR,INVALID	  ;; Mode is invalid
	  MOV  PARSE_ERROR,YES		  ;;
	  MOV  BUILD_STATE,NO		  ;;
      .ENDIF				  ;;
   .ENDIF			       ;;
 .UNTIL <AX EQ -1>		       ;;
  RET
PARSE_DISPLAYMODE  ENDP
;; Module Name:
;;   PARSE_SETUP
SETUP_PARSE_PARMS  LABEL WORD	     ;; Parser control blocks
	    DW	 SETUP_P	     ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
SETUP_P   DB   0,1		    ;; Required, max parms
	    DW	 SETUP_P1	    ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
SETUP_P1 DW   08000H		    ;; Numeric
	    DW	 0		       ;; nO Capitalize
	    DW	 RESULT_BUFFER	    ;; Result buffer
	    DW	 SETUP_P1V	    ;; Value list
	    DB	 0		       ;; Synomyms
SETUP_P1V    DB   1		    ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 0,255		       ;; range 0..255
PARSE_SETUP  PROC		       ;;
  MOV  CUR_STMT,SET		       ;;
 .IF <BIT STMTS_DONE NAND DISP>        ;; DISPLAYMODE must preceed this
     OR  STMT_ERROR,MISSING	       ;;
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT GROUPS_DONE AND SET>	       ;; Check for previous group of SETUP
     OR  STMT_ERROR,SEQUENCE	       ;;  stmts
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE NAND SET>	       ;; If first SETUP...
     .IF <BUILD_STATE EQ YES>	       ;;
	 MOV  DI,BLOCK_START	       ;;
	 MOV  AX,BLOCK_END	       ;;
	 MOV  [BP+DI].SETUP_ESC_PTR,AX ;; Set pointer to SETUP seq
	 MOV  [BP+DI].NUM_SETUP_ESC,0  ;; Init sequence size
     .ENDIF			       ;;
 .ENDIF 			       ;;
  OR   STMTS_DONE,SET		       ;; Indicate SETUP found
 .IF <PREV_STMT NE SET> THEN	       ;; Terminate any preceeding groups
     MOV  AX,PREV_STMT		       ;;  except for SETUP group
     OR   GROUPS_DONE,AX	       ;;
 .ENDIF 			       ;;
  MOV  DI,OFFSET SETUP_PARSE_PARMS     ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
 .REPEAT			       ;;
    XOR  CX,CX			       ;;
    CALL SYSPARSE		       ;;
   .IF <AX EQ 0>		       ;; If esc byte is valid
	  PUSH AX		       ;;
	  MOV	AX,1		       ;; Add a byte to the sequence
	  CALL	GROW_SHARED_DATA       ;; Update block end
	 .IF <BUILD_STATE EQ YES>      ;;
	     PUSH DI		       ;;
	     MOV  DI,BLOCK_START       ;;
	     INC  [BP+DI].NUM_SETUP_ESC   ;; Bump number of bytes in sequence
	     MOV  DI,BLOCK_END	       ;;
	     MOV  AL,RESULT_VAL  ;; Get esc byte from result buffer
	     MOV  [BP+DI-1],AL	       ;; Store at end of sequence
	     POP  DI		       ;;
	 .ENDIF 		       ;;
	  POP  AX		       ;;
   .ELSE			       ;;
      .IF <AX NE -1>		       ;;
	  OR   STMT_ERROR,INVALID      ;; parm is invalid
	  MOV  PARSE_ERROR,YES	       ;;
	  MOV  BUILD_STATE,NO	       ;;
      .ENDIF			       ;;
   .ENDIF			       ;;
 .UNTIL <AX EQ -1> NEAR 	       ;;
  RET				       ;;
PARSE_SETUP  ENDP		    ;;
;; Module Name:
;;   PARSE_RESTORE
RESTORE_PARSE_PARMS  LABEL WORD        ;; Parser control blocks
	    DW	 RESTORE_P	       ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
RESTORE_P   DB	 0,1		      ;; Required, max parms
	    DW	 RESTORE_P1	      ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
RESTORE_P1 DW	08000H		      ;; Numeric
	    DW	 0		       ;; nO Capitalize
	    DW	 RESULT_BUFFER	    ;; Result buffer
	    DW	 RESTORE_P1V	      ;; Value list
	    DB	 0		       ;; Synomyms
RESTORE_P1V    DB   1		      ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 0,255		       ;; range 0..255
PARSE_RESTORE  PROC			 ;;
  MOV  CUR_STMT,SET		       ;;
 .IF <BIT STMTS_DONE NAND DISP>        ;; DISPLAYMODE must preceed this
     OR  STMT_ERROR,MISSING	       ;;
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT GROUPS_DONE AND REST>        ;; Check for previous group of RESTORE
     OR  STMT_ERROR,SEQUENCE	       ;;  stmts
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE NAND REST>        ;; If first RESTORE...
     .IF <BUILD_STATE EQ YES>	       ;;
	 MOV  DI,BLOCK_START	       ;;
	 MOV  AX,BLOCK_END	       ;;
	 MOV  [BP+DI].RESTORE_ESC_PTR,AX ;; Set pointer to RESTORE seq
	 MOV  [BP+DI].NUM_RESTORE_ESC,0  ;; Init sequence size
     .ENDIF			       ;;
 .ENDIF 			       ;;
  OR   STMTS_DONE,REST		       ;; Indicate RESTORE found
 .IF <PREV_STMT NE REST> THEN		;; Terminate any preceeding groups
     MOV  AX,PREV_STMT		       ;;  except for RESTORE group
     OR   GROUPS_DONE,AX	       ;;
 .ENDIF 			       ;;
  MOV  DI,OFFSET RESTORE_PARSE_PARMS	 ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
 .REPEAT			       ;;
    XOR  CX,CX			       ;;
    CALL SYSPARSE		       ;;
   .IF <AX EQ 0>		       ;; If esc byte is valid
	  PUSH AX		       ;;
	  MOV	AX,1		       ;; Add a byte to the sequence
	  CALL	GROW_SHARED_DATA       ;; Update block end
	 .IF <BUILD_STATE EQ YES>      ;;
	     PUSH DI		       ;;
	     MOV  DI,BLOCK_START       ;;
	     INC  [BP+DI].NUM_RESTORE_ESC   ;; Bump number of bytes in sequence
	     MOV  DI,BLOCK_END	       ;;
	     MOV  AL,RESULT_VAL  ;; Get esc byte from result buffer
	     MOV  [BP+DI-1],AL	       ;; Store at end of sequence
	     POP  DI		       ;;
	 .ENDIF 		       ;;
	  POP  AX		       ;;
   .ELSE			       ;;
      .IF <AX NE -1>		       ;;
	  OR   STMT_ERROR,INVALID      ;; parm is invalid
	  MOV  PARSE_ERROR,YES	       ;;
	  MOV  BUILD_STATE,NO	       ;;
      .ENDIF			       ;;
   .ENDIF			       ;;
 .UNTIL <AX EQ -1> NEAR 	       ;;
  RET				       ;;
PARSE_RESTORE  ENDP		      ;;
;; Module Name:
;;   PARSE_PRINTBOX
PRINTBOX_PARSE_PARMS  LABEL WORD	;; Parser control blocks
	    DW	 PRINTBOX_P		;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
PRINTBOX_P  DB	 1,4		       ;; Required, max parms
	    DW	 PRINTBOX_P0	       ;; LCD/STD
	    DW	 PRINTBOX_P1	       ;; width
	    DW	 PRINTBOX_P1	       ;; height
	    DW	 PRINTBOX_P2	       ;; rotate
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
PRINTBOX_P0  DW   2000H 	       ;; sTRING - display type
	    DW	 2		       ;; Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 PRINTBOX_P0V	       ;; Value list
	    DB	 0		       ;; Synomyms
PRINTBOX_P0V	DB   3			;; # of value lists
	    DB	 0		       ;; # of range numerics
	    DB	 0		       ;; # of discrete numerics
	    DB	 1		       ;; # of strings
	    DB	 1		       ;; tag
PRINTBOX_P0V1 DW   ?		       ;; string
PRINTBOX_P1  DW   8001H 	       ;; Numeric - BOX DIMENSIONS
	    DW	 0		       ;; No Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 PRINTBOX_P1V	       ;; Value list
	    DB	 0		       ;; Synomyms
PRINTBOX_P1V	DB   1		       ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 1,9		       ;; range 1..9
PRINTBOX_P2  DW   2001H 	       ;; sTRING - ROTATE PARM
	    DW	 2		       ;; Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 PRINTBOX_P2V	       ;; Value list
	    DB	 0		       ;; Synomyms
PRINTBOX_P2V	DB   3			;; # of value lists
	    DB	 0		       ;; # of range numerics
	    DB	 0		       ;; # of discrete numerics
	    DB	 1		       ;; # of strings
	    DB	 1		       ;; tag
	    DW	 ROTATE_STR	       ;; string
ROTATE_STR  DB	 'ROTATE',0            ;;
PROF_BOX_W  DB	0		       ;; Box width and height extracted from
PROF_BOX_H  DB	0		       ;;  the profile
PRINTBOX_MATCH	     DB  0	       ;;
PARSE_PRINTBOX	PROC		       ;;
  MOV  PRINTBOX_MATCH,NO	       ;; Start out assuming the PRINTBOX ID
  MOV  PROF_BOX_W,0		       ;;  does not match the one requested
  MOV  PROF_BOX_H,0		       ;;
  MOV  CUR_STMT,BOX		       ;;
 .IF <BIT STMTS_DONE NAND DISP>        ;; DISPLAYMODE must preceed PRINTBOX
     OR  STMT_ERROR,MISSING	       ;;
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
				       ;; Multiple PRINTBOX stmts may be coded
				       ;;  We must decide if this one
				       ;;   matches the requested display type
				       ;;    If not, ignore the statement
  MOV  DI,OFFSET PRINTBOX_PARSE_PARMS  ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
  XOR  CX,CX			       ;;
  MOV  AX,PRINTBOX_ID_PTR	       ;; Insert requested display type in
  MOV  PRINTBOX_P0V1,AX 	       ;;  parser value list
  CALL SYSPARSE 		       ;; PARSE display type
 .IF <AX EQ 0>			       ;; If ID matches then set this flag.
     MOV  PRINTBOX_MATCH,YES	       ;;
     OR   STMTS_DONE,BOX	       ;; Indicate PRINTBOX found
     MOV  AX,PREV_STMT		       ;; Terminate any preceeding groups
     OR   GROUPS_DONE,AX	       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; PARSE horizontal dimension
 .IF <AX EQ 0>			       ;;
     MOV  BL,RESULT_VAL 	       ;;
     MOV  PROF_BOX_W,BL 	       ;; Save in local var
 .ELSE				       ;;
    .IF <AX EQ -1>		       ;;
	JMP  PRINTBOX_DONE	       ;;
    .ELSE			       ;;
	OR  STMT_ERROR,INVALID	       ;;
	MOV PARSE_ERROR,YES	       ;;
	MOV BUILD_STATE,NO	       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; PARSE vertical dimension
 .IF <AX EQ 0>			       ;;
     MOV  BL,RESULT_VAL 	       ;;
     MOV  PROF_BOX_H,BL 	       ;; Save in local var
 .ELSE				       ;;
    .IF <AX EQ -1>		       ;;
	JMP  PRINTBOX_DONE	       ;;
    .ELSE			       ;;
	OR  STMT_ERROR,INVALID	       ;;
	MOV PARSE_ERROR,YES	       ;;
	MOV BUILD_STATE,NO	       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; Parse ROTATE parm
 .IF <AX EQ 0>			       ;;
    .IF <BUILD_STATE EQ YES> AND       ;;
    .IF <PRINTBOX_MATCH EQ YES>        ;;
	PUSH DI 		       ;;
	MOV  DI,BLOCK_START	       ;;
	OR   [BP+DI].PRINT_OPTIONS,ROTATE ;;
	POP  DI 		       ;;
    .ENDIF			       ;;
 .ELSE				       ;;
    .IF <AX EQ -1>		       ;;
	JMP  PRINTBOX_DONE	       ;;
    .ELSE			       ;;
	OR  STMT_ERROR,INVALID	       ;;
	MOV PARSE_ERROR,YES	       ;;
	MOV BUILD_STATE,NO	       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; CHECK FOR EXTRA PARMS
 .IF <AX NE -1> 		    ;;
    OR	STMT_ERROR,INVALID	   ;;
    MOV PARSE_ERROR,YES 	   ;;
    MOV BUILD_STATE,NO		   ;;
 .ENDIF 			       ;;
PRINTBOX_DONE:			       ;;
 .IF <BUILD_STATE EQ YES> AND	    ;; Store the PRINTBOX dimensions
 .IF <PRINTBOX_MATCH EQ YES>	    ;;
     PUSH DI			    ;;	in the DISPLAYMODE block
     MOV  DI,BLOCK_START	    ;;
     MOV  AL,PROF_BOX_W 	    ;;
     MOV  [BP+DI].BOX_WIDTH,AL	    ;;
     MOV  AL,PROF_BOX_H 	    ;;
     MOV  [BP+DI].BOX_HEIGHT,AL     ;;
     POP  DI			    ;;
 .ENDIF 			    ;;
				       ;; If we have a B&W printer then
				       ;;   load the grey patterns for the
				       ;;    requested print box size.
 .IF <CUR_PRINTER_TYPE EQ BLACK_WHITE> NEAR
    .IF <PROF_BOX_W NE 0> AND NEAR	  ;; Dimensions could also be 0 if the
    .IF <PROF_BOX_H NE 0> NEAR		  ;;  printbox ID does not apply to this
					  ;;   displaymode, so don't try for
					  ;;	a pattern!
	MOV  BX,OFFSET TAB_DIRECTORY	  ;;
	MOV  CL,TAB_DIR_NB_ENTRIES	  ;;
	XOR  CH,CH			  ;;
	MOV  DI,BLOCK_START		  ;;
	MOV  AL,PROF_BOX_W		  ;; Requested box width
	MOV  AH,PROF_BOX_H		  ;; Requested box height
       .REPEAT				  ;;
	  .IF <[BX].BOX_W_PAT EQ AL> AND  ;;
	  .IF <[BX].BOX_H_PAT EQ AH>	  ;;
	     .LEAVE			  ;;
	  .ELSE 			  ;;
	      ADD  BX,SIZE TAB_ENTRY	  ;;
	  .ENDIF			  ;;
       .LOOP				  ;;
       .IF <ZERO CX>			  ;;
	   OR  STMT_ERROR,INVALID	  ;; Unsupported box size
	   MOV PARSE_ERROR,YES		  ;;
	   MOV BUILD_STATE,NO		  ;;
       .ELSE NEAR			  ;; Box size OK - pattern tab found
	  .IF <[BX].TAB_COPY NE -1>	  ;; Pointer is NOT null if the table
	      MOV  AX,[BX].TAB_COPY	  ;;  has already been copied to
					  ;;   the shared data area.
	     .IF <BUILD_STATE EQ YES> AND ;;	Point to the copy.
	     .IF <PRINTBOX_MATCH EQ YES>  ;; Establish pointer to table ONLY
		 MOV  [BP+DI].PATTERN_TAB_PTR,AX ;; if the PB ID matched.
		 MOV  AL,[BX].NB_INT	  ;; Number of table entries (intensitie
		 MOV  [BP+DI].NUM_PATTERNS,AL ;;
	     .ENDIF			  ;;
	  .ELSE 			  ;; Otherwise we have to copy it.
	   ;; Copy the table even if the printbox ID didn't match!
	   ;; This is a simple way to reserve enough space to allow reloading
	   ;; with a different PRINTBOX ID specified on the command line.
	   ;; This scheme avoids storing
	   ;; duplicate tables but may reserve slightly more space
	   ;; (probably only a hundred bytes or so) than
	   ;; could ever be required.  The optimal solution (too
	   ;; complicated!) would involve keeping running totals for each
	   ;; PRINTBOX ID coded.
	      MOV  DI,BLOCK_END 	  ;; Copy it onto the end of the
					  ;;  current block
	      MOV  DX,DI		  ;; Save start addr of the copy
	      MOV  [BX].TAB_COPY,DX	  ;; Store ptr to copy in the directory
	      MOV  AX,[BX].TAB_SIZE	  ;;
	      CALL GROW_SHARED_DATA	  ;; Allocate room for the table
	     .IF <BUILD_STATE EQ YES>	  ;;
		 MOV  CX,AX		  ;; Number of bytes to copy
		 PUSH SI		  ;; Save parse pointer
		 MOV  SI,[BX].TAB_OFFSET  ;; Source pointer
		 ADD  DI,BP		  ;; make DI an absolute pointer (dest)
		 REP  MOVSB		  ;; Move it!
		 POP  SI		  ;;
		.IF <PRINTBOX_MATCH EQ YES>  ;; Establish pointer to table ONLY
		    MOV  DI,BLOCK_START      ;; Establish pointer in DISPLAYMODE
		    MOV  [BP+DI].PATTERN_TAB_PTR,DX  ;;  info
		    MOV  AL,[BX].NB_INT      ;; Number of table entries (intens)
		    MOV  [BP+DI].NUM_PATTERNS,AL ;;
		.ENDIF			     ;;
	     .ENDIF			  ;;
	  .ENDIF			   ;;
       .ENDIF			       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
  RET				       ;;
PARSE_PRINTBOX	ENDP
;; Module Name:
;;   PARSE_VERB
VERB_PARSE_PARMS  LABEL WORD	       ;; Parser control blocks to parse verb
	    DW	 VERB_P 	       ;; Parser control blocks to parse verb
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
VERB_P	    DB	 0,1		       ;; Required, max parms
	    DW	 VERB_P1	       ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
VERB_P1     DW	 2000H		       ;; simple string
	    DW	 0002H		       ;; Capitalize using character table
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 VERB_P1V	       ;; Value list
	    DB	 0		       ;; Synomyms
VERB_P1V    DB	 3			  ;; # of value lists
	    DB	 0			  ;; # of range numerics
	    DB	 0			  ;; # of discrete numerics
	    DB	 9			  ;; # of strings
	    DB	 0			  ;; tag: index into verb jump table
	    DW	 PRINTER_STRING 	  ;; string offset
	    DB	 2			  ;; tag
	    DW	 DISPLAYMODE_STRING	  ;; string offset
	    DB	 4			  ;; tag
	    DW	 PRINTBOX_STRING	  ;; string offset
	    DB	 6			  ;; tag
	    DW	 SETUP_STRING		  ;; string offset
	    DB	 8			  ;; tag
	    DW	 RESTORE_STRING 	  ;; string offset
	    DB	 10			  ;; tag
	    DW	 GRAPHICS_STRING	  ;; string offset
	    DB	 12			  ;; tag
	    DW	 COLORPRINT_STRING	  ;; string offset
	    DB	 14			  ;; tag
	    DW	 COLORSELECT_STRING	  ;; string offset
	    DB	 16			  ;; tag
	    DW	 DARKADJUST_STRING	  ;; string offset
PRINTER_STRING	    DB 'PRINTER',0        ;;
DISPLAYMODE_STRING  DB 'DISPLAYMODE',0    ;;
PRINTBOX_STRING     DB 'PRINTBOX',0       ;;
SETUP_STRING	    DB 'SETUP',0          ;;
RESTORE_STRING	    DB 'RESTORE',0        ;;
GRAPHICS_STRING     DB 'GRAPHICS',0       ;;
COLORPRINT_STRING   DB 'COLORPRINT',0     ;;
COLORSELECT_STRING  DB 'COLORSELECT',0    ;;
DARKADJUST_STRING   DB 'DARKADJUST',0     ;;
PARSE_VERB     PROC		       ;;
  MOV  DI,OFFSET VERB_PARSE_PARMS      ;; parse parms
  MOV  SI,OFFSET STMT_BUFFER	       ;; the line to parse
  XOR  DX,DX			       ;;
  XOR  CX,CX			       ;;
  CALL SYSPARSE 		       ;;
 .IF <AX EQ 0>			       ;;
    MOV  BL,RESULT_TAG		       ;;
    XOR  BH,BH			       ;; return tag in BX
 .ELSE				       ;;
   .IF <AX NE -1>		       ;; syntax error
      OR  STMT_ERROR,INVALID	       ;; set error flag for caller
   .ENDIF			       ;;
 .ENDIF 			       ;;
  RET
PARSE_VERB     ENDP
LIMIT	LABEL NEAR		       ;;
CODE	ENDS			       ;;
	END
