
;
;*****************************************************************************
;*****************************************************************************
;
;UTILITY NAME: FORMAT.COM
;
;MODULE NAME: FORLABEL.SAL
;
;		Interpret_Parse
;			|
;*			|
;³ÚÄÄÄÄÄ¿ÚÄÄÄÄÄÄÄÄÄÄÄÄÄ¿|ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿ ÚÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;À´VolIDÃ´Get_New_LabelÃÄ´Get_11_CharactersÃÂ´Change_Blanks³
; ÀÄÄÄÄÄÙÀÄÄÄÄÄÄÄÄÄÄÄÄÄÙ ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;					    ³ÚÄÄÄÄÄÄÄÄÄÄÄ¿
;					    Ã´Skip_Blanks³
;					    ³ÀÄÄÄÄÄÄÄÄÄÄÄÙ
;					    ³ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;					    Ã´Check_DBCS_OverrunÃ´Check_DBCS_Character³
;					    ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;					    ³ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;					    À´Copy_FCB_String³
;					     ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;*****************************************************************************
;*****************************************************************************

data	segment public para 'DATA'
data	ends

code	segment public para 'CODE'
	assume	cs:code,ds:data
code	ends

.xlist
INCLUDE FORCHNG.INC
INCLUDE FORMACRO.INC
INCLUDE SYSCALL.INC
INCLUDE FOREQU.INC
INCLUDE FORSWTCH.INC
.list

;
;*****************************************************************************
; Equates
;*****************************************************************************
;

None	equ	0
StdIn	equ	0
StdOut	equ	1
StdErr	equ	2
Tab	equ	09h
Label_Buffer_length equ 80h
Create_Worked equ 0


;
;*****************************************************************************
; External Data Declarations
;*****************************************************************************
;

	Extrn	SwitchMap:Word
	Extrn	Switch_String_Buffer:Byte
	Extrn	VolFCB:Byte
	Extrn	MsgBadCharacters:Byte
	Extrn	MsgLabelPrompt:Byte
	Extrn	MsgBadVolumeID:Byte
	Extrn	MsgCRLF:Byte
	Extrn	VolNam:Byte
	Extrn	Vol_Label_Count:Byte
	Extrn	VolDrive:Byte
	Extrn	Drive:Byte
	Extrn	Command_Line:Byte
	Extrn	Vol_Label_Buffer:Byte
	Extrn	DelDrive:Byte
	Extrn	DelFCB:Byte

code	segment public para 'CODE'

;************************************************************************************************
;Routine name Volid
;************************************************************************************************
;
;Description: Get volume id from command line /V:xxxxxxx if it is there, or
;	      else prompt user for volume label, parse the input. At this
;	      point setup the FCB and create the volume label. If failure,
;	      prompt user that they entered bad input, and try again.
;
;	      Note: This routine in 3.30 and prior used to check for /V
;		    switch. Volume labels are always required now, so /V
;		    is ignored, except to get volume label on command line.
;
;Called Procedures: Message (macro)
;		    Get_New_Label
;
;Input: Switch_V
;	Command_Line = YES/NO
;
;Output: None
;
;Psuedocode
;----------
;
;	Save registers
;	IF /V switch entered
;	   IF /v:xxxxx form not entered
;	      CALL Get_New_Label     ;Return string in Volume_Label
;	   ENDIF
;	ELSE
;	   CALL Get_New_Label	  ;Return string in Volume_Label
;	ENDIF
;	DO
;	   Create volume label
;	LEAVE Create Ok
;	   Display Bad Character message
;	   CALL Get_New_Label	;Return string in Volume_Label
;	ENDDO
;	Restore registers
;	ret
;*****************************************************************************

Procedure Volid 				;

	push	ds				;Save registers
	push	si				; "  "	  "  "
	test	SwitchMap,Switch_V		;Was /V entered
;	$IF	NZ				;Yes, see if label entered also
	JZ $$IF1
	   cmp	   Command_Line,YES		;Is there a string there?
;	   $IF	   NE				;Nope
	   JE $$IF2
	      call    Get_New_Label		;Go get volume label from user
;	   $ENDIF				;
$$IF2:
;	$ELSE					;Label not entered on cmd line
	JMP SHORT $$EN1
$$IF1:
	   call    Get_New_Label		;Go get label from user
;	$ENDIF					;
$$EN1:
	mov	dl,drive			;Get drive number  A=0
	inc	dl				;Make it 1 based
	mov	DelDrive,dl			;Put into FCBs
	mov	VolDrive,dl			;
	mov	dx,offset DelFCB		;Point at FCB to delete label
	DOS_Call FCB_Delete			;Do the delete
	mov	dx,offset VolFCB		;Point at FCB for create
	DOS_CALL FCB_Create			;Go create it
	cmp	dl,Create_Worked		;See if the create worked
;	$IF	E
	JNE $$IF6
	   mov	   dx,offset VolFCB		;Point to the FCB created
	   DOS_Call FCB_Close			;Close the newly created FCB
;	$ENDIF
$$IF6:

	pop	si				;Restore registers
	pop	ds				; "  "	   "  "
	ret					;

Volid	endp					;

;*****************************************************************************
;Routine name: Get_New_Label
;*****************************************************************************
;
;Description: Prompts, inputs and verifies a volume label string. Continues
;	      to prompt until valid vol label is input
;
;Called Procedures: Message (macro)
;		    Build_String
;		    Get_11_Characters
;
;Input: None
;
;Output: Volume_Label holds
;
;Psuedocode
;----------
;
;	DO
;	   Display  new volume label prompt
;	   Input vol label
;	   IF No error (NC)
;	      Build Asciiz string with label, pointer DS:SI (CALL Build_String)
;	      Call Get_11_Characters (Error returned CY)
;	   ENDIF
;	LEAVE no error (NC)
;	   Display label error
;	ENDDO
;	ret
;*****************************************************************************

Procedure Get_New_Label 			;

;	$DO					;Loop until we get good one
$$DO8:
	   Message msgLabelPrompt		;Prompt to input Vol label
	   mov	ax,(Std_Con_Input_Flush shl 8) + 0 ;an000; dms;clean out input
	   int	21h
	   mov	dx,offset Vol_Label_Count	;an000; dms;beginning of buffer
	   mov	ah,Std_Con_String_Input 	;an000; dms;get input
	   int	21h
	   mov	ax,(Std_Con_Input_Flush shl 8) + 0 ;an000; dms; clean out input
	   int	21h
;	   $IF	   NC				;Read ok if NC, Bad sets CY
	   JC $$IF9
	      mov     si,offset Vol_Label_Buffer ;Get pointer to string
	      call    Get_11_Characters 	;Handle DBCS stuff on input
;	   $ENDIF				;Ret CY if error
$$IF9:
;	$LEAVE	NC				;Done if NC
	JNC $$EN8
	   Message MsgCRLF			;next line
	   Message msgBadVolumeID		;Tell user error
;	$ENDDO					;Try again
	JMP SHORT $$DO8
$$EN8:
	Message MsgCRLF 			;an000; dms;next line
	ret					;

Get_New_Label endp				;

;*****************************************************************************
;Routine name: Get_11_Characters
;*****************************************************************************
;
;Description: Handle DBCS considerations, and build FCB to create vol label
;
;
;Called Procedures: Change_Blanks
;		    Skip_Blanks
;		    Check_DBCS_Overrun
;		    Copy_FCB_String
;
;Input: DS:SI = Asciiz string containing volume label input
;	Command_Line = YES/NO
;
;Output: Volname will contain an 8.3 volume label in FCB
;	 CY set on invalid label
;
;Psuedocode
;----------
;	Save regs used
;	Scan line replacing all DBCS blanks with SBCS  (CALL_Change_Blanks)
;	Skip over leading blanks (Call Skip_Blanks)
;	IF leading blanks ,AND
;	IF Command line
;	   Indicate invalid label (STC)
;	ELSE
;	   See if DBCS character at 11th byte (CALL Check_DBCS_Overrun)
;	   IF DBCS character at 11th byte
;	      Indicate invalid label (STC)
;	   ELSE
;	   Put string into FCB (CALL Copy_FCB_STRING)
;	   CLC
;	   ENDIF
;	ENDIF
;	Restore regs
;	ret
;*****************************************************************************

Procedure Get_11_Characters			;

	call	Change_Blanks			;Change DBCS blanks to SBCS
	call	Skip_Blanks			;Skip over leading blanks
;	$IF	C,AND				;Find leading blanks?
	JNC $$IF13
	cmp	Command_Line,YES		;Is this command line input?
;	$IF	E				;Yes
	JNE $$IF13
	   stc					;Indicate error (CY set)
;	$ELSE					;Leading blanks ok
	JMP SHORT $$EN13
$$IF13:
	   call    Check_DBCS_Overrun		;Is DBCS char at 11th byte?
;	   $IF	   C				;Yes
	   JNC $$IF15
	      stc				;Indicate invalid label
;	   $ELSE				;No, good characters
	   JMP SHORT $$EN15
$$IF15:
	      call    Copy_FCB_String		;Put string into FCB
	      clc				;Indicate everything A-OK!
;	   $ENDIF				;
$$EN15:
;	$ENDIF					;
$$EN13:
	ret					;

Get_11_Characters endp				;

;*****************************************************************************
;Routine name: Change_Blanks
;*****************************************************************************
;
;Description: Replace all DBCS blanks with SBCS blanks, end string with
;	      Asciiz character if one doesn't already exist
;
;Called Procedures: Check_DBCS_Character
;
;
;Input: DS:SI = String containing volume label input
;
;Output: DS:SI = ASCIIZ string with all DBCS blanks replaced with 2 SBCS blanks
;
;
;Psuedocode
;----------
;
;	Save pointer to string
;	DO
;	LEAVE End of string (0)
;	   See if DBCS character (Check_DBCS_Character)
;	   IF CY (DBCS char found)
;	      IF first byte DBCS blank, AND
;	      IF second byte DBCS blank
;		 Convert to SBCS blanks
;	      ENDIF
;	      Point to next byte to compensate for DBCS character
;	   ENDIF
;	ENDDO
;	Tack on ASCIIZ character to string
;	Restore pointer to string
;
;*****************************************************************************

Procedure Change_Blanks 			;

	push	si				;Save pointer to string
	push	cx				;
	push	ax				;
	xor	cx,cx				;
;	$DO					;Do while not CR
$$DO19:
	   cmp	   byte ptr [si],Asciiz_End	;Is it end of string?
;	$LEAVE	E,OR				;All done if so
	JE $$EN19
	   cmp	   byte ptr [si],CR		;Is it CR?
;	$LEAVE	E,OR				;Exit if yes,end of label
	JE $$EN19
	   inc	   cx				;Count the character
	   cmp	   cx,Label_Buffer_Length	;Reached max chars? (80h)
;	$LEAVE	E				;Exit if so
	JE $$EN19
	   mov	   al,byte ptr [si]		;Get char to test for DBCS
	   call    Check_DBCS_Character 	;Test for dbcs lead byte
;	   $IF	   C				;We have a lead byte
	   JNC $$IF21
	      cmp     byte ptr [si],DBCS	;Is it a lead blank?
;	      $IF     E,AND			;If a dbcs char
	      JNE $$IF22
	      cmp     byte ptr [si+1],DBCS_Blank ;Is it an Asian blank?
;	      $IF     E 			;If an Asian blank
	      JNE $$IF22
		 mov	 byte ptr [si+1],Blank	;set up moves
		 mov	 byte ptr [si],Blank	;  to replace
;	      $ENDIF				;
$$IF22:
	      inc     si			;Point to dbcs char
;	   $ENDIF				;End lead byte test
$$IF21:
	   inc	   si				;Point to si+1
;	$ENDDO					;End do while
	JMP SHORT $$DO19
$$EN19:
	mov	byte ptr [si],Asciiz_End	;Mark end of string
	pop	ax				;Restore regs
	pop	cx				;
	pop	si				;
	ret					;return to caller

Change_Blanks endp				;

;*****************************************************************************
;Routine name: Skip_Blanks
;*****************************************************************************
;
;Description: Scan ASCIIZ string for leading blanks, return pointer to first
;	      non-blank character. Set CY if blanks found
;
;Called Procedures: None
;
;
;Input: DS:SI = ASCIIZ string containing volume label input
;
;Output: DS:SI = Input string starting at first non-blank character
;	 CY set if blanks found
;
;
;
;Psuedocode
;----------
;
;	Save original pointer, DI register
;	DO
;	  Look at character from string
;	LEAVE End of string (0)
;	  IF character is blank,OR
;	  IF character is tab
;	     INC pointer (SI)
;	     Indicate blank
;	  ELSE
;	     Indicate non-blank
;	  ENDIF
;	ENDDO non-blank
;	Get back pointer
;	Cmp string pointer to original pointer
;	IF NE
;	   STC
;	ELSE
;	   CLC
;	ENDIF
;	ret
;*****************************************************************************

Procedure Skip_Blanks				;

	push	di				;Preserve DI, just in case
	push	si				;Save pointer to string
;	$DO					;Look at entire ASCIIZ string
$$DO26:
	   cmp	   byte ptr [si],ASCIIZ_End	;End of string?
;	$LEAVE	E				;Yep, exit loop
	JE $$EN26
	   cmp	   byte ptr [si],Blank		;Find a blank?
;	   $IF	   E,OR 			;Yes
	   JE $$LL28
	   cmp	   byte ptr [si],TAB		;Is it tab?
;	   $IF	   E				;Yes
	   JNE $$IF28
$$LL28:
	      inc     si			;Bump pointer to next character
	      clc				;Indicate found blank
;	   $ELSE				;Not blank or tab
	   JMP SHORT $$EN28
$$IF28:
	      stc				;Force exit
;	   $ENDIF				;
$$EN28:
;	$ENDDO	C				;Go look at next character
	JNC $$DO26
$$EN26:
	pop	di				;Get back original pointer
	cmp	di,si				;Are they the same?
;	$IF	NE				;If not equal blanks were found
	JE $$IF32
	   stc					;Set CY
;	$ELSE					;No leading blanks found
	JMP SHORT $$EN32
$$IF32:
	   clc					;Clear CY
;	$ENDIF					;
$$EN32:
	pop	di				;Restore DI
	ret					;

Skip_Blanks endp				;


;*****************************************************************************
;Routine name: Copy_FCB_String
;*****************************************************************************
;
;Description: Build an 11 character string in the FCB from ASCIIZ string
;	      If nothing entered, than terminated with 0. Also add drive
;	      number in FCB
;
;Called Procedures: None
;
;
;Input: DS:SI = String containing volume label input
;
;Output: VOLNAM is filled in with Volume label string
;
;
;
;Psuedocode
;----------
;
;	Save regs
;	Init VolNam to blanks
;	DO
;	LEAVE if character is end of ASCIIZ string
;	   Mov character to FCB
;	   Inc counter
;	ENDDO all 11 chars done
;	Restore regs
;*****************************************************************************

Procedure Copy_FCB_String			;

	push	di				;
	push	cx				;
	push	si				;Save pointer to string
	cld					;Set string direction to up
	mov	di,offset Volnam		;Init FCB field to blanks
	mov	al,Blank			; "  "	  "  "
	mov	cx,Label_Length 		; "  "	  "  "
	rep	stosb				; "  "	  "  "
	pop	si				;Get back pointer to string
	mov	di,offset VolNam		;Point at FCB field
	xor	cx,cx				;Init counter
;	$DO					;Copy characters over
$$DO35:
	   cmp	   byte ptr [si],ASCIIZ_End	;End of String?
;	$LEAVE	E				;Yes, don't copy - leave blanks
	JE $$EN35
	   movsb				;Nope, copy character
	   inc	   cx				;Bump up count
	   cmp	   cx,Label_Length		;Have we moved 11?
;	$ENDDO	E				;Quit if so
	JNE $$DO35
$$EN35:
	pop	cx				;
	pop	di				;
	ret					;

Copy_FCB_String endp				;


;*****************************************************************************
;Routine name: Check_DBCS_Overrun
;*****************************************************************************
;
;Description: Check 11th byte, if the string is that long, to see
;	      if it is a DBCS character that is split down the middle. Must
;	      scan entire string to properly find DBCS characters, due to
;	      the fact a second byte of a DBCS character can fall into
;	      the range of the first byte environment vector, and thus look
;	      like a DBCS char when it really isn't
;
;Called Procedures: Check_DBCS_Character
;
;
;Input: DS:SI = String containing volume label input
;
;Output: CY set if DBCS character at bytes 11-12 in string
;
;*****************************************************************************

Procedure Check_DBCS_Overrun			;

	push	si				;Save pointer
	push	ax				;Save registers
	push	cx				;  "  "   "  "
	mov	cx,si				;Get start of string
	add	cx,Label_Length 		;Find where to check for overrun

Check_DBCS_OverRun_Cont:			;Scan string for DBCS chars

	   cmp	   byte ptr [si],ASCIIZ_End	;End of string?
	   je	   DBCS_Good_Exit		;Yep

	   mov	   al,[si]			;Get character for routine
	   call    Check_DBCS_Character 	;See if DBCS leading character
;	   $if	   c				;DBCS if CY set
	   JNC $$IF38
		   inc	si			;Next byte to handle DBCS
		   cmp	si,cx			;Is DBCS char spanning 11-12?
;		   $if	e			;truncate string
		   JNE $$IF39
			mov  byte ptr [si-1],20h;blank it out
			mov  byte ptr [si],20h	;blank it out
			jmp  DBCS_Good_Exit	;exit
;		   $endif			;
$$IF39:
;	   $else				;Not DBCS character
	   JMP SHORT $$EN38
$$IF38:
		   mov	al,[si] 		;Get character for routine
		   call Scan_For_Invalid_Char	;See if invalid vol ID char
		   jc	DBCS_Bad_Exit		;Bad char entered - exit
;	   $endif				;
$$EN38:

	   inc	   si				;Point to next character
	   jmp	   Check_DBCS_OverRun_Cont	;Continue looping

DBCS_Good_Exit:
	clc					;Signal no error
	jmp	DBCS_Exit			;Exit routine

DBCS_Bad_Exit:

	stc					;Signal error

DBCS_Exit:

	pop	cx				;Restore registers
	pop	ax				; "  "	  "  "
	pop	si				;Restore string pointer
	ret					;

Check_DBCS_Overrun endp 			;

;*****************************************************************************
;Routine name: Check_DBCS_Character
;*****************************************************************************
;
;Description: Check if specified byte is in ranges of DBCS vectors
;
;Called Procedures: None
;
;
;Input: AL = Character to check for DBCS lead character
;	DBCS_Vector = YES/NO
;
;Output: CY set if DBCS character
;	 DBCS_VECTOR = YES
;
;
;Psuedocode
;----------
;	Save registers
;	IF DBCS vector not found
;	   Get DBCS environmental vector (INT 21h
;	   Point at first set of vectors
;	ENDIF
;	SEARCH
;	LEAVE End of DBCS vectors
;	EXITIF Character > X1,AND  (X1,Y1) are environment vectors
;	EXITIF Character < Y1
;	  STC (DBCS character)
;	ORELSE
;	   Inc pointer to next set of vectors
;	ENDLOOP
;	   CLC (Not DBCS character)
;	ENDSRCH
;	Restore registers
;	ret
;*****************************************************************************

Procedure Check_DBCS_Character			;

	push	ds				;Save registers
	push	si				; "  "	  "  "
	push	ax				; "  "	  "  "
	push	ds				; "  "	  "  "
	pop	es				;Establish addressability
	cmp	byte ptr es:DBCS_VECTOR,Yes	;Have we set this yet?
	push	ax				;Save input character
;	$IF	NE				;Nope
	JE $$IF43
	   mov	   al,0 			;Get DBCS environment vectors
	   DOS_Call Hongeul			;  "  "    "  "
	   mov	   byte ptr es:DBCS_VECTOR,YES	;Indicate we've got vector
	   mov	   es:DBCS_Vector_Off,si	;Save the vector
	   mov	   ax,ds			;
	   mov	   es:DBCS_Vector_Seg,ax	;
;	$ENDIF					; for next time in
$$IF43:
	pop	ax				;Restore input character
	mov	si,es:DBCS_Vector_Seg		;Get saved vector pointer
	mov	ds,si				;
	mov	si,es:DBCS_Vector_Off		;
;	$SEARCH 				;Check all the vectors
$$DO45:
	   cmp	   word ptr ds:[si],End_Of_Vector ;End of vector table?
;	$LEAVE	E				;Yes, done
	JE $$EN45
	   cmp	   al,ds:[si]			;See if char is in vector
;	$EXITIF AE,AND				;If >= to lower, and
	JNAE $$IF45
	   cmp	   al,ds:[si+1] 		; =< than higher range
;	$EXITIF BE				; then DBCS character
	JNBE $$IF45
	   stc					;Set CY to indicate DBCS
;	$ORELSE 				;Not in range, check next
	JMP SHORT $$SR45
$$IF45:
	   add	   si,DBCS_Vector_Size		;Get next DBCS vector
;	$ENDLOOP				;We didn't find DBCS char
	JMP SHORT $$DO45
$$EN45:
	   clc					;Clear CY for exit
;	$ENDSRCH				;
$$SR45:
	pop	ax				;Restore registers
	pop	si				; "  "	  "  "
	pop	ds				;Restore data segment
	ret					;

Check_DBCS_Character endp			;

;=========================================================================
; Scan_For_Invalid_Char : This routine scans the bad character table
;			  to determine if the referenced character is
;			  invalid.
;
;	Inputs	: Bad_Char_Table	- Table of bad characters
;		  Bad_Char_Table_Len	- Length of table
;		  AL			- Character to be searched for
;
;	Outputs : CY			- Bad character
;		  NC			- Character good
;=========================================================================

Procedure Scan_For_Invalid_Char

	push	ax								;an000; dms;save ax
	push	cx								;an000; dms;save cx
	push	di								;an000; dms;save di

	lea	di,Bad_Char_Table						;an000; dms;point to bad character table
	mov	cx,Bad_Char_Table_Len						;an000; dms;get its length
	repnz	scasb								;an000; dms;scan the table
	cmp	cx,0000h							;an000; dms;did we find the character
;	$if	e								;an000; dms;no - a good character
	JNE $$IF51
		clc								;an000; dms;flag a good character
;	$else									;an000; dms;yes - a bad character
	JMP SHORT $$EN51
$$IF51:
		stc								;an000; dms;flag a bad character
;	$endif
$$EN51:

	pop	di								;an000; dms;restore di
	pop	cx								;an000; dms;restore cx
	pop	ax								;an000; dms;restore ax

	ret

Scan_For_Invalid_Char	endp


code	ends

data	segment public	para 'DATA'

Bad_Char_Table	label	byte			;an000; dms;table of invalid vol ID chars
	db	"*"
	db	"?"
	db	"["
	db	"]"
	db	":"
	db	"<"
	db	"|"
	db	">"
	db	"+"
	db	"="
	db	";"
	db	","
	db	"/"
	db	"\"
	db	'.'
	db	'"'
	db	" "
Bad_Char_Table_Len	equ	$-Bad_Char_Table;an000; dms;length of table

DBCS_Vector_Off dw 0				;
DBCS_Vector_Seg dw 0				;

data	ends
	end
