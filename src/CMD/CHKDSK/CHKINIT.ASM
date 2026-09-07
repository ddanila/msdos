page	,132					;
;*****************************************************************************
;*****************************************************************************
;UTILITY NAME: CHKOVER.COM
;
;MODULE NAME: CHKINIT.SAL
;
;�����������Ŀ
;� Main_Init �
;�������������
;  �
;  ������������������Ŀ     ����������������Ŀ
;  ôInit_Input_Output�����´Preload_Messages�
;  ��������������������    �������������������
;  �			   ��������������������Ŀ
;  �			   ôParse_Drive_Letter �
;  �			   ����������������������
;  �			   ��������������������Ŀ
;  �			   ôParse_Command_Line �
;; �			   ����������������������
;  �			   ����������������Ŀ
;  �			   ��Interpret_Parse�
;  �			    �����������������
;  ����������������������Ŀ ������������������Ŀ
;  ôValidate_Target_Drive�´Check_Target_Drive�
;  �����������������������ٳ��������������������
;  �			   ������������������Ŀ
;  �			   ôCheck_For_Network�
;  �			   ��������������������
;  �			   ����������������������Ŀ
;  �			   ��Check_Translate_Drive�
;  �			    �����������������������
;  ����������������Ŀ
;  ôHook_Interrupts�
;  ������������������
;  ���������������Ŀ
;  ôClear_Append_X�
;  �����������������
;  �����������Ŀ ��������������Ŀ
;  ôCHKDSK_IFS�´EXEC_FS_CHKDSK�
;  ������������ٳ����������������
;  �		�������������Ŀ
;  �		��Main_Routine�
;  �		 ��������������
;  ���������������Ŀ
;  ��Reset_Append_X�
;   ����������������
;*****************************************************************************
;;an099;dcl for p3202
;*****************************************************************************

;
;*****************************************************************************
; Include files
;*****************************************************************************
.xlist
include chkseg.inc
include pathmac.inc
INCLUDE CHKEQU.INC				;
INCLUDE CHKCHNG.INC				;List of changes
include dossym.inc
INCLUDE SYSCALL.INC				;
INCLUDE CHKMACRO.INC				;
INCLUDE CHKPARSE.INC				;
INCLUDE IOCTL.INC
.list
psp    segment public para 'DUMMY'
	org	05Ch
FCB1	label	byte
	org	06Ch
FCB2	label	byte
psp    ends
DATA	segment public para 'DATA'
;*****************************************************************************
; Data	Area
;*****************************************************************************
old_drive db 0

include version.inc

IF  IBMCOPYRIGHT

ELSE

myramdisk db 'RDV 1.20'

ENDIF

myvdisk   db 'VDISK'
bytes_per_sector     dw   0
BPB_Buffer A_DeviceParameters <>		;
Data_Start_Low dw ?				;
Data_Start_High dw ?				;
public command_line_buffer
Command_Line_Buffer db 128 dup(0)		;
Command_Line_Length equ $ - Command_Line_Buffer ;
Fatal_Error db	0				;
Command_Line db NO				;
Append	db	0				;
ifdef	fsexec
 ;These should stay together			 ;
 ; ---------------------------------------	 ;  ;
 FS_String_Buffer db 13 dup(" ")		 ;
 FS_String_End db "CHK.EXE",0			 ;
 Len_FS_String_End equ $ - FS_String_End	 ;
 ;----------------------------------------	 ;
 FS_Not_Fat db	 0				 ;
 FAT12_String db "FAT12   "			 ;
 FAT16_String db "FAT16   "			 ;
 Len_FS_ID_String equ $ - FAT16_String		 ;
 Media_ID_Buffer Media_ID <>			 ;
endif

ExitStatus db	0				;
PSP_Segment dw	0				;
tot_bytes_lo  dw  0		     ; low word of number of sectors in disk
tot_bytes_hi  dw  0		     ;high word of number of sectors in disk
fat_dir_secs  dw  0		     ;sectors in fat, directory and resvd
;*****************************************************************************
; Public Data Declarations
;*****************************************************************************
	public	bpb_buffer
	public	tot_bytes_lo
	public	tot_bytes_hi
	public	fat_dir_secs
	public	bytes_per_sector
	Public	Data_Start_Low
	Public	Data_Start_High
	Public	Fatal_Error
	Public	ExitStatus
	Public	PSP_Segment
ifdef	fsexec
	Public	FS_String_Buffer
endif
;*****************************************************************************
; External Data Declarations
;*****************************************************************************
	EXTRN	movsi:word  ;move si pointer here for display of invalid parm
	EXTRN	fatcnt:Byte
	EXTRN	AllDrv:Byte
	EXTRN	VolNam:Byte
	EXTRN	BadDrvM:Byte
	EXTRN	OrphFCB:Byte
	EXTRN	Arg_Buf:Byte
	EXTRN	Noisy:Byte
	EXTRN	DoFix:Byte
	EXTRN	SubstErr:Byte
	EXTRN	No_Net_Arg:Byte
	EXTRN	UserDev:Byte
	EXTRN	BadDrv_Arg:Byte
	EXTRN	TranSrc:Byte
	EXTRN	ContCh:Word
	EXTRN	HardCh:Word
	EXTRN	Fragment:Byte
	EXTRN	Parse_Error_Msg:Byte
	EXTRN	Chkprmt_End:Byte
	extrn	save_drive:byte
	EXTRN	Read_Write_Relative:Byte
	EXTRN	inval_media:byte
data	ends
code	segment public para 'CODE'
;*****************************************************************************
; External Routine Declarations
;*****************************************************************************
ifdef	fsexec
	EXTRN	Exec_FS_CHKDSK:Near
endif
	EXTRN	SysLoadMsg:Near
	EXTRN	SysDispMsg:Near
	EXTRN	Done:Near
	EXTRN	Main_Routine:Near
	EXTRN	INT_23:Near
	EXTRN	INT_24:Near
	EXTRN	Path_Name:Near
	extrn	read_once:near

	public	p97, multiply_32_bits
	public	func60
	public	hook_interrupts
	public get_bpb

   pathlabl chkinit
;*****************************************************************************
;Routine name:	Main_Init
;*****************************************************************************
;Description: Main control routine for init section
;Called Procedures: Check_DOS_Version
;		    Init_Input_Output
;		    Validate_Target_Drive
;		    Hook_Interrupts
;		    Clear_Append_X
;		    CHKDSK_IFS
;		    Reset_Append_X
;Input: None
;Output: None
;Psuedocode
;----------
;	Set segregs to DATA
;	Get segment of PSP
;	Fatal_Error = NO
;	Flush all buffers (INT 21h AH=0Dh)
;	Parse input and load messages (CALL Init_Input_Output)
;	IF !Fatal_Error
;	   Check target drive letter (CALL Validate_Target_Drive)
;	   IF !Fatal_Error
;	      Set up Control Break (CALL Hook_Interrupts)
;	      IF !Fatal_Error
;		 CALL Clear_Append_X
;		 CALL CHKDSK_IFS
;		 CALL Reset_Append_X
;	      ENDIF
;	   ENDIF
;	ENDIF
;	Exit program
;*****************************************************************************
Procedure Main_Init				;
	Set_Data_Segment			;Setup addressibility
	call get_psp
;;;;;;;;DOS_Call GetCurrentPSP			;Get PSP segment address
;;;;;;;;mov	PSP_Segment,bx			;Save it for later
	mov	Fatal_Error,No			;Init the error flag
	Dos_Call	Disk_Reset		;Flush all buffers
	call	Init_IO 			;Setup messages and parse
	cmp	Fatal_Error,Yes 		;Error occur?
;	$IF	NE				;Nope, keep going
	JE $$IF1
	   call    Validate_Target_Drive	;Check drive letter
	   cmp	   Fatal_Error,Yes		;Error occur?
;	   $IF	   NE				;Nope, keep going
	   JE $$IF2
;;;;;;;;;;;;;;call    Hook_Interrupts		;Set CNTRL -Break hook
	      call    Clear_Append_X		;
	      call    CHKDSK_IFS		;Chkdsk correct file system
	      call    Reset_Append_X		;
;	   $ENDIF				;
$$IF2:
;	$ENDIF					;
$$IF1:
	mov	al,ExitStatus			;Get Errorlevel
	DOS_Call Exit				;Exit program
	int	20h				;If other exit fails
Main_Init endp					;
;*****************************************************************************
;Routine name: get_psp
;*****************************************************************************
;Description: get info from the psp area
;Called Procedures: get_drive
;Input: none
;Output: psp_segment
;	 command_line_buffer
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
;;;;;;;;DOS_Call GetCurrentPSP		;Get PSP segment address	:AN035;b;an000;bgbgb
;;;;;;;;mov	PSP_Segment,bx		;Save it for later		;AN035;b;an000;bgbgb
; get command line from psp
	mov	cx,PSP_Segment		;point ds to data seg
	mov	ds,cx			;  "   "   "   "    "
	assume	ds:NOTHING,es:dg	;  "   "   "   "    "
; get the drive number of the target from the psp (0=default, a=1, b=2, c=3) ;AN;an000;bgb000;bgb
	mov	bl,ds:[FCB1]	    ;Get target drive from FCB -74	    ;AN0;an000;bgb00;
	Set_Data_Segment	    ;Set DS,ES to Data segment		    ;AN0;an000;bgb00;bgb
	call	get_drive
	ret
get_psp   endp				;
;*****************************************************************************
;Routine name: get_drive
;*****************************************************************************
;Description: get drive letter from reg bl
;Input: bl = drive num (default=0)
;Output: driveletter
;	 user_drive
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
	    JNE $$IF5
; get default drive number
		DOS_Call Get_Default_Drive ;Get default drive num in al    ;AN00;an000;bgb0;
					;a=0, b=1, c=2
;	    $ELSE			;Not default, A=1
	    JMP SHORT $$EN5
$$IF5:
; bl already contains the correct drive number - save it
		dec	bl		;make it zero based
		mov	al,bl
;	    $ENDIF			; 74+40=b4
$$EN5:
	    mov     BadDrvm+1,al		 ; "  "    "  "
	    inc     al
	    mov     byte ptr Buffer.drnum_stroff,al			     ;	;an000;bgb   ;
	    mov     AllDrv,al			 ;
	    mov     VolNam,al			 ;
	    mov     OrphFCB,al			 ;
	    dec     al
	    add     al,"A"		;convert it to letter
	    mov     arg_buf,al	    ;set up prompt msg			    ;AN0;an000;bgb00;bgb
	ret
get_drive endp				;
;*****************************************************************************
;Routine name: Init_Input_Output
;*****************************************************************************
;description: Initialize messages, Parse command line if FAT file system
;Called Procedures: Preload_Messages
;		   Parse_Command_Line
;Input: PSP command line at 81h and length at 80h
;Output: FS_Not_FAT = YES/NO
;Psuedocode
;----------
;	FS_Not_FAT = NO
;	Load messages (CALL Preload_Messages)
;	IF !Fatal_Error
;	   Get file system type (INT 21h AX=440Dh, CX=084Eh GET MEDIA_ID)
;	   IF CY (Old type diskette),OR
;	   IF "FAT_12  ",OR
;	   IF "FAT_16  "
;	      CALL Parse_Command_Line
;	      IF !Fatal_Error
;		 Interpret_Parse
;	      ENDIF
;	   ELSE
;	      Get drive letter only (CALL Parse_Drive_Letter)
;	      FS_Not_FAT = YES
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************
Procedure Init_IO		      ;
	call	Preload_Messages		;Load up message retriever
ifdef	fsexec
	mov	FS_Not_FAT,No
	cmp	Fatal_Error,YES 		;Quit?
;	$IF	NE				;Nope, keep going
	JE $$IF8
	   mov	   al,GENERIC_IOCTL		;Generic IOCtl call
	   push    ds				;
	   mov	   bx,PSP_Segment		;
	   mov	   ds,bx			;
	   assume  ds:nothing			;
	   mov	   bl,ds:FCB1			;Get drive (A=1)
	   pop	   ds				;
	   assume  ds:dg			;
	   xor	   bh,bh			;Set bh=0
	   mov	   ch,RawIO			;Get Media ID call
	   mov	   cl,GET_MEDIA_ID		;
	   lea	   dx,Media_ID_Buffer		;Point at buffer
	   DOS_Call IOCtl			;Do function call
;	   $IF	   C,OR 			;Old style diskette, OR
	   JC $$LL9
	   lea	   si,FAT12_String		;Check for FAT_12 string
	   lea	   di,Media_ID_Buffer.Media_ID_File_System ;
	   mov	   cx,Len_FS_ID_String		;Length of compare
	   repe    cmpsb			;Find it?
;	   $IF	   E,OR 			;Nope, keep going
	   JE $$LL9
	   lea	   si,FAT16_String		;Check for FAT_16 string
	   lea	   di,Media_ID_Buffer.Media_ID_File_System ;
	   mov	   cx,Len_FS_ID_String		;Length of compare
	   repe    cmpsb			;Do compare
;	   $IF	   E				;Find it?
	   JNE $$IF9
$$LL9:
endif
	      call    Parse_Command_Line	;Parse in command line input
ifdef	fsexec
;	   $ELSE				;We got FS other than FAT
	   JMP SHORT $$EN9
$$IF9:
;;;;;;;;;;;;;;call    Parse_Drive_Letter	;Only look for drive letter
	      mov     FS_Not_FAT,Yes		;Indicate exec file system
		mov	cx,8
		lea	si,Media_ID_Buffer.Media_ID_File_System ;get file system
		lea	di,fs_string_buffer ;put it here
		rep	movsb
		lea	di,fs_string_buffer ;point to beginning again
;		$DO	COMPLEX 	;search th string until eol found
		JMP SHORT $$SD11
$$DO11:
		    inc     di		;next char
;		$STRTDO 		;start loop here
$$SD11:
		    cmp     byte ptr [di],' '	 ;end of string ?
;		$ENDDO	E		;end loop when eol found
		JNE $$DO11
		lea	si,fs_string_end ;get end of string - rec.exe
		mov	cx,8		; 8 more chars
		rep	movsb		;move it in
;	   $ENDIF				;
$$EN9:
;	$ENDIF					;
$$IF8:
endif
	ret					;
Init_IO endp			      ;
;*****************************************************************************
;Routine name: Preload_Messages
;*****************************************************************************
;Description: Preload messages using common message retriever routines.
;Called Procedures: SysLoadMsg
;Input: Fatal_Error = NO
;Output: Fatal_Error = YES/NO
;Psuedocode
;----------
;	Preload All messages (Call SysLoadMsg)
;	IF error
;	   Display SysLoadMsg error message
;	   Fatal_Error = YES
;	ENDIF
;	ret
;*****************************************************************************
Procedure Preload_Messages			;
	call	SysLoadMsg			;Preload the messages
;	$IF	C				;Error?
	JNC $$IF16
	   call    SysDispMsg			;Display preload msg
	   mov	   Fatal_Error, YES		;Indicate error exit
;	$ENDIF					;
$$IF16:
	ret					;
Preload_Messages endp				;
;*****************************************************************************
;Routine name: Parse_Command_Line
;*****************************************************************************
;Description: Parse the command line. Check for errors, and display error and
;		 exit program if found. Use parse error messages except in case
;		 of no parameters, which has its own message
;Called Procedures: Message (macro)
;		    SysParse
;		    Interpret_Parse
;Input: Fatal_Error = NO
;	PSP_Segment
;Output: Fatal_Error = YES/NO
;	 Parse output buffers set up
;Psuedocode
;----------
;	SEARCH
;	   Parse command line (CALL SysParse)
;	EXITIF end of parsing command line
;	   Figure out last thing parsed (Call Interpret_Parse)
;	ORELSE
;	   See if parse error
;	ENDLOOP parse error
;	   See what was parsed (Call Interpret_Parse)
;	   Fatal_Error = YES
;	ENDSRCH
;	ret
;*****************************************************************************
Procedure Parse_Command_Line			;
	push	ds				;Save data segment
	Set_Data_Segment			;
	mov	cx,PSP_Segment			;Get segment of PSP
	mov	ds,cx				;  "  "    "  "
	assume	ds:nothing,es:dg		;
	mov	si,Command_Line_Parms		;Point at command line
	lea	di,Command_Line_Buffer		;Where to put a copy of it
	mov	cx,Command_Line_Length		;How long was input?
	rep	movsb				;Copy it
	lea	Di,Command_Line_Buffer		;
public nextdi
nextdi:
	mov	al,0dh				;search for end of line
	cmp	al,ES:[Di]			   ;zero terminate string
;	$IF	NZ
	JZ $$IF18
	    inc    di
	    jmp    nextdi
;	$ELSE
	JMP SHORT $$EN18
$$IF18:
	    mov    byte ptr ES:[di+1],00
;	$ENDIF
$$EN18:
	Set_Data_Segment			;Set DS,ES to Data segment
	xor	cx,cx				;
	xor    dx,dx			       ;Required for SysParse call     ;;an000;bgbAN000;
	lea	si,Command_Line_Buffer		;Pointer to parse line
	lea	di,input_table			;Pointer to control table
;	$SEARCH 				;Loop until all parsed
$$DO21:
	   cmp	   Fatal_Error,Yes		;Interpret something bad?
;	$EXITIF E,OR				;If so, don't parse any more
	JE $$LL22
	   call    SysParse			;Go parse
	   cmp	   ax,End_Of_Parse		;Check for end of parse
;	$EXITIF E				;Is it?
	JNE $$IF21
$$LL22:
						;All done
;	$ORELSE 				;Not end
	JMP SHORT $$SR21
$$IF21:
	   cmp	   ax,0 			;Check for parse error
;	$LEAVE	NE				;Stop if there was one
	JNE $$EN21
	   call    Interpret_Parse		;Go find what we parsed
;	$ENDLOOP				;Parse error, see what it was
	JMP SHORT $$DO21
$$EN21:

	   dec	  si			;point to last byte of invalid parm
public decsi
decsi:	   cmp	   byte ptr [si],' '	;are we pointing to a space?
;	   $IF	   E,OR 		;if so, we dont want to do that
	   JE $$LL26
	   cmp	   byte ptr [si],0dh	;are we pointing to CR?
;	   $IF	   E			;if so, we dont want to do that
	   JNE $$IF26
$$LL26:
	       dec   si 		;find the last byte of parm
	       jmp   decsi
;	   $ENDIF
$$IF26:
	   mov	   byte ptr [si+1],00	  ;zero terminate display string
nextsi:
public nextsi
	   dec	   si			;look at previous char
	   cmp	   byte ptr [si],' '	;find parm separator
	   jnz	   nextsi		;loop until begin of parm found
	   mov	   movsi,si		;mov si into display parms
	   PARSE_MESSAGE			;Display parse error
	   mov	   Fatal_Error,YES		;Indicate death!
;	$ENDSRCH				;
$$SR21:
	pop	ds				;
	ret					;
Parse_Command_Line endp 			;
;*****************************************************************************
;Routine name: Interpret_Parse
;*****************************************************************************
;description: Get any switches entered, and dr
;Called Procedures: Message (macro)
;Input: DS:DrNum (FCB at 5Ch)
;Output: Noisy = ON/OFF
;	 DoFix = ON/OFF
;	 ALLDRV = Target drive, A=1
;	 VOLNAM = Target drive, A=1
;	 ORPHFCB = Target drive, A=1
;	 BADDRVm+1 = Target drive, A=0
;	 Arg_Buf = Target drive letter
;	 Fragment > 1 if filespec entered
;Psuedocode
;----------
;	Noisy = OFF
;	DoFix = OFF
;	IF /V
;	   Noisy = ON
;	ENDIF
;	IF /F
;	   DoFix = ON
;	ENDIF
;	IF file spec entered
;	   Build filename
;	   Fragment = 1
;	ENDIF
;	ret
;*****************************************************************************
Procedure Interpret_Parse			;
	push	ds				;Save segment
	push	si				;Restore SI for parser
	push	cx				;
	push	di				;
	Set_Data_Segment			;
	cmp	byte ptr Buffer.dfType,Type_Drive ;Have drive letter?
;	$IF	E				;Yes, save info
	JNE $$IF29
	   and	   word ptr dfcontrol,filespec	;dont let another drive letter
	   mov	   al,byte ptr Buffer.Drnum_stroff ;Get drive entered	       ;;an000;bgbAN000;
	   mov	   AllDrv,al			;
	   mov	   VolNam,al			;
	   mov	   OrphFCB,al			;
	   dec	   al				;Make it 0 based
	   mov	   BadDrvm+1,al 		; "  "	  "  "
	   add	   al,'A'			;Make it a drive letter
	   mov	   Arg_Buf,al			;Save it
;	$ENDIF					;
$$IF29:
	cmp	SwBuffer.Switch_Pointer,offset Sw_v			 ;AN020;;an000;bgbbgb
;	$IF	E				;
	JNE $$IF31
	   mov	   Noisy,ON			;Set flag
	   mov	   byte ptr sw_v,blank
;	$ENDIF					;
$$IF31:
	cmp	SwBuffer.Switch_Pointer,offset sw_f			 ;AN020;;an000;bgbbgb
;	$IF	E				;
	JNE $$IF33
	   mov	   DoFix,ON			;Set flag
	   mov	   byte ptr sw_f,blank					       ;;an000;bgban020;bgb
;	$ENDIF					;
$$IF33:
;;;;;;; cmp	FileSpec_Buffer.FileSpec_Pointer,offset FileSpec_Control.Keyword
	cmp	buffer.dftype, type_filespec
;	$IF	E				;
	JNE $$IF35
	   mov	   word ptr dfcontrol,0 ;dont let another drive letter or filesp;an000;bgbec
	   mov	   si,Buffer.drnum_StrOff ;
	   lea	   di,Path_Name 		;Point to where to build path
	   cld					;SI-DI dir is up
;	   $DO					;Move string one char at a time
$$DO36:
	      cmp     byte ptr [si],Asciiz_End	;Is it the end?
;	   $LEAVE  E				;You got it
	   JE $$EN36
	      movsb				;Nope, move the character
;	   $ENDDO				;And keep crusin
	   JMP SHORT $$DO36
$$EN36:
	   inc	   fragment			;To be compat with old code
;	$ENDIF					;
$$IF35:
	pop	di				;Restore parse regs
	pop	cx				;
	pop	si				;
	pop	ds				;
	ret					;
Interpret_Parse endp				;
;*****************************************************************************
;Routine name: Validate_Target_Drive
;*****************************************************************************
;Description: Control routine for validating the specified format target drive.
;	      If any of the called routines find an error, they will print
;	      message and terminate program, without returning to this routine
;Called Procedures: Check_Target_Drive
;		    Check_For_Network
;		    Check_Translate_Drive
;Input: Fatal_Error = NO
;Output: Fatal_Error = YES/NO
;Psuedocode
;----------
;	CALL Check_Target_Drive
;	IF !Fatal_Error
;	   CALL Check_For_Network
;	   IF !Fatal_Error
;	      CALL Check_Translate_Drive
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************
Procedure Validate_Target_Drive 		;
    call    Check_For_Network		 ;See if Network drive letter	 ;an000;;an043;bgbbgb
    cmp     Fatal_Error,YES		    ;Can we continue?		    ;an0;an043;bgb00;bgb
;   $IF     NE				    ;Yep			    ;an0;an043;bgb00;bgb
    JE $$IF40
	call	Check_Target_Drive		;See if valid drive letter
	cmp	Fatal_Error,YES 		;Can we continue?
;	$IF	NE				;Yep
	JE $$IF41
	   call    Check_For_Network		;See if Network drive letter
	   cmp	   Fatal_Error,YES		;Can we continue?
;	   $IF	   NE				;Yep
	   JE $$IF42
	      call    Check_Translate_Drive	;See if Subst, Assigned
;	   $ENDIF				;- Fatal_Error passed back
$$IF42:
;	$ENDIF					;
$$IF41:
;   $ENDIF
$$IF40:
	ret					;
Validate_Target_Drive endp			;
;*****************************************************************************
;Routine name: Check_Target_Drive
;*****************************************************************************
;Description: Check to see if valid DOS drive by checking if drive is
;	      removable. If error, the drive is invalid. Save default
;	      drive info. Also get target drive BPB information, and compute
;	      the start of the data area
;Called Procedures: Message (macro)
;Input: Fatal_Error = NO
;Output: BIOSFile = default drive letter
;	 DOSFile = default drive letter
;	 CommandFile = default drive letter
;	 Fatal_Error = YES/NO
;Psuedocode
;----------
;	Get default drive (INT 21h, AH = 19h)
;	Convert it to drive letter
;	Save into BIOSFile,DOSFile,CommandFile
;	See if drive removable (INT 21h, AX=4409h IOCtl)
;	IF error - drive invalid
;	   Display Invalid drive message
;	   Fatal_Error= YES
;	ENDIF
;	Get BPB of target drive (Generic IOCtl Get Device parameters)
;	Compute start of data area
;	ret
;*****************************************************************************
Procedure Check_Target_Drive			;
    call    func60				;
    mov     al,save_drive
    cmp     al,0ffh			;save drive spec
;   $IF     E
    JNE $$IF46
	   Message BadDrv_Arg			;Print message
	   mov	   Fatal_Error,Yes		;Indicate error
	   jmp	   Exit_Baddrv			;dont do rest of proc
;   $ENDIF
$$IF46:
	DOS_Call Get_Default_Drive		;Find the current drive  19
	mov	UserDev,al			;Save it			;an000;bgb;	;
	cmp	AllDrv,0			;Was drive entered?
;	$IF	E				;No
	JNE $$IF48
	   mov	   BadDrvm+1,al 		;Save 0 based number
	   inc	   al				;Make 1 based
	   mov	   byte ptr Buffer.Drnum_stroff,al			    ;	;an000;bgb  ;
	   mov	   AllDrv,al			;Use default drive for
	   mov	   VolNam,al			;entries for drive fields
	   mov	   OrphFCB,al			;
	   add	   al,'A'-1			;Make it a drive letter
	   mov	   Arg_Buf,al			;Save it
;	$ENDIF					;
$$IF48:
	mov	bl,alldrv			;Get drive number (A=1)    ;AN00;an044;bgb;an000;bgb0;
	mov	al,09h				;See if drive is local
	DOS_Call IOCtl				;-this will fail if bad drive
;	$IF	C				;CY means invalid drive
	JNC $$IF50
	   Message BadDrv_Arg			;Print message
	   mov	   Fatal_Error,Yes		;Indicate error
;	$ENDIF					;
$$IF50:
	cmp	fatal_error,no
;	$IF	E
	JNE $$IF52
get_bpb:   mov	   al,GENERIC_IOCTL		   ;Get BPB information
	   mov	   ch,RawIO			   ; "  "   "  "
	   mov	   cl,GET_DEVICE_PARAMETERS	   ;
	   mov	   bl,AllDrv			   ; "  "   "  "
	   lea	   dx,BPB_Buffer		   ; dx points to bpb area
	   mov	   byte ptr bpb_buffer, 0ffh	   ;turn bit 0 on to get bpb inf;an000;bgbo of disk
	   DOS_Call IOCtl			   ; "  "   "  "
	   mov	   bx,dx			   ;use bx as the pointer to bpb
;	   $IF	   C			   ;is ioct not supported or bad?
	   JNC $$IF53
	      mov     al,BadDrvm+1		   ; drive number a=0
	      lea     bx,chkprmt_end		   ; transfer address es:bx
	      ;warning! this label must be the last in the code segment
	      mov     cx,1			   ; 1 sector - boot record
	      mov     dx,0			   ; logical sector 0
	      mov     Read_Write_Relative.Start_Sector_High,0 ;
	      call    read_once
;	      $IF     C 		   ;couldnt read the boot?
	      JNC $$IF54
		  Message BadDrv_Arg		       ;Print message
		  mov	  Fatal_Error,Yes	       ;Indicate error
;	      $ELSE			;ioct not supported - is it vdisk
	      JMP SHORT $$EN54
$$IF54:
;		  mov	di,bx
;		  add	di,3		;es:di --> to vdisk area in boot rcd
;		  lea	si,myvdisk	;ds:si --> proper vdisk string
;		  mov	cx,5		; compare 5 bytes
;		  repe	cmpsb		;compare both strings
IF  IBMCOPYRIGHT
;		  $IF	NE
;		      jmp     baddrv
;		  $ENDIF
ELSE
;		  $IF	NE
			mov   di,bx
			add   di,3
			lea   si,myramdisk
			mov   cx,8
			repe  cmpsb

;			$IF   NE
			JE $$IF56
			jmp   baddrv
;			$ENDIF
$$IF56:
;		  $ENDIF
ENDIF
;	      $ENDIF
$$EN54:
	      add     bx,4		   ;boot-record-offset - device-paramete;an000;bgbr offset
;	   $ENDIF
$$IF53:
;	$ENDIF
$$IF52:
	   cmp	   fatal_error,no
;	   $IF	   E
	   JNE $$IF61
	      call    get_boot_info
	      call    calc_space
;	   $ENDIF
$$IF61:
	      cmp     bytes_per_sector,0
;	      $IF     E
	      JNE $$IF63
baddrv: 	  mov  fatal_error,yes
		  mov	  dx,offset dg:inval_media
		  invoke  printf_crlf
;	      $ENDIF
$$IF63:
Exit_Baddrv:
	     ret				;And we're outa here
Check_Target_Drive endp 			;

;******************************************************************************
; get_boot_info
;	Inputs	: none
;	Outputs :
;******************************************************************************
Procedure get_boot_info        ;
	      mov     cx,[bx].BytePerSector	; usually 512
	      cmp     cx,512 ;vdisk sizes
;	      $IF     NE,AND ;vdisk sizes
	      JE $$IF65
	      cmp     cx,256 ;vdisk sizes
;	      $IF     NE,AND ;vdisk sizes
	      JE $$IF65
	      cmp     cx,128 ;vdisk sizes
;	      $IF     NE     ;vdisk sizes
	      JE $$IF65
		  jmp	 baddrv
;	      $ENDIF
$$IF65:
	      mov     bytes_per_sector,cx     ; 		 ;
	      xor     cx,cx			      ;Find # sectors used by FA;an053;bgb;an000;bgbT's
	      mov     cl,[bx].NumberOfFats	; "  "	 "  "
	      cmp     cx,2		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF67
	      cmp     cx,1		;make sure it is ok
;	      $IF     NE
	      JE $$IF67
		  jmp	  baddrv	    ;must be 2 fats
;	      $ENDIF
$$IF67:
	      mov     fatcnt,cl
	      xor     ax,ax
	      mov     al,[bx].SectorsPerCluster   ;get total sectors
	      cmp     ax,1		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,2		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,4		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,8		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,16		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,32		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,64		;make sure it is ok
;	      $IF     NE,AND
	      JE $$IF69
	      cmp     ax,128		;make sure it is ok
;	      $IF     NE
	      JE $$IF69
		  jmp	  baddrv	    ;this is not!
;	      $ENDIF
$$IF69:
	      mov     ax,[bx].SectorsPerFAT	; "  "	 "  "
	      cmp     ax,0		;make sure it is ok
	      jz      baddrv		;this is not!
	      mul     cx			      ; "  "   "  "
	      push    bx		      ;save bpb pointer
	      push    dx			      ;Save results
	      push    ax			      ;     "  "
	      mov     ax,[bx].RootEntries	;Find number of sectors in root
	      cmp     ax,2		;make sure it is ok
;	      $IF     B,OR		;this is not!
	      JB $$LL71
	      cmp     ax,512		;make sure it is ok
;	      $IF     A 		;this is not!
	      JNA $$IF71
$$LL71:
		jmp	baddrv
;	      $ENDIF
$$IF71:
	      mov     cl,Dir_Entries_Per_Sector       ; by dividing RootEntries
	      cmp     cl,0
;	      $IF     NE
	      JE $$IF73
		  div	  cl				  ; by (512/32)
;	      $ENDIF
$$IF73:
	      pop     bx			      ;Get low sectors per FAT b;an053;bgb;an000;bgback
	      pop     dx			      ;Get high part
	      add     ax,bx			      ;Add to get FAT+Dir sector;an053;bgb;an000;bgbs
	      adc     dx,0			      ;High part
	      mov     fat_dir_secs,ax		      ;save it
	      inc     fat_dir_secs		      ; 1 for reserved sector
	      pop     bx		      ;restore bpb pointer
	      add     ax,[bx].ReservedSectors	;Add in Boot record sectors
	      adc     dx,0			      ;to get start of data (DX:;an053;bgb;an000;bgbAX)
	      mov     Data_Start_Low,ax 	      ;Save it
	      mov     Data_Start_High,dx	      ;
	ret					 ;
get_boot_info endp	       ;







;******************************************************************************
; Calc_Space  : Calculate the total space that is
;				  addressible on the the disk by DOS.
;	Inputs	: none
;	Outputs : Fdsksiz - Size in bytes of the disk
;******************************************************************************
Procedure Calc_Space	       ;
; get the total number of clusters on the disk
p97:	xor	ax,ax				 ;clear ax
	mov	ah,36h				 ;Get disk free space
	mov	dl,alldrv		; 1 based drive number
	push	bx			;save bpb pointer
	int	21h				 ;bx = total space avail
;multiply by sectors per cluster
gtsecs: mov	ax,dx				 ;get total clusters
	xor	cx,cx				 ;clear cx
	pop	bx			;restore bpb pointer
	mov	cl,[bx].SectorsPerCluster   ;get total sectors
	push	bx			;save bpb pointer
	xor	bx,bx				 ;clear bx
	call	Multiply_32_Bits		 ;multiply
;multiply by bytes per sector
	mov	dx,bx			;save bx
	pop	bx			;get bpb addr
	mov	cx,[bx].BytePerSector	;get total bytes
	mov	bx,dx			;restore bx
	call	Multiply_32_Bits		 ; multiply
;result is bytes on disk
	mov	tot_bytes_lo,ax 	     ;save high word
	mov	tot_bytes_hi,bx 	   ;save low word
	ret					 ;
Calc_Space    endp	       ;


;*****************************************************************************
;Routine name: Check_For_Network
;*****************************************************************************
;Description: See if target drive isn't local, or if it is a shared drive. If
;	      so, exit with error message. The IOCtl call is not checked for
;	      an error because it is called previously in another routine, and
;	      invalid drive is the only error it can generate. That condition
;	      would not get this far
;Called Procedures: Message (macro)
;Input:    Drive_Letter_Buffer.Drive_Number
;	   Fatal_Error = NO
;Output: Fatal_Error = YES/NO
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
Procedure Check_For_Network			;
	mov	bl,alldrv			;Drive is 1=A, 2=B		;an000;bgb;	;
	mov	al,09h				;See if drive is local or remote
	DOS_CALL IOCtl				;We will not check for error
	test	dx,Net_Check			;if (x & 1200H)(redir or shared);an000;bgb;	;
;	$IF	NZ				;Found a net drive
	JZ $$IF75
	   Message No_Net_Arg			;Tell 'em
	   mov	   Fatal_Error,Yes		;Indicate bad stuff
;	$ELSE					;Local drive, now check assign
	JMP SHORT $$EN75
$$IF75:
	   test    dx,Assign_Check		;8000h bit is bad news		;an000;bgb;	;
;	   $IF	   NZ				;Found it
	   JZ $$IF77
	      Message SubstErr			;Tell error
	      mov     Fatal_Error,Yes		;Indicate bad stuff
;	   $ENDIF				;
$$IF77:
;	$ENDIF					;
$$EN75:
	ret					;
Check_For_Network endp				;
;*****************************************************************************
;Routine name: Check_Translate_Drive
;*****************************************************************************
;Description: Do a name translate call on the drive letter to see if it is
;	      assigned by SUBST or ASSIGN
;Called Procedures: Message (macro)
;Input: Drive_Letter_Buffer.Drive_Number
;	   Fatal_Error = NO
;Output: Fatal_Error = YES/NO
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
Procedure Check_Translate_Drive 		;
	call	func60				;
	mov	bl,byte ptr [TranSrc]		;Get drive letter from path	;an000;bgb;	;
	cmp	bl,byte ptr [Chkprmt_End]	;Did drive letter change?	;an000;bgb;	;
;	$IF	NE				;If not the same, it be bad
	JE $$IF80
	   Message SubstErr			;Tell user
	   mov	   Fatal_Error,Yes		;Setup error flag
;	$ENDIF					;
$$IF80:
	ret					;
Check_Translate_Drive endp			;
Procedure func60				;
;  PUSH    DS			   ;ICE
;  push    bx			   ;ICE
;  push    ax			   ;ICE
;  mov	   bx,0140H		   ;ICE
;  xor	   ax,ax		   ;ICE
;  mov	   ds,ax		   ;ICE
;  mov	   ax,word ptr ds:[bx]	   ;ICE
;  mov	   word ptr ds:[bx],ax	   ;ICE
;  pop	   ax			   ;ICE
;  pop	   bx			   ;ICE
;  POP	   DS			   ;ICE
	mov	byte ptr [transrc],'A'
	mov	bl,alldrv			;Get drive		    ;	;an000;bgb  ;
	dec	bl				;Make it 0 based
	add	byte ptr [TranSrc],bl		;Make string "d:\"		;an000;bgb;	;
	lea	si,TranSrc			;Point to translate string	;an000;bgb;	;
	push	ds				;Set ES=DS (Data segment)	;an000;bgb;	;
	pop	es				;     "  "	"  "		;an000;bgb;	;
	lea	di,Chkprmt_End			;Point at output buffer 	;an000;bgb;	;
	DOS_Call xNameTrans			;Get real path
	ret					;
func60 endp			 ;
;*****************************************************************************
;Routine name: Hook_Interrupts
;*****************************************************************************
;Description: Change the interrupt handler for INT 13h to point to the
;	      ControlC_Handler routine
;Called Procedures: None
;Input: None
;Output: None
;Psuedocode
;----------
;	Point at ControlC_Handler routine
;	Set interrupt handler (INT 21h, AX=2523h)
;	ret
;*****************************************************************************
procedure Hook_Interrupts			;
	mov	al,23h
	DOS_Call Get_Interrupt_Vector		;Get the INT 23h handler
	mov	word ptr [CONTCH],bx		;
	mov	bx,es				;
	mov	word ptr [CONTCH+2],bx		;
	mov	al,23h				;Specify CNTRL handler		;an000;bgb;	;
	lea	dx, INT_23			;Point at it			;an000;bgb;	;
	push	ds				;Save data seg			;an000;bgb;	;
	push	cs				;Point to code segment		;an000;bgb;	;
	pop	ds				;				;an000;bgb;	;
	DOS_Call Set_Interrupt_Vector		;Set the INT 23h handler
	pop	ds				;Get Data degment back		;an000;bgb;	;
	mov	al,24h				;
	DOS_Call Get_Interrupt_Vector		;Get the INT 24h handler
	mov	word ptr [HardCh],bx		;Save it
	mov	bx,es				;
	mov	word ptr [HardCh+2],bx		;
	mov	al,24h				;Specify handler		;an000;bgb ;	 ;
	lea	dx, INT_24			;Point at it			;an000;bgb;	;
	push	ds				;Save data seg			;an000;bgb;	;
	push	cs				;Point to code segment		;an000;bgb;	;
	pop	ds				;				;an000;bgb;	;
	DOS_Call Set_Interrupt_Vector		;Set the INT 23h handler
	pop	ds				;Get Data degment back		;an000;bgb;	;
	ret					;
hook_Interrupts endp				;
;*****************************************************************************
;Routine name: Clear_Append_X
;*****************************************************************************
;Description: Determine if Append /XA is turned on thru INT 2Fh, and shut
;	      off for life of CHKDSK if it is.
;Called Procedures: None
;Input: None
;Output: APPEND = YES/NO
;Psuedocode
;----------
;	Append = NO
;	See if APPEND /X is present (INT 2Fh, AX=0B706h)
;	IF present
;	   Turn append /X off (INT 2Fh, AX=B707h, BX = 0)
;	   Append = YES
;	ENDIF
;	ret
;*****************************************************************************
Procedure Clear_Append_X			;
	mov	Append,NO			;Init the Append /X flag
	mov	ax,Append_X			;Is Append /X there?
	int	Multiplex			; "  "	   "  "
	cmp	bx,Append_X_Set 		;Was it turned on?
;	$IF	E				;Yep
	JNE $$IF82
	   mov	   Append,YES			;Indicate that it was on
	   mov	   ax,Set_Append_X		;Turn Append /X off
	   mov	   bx,Append_Off		; "  "	  "  "
	   int	   Multiplex			; "  "	  "  "
;	$ENDIF					;
$$IF82:
	ret					;
Clear_Append_X endp				;
;*****************************************************************************
;Routine name: CHKDSK_IFS
;*****************************************************************************
;Description:
;Called Procedures: Main_Routine
;		   EXEC_FS_CHKDSK
;		   Done
;Input: FS_Not_FAT = Yes/No
;Output: None
;Psuedocode
;----------
;	IF File system other than FAT
;	   Go call file system specific CHKDSK (CALL Exec_FS_CHKDSK)
;	ELSE
;	   Do FAT based CHKDSK (CALL Main_Routine)
;	ENDIF
;	Restore current drive (CALL Done)
;	ret
;*****************************************************************************
Procedure CHKDSK_IFS				;
ifdef	fsexec
	cmp	FS_Not_Fat,YES			;Is the target FS a FAT?
;	$IF	E				;No, so need to exec the
	JNE $$IF84
	   call    EXEC_FS_CHKDSK		; file system specific prog.
;	$ELSE					;It's a FAT
	JMP SHORT $$EN84
$$IF84:
endif
	   call    Main_Routine 		;Use canned code!
ifdef	fsexec
;	$ENDIF					;
$$EN84:
endif
	call	Done				;Restore current drive
	ret					;
CHKDSK_IFS endp 				;
;*****************************************************************************
;Routine name: Reset_Append_X
;*****************************************************************************
;description: If APPEND /XA was on originally, turn it back on
;Called Procedures: None
;Input: None
;Output: APPEND = YES/NO
;Psuedocode
;----------
;	IF APPEND = YES
;	   Turn append /X on (INT 2Fh, AX=B707h, BX = 1)
;	ENDIF
;	ret
;*****************************************************************************
Procedure Reset_Append_X			;
	cmp	Append,Yes			;Was Append /X on to start with?
;	$IF	E				;Yep
	JNE $$IF87
	   mov	   ax,Set_Append_X		;Turn Append /X off
	   mov	   bx,Append_On 		; "  "	  "  "
	   int	   Multiplex			; "  "	  "  "
;	$ENDIF					;
$$IF87:
	ret					;
Reset_Append_X endp				;
;*****************************************************************************
;Routine name: Multiply_32_Bits
;*****************************************************************************
;Description: A real sleazy 32 bit x 16 bit multiply routine. Works by adding
;	      the 32 bit number to itself for each power of 2 contained in the
;	      16 bit number. Whenever a bit that is set in the multiplier (CX)
;	      gets shifted to the bit 0 spot, it means that that amount has
;	      been multiplied so far, and it should be added into the total
;	      value. Take the example CX = 12 (1100). Using the associative
;	      rule, this is the same as CX = 8+4 (1000 + 0100). The
;	      multiply is done on this principle - whenever a bit that is set
;	      is shifted down to the bit 0 location, the value in BX:AX is
;	      added to the running total in DI:SI. The multiply is continued
;	      until CX = 0. The routine will exit with CY set if overflow
;	      occurs.
;Called Procedures: None
;Input: BX:AX = 32 bit number to be multiplied
;	CX = 16 bit number to be multiplied. (Must be even number)
;Output: BX:AX = output.
;	 CY set if overflow
;Psuedocode
;----------
;	Point at ControlC_Handler routine
;	Set interrupt handler (INT 21h, AX=2523h)
;	ret
;*****************************************************************************
Public Multiply_32_Bits
Multiply_32_Bits proc				;
	push	di				;
	push	si				;
	xor	di,di				;Init result to zero
	xor	si,si				;
	cmp	cx,0				;Multiply by 0?
;	$IF	NE				;Keep going if not
	JE $$IF89
;	   $DO					;This works by adding the result
$$DO90:
	      test    cx,1			;Need to add in sum of this bit?
;	      $IF     NZ			;Yes
	      JZ $$IF91
		 add	 si,ax			;Add in the total so far for
		 adc	 di,bx			; this bit multiplier (CY oflow)
;	      $ELSE				;Don't split multiplier
	      JMP SHORT $$EN91
$$IF91:
		 clc				;Force non exit
;	      $ENDIF				;
$$EN91:
;	   $LEAVE  C				;Leave on overflow
	   JC $$EN90
	      shr     cx,1			;See if need to multiply value
	      cmp     cx,0			;by 2
;	   $LEAVE  E				;Done if cx shifted down to zero
	   JE $$EN90
	      add     ax,ax			;Each time cx is shifted, add
	      adc     bx,bx			;value to itself (Multiply * 2)
;	   $ENDDO  C				;CY set on overflow
	   JNC $$DO90
$$EN90:
;	   $IF	   NC				;If no overflow, add in DI:SI
	   JC $$IF97
	      mov     ax,si			; which contains the original
	      mov     bx,di			; value if odd, 0 if even. This
	      clc				;Set no overflow flag
;	   $ENDIF				;
$$IF97:
;	$ELSE					;
	JMP SHORT $$EN89
$$IF89:
	   xor	   ax,ax			;
	   xor	   bx,bx			;
;	$ENDIF					;Multiply by 0
$$EN89:
	pop	si				;
	pop	di				;
	ret					;
Multiply_32_Bits endp
	pathlabl chkinit
code	ends
	end
