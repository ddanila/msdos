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
	INCLUDE GRLOAD2.EXT	       ;;
	INCLUDE GRPARSE.EXT	       ;;
	INCLUDE GRPATTRN.STR	       ;;
	INCLUDE GRPATTRN.EXT	       ;;
;; Public Symbols
   PUBLIC PARSE_GRAPHICS	       ;;
   PUBLIC PARSE_COLORSELECT	       ;;
   PUBLIC PARSE_COLORPRINT	       ;;
   PUBLIC PARSE_DARKADJUST	       ;;
   PUBLIC LIMIT 		       ;;
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
;;   PARSE_GRAPHICS
GRAPHICS_PARSE_PARMS  LABEL WORD       ;; Parser control blocks
	    DW	 GRAPHICS_P	       ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
GRAPHICS_P   DB   0,1		       ;; Required, max parms
	    DW	 GRAPHICS_P1	       ;;
	    DB	 0		       ;; # Switches
	    DB	 0		       ;; # keywords
GRAPHICS_P1 DW	 0A000H 	       ;; Numeric OR string
	    DW	 2		       ;; Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 GRAPHICS_P1V	       ;; Value list
	    DB	 0		       ;; Synomyms
GRAPHICS_P1V	DB   3		       ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 0,255		       ;; range 0..255
	    DB	 0		       ;; 0 - no actual numerics
	    DB	 2		       ;; 2 STRING VALUES
	    DB	 2		       ;; tag
	    DW	 LOWCOUNT_STR	       ;; ptr
	    DB	 3		       ;; tag
	    DW	 HIGHCOUNT_STR	       ;; ptr
lowcount_str  db  'LOWCOUNT',0         ;;
HIGHcount_str  db  'HIGHCOUNT',0       ;;
LOWCOUNT_FOUND	 DB  NO 	       ;;
HIGHCOUNT_FOUND  DB  NO 	       ;;
PARSE_GRAPHICS	PROC		       ;;
  MOV  CUR_STMT,GR		       ;;
 .IF <BIT STMTS_DONE NAND DISP>        ;;
     OR  STMT_ERROR,MISSING	       ;;
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BUILD_STATE EQ YES>	       ;;
     MOV  DI,BLOCK_START	       ;;
     MOV  AX,BLOCK_END		       ;;
     MOV  [BP+DI].GRAPHICS_ESC_PTR,AX  ;; Set pointer to GRAPHICS seq
     MOV  [BP+DI].NUM_GRAPHICS_ESC,0   ;; Init sequence size
 .ENDIF 			       ;;
  MOV  LOWCOUNT_FOUND,NO	       ;; Flags to indicate whether the LOW
  MOV  HIGHCOUNT_FOUND,NO	       ;;  and HIGHCOUNT parms were found
  OR   STMTS_DONE,GR		       ;; Indicate GRAPHICS found
  MOV  AX,PREV_STMT		       ;; Terminate any preceeding groups
  OR   GROUPS_DONE,AX		       ;;
  MOV  DI,OFFSET GRAPHICS_PARSE_PARMS  ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
 .REPEAT			       ;;
    XOR  CX,CX			       ;;
    CALL SYSPARSE		       ;;
   .IF <AX EQ 0> NEAR		       ;; If PARM is valid
	MOV  BL,RESULT_TAG	       ;;
       .SELECT			       ;;
       .WHEN <BL EQ 1>		       ;; Escape byte
	  PUSH AX		       ;;
	  MOV	AX,1		       ;; Add a byte to the sequence
	  CALL	GROW_SHARED_DATA       ;; Update block end
	 .IF <BUILD_STATE EQ YES>      ;;
	     PUSH DI		       ;;
	     MOV  DI,BLOCK_START       ;;
	     INC  [BP+DI].NUM_GRAPHICS_ESC ;; Bump number of bytes in sequence
	     MOV  DI,BLOCK_END	       ;;
	     MOV  AL,RESULT_VAL        ;; Get esc byte from result buffer
	     MOV  [BP+DI-1],AL	       ;; Store at end of sequence
	     POP  DI		       ;;
	 .ENDIF 		       ;;
	  POP  AX		       ;;
       .WHEN <BL EQ 2>		       ;; LOWCOUNT
	  .IF <LOWCOUNT_FOUND EQ NO>   ;;
	       MOV   LOWCOUNT_FOUND,YES ;;
	       PUSH AX		       ;;
	       MOV   AX,1	       ;; Add a byte to the sequence
	       CALL  GROW_SHARED_DATA  ;; Update block end
	      .IF <BUILD_STATE EQ YES> ;;
		  PUSH DI	       ;;
		  MOV  DI,BLOCK_START  ;;
		  INC  [BP+DI].NUM_GRAPHICS_ESC ;; Bump number of bytes in seq.
		  MOV  AX,BLOCK_END    ;; Save pointer to low byte
		  DEC  AX	       ;;
		  MOV  [BP+DI].LOW_BYT_COUNT_PTR,AX
		  MOV  DI,AX	       ;;
		  MOV  BYTE PTR[BP+DI],0 ;; Store 0 in place of count
		  POP  DI	       ;;
	      .ENDIF		       ;;
	       POP  AX		       ;;
	  .ELSE 		       ;;
	       OR  STMT_ERROR,INVALID  ;; Duplicate LOWCOUNT parms
	       MOV  PARSE_ERROR,YES    ;;
	       MOV  BUILD_STATE,NO     ;;
	  .ENDIF		       ;;
       .WHEN <BL EQ 3>		       ;; HIGHCOUNT
	  .IF <HIGHCOUNT_FOUND EQ NO>  ;;
	      MOV   HIGHCOUNT_FOUND,YES ;;
	      PUSH AX		       ;;
	      MOV   AX,1	       ;; Add a byte to the sequence
	      CALL  GROW_SHARED_DATA   ;; Update block end
	     .IF <BUILD_STATE EQ YES>  ;;
		 PUSH DI	       ;;
		 MOV  DI,BLOCK_START   ;;
		 INC  [BP+DI].NUM_GRAPHICS_ESC ;; Bump number of bytes in sequen
		 MOV  AX,BLOCK_END     ;; Save pointer to high byte
		 DEC  AX	       ;; Block end always points 1 ahead
		 MOV  [BP+DI].HGH_BYT_COUNT_PTR,AX
		 MOV  DI,AX	       ;;
		 MOV  BYTE PTR[BP+DI],0 ;; Store 0 in place of count
		 POP  DI	       ;;
	     .ENDIF		       ;;
	      POP  AX		       ;;
	  .ELSE 		       ;;
	       OR  STMT_ERROR,INVALID  ;; Duplicate HIGHCOUNT parms
	       MOV  PARSE_ERROR,YES    ;;
	       MOV  BUILD_STATE,NO     ;;
	  .ENDIF		       ;;
       .ENDSELECT		       ;;
   .ELSE NEAR			       ;;
      .IF <AX NE -1>		       ;;
	  OR   STMT_ERROR,INVALID      ;; parm is invalid
	  MOV  PARSE_ERROR,YES	       ;;
	  MOV  BUILD_STATE,NO	       ;;
      .ENDIF			       ;;
   .ENDIF			       ;;
 .UNTIL <AX EQ -1> NEAR 	       ;;
 .IF  <LOWCOUNT_FOUND EQ NO> OR        ;;
 .IF  <HIGHCOUNT_FOUND EQ NO>	       ;; Missing LOWCOUNT/HIGHCOUNT parms
      OR   STMT_ERROR,INVALID	       ;;
      MOV  PARSE_ERROR,YES	       ;;
      MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  RET				       ;;
PARSE_GRAPHICS	ENDP		       ;;
;; Module Name:
;;   PARSE_COLORSELECT
COLORSELECT_PARSE_PARMS  LABEL WORD    ;; Parser control blocks
	    DW	 COLORSELECT_P	       ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
COLORSELECT_P	   LABEL BYTE	       ;;
CS_NUM_REQ    DB   1,1		       ;; Required, max parms
COLORSELECT_PARM   LABEL  WORD	       ;;
CS_POSITIONAL DW   ?		       ;; Pointer to our positional
	      DB   0		       ;; # Switches
	      DB   0		       ;; # keywords
COLORSELECT_P0	DW   2000H	       ;; sTRING - display type
	    DW	 2		       ;; Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 COLORSELECT_P0V       ;; Value list
	    DB	 0		       ;; Synomyms
COLORSELECT_P0V    DB	0		   ;; # of value lists
;	    DB	 0		       ;; # of range numerics
;	    DB	 0		       ;; # of discrete numerics
;	    DB	 1		       ;; # of strings
;	    DB	 1		       ;; tag
;COLORSELECT_P0V1 DW   ?		   ;; string
COLORSELECT_P1	DW   8001H		  ;; Numeric - escape sequence byte
	    DW	 0		       ;; No Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 COLORSELECT_P1V	  ;; Value list
	    DB	 0		       ;; Synomyms
COLORSELECT_P1V    DB	1		  ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 1,255		       ;; range 1..255
SEQ_LENGTH_PTR	DW   0		       ;; Number of colorselect statements
PARSE_COLORSELECT  PROC 	       ;;
  MOV  CUR_STMT,COLS		       ;;
 .IF <BIT STMTS_DONE NAND PRT>	       ;; PRINTER  statemnet must have been
     OR  STMT_ERROR,MISSING	       ;;  processed
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE AND DISP+COLP>    ;; DISDPLAYMODE and COLORPRINT  stmts
     OR  STMT_ERROR,SEQUENCE	       ;;  should NOT have been processed
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT GROUPS_DONE AND COLS>        ;; Check for a previous group of
     OR  STMT_ERROR,SEQUENCE	       ;;  COLORSELECTS within this PTD
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE NAND COLS>        ;; If first COLORSELECT...
      MOV  NUM_BANDS,0		       ;; Init number of COLORSELECT bands
     .IF <BUILD_STATE EQ YES>	       ;; Update count and pointer in the
	 MOV  AX,BLOCK_END	       ;;  Shared Data Area header
	 MOV  [BP].COLORSELECT_PTR,AX  ;; Set pointer to COLORSELECT info
	 MOV  [BP].NUM_PRT_BANDS,0     ;; Init NUMBER OF COLORSELECTS
     .ENDIF			       ;;
 .ENDIF 			       ;;
  OR   STMTS_DONE,COLS		       ;; Indicate found
 .IF <PREV_STMT NE COLS> THEN	       ;; Terminate any preceeding groups
     MOV  AX,PREV_STMT		       ;;  except for COLORSELECT
     OR   GROUPS_DONE,AX	       ;;
 .ENDIF 			       ;;
  MOV	AX,1			       ;; Make room for sequence length field
  CALL	GROW_SHARED_DATA	       ;;
 .IF <BUILD_STATE EQ YES>	       ;;
     INC  [BP].NUM_PRT_BANDS	       ;; Inc number of selects
     MOV  DI,BLOCK_END		       ;;
     MOV  BYTE PTR [BP+DI-1],0	       ;; Init sequence length field
     LEA  AX,[DI-1]		       ;;
     MOV  SEQ_LENGTH_PTR,AX	       ;; Save pointer to length of sequence
 .ENDIF 			       ;;
  MOV  DI,OFFSET COLORSELECT_PARSE_PARMS  ;; parse parms
  MOV  CS_NUM_REQ,1		       ;; Change to 1 required parameters
  MOV  AX,OFFSET COLORSELECT_P0        ;; Point to control block for the band
  MOV  CS_POSITIONAL,AX 	       ;;  ID.	(Dealing with only 1 positional
				       ;;  parameter at a time was the only way
				       ;;   I could get SYSPARSE to handle
				       ;;    the COLORSELECT syntax!)
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
  XOR  CX,CX			       ;;
  CALL SYSPARSE 		       ;; PARSE the band ID
 .IF <AX NE 0>			       ;;
     OR  STMT_ERROR,INVALID	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
     RET			       ;;  statement.
 .ENDIF 			       ;;
  PUSH	ES			       ;; We got a band id........
  PUSH	DI			       ;;
  LES	DI,DWORD PTR RESULT_VAL        ;; Get pointer to the parsed band id
 .IF <<BYTE PTR ES:[DI+1]> NE 0>       ;; Make sure the band id is only
     OR  STMT_ERROR,INVALID	       ;;  one byte long
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  MOV  BL,NUM_BANDS		       ;;
  XOR  BH,BH			       ;;
 .IF <BX EQ MAX_BANDS> THEN	       ;; Watch out for too many COLORSELECTs
     OR  STMT_ERROR,SEQUENCE	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ELSE				       ;;
     SHL  BX,1			       ;; calc index to store band in value list
     MOV  AL,ES:[DI]		       ;; get BAND ID FROM PARSEr
     MOV  BAND_VAL_LIST[BX],AL	       ;;
     INC  NUM_BANDS		       ;; bump number of bands
 .ENDIF 			       ;;
  POP  DI			       ;;
  POP  ES			       ;;
  MOV  AX,OFFSET COLORSELECT_P1        ;; Switch to numeric positional parm!!!
  MOV  CS_POSITIONAL,AX 	       ;;
  MOV  CS_NUM_REQ,0		       ;; Change to 0 required parameters
  XOR  DX,DX			       ;; PARSE the sequence of escape bytes
 .REPEAT			       ;;
    XOR  CX,CX			       ;;
    CALL SYSPARSE		       ;;
   .IF <AX EQ 0>		       ;; If esc byte is valid
	  PUSH AX		       ;;
	  MOV	AX,1		       ;; Add a byte to the sequence
	  CALL	GROW_SHARED_DATA       ;; Update block end
	 .IF <BUILD_STATE EQ YES>      ;;
	     PUSH DI		       ;;
	     MOV  DI,SEQ_LENGTH_PTR    ;;
	     INC  byte ptr [BP+DI]     ;; Bump number of bytes in sequence
	     MOV  DI,BLOCK_END	       ;;
	     MOV  AL,RESULT_VAL        ;; Get esc byte from result buffer
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
PARSE_COLORSELECT  ENDP 	       ;;
;; Module Name:
;;   PARSE_COLORPRINT
COLORPRINT_PARSE_PARMS	LABEL WORD    ;; Parser control blocks
	    DW	 COLORPRINT_P	      ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
COLORPRINT_P	  LABEL BYTE	       ;;
	      DB   3,4		       ;; Required,MAX
	      DW   COLORPRINT_P0       ;; Numeric: Red value
	      DW   COLORPRINT_P0       ;; Green value
	      DW   COLORPRINT_P0       ;; Blue value
	      DW   COLORPRINT_P1       ;; Band ID ... REPEATING
	      DB   0		       ;; # Switches
	      DB   0		       ;; # keywords
COLORPRINT_P0  DW   8000H	       ;; Numeric - RGB value
	    DW	 0		       ;; No Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 COLORPRINT_P0V        ;; Value list
	    DB	 0		       ;; Synomyms
COLORPRINT_P0V	 DB   1 	       ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 0,63		       ;; range 0..63
COLORPRINT_P1  DW   2001H	       ;; sTRING - Band ID
	    DW	 2		       ;; Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 COLORPRINT_P1V        ;; Value list
	    DB	 0		       ;; Synomyms
COLORPRINT_P1V	  DB   3	       ;; # of value lists
	    DB	 0		       ;; 0 - no range numerics
	    DB	 0		       ;; 0 - no actual numerics
NUM_BANDS   DB	 0		       ;; number of band values
	    DB	 01H		       ;; tag: TAGS ARE BAND MASKS
	    DW	 BAND_PTR_1	       ;; ptr
	    DB	 02H		       ;; tag
	    DW	 BAND_PTR_2	       ;; ptr
	    DB	 04H		       ;; tag
	    DW	 BAND_PTR_3	       ;; ptr
	    DB	 08H		       ;; tag
	    DW	 BAND_PTR_4	       ;; ptr
	    DB	 10H		       ;; tag
	    DW	 BAND_PTR_5	       ;; ptr
	    DB	 20H		       ;; tag
	    DW	 BAND_PTR_6	       ;; ptr
	    DB	 40H		       ;; tag
	    DW	 BAND_PTR_7	       ;; ptr
	    DB	 80H		       ;; tag
	    DW	 BAND_PTR_8	       ;; ptr
MAX_BANDS   EQU  8		       ;;
BAND_VAL_LIST  LABEL BYTE	       ;;
BAND_PTR_1  DB	 ?,0		       ;;
BAND_PTR_2  DB	 ?,0		       ;;
BAND_PTR_3  DB	 ?,0		       ;;
BAND_PTR_4  DB	 ?,0		       ;;
BAND_PTR_5  DB	 ?,0		       ;;
BAND_PTR_6  DB	 ?,0		       ;;
BAND_PTR_7  DB	 ?,0		       ;;
BAND_PTR_8  DB	 ?,0		       ;;
PARSE_COLORPRINT  PROC		       ;;
  MOV  CUR_STMT,COLP		       ;;
 .IF <BIT STMTS_DONE NAND PRT>	       ;; PRINTER  statemnet must have been
     OR  STMT_ERROR,MISSING	       ;;  processed
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT STMTS_DONE AND DISP>	       ;; DISPLAYMODE stmts
     OR  STMT_ERROR,SEQUENCE	       ;;  should NOT have been processed
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
 .IF <BIT GROUPS_DONE AND COLP>        ;; Check for a previous group of
     OR  STMT_ERROR,SEQUENCE	       ;;  COLORPRINTS within this PTD
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  MOV  CUR_PRINTER_TYPE,COLOR	       ;;
 .IF <BIT STMTS_DONE NAND COLP>        ;; If first COLORPRINT...
     .IF <BUILD_STATE EQ YES>	       ;; Update count and pointer in the
	 MOV  AX,BLOCK_END	       ;;  Shared Data Area header
	 MOV  [BP].COLORPRINT_PTR,AX   ;; Set pointer to COLORPRINT info
	 MOV  [BP].PRINTER_TYPE,COLOR  ;;
	 MOV  [BP].NUM_PRT_COLOR,0     ;; Init NUMBER OF COLORPRINTS
     .ENDIF			       ;;
 .ENDIF 			       ;;
 .IF <BUILD_STATE EQ YES>	       ;;
     INC  [BP].NUM_PRT_COLOR	       ;; Inc number of selects
 .ENDIF 			       ;;
  OR   STMTS_DONE,COLP		       ;; Indicate found
 .IF <PREV_STMT NE COLP> THEN	       ;; Terminate any preceeding groups
     MOV  AX,PREV_STMT		       ;;  except for COLORPRINT
     OR   GROUPS_DONE,AX	       ;;
 .ENDIF 			       ;;
  MOV	AX,BLOCK_END		       ;; Start a new block
  MOV	BLOCK_START,AX		       ;;
  MOV	AX,SIZE COLORPRINT_STR	       ;; Make room for COLORPRINT info
  CALL	GROW_SHARED_DATA	       ;;
  MOV  DI,OFFSET COLORPRINT_PARSE_PARMS  ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
  XOR  CX,CX			       ;;
  CALL SYSPARSE 		       ;; PARSE the RED value
 .IF <AX NE 0>			       ;;
     OR  STMT_ERROR,INVALID	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ELSE				       ;;
     .IF <BUILD_STATE EQ YES>	       ;;
	 PUSH  DI		       ;;
	 MOV  DI,BLOCK_START	       ;;
	 MOV  AL,RESULT_VAL	       ;; Store RED value in COLORPRINT info
	 MOV  [BP+DI].RED,AL	       ;;
	 POP  DI		       ;;
     .ENDIF			       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; PARSE the GREEN value
 .IF <AX NE 0>			       ;;
     OR  STMT_ERROR,INVALID	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ELSE				       ;;
     .IF <BUILD_STATE EQ YES>	       ;;
	 PUSH  DI		       ;;
	 MOV  DI,BLOCK_START	       ;;
	 MOV  AL,RESULT_VAL	       ;; Store GREEN value in COLORPRINT info
	 MOV  [BP+DI].GREEN,AL	       ;;
	 POP  DI		       ;;
     .ENDIF			       ;;
 .ENDIF 			       ;;
  CALL SYSPARSE 		       ;; PARSE the BLUE value
 .IF <AX NE 0>			       ;;
     OR  STMT_ERROR,INVALID	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ELSE				       ;;
     .IF <BUILD_STATE EQ YES>	       ;;
	 PUSH  DI		       ;;
	 MOV  DI,BLOCK_START	       ;;
	 MOV  AL,RESULT_VAL	       ;; Store BLUE value in COLORPRINT info
	 MOV  [BP+DI].BLUE,AL	       ;;
	 POP  DI		       ;;
     .ENDIF			       ;;
 .ENDIF 			       ;;
 .IF <BUILD_STATE EQ YES>	       ;;
     PUSH  DI			       ;;
     MOV   DI,BLOCK_START	       ;;
     MOV   [BP+DI].SELECT_MASK,0       ;; Initialize band select mask
     POP   DI			       ;;
 .ENDIF 			       ;;
  XOR  DX,DX			       ;; For each band found "OR" the item
 .REPEAT			       ;;  tag into the select mask
    MOV  CX,3			       ;; Avoid getting too many parms error
    CALL SYSPARSE		       ;;  from parser
   .IF <AX EQ 0>		       ;;
     .IF <BUILD_STATE EQ YES>	       ;;
	  PUSH	DI		       ;;
	  MOV	DI,BLOCK_START	       ;;
	  MOV	AL,RESULT_TAG	       ;;
	  OR	[BP+DI].SELECT_MASK,AL ;; OR the mask for this band into the
				       ;;  select mask for this color
	  POP	DI		       ;;
     .ENDIF			       ;;
   .ELSE			       ;;
      .IF <AX NE -1>		       ;;
	  OR   STMT_ERROR,INVALID      ;; parm is invalid
	  MOV  PARSE_ERROR,YES	       ;;
	  MOV  BUILD_STATE,NO	       ;;
      .ENDIF			       ;;
   .ENDIF			       ;;
 .UNTIL <AX EQ -1> NEAR 	       ;;
  RET				       ;;
PARSE_COLORPRINT  ENDP		       ;;
;; Module Name:
;;   PARSE_DARKADJUST
DARKADJUST_PARSE_PARMS	LABEL WORD    ;; Parser control blocks
	    DW	 DARKADJUST_P	      ;;
	    DB	 2		       ;; # of lists
	    DB	 0		       ;; # items in delimeter list
	    DB	 1		       ;; # items in end-of-line list
	    DB	 ';'                   ;; ';' used for comments
DARKADJUST_P	  LABEL BYTE	       ;;
	      DB   1,1		       ;; Required,MAX
	      DW   DARKADJUST_P0       ;; Numeric: adjust value
	      DB   0		       ;; # Switches
	      DB   0		       ;; # keywords
DARKADJUST_P0  DW   4000H	       ;; Signed Numeric - adjust value
	    DW	 0		       ;; No Capitalize
	    DW	 RESULT_BUFFER	       ;; Result buffer
	    DW	 DARKADJUST_P0V        ;; Value list
	    DB	 0		       ;; Synomyms
DARKADJUST_P0V	 DB   1 	       ;; # of value lists
	    DB	 1		       ;; # of range numerics
	    DB	 1		       ;; tag
	    DD	 -63,63 	       ;; range -63,63
;;;;***********************************;;
PARSE_DARKADJUST  PROC		       ;;
  MOV  CUR_STMT,DARK		       ;;
 .IF <BIT STMTS_DONE NAND PRT>	       ;; PRINTER  statemnet must have been
     OR  STMT_ERROR,MISSING	       ;;  processed
	MOV  PARSE_ERROR,YES	       ;;
	MOV  BUILD_STATE,NO	       ;;
 .ENDIF 			       ;;
  OR   STMTS_DONE,DARK		       ;; Indicate found
				       ;; Terminate any preceeding groups
  MOV  AX,PREV_STMT		       ;;
  OR   GROUPS_DONE,AX		       ;;
  MOV  DI,OFFSET DARKADJUST_PARSE_PARMS  ;; parse parms
				       ;; SI => the line to parse
  XOR  DX,DX			       ;;
  XOR  CX,CX			       ;;
  CALL SYSPARSE 		       ;; PARSE the ADJUST VALUE
 .IF <AX NE 0>			       ;;
     OR  STMT_ERROR,INVALID	       ;;
     MOV  PARSE_ERROR,YES	       ;;
     MOV  BUILD_STATE,NO	       ;;
 .ELSE				       ;;
     .IF <BUILD_STATE EQ YES>	       ;;
	 MOV  AL,RESULT_VAL	       ;;
	 MOV  [BP].DARKADJUST_VALUE,AL ;;
     .ENDIF			       ;;
      CALL SYSPARSE		       ;; CHECK FOR EXTRA PARMS
     .IF <AX NE -1>		       ;;
	OR  STMT_ERROR,INVALID	       ;;
	MOV PARSE_ERROR,YES	       ;;
	MOV BUILD_STATE,NO	       ;;
     .ENDIF			       ;;
 .ENDIF 			       ;;
  RET				       ;;
PARSE_DARKADJUST  ENDP		       ;;
LIMIT	LABEL NEAR		       ;;
CODE	ENDS			       ;;
	END
