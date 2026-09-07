
Title	E2BINIT(EXE2BIN)

; EXE-to-binary loader.

; Keep EXE2BIN.EXE's retail 5.00 mapping; use the actual native DOS version.
MSG_TRUE_DOS_VERSION EQU 1
INCLUDE SYSMSG.INC
MSG_UTILNAME <EXE2BIN>

	subttl	Main Code Area
	page


; The following switch allows use with the "old linker", which put a version
; number where the new linker puts the number of bytes used in the last page.
; If enabled, this will cause a test for 0004 at this location (the old linker
; version number), and if equal, change it to 200H so all of the last page
; will be used.

OLDLINK EQU	0			;1 to enable, 0 to disable

CODE	SEGMENT PARA PUBLIC 'CODE'
CODE	ENDS
DATA	SEGMENT PARA PUBLIC 'DATA'
DATA	ENDS
STACK	SEGMENT PARA PUBLIC 'STACK'
STACK	ENDS
ZLOAD	SEGMENT PARA PUBLIC 'ZLOAD'
ZLOAD	ENDS

DATA	SEGMENT PARA PUBLIC 'DATA'

MSG_SERVICES <MSGDATA>

Command_Line_Buffer db 128 dup(0)
Command_Line_Length equ $ - Command_Line_Buffer

Fatal_Error db	0

Command_Line db NO



rev	db	"2.4"


file1_ext db	".EXE",00h
file2_ext db	".BIN",00h

per11	db	0
per2	db	0
per22	db	0

update	equ	0
noupdate equ	-1

file1	db	(64+13) dup(?)
fnptr	dw	offset file1		; Ptr to filename in file1
handle1 dw	1 dup(?)

file2	db	(64+13) dup(?)
f2cspot dw	offset file2		; Ptr to spot in file2, file1 maybe added
handle2 dw	1 dup(?)

dma_buf db	80h dup(0)		; DMA transfer buffer

INBUF	DB	5,0
	DB	5 DUP(?)

;The following locations must be defined for storing the header:

RUNVAR	LABEL	BYTE			;Start of RUN variables
RELPT	DW	?
LASTP	LABEL	WORD
RELSEG	DW	?
SIZ	LABEL	WORD			;Share these locations
PAGES	DW	?
RELCNT	DW	?
HEADSIZ DW	?
	DW	?
LOADLOW DW	?
INITSS	DW	?
INITSP	DW	?
	DW	?
INITIP	DW	?
INITCS	DW	?
RELTAB	DW	?
RUNVARSIZ EQU	$-RUNVAR

DBCS_Vector_Off dw 0
DBCS_Vector_Seg dw 0

parse_ptr DW	?

DATA	ENDS


STACK	SEGMENT PARA PUBLIC 'STACK'
	DB	(362 - 80h) + 80H DUP (?) ; (362 - 80h) is IBMs ROM requirement
					; (New - Old) == size of growth
STACK	ENDS
;



ZLOAD	SEGMENT PARA PUBLIC 'ZLOAD'
	db	?
ZLOAD	ENDS
LOAD	EQU	ZLOAD
;



;
;*****************************************************************************
; Include files
;*****************************************************************************
;

.xlist
INCLUDE DOSSYM.INC			; also versiona.inc
INCLUDE SYSCALL.INC
INCLUDE E2BMACRO.INC
INCLUDE E2BEQU.INC
INCLUDE E2BTABLE.INC
INCLUDE E2BPARSE.INC
include version.inc
.list



CODE	SEGMENT PARA PUBLIC 'CODE'
	assume	cs:CODE,ds:DATA,es:NOTHING,SS:STACK

psp_ptr dw	1 dup(?)
;
;*****************************************************************************
; SysDisplayMsg Declarations
;*****************************************************************************
;
.xlist
MSG_SERVICES <LOADmsg>
MSG_SERVICES <DISPLAYmsg,CHARmsg>
MSG_SERVICES <EXE2BIN.CLA,EXE2BIN.CLB>
MSG_SERVICES <EXE2BIN.CL1,EXE2BIN.CL2>
MSG_SERVICES <EXE2BIN.CTL>


.list

;
;*****************************************************************************
; External Routine Declarations
;*****************************************************************************
;

	public	SysDispMsg
	public	SysLoadMsg


;*****************************************************************************
;Routine name:	Main_Init
;*****************************************************************************
;
;Description: Main control routine for init section
;
;Called Procedures: Message (macro)
;		    Check_DOS_Version
;		    Init_Input_Output
;		    Validate_Target_Drive
;		    Hook_CNTRL_C
;
;Input: None
;
;Output: None
;
E2B_HELP_STR	DB  "EXE2BIN [drive:][path]input[.EXE] [[drive:][path]output[.BIN]]",0Dh,0Ah,"$"

procedure Main_Init		;

	ASSUME	DS:NOTHING		; THIS IS WHAT dos GIVES YOU
	ASSUME	ES:NOTHING

	; Check for /? (EXE file: DS=PSP at entry)
	MOV	SI, 081h
E2B_SKIP_SP:
	CMP	BYTE PTR DS:[SI], ' '
	JNE	E2B_CHK_SL
	INC	SI
	JMP	SHORT E2B_SKIP_SP
E2B_CHK_SL:
	CMP	BYTE PTR DS:[SI], '/'
	JNE	E2B_NO_HELP
	CMP	BYTE PTR DS:[SI+1], '?'
	JNE	E2B_NO_HELP
	PUSH	CS
	POP	DS
	MOV	DX, OFFSET E2B_HELP_STR
	MOV	AH, 09H
	INT	21H
	MOV	AX, 4C00H
	INT	21H
E2B_NO_HELP:

	PUSH	DS
	mov	psp_ptr,ds
	XOR	AX,AX
	PUSH	AX			;Push return address to DS:0

	MOV	AX,SEG DATA		;SET UP ADDRESSABILITY TO
	MOV	DS,AX			; THE DATA SEGMENT
	ASSUME	DS:DATA 		;TELL ASSEMBLER WHAT I JUST DID

	mov	Fatal_Error,No		;Init the error flag
	call	Init_Input_Output	;Setup messages and parse
	cmp	Fatal_Error,Yes 	;Error occur?
;	$IF	NE			;Nope, keep going
	JE $$IF1
	    call    LOCATE		;Go do the real program
;	$ENDIF
$$IF1:
	xor	al,al
	Dos_call Exit
	int	20h			;If other exit fails

Main_Init endp

;*****************************************************************************
;Routine name: Init_Input_Output
;*****************************************************************************
;
;Description: Initialize messages, Parse command line, allocate memory as
;	      needed. If there is a /FS switch, go handle it first as
;	      syntax of IFS format may be different from FAT format.
;
;Called Procedures: Preload_Messages
;		    Parse_For_FS_Switch
;		    Parse_Command_Line
;		    Interpret_Parse
;
;
;Input: PSP command line at 81h and length at 80h
;	Fatal_Error  = No
;
;Output: Fatal_Error = YES/NO
;
;*****************************************************************************

procedure Init_Input_Output

	call	Preload_Messages	;Load up message retriever
	cmp	Fatal_Error,YES 	;Quit?
;	$IF	NE			;Nope, keep going
	JE $$IF3
	    call    Parse_Command_Line	;Parse in command line input
;	$ENDIF
$$IF3:
	ret

Init_Input_Output endp

;*****************************************************************************
;Routine name: Preload_Messages
;*****************************************************************************
;
;Description: Preload messages using common message retriever routines.
;
;Called Procedures: SysLoadMsg
;
;
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;*****************************************************************************

procedure Preload_Messages

	call	SYSLOADMSG		;Preload the messages
;	$IF	C			;Error?
	JNC $$IF5
	    call    SYSDISPMSG
	    mov     fatal_error, YES
;	$ENDIF
$$IF5:
	ret
Preload_Messages endp


;*****************************************************************************
;Routine name: Parse_Command_Line
;*****************************************************************************
;
;Description: Parses command line.
;
;Called Procedures: Message (macro)
;		    Sysparse
;
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;*****************************************************************************


Procedure Parse_Command_Line

	push	ds
	mov	ds,psp_ptr
	ASSUME	DS:NOTHING
	mov	si,Command_Line_Parms
	mov	ax,seg command_line_table
	push	es
	mov	es,ax
	ASSUME	ES:NOTHING
	mov	di,offset Command_Line_Table
	xor	cx,cx

;	$DO
$$DO7:
	    xor     dx,dx
	    mov     es:parse_ptr,si
	    call    Sysparse
	    cmp     ax,No_Error

;	    $IF     E
	    JNE $$IF8

		push	ax
		push	bx
		push	ds
		push	es
		push	si
		push	di

		cmp	cx,1

;		$IF	E
		JNE $$IF9

		    mov     ax,seg rb_string1_off
		    mov     ds,ax
		    ASSUME  DS:NOTHING
		    mov     si,offset rb_string1_off
		    mov     ax,ds:[si]
		    mov     bx,ax


		    mov     ax,ds:[si+2]
		    mov     ds,ax
		    ASSUME  DS:NOTHING
		    mov     si,bx

		    mov     ax,seg file1
		    mov     es,ax
		    ASSUME  ES:NOTHING
		    mov     di,offset file1
		    call    copyfs

;		$ELSE
		JMP SHORT $$EN9
$$IF9:

		    mov     ax,seg rb_string2_off
		    mov     ds,ax
		    ASSUME  DS:NOTHING
		    mov     si,offset rb_string2_off
		    mov     ax,ds:[si]
		    mov     bx,ax


		    mov     ax,ds:[si+2]
		    mov     ds,ax
		    ASSUME  DS:NOTHING
		    mov     si,bx

		    mov     ax,seg file2
		    mov     es,ax
		    ASSUME  ES:NOTHING
		    mov     di,offset file2
		    call    copyfs

;		$ENDIF
$$EN9:

		pop	di
		pop	si
		pop	es
		ASSUME	ES:NOTHING
		pop	ds
		ASSUME	DS:NOTHING
		pop	bx
		pop	ax

;	    $ENDIF
$$IF8:

	    cmp     ax,No_Error

;	$ENDDO	NE
	JE $$DO7

	cmp	ax,End_of_Parse 	;Check for parse error
;	$IF	NE
	JE $$IF14
		push	ax
		mov	ax,es:parse_ptr
		mov	es:parsoff,ax
		mov	es:parseg,ds
		mov	byte ptr ds:[si],0
		pop	ax
		parse_message		       ;Must enter file name
		mov	es:Fatal_Error,YES     ;Indicate death!
;	$ENDIF
$$IF14:

	pop	es
	ASSUME	ES:NOTHING
	pop	ds
	ASSUME	DS:DATA

	ret

Parse_Command_Line endp

;*****************************************************************************

INCLUDE PARSE.ASM

;*****************************************************************************


procedure LOCATE

	push	ds
	ASSUME	ES:NOTHING		; THIS IS THE WAY IT GETS HERE!
	mov	ax,es			; ES -> PSP
	mov	ds,ax			; DS -> PSP
	ASSUME	DS:NOTHING

	MOV	SI,offset file1
	MOV	BX,SEG DATA
	MOV	ES,BX
	assume	es:data

	MOV	BX,WORD PTR DS:[2]	;Get size of memory


;-----------------------------------------------------------------------;

;
; The rules for the arguments are:
;   File 1:
;	If no extention is present, .EXE is used.
;   File 2:
;	If no drive is present in file2, use the one from file1
;	If no path is specified, then use current dir
;	If no filename is specified, use the filename from file1
;	If no extention is present in file2, .BIN is used
;


;----- Get the first file name
	push	ds
	push	es
	ASSUME	ES:DATA
	pop	ds
	ASSUME	DS:DATA

sj01:
	mov	si,offset file1 	;   d = file1;
	mov	per11,0 		;   assume no extension on file1

;******************************************************************************

sj0:
	lodsb				;   while (!IsBlank(c=*p++)) {
	cmp	al,0
	JE	SJ2
	call	dbcs_check		; see if a dbcs character
	jc	dbcs_1			; dbcs character, go load another char
	cmp	al,'\'			;	if (c == '\\' || c == ':') {
	jnz	sj05
	mov	per11,update
	mov	fnptr,si		;	    fnptr = ptr to slash
sj05:
	cmp	al,':'			;	if (c == '\\' || c == ':') {
	jnz	checkper1
	mov	per11,update
	mov	fnptr,si		;	    fnptr = ptr to slash
checkper1:
	cmp	al,'.'			;	if (c == '.')
	jne	sj1
	mov	per11,noupdate		;   set file1 to have extension

sj1:

IF IBMCOPYRIGHT
ELSE
	cmp	al,'*'
	je	File1_Err
	cmp	al,'?'
	je	File1_Err
ENDIF

	jmp	short sj0		;	}

IF IBMCOPYRIGHT
ELSE
File1_Err:
	stc
	mov	dx, offset file1
	jmp	DosError
ENDIF

dbcs_1: 				;
	lodsb				; load another character and got to
	jmp	short sj0		; the start again.

;******************************************************************************

sj2:
get_second:
;----- Get the second file name
	MOV	SI,offset file1
	mov	di,offset file2 	;   d = file2

;******************************************************************************

sj3:
	cmp	word ptr [di],00	;   check to see if first character of
	je	sj32			;   file2 is a null.
	mov	si,offset file2 	;   set pointer to file2

;******************************************************************************

sj31:
	lodsb				;   If file2 first character is not a
	mov	f2cspot,si
	cmp	al,0			;   null, this loop will check to see
	JZ	maycopy 		;   the file has an extension assigned
	call	dbcs_check		; to it.  If not it will set per2 to
	jc	dbcs_2			; go load another byte
	mov	per22,noupdate		;
	cmp	al,'\'			;   0 so that in check_ext, the .BIN
	jnz	checkper6		;   will be added to the filename.
	mov	per2,update		;
	mov	per22,update		;
checkper6:
	cmp	al,':'			;	if (c == '\\' || c == ':') {
	jnz	checkper4
	mov	per22,update		;
checkper4:				;   there is an extension already.
	cmp	al,'.'			;
	jne	sj33			;
	mov	per2,noupdate		;

sj33:					;

IF IBMCOPYRIGHT
ELSE
	cmp	al,'*'
	je	File2_Err
	cmp	al,'?'
	je	File2_Err
ENDIF

	jmp	short sj31		;

IF IBMCOPYRIGHT
ELSE
File2_Err:
	stc
	mov	dx, offset file2
	jmp	DosError
ENDIF


dbcs_2:
	lodsb				;load another character and got to
	jmp	short sj31		;the start again.

;******************************************************************************

maycopy:				;   Check to see if the
	cmp	per22,noupdate		;   Last thing copied was either a
	je	SJ5			;   driver letter or  "\".
	dec	f2cspot
	mov	di,f2cspot

sj32:
					;   There is no second filename so
	mov	si,fnptr
	mov	per2,update		;   set per2 to 0 to get default .BIN
					;   extension in check_ext.

;******************************************************************************

copy1to2:
	lodsb				; This loop is executed when there is
	cmp	al,0			; no file2 specified on the command
	JZ	SJ5			; line.  It will copy the file1 name
	call	dbcs_check		; check for dbcs character
	jc	dbcs_3			; got a dbcs character, go copy.
	cmp	al,'.'			; extension.  The defult extension
	je	sj5			; of .BIN will be added in check_ext.
	stosb
	jmp	short copy1to2
dbcs_3:
	stosb				; Got a dbcs character. Copy
	lodsb				; two characters and then go to
	stosb				; next character in filename.
	jmp	short copy1to2

;******************************************************************************

sj5:
;	mov	byte ptr es:[di],00h	;   *d = 0;
	mov	ah,Set_DMA		; Use find_first to see if file2 is
	mov	dx,offset dma_buf	; a directory.	If it isn't, go to
	int	21h			; set f2cspot to point to the spot
	mov	ah,Find_First		; right after the backslash, and
	mov	dx,offset file2 	; fall through to no_second so that
	mov	cx,-1			; file1's name will be added to file2.
	int	21h
	jc	check_ext
	test	dma_buf+21,00010000b
	jNZ	DoDirectory
	jmp	Check_Ext
DoDirectory:
	mov	AL,'\'
	mov	di,f2cspot
	dec	di
	stosb
SetSecond:
	mov	per22,update
	inc	di
	mov	f2cspot,di
	jmp	maycopy


;----- Check that files have an extension, otherwise set default
check_ext:
	cmp	per11,noupdate		;   if (per1 == NULL) {
	jz	file1_ok
	mov	di,offset file1 	;	d = file1;
	mov	si,offset file1_ext	;	s = ".EXE";
	call	strcat			;	strcat (d, s);
file1_ok:				;	}
	cmp	per2,noupdate		;   if (per2 != NULL) {
	je	file2_ok
	mov	di,offset file2 	;	d = file2;
	mov	si,offset file2_ext	;	s = ".BIN";
	call	strcat			;	strcap (d, s);
	jmp	short file2_ok		;	}

;-----------------------------------------------------------------------;
file2_ok:
	mov	dx,offset file1
	mov	ax,(open SHL 8) + 0	;for reading only
	INT	21H			;Open input file
	jc	bad_file
	mov	[handle1],ax
	jmp	exeload

bad_file:
	pop	ds
	ASSUME	DS:NOTHING
	MESSAGE msgNoFile
	jmp	getout

BADEXE:
	pop	ds
	ASSUME	DS:nothing
	MESSAGE msgNoConvert
	jmp	getout

ReadError:
	jmp	DosError

EXELOAD:
	ASSUME	DS:DATA
	MOV	DX,OFFSET RUNVAR	;Read header in here
	MOV	CX,RUNVARSIZ		;Amount of header info we need
	push	bx
	mov	bx,[handle1]
	MOV	AH,read
	INT	21H			;Read in header
	pop	bx
	jc	ReadError
	CMP	[RELPT],5A4DH		;Check signature word
	JNZ	BADEXE
	MOV	AX,[HEADSIZ]		;size of header in paragraphs
	ADD	AX,31			;Round up first
	CMP	AX,1000H		;Must not be >=64K
	JAE	TOOBIG
	AND	AX,NOT 31
	MOV	CL,4
	SHL	AX,CL			;Header size in bytes

	push	dx
	push	cx
	push	ax
	push	bx
	mov	dx,ax
	xor	cx,cx
	mov	al,0
	mov	bx,[handle1]
	mov	ah,lseek
	int	21h
	jc	LseekError
	pop	bx
	pop	ax
	pop	cx
	pop	dx

	XCHG	AL,AH
	SHR	AX,1			;Convert to pages
	MOV	DX,[PAGES]		;Total size of file in 512-byte pages
	SUB	DX,AX			;Size of program in pages
	CMP	DX,80H			;Fit in 64K? (128 * 512 = 64k)
	JAE	TOOBIG
	XCHG	DH,DL
	SHL	DX,1			;Convert pages to bytes
	MOV	AX,[LASTP]		;Get count of bytes in last page
	OR	AX,AX			;If zero, use all of last page
	JZ	WHOLEP

	IF	OLDLINK
	    CMP     AX,4		;Produced by old linker?
	    JZ	    WHOLEP		;If so, use all of last page too
	ENDIF

	SUB	DX,200H 		;Subtract last page
	ADD	DX,AX			;Add in byte count for last page
WHOLEP:
	MOV	[SIZ],DX
	ADD	DX,15
	SHR	DX,CL			;Convert bytes to paragraphs
	MOV	BP,SEG LOAD
	ADD	DX,BP			;Size + start = minimum memory (paragr.)
	CMP	DX,BX			;Enough memory?
	JA	TOOBIG
	MOV	AX,[INITSS]
	OR	AX,[INITSP]
	OR	AX,[INITCS]
	JMP	ERRORNZ

TOOBIG:
	pop	ds
	ASSUME	DS:NOTHING
	MESSAGE msgOutOfMemory
	jmp	getout

LseekError:
	jmp	DosError


ERRORNZ:
	ASSUME	DS:DATA
	jz	xj
	JMP	BADEXE			;AC000; For ptm P475;
xj:	MOV	AX,[INITIP]
	OR	AX,AX			;If IP=0, do binary fix
	JZ	BINFIX
	CMP	AX,100H 		;COM file must be set up for CS:100
	JNZ	ERRORNZ

	push	dx
	push	cx
	push	ax
	push	bx
	mov	dx,100h 		;chop off first 100h
	xor	cx,cx
	mov	al,1			;seek from current position
	mov	bx,[handle1]
	mov	ah,lseek
	int	21h
	jc	LseekError
	pop	bx
	pop	ax
	pop	cx
	pop	dx

	SUB	[SIZ],AX		;And count decreased size
	CMP	[RELCNT],0		;Must have no fixups
	JNZ	ERRORNZ
BINFIX:
	XOR	BX,BX			;Initialize fixup segment
;See if segment fixups needed
	CMP	[RELCNT],0
	JZ	LOADEXE
GETSEG:
	pop	ds
	ASSUME	DS:NOTHING
	MESSAGE msgFixUp
	PUSH	DS
	PUSH	ES
	POP	DS
	ASSUME	DS:DATA
	MOV	AH,STD_CON_STRING_INPUT
	MOV	DX,OFFSET INBUF
	INT	21H			;Get user response
	MOV	SI,OFFSET INBUF+2
;;dcl;; MOV	BYTE PTR [SI-1],0	;Any digits?
	cmp	BYTE PTR [SI-1],0	;Any digits?
	JZ	GETSEG
DIGLP:
	LODSB
	SUB	AL,"0"
	JC	DIGERR
	CMP	AL,10
	JB	HAVDIG
	AND	AL,5FH			;Convert to upper case
	SUB	AL,7
	CMP	AL,10
	JB	DIGERR
	CMP	AL,10H
	JAE	DIGERR
HAVDIG:
	SHL	BX,1
	SHL	BX,1
	SHL	BX,1
	SHL	BX,1
	OR	BL,AL
	JMP	DIGLP

DIGERR:
	CMP	BYTE PTR [SI-1],0DH	;Is last char. a CR?
	JNZ	GETSEG
LOADEXE:
	XCHG	BX,BP			;BX has LOAD, BP has fixup

	MOV	CX,[SIZ]
	MOV	AH,read
	push	di
	mov	di,[handle1]
	PUSH	DS
	MOV	DS,BX
	ASSUME	DS:NOTHING
	XOR	DX,DX
	push	bx
	mov	bx,di
	INT	21H			;Read in up to 64K
	pop	bx
	POP	DS
	ASSUME	DS:DATA
	pop	di
	Jnc	HAVEXE			;Did we get it all?

	jmp	DosError

LseekError2:
	jmp	DosError

HAVEXE:
	ASSUME	DS:DATA
	CMP	[RELCNT],0		;Any fixups to do?
	JZ	STORE
	MOV	AX,[RELTAB]		;Get position of table

	push	dx
	push	cx
	push	ax
	push	bx
	mov	dx,ax
	xor	cx,cx
	mov	al,0
	mov	bx,[handle1]
	mov	ah,lseek
	int	21h
	jc	LseekError2
	pop	bx
	pop	ax
	pop	cx
	pop	dx

	MOV	DX,OFFSET RELPT 	;4-byte buffer for relocation address
RELOC:
	MOV	DX,OFFSET RELPT 	;4-byte buffer for relocation address
	MOV	CX,4
	MOV	AH,read
	push	bx
	mov	bx,[handle1]
	INT	21H			;Read in one relocation pointer
	pop	bx
	Jnc	RDCMP
	jmp	DosError
RDCMP:
	MOV	DI,[RELPT]		;Get offset of relocation pointer
	MOV	AX,[RELSEG]		;Get segment
	ADD	AX,BX			;Bias segment with actual load segment
	MOV	ES,AX
	ASSUME	ES:NOTHING
	ADD	ES:[DI],BP		;Relocate
	DEC	[RELCNT]		;Count off
	JNZ	RELOC
STORE:
	MOV	AH,CREAT
	MOV	DX,OFFSET file2
	xor	cx,cx
	INT	21H
	Jc	MKERR
	mov	[handle2],ax
	MOV	CX,[SIZ]
	MOV	AH,write
	push	di
	mov	di,[handle2]
	PUSH	DS
	MOV	DS,BX
	ASSUME	DS:NOTHING
	XOR	DX,DX			;Address 0 in segment
	push	bx
	mov	bx,di
	INT	21H
	pop	bx
	POP	DS
	ASSUME	DS:DATA
	pop	di
	Jc	WRTERR			;Must be zero if more to come
	cmp	AX,CX
	jnz	NOROOM
	MOV	AH,CLOSE
	push	bx
	mov	bx,[handle2]
	INT	21H
	jc	CloseError
	pop	bx
	pop	ds
	pop	ds
	ASSUME	DS:NOTHING

	RET

;*******************************************************************************

NOROOM: 				;
	ASSUME	DS:DATA
	MOV	AH,CLOSE		; Close the file here
	push	bx			;
	mov	bx,[handle2]		;
	INT	21H			;
	jc	CloseError		; If error let extend messages get it
	pop	bx			;
	mov	ah,UNLINK		; Delete the file because it did
	MOV	DX,OFFSET file2 	; not get written correctly.
	INT	21H			;
	jc	CloseError		; If error let extend messages get it
	pop	ds			;
	ASSUME	DS:NOTHING		;
	message msgNoDiskSpace		; Put out insufficient disk space
	jmp	getout			; message
	RET				; return to main_init

;*******************************************************************************

WRTERR:
MKERR:
CloseError:

	public	DosError
DosError:
	mov	es:FileNameSegment,ds	   ; save for opens, creates,
	mov	es:FileNameOffset,dx

	mov	bx,0			; get the extended error code
	mov	ah,059h
	int	21h

	mov	si,offset ds:Sublist_msg_exterror
	extend_message
	pop	ds

getout:
	pop	ds
	ASSUME	DS:NOTHING

	ret


LOCATE	ENDP

;----- concatenate two strings
strcat	proc	near			;   while (*d)
	cmp	byte ptr [di],0
	jz	atend
	inc	di			;	d++;
	jmp	strcat
atend:					;   while (*d++ = *s++)
	lodsb
	stosb
	or	al,al			;	;
	jnz	atend
	ret
strcat	endp

;----- Find the first non-ignorable char, return carry if CR found
kill_bl proc	near
	cld
sj10:					;   while ( *p != 13 &&
	lodsb
	CMP	AL,13			;	    IsBlank (*p++))
	JZ	BreakOut
	CALL	IsBlank
	JZ	SJ10			;	;
BreakOut:
	dec	si			;   p--;
	cmp	al,0dh			;   return *p == 13;
	clc
	jne	sj11
	stc
sj11:
	ret
kill_bl endp

IsBlank proc	near
	cmp	al,00
	retz
	cmp	al,13
	retz
	cmp	al,' '			; space
	retz
	cmp	al,9			; tab
	retz
	cmp	al,','			; comma
	retz
	cmp	al,';'			; semicolon
	retz
	cmp	al,'+'			; plus
	retz
	cmp	al,10			; line feed
	retz
	cmp	al,'='			; equal sign
	return
IsBlank Endp


procedure copyfs

	push	ax

;	$do				; while we have filespec
$$DO16:
	    lodsb			; move byte to al
	    cmp     al,0		; see if we are at
					; the end of the
					; filespec
;	$leave	e			; exit while loop
	JE $$EN16
	    stosb			; move byte to path_name
;	$enddo				; end do while
	JMP SHORT $$DO16
$$EN16:
	stosb
	pop	ax

	ret
copyfs	endp


procedure dbcs_check

	push	ds				;Save registers
	push	si				; "  "	  "  "
	push	ax				; "  "	  "  "
	push	ds				; "  "	  "  "
	pop	es				;Establish addressability
	cmp	byte ptr es:DBCS_VECTOR,Yes	;Have we set this yet?
	push	ax				;Save input character
;	$IF	NE				;Nope
	JE $$IF19
	   mov	   al,0 			;Get DBCS environment vectors
	   DOS_Call Hongeul			;  "  "    "  "
	   mov	   byte ptr es:DBCS_VECTOR,YES	;Indicate we've got vector
	   mov	   es:DBCS_Vector_Off,si	;Save the vector
	   mov	   ax,ds			;
	   mov	   es:DBCS_Vector_Seg,ax	;
;	$ENDIF					; for next time in
$$IF19:
	pop	ax				;Restore input character
	mov	si,es:DBCS_Vector_Seg		;Get saved vector pointer
	mov	ds,si				;
	mov	si,es:DBCS_Vector_Off		;
;	$SEARCH 				;Check all the vectors
$$DO21:
	   cmp	   word ptr ds:[si],End_Of_Vector ;End of vector table?
;	$LEAVE	E				;Yes, done
	JE $$EN21
	   cmp	   al,ds:[si]			;See if char is in vector
;	$EXITIF AE,AND				;If >= to lower, and
	JNAE $$IF21
	   cmp	   al,ds:[si+1] 		; =< than higher range
;	$EXITIF BE				; then DBCS character
	JNBE $$IF21
	   stc					;Set CY to indicate DBCS
;	$ORELSE 				;Not in range, check next
	JMP SHORT $$SR21
$$IF21:
	   add	   si,DBCS_Vector_Size		;Get next DBCS vector
;	$ENDLOOP				;We didn't find DBCS chaR
	JMP SHORT $$DO21
$$EN21:
	   clc					;Clear CY for exit
;	$ENDSRCH				;
$$SR21:
	pop	ax				;Restore registers
	pop	si				; "  "	  "  "
	pop	ds				;Restore data segment
	ret					;

	ret
dbcs_check  endp



CODE	ends


	end	main_init


