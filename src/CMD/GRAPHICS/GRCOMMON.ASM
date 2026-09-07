	PAGE	,132
;; DOS - GRAPHICS Command
;; (c) Copyright 1988 Microsoft
;; File Name:  GRCOMMON.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the modules common to the Print Screen
;;	 process of GRAPHICS.COM.
;;	 This file is included by both set of Print modules.
;;	 This file MUST BE COMPILED WITH EACH SET OF MODULES since,
;;	 one set is relocated in memory at installation time; all
;;	 references to the common procedures must be resolved from
;;	 within each set of print modules.
;;	 The set of common modules is relocated in memory along with
;;	 the selected set of print modules.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	READ_DOT
;;	LOC_MODE_PRT_INFO
;;	STORE_BOX
;;	PRINT_BUFFER
;;	GET_SCREEN_INFO
;;	SETUP_PRT
;;	RESTORE_PRT
;;	NEW_PRT_LINE
;;	PRINT_BYTE
;;	DET_CUR_SCAN_LNE_LENGTH
;; Include Files Required:
;; -----------------------
;;	none
;; External Procedure References:
;; ------------------------------
;;	 FROM FILE  GRCTRL.ASM:
;;	      PRT_SCR	       - Main module for printing the screen.
;;	 FROM FILE  GRBWPRT.ASM:
;;	      PRT_BW_APA       - Main module for printing on BW printer.
;;	 FROM FILE  GRCOLPRT.ASM:
;;	      PRINT_COLOR      - Main module for printing on COLOR printer.
;; Linkage Instructions:
;; --------------------
;;	 This file is included by both GRBWPRT.ASM and GRCOLPRT.ASM and is
;;	 compiled with each of them. However, only one copy is made resident.
PAGE
;===============================================================================
; LOC_MODE_PRT_INFO: LOCATE DISPLAYMODE PRINTER INFO. FOR THE CURRENT
;		     MODE
;-------------------------------------------------------------------------------
;	INPUT:	BP		= Offset of the shared data area
;		CUR_MODE	= Current video mode
;	OUTPUT: CUR_MODE_PTR	= Absolute Offset of the
;				  current DISPLAYMODE INFO record.
;		ERROR_CODE	= DISPLAYMODE_INFO_NOT_FOUND if not found.
;	CALLED BY: PRINT_COLOR
;		   PRINT_BW_APA
;-------------------------------------------------------------------------------
; DESCRIPTION:	DISPLAYMODE_PTR is pointing to the first DISPLAYMODE
; INFO record within the Shared Data Area.
; This (chained) list of DISPLAYMODE records is scanned until the record
; for the current mode is found.
; Note: All pointers in the DISPLAYMODE records are relative to the beginning
;	of the shared data area. Therefore, we must add the offset of the
;	shared data area (in BP) in order to access the data these pointers
;	are referencing.
;	The CUR_MODE_PTR is relative to the segment and references the
;	DISPLAYMODE record for the video mode currently set at print screen
;	time.
; LOGIC:
; FOUND := FALSE
; DO UNTIL FOUND OR END_OF_LIST
;   Get a display mode information record
;   IF record.DISP_MODE = CUR_MODE
;     THEN FOUND := TRUE
;   ELSE
;     CUR_MODE_PTR := record.NEXT_DISP_MODE
LOC_MODE_PRT_INFO PROC NEAR
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	MOV	BX,DS:[BP].DISPLAYMODE_PTR	; [BX] := Current DISPLAYMODE
	ADD	BX,BP				;	   record
	MOV	DL,CUR_MODE			; DL := Current mode
SCAN_1_DISPLAYMODE_RECORD:
	MOV	SI,[BX].DISP_MODE_LIST_PTR	; [SI] : First mode covered
	ADD	SI,BP				;    by this DISPLAYMODE record
	MOV	CL,[BX].NUM_DISP_MODE		; Scan each mode in the list
	XOR	CH,CH
SCAN_LIST_OF_MODES:
	CMP	CS:[SI],DL			; FOUND ?
	JE	FOUND
	INC	SI				; NO, get next mode in
	LOOP	SCAN_LIST_OF_MODES		;      DISPLAYMODE record
	CMP	[BX].NEXT_DISP_MODE,-1		; END OF DISPLAYMODE LIST ?
	JE	NOT_FOUND			; Yes, this mode not supported
NEXT_RECORD:					; No,
	MOV	BX,[BX].NEXT_DISP_MODE		;     [BX] := Next record
	ADD	BX,BP				;
	JMP	SHORT SCAN_1_DISPLAYMODE_RECORD
FOUND:						; Found:
	MOV	CUR_MODE_PTR,BX 		; Update pointer to current
	JMP	SHORT LOC_MODE_PRT_INFO_END	; DISPLAYMODE record.
NOT_FOUND:					; Not found:
	MOV	ERROR_CODE,DISPLAYMODE_INFO_NOT_FOUND ; Return error condition
LOC_MODE_PRT_INFO_END:
	POP	SI
	POP	DX
	POP	CX
	POP	BX
	RET
LOC_MODE_PRT_INFO ENDP
PAGE
;===============================================================================
; STORE_BOX : STORE ONE BOX IN THE PRINT BUFFER.
;-------------------------------------------------------------------------------
;	INPUT:	SI	   = OFFSET OF THE BOX TO BE PRINTED
;		BOX_W	   = BOX WIDTH IN BITS
;		BOX_H	   = BOX HEIGHT IN BITS
;	OUTPUT: PRT_BUF  = THE PRINT BUFFER
;-------------------------------------------------------------------------------
; DESCRIPTION: The print buffer is first shifted left in order to make
; room for the new box (Note: the MSB's are lost; they are assumed to
; have been printed), then the box is inserted in the low-order bits of
; the printer buffer.
PAGE
;			      EXAMPLE
;			      -------
; BEFORE:				     AFTER:
; BOX: 0    0	0
;      0    0	0
;      0    0	0
;      0    0	0
;      0    0	0
;      0    0	0
;      b1  b2  b3
;      b4  b5  b6
; PRT_BUF: byte1 byte2 byte3		     PRT_BUF:  byte1 byte2 byte3
;	     0	   1	 0				 1     1     1
;	     1	   0	 1				 1     1     1
;	     1	   1	 1				 1     1     1
;	     1	   1	 1				 1     1     1
;	     1	   1	 1				 1     1     1
;	     1	   1	 1				 1     1     1
;	     1	   1	 1				 b1    b2    b3
;    LSB --> 1	   1	 1				 b4    b5    b6
; LOGIC:
; FOR each byte of the buffer (BOX_W)
;   BEGIN
;   Make room for the box to be inserted
;   Insert the box
;   END
STORE_BOX PROC NEAR
	PUSH	BX
	PUSH	CX
	PUSH	DI
	MOV	DI,OFFSET PRT_BUF ; DI := Offset of the Print buffer
	XOR	BX,BX		  ; BX := Byte index number
	MOV	CL,BOX_H	  ; CL := Number of BITS to be shifted
; FOR each column (byte) of the box to be stored in the buffer:
STORE_1_BYTE:
	SHL	BYTE PTR [BX][DI],CL	; Make room for the bits to be inserted
	MOV	CH,[BX][SI]		; CH := column of the box to be inserted
	OR	[BX][DI],CH		; Insert the box column in the buffer
	INC	BL			; Get next column (byte) of the box
	CMP	BL,BOX_W		; All columns (bytes) of box stored ?
	JL	STORE_1_BYTE		; No, store next one.
STORE_BOX_END:
	POP	DI
	POP	CX
	POP	BX
	RET
STORE_BOX ENDP
PAGE
;===============================================================================
; PRINT_BUFFER : PRINT THE BUFFER
;-------------------------------------------------------------------------------
;	INPUT:	PRT_BUF  = BYTES TO BE PRINTED
;		BOW_W	 = BOX WIDTH
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
; DESCRIPTION: Prints BOX_W bytes.
; LOGIC:
; DO for each column in one pattern
;   BEGIN
;   Print one byte from the buffer
;   END
PRINT_BUFFER PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	BX,OFFSET PRT_BUF
	XOR	CX,CX
	MOV	CL,BOX_W
PRINT_1_BUF_COLUMN:
	MOV	AL,[BX] 	; Print one byte
	CALL	PRINT_BYTE
	JC	PRINT_BUFFER_END; If printer error, quit the loop
	INC	BX		; Get next byte
	LOOP	PRINT_1_BUF_COLUMN
PRINT_BUFFER_END:
	POP	CX
	POP	BX
	POP	AX
	RET
PRINT_BUFFER ENDP
PAGE
;===============================================================================
; GET_SCREEN_INFO : GET INFORMATION ABOUT HOW TO READ THE SCREEN.
;-------------------------------------------------------------------------------
;	INPUT:	SCREEN_HEIGHT	  = Number of pixel rows on the screen
;		SCREEN_WIDTH	  = Number of pixel columns on screen
;		CUR_MODE_PTR	  = Offset of the current DISPLAYMODE info rec.
;	OUTPUT: PRINTER
;		SCAN_LINE_MAX_LENGTH = Maximum length of Screen scan line.
;		NB_SCAN_LINES	  = Number of SCAN LINES on the screen
;		CUR_ROW,CUR_COLUMN = Coordinates of the first pixel to be
;					 read on the screen
;		NB_BOXES_PER_PRT_BUF = Number of boxes fitting in the Print
;				       buffer
;	CALLED BY: PRINT_COLOR
;		   PRT_BW_APA
;-------------------------------------------------------------------------------
; DESCRIPTION:
;    1) Determine where to start reading the screen.
;	For non-rotated printing, it should start with the top-left
;	corner pixel.
;	For rotated printing, it should start with the low-left corner
;	pixel.
;    2) Determine the length of a scan line.
;	For non-rotated printing, it is the WIDTH of the screen.
;	For rotated printing, it is the HEIGHT of the screen.
;    3) Determine the number of scan lines on the screen.
;	For non-rotated printing, it is the HEIGHT of the screen divided
;	by the number of boxes fitting in the print buffer.
;	For rotated printing, it is the WIDTH of the screen divided by
;	the number of boxes fitting in the print buffer.
; LOGIC:
; CUR_COLUMN   := 0
; IF printing is sideways
;   THEN
;     CUR_ROW := SCREEN_HEIGHT - 1	  ; Low-left pixel
;     SCAN_LINE_MAX_LENGTH := SCREEN_HEIGHT
;     NB_SCAN_LINES :=	SCREEN_WIDTH / NB_BOXES_PER_PRT_BUF
;   ELSE
;     CUR_ROW := 0			  ; Top-left pixel
;     SCAN_LINE_MAX_LENGTH := SCREEN_WIDTH
;     NB_SCAN_LINES :=	SCREEN_HEIGHT / NB_BOXES_PER_PRT_BUF
GET_SCREEN_INFO PROC NEAR
	PUSH	AX
	PUSH	BX			; Used for DIV
	PUSH	DX			; Used for DIV
	MOV	BX,CUR_MODE_PTR 	; BX := Offset DISPLAYMODE info record
;-------------------------------------------------------------------------------
; Calculate how many printer boxes fit in the print buffer:
;-------------------------------------------------------------------------------
	MOV	AX,8			; Num := 8 bits / Box heigth
	MOV	DL,[BX].BOX_HEIGHT
	DIV	DL
	MOV	NB_BOXES_PER_PRT_BUF,AL
;-------------------------------------------------------------------------------
; Determine where to start reading the screen:
;-------------------------------------------------------------------------------
	MOV	CUR_COLUMN,0		; Reading always start from left of scr
.IF <[BX].PRINT_OPTIONS EQ ROTATE>
.THEN
;-------------------------------------------------------------------------------
; Printing is sideways; screen must be read starting in low-left corner.
;-------------------------------------------------------------------------------
	MOV	AX,SCREEN_HEIGHT
	MOV	SCAN_LINE_MAX_LENGTH,AX ; Scan line length := screen height
	DEC	AX
	MOV	CUR_ROW,AX		; First row := screen height - 1
;-------Calculate the number of scan lines:
	MOV	AX,SCREEN_WIDTH 	; DX AX = Screen width
	CWD				;
	XOR	BX,BX			; BX	= Number of boxes per print buf
	MOV	BL,NB_BOXES_PER_PRT_BUF ;
	DIV	BX			; Screen width / number boxes per buff
	MOV	NB_SCAN_LINES,AX	; Number of scan lines := result
.ELSE
;-------------------------------------------------------------------------------
; Printing is not sideways; screen must be read starting in top-left corner
;-------------------------------------------------------------------------------
	MOV	AX,SCREEN_WIDTH
	MOV	SCAN_LINE_MAX_LENGTH,AX ; Scan line length := screen width
	MOV	CUR_ROW,0		; First row := 0
;-------Calculate the number of scan lines:
	MOV	AX,SCREEN_HEIGHT	; DX AX = Screen height
	CWD				;
	XOR	BX,BX			; BX  = Number of boxes per print buff
	MOV	BL,NB_BOXES_PER_PRT_BUF ;
	DIV	BX			; Screen height/number boxes per buff.
	MOV	NB_SCAN_LINES,AX	; Number of scan lines := result
.ENDIF
	POP	DX
	POP	BX
	POP	AX
	RET
GET_SCREEN_INFO ENDP
PAGE
;===============================================================================
; DET_CUR_SCAN_LNE_LENGTH : Determine where is the last non-blank "scan line
;				column" on the current scan line.
;-------------------------------------------------------------------------------
;     INPUT:  CUR_ROW,
;	      CUR_COLUMN	  = Coordinates of the top pixel of the current
;				    scan line.
;	      XLT_TAB		  = Color translation table
;     OUTPUT: CUR_SCAN_LNE_LENGTH = Number of "columns" of pixels from the
;				    beginning of the scan line up to
;				    the last non-blank pixel.
; DATA	      SCREEN_WIDTH,
; REFERENCED: SCREEN_HEIGHT	  = Dimensions of the screen in pels
;	      SCAN_LINE_MAX_LENGTH= Maximum length of the scan line
;	      ROTATE_SW 	  = ON if printing is sideways
;-------------------------------------------------------------------------------
; DESCRIPTION: Determine where is the last non-blank "column" by reading
; the scan line backwards, one column at a time.
; LOGIC:
; ; Obtain coordinates for the top pixel of the last column on the current
; ; scan line:
; IF printing is sideways
;   THEN
;   CUR_ROW := 0
; ELSE
;   CUR_COLUMN := SCREEN_WIDTH - 1
; CUR_SCAN_LNE_LENGTH := SCAN_LINE_MAX_LENGTH
; ; Read a column of pixels on the scan line until a non-blank is found:
; For each column on the screen
;   CALL FILL_BUFF
; ; Check if PRT_BUF is empty
;   IF buffer is empty
;     THEN DEC	CUR_SCAN_LNE_LENGTH
;	   ; Get next column
;	   IF printing sideways THEN DEC CUR_ROW
;				ELSE DEC CUR_COLUMN
;   ELSE quit the loop
DET_CUR_SCAN_LNE_LENGTH PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	CUR_COLUMN
	PUSH	CUR_ROW
	MOV	BX,OFFSET XLT_TAB	; BX := Offset of XLT_TAB
;-------------------------------------------------------------------------------
; Obtain coordinates of the top pixel for the last column of the current
; scan line:
;-------------------------------------------------------------------------------
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				; then,
	  MOV	  CUR_ROW,0		;   CUR_ROW := 0
       .ELSE				; else,
	  MOV	  CX,SCREEN_WIDTH	;   CUR_COLUMN := SCREEN_WIDTH - 1
	  DEC	  CX			;
	  MOV	  CUR_COLUMN,CX 	;
       .ENDIF
;-------------------------------------------------------------------------------
; Read the scan line backwards "column" by "column" until a non-blank is found:
;-------------------------------------------------------------------------------
	MOV	CX,SCAN_LINE_MAX_LENGTH ; CX := current length
;-------For each "column"
CHECK_1_COLUMN:
	MOV	SI,CUR_ROW		; Save coordinates of the column
	MOV	DI,CUR_COLUMN		; in SI, DI
	XOR	DL,DL			; DL := Number of pixels verified in
					;	  one "column"
;-------For each pixel within that "column"
CHECK_1_PIXEL:
	CALL	READ_DOT		; AL := Index into translation table
	XLAT	XLT_TAB 		; AL := Band mask or Intensity
;-------Check if pixel will map to an empty box:
       .IF <DS:[BP].PRINTER_TYPE EQ BLACK_WHITE> ; If BLACK AND WHITE printer
       .THEN				; then, check for intensity of white
	  CMP	  AL,WHITE_INT		;      If curent pixel not blank
	  JNE	  DET_LENGTH_END	;      THEN, LEAVE THE LOOP
       .ELSE				; else, COLOR printer
	  OR	  AL,AL 		;      IF Band mask not blank
	  JNZ	  DET_LENGTH_END	;      THEN, LEAVE THE LOOP
       .ENDIF
;-------All pixels so far on this "column" are blank, get next pixel:
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  INC CUR_COLUMN		; then, increment column number
       .ELSE				;
	  INC CUR_ROW			; else, increment row number
       .ENDIF				;
	INC	DL			; One more pixel checked
	CMP	DL,NB_BOXES_PER_PRT_BUF ; All pixels for that column done ?
	JL	CHECK_1_PIXEL		;   No, check next one.
;-------Nothing to print for this column, get next column
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				; then,
	  MOV CUR_COLUMN,DI		;   Restore column number
	  INC CUR_ROW			;   Get next row
       .ELSE				; else,
	  MOV CUR_ROW,SI		;   Restore row number
	  DEC CUR_COLUMN		;   Get next column
       .ENDIF				;
	LOOP CHECK_1_COLUMN		; CX (length) := CX - 1
DET_LENGTH_END:
	MOV	CUR_SCAN_LNE_LENGTH,CX	; Get current length
	POP	CUR_ROW
	POP	CUR_COLUMN
	POP	DI
	POP	SI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET
DET_CUR_SCAN_LNE_LENGTH ENDP
PAGE
;===============================================================================
; SETUP_PRT : SET UP THE PRINTER FOR PRINTING IN GRAPHIC MODE
;-------------------------------------------------------------------------------
;	INPUT: CUR_MODE_PTR = Offset of the DISPLAYMODE information
;			      record for the current mode
;	OUTPUT: PRINTER
;	CALLED BY: PRINT_COLOR
;		   PRT_BW_APA
;-------------------------------------------------------------------------------
; DESCRIPTION: Extract the SETUP escape sequence from the DISPLAYMODE
; information record; Send this escape sequence to the printer.
; LOGIC:
; Number of bytes to print := CUR_MODE_PTR.NUM_SETUP_ESC
; Get the escape sequence:
; SI := CUR_MODE_PTR.SETUP_ESC_PTR
; FOR each byte to be printed
;   PRINT_BYTE [SI]			; Send the byte to the printer
;   INC SI				; Get the next byte
SETUP_PRT PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	BX,CUR_MODE_PTR 	; BX := Displaymode info record.
	XOR	CX,CX			; CX := Number of bytes to print
	MOV	CL,[BX].NUM_SETUP_ESC	;
.IF <CL G 0>				; If there is at least one
.THEN					; byte to be printed:
	MOV	BX,[BX].SETUP_ESC_PTR	; BX := Offset sequence to send
	ADD	BX,BP
SEND_1_SETUP_BYTE:
	MOV	AL,[BX] 		; AL := byte to print
	CALL	PRINT_BYTE		; Send it to the printer
	JC	SETUP_PRT_END		; If printer error, quit the loop
	INC	BX			; Get next byte
	LOOP	SEND_1_SETUP_BYTE
.ENDIF
SETUP_PRT_END:
	POP	CX
	POP	BX
	POP	AX
	RET
SETUP_PRT ENDP
PAGE
;===============================================================================
; RESTORE_PRT : RESTORE THE PRINTER TO ITS INITIAL STATUS
;-------------------------------------------------------------------------------
;	INPUT: CUR_MODE_PTR = Offset of the DISPLAYMODE information
;				 record for the current mode
;	OUTPUT: PRINTER
;	CALLED BY: PRINT_COLOR
;		   PRT_BW_APA
;-------------------------------------------------------------------------------
; DESCRIPTION: Extract the RESTORE escape sequence from the DISPLAYMODE
; information record; Send this escape sequence to the printer.
; LOGIC:
; Number of bytes to print := CUR_MODE_PTR.NUM_RESTORE_ESC
; Get the escape sequence:
; SI := CUR_MODE_PTR.RESTORE_ESC_PTR
; FOR each byte to be printed
;   PRINT_BYTE [SI]			; Send the byte to the printer
;   INC SI				; Get the next byte
RESTORE_PRT PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	BX,CUR_MODE_PTR 	; BX := Displaymode info record.
	XOR	CX,CX			; CX := Number of bytes to print
	MOV	CL,[BX].NUM_RESTORE_ESC
.IF <CL G 0>				; If there is at least one
.THEN					; byte to be printed:
	MOV	BX,[BX].RESTORE_ESC_PTR ; BX := Offset sequence to send
	ADD	BX,BP
SEND_1_RESTORE_BYTE:
	MOV	AL,[BX] 		; AL := byte to print
	CALL	PRINT_BYTE		; Send it to the printer
	JC	RESTORE_PRT_END 	; If printer error, quit the loop
	INC	BX			; Get next byte
	LOOP	SEND_1_RESTORE_BYTE
.ENDIF
RESTORE_PRT_END:
	POP	CX
	POP	BX
	POP	AX
	RET
RESTORE_PRT ENDP
PAGE
;===============================================================================
; NEW_PRT_LINE : INITIALIZE THE PRINTER FOR A GRAPHIC LINE
;-------------------------------------------------------------------------------
;	INPUT: CUR_MODE_PTR = Offset of the DISPLAYMODE information
;				 record for the current mode
;	       CUR_SCAN_LNE_LENGTH = Number of bytes to send to the printer.
;	OUTPUT: PRINTER
;	CALLED BY: PRINT_BAND
;		   PRT_BW_APA
;-------------------------------------------------------------------------------
; DESCRIPTION: Extract the GRAPHICS escape sequence from the DISPLAYMODE
; information record; Send this escape sequence to the printer.
; Then, send the number of bytes that will follow.
; LOGIC:
; Number of bytes to print := CUR_MODE_PTR.NUM_GRAPHICS_ESC
; Get the escape sequence:
; Set up the 2 bytes containing the number of bytes to send in this sequence.
; SI := CUR_MODE_PTR.GRAPHICS_ESC_PTR
; FOR each byte to be printed
;   PRINT_BYTE [SI]			; Send the byte to the printer
;   INC SI				; Get the next byte
; Send the byte count
NEW_PRT_LINE PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	DI
	MOV	BX,CUR_MODE_PTR 	; BX := Displaymode info record.
;-------------------------------------------------------------------------------
; Set up the 2 bytes containing the number of bytes to send in the GRAPHICS seq.
; NOTE: number of bytes to send is "CUR_SCAN_LNE_LENGTH * BOX_W"
;-------------------------------------------------------------------------------
	MOV	AL,BOX_W		;   cur_scan_lne_length *
	CBW				;   printer box width = nb bytes to send
	MUL	CUR_SCAN_LNE_LENGTH	;     (result in DX AX)
;-------AX := Number of bytes to print
	MOV	DI,[BX].LOW_BYT_COUNT_PTR; DI := Offset of LOW byte of
	ADD	DI,BP			;	 byte count
	MOV	[DI],AL 		; Store low byte
	MOV	DI,[BX].HGH_BYT_COUNT_PTR; DI := Offset of HIGH byte of
	ADD	DI,BP			;	 byte count
	MOV	[DI],AH 		; Store high byte
;-------------------------------------------------------------------------------
; Send the GRAPHICS escape sequence to the printer:
;-------------------------------------------------------------------------------
	XOR	CX,CX				; CX := Length of the escape seq
	MOV	CL,[BX].NUM_GRAPHICS_ESC
	MOV	BX,[BX].GRAPHICS_ESC_PTR	; BX := Offset sequence to send
	ADD	BX,BP
SEND_1_GRAPHICS_BYTE:
	MOV	AL,[BX] 		; AL := byte to print
	CALL	PRINT_BYTE		; Send it to the printer
	JC	NEW_PRT_LINE_ENDP	; If printer error, quit the loop
	INC	BX			; Get next byte
	LOOP	SEND_1_GRAPHICS_BYTE
NEW_PRT_LINE_ENDP:
	POP	DI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET
NEW_PRT_LINE ENDP
PAGE
;===============================================================================
; PRINT_BYTE : SEND A BYTE TO THE PRINTER AT LPT1
;-------------------------------------------------------------------------------
;	INPUT:	AL		= Byte to be printed
;	OUTPUT: PRINTER
;		ERROR_CODE	= PRINTER_ERROR if an error is detected.
;		Carry flag is set in case of error.
;-------------------------------------------------------------------------------
PRINT_BYTE PROC    NEAR
	PUSH	AX
	PUSH	DX
	MOV	DX,0000 	; PRINTER NUMBER
	MOV	AH,00		; REQUEST PRINT
	INT	17H		; CALL BIOS : SEND THE CHARACTER
	AND	AH,00101001B	; Test error code returned in AH for
				;   "Out of paper", "I/O error" and "Time-out".
	JNZ	PRINT_BYTE_ERROR; Set the error code if error
	JMP	SHORT PRINT_BYTE_END ; else, return normally
PRINT_BYTE_ERROR:
	MOV	ERROR_CODE,PRINTER_ERROR
	STC			; Set the carry flag to indicate ERROR
PRINT_BYTE_END:
	POP	DX
	POP	AX
	RET
PRINT_BYTE ENDP
PAGE
;===============================================================================
; READ_DOT: READ A PIXEL - RETURN A COLOR TRANSLATION TABLE INDEX
;-------------------------------------------------------------------------------
;	INPUT:	CUR_MODE   = Current video mode.
;		CUR_ROW,
;		CUR_COLUMN = Coordinates of the pixel to be read.
;		CUR_PAGE   = Active page number
;	OUTPUT: AL	   = Index into COLOR TRANSLATION TABLE.
;	DEPENDENCIES : COLOR TRANSLATION TABLE entries must be bytes
;-------------------------------------------------------------------------------
; DESCRIPTION: Use VIDEO BIOS INTERRUPT 10H "READ DOT CALL".
; Depending on the video hardware, the dot returned by BIOS has
; different meanings.
; With an EGA it is an index into the Palette registers,
; With a CGA it is a number from 0 to 3,  mapping to a specific color
; depending on the background color and the color palette currently
; selected.
; The Color Translation table has been set up to hold the correct color
; mapping for any "dot" in any mode.  Therefore, the dot number returned
; by INT 10H can be used with any mode as a direct index within that
; table.
; With APA Monochrome mode 0FH there are 4 different dots: white,
; blinking white, high-intensity white, and black.
; For mode 0FH, the dot returned by interrupt 10 "read dot" call is a byte
; where only bits 0 and 2 are significant.  These 2 bits must be appended
; together in order to obtain a binary number (from 0 to 3) that will be used
; as an index in the Color Translation table.
; For mode 11H, the dot is either 0 (for background color) or 7 (for the
; foreground color) only the LSB is returned.  That is, we return either
; 0 or 1.
; LOGIC:
; Call VIDEO BIOS "READ DOT"
; IF CUR_MODE = 0FH
; THEN
;   Append bits 1 and 3.
; IF CUR_MODE = 11H
; THEN
;   Wipe out bits 1 and 2.
READ_DOT PROC NEAR
	PUSH	BX			; Save registers
	PUSH	CX
	PUSH	DX
	MOV	BH,CUR_PAGE
	MOV	DX,CUR_ROW
	MOV	CX,CUR_COLUMN
	MOV	AH,READ_DOT_CALL
	INT	10H			; Call BIOS: AL <-- Dot read
	CMP	CUR_MODE,0FH		; Is it Mode 0fH ?
	JNE	MODE_11H?		; No, look for mode 11h.
;-------Mode 0Fh is the current mode:
;-------Convert bits 2 and 0 into a 2 bit number:
	MOV	BL,AL			; BL := AL = "Pixel read"
	AND	BL,00000100B		; Wipe off all bits but bit 2 in BL
	AND	AL,00000001B		; Wipe off all bits but bit 0 in AL
	SHR	BL,1			;  Move bit 2 to bit 1 in BL
	OR	AL,BL			;  Append bit 1 and bit 0
	JMP	SHORT READ_DOT_END	;  Quit.
MODE_11H?:
	CMP	CUR_MODE,11H		; Is it Mode 0fH ?
	JNE	READ_DOT_END		; No, quit
;-------Mode 11H is the current mode:
	AND	AL,00000001B		; Keep only the Least significant bit
READ_DOT_END:
	POP	DX			; Restore registers
	POP	CX
	POP	BX
	RET
READ_DOT ENDP
