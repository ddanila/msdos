PAGE	,132
TITLE	ANSI Console device CON$INIT routine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  MODULE_NAME: CON$INIT
;
;  FUNCTION:
;    THIS PROCEDURE PERFORMS ALL NECESSARY INITIALIZATION ROUTINES
;  FOR ANSI.SYS.
;

INCLUDE    ANSI.INC		   ; WGR equates and strucs
.XLIST
INCLUDE    STRUC.INC		   ; WGR structured macros
.LIST

PUBLIC	   CON$INIT		   ; WGR


CODE	SEGMENT  PUBLIC  BYTE
	ASSUME	CS:CODE,DS:CODE

EXTRN	VIDEO_MODE_TABLE:BYTE	       ; WGR
EXTRN	FUNC_INFO:BYTE		       ; WGR
EXTRN	HDWR_FLAG:WORD		       ; WGR
EXTRN	VIDEO_TABLE_MAX:ABS	       ; WGR
EXTRN	SCAN_LINES:BYTE 	       ; WGR
EXTRN	PTRSAV:DWORD		       ; WGR
EXTRN	PARSE_PARM:NEAR 	       ; WGR
EXTRN	ERR2:NEAR		       ; WGR
EXTRN	EXT_16:BYTE		       ; WGR
EXTRN	BRKADR:ABS		       ; WGR
EXTRN	BRKKY:NEAR		       ; WGR
EXTRN	COUT:NEAR		       ; WGR
EXTRN	BASE:WORD		       ; WGR
EXTRN	MODE:BYTE		       ; WGR
EXTRN	MAXCOL:BYTE		       ; WGR
EXTRN	TRANS:ABS		       ; WGR
EXTRN	STATUS:ABS		       ; WGR
EXTRN	EXIT:NEAR		       ; WGR
EXTRN	MAX_SCANS:BYTE		       ; WGR
EXTRN	ROM_INT10:WORD		       ; WGR
EXTRN	INT10_COM:NEAR		       ; WGR
EXTRN	ROM_INT2F:WORD		       ; WGR
EXTRN	INT2F_COM:NEAR		       ; WGR
EXTRN	ABORT:BYTE		       ; WGR
extrn	Display_Loaded_Before_Me:byte  ;AN002;Defined in IOCTL.ASM
extrn	Switch_K:Byte

INCLUDE   ANSIVID.INC		       ; WGR video tables data

CON$INIT:
	LDS	BX,CS:[PTRSAV]	       ; WGR establish addressability to request header
	LDS	SI,[BX].ARG_PTR        ; WGR DS:SI now points to rest of DEVICE=statement
	CALL	PARSE_PARM	       ; WGR parse DEVICE= command line
	JNC	CONT_INIT	       ; WGR no error in parse...continue install
	LDS	BX,CS:[PTRSAV]	       ; WGR prepare to abort install
	XOR	AX,AX		       ; WGR
	MOV	[BX].NUM_UNITS,AL      ; WGR set number of units to zero
	MOV	[BX].END_ADDRESS_O,AX  ; WGR set ending address offset to 0
	MOV	[BX].END_ADDRESS_S,CS  ; WGR set ending address segment to CS
	mov	word ptr [bx].CONFIG_ERRMSG, -1 ;AN004; Let IBMBIO display "Error in CONFIG.SYS..".
	MOV	AX,UNKNOWN_CMD	       ; WGR set error in status
	MOV	WORD PTR [BX].STATUS,AX ; WGR set error status
	JMP	ERR2		       ; WGR prepare to exit

CONT_INIT:			       ; WGR
	PUSH	CS		       ; WGR
	POP	DS		       ; WGR restore DS to ANSI segment
	MOV	AX,ROM_BIOS	       ; WGR
	MOV	ES,AX		       ; WGR DS now points to BIOS data area
	MOV	AH,ES:[KBD_FLAG_3]     ; WGR load AH with KBD_FLAG_3
	.IF  <BIT AH AND EXT16_FLAG> AND   ; WGR see if extended INT16 is loaded
	.IF  <Switch_K EQ OFF>	       ;The user does not want to disable the extended INT 16h
	  MOV	  EXT_16,ON	       ; WGR extended INT16 available, set flag
	.ENDIF			       ; WGR
	CALL	DET_HDWR	       ; WGR procedure to determine video hardware status
	.IF <HDWR_FLAG GE MCGA_ACTIVE> ; WGR if we have EGA or better then..
	  MOV	  AH,ALT_SELECT        ; WGR issue select alternate print..
	  MOV	  BL,ALT_PRT_SC        ; WGR screen routine call..
	  INT	  10H		       ; WGR
	.ENDIF
	CALL	LOAD_INT10	       ; WGR load interrupt 10h handler
	CALL	LOAD_INT2F	       ; WGR load interrupt 2Fh handler
	int	11h
	and	al,00110000b
	cmp	al,00110000b
	jnz	iscolor
	mov	[base],0b000h		;look for bw card
iscolor:
	cmp	al,00010000b		;look for 40 col mode
	ja	setbrk
	mov	[mode],0
	mov	[maxcol],39

setbrk:
	XOR	BX,BX
	MOV	DS,BX
	MOV	BX,BRKADR
	MOV	WORD PTR [BX],OFFSET BRKKY
	MOV	WORD PTR [BX+2],CS

	MOV	BX,29H*4
	MOV	WORD PTR [BX],OFFSET COUT
	MOV	WORD PTR [BX+2],CS

	LDS	BX,CS:[PTRSAV]
	MOV	WORD PTR [BX].TRANS,OFFSET CON$INIT	;SET BREAK ADDRESS
	MOV	[BX].TRANS+2,CS
	JMP	EXIT


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  PROCEDURE_NAME: DET_HDWR
;
;  FUNCTION:
;  THIS CODE DETERMINES WHAT VIDEO HARDWARE IS AVAILABLE.  THIS INFORMATION
;  IS USED TO LOAD APPROPRIATE VIDEO TABLES INTO MEMORY FOR USE IN THE
;  GENERIC IOCTL.
;
;  AT ENTRY:
;
;  AT EXIT:
;     NORMAL: FLAG WORD WILL CONTAIN BITS SET FOR THE APPROPRIATE
;	      TABLES. IN ADDITION, FOR VGA SUPPORT, A FLAG BYTE
;	      WILL CONTAIN THE AVAILABLE SCAN LINE SETTINGS FOR THE
;	      INSTALLED ADAPTER.
;	      VIDEO TABLES WILL BE LOADED INTO MEMORY REFLECTING
;	      APPLICABLE MODE SETTINGS AND SCREEN LINE LENGTHS.
;
;     ERROR:  N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DET_HDWR  PROC	  NEAR
	  MOV	 AH,GET_SYS_ID		     ; see if this is a Convertible
	  INT	 15H			     ;
	  .IF <ES:[BX].MODEL_BYTE EQ LCD_MODEL> AND ; yes...check for LCD attached?
	  MOV	 AH,GET_STATUS		     ; system status will tell us
	  INT	 15H			     ;
	  .IF <BIT AL NAND ON>		     ; if bit 0 = 0 then LCD..
	     OR     HDWR_FLAG,LCD_ACTIVE     ; so ...set hdwr flag and...
	     LEA    SI,COLOR_TABLE	     ;
	     MOV    CX,COLOR_NUM	     ; load color table (for LCD)
	     CALL   LOAD_TABLE		     ;
	     LEA    SI,MONO_TABLE	     ; and mono table
	     MOV    CX,MONO_NUM 	     ;
	     CALL   LOAD_TABLE		     ;
	  .ELSE 			     ; not LCD...check for CGA and mono
	    MOV   AX,MONO_ADDRESS	     ; write to mono buffer to see if present
	    CALL  CHECK_BUF		     ;
	    .IF <AH EQ AL>		     ; if present then...
	      OR     HDWR_FLAG,MONO_ACTIVE   ; set hdwr flag and..
	      LEA    SI,MONO_TABLE	     ;
	      MOV    CX,MONO_NUM	     ; load mono table
	      CALL   LOAD_TABLE 	     ;
	    .ENDIF			     ;
	    MOV   AX,COLOR_ADDRESS	     ; write to CGA buffer to see if present
	    CALL  CHECK_BUF		     ;
	    .IF <AH EQ AL>		     ; if present then..
	      OR     HDWR_FLAG,CGA_ACTIVE    ; set hdwr flag and...
	      LEA    SI,COLOR_TABLE	     ;
	      MOV    CX,COLOR_NUM	     ; load color table
	      CALL   LOAD_TABLE 	     ;
	    .ENDIF			     ;
	  .ENDIF			     ;
	  PUSH	  CS			     ; setup addressiblity for
	  POP	  ES			     ;	functionality call
	  XOR	  AX,AX 		     ;
	  MOV	  AH,FUNC_CALL		     ; functionality call
	  XOR	  BX,BX 		     ; implementation type 0
	  LEA	  DI,FUNC_INFO		     ; block to hold data
	  INT	  10H			     ;
	  .IF <AL EQ FUNC_CALL> 	     ; if call supported then..
	    .IF <BIT [DI].MISC_INFO AND ON>  ; test bit to see if VGA
	      OR     HDWR_FLAG,VGA_ACTIVE    ; yes ....so
	      LEA    SI,COLOR_TABLE	     ; set hdwr flag and...
	      MOV    CX,COLOR_NUM	     ; load color table +..
	      CALL   LOAD_TABLE 	     ;
	      LEA    SI,VGA_TABLE	     ; load VGA table
	      MOV    CX,VGA_NUM 	     ;
	      CALL   LOAD_TABLE 	     ;
	    .ELSE			     ; not VGA...then must be MCGA
	      .IF <[DI].ACTIVE_DISPLAY EQ MOD30_MONO> OR
	      .IF <[DI].ACTIVE_DISPLAY EQ MOD30_COLOR> OR
	      .IF <[DI].ALT_DISPLAY EQ MOD30_MONO> OR
	      .IF <[DI].ALT_DISPLAY EQ MOD30_COLOR>
		OR     HDWR_FLAG,MCGA_ACTIVE ; so...set hdwr flag and...
		LEA    SI,COLOR_TABLE	     ;
		MOV    CX,COLOR_NUM	     ; load color table +..
		CALL   LOAD_TABLE	     ;
		LEA    SI,MCGA_TABLE	     ; load MCGA table
		MOV    CX,MCGA_NUM	     ;
		CALL   LOAD_TABLE	     ;
	      .ENDIF			     ;
	    .ENDIF			     ;
	    MOV    AL,[DI].CURRENT_SCANS     ; copy current scan line setting..
	    MOV    MAX_SCANS,AL 	     ; as maximum text mode scan setting.
	    LES    DI,[DI].STATIC_ADDRESS    ; point to static functionality table
	    MOV    AL,ES:[DI].SCAN_TEXT      ; load available scan line flag byte..
	    MOV    SCAN_LINES,AL	     ; and store it in resident data.
	  .ELSE 			     ; call not supported..try EGA
	    MOV    AH,ALT_SELECT	     ; alternate select call
	    MOV    BL,EGA_INFO		     ; get EGA information subcall
	    INT    10H			     ;
	    .IF <BL NE EGA_INFO>	     ; check if call was valid
	      .IF <BH EQ MONOCHROME>	     ; yes...check for monochrome
		OR    HDWR_FLAG,E5151_ACTIVE ; ..5151 found so set hdwr flag and..
		LEA   SI,EGA_5151_TABLE      ;
		MOV   CX,EGA_5151_NUM	     ; load 5151 table.
		CALL  LOAD_TABLE	     ;
	      .ELSE			     ;
		AND   CL,0FH		     ; clear upper nibble of switch setting byte
		.IF <CL EQ NINE> OR	     ; test for switch settings of 5154
		.IF <CL EQ THREE>	     ; ..5154 found..
		  OR	 HDWR_FLAG,E5154_ACTIVE ; so..set hdwr flag and...
		  LEA	 SI,COLOR_TABLE      ;
		  MOV	 CX,COLOR_NUM	     ; load color table +..
		  CALL	 LOAD_TABLE	     ;
		  LEA	 SI,EGA_5154_TABLE   ; load 5154 table
		  MOV	 CX,EGA_5154_NUM     ;
		  CALL	 LOAD_TABLE	     ;
		.ELSE			     ; 5154 not found...must be 5153...
		  OR	 HDWR_FLAG,E5153_ACTIVE ; so..set hdwr flag and...
		  LEA	 SI,COLOR_TABLE      ;
		  MOV	 CX,COLOR_NUM	     ; load color table +..
		  CALL	 LOAD_TABLE	     ;
		  LEA	 SI,EGA_5153_TABLE   ; load 5153 table
		  MOV	 CX,EGA_5153_NUM     ;
		  CALL	 LOAD_TABLE	     ;
		.ENDIF			     ;
	      .ENDIF			     ;
	    .ENDIF			     ;
	  .ENDIF			     ;
	  RET
DET_HDWR  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: CHECK_BUF
;
; FUNCTION:
; THIS PROCEDURE WRITES TO THE VIDEO BUFFER AND READS THE DATA BACK
; AGAIN TO DETERMINE THE EXISTANCE OF THE VIDEO CARD.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: AH EQ AL IF BUFFER PRESENT
;	     AH NE AL IF NO BUFFER
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CHECK_BUF PROC	 NEAR		    ; write to video buffer to see if it is present
	  PUSH	 DS		    ;
	  MOV	 DS,AX		    ; load DS with address of buffer
	  MOV	 CH,DS:0	    ; save buffer information (if present)
	  MOV	 AL,55H 	    ; prepare to write sample data
	  MOV	 DS:0,AL	    ; write to buffer
	  PUSH	 BX		    ; terminate the bus so that lines..
	  POP	 BX		    ; are reset
	  MOV	 AH,DS:0	    ; bring sample data back...
	  MOV	 DS:0,CH	    ; repair damage to buffer
	  POP	 DS		    ;
	  RET
CHECK_BUF ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: LOAD_TABLE
;
; FUNCTION:
; THIS PROCEDURE COPIES ONE OF THE VIDEO TABLES INTO RESIDENT DATA.
; IT MAY BE REPEATED TO LOAD SEVERAL TABLES INTO THE SAME DATA SPACE.
; MATCHING MODES WILL BE OVERWRITTEN...THEREFORE..CARE MUST BE TAKEN
; IN LOAD ORDERING.
;
; AT ENTRY:
;   SI: POINTS TO TOP OF TABLE TO COPY
;   CX: NUMBER OF RECORDS TO COPY
;
; AT EXIT:
;    NORMAL: TABLE POINTED TO BY SI IS COPIED INTO RESIDENT DATA AREA
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LOAD_TABLE PROC   NEAR
	   PUSH   DI			  ; save DI
	   PUSH   ES			  ; and ES
	   PUSH   CS			  ; setup ES to code segment
	   POP	  ES			  ;
	   LEA	  DI,VIDEO_MODE_TABLE	  ; point DI to resident video table
	   .WHILE <CX NE 0> AND 	  ; do for as many records as there are
	   .WHILE <DI LT VIDEO_TABLE_MAX> ; check to ensure other data not overwritten
	     MOV    AL,[DI].V_MODE	  ; prepare to check resident table
	     .IF <AL NE UNOCCUPIED> AND   ; if this spot is occupied...and
	     .IF <AL NE [SI].V_MODE>	  ; ...is not the same mode then...
	       ADD    DI,TYPE MODE_TABLE  ; do not touch...go to next mode
	     .ELSE			  ; can write at this location
	       PUSH   CX		  ; save record count
	       MOV    CX,TYPE MODE_TABLE  ; load record length
	       REP    MOVSB		  ; copy record to resident data
	       lea    DI,VIDEO_MODE_TABLE ;AN001; Set DI to the top of the target again.
	       POP    CX		  ; restore record count and..
	       DEC    CX		  ; decrement
	     .ENDIF			  ;
	   .ENDWHILE			  ;
	   POP	  ES			  ; restore..
	   POP	  DI			  ; registers
	   RET				  ;
LOAD_TABLE ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: LOAD_INT10
;
; FUNCTION:
; THIS PROCEDURE LOADS THE INTERRUPT HANDLER FOR INT10H
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: INTERRUPT 10H VECTOR POINTS TO INT10_COM. OLD INT 10H
;	     VECTOR STORED.
;
;    ERROR:  N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LOAD_INT10 PROC   NEAR
	   PUSH   ES
	   XOR	  AX,AX 			   ; point ES to low..
	   MOV	  ES,AX 			   ; memory.
	   MOV	  CX,ES:WORD PTR INT10_LOW	   ; store original..
	   MOV	  CS:ROM_INT10,CX		   ; interrupt 10h..
	   MOV	  CX,ES:WORD PTR INT10_HI	   ; location..
	   MOV	  CS:ROM_INT10+2,CX		   ;
	   CLI					   ;
	   MOV	  ES:WORD PTR INT10_LOW,OFFSET INT10_COM ; replace vector..
	   MOV	  ES:WORD PTR INT10_HI,CS	   ; with our own..
	   STI					   ;
	   mov	  ax, DISPLAY_CHECK		   ;AN002;DISPLAY.SYS already loaded?
	   int	  2fh
	   cmp	  al, INSTALLED
	   jne	  L_INT10_Ret
	   mov	  cs:Display_Loaded_Before_Me,1
L_INT10_Ret:
	   POP	  ES				   ;
	   RET					   ;
LOAD_INT10 ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: LOAD_INT2F
;
; FUNCTION:
; THIS PROCEDURE LOADS THE INTERRUPT HANDLER FOR INT2FH
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: INTERRUPT 2FH VECTOR POINTS TO INT2F_COM. OLD INT 2FH
;	     VECTOR STORED.
;
;    ERROR:  N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LOAD_INT2F PROC   NEAR
	   PUSH   ES
	   XOR	  AX,AX 			   ; point ES to low..
	   MOV	  ES,AX 			   ; memory.
	   MOV	  AX,ES:WORD PTR INT2F_LOW	   ; store original..
	   MOV	  CS:ROM_INT2F,AX		   ; interrupt 2Fh..
	   MOV	  CX,ES:WORD PTR INT2F_HI	   ; location..
	   MOV	  CS:ROM_INT2F+2,CX		   ;
	   OR	  AX,CX 			   ; check if old int2F..
	   .IF Z				   ; is 0.
	     MOV    AX,OFFSET ABORT		   ; yes....point to..
	     MOV    CS:ROM_INT2F,AX		   ; IRET.
	     MOV    AX,CS			   ;
	     MOV    CS:ROM_INT2F+2,AX		   ;
	   .ENDIF				   ;
	   CLI					   ;
	   MOV	  ES:WORD PTR INT2F_LOW,OFFSET INT2F_COM ; replace vector..
	   MOV	  ES:WORD PTR INT2F_HI,CS	   ; with our own..
	   STI					   ;
	   POP	  ES				   ;
	   RET					   ;
LOAD_INT2F ENDP


CODE	ENDS
	END
