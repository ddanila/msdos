;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.ALPHA
.XLIST
INCLUDE    STRUC.INC
.LIST
					;
	PUBLIC	MONO, CGA, EGA, LCD
	PUBLIC	 ACTIVE, ALTERNATE
					;
	EXTRN  IN_CURNOR:WORD
					;
DATA	SEGMENT BYTE PUBLIC 'DATA'
MONO	EQU    1
CGA	EQU    2
EGA	EQU    3
LCD	EQU    4
					;
READ_DISPLAY   EQU   1AH
ALT_SELECT     EQU   12H
EGA_INFO       EQU   10H
MONOCHROME     EQU   1
BASE_COLOR     EQU   0B800H
BASE_MONO      EQU   0B000H
GET_SYS_ID     EQU   0C0H
LCD_MODEL      EQU   0F9H
GET_STATUS     EQU   43H
ON	       EQU   1
					;
SYSTEM_ID      STRUC
	       DW    ?
MODEL_BYTE     DB    ?
SYSTEM_ID      ENDS
					;
ACTIVE	   DB	0
ALTERNATE  DB	0
					;
DATA	       ENDS			;AN000;DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SERVICE SEGMENT PARA PUBLIC 'SERVICE'        ;AN000;segment for far routine
	ASSUME	CS:SERVICE,DS:DATA
					     ;
	PUBLIC	VIDEO_CHECK
VIDEO_CHECK PROC   FAR
	    PUSH   AX
	    PUSH   BX			     ;AN000; save all registers
	    PUSH   CX
	    PUSH   DX
	    PUSH   SI
	    PUSH   DI
	    PUSH   ES
	    XOR    AL,AL
	    MOV    AH,READ_DISPLAY	     ;AN000; check for VGA first.
	    INT    10H
	    .IF <AL EQ READ_DISPLAY>	     ;AN000; VGA present?
	      .SELECT			     ;AN000; yes....BL contains active..
	      .WHEN <BL EQ MONO>	     ;AN000; display code.
		MOV    ACTIVE,MONO
	      .WHEN <BL EQ CGA>
		MOV    ACTIVE,CGA
	      .WHEN <BL A CGA>
		MOV    ACTIVE,EGA
	      .ENDSELECT
	      .SELECT			     ;AN000; ...and BH contains alternate..
	      .WHEN <BH EQ MONO>	     ;AN000; display code.
		MOV    ALTERNATE,MONO
	      .WHEN <BH EQ CGA>
		MOV    ALTERNATE,CGA
	      .WHEN <BH A CGA>
		MOV    ALTERNATE,EGA
	      .ENDSELECT
	    .ELSE			     ;AN000; VGA not there..check for EGA.
	      MOV    AH,ALT_SELECT
	      MOV    BL,EGA_INFO
	      INT    10H
	      .IF <BL NE EGA_INFO>	     ;AN000; EGA present?
		MOV    ACTIVE,EGA	     ;AN000; yes....set as active.
		.IF <BH EQ MONOCHROME>	     ;AN000; if monochrome attached to EGA then..
		  MOV	 AX,BASE_COLOR	     ;AN000; check if CGA is an alternate.
		  CALL	 CHECK_BUFF
		  .IF <AH EQ AL>	     ;AN000; CGA there?
		    MOV    ALTERNATE,CGA     ;AN000; yes....alternate display.
		  .ENDIF
		.ELSE			     ;AN000; if color attached to EGA then...
		  MOV	 AX,BASE_MONO	     ;AN000; check if monochrome is an alternate.
		  CALL	 CHECK_BUFF
		  .IF <AH EQ AL>	     ;AN000; MONO there?
		    MOV    ALTERNATE,MONO    ;AN000; yes....alternate display.
		  .ENDIF
		.ENDIF
	      .ELSE			     ;AN000; EGA not present so...
		MOV    AH,GET_SYS_ID	     ;AN000; check for LCD.
		INT    15H
		.IF <ES:[BX].MODEL_BYTE EQ LCD_MODEL> AND ;AN000; if model byte says convertible..
		MOV    AH,GET_STATUS	     ;AN000; and..
		INT    15H
		.IF <BIT AL NAND ON>	     ;AN000; if LCD screen attached..then
		  MOV	 ACTIVE,LCD	     ;AN000; set LCD as active display.
		.ELSE
		  MOV	 AX,BASE_MONO	     ;AN000; not LCD...check for..
		  CALL	 CHECK_BUFF	     ;AN000; MONO....
		  .IF <AH EQ AL>
		    MOV    ACTIVE,MONO	     ;AN000; MONO found...set as active.
		    MOV    IN_CURNOR,0B0CH   ;AN000;JW set mono cursor size
		  .ENDIF
		  MOV	 AX,BASE_COLOR	     ;AN000; ..and check for color.
		  CALL	 CHECK_BUFF
		  .IF <AH EQ AL>
		    MOV    ALTERNATE,CGA     ;AN000; color found...set CGA as alternate.
		  .ENDIF
		.ENDIF
	      .ENDIF
	    .ENDIF
	    POP    ES
	    POP    DI			     ;AN000; restore registers.
	    POP    SI
	    POP    DX
	    POP    CX
	    POP    BX
	    POP    AX
	    RET
VIDEO_CHECK ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CHECK_BUFF  PROC   NEAR 	;AN000; write to video buffer to see if it is present
	    PUSH   DS
	    MOV    DS,AX	;AN000; load DS with address of buffer
	    MOV    CH,DS:0	;AN000; save buffer information (if present)
	    MOV    AL,55H	;AN000; prepare to write sample data
	    MOV    DS:0,AL	;AN000; write to buffer
	    PUSH   BX		;AN000; terminate the bus so that lines..
	    POP    BX		;AN000; are reset
	    MOV    AH,DS:0	;AN000; bring sample data back...
	    MOV    DS:0,CH	;AN000; repair damage to buffer
	    POP    DS
	    RET
CHECK_BUFF  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SERVICE     ENDS
	    END
