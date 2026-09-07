;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	DUMMY DATA SEGMENT THAT WILL LINK WITH THE DATA.MAC
;	FILE.  THIS RESOLVES ANY REFERENCES TO THE DATA SEGMENT.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DATA	SEGMENT BYTE PUBLIC 'DATA'
HELPBUFSEG     DW     0
MEM_ALLOC      DB     0 		;AN000;DT Memory allocated indicator
HELP_ALLOC     EQU    80H		;AN000;DT Help memory allocated
BLOCK_ALLOC    EQU    40H		;AN000;DT PANEL memory allocated
LVB_ALLOC      EQU    20H		;AN000;DT LVB memory allocated
BLOCK_SET      EQU    01H		;AN000;DT SETBLOCK done
DATA	       ENDS			;AN000;DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Define dummy segment to calculate end of program
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ZSEG	 SEGMENT PARA PUBLIC 'ZSEG'     ;AN000;marks end of routine
ZSEG	 ENDS				;AN000;ZSEG will alphabetically appear
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	INITMEM.ASM
;
;
;  Allocate Memory
;
;  This routine will free up the required memory from DOS to make
;  space for the panels, scroll, help, and input field data.
;
;
;	INPUT:	BX = # paragraphs to keep (in the program) ZSEG-PSP_SEG
;		CX = Length of program in bytes
;		DX = # paragraphs to allocate
;		DS = ES = CS - 10H
;
;	OUTPUT: DS:DX = segment:offset of allocated buffer
;		BX    = length of allocated buffer
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	WR_MAXMEMPAR:WORD
	EXTRN	WR_MAXHELPSZ:WORD
	EXTRN	WR_DATA2SEG:WORD
	EXTRN	WR_DATA2OFF:WORD
	EXTRN	WR_DATA2LEN:WORD
	EXTRN	WR_LVBSEG:WORD
	EXTRN	WR_LVBOFF:WORD
	EXTRN	WR_LVBLEN:WORD
	EXTRN	WR_LVBMEM:WORD
	EXTRN	HRD_BUFSEG:WORD
	EXTRN	HRD_BUFOFF:WORD
	EXTRN	HRD_BUFLEN:WORD
					;
SERVICE SEGMENT PARA PUBLIC 'SERVICE'   ;AN000;segment for far routine
	ASSUME CS:SERVICE,DS:DATA
					;
	PUBLIC	ALLOCATE_MEMORY_CALL
	PUBLIC	DEALLOCATE_MEMORY_CALL
	PUBLIC	ALLOCATE_HELP
	PUBLIC	DEALLOCATE_HELP
	PUBLIC	ALLOCATE_BLOCK
	PUBLIC	DEALLOCATE_BLOCK
	PUBLIC	ALLOCATE_LVB
	PUBLIC	DEALLOCATE_LVB
					;
SET_BLOCK	equ	4AH
ALLOCATEB	equ	48H
FREE_BLOCK	equ	49H
					;
	INCLUDE STRUC.INC
	INCLUDE MACROS.INC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DS and AX will auto pop on ret
;
; ALLOCATE_MEMORY_CALL
;
;	This first takes the memory held by the active program
;	(initially all of remaining memory) and requests only the
;	memory held by the running program.  Next, memory is
;	re-allocated to the running program - specified by WR_MAXMEMPAR
;	starting from the end of the program (re/ZSEG).
;
; ENTRY:
;	AX = CODE segment (PSP+100H)
;
;
; EXIT:
;	if CY = 0 then,
;		WR_DATA2SEG = start of allocated segment
;		WR_DATA2OFF = start of allocated offset (always 0)
;		WR_DATA2LEN = length of allocated block (always WR_MAXMEMPAR)
;
;	if CY = 1 then an error occurred allocating memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ALLOCATE_MEMORY_CALL  PROC FAR
	PUSHH  <AX,BX,DX,DS,ES>
					;
	TEST MEM_ALLOC,BLOCK_SET	;AN000;DT SETBLOCK done?
	JNZ  AM_SBDONE			;AN000;DT if so, skip it
					;
	MOV	AH,62H			;AN000; Get the PSP segment
	INT	21H
	MOV	AX,BX			;AN000;save the PSP segment of SELECT
	MOV	BX,SEG ZSEG 		;AN000;get last address of code (from ZSEG)
	MOV	ES,AX			;AN000;set PSP segment in ES
	SUB	BX,AX			;AN000;calc # of paragraphs in the program
	MOV	AH,SET_BLOCK		;AN000;setblock function number
	DOSCALL 			;AN000;free used memory
	.IF   < C >
	   GOTO    ALLOC_RET		;AN000;DT If error, exit
	.ENDIF
	OR	MEM_ALLOC,BLOCK_SET
					;
AM_SBDONE:
	MOV	AX,SEG DATA 		;AN000;initialize data segment
	MOV	DS,AX			;AN000; and extra segment
					;
	PUSH	CS			;AN000;call far procedure
	CALL	ALLOCATE_BLOCK_NEAR	;AN000;now allocate Panel block
	.IF   < C >
	   GOTO    ALLOC_RET		;AN000;DT If error, exit
	.ENDIF
					;
	PUSH	CS			;AN000;call far procedure
	CALL	ALLOCATE_LVB_NEAR	;AN000;now allocate LVB block
	.IF   < C >
	   GOTO    ALLOC_RET		;AN000;DT If error, exit
	.ENDIF
					;
	PUSH	CS			;AN000;call far procedure
	CALL	ALLOCATE_HELP_NEAR	;AN000;now allocate help
					;
ALLOC_RET:
	POPP   <ES,DS,DX,BX,AX>
	RET
ALLOCATE_MEMORY_CALL	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DEALLOCATE_MEMORY_CALL
;
;	This is the house-cleaning before the running program
;	returns to DOS.
;
; ENTRY:
;	none
;
; EXIT:
;	if CY = 0 then,
;		The memory after (WR_DATA2SEG) is released to DOS
;	if CY = 1 then,
;		An error occurred while trying to release this memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DEALLOCATE_MEMORY_CALL	PROC FAR
	PUSHH  <AX,DS,ES>
	MOV	AX,SEG DATA
	MOV	DS,AX
	PUSH	CS		;AN000;call far procedure
	CALL	DEALLOCATE_BLOCK_NEAR ;AN024;now deallocate Panel block
	PUSH	CS		;AN000;call far procedure
	CALL	DEALLOCATE_LVB_NEAR ;AN024; deallocate LVB block
	PUSH	CS		;AN000;call far procedure
	CALL	DEALLOCATE_HELP_NEAR ;AN000;now deallocate help
	POPP   <ES,DS,AX>
	RET
DEALLOCATE_MEMORY_CALL	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DS and AX will auto pop on ret
;
; ALLOCATE_HELP
;
;
; ENTRY:
;	AX = CODE segment (PSP+100H)
;
;
; EXIT:
;	if CY = 0 then, ok
;	if CY = 1 then an error occurred allocating memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ALLOCATE_HELP  PROC FAR
ALLOCATE_HELP_NEAR:
	PUSHH  <AX,BX,DX,DS,ES>
	MOV	AX,SEG DATA
	MOV	DS,AX
					;
	TEST MEM_ALLOC,HELP_ALLOC	;AN000;DT Is help allocated
	JNZ   AH_RET			;AN000;DT if so, skip allocation
					;now allocate help
	 MOV	 BX,WR_MAXHELPSZ	;AN000;set BX to max # of paragraphs
	 SHR	 BX,1
	 SHR	 BX,1
	 SHR	 BX,1
	 SHR	 BX,1
	 MOV	 AH,ALLOCATEB		;AN000;set allocate function number
	 DOSCALL			;AN000;allocate memory
	.IF   < NC >
	     MOV     HRD_BUFSEG,AX	;AN000;save segment
	     MOV     HELPBUFSEG,AX	;AN000;save segment
	     MOV     HRD_BUFOFF,0	;AN000; and offset
	     MOV     BX,WR_MAXHELPSZ	;AN000;set BX to max # of byte
	     MOV     HRD_BUFLEN,BX
	     OR      MEM_ALLOC,HELP_ALLOC
	     CLC
	.ENDIF
AH_RET:
	POPP   <ES,DS,DX,BX,AX>
	RET
ALLOCATE_HELP	 ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DEALLOCATE_HELP
;
;	This is the house-cleaning before the running program
;	returns to DOS.
;
; ENTRY:
;	none
;
; EXIT:
;	if CY = 0 then, OK
;	if CY = 1 then,
;		An error occurred while trying to release this memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DEALLOCATE_HELP  PROC FAR
DEALLOCATE_HELP_NEAR:
	PUSHH  <AX,BX,DS,ES>
	MOV	AX,SEG DATA
	MOV	DS,AX
	TEST MEM_ALLOC,HELP_ALLOC ;AN000;DT Is help allocated
	JZ   DH_RET		;AN000;DT if not, skip deallocation
	MOV	AX,HELPBUFSEG	;AN000;free help segment
	MOV	ES,AX
	MOV	AH,FREE_BLOCK
	DOSCALL
	AND	MEM_ALLOC,255-HELP_ALLOC
DH_RET:
	POPP   <ES,DS,BX,AX>
	RET
DEALLOCATE_HELP  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DS and AX will auto pop on ret
;
; ALLOCATE_BLOCK
;
;	Allocate Panel and Scroll memory.
;
; ENTRY:
;	none
; EXIT:
;	if CY = 0 then,
;		WR_DATA2SEG = start of allocated segment
;		WR_DATA2OFF = start of allocated offset (always 0)
;		WR_DATA2LEN = length of allocated block (always WR_MAXMEMPAR)
;
;	if CY = 1 then an error occurred allocating memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ALLOCATE_BLOCK	PROC FAR
ALLOCATE_BLOCK_NEAR:
	PUSHH  <AX,BX,DX,DS,ES>
	MOV	AX,SEG DATA 		;AN000;initialize data segment
	MOV	DS,AX			;AN000; and extra segment
					;
	TEST MEM_ALLOC,BLOCK_ALLOC	;AN000;DT Is PANEL block allocated
	JNZ   AB_RET			;AN000;DT if so, skip allocation
					;
	MOV	BX,WR_MAXMEMPAR 	;AN000;set DX to max # of 16 byte parag's
	MOV	AH,ALLOCATEB		;AN000;set allocate function number
	DOSCALL 			;AN000;allocate memory
	.IF   < NC >
	   MOV	   BX,WR_MAXMEMPAR
	   SHL	   BX,1 		;AN000;THIS SHOULD BE REMOVED WHEN
	   SHL	   BX,1 		;AN000;THE INITIALIZE ROUTINE TREATS
	   SHL	   BX,1 		;AN000;WR_DATA2LEN AS PARAGRAPHS AND
	   SHL	   BX,1 		;AN000;NOT BYTES......
	   MOV	   WR_DATA2SEG,AX	;AN000;save segment
	   MOV	   WR_DATA2OFF,0
	   MOV	   WR_DATA2LEN,BX
	   OR	   MEM_ALLOC,BLOCK_ALLOC ;AN000;DT PANEL block allocated
	.ENDIF
AB_RET:
	POPP   <ES,DS,DX,BX,AX>
	RET
ALLOCATE_BLOCK	  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DEALLOCATE_BLOCK
;
;	This is the house-cleaning before the running program
;	returns to DOS.
;
; ENTRY:
;	none
;
; EXIT:
;	if CY = 0 then, OK
;	if CY = 1 then,
;		An error occurred while trying to release this memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DEALLOCATE_BLOCK PROC FAR
DEALLOCATE_BLOCK_NEAR:
	PUSHH  <AX,BX,DS,ES>
	MOV	AX,SEG DATA
	MOV	DS,AX
	TEST MEM_ALLOC,BLOCK_ALLOC ;AN000;DT Is PANEL block allocated
	JZ   DB_RET		;AN000;DT if not, skip deallocation
	MOV	AX,WR_DATA2SEG	;AN000;free up allocated segment
	MOV	ES,AX
	MOV	AH,FREE_BLOCK
	DOSCALL
	AND	MEM_ALLOC,255-BLOCK_ALLOC
DB_RET:
	POPP   <ES,DS,BX,AX>
	RET
DEALLOCATE_BLOCK ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DS and AX will auto pop on ret
;
; ALLOCATE_LVB
;
;
; ENTRY:
;	AX = none
;
;
; EXIT:
;	if CY = 0 then, ok
;	if CY = 1 then an error occurred allocating memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ALLOCATE_LVB   PROC FAR
ALLOCATE_LVB_NEAR:
	PUSHH  <AX,BX,DX,DS,ES>
					;
	MOV	AX,SEG DATA
	MOV	DS,AX
					;;;;;;;
	TEST MEM_ALLOC,LVB_ALLOC	;AN000;DT Is LVB block allocated
	JNZ  ALVB_RET			;AN000;DT if so, skip allocation
					;
	MOV	BX,WR_LVBMEM		;AN000;set BX to max # of 16 byte parag's
	MOV	AH,ALLOCATEB		;AN000;set allocate function number
	DOSCALL 			;AN000;allocate memory
	.IF   < NC >
	   MOV	   WR_LVBSEG,AX 	;AN000;save segment
	   MOV	   WR_LVBOFF,0		;AN000;and offset
	   SHL	   BX,1 		;AN000;THIS SHOULD BE REMOVED WHEN
	   SHL	   BX,1 		;AN000;THE INITIALIZE ROUTINE TREATS
	   SHL	   BX,1 		;AN000;WR_DATA2LEN AS PARAGRAPHS AND
	   SHL	   BX,1 		;AN000;NOT BYTES......
	   MOV	   WR_LVBLEN,BX 	;AN000;and byte length
	   OR	   MEM_ALLOC,LVB_ALLOC	;AN000;DT LVB block allocated
	.ENDIF
					;
ALVB_RET:
	POPP   <ES,DS,DX,BX,AX>
	RET
ALLOCATE_LVB	 ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; DEALLOCATE_LVB
;
;
; ENTRY:
;	none
;
; EXIT:
;	if CY = 0 then, OK
;	if CY = 1 then,
;		An error occurred while trying to release this memory
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DEALLOCATE_LVB PROC FAR
DEALLOCATE_LVB_NEAR:
	PUSHH  <AX,BX,DS,ES>
	MOV	AX,SEG DATA
	MOV	DS,AX
	TEST MEM_ALLOC,LVB_ALLOC ;AN000;DT Is LVB block allocated
	JZ   DLVB_RET		;AN000;DT if not, skip deallocation
	MOV	AX,WR_LVBSEG	;AN000;free up LVB allocated segment
	MOV	ES,AX
	MOV	AH,FREE_BLOCK
	DOSCALL
	AND	MEM_ALLOC,255-LVB_ALLOC
DLVB_RET:
	POPP   <ES,DS,BX,AX>
	RET
DEALLOCATE_LVB	 ENDP

SERVICE ENDS
	END
