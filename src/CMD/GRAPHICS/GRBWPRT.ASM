	PAGE ,132
	TITLE	DOS GRAPHICS Command  -	Black and White printing modules
;; DOS - GRAPHICS Command
;; (c) Copyright 1988 Microsoft
;; File Name:  GRBWPRT.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the code for printing a GRAPHICS screen on a
;;	 BLACK and WHITE printer.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	PRINT_BW_APA
;;	  FILL_BUFFER
;;	    INT2PAT
;;	    PAT2BOX
;; Include Files Required:
;; -----------------------
;;	 GRCTRL.EXT   - Externals for print screen control
;;	 GRCTRL.STR   - Structures and equates for print screen control
;;	 GRPATTRN.STR - Structures for the printer patterns.
;;	 GRSHAR.STR   - Shared Data Area Structure
;;	 STRUC.INC    - Macros for using structured assembly language
;; External Procedure References:
;; ------------------------------
;;	 FROM FILE  GRCTRL.ASM:
;;	      PRT_SCR - Main module for printing the screen.
;;	 TO FILE GRCOMMON.ASM
;;	      Common modules - tools for printing a screen.
;; Linkage Instructions:
;; --------------------
;;	 This file is included by GRCTRL.ASM
PAGE
CODE	SEGMENT PUBLIC 'CODE'
	ASSUME		CS:CODE,DS:CODE
	PUBLIC	PRINT_BW_APA
	PUBLIC	LEN_OF_BW_MODULES
.XLIST
INCLUDE GRCTRL.STR			; Stuctures needed
INCLUDE GRSHAR.STR			;  for both set of print modules
INCLUDE GRPATTRN.STR			;
INCLUDE GRCTRL.EXT			; Externals from PRT_SCR control module
INCLUDE STRUC.INC			;
	PUBLIC PRINT_BW_APA		; Black and white modules,
.LIST
;===============================================================================
; PRINT_BW_APA : PRINT A GRAPHIC MODE SCREEN ON A BLACK AND WHITE PRINTER
;-------------------------------------------------------------------------------
;	INPUT:	BP	 = Offset of the shared data area
;		XLT_TAB  = Color translation table
;		BIOS_INT_5H = Pointer to BIOS int 5h
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
; DESCRIPTION:	This procedure	maps  each  pixel of the screen to a box
; of dots on the printer.  The box size depends on the screen resolution
; and  the number  of  bytes per printer line.	It is chosen in order to
; respect the  screen ratio and  is  documented in each printer profile.
;     For efficiency and space considerations, the print buffer does not
; hold a full print line.  Bytes representing pixels are printed as soon
; as they are  ready to be printed.  However, the print buffer	is  wide
; enough to hold complete boxes.
;     The order  for reading  pixels  off the screen  is  driven  by the
; order bytes  are  expected by the printer.  To print the screen in its
; original orientation we must begin reading it from the top left corner
; and  send  the pixels line by line; to print it sideways, reading will
; start from the bottom left  corner and a "LINE" will now be a vertical
; screen column read from bottom to top.
;     There is	more  to it  however, the  printer  head  is  printing a
; vertical  column of 8 dots  at a time and each pixel read is mapped to
; a box of dots  that is less than  8 dots high  (e.g., 2 cols	x 1 row)
; therefore, many boxes must be stored in the bytes sent to the printer.
;     These boxes represent pixels that are one above each other on  the
; screen. We must read enough pixels on one column of the screen to  use
; all 8 bits of the vertical printer head (e.g., if the box size  is 2x1
; then 8  pixels  must be read	and  2 bytes of the print buffer will be
; filled).
;     The  PRINT BUFFER  for  any  box size  will be 8 bits high by "BOX
; WIDTH" bits wide.
;     After the buffer is filled, it is  printed  and  the next "column"
; of  8 pixels	is read.  Therefore,  the screen  is read "line by line"
; where a line is  8 pixels high  for a 2x1 box (4 pixels high for a 3x2
; box).  ONE SUCH LINE IS CALLED A SCAN LINE.
PAGE
; A 350X200 screen mapping to a 3x2 box is read in the following order:
; SCREEN:
;	  column column    . . .	column
;	  no. 0  no. 1			no. 349
;	 ษออออออออออออออออออออออออออออออออออออออออป
;  scan  บ1(0,0) 5(0,1) 	       1397(0,349)บ
;  line  บ2(1,0) 6(1,1)  . . . . . . . 1398(1,349)บ
;  no. 1 บ3(2,0) 7(2,1) 	       1399(2,349)บ
;	 บ4(3,0) 8(3,1) 	       1400(3,349)บ
;	 บ					  บ
;  scan  บ1401(4,0) 1405(4,1)			  บ    LEGEND:	n(X,Y)
;  line  บ1402(5,0)   etc,			  บ
;  no. 2 บ1403(6,0)	     . . . . .		  บ    n = READ RANK
;	 บ1404(7,0)				  บ    X = ROW NUMBER
;	 บ    . 				  บ    Y = COLUMN NUMBER
;   etc, บ    . 				  บ
;	 บ    . 		    70000(199,349)บ
;	 ศออออออออออออออออออออออออออออออออออออออออผ
; LOGIC :
; Initialize printer and local variables.
; CALL	  LOC_MODE_PRT_INFO ; Get printer info related to current mode.
; CALL	  GET_SCREEN_INFO   ; Get info. about how to read the screen
; CALL	  SETUP_PRT	    ; Set up the printer (Line spacing, etc)
; FOR each scan line on the screen (NB_SCAN_LINES)
;   (Note: One scan line maps to one print line)
;   BEGIN
;   CALL DET_CUR_SCAN_LNE_LENGTH ; Determine length in pels of the current
;			  ;  scan line.
;   IF CUR_SCAN_LNE_LENGTH NE 0 THEN
;     CALL NEW_PRT_LINE     ; Initialize a new printer line
;     DO CUR_SCAN_LNE_LENGTH times ; For each column
;	BEGIN
;	CALL FILL_BUFFER    ; Read top-down enough pels to fill the buffer
;	CALL PRINT_BUFFER   ; Print the buffer
;	IF printing sideways THEN INC CUR_ROW	 ; Get coordinates of next
;			     ELSE INC CUR_COLUMN ;  "column" (vertical chunk of
;	END (for each column)			 ;   a scan line).
;   PRINT_BYTE CR	  ; Print a CR and a LF
;   PRINT_BYTE LF
;   ; Get coordinates of next scan line:
;   IF printing sideways THEN
;			      ADD CUR_COLUMN,NB_BOXES_PER_PRT_BUF
;			      MOV CUR_ROW,SCREEN_HEIGHT - 1
;			 ELSE
;			      ADD CUR_ROW,NB_BOXES_PER_PRT_BUF
;			      MOV CUR_COLUMN,0
;   END (for each scan line)
PRINT_BW_APA PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
;-------------------------------------------------------------------------------
; INITIALIZATION:
;	1) Locate and extract printer DISPLAYMODE information from
;	   the shared data area, calculate the number of boxes fitting
;	   in the printer buffer.
;	2) Determine where to start reading the screen:
;	     If printing sideways, start in LOW LEFT corner.
;	     If normal printing, start in TOP LEFT corner.
;	   Determine the maximum length for a scan line:
;	     If printing sideways, it is the height of the screen.
;	     For normal printing, it is the width of the screen.
;	   Determine the number of scan lines on the screen.
;	3) Set up the Printer for printing Graphics.
;-------------------------------------------------------------------------------
	CALL	LOC_MODE_PRT_INFO	; Get printer info related to curr. mode
;-------Test if DISPLAYMODE info record was found:
       .IF <ERROR_CODE EQ DISPLAYMODE_INFO_NOT_FOUND>
       .THEN
	  MOV	  ERROR_CODE,UNABLE_TO_PRINT ; IF no record found,
	  JMP	  PRINT_BW_APA_END	     ; then, return error code
       .ENDIF				     ;	      and quit procedure
;-------Get the box size from the DISPLAYMODE info record:
	MOV	BX,CUR_MODE_PTR 	; BX := Offset current DISPLAYMODE info.
	MOV	AH,[BX].BOX_WIDTH	; Take local copy of the box size.
	MOV	BOX_W,AH		;  in BOX_W and BOX_H
	MOV	AL,[BX].BOX_HEIGHT
	MOV	BOX_H,AL
;-------Verify if the box size obtained from DISPLAYMODE info. is valid
       .IF <ZERO AL> OR 		; IF height of the box is 0
       .IF <ZERO AH>			;  OR width of the box is 0
       .THEN				; THEN we can't print:
	  MOV	  ERROR_CODE,UNABLE_TO_PRINT ; return error code
	  JMP	  PRINT_BW_APA_END	;	and quit
       .ENDIF
;-------Get the Print Orientation from the DISPLAYMODE info record
       .IF <[BX].PRINT_OPTIONS EQ ROTATE>; If printing sideways
       .THEN				;  then:
	  MOV	  ROTATE_SW,ON		;    Rotate switch := "ON"
       .ENDIF
;-------Initialize print variables and the printer:
	CALL	GET_SCREEN_INFO 	; Get info. about how to read the screen
	CALL	SETUP_PRT		; Set up the printer (Line spacing, etc)
       .IF  <BIT ERROR_CODE NZ PRINTER_ERROR>
       .THEN				; A printer error occurred: quit
	  JMP	  PRINT_BW_APA_END	;
       .ENDIF
	MOV	CX,NB_SCAN_LINES
;-------------------------------------------------------------------------------
; FOR EACH SCAN LINE ON THE SCREEN:
;-------------------------------------------------------------------------------
PRINT_1_SCAN_LINE:
	CALL	DET_CUR_SCAN_LNE_LENGTH ; Determine how many non-blanks on line
.IF <CUR_SCAN_LNE_LENGTH NE 0>		; If line is not empty
.THEN					; then,
	CALL	NEW_PRT_LINE		;  Send escape sequence to the printer
       .IF  <BIT ERROR_CODE NZ PRINTER_ERROR> ; for starting a new line.
       .THEN				; If a printer error occurred:
	  JMP	  PRINT_BW_APA_END	;   Quit !
       .ENDIF
	PUSH	CX			; Save scan line counter
	MOV	CX,CUR_SCAN_LNE_LENGTH
;-------------------------------------------------------------------------------
; FOR each column on the current scan line (up to the last non-blank):
;-------------------------------------------------------------------------------
PRINT_1_SCAN_COLUMN:
	CALL	FILL_BUFFER		; Read all pixels on this column,
					;   convert each to a printer box,
					;    store boxes in the print buffer
					;     (a buffer contains one "column"
					;      of pixels).
	CALL	PRINT_BUFFER		; Print the buffer.
       .IF  <BIT ERROR_CODE NZ PRINTER_ERROR>
       .THEN				; A printer error occurred:
	  POP	  CX			; Restore scan line counter and quit
	  JMP	  PRINT_BW_APA_END	;
       .ENDIF
;-------Get coordinates of next "column":
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  DEC CUR_ROW			; then, get row above on screen
       .ELSE				;
	  INC CUR_COLUMN		; else, get column next right
       .ENDIF				;
	LOOP	PRINT_1_SCAN_COLUMN	; Print next column
	POP	CX			; Restore scan line counter
.ENDIF					; Endif line is not empty
;-------------------------------------------------------------------------------
; Print a carriage return and a line feed:
;-------------------------------------------------------------------------------
	MOV	AL,CR
	CALL	PRINT_BYTE		; Send CR
	JC	PRINT_BW_APA_END	; If printer error, leave
	MOV	AL,LF
	CALL	PRINT_BYTE		; Send LF
	JC	PRINT_BW_APA_END	; If printer error, leave
;-------------------------------------------------------------------------------
; Get coordinates of next scan line:
;-------------------------------------------------------------------------------
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				; then:
	  MOV	  AL,NB_BOXES_PER_PRT_BUF ;   AX := Numbers of pels read on row
	  CBW				;
	  ADD	  CUR_COLUMN,AX 	;   CUR_COLUMN + Number of pels read
	  MOV	  AX,SCREEN_HEIGHT	;   CUR_ROW := SCREEN_HEIGHT - 1
	  DEC	  AX			;
	  MOV	  CUR_ROW,AX		;
       .ELSE				; else, printing NOT rotated:
	  MOV	  AL,NB_BOXES_PER_PRT_BUF ;   AX := Number of pels read on colum
	  CBW				;
	  ADD	  CUR_ROW,AX		;   CUR_ROW + Number of pels read
	  MOV	  CUR_COLUMN,0		;   CUR_COLUMN := 0
       .ENDIF				;
	LOOP	PRINT_1_SCAN_LINE	;
;-------------------------------------------------------------------------------
; Restore the printer.
;-------------------------------------------------------------------------------
	CALL	RESTORE_PRT
PRINT_BW_APA_END:
	POP	CX
	POP	BX
	POP	AX
	RET
PRINT_BW_APA ENDP
PAGE
;===============================================================================
; FILL_BUFFER : READS ENOUGH PIXELS TO FILL UP THE PRINT BUFFER.
;		THESE PIXELS ARE MAPPED TO A PRINTER DOT BOX.
;-------------------------------------------------------------------------------
;	INPUT:	CUR_COLUMN,
;		CUR_ROW = Coordinates of the first pixel to be read
;		BOXES_PER_PRT_BUF = Number of boxes fitting in the print
;				    buffer
;		XLT_TAB = Color translation table
;	OUTPUT: PRT_BUF = PRINT BUFFER
;-------------------------------------------------------------------------------
; DESCRIPTION:
;	1) Pixels are read one by one vertically from top to bottom in
;	   the current column of the screen scan line.
;	   NOTE: What is called here a 'column' can actually be a line
;		 on the physical display.
;	2) Each pixel is mapped to a printer dot box.
;	3) Each Dot box is stored in the printer buffer.
;	4) The coordinates in input are those of the "top" pixel
;	   and restored when leaving this procedure.
; LOGIC:
; Save coordinates of the current "column" (slice of a screen scan line)
; DO for BOXES_PER_PRT_BUF  (8 / BOX_H)
;   BEGIN
;   CALL READ_DOT		  ; Read a pixel, get index in XLT_TAB
;   Get pixel intensity from XLT_TAB
;   CALL INT2PAT		  ; Locate pattern corresponding to int.
;   CALL PAT2BOX		  ; Extract box from pattern
;   CALL STORE_BOX		  ; Store the box in the printer buffer
;   ; Get coordinates of next pixel below:
;   IF printing is sideways THEN INC CUR_COLUMN
;			    ELSE INC CUR_ROW
;   END
; Restore initial coordinates.
FILL_BUFFER PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	SI
	PUSH	DI
;-------------------------------------------------------------------------------
; Save initial coordinates:
;-------------------------------------------------------------------------------
	PUSH	CUR_ROW
	PUSH	CUR_COLUMN
;-------Clear the print buffer:
	XOR	BX,BX		; For each byte in the PRT_BUF:
CLEAR_PRT_BUF:
	MOV	PRT_BUF[BX],0	;  Initialize byte to blanks
	INC	BX		;  Get next byte
	CMP	BL,BOX_W	;  All bytes cleared ?
	JL	CLEAR_PRT_BUF	;  No, clear next one.
	MOV	BX,OFFSET XLT_TAB ; BX := Offset of XLT_TAB
;-------Fill the print buffer with one box for each pixel read:
	XOR	CX,CX		; CL := Number of pixels to read
	MOV	CL,NB_BOXES_PER_PRT_BUF
;-------------------------------------------------------------------------------
; For each pixel within the current column of the scan line:
;-------------------------------------------------------------------------------
READ_AND_STORE_1_PIXEL:
	CALL	READ_DOT		; AL := Index into translation table
	XLAT	XLT_TAB 		; AL := Intensity
	CALL	INT2PAT 		; SI := Offset of matching Pattern
	CALL	PAT2BOX 		; Extract CUR_BOX from the pattern.
	MOV	SI,OFFSET CUR_BOX	; Store it in the PRT_BUF
	CALL	STORE_BOX
;-------Get coordinates of next pixel:
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  INC CUR_COLUMN		; then, increment column number
       .ELSE				;
	  INC CUR_ROW			; else, increment row number
       .ENDIF				;
	LOOP READ_AND_STORE_1_PIXEL
;-------------------------------------------------------------------------------
; Restore initial coordinates:
;-------------------------------------------------------------------------------
	POP	CUR_COLUMN
	POP	CUR_ROW
	POP	DI
	POP	SI
	POP	CX
	POP	BX
	POP	AX
	RET
FILL_BUFFER ENDP
PAGE
;===============================================================================
; INT2PAT : MAP AN INTENSITY TO A PATTERN.
;-------------------------------------------------------------------------------
;	INPUT:	AL = GREY INTENSITY (0 - 63 = BLACK to WHITE)
;		BOX_W = Number of columns in a box
;		CUR_MODE_PTR = Offset of current DISPLAYMODE info record
;	OUTPUT: SI = OFFSET OF THE PATTERN MATCHING THE INTENSITY
;-------------------------------------------------------------------------------
; DESCRIPTION: Performs a sequential search in the table of patterns
; until the proper pattern is found.
; SI = 0 ; FOUND = FALSE
; DO UNTIL FOUND = TRUE
;   BEGIN
;   IF AL <= Maximum intensity of the current pattern in the table
;     THEN
;	FOUND = TRUE
;     ELSE
;	SI = SI + (BOX_W * 2)
;   END
INT2PAT PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	DX
;-------Calculate the size in bytes of one pattern STRUCTURE: (see GRPATTRN.STR)
	MOV	DL,BOX_W	; DX := Number of columns in the box
	XOR	DH,DH
	SHL	DL,1		; (DX * 2) = Number of columns in the pattern
	INC	DL		; DL := Size in bytes of one pattern
				;	(includes intensity field)
	MOV	BX,CUR_MODE_PTR ; BX := Offset of current mode
				; SI := Offset of the first pattern
	MOV	SI,[BX].PATTERN_TAB_PTR
	ADD	SI,BP
COMPARE_INTENSITY:
	CMP	AL,[SI] 	; Within the range of this pattern ?
	JLE	FOUND_PATTERN	;   Yes, use this pattern.
				;   No, look at next pattern:
	ADD	SI,DX		;     SI := SI + Number columns in pattern)
	JMP	SHORT COMPARE_INTENSITY
FOUND_PATTERN:
	POP	DX
	POP	BX
	POP	AX
	RET
INT2PAT ENDP
PAGE
;===============================================================================
; PAT2BOX : SELECT AND EXTRACT THE PROPER BOX FROM THE PATTERN ACCORDING
;	    TO THE COORDINATES OF THE PIXEL.
;-------------------------------------------------------------------------------
;	INPUT:	SI = OFFSET OF CURRENT PATTERN
;		CUR_COLUMN,
;		CUR_ROW  = COORDINATES OF THE CURRENT PIXEL
;	OUTPUT: CUR_BOX  = PORTION OF THE PATTERN TO BE PRINTED
;-------------------------------------------------------------------------------
; DESCRIPTION: If the pixel is on even-even coordinates, then the
; top-left box of the pattern is extracted.
; If its Even-odd --> extract the top-right box.
; Odd-even --> low-left box, and Odd-odd  --> low-right box.
PAGE
;  For example., (with a 3x2 box):
;  PATTERN (over 6 bytes):
;	       byte1  byte2  byte3	byte4  byte5  byte6
;		 0	0      0	  0	 0	0
;		 0	0      0	  0	 0	0
;		 0	0      0	  0	 0	0
;		 0	0      0	  0	 0	0
; even-even --> dot1   dot2   dot3   |	 dot1	dot2   dot3 <-- even-odd
; (row-column)	dot4   dot5   dot6   |	 dot4	dot5   dot6	box
; box.	       ------------------------------------------------
; odd-even  --> dot1   dot2   dot3   |	 dot1	dot2   dot3 <-- odd-odd
; box		dot4   dot5   dot6   |	 dot4	dot5   dot6	box
;  The selected box is then stored as follow:
;  CUR_BOX:
;		byte1 byte2 byte3
;     MSB ------> 0	0     0
;     (bit7)	  0	0     0
;		  0	0     0
;		  0	0     0
;		  0	0     0
;		  0	0     0
;		 dot1  dot2  dot3 <-- box
;     LSB ------>dot4  dot5  dot6
; LOGIC:
; IF CUR_ROW is odd
; THEN SI := SI + BOX_W 	; Access right portion of pattern
; Build a bit mask in BL of BOX_H bits, right justified.
; FOR each column in the box (BOX_W)
;   Get the pattern column in AL
;   IF CUR_COLUMN is even
;   THEN
;     Move down the column of the top box.
;   AND BL,AL			; BL <-- Column of the desired box
PAT2BOX PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	SI
					; SI := Offset of current pattern
	INC	SI			; Skip the MAX INTENSITY field
;-------------------------------------------------------------------------------
; Set SI to either the left or right set of 2 boxes in the pattern:
;-------------------------------------------------------------------------------
	TEST	CUR_ROW,1		; Odd row ?
	JZ	EXTRACT_BOX		;   No,  access left portion of pattern
	MOV	AL,BOX_W		;
	CBW				;
	ADD	SI,AX			;   Yes, access right portion of pattern
;-------------------------------------------------------------------------------
; Extract the box:
;-------------------------------------------------------------------------------
EXTRACT_BOX:
;-------Build a bit mask that will be used to keep only BOX_H bits
;-------of the bytes where CUR_BOX is stored.
	XOR	AH,AH			; AH := Box column bit mask
	MOV	AL,BOX_H		; For each row of the box:
INIT_MASK:				;
	SHL	AH,1			;
	OR	AH,1			;    Insert one bit in the mask.
	DEC	AL			;
	CMP	AL,0			;
	JG	INIT_MASK
	XOR	BX,BX			; BL := Column number within the box
;-------For each column of the box:
EXTRACT_1_BOX_COLUMN:
	MOV	AL,[SI] 		; AL := Current column of pattern
	TEST	CUR_COLUMN,1		; If the pixel is on ODD column
	JNZ	BOTTOM_BOX		;   Then, need bottom box portion
	MOV	CL,BOX_H		;   Else, need top box portion
TOP_BOX:				; Need top box:
	SHR	AL,CL			;   Shift top box over bottom box
BOTTOM_BOX:				; The box we want is now at bottom
	AND	AL,AH			; Keep only bits from the box
	MOV	CUR_BOX[BX],AL		; Store this box column
	INC	SI			; Access next column of the pattern
	INC	BX			; One more column stored.
	CMP	BL,BOX_W		; All stored ?
	JL	EXTRACT_1_BOX_COLUMN	;   No, continue
	POP	SI
	POP	CX
	POP	BX
	POP	AX
	RET
PAT2BOX ENDP
INCLUDE GRCOMMON.ASM
LEN_OF_BW_MODULES EQU $-PRINT_BW_APA
CODE	ENDS
	END
