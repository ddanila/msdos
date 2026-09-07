page	,132				;
TITLE	RECINIT.SAL - MS-DOS File/Disk Recovery Utility
;*****************************************************************************
;*****************************************************************************
; Include files
;*****************************************************************************
;
 .xlist
	include pathmac.inc
 INCLUDE RECSEG.INC
	INCLUDE DOSSYM.INC
INCLUDE SYSCALL.INC
INCLUDE RECEQU.INC
INCLUDE RECMACRO.INC
INCLUDE RECPARSE.INC
 .list

;
;*****************************************************************************
; External Data Declarations
;*****************************************************************************
data	segment public para 'Data'
	EXTRN	movsi:word  ;move si pointer here for display of invalid parm
	extrn	command_line_buffer:byte
	extrn	ExitStatus:Byte
	Extrn	FATTbl:byte
	Extrn	SubstErr:Byte
	Extrn	NotNetM:Byte
	Extrn	User_Drive:Byte
	Extrn	Baddrv:Byte
	Extrn	Drive_Letter_Msg:Byte
	Extrn	Parse_Error_Msg:Byte
	extrn	fname_buffer:byte
	extrn	PSP_Segment:word
	extrn	fatal_error:byte
	extrn	found:byte
	extrn	done:byte
	extrn	bpb_buffer:byte
	extrn	data_start_low:word
	extrn	data_start_high:word
	extrn	driveletter:byte
	extrn	drive:byte
	extrn	transrc:byte
	extrn	int_23_old_off:word
	extrn	int_23_old_seg:word
	extrn	int_24_old_off:word
	extrn	int_24_old_seg:word
	extrn	append:byte
ifdef fsexec
	extrn	fat12_string:byte
	extrn	fat16_string:byte
	extrn	media_id_buffer:byte
	extrn	fs_not_fat:byte
	extrn	FS_String_Buffer:Byte
	extrn	FS_String_end:Byte
endif
data	ends


code	segment public para 'CODE'
	pathlabl recinit
;*****************************************************************************
; recinit procedures
;*****************************************************************************
public	Main_Init, Init_Io, Preload_Messages, Parse_recover
public	Parse_good, Parse_err, Validate_Target_Drive
public	 Check_Target_Drive, Check_For_Network, Check_Translate_Drive
public	 Hook_interrupts, Clear_Append_X, RECOVER_IFS, Reset_Append_X
public	exitpgm
;*****************************************************************************
; External Routine Declarations
;*****************************************************************************
;	Extrn	EXEC_FS_Recover:Near
	 Extrn	 SysLoadMsg:Near
	Extrn	SysDispMsg:Near
	Extrn	Main_Routine:Near
	Extrn	INT_23:Near
	Extrn	INT_24:Near

;*****************************************************************************
;Routine name:	MAIN_INIT
;*****************************************************************************
;
;description: Main routine for recover program
;
;Called Procedures: get_psp
;		    Init_IO
;		    Validate_Target_Drive
;		    Hook_Interrupts
;		    RECOVER_IFS (goes to main-routine)
;
;Input: None
;
;Output: None
;
;Psuedocode
;----------
;	get info from psp
;	Parse input and load messages (CALL Init_Input_Output)
;	IF no error
;	   Check target drive letter (CALL Validate_Target_Drive)
;	   IF no error
;	      Set up Control Break (CALL Hook_Interrupts)
;	      IF no error
;		 CALL RECOVER_IFS (goes to main routine)
;	      ENDIF
;	   ENDIF
;	ENDIF
;	Exit program
;*****************************************************************************
procedure Main_Init			;
	; Check for /? (CONVERT COM: CS=DG after CONVERT far-jmp, DS=DG)
	MOV	AH, 062H
	INT	21H			; BX = PSP segment
	MOV	ES, BX			; ES = PSP
	MOV	SI, 081H
RC_SKIP_SP:
	CMP	BYTE PTR ES:[SI], ' '
	JNE	RC_CHK_SL
	INC	SI
	JMP	SHORT RC_SKIP_SP
RC_CHK_SL:
	CMP	BYTE PTR ES:[SI], '/'
	JNE	RC_NO_HELP
	CMP	BYTE PTR ES:[SI+1], '?'
	JE	RC_DO_HELP
RC_NO_HELP:
	JMP	RC_CONTINUE
RC_DO_HELP:
	CALL	RC_HELP_END
RC_HELP_STR DB "RECOVER [drive:][path]filename",0Dh,0Ah
	DB 0Dh,0Ah
	DB "  Recovers readable information from a bad-sector disk.",0Dh,0Ah,"$"
RC_HELP_END:
	POP	DX
	PUSH	CS
	POP	DS			; DS = CS = DG
	MOV	AH, 09H
	INT	21H
	MOV	AX, 4C00H
	INT	21H
RC_CONTINUE:
	xor	bp,bp
	Set_Data_Segment		;Set DS,ES to Data segment
	call	get_psp
	mov	Fatal_Error,No		;Init the error flag
	call	Init_Io 		;Setup messages and parse
	cmp	Fatal_Error,Yes 	;Error occur?
;	$IF	NE			;Nope, keep going
	JE $$IF1
	    call    Validate_Target_Drive ;Check drive letter
	    cmp     Fatal_Error,Yes	;Error occur?
;	    $IF     NE			;Nope, keep going
	    JE $$IF2
		call	Hook_Interrupts ;Set CNTRL -Break hook
		cmp	Fatal_Error,Yes ;Error occur?
;		$IF	NE		;Nope, keep going
		JE $$IF3
		    call    RECOVER_IFS ;RECOVER correct file system
;		$ENDIF			;
$$IF3:
;	    $ENDIF			;
$$IF2:
;	$ENDIF				;
$$IF1:
exitpgm: mov	 al,ExitStatus		 ;Get Errorlevel
	DOS_Call Exit			;Exit program
	int	20h			;If other exit fails

Main_Init endp				;

;*****************************************************************************
;Routine name: get_psp
;*****************************************************************************
;Description: get info from the psp area
;
;Called Procedures: get_drive
;
;Input: none
;
;Output: psp_segment
;	 command_line_buffer
;
;Psuedocode
;----------
;	get addr of psp
;	move command line into data seg
;	get drive number of target
;	get addr of data seg
;	call get_drive
;	ret
;*****************************************************************************
Procedure get_psp			;
	DOS_Call GetCurrentPSP		;Get PSP segment address	:AN000;bgb
	mov	PSP_Segment,bx		;Save it for later
; get command line from psp
	mov	cx,PSP_Segment		;point ds to data seg
	mov	ds,cx			;  "   "   "   "    "
	assume	ds:NOTHING,es:dg	;  "   "   "   "    "
	mov	si,Command_Line_Parms	;ds:si --> old area in psp
	LEA	di,command_line_buffer ; es:di -> new area in data
	mov	cx,128			; do for 128 bytes
	rep	movsb			; mov 1 byte until cx=0
; get the drive number of the target from the psp (0=default, a=1, b=2, c=3)
	mov	bl,ds:[FCB1]	    ;Get target drive from FCB -74
	Set_Data_Segment	    ;Set DS,ES to Data segment
	call	get_drive
	ret
get_psp   endp				;


;*****************************************************************************
;Routine name: get_drive
;*****************************************************************************
;Description: get drive letter from reg bl
;
;Input: bl = drive num (default=0)
;
;Output: driveletter
;	 drive_letter_msg
;	 user_drive
;
;Psuedocode
;----------
;	IF drive-num = default
;	   get default drive number (a=1)
;	   convert to letter
;	ELSE
;	   convert to letter
;	ENDIF
;	move letter into data areas
;	ret
;*****************************************************************************
Procedure get_drive			;
; convert drive number to drive letter
	    cmp     bl,0  ;a=1 b=2 c=3	;Is it default drive? 0=default
;	    $IF     E			;Yes, turn it into drive letter
	    JNE $$IF7
; get default drive number
		DOS_Call Get_Default_Drive ;Get default drive num in al
					;a=0, b=1, c=2
		mov	drive,al	;
;	    $ELSE			;Not default, A=1
	    JMP SHORT $$EN7
$$IF7:
; bl already contains the correct drive number - save it
		dec	bl		;a=0 b=1 c=2
		mov	drive,bl	;
		mov	al,bl
;	    $ENDIF			; 74+40=b4
$$EN7:
	    add     al,"A"		;convert it to letter
	    mov     driveletter,al	;set up prompt msg
	    mov     Drive_Letter_Msg,al ;Save it in message
	    mov     User_Drive,al	;Put it into path strings	;     ;
	ret
get_drive endp				;

;*****************************************************************************
;Routine name: Init_Io
;*****************************************************************************
;description: Initialize messages, Parse command line if FAT file system
;
;Called Procedures: Preload_Messages
;		   Parse_Recover
;
;Change History: Created	5/10/87 	MT
;
;Input: PSP command line at 81h and length at 80h
;
;Output: FS_Not_FAT = YES/NO
;	 Drive_Letter_Msg set up for any future messages that need it
;
;Psuedocode
;----------
;	Load messages (CALL Preload_Messages)
;	IF no fatal error
;	   Get file system type (12-bit fat, 16-bit fat, big fat, ifs)
;	   IF old-type-diskette, or
;	      dos4.00 12-bit fat, or
;	      dos4.00 16-bit fat, then
;	      Go handle FAT based Recover syntax's (Call Parse_Recover)
;	   ELSE
;	      FS_Not_FAT = YES
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************
Procedure Init_IO			;
; load the error messages from the system
	call	Preload_Messages	;Load up message retriever
ifdef fsexec
	mov	FS_Not_FAT,No
	cmp	Fatal_Error,YES 	;Quit?
;	$IF	NE			;Nope, keep going
	JE $$IF10
; get file system type from ioctl
	    mov     al,generic_ioctl	 ;al=0d (get media id)
	    xor     bx,bx		;use default drive		;AN009;b;an022;bgbgb
	    mov     ch,Rawio		;8 = disk io
	    mov     cl,Get_Media_Id	;66h
	    lea     dx,Media_ID_Buffer ;Point at buffer
	    DOS_Call IOCtl		;Do function call ah=44
; is it DOS 3.3 or below?			;carry flag means old dos
;	    $IF     C,OR		;Old style diskette, OR
	    JC $$LL11
; is it a new-12 bit fat?
	       lea     si,FAT12_String ;Check for FAT_12 string
	       lea     di,Media_ID_Buffer.Media_ID_File_System ;	    ;AN0;an022;bgb00;
	       mov     cx,Len_FS_ID_String ;Length of compare		   ;AN00;an022;bgb0;
	       repe    cmpsb		   ;Find it?			   ;AN00;an022;bgb0;
;	    $IF     E,OR		;Nope, keep going
	    JE $$LL11
; is it a new 16-bit fat?
	       lea     si,FAT16_String ;Check for FAT_16 string
	       lea     di,Media_ID_Buffer.Media_ID_File_System ;	    ;AN0;an022;bgb00;
	       mov     cx,Len_FS_ID_String ;Length of compare		   ;AN00;an022;bgb0;
	       repe    cmpsb		   ;Do compare			   ;AN00;an022;bgb0;
;	    $IF     E			; is it new 16-bit fat?
	    JNE $$IF11
$$LL11:
endif
; file system is fat based, continue (old or new)
		call	Parse_Recover	;Yes, go sort out syntax
; non-fat based system
ifdef fsexec
;	    $ELSE			;We got FS other than FAT
	    JMP SHORT $$EN11
$$IF11:
		mov	FS_Not_FAT,Yes	;Indicate exec file system
		mov	cx,8
		lea	si,Media_ID_Buffer.Media_ID_File_System ;get file system
		lea	di,fs_string_buffer ;put it here
		rep	movsb
		lea	di,fs_string_buffer ;point to beginning again
;		$DO	COMPLEX 	;search th string until eol found
		JMP SHORT $$SD13
$$DO13:
		    inc     di		;next char
;		$STRTDO 		;start loop here
$$SD13:
		    cmp     byte ptr [di],' '	 ;end of string ?
;		$ENDDO	E		;end loop when eol found
		JNE $$DO13
		lea	si,fs_string_end ;get end of string - rec.exe
		mov	cx,8		; 8 more chars
		rep	movsb		;move it in
;	    $ENDIF			; fat based file system
$$EN11:
;	$ENDIF				; no error from msg retreiver	   ;AN00;an022;bgb0;
$$IF10:
endif
	ret				;
Init_Io 	  endp			;

;*****************************************************************************
;Routine name: Preload_Messages
;*****************************************************************************
;Description: Preload messages using common message retriever routines.
;
;Called Procedures: SysLoadMsg
;
;Change History: Created	5/1/87	       MT
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;	Preload All messages (Call SysLoadMsg)
;	IF error
;	   Display SysLoadMsg error message
;	   Fatal_Error = YES
;	ENDIF
;	ret
;*****************************************************************************
Procedure Preload_Messages		;;AN000;						 ;
	call	SysLoadMsg		;Preload the messages
;	$IF	C			;Error?
	JNC $$IF18
	    call    SysDispMsg		;Display preload msg
	    mov     Fatal_Error, YES	;Indicate error exit
;	$ENDIF				;
$$IF18:
	ret				;

Preload_Messages endp			;

;*****************************************************************************
;Routine name: Parse_Command_Line
;*****************************************************************************
;Description: Parse the command line. Check for errors, and display error and
;		 exit program if found. Use parse error messages except in case
;		 of no parameters, which has its own message
;
;Called Procedures: Message (macro)
;		    SysParse
;		    parse_good
;		    parse_err
;
;Change History: Created	5/1/87	       MT
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 PARSE-ADDR
;	 DRIVELETTER
;	 PARSE-ADDR
;
;Psuedocode
;----------
;    set up regs to call sysparse
;DO UNTIL error=yes or return(ax)=finish(-1)
;    call sysparse
;    IF ax=good return(0)
;	   call parse-good
;    ELSE
;	   call parse-err
;    ENDIF
;ENDLOOP
;ret
;
;A. normal proc ==  1- ax=good 0
;		    2- ax=done -1
;B. no parm	==  1- ax=error 2
;
;C. too many	==  1- ax=good 0
;		    2- ax=error 1
;D. syntax	==  1- ax=error 9
;*****************************************************************************
Procedure Parse_recover 		;
	push	ds			; save ds
; set up to call sysparse
	set_data_segment		;ds,es point to data seg
	LEA	si,command_line_buffer ;ds:si -> cmd line
	LEA	di,parms_input_block   ;es:di--> parms input block
	xor	cx,cx			;cx = 0
	xor	dx,dx			;dx = 0
	mov	done,no
; call sysparse until error or end of cmd line
;	$DO
$$DO20:
	    call    SysParse		;go parse
	    cmp     ax,$p_rc_eol	; -1 end of command line?
;	    $LEAVE  E			; yes - done
	    JE $$EN20
	    cmp     ax,$p_no_error	; good return code ??? (0)
;	    $IF     E			; yes
	    JNE $$IF22
		call	parse_good	; go get it
;	    $ELSE			; ax not= good
	    JMP SHORT $$EN22
$$IF22:
		call	parse_err	; check for error
;	    $ENDIF			; eol
$$EN22:
	    cmp     Fatal_Error,YES	;Can we continue?
;	    $LEAVE  E			    ;NO
	    JE $$EN20
;	$ENDDO				;
	JMP SHORT $$DO20
$$EN20:
	pop	ds			;
	ret				;
Parse_recover endp			;
;*****************************************************************************
;Routine name: parse_good
;*****************************************************************************
;
;Description: when the ax register returned by sysparse indicates and error,
;	      this procedure is called.  it then determines which error
;	      occurred, and calls parse_message to display the msg.
;
;Called Procedures: parse_message (macro)
;
;Change History: Created	7/23/87 	bgb
;
;Input:
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;
;	  found=yes
;	  IF data=drive
;	       save drive number and letter
;	  ELSE
;	       IF data=filespec
;		    save filespec
;	       ELSE
;		    call parse-msg
;	       ENDIF
;	  ENDIF
;*****************************************************************************
;
Procedure Parse_good			;
	cmp	parse_type,$p_drive  ; 6 if data=drive
;	$IF	E			; not eol, good syntax, drive entered
	JNE $$IF27
	    mov     bl,byte ptr parse_addr
	    dec     bl			;Make drive 0 based
	    mov     drive,bl
	    add     bl,'A'		;make it character
	    mov     driveletter,bl	;save into drive letter
;	$ELSE				; no - filespec entered
	JMP SHORT $$EN27
$$IF27:
	    cmp     parse_type,$p_file_spec ; 5 if data = filespec
;	    $IF     E			; was file spec entered
	    JNE $$IF29
;		    push    si		; save input offset reg
;		    push    ds		; save input seg reg
;		    push    cx		; save count
;		    push    es		; save other seg reg
;		    mov     cx,ds	;es points to data
;		    mov     es,cx	;es points to data
;		    mov     si,word ptr parse_addr ;get offset to filespec
;		    mov     ds,word ptr parse_addr+2 ;get segment to filespec
;		    mov     cx,128	; mov 128 bytes
;		    rep     movs es:fname_buffer,ds:[si] ;move it
;		    pop     es		; save other seg reg
;		    pop     cx		; save other seg reg
;		    pop     ds		; save other seg reg
;		    pop     si		; save other seg reg
;	    $ELSE			; no, no drive or filespec
	    JMP SHORT $$EN29
$$IF29:
		mov	ax,$p_syntax	;tell user bad syntax
		parse_message		;display msg
		mov Fatal_Error,YES ;Indicate death!
;	    $ENDIF			; was drive entered ?
$$EN29:
;	$ENDIF				;if data=drive
$$EN27:
	ret				;
parse_good endp 			;

;*****************************************************************************
;Routine name: parse_err
;*****************************************************************************
;
;Description: when the ax register returned by sysparse indicates and error,
;	      this procedure is called.  it then determines which error
;	      occurred, and calls parse_message to display the msg.
;
;Called Procedures: parse_message (macro)
;
;Change History: Created	7/23/87 	bgb
;
;Input:
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;
;	  IF ax=done	   (end of cmd line?) -1
;	       IF found=no (eol, but no parameters listed)
;		    call parse-msg
;	       ENDIF
;	  ELSE		   (error other than eol)
;	       call parse-msg
;	  ENDIF
;*****************************************************************************
;
Procedure Parse_err			;
	mov Fatal_Error,YES ;Indicate death!
	cmp ax,$P_Op_Missing		; 2 = no parameters ?
;	$IF E				;
	JNE $$IF33
	    message baddrv		; yes (invalid drive or filename)
;	$ELSE
	JMP SHORT $$EN33
$$IF33:
	   mov	   byte ptr [si],00	;zero terminate display string
	   dec	   si			;look at previous char
nextsi:
public nextsi
	   dec	   si			;look at previous char
	   cmp	   byte ptr [si],' '	;find parm separator
	   jnz	   nextsi		;loop until begin of parm found
	   mov	   movsi,si		;mov si into display parms
	    parse_message		;no- display parse message
;	$ENDIF
$$EN33:
	ret				;
parse_err endp				;


;*****************************************************************************
;Routine name: Validate_Target_Drive
;*****************************************************************************
;
;Description: Control routine for validating the specified format target drive.
;	      If any of the called routines find an error, they will print
;	      message and terminate program, without returning to this routine
;
;Called Procedures: Check_Target_Drive
;		    Check_For_Network
;		    Check_Translate_Drive
;
;Change History: Created	5/1/87	       MT
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;
;	CALL Check_Target_Drive
;	IF !Fatal_Error
;	   CALL Check_For_Network
;	   IF !Fatal_Error
;	      CALL Check_Translate_Drive
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure Validate_Target_Drive 	;
	call	Check_For_Network	;See if Network drive letter
	cmp	Fatal_Error,YES 	;Can we continue?
;	$IF	NE			;Yep
	JE $$IF36
	    call    Check_Translate_Drive ;See if Subst, Assigned
	    call    Check_Target_Drive	;See if valid drive letter
;	$ENDIF				;- Fatal_Error passed back
$$IF36:
	ret				;

Validate_Target_Drive endp		;

;*****************************************************************************
;Routine name: Check_Target_Drive
;*****************************************************************************
;
;Description: Check to see if valid DOS drive by checking if drive is
;	      removable. If error, the drive is invalid. Save default
;	      drive info. Also get target drive BPB information, and compute
;	      the start of the data area
;
;Called Procedures: Message (macro)
;
;Change History: Created	5/1/87	       MT
;
;Input: Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 User_Drive = default drive
;
;Psuedocode
;----------
;
;	Get default drive
;	See if drive LOCAL     (INT 21h, AX=4409h IOCtl)
;	IF error - drive invalid
;	   Display Invalid drive message
;	   Fatal_Error= YES
;	ENDIF
;	Get BPB of target drive (Generic IOCtl Get Device parameters)
;	Compute start of data area
;	ret
;*****************************************************************************
;
Procedure Check_Target_Drive		;
	mov	al,0Dh			;Get BPB information
	mov	cx,0860h		; "  "	 "  "
;;;;;;;;mov	bl,byte ptr parse_addr	; "  "	 "  "
	mov	bl,drive		;drive number	 ;A=0,B=1
	inc	bl			;a=1
	lea	dx,BPB_Buffer	 ; "  "   "  "
	DOS_Call IOCtl			; "  "	 "  "
	xor	cx,cx			;Find # sectors used by FAT's
	mov	cl,BPB_Buffer.NumberOfFATs ; "  "   "  "
	mov	ax,BPB_Buffer.SectorsPerFAT ; "  "   "  "
	mul	cx			; "  "	 "  "
	push	dx			;Save results
	push	ax			;     "  "
	mov	ax,BPB_Buffer.RootEntries ;Find number of sectors in root
	mov	cl,Dir_Entries_Per_Sector ; by dividing RootEntries
	div	cl			; by (512/32)
	pop	bx			;Get low sectors per FAT back
	pop	dx			;Get high part
	add	ax,bx			;Add to get FAT+Dir sectors
	adc	dx,bp ;zero		;High part
	add	ax,ReservedSectors	;Add in Boot record sectors
	adc	dx,bp ;zero		;to get start of data (DX:AX)
	mov	Data_Start_Low,ax	;Save it
	mov	Data_Start_High,dx	;
	ret				;And we're outa here
Check_Target_Drive endp 		;

;*****************************************************************************
;Routine name: Check_For_Network
;*****************************************************************************
;
;Description: See if target drive isn't local, or if it is a shared drive. If
;	      so, exit with error message. The IOCtl call is not checked for
;	      an error because it is called previously in another routine, and
;	      invalid drive is the only error it can generate. That condition
;	      would not get this far
;
;Called Procedures: Message (macro)
;
;Change History: Created	5/1/87	       MT
;
;Input: Drive
;	   Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;	See if drive is local (INT 21h, AX=4409 IOCtl)
;	IF not local
;	   Display network message
;	   Fatal_ERROR = YES
;	ELSE
;	   IF  8000h bit set on return
;	      Display assign message
;	      Fatal_Error = YES
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure Check_For_Network		;
; is device local?  int 21, ah=44, al=9
	mov	bl,drive		;drive number	 ;A=0,B=1
	inc	bl			;drive number	 ;A=1,B=2 for IOCtl call
	mov	al,09h			;See if drive is local
	DOS_Call IOCtl			;-this will fail if bad drive
;	$IF	C			;CarrY means invalid drive
	JNC $$IF38
	    Message BadDrv		;Print message
	    mov     Fatal_Error,Yes	;Indicate error
;	$ELSE
	JMP SHORT $$EN38
$$IF38:
	    test    dx,Net_Check	;if (x & 1200H)(redir or shared);     ;
;	    $IF     NZ			;Found a net drive
	    JZ $$IF40
		Message NotNetM 	;Tell 'em
		mov	Fatal_Error,Yes ;Indicate bad stuff
;	    $ELSE			;Local drive, now check assign
	    JMP SHORT $$EN40
$$IF40:
		test	dx,Assign_Check ;8000h bit is bad news		;     ;
;		$IF	NZ		;Found it
		JZ $$IF42
		    Message SubstErr	;Tell error
		    mov     Fatal_Error,Yes ;Indicate bad stuff
;		$ENDIF			;
$$IF42:
;	    $ENDIF			;
$$EN40:
;	$ENDIF				;
$$EN38:
	ret				;

Check_For_Network endp			;

;*****************************************************************************
;Routine name: Check_Translate_Drive
;*****************************************************************************
;
;Description: Do a name translate call on the drive letter to see if it is
;	      assigned by SUBST or ASSIGN
;
;Called Procedures: Message (macro)
;
;Change History: Created	5/1/87	       MT
;
;Input: Drive_Letter_Msg has drive string
;	   Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;
;Psuedocode
;----------
;	Put drive letter in ASCIIZ string "d:\",0
;	Do name translate call (INT 21)
;	IF drive not same
;	   Display assigned message
;	   Fatal_Error = YES
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure Check_Translate_Drive 	;
	mov	al,Drive_Letter_Msg	;Get target drive letter into
	mov	TranSrc,al		; "d:\",0 string
	lea	si,TranSrc	 ;Point to translate string
	push	ds			;Set ES=DS (Data segment)	;     ;
	pop	es			;     "  "	"  "		;     ;
	lea	di,FatTbl	 ;Point at output buffer	 ;     ;
	DOS_Call xNameTrans		;Get real path
;	$IF	NC
	JC $$IF46
	    mov     bl,byte ptr [TranSrc]   ;Get drive letter from path     ;	  ;
	    cmp     bl,byte ptr [Fattbl]    ;Did drive letter change?	    ;	  ;
;	    $IF     NE			    ;If not the same, it be bad
	    JE $$IF47
		Message SubstErr	    ;Tell user
		mov	Fatal_Error,Yes     ;Setup error flag
;	    $ENDIF			    ;
$$IF47:
;	$ELSE
	JMP SHORT $$EN46
$$IF46:
	    mov     Fatal_Error,Yes	;Setup error flag
	    mov     bx,1
	    mov     cx,bp ;zero
	    mov     dx,0100h
	    call    sysdispmsg
;	$ENDIF				;
$$EN46:
	ret				;

Check_Translate_Drive endp		;

;*****************************************************************************
;Routine name: Hook_Interrupts
;*****************************************************************************
;
;Description: Change the interrupt handler for INT 13h to point to the
;	      ControlC_Handler routine
;
;Called Procedures: None
;
;Change History: Created	4/21/87 	MT
;
;Input: None
;
;Output: None
;
;Psuedocode
;----------
;
;	Point at ControlC_Handler routine
;	Set interrupt handler (INT 21h, AX=2523h)
;	ret
;*****************************************************************************
;
 Procedure Hook_Interrupts		 ;
	mov	al,23h
	DOS_Call Get_Interrupt_Vector	;Get the INT 23h handler
	mov	word ptr INT_23_Old_Off,bx ;
	mov	bx,es			;
	mov	word ptr INT_23_Old_Seg,bx ;
	mov	al,23h			;Specify CNTRL handler		;     ;
	lea	dx, INT_23	 ;Point at it			 ;     ;
	push	ds			;Save data seg			;     ;
	push	cs			;Point to code segment		;     ;
	pop	ds			;				;     ;
	DOS_Call Set_Interrupt_Vector	;Set the INT 23h handler
	pop	ds			;Get Data degment back		;     ;
	mov	al,24h			;
	DOS_Call Get_Interrupt_Vector	;Get the INT 24h handler
	mov	word ptr INT_24_Old_Off,bx ;Save it
	mov	bx,es			;
	mov	word ptr INT_24_Old_Seg,bx ;
	mov	al,24h			;Specify handler		 ;     ;
	lea	dx, INT_24	 ;Point at it			 ;     ;
	push	ds			;Save data seg			;     ;
	push	cs			;Point to code segment		;     ;
	pop	ds			;				;     ;
	DOS_Call Set_Interrupt_Vector	;Set the INT 23h handler
	pop	ds			;Get Data degment back		;     ;
	ret				;

 Hook_Interrupts endp			 ;

;*****************************************************************************
;Routine name: Hook_CNTRL_C
;*****************************************************************************
;
;Description: Change the interrupt handler for INT 13h to point to the
;	      ControlC_Handler routine
;
;Called Procedures: None
;
;Change History: Created	4/21/87 	MT
;
;Input: None
;
;Output: None
;
;Psuedocode
;----------
;
;	Point at ControlC_Handler routine
;	Set interrupt handler (INT 21h, AX=2523h)
;	ret
;*****************************************************************************
;
;rocedure Hook_CNTRL_C				;
;	mov	al,23H				;Specify CNTRL handler		;     ;
;	mov	dx, offset ControlC_Handler	;Point at it			;     ;
;	push	ds				;Save data seg			;     ;
;	push	cs				;Point to code segment		;     ;
;	pop	ds				;				;     ;
;	DOS_Call Set_Interrupt_Vector		;Set the INT 23h handler
;	pop	ds				;Get Data degment back		;     ;
;	ret					;
;ook_CNTRL_C endp				;
;
;ontrolC_Handler:
;	set_data_segment
;;;;;;; Message msgInterrupt			;
;;;;;;;;mov	ExitStatus, ExitCtrlC
;	jmp	ExitPgm
;*****************************************************************************
;Routine name: Clear_Append_X
;*****************************************************************************
;
;Description: Determine if Append /XA is turned on thru INT 2Fh, and shut
;	      off for life of RECOVER if it is.
;
;Called Procedures: None
;
;
;Change History: Created	5/13/87 	MT
;
;Input: None
;
;Output: APPEND = YES/NO
;
;Psuedocode
;----------
;
;	Append = NO
;	See if APPEND /X is present (INT 2Fh, AX=0B706h)
;	IF present
;	   Turn append /X off (INT 2Fh, AX=B707h, BX = 0)
;	   Append = YES
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure Clear_Append_X		;
	mov	Append,NO		;Init the Append /X flag
	mov	ax,Append_X		;Is Append /X there?
	int	Multiplex		; "  "	   "  "
	cmp	bx,Append_X_Set 	;Was it turned on?
;	$IF	E			;Yep
	JNE $$IF51
	    mov     Append,YES		;Indicate that it was on
	    mov     ax,Set_Append_X	;Turn Append /X off
	    xor     bx,bx ;Append_Off	    ; "  "    "  "
	    int     Multiplex		; "  "	  "  "
;	$ENDIF				;
$$IF51:
	ret				;

Clear_Append_X endp			;


;*****************************************************************************
;Routine name: RECOVER_IFS
;*****************************************************************************
;
;description:
;
;Called Procedures: Main_Routine
;		   EXEC_FS_RECOVER
;
;Change History: Created	5/8/87	       MT
;
;Input: FS_Not_FAT = Yes/No
;
;Output: None
;
;Psuedocode
;----------
;
;	IF File system other than FAT
;	   Go call file system specific RECOVER (CALL EXEC_FS_RECOVER)
;	ELSE
;	   Do FAT based RECOVER (CALL Main_Routine)
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure RECOVER_IFS			;
ifdef fsexec
;	cmp	FS_Not_Fat,YES		;Is the target FS a FAT?
;	$IF	E			;No, so need to exec the
;	    call    EXEC_FS_RECOVER	; file system specific prog.
;	$ELSE				;It's a FAT
endif
	    call    clear_append_x	;BGB
	    call    Main_Routine	;Use canned code!
	    call    reset_append_x	;BGB
ifdef fsexec
;	$ENDIF				;
endif
	ret				;

RECOVER_IFS endp			;

;*****************************************************************************
;Routine name: Reset_Append_X
;*****************************************************************************
;
;description: If APPEND /XA was on originally, turn it back on
;
;Called Procedures: None
;
;
;Change History: Created	5/13/87 	MT
;
;Input: None
;
;Output: APPEND = YES/NO
;
;Psuedocode
;----------
;
;	IF APPEND = YES
;	   Turn append /X on (INT 2Fh, AX=B707h, BX = 1)
;	ENDIF
;	ret
;*****************************************************************************
;
Procedure Reset_Append_X		;
	cmp	Append,Yes		;Was Append /X on to start with?
;	$IF	E			;Yep
	JNE $$IF53
	    mov     ax,Set_Append_X	;Turn Append /X off
	    mov     bx,Append_On	; "  "	  "  "
	    int     Multiplex		; "  "	  "  "
;	$ENDIF				;
$$IF53:
	ret				;

Reset_Append_X endp			;

	pathlabl recinit
code	ends
	end main_init

