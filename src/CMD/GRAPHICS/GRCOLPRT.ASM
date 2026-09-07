	PAGE	,132
	TITLE	DOS GRAPHICS Command  -	Color printing modules
;; DOS - GRAPHICS Command
;; (c) Copyright 1988 Microsoft
;; File Name:  GRCOLPRT.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the code for printing a screen (text and graphics)
;;	 on a COLOR printer.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	PRINT_COLOR
;;	  SCAN_FOR_BANDS_APA
;;	  SCAN_FOR_BANDS_TXT
;;	  PRINT_BAND_APA
;;	  PRINT_BAND_TXT
;;	  SET_CURSOR
;;	  SET_COLOR_BAND
;;	  INIT_BLACK_BOX
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
;;	 Refer to GRAPHICS.ASM
PAGE
CODE	SEGMENT PUBLIC 'CODE'
	ASSUME		CS:CODE,DS:CODE
	PUBLIC	PRINT_MODULE_START     ;; Color modules public
	PUBLIC	PRINT_COLOR	       ;;  procedures
	PUBLIC	LEN_OF_COLOR_MODULES   ;;
.XLIST					;
INCLUDE GRCTRL.STR			; Stuctures needed
INCLUDE GRSHAR.STR			;  for both set of print modules
INCLUDE GRPATTRN.STR			;
INCLUDE GRCTRL.EXT			; Externals from PRT_SCR control module
INCLUDE STRUC.INC			;
.LIST					;
;; PRINT_COLOR : PRINT TEXT AND APA MODE SCREEN ON A COLOR PRINTER
;-------------------------------------------------------------------------------
;	INPUT:	BP	 = Offset of the shared data area
;		XLT_TAB  = Color translation table
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
;; Description:
;;   Main control module for printing of text and graphics
;;   on color printers.
;;   Calls either the text or graphics mode routine.
;; Called By:
;;   PRINT_SCREEN
;; External Calls:
;;   LOC_MODE_PRT_INFO, PRINT_COLOR_APA, PRINT_COLOR_TXT
;; Logic:
;;   IF MODE_TYPE = TXT
;;     THEN CALL PRINT_COLOR_TXT
;;   ELSE (MODE_TYPE = APA)
;;     CALL LOC_MODE_PRT_INFO	 ; Get DISPLAYMODE record from the SHARED AREA
;;     CALL PRINT_COLOR_APA
;;   RETURN
PRINT_MODULE_START  LABEL BYTE
PRINT_COLOR	PROC NEAR
	JMP	SHORT PRINT_COLOR_BEGIN
WHITE_BOX	DB	0,0,0,0 ; Print boxes for APA mode
BLACK_BOX	DB	?,?,?,? ;  NOTE: 1 print box = 1 screen pixel
				;   only BOX_W bytes are used out of these 2
				;    boxes.
REQ_BAND_MASK	DB	?	; Mask = "All color bands needed for the current
				;	   print line".
PRINT_COLOR_BEGIN:
.IF <MODE_TYPE EQ TXT>
.THEN
;-------------------------------------------------------------------------------
; The screen is in a text mode:
;-------------------------------------------------------------------------------
  CALL PRINT_COLOR_TXT			; Print a text screen on a color printer
.ELSE
;-------------------------------------------------------------------------------
; The screen is in All Points Addressable mode:
; Locate and extract printer DISPLAYMODE information from
; the shared data area.
;-------------------------------------------------------------------------------
	CALL	LOC_MODE_PRT_INFO	; Get printer info related to curr. mode
;-------Test if DISPLAYMODE info record was found:
       .IF <ERROR_CODE EQ DISPLAYMODE_INFO_NOT_FOUND>
       .THEN
	  MOV	  ERROR_CODE,UNABLE_TO_PRINT ; IF no record found,
	  JMP	  SHORT PRINT_COLOR_END      ; then, return error code
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
	  JMP	  SHORT PRINT_COLOR_END      ;	     and quit
       .ENDIF
;-------Get the Print Orientation from the DISPLAYMODE info record
       .IF <[BX].PRINT_OPTIONS EQ ROTATE>; If printing sideways
       .THEN				;  then:
	  MOV	  ROTATE_SW,ON		;    Rotate switch := "ON"
       .ENDIF
  CALL PRINT_COLOR_APA			; Print APA screen on a color printer
.ENDIF
PRINT_COLOR_END:
	RET
PRINT_COLOR ENDP
PAGE
;===============================================================================
; PRINT_COLOR_TXT: PRINT A TEXT MODE SCREEN ON A COLOR PRINTER
;-------------------------------------------------------------------------------
;	INPUT:	BP		     = Offset of the shared data area
;		XLT_TAB 	     = Color translation table
;		SCREEN_WIDTH	     = Maximum length of Screen scan line.
;		SCREEN_HEIGHT	     = Number of SCAN LINES on the screen
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
; DESCRIPTION: The screen is read and printed line by line; character by
; character.
; Each line is first scanned in order to determine what colors are present on
; it and what printer bands will be needed to approximate these colors.
; For each printer color band needed for the current line, this screen line
; is READ AGAIN character by character; If the color of the
; current character must use the current color band to be
; approximated; then, the character is printed.
; LOGIC :
; Save current coordinates of the cursor.
; Initialize the cursor to the first character to be read  (Top-left of screen)
; FOR each row on the screen (SCREEN_HEIGHT)
;   BEGIN
;   CALL SCAN_FOR_BANDS_TXT(CUR_ROW,CUR_COLUMN,REQ_BAND_MASK)
;   CUR_BAND_MASK := 01H
;   IF REQ_BAND_MASK <> 0 THEN
;	DO 8 TIMES
;	 IF (REQ_BAND_MASK AND CUR_BAND_MASK)=1 THEN
;	    CALL PRINT_BAND_TXT(CUR_ROW,CUR_COLUMN,CUR_BAND_MASK)
;	    CALL PRINT_BYTE(CARRIAGE_RETURN)
;	  ENDIF
;	  Shift CUR_BAND_MASK one bit left
;	ENDDO
;	CALL PRINT_BYTE(LINE_FEED)
;   ENDIF
;   CUR_COLUMN := 0		    ; Get next row coordinates
;   CUR_ROW    := CUR_ROW + 1
;   END ; FOR each row on the screen
; Restore initial coordinates of the cursor
PRINT_COLOR_TXT PROC
	PUSH	BX
	PUSH	CX
	PUSH	DX
;-------Save coordinates of the cursor on the stack:
	MOV	AH,READ_CURSOR_CALL  ; Read position of the cursor on the screen
	MOV	BH,CUR_PAGE	     ;	for the current page
	INT	10H		     ; Call BIOS
	PUSH	DX		     ; DH := Row number, DL := Column number
				     ; CX := Top line and bottom line for cursor
				     ;	      (not needed)
;-------Initialize the cursor to the first character to be read
	MOV	CUR_ROW,0	     ; cursor = position (0,0) on the screen
	MOV	CUR_COLUMN,0	     ;	(top-left corner)
	CALL	SET_CURSOR
	MOV	CX,SCREEN_HEIGHT     ; CX := Number of rows on the screen
;-------------------------------------------------------------------------------
; FOR EACH ROW ON THE SCREEN:
;-------------------------------------------------------------------------------
PRINT_1_TEXT_LINE:
	CALL	SCAN_FOR_BANDS_TXT	; REQ_BAND_MASK := Print bands needed
					;  for this line
	MOV	DL,01H			; DL :="Current Band printed" mask
	; NOTE: The COLORSELECT records are stored sequentially in the
	; Shared Data area. The band mask 00000001 corresponds to the first
	; record, 00000010 to the second, etc.
	; The COLORSELECT record indicates: "How to select the color band"
	; on the printer (It contains the bytes that must be sent to the printer
	MOV	BX,DS:[BP].COLORSELECT_PTR; BX := relative offset of COLORSELECT
	ADD	BX,BP			; BX := absolute offset of COLORSELECT
	PUSH	CX			; Save row counter
	MOV	CX,8			; For up to the maximum number of print
					;  bands with this printer
	;-----------------------------------------------------------------------
	; FOR each Color Band available with the ribbon installed on the printer
	;-----------------------------------------------------------------------
	PRINT_1_COLOR_BAND_TXT: 	  ; Do one pass of the printer head:
	 .IF <BIT REQ_BAND_MASK AND DL>   ; IF this color band is needed
	 .THEN				  ;  by any character on the line
	    CALL SET_COLOR_BAND 	  ; then, select the color band
	    CALL PRINT_BAND_TXT 	  ;    and do one Print Pass for it.
	   .IF	<BIT ERROR_CODE NZ PRINTER_ERROR>
	   .THEN			  ; A printer error occurred:
	      POP     CX		  ;   Restore the line counter
	      JMP     PRINT_COLOR_TXT_END ;    and quit.
	   .ENDIF
	    MOV     AL,CR		  ;    Print a carriage return
	    CALL    PRINT_BYTE
	   .IF	C
	   .THEN			  ; A printer error occurred:
	      POP     CX		  ;   Restore the line counter
	      JMP     PRINT_COLOR_TXT_END ;    and quit.
	   .ENDIF			  ; ENDIF printer error
	 .ENDIF 			  ; ENDIF this color band is needed
	  SHL	  DL,1			  ; Get next Color Band mask
					  ; [BX] := Next COLORSELECT record:
	  MOV	  AL,[BX].NUM_SELECT_ESC  ;	skip the escape bytes
	  XOR	  AH,AH 		  ;
	  ADD	  BX,AX 		  ;
	  INC	  BX			  ;	skip the NUM_SELECT_ESC field
	LOOP	PRINT_1_COLOR_BAND_TXT
	POP	CX			  ; Restore row counter
;-----Print a line feed:
	MOV	AL,LF
	CALL	PRINT_BYTE		; Send the LF
	JC	PRINT_COLOR_TXT_END	; If printer error, quit
;-------Get coordinates of the first character in the next scan line:
	INC	CUR_ROW 		;   CUR_ROW + 1
	MOV	CUR_COLUMN,0		;   CUR_COLUMN := 0
;-------Point CURSOR to first character in the next scan line:
	CALL	SET_CURSOR
	LOOP	PRINT_1_TEXT_LINE	; Print next scan line
;-------Restore CURSOR to its original location (saved on the stack)
PRINT_COLOR_TXT_END:
	POP	DX			; DH := Row number, DL := Column number
	MOV	CL,DH
	MOV	CUR_ROW,CX		; CUR_ROW := Original row number
	MOV	CL,DL
	MOV	CUR_COLUMN,CX		; CUR_COLUMN := Original column number
	CALL	SET_CURSOR		; Set the cursor back there
	POP	DX
	POP	CX
	POP	BX
	RET
PRINT_COLOR_TXT ENDP
PAGE
;===============================================================================
; SCAN_FOR_BANDS_TEXT: DETERMINE WHAT PRINTER COLOR BANDS ARE NEEDED FOR
;			PRINTING THE COLORS ON THE CURRENT SCREEN LINE.
;-------------------------------------------------------------------------------
; INPUT:  CUR_ROW	      = row to start scanning
;	  CUR_COLUMN	      = column to start scanning
;	  ROTATE_SW	      = ON if printing is sideways
; OUTPUT: REQ_BAND_MASK
; DATA STRUCTURE REFERENCED:
;	  XLT_TAB	     = Color translation table
;-------------------------------------------------------------------------------
; DESCRIPTION: Read all characters on the current line from left to right.
; For each character, extract its band mask from the color translation table.
; Add the band mask required for this character to the "Required Bands" mask.
; LOGIC :
; Save current coordinates
; DO (SCREEN_WIDTH) TIMES
;   Read a character
;   Get its Band Mask from the color translation table in AL
;   OR REQ_BAND_MASK,AL 	; Add its band mask to the "Required bands" mask
;   ; Get coordinates of the next character:
;   INC CUR_COLUMN
; Restore initial coordinates
SCAN_FOR_BANDS_TXT PROC NEAR
	PUSH	CUR_ROW 		; Save coordinates
	PUSH	CUR_COLUMN
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	REQ_BAND_MASK,0 	; No Color bands needed so far...
	MOV	CX,SCREEN_WIDTH 	; For each character on the screen row
;-------------------------------------------------------------------------------
; FOR each character on the current scan line:
;-------------------------------------------------------------------------------
SCAN_1_CHAR:
;-------Read the character at the current cursor position
	CALL	SET_CURSOR		; Set cursor at character to be read
	MOV	AH,READ_CHAR_CALL	; Read one character
	MOV	BH,CUR_PAGE		;  at CUR_PAGE, CUR_COLUMN and CUR_ROW
	INT	10H			; Call BIOS
					; AL:=Character read, AH:=Byte attribute
	AND	AH,00001111B		; AH := Foreground color attribute
	XCHG	AL,AH			; AL := AH, used as index in the XLT_TAB
	MOV	BX,OFFSET XLT_TAB	; BX := Offset of translation table
	XLAT	XLT_TAB 		; AL  = Band mask
;-------Obtain what Print bands are required to print the color of this char:
	OR	REQ_BAND_MASK,AL
	INC	CUR_COLUMN		; Get coordinates of next character
	LOOP	SCAN_1_CHAR		; Scan next character
	POP	CX
	POP	BX
	POP	AX
	POP	CUR_COLUMN		; Restore initial coordinates
	POP	CUR_ROW
	RET
SCAN_FOR_BANDS_TXT ENDP
PAGE
;;   PRINT_BAND_TXT: PRINT ALL CHARACTERS ON THE CURRENT LINE THAT ARE THE SAME
;;		     COLOR AS THE CURRENT PRINT BAND.
;-------------------------------------------------------------------------------
;  INPUT:  CUR_ROW,
;	   CUR_COLUMN	  : Coordinates of the first character to be read in
;			    the current scan line.
;	   DL		  : Band mask indicating what print band to use
;			    for this print pass.
;	   SCAN_LINE_LENGTH: Length of the current scan line.
;  OUTPUT: PRINTER
;-------------------------------------------------------------------------------
; LOGIC:
;    DO (SCAN_LINE_LENGTH) TIMES
;      CALL BIOS INT 10H Read Character - returns CHAR, COLOR_NUM
;      IF (CUR_BAND_MASK AND XLAT_TAB[COLOR_NUM])=1
;      THEN IF Background color is same as Foreground color
;	    THEN
;	      CALL PRINT_BYTE(SOLID_BOX)
;	    ELSE
;	      CALL PRINT_BYTE(CHAR)
;      ELSE
;	 CALL PRINT_BYTE(blank)
;      Get coordinates of the next character
PRINT_BAND_TXT PROC
SOLID_BOX	EQU	219	; ASCII Code for printing a solid box
BLANK		EQU	32	; ASCII code for printing a space
	PUSH	CUR_COLUMN	; Save column number
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	CX,SCREEN_WIDTH ; CX := Number of character on one screen row
;===============================================================================
; FOR each character on the current row:
;===============================================================================
PRINT_1_CHAR:
;-------Read the character at the current cursor position
	CALL	SET_CURSOR		; Set cursor at character to be read
	MOV	AH,READ_CHAR_CALL	; Read one character
	MOV	BH,CUR_PAGE		;  at CUR_PAGE, CUR_COLUMN and CUR_ROW
	INT	10H			; Call BIOS
					; AL:=Character read, AH:=Byte attribute
	MOV	CUR_CHAR,AL
	MOV	DH,AH			; DH := Byte attribute
	AND	DH,11110000B		; DH := Background color
	SHR	DH,1			; DH := Background color right justified
	SHR	DH,1
	SHR	DH,1
	SHR	DH,1
	AND	AH,00001111B		; AH := Foreground color right justified
;-------Test if this character should be printed (need color of the current band
	MOV	AL,AH			; AL:=color used as index in the XLT_TAB
	MOV	BX,OFFSET XLT_TAB	; BX := Offset of translation table
	XLAT	XLT_TAB 		; AL := Band mask (DL=current band mask)
       .IF     <BIT AL AND DL>		;If needs this band to print the color
       .THEN				; of this character
	 .IF	 <AH EQ DH>		; then: when foreground = background
	 .THEN				;	send a solid box
	    MOV     AL,SOLID_BOX	;
	 .ELSE				;	when foreground <> background
	    MOV     AL,CUR_CHAR 	;	send the character
	 .ENDIF 			; Endif foreground = background
       .ELSE				; else: send a blank
	  MOV	  AL,BLANK		;
       .ENDIF				; Endif color band needed
	CALL	PRINT_BYTE		; Print the byte
	JC	PRINT_BAND_TXT_END	; If printer error occurred: QUIT
	INC CUR_COLUMN			; Else, Get next column; keep going
	LOOP	PRINT_1_CHAR
PRINT_BAND_TXT_END:
	POP	CX
	POP	BX
	POP	AX
	POP	CUR_COLUMN		; Restore column number
	RET
CUR_CHAR	DB ?
PRINT_BAND_TXT ENDP
PAGE
;===============================================================================
; PRINT_COLOR_APA: PRINT AN APA MODE SCREEN ON A COLOR PRINTER
;-------------------------------------------------------------------------------
;	INPUT:	BP	 = Offset of the shared data area
;		XLT_TAB  = Color translation table
;		CUR_MODE_PTR = Coordinates of current DISPLAYMODE info.
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
; DESCRIPTION: Each pixel on the screen is printed as a "box" of dots on the
; printer. For a screen pixel of a given color, the best color approximation
; is chosen among the color available on the printer.
; The printer colors are obtained by selecting a print band. A few more printer
; color are obtained by printing twice (or more times) with different color
; bands.
; For example, let's say we have a ribbon on the printer with a YELLOW CYAN
; MAGENTA ribbon and we read a GREEN pixel on the screen.
;   We first determine what "box" size will be used to represent this pixel.
;   Let's say it's a 3x2 box (this is obtained from the DISPLAYMODE record)
;   In all cases, we will print this pixel as a 3x2 box of printer dots.
;   That is, we will print 6 dots on the printer for one on the screen.
;   We do not use any kind of patterns (e,g,. printing only 2 dots out of 6)
;   for printing on the color printer. A screen pixel is either printed
;   as a "full" box of printer dots or not printed at all (e,g,. if it's white).
;   Now, from the COLORPRINT records, we know all the colors availables on the
;   printer, and what print bands must be used (or overlaid) in order to
;   obtain them.
;   So, we consult these COLORPRINT records one by one comparing how close
;   the color of each of them is to our GREEN pixel. (the colors for our pixel
;   AND for the printer color are both indicated in terms of RGB values)
;   WE PICK THE CLOSEST PRINTER COLOR.
;   To conclude, our GREEN pixel will be printed by first selecting the YELLOW
;   band, then sending to the printer a "box".  Then, the BLUE band is selected
;   and the "box" is sent again.
; This process is carried line by line.
; For each line, we first read each pixel to see what color bands are going
; to be needed for this line.
; Then, we loop for each band available on the printer.
; IF the current line needs the current printer band (i.e.,if any pixel on
;  the line needs this color band in order to achieve its color.
; THEN, we select this color band (we know how to do it from the COLORSELECT
;	record in the Shared Data area)
;	AND we must read the line again; for each pixel that needs the current
;	band  a "box" is sent to the printer.
; LOGIC :
;     CALL INIT_BLACK_BOX		; Initialize a print box
;     CALL GET_SCREEN_INFO
;     CALL SETUP_PRT
;     DO (NB_SCAN_LINES) TIMES
;	  CALL DET_CUR_SCAN_LNE_LENGTH
;	  IF CUR_SCAN_LNE_LENGTH NE 0 THEN
;	    CALL SCAN_FOR_BANDS_APA(CUR_ROW,CUR_COLUMN,REQ_BAND_MASK)
;	    CUR_BAND_MASK := 01H
;	    IF REQ_BAND_MASK <> 0 THEN
;	       DO 8 TIMES
;		  IF (REQ_BAND_MASK AND CUR_BAND_MASK)=1 THEN
;		     CALL NEW_PRT_LINE
;		     CALL PRINT_BAND_APA(CUR_ROW,CUR_COLUMN,CUR_BAND_MASK)
;		     CALL PRINT_BYTE(CARRIAGE_RETURN)
;		  ENDIF
;		  Shift CUR_BAND_MASK one bit left
;	       ENDDO
;	    ENDIF ; Should make a print pass for this color band
;	    CALL PRINT_BYTE(LINE_FEED)
;	  ENDIF ; Current scan line is not empty
;	  IF rotated print THEN
;	     CUR_COLUMN := CUR_COLUMN - BOXES_PER_PRT_BUF
;	     CUR_ROW := SAVE_START_ROW
;	  ELSE
;	     CUR_ROW := CUR_ROW + BOXES_PER_PRT_BUF
;	     CUR_COLUMN := SAVE_START_COLUMN
;	  ENDIF
;     ENDDO ; Number of Scan lines
;     CALL RESTORE_PRT
PRINT_COLOR_APA PROC
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
;-------Initialize print box (A "box" represents one screen pel on the printer)
	CALL INIT_BLACK_BOX
;-------------------------------------------------------------------------------
;  Determine where to start reading the screen:
;    If printing sideways, start in LOW LEFT corner.
;    If normal printing, start in TOP LEFT corner.
;  Determine the maximum length for a scan line:
;    If printing sideways, it is the height of the screen.
;    For normal printing, it is the width of the screen.
;  Determine the number of scan lines on the screen.
;-------------------------------------------------------------------------------
	CALL	GET_SCREEN_INFO 	; Get info. about how to read the screen
	CALL	SETUP_PRT		; Set up the printer (Line spacing, etc)
       .IF  <BIT ERROR_CODE NZ PRINTER_ERROR>
       .THEN				; A printer error occurred: quit
	  JMP	  PRINT_COLOR_APA_END	;
       .ENDIF
	MOV	CX,NB_SCAN_LINES
;----------------------------------------------------------------------------
; FOR EACH SCAN LINE ON THE SCREEN (and each print line):
;----------------------------------------------------------------------------
PRINT_SCAN_LINE:
	CALL	DET_CUR_SCAN_LNE_LENGTH ; Determine length of the scan line
       .IF <CUR_SCAN_LNE_LENGTH NE 0>	; If line is not empty
       .THEN
	  CALL	  SCAN_FOR_BANDS_APA	  ; REQ_BAND_MASK := Mask for what print
					  ;  bands are needed.
	  MOV	  DL,01H		  ; DL := "Current Band to be printed"
	  MOV	  BX,DS:[BP].COLORSELECT_PTR; BX := Offset of COLORSELECT record
	  ADD	  BX,BP 		  ;	("How to select the color band")
	  PUSH	  CX			  ; Save scan line counter
	  MOV	  CX,8			  ; For up to the maximum number of prin
					  ;  bands with this printer
	  ;---------------------------------------------------------------------
	  ; FOR each Color Band needed:
	  ;---------------------------------------------------------------------
       PRINT_1_COLOR_BAND_APA:		  ; Only if this color band is needed:
	   .IF <BIT REQ_BAND_MASK AND DL> ;   Do one pass of the printer head
	   .THEN			  ;
	      CALL    SET_COLOR_BAND	  ; Select the color band on the printer
	      CALL    NEW_PRT_LINE	  ; Send escape sequence to the printer
					  ;  for starting a new graphics line
	     .IF  <BIT ERROR_CODE NZ PRINTER_ERROR>
	     .THEN			  ; A printer error occurred:
		POP   CX		  ; Restore the line counter and
		JMP   PRINT_COLOR_APA_END ;  return
	     .ENDIF			  ; Endif printer error occurred
	      CALL PRINT_BAND_APA	  ; Do one Print Pass for current band
	      MOV     AL,CR		  ;   Print a carriage return
	      CALL    PRINT_BYTE
	     .IF      C 		  ; If a printer error occurred
	     .THEN
		POP   CX		  ; Restore the line counter and
		JMP   PRINT_COLOR_APA_END ;  return
	     .ENDIF			  ; End if printer error occurred
	   .ENDIF			  ; End if this color band is needed
	    SHL     DL,1		  ; Get next Color Band mask
					  ; Locate next COLORSELECT record:
	    MOV     AL,[BX].NUM_SELECT_ESC;  skip the escape bytes
	    XOR     AH,AH
	    ADD     BX,AX
	    INC     BX			  ;  skip the NUM_SELECT_ESC field
	  LOOP	  PRINT_1_COLOR_BAND_APA
	  POP	  CX			  ; Restore scan line counter
       .ENDIF ; Scan line length <> 0
;-----Print a line feed:
	MOV	AL,LF
	CALL	PRINT_BYTE
	JC	PRINT_COLOR_APA_END	  ; If a printer error occurred: quit
;-------Get coordinates of next scan line:
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				; then:
	  MOV	  AL,NB_BOXES_PER_PRT_BUF;  AX := Numbers of pels read on row
	  CBW				;
	  ADD	  CUR_COLUMN,AX 	;   CUR_COLUMN + Number of pels read
	  MOV	  AX,SCREEN_HEIGHT	;   CUR_ROW := SCREEN_HEIGHT - 1
	  DEC	  AX			;
	  MOV	  CUR_ROW,AX		;
       .ELSE				; else, printing NOT rotated:
	  MOV	  AL,NB_BOXES_PER_PRT_BUF ; AX := Number of pels read on column
	  CBW				;
	  ADD	  CUR_ROW,AX		;   CUR_ROW + Number of pels read
	  MOV	  CUR_COLUMN,0		;   CUR_COLUMN := 0
       .ENDIF				; End if printing sideways
	LOOP	PRINT_SCAN_LINE 	;
;-------------------------------------------------------------------------------
; Restore the printer (send a Page Eject, etc.)
;-------------------------------------------------------------------------------
	CALL	RESTORE_PRT
PRINT_COLOR_APA_END:
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET
PRINT_COLOR_APA ENDP
PAGE
;;   SCAN_FOR_BANDS_APA : DETERMINE WHAT PRINT BANDS ARE NEEDED FOR THE CURRENT
;;			  PRINT PASS.
;;------------------------------------------------------------------------------
; INPUT:  CUR_ROW	      : row to start scanning	(word)
;	  CUR_COLUMN	      : column to start scanning (word)
;	  CUR_SCAN_LNE_LENGTH : length of the current scan line (word)
;	  ROTATE_SW	      = ON if printing is sideways
; OUTPUT: REQ_BAND_MASK       : band mask for required bands (byte)
;;------------------------------------------------------------------------------
;; Data Structures Referenced:
;;   Shared Data Area
;;   Print Info
;;   Color Translate Table
;; Description:
;;   Read all the dots required for one print line to determine
;;   the print bands required.	The print line corresponds to several
;;   screen rows (or columns if rotated printing).  The number of
;;   rows / columns per print line is stored in NB_BOXES_PER_PRT_BUF.
;;   The band information is obtained from the Color Translate Table.
;; Called By:
;;   PRINT_COLOR_APA
;; External Calls:
;;   READ_DOT, BIOS INT 10H
;; Logic:
;;   Save initial coordinates
;;   SAVE_START_COLUMN := CUR_COLUMN
;;   REQ_BAND_MASK := 00H
;;   DO (SCAN_LINE_LENGTH) TIMES
;;	Save coordinates of the "column"
;;	DO (BOXES_PER_PRT_BUF) TIMES
;;	  CALL READ_DOT(IN CUR_ROW,CUR_COLUMN; OUT COLOR_NUM)
;;	   REQ_BAND_MASK := REQ_BAND_MASK OR COLOR_XLAT_TAB[BX]
;;	   IF rotated print THEN
;;	      Increment CUR_COLUMN
;;	   ELSE
;;	      Increment CUR_ROW
;;	   ENDIF
;;	Restore coordinates of the "column"
;;	ENDDO
;;	IF rotated print THEN
;;	   Decrement CUR_ROW
;;	ELSE
;;	   Increment CUR_COLUMN
;;	ENDIF
;;   ENDDO
;;   Restore initial coordinates
;;   RETURN
SCAN_FOR_BANDS_APA PROC NEAR
	PUSH	CUR_ROW
	PUSH	CUR_COLUMN
	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	REQ_BAND_MASK,0 	; No Color bands needed so far...
	MOV	BX,OFFSET XLT_TAB	; BX := Offset of translation table
	MOV	CX,CUR_SCAN_LNE_LENGTH
;===============================================================================
; FOR each column on the current scan line (up to the last non=blank):
;===============================================================================
SCAN_1_COLUMN:
	PUSH	CX			; Save column counter
	PUSH	CUR_ROW 		; Save coordinates of the "column"
	PUSH	CUR_COLUMN
;-------------------------------------------------------------------------------
; For each pixel within the current column of the scan line:
;-------------------------------------------------------------------------------
	XOR	CX,CX			; CX := Number of pixels to read
	MOV	CL,NB_BOXES_PER_PRT_BUF ;   within the current "column"
SCAN_1_PIXEL:
	CALL	READ_DOT		; AL := Index into translation table
	XLAT	XLT_TAB 		; AL := Band mask
	OR	REQ_BAND_MASK,AL	; Add bands required for this pixel
;-------Get coordinates of next pixel:
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  INC CUR_COLUMN		; then, increment column number
       .ELSE				;
	  INC CUR_ROW			; else, increment row number
       .ENDIF				;
	LOOP SCAN_1_PIXEL
	POP	CUR_COLUMN		; Restore coordinates of the "column"
	POP	CUR_ROW 		;
	POP	CX			; Restore column counter
;-------Get coordinates of next "column":
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  DEC CUR_ROW			; then, get row above on screen
       .ELSE				;
	  INC CUR_COLUMN		; else, get column next right
       .ENDIF				;
	LOOP	SCAN_1_COLUMN
	POP	CX
	POP	BX
	POP	AX
	POP	CUR_COLUMN
	POP	CUR_ROW
	RET
SCAN_FOR_BANDS_APA ENDP
PAGE
;;   PRINT_BAND_APA : PRINT ALL DOTS ON CURRENT LINE THAT NEED THE CURRENT BAND
;;		      TO APPROXIMATE THEIR COLOR.
;-------------------------------------------------------------------------------
;  INPUT:  CUR_ROW,
;	   CUR_COLUMN	  : Coordinates of the first pixel to be read in the
;			    current scan line.
;	   DL		  : Band mask indicating what print band to use
;			    for this print pass.
;	   CUR_SCAN_LNE_LENGTH: Length of the current scan line.
;	   ROTATE_SW	   = ON if printing is sideways
;  OUTPUT: PRINTER
;-------------------------------------------------------------------------------
;; Data Structures Referenced:
;;   Shared Data Area
;;   Print Info
;;   Color Translate Table
;; Description:
;;   Print all dots on this print line which need the current
;;   band. The print line corresponds to several
;;   screen rows (or columns if rotated printing).  The number of
;;   rows / columns per print line is stored in NB_BOXES_PER_PRT_BUF.
;;   The band information is obtained from the Color Translate Table.
;; Called By:
;;   PRINT_COLOR_APA
;; External Calls:
;;   READ_DOT, BIOS INT 10H, STORE_BOX, PRT_BUFFER, PRINT_BYTE
;; Logic:
;;   SAVE_START_ROW := CUR_ROW
;;   SAVE_START_COLUMN := CUR_COLUMN
;;   CALL SET_COLOR_BAND	; Select the color for this print pass
;;   DO (SCAN_LINE_LENGTH) TIMES
;;	Save coordinates of the "column"
;;	Clear the print buffer
;;	DO (BOXES_PER_PRT_BUF) TIMES
;;	   CALL READ_DOT(CUR_ROW,CUR_COLUMN,COLOR_NUM)
;;	   IF (CUR_BAND_MASK AND XLAT_TAB[COLOR_NUM])=1 THEN
;;	      CALL STORE_BOX(black box)
;;	   ELSE
;;	      CALL STORE_BOX(white box)
;;	   ENDIF
;;	   IF rotated print THEN
;;	      Decrement CUR_COLUMN
;;	   ELSE
;;	      Increment CUR_ROW
;;	   ENDIF
;;	ENDDO
;;	CALL PRINT_BUFFER
;;	Restore coordinates of the "column"
;;	; Get coordinates of the next "column";
;;	IF rotated print THEN
;;	   Decrement CUR_ROW
;;	   CUR_COLUMN := SAVE_START_COLUMN
;;	ELSE
;;	   Increment CUR_COLUMN
;;	   CUR_ROW := SAVE_START_ROW
;;	ENDIF
;;   ENDDO
;;   RETURN
PRINT_BAND_APA	    PROC NEAR
	PUSH	CUR_ROW 		; Save coordinates
	PUSH	CUR_COLUMN
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	SI
	PUSH	DI
	MOV	BX,OFFSET XLT_TAB	; BX := Offset of translation table
	MOV	CX,CUR_SCAN_LNE_LENGTH
;===============================================================================
; FOR each column on the current scan line (up to the last non=blank):
; (One "column" contains the number of pixels required to fill the Print buffer)
;===============================================================================
PRINT_1_COLUMN:
;-------------------------------------------------------------------------------
; Clear the print buffer "PRT_BUF"
;-------------------------------------------------------------------------------
	XOR	DI,DI		; DI := Number of bytes cleared in the buffer
	XOR	AX,AX
	MOV	AL,BOX_W	; AX := Number of bytes in the print buffer
CLEAR_BUF:			; For each byte in the PRT_BUF:
	MOV	PRT_BUF[DI],0	;    Initialize byte to blanks
	INC	DI		;    One more has been cleared
	CMP	DI,AX		;    All bytes cleared ?
	JL	CLEAR_BUF	;	 No, clear next one.
;-------------------------------------------------------------------------------
; Fill up the print buffer "PRT_BUF"
;-------------------------------------------------------------------------------
	PUSH	CX			; Save column counter
	XOR	CX,CX			; CX := Number of pixels to read
	MOV	CL,NB_BOXES_PER_PRT_BUF ;   within the current "column"
					;    of the scan line
	PUSH	CUR_ROW 		; Save coordinates of the "column"
	PUSH	CUR_COLUMN
; For each pixel within the current column of the scan line:
STORE_1_PIXEL:
	CALL	READ_DOT		; AL := Index into translation table
	XLAT	XLT_TAB 		; AL := Band mask
       .IF <BIT AL AND DL>		; If color of the current pixel needs
       .THEN				;  the current printer band
	  MOV	SI,OFFSET BLACK_BOX	; then, store a box in the
	  CALL STORE_BOX		;	 PRT_BUF
       .ELSE				;
	  MOV	SI,OFFSET WHITE_BOX	;  else, store an empty box
	  CALL STORE_BOX		;	  in the PRT_BUF
       .ENDIF
;-------Get coordinates of next pixel:
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  INC CUR_COLUMN		; then, increment column number
       .ELSE				;
	  INC CUR_ROW			; else, increment row number
       .ENDIF				;
	LOOP STORE_1_PIXEL
	POP	CUR_COLUMN		; Restore coordinates of the "column"
	POP	CUR_ROW 		;
	POP	CX			; Restore column counter
;-------------------------------------------------------------------------------
; Print the PRT_BUF:
;-------------------------------------------------------------------------------
	CALL	PRINT_BUFFER
       .IF  <BIT ERROR_CODE NZ PRINTER_ERROR>
       .THEN				; A printer error occurred: QUIT
	  JMP SHORT PRINT_BAND_APA_END	;
       .ENDIF
;-------------------------------------------------------------------------------
; Get coordinates of next "column":
;-------------------------------------------------------------------------------
       .IF <ROTATE_SW EQ ON>		; If printing sideways
       .THEN				;
	  DEC CUR_ROW			; then, get row above on screen
       .ELSE				;
	  INC CUR_COLUMN		; else, get column next right
       .ENDIF				;
	LOOP	PRINT_1_COLUMN
PRINT_BAND_APA_END:
	POP	DI
	POP	SI
	POP	CX
	POP	BX
	POP	AX
	POP	CUR_COLUMN		; Restore initial coordinates
	POP	CUR_ROW
	RET
PRINT_BAND_APA	ENDP
PAGE
;===============================================================================
; SET_CURSOR : SET THE CURSOR TO CUR_ROW, CUR_COLUMN AND CUR_PAGE
;-------------------------------------------------------------------------------
;	INPUT:	CUR_ROW,
;		CUR_COLUMN  = Coordinates for the cursor (word)
;		CUR_PAGE    = Page for which to set the cursor (byte)
;	OUTPUT: SCREEN
;-------------------------------------------------------------------------------
SET_CURSOR PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	DX
	MOV	DH,BYTE PTR CUR_ROW
	MOV	DL,BYTE PTR CUR_COLUMN
	MOV	BH,CUR_PAGE
	MOV	AH,SET_CURSOR_CALL	; Set cursor request
	INT	10H			; Call BIOS
	POP	DX
	POP	BX
	POP	AX
	RET
SET_CURSOR ENDP
PAGE
;===============================================================================
; SET_COLOR_BAND : SET THE PRINTER TO THE CURRENT COLOR BAND
;-------------------------------------------------------------------------------
;	INPUT: BX	= Offset of current COLORSELECT record in the
;			  Shared data area.
;	       DS:[BP]	= Offset of shared data area
;	OUTPUT: PRINTER
;-------------------------------------------------------------------------------
SET_COLOR_BAND PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
;-------Send the escape sequence for selecting this color band to the printer:
	XOR	CX,CX
	MOV	CL,[BX].NUM_SELECT_ESC	; CX := Number of bytes to send
	ADD	BX,OFFSET SELECT_ESC	; BX := Offset of bytes to send
SEND_1_COLORSELECT_BYTE:
	MOV	AL,[BX] 		; AL := Byte to send to printer
	CALL	PRINT_BYTE		; Send it
	JC	SET_COLOR_BAND_END	; If printer error: return
	INC	BX			; Get next byte
	LOOP	SEND_1_COLORSELECT_BYTE
SET_COLOR_BAND_END:
	POP	CX
	POP	BX
	POP	AX
	RET
SET_COLOR_BAND ENDP
PAGE
;===============================================================================
; INIT_BLACK_BOX: INIT. THE BOX FOR PRINTING APA MODE DOTS ON A COLOR PRINTER.
;-------------------------------------------------------------------------------
;	INPUT:	BOX_W,
;		BOX_H		= Size of the print box for one pixel.
;	OUTPUT: BLACK_BOX	= A box for which all dots are on.
;-------------------------------------------------------------------------------
; DESCRIPTION: Initialize the print box used to print a screen pixel.
; For example,
; with a size of 3x2 the BLACK_BOX will use 3 bytes:
;	  byte1     byte2     byte3
;	(column1) (column2) (column3)
;  bit 7 -->0	       0	 0
;	    0	       0	 0
;	    0	       0	 0
;	    0	       0	 0
;	    0	       0	 0
;	    0	       0	 0
;	    1	       1	 1
;  bit 0 -->1	       1	 1
;-------------------------------------------------------------------------------
INIT_BLACK_BOX PROC NEAR
	PUSH	AX
	PUSH	BX
	PUSH	CX
;-------Build one box column:
	XOR	CX,CX
	MOV	CL,BOX_H	; CX := Height in bits of the print box
	XOR	AL,AL		; AX := Bit mask for creating box column
       .REPEAT			; For height of the box:
	  SHL	  AL,1		;
	  OR	  AL,1		;   Insert one bit in the box column
       .LOOP
;-------------------------------------------------------------------------------
;	AL now contains one box column.
;-------------------------------------------------------------------------------
;-------Replicate this column over all columns of the box.
	XOR	BX,BX		; BX := Index into the BOX
INIT_1_BLACK_COLUMN:
	MOV	BLACK_BOX[BX],AL; Init current column to black box column
	INC	BX		; Get next column
	CMP	BL,BOX_W
	JL	INIT_1_BLACK_COLUMN
	POP	CX
	POP	BX
	POP	AX
	RET
INIT_BLACK_BOX ENDP
INCLUDE GRCOMMON.ASM
LEN_OF_COLOR_MODULES EQU $-PRINT_COLOR
CODE	ENDS
	END
