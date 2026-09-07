	PAGE
;  $SALUT (4,4,8,41)
;(deleted).XLIST
;(deleted)INCLUDE   STRUC.INC ;AN020;structured macro definitions for .IF,.ELSE etc.
;(deleted).LIST
;
; NOTE:   basesw must be set properly to allow the PARSER to access psdata.
;	   - basesw undefined	 means	 CS seg. override for psdata access.
;	   - basesw = 1 	 means	 DS seg. override for psdata access &
;					 DS must point to psdata.
;	   - basesw = 0 	 means	 ES seg. override for psdata access &
;					 ES must point to psdata.
;
;
IFNDEF basesw
   psdata_seg EQU   CS
ELSE
   IF  basesw				;AN022;IF "basesw  EQU  1" specified by caller THEN
       psdata_seg EQU	DS
   ELSE
       psdata_seg EQU	ES		;AN022;ELSE only other choice is ES (basesw EQU 0)
   ENDIF
ENDIF

ifndef incsw				;AN000; (tm03) Someone doesn't want to include psdata
   incsw equ	 1			;AN000; include psdata.inc (tm03)
endif					;AN000; (tm03)
if incsw				;AN000; If incsw = 1 then (tm03)
   include psdata.inc			;AN000;    include psdata.inc (tm03)
endif					;AN000; endif		  (tm03)
   PAGE
IF1
   %OUT INCLUDING COMP=COMMON DSN=PARSE.ASM...
ENDIF
;***********************************************************************
; SysParse;
;
;  Function : Parser Entry
;
;  Input: DS:SI -> command line
;	  ES:DI -> parameter block
;	  psdata_seg -> psdata.inc
;	  CX = operand ordinal
;
;	  Note:  ES is the segment containing all the control blocks defined
;		 by the caller, except for the DOS COMMAND line parms, which
;		 is in DS.
;
;  Output: CY = 1   error of caller, means invalid parameter block or
;		    invalid value list. But this parser does NOT implement
;		    this feature. Therefore CY always zero.
;
;	   CY = 0   AX = return code
;		    BL = terminated delimiter code
;		    CX = new operand ordinal
;		    SI = set past scaned operand
;		    DX = selected result buffer
;
; Use:	$P_Skip_Delim, $P_Chk_EOL, $P_Chk_Delim, $P_Chk_DBCS
;	$P_Chk_Swtch, $P_Chk_Pos_Control, $P_Chk_Key_Control
;	$P_Chk_Sw_Control, $P_Fill_Result
;
; Vars: $P_Ordinal(RW), $P_RC(RW), $P_SI_Save(RW), $P_DX(R), $P_Terminator(R)
;	$P_SaveSI_Cmpx(W), $P_Flags(RW), $P_Found_SYNONYM(R), $P_Save_EOB(W)
;
; Parser-local data uses PSDATA_SEG; DS may point to the caller's PSP.
; Quoted strings use double quotes only. Some older procedure descriptions
; still mention single quotes.

IF FarSW				;AN000;(Check if need far return)
SysParse proc far
ELSE
SysParse proc near
ENDIF					;AN000;(of FarSW)
;	$SALUT	(4,9,17,41)
	mov	psdata_seg:$P_Flags,0	;AC034; Clear all internal flags
IF	TimeSw				;AN039; FOR TIME ONLY
	MOV    PSDATA_SEG:$P_ORIG_ORD,CX ;AN039; ORIGINAL ORDINAL FROM CX
	MOV    PSDATA_SEG:$P_ORIG_STACK,SP ;AN039; ORIGINAL VALUE OF STACK FROM SP
	MOV    PSDATA_SEG:$P_ORIG_SI,SI ;AN039; ORIGINAL START PARSE POINTER FROM SI
$P_REDO_TIME:				;AN039; try to parse time again
ENDIF					;AN039; FOR TIME ONLY
	cld				      ;AN000; confirm forward direction
	mov	psdata_seg:$P_ordinal,cx      ;AC034; save operand ordinal
	mov	psdata_seg:$P_RC,$P_No_Error  ;AC034; Assume no error
	mov	psdata_seg:$P_Found_SYNONYM,0 ;AC034; initalize synonym pointer

	mov	word ptr psdata_seg:$P_DX,0   ;AC034; (tm15)
IF KeySW
;IN CASE THE USER PUT OPTIONAL WHITESPACE CHARS AROUND THE "=" USED IN
;KEYWORD DEFINITIONS, SCAN THE COMMAND LINE AND COMPRESS OUT ANY WHITESPACES
;NEXT TO "=" BEFORE STARTING THE USUAL PARSING.
       push	 cx
       push	 dx
       push	 di

       push	 si			;AN029; remember where command line starts
       mov	 cx,-1			;AN029; init counter
;      $do
$P_loc_eol:
	  inc	    cx			;AN029; bump counter of chars up to EOL
	  lodsb 			;AN029; get a char from command line
	  CALL	    $P_Chk_EOL		;AN029; see if AL is EOL char

;      enddo z
       jnz	 $P_loc_EOL		;AN029; not found that EOL char

       mov	 psdata_seg:$P_count_to_EOL,cx ;AN029;AC034;; save count of chars up to EOL
       pop	 si			;AN029; restore start of command line

;scan command string for combinations including "=",
;      and replace each with just the simple "="

;REPEAT UNTIL ONE PASS IS MADE WHEREIN NO CHANGES WERE MADE
;  $do
$P_DO1:
       push si			   ;AN029; remember where string started
       MOV  CX,psdata_seg:$P_COUNT_TO_EOL ;AN029;AC034;; set  count to no. chars in string,
				   ;AN029; not counting the EOL char
       XOR  BX,BX		   ;AN029;SET $P_REG_BL_DQ_SW TO "NOT IN QUOTES", AND...
				   ;AN029;SET $P_REG_BH_CG_SW TO "NO CHANGES MADE"
;MAKE ONE PASS THRU THE STRING, LOOKING AT EACH CHARACTER
;      $do
$P_DO2:
	   cmp	BYTE PTR [SI],$P_double_quote
;	   $if	e		   ;AN029;if a double quote was found
	   JNE $P_IF3
	       NOT  $P_REG_BL_DQ_SW ;AN029;TOGGLE THE DOUBLE QUOTE STATE SWITCH
;	   $endif
$P_IF3:
	   OR	$P_REG_BL_DQ_SW,$P_REG_BL_DQ_SW ;AN029;IS THE DOUBLE QUOTE SWITCH SET?
;	   $if	Z		   ;AN029;IF NOT IN DOUBLE QUOTES
	   JNZ $P_IF5
	       mov  ax,word ptr [si] ;AN029; get pair to be checked out
	       cmp  ax,$P_BL_EQ    ;AN029;" ="
;	       $if  e,or
	       JE $P_LL6
	       cmp  ax,$P_EQ_BL    ;AN029;"= "
;	       $if  e,or
	       JE $P_LL6
	       cmp  ax,$P_EQ_TB    ;AN029; "=<tab>"
;	       $if  e,or
	       JE $P_LL6
	       cmp  ax,$P_TB_EQ    ;AN029;"<tab>="
;	       $if  e		   ;AN029;if this pair to be replaced with a single "="
	       JNE $P_IF6
$P_LL6:
		   mov	BYTE PTR [SI],$P_Keyword ;AN029; "="
		   inc	si	   ;AN029;point to next char after the new "="
		   mov	di,si	   ;AN029;move target right after new "="

		   push si	   ;AN029;remember where i am, right after new "="
		   PUSH CX	   ;AN029;SAVE CURRENT COUNT
		   inc	si	   ;AN029;source is one beyond that
		   push es	   ;AN029;remember the extra segment
		   push ds	   ;AN029;temporarily, set source seg and
		   pop	es	   ;AN029; target seg to the command line seg
		   rep	movsb	   ;AN029;move chars left one position
		   pop	es	   ;AN029;restore the extra segment
		   POP	CX	   ;AN029;RESTORE CURRENT COUNT
		   pop	si	   ;AN029;back to where I was

		   DEC	SI	   ;AN029;LOOK AT FIRST CHAR JUST MOVED
		   MOV	$P_REG_BH_CG_SW,-1 ;AN029;set switch to say "a change was made"
		   DEC	psdata_seg:$P_COUNT_TO_EOL ;AN029;AC034;;because just threw away a char
		   dec	CX	   ;AN029;DITTO
;	       $endif		   ;AN029;comparand pair found?
$P_IF6:
;	   $endif		   ;AN029;double quote switch?
$P_IF5:
	   inc	si		   ;AN029;bump index to look at next char in command string
	   dec	CX		   ;AN029;one less char to look at
;(deleted ;AC035;)  CMP  CX,0		    ;AN029;is char count all gone yet?
;      $enddo LE		   ;AN029;quit if no more chars
       JNLE $P_DO2
       pop  si			   ;AN029;remember where string started
       OR   $P_REG_BH_CG_SW,$P_REG_BH_CG_SW ;AN029;WAS "A CHANGE MADE"?
;  $enddo Z			   ;AN029;QUIT when no changes were made
   JNZ $P_DO1
   pop	di
   pop	dx
   pop	cx

;NOW THAT ALL WHITESPACE SURROUNDING "=" HAVE BEEN COMPRESSED OUT,
;RESUME NORMAL PARSING...
ENDIF					;AN029; KEYWORDS SUPPORTED?
	call	$P_Skip_Delim		;AN000; Move si to 1st non white space
	jnc	$P_Start		;AN000; If EOL is not encountered, do parse

;--------------------------- End of Line
	mov	ax,$P_RC_EOL		;AN000; set exit code to -1
	push	bx
	mov	bx,es:[di].$P_PARMSX_Address ;AN000; Get the PARMSX address to
	cmp	cl,es:[bx].$P_MinP	;AN000; check ORDINAL to see if the minimum
	jae	$P_Fin			;AN000; positional found.

	mov	ax,$P_Op_Missing	;AN000; If no, set exit code to missing operand
$P_Fin:
	pop	bx
	jmp	$P_Single_Exit		;AN000; return to the caller

;---------------------------
$P_Start:
	mov	psdata_seg:$P_SaveSI_Cmpx,si ;AN000;AC034;  save ptr to command line for later use by complex,
	push	bx			;AN000; quoted string or file spec.
	push	di
	push	bp
	lea	bx,psdata_seg:$P_STRING_BUF ;AC034; set buffer to copy from command string
	test	psdata_seg:$P_Flags2,$P_Extra ;AC034; 3/9 extra delimiter encountered ?
	jne	$P_Pack_End		;AN000; 3/9 if yes, no need to copy

$P_Pack_Loop:
	lodsb				;AN000; Pick a operand from buffer
	call	$P_Chk_Switch		;AN000; Check switch character
	jc	$P_Pack_End_BY_EOL	;AN020; if carry set found delimiter type slash, need backup si, else continue

	call	$P_Chk_EOL		;AN000; Check EOL character
	je	$P_Pack_End_BY_EOL	;AN000; need backup si

	call	$P_Chk_Delim		;AN000; Check delimiter
	jne	$P_PL01 		;AN000; If no, process next byte

	test	psdata_seg:$P_Flags2,$P_Extra ;AC034; 3/9 If yes and white spec,
; (tm08)jne	$P_Pack_End		;AN000; 3/9 then
	jne	$P_Pack_End_backup_si	;AN000; (tm08)

	call	$P_Skip_Delim		;AN000; skip subsequent white space,too
	jmp	short $P_Pack_End	;AN000; finish copy by placing NUL at end

$P_PAck_End_backup_si:			;AN000; (tm08)
	test	psdata_seg:$P_Flags2,$P_SW+$P_equ ;AN000;AC034;  (tm08)
	je	$P_Pack_End		;AN000; (tm08)

	dec	si			;AN000; (tm08)
	jmp	short $P_Pack_End	;AN025; (tm08)

$P_PL01:
	mov	psdata_seg:[bx],al	;AN000; move byte to STRING_BUF
	cmp	al,$P_Keyword		;AN000; if it is equal character,
	jne	$P_PL00 		;AN000; then

	or	psdata_seg:$P_Flags2,$P_equ ;AC034; remember it in flag
$P_PL00:
	inc	bx			;AN000; ready to see next byte
	call	$P_Chk_DBCS		;AN000; was it 1st byte of DBCS ?
	jnc	$P_Pack_Loop		;AN000; if no, process to next byte

	lodsb				;AN000; if yes, store
	mov	psdata_seg:[bx],al	;AN000;    2nd byte of DBCS
	inc	bx			;AN000; update pointer
	jmp	short $P_Pack_Loop	;AN000; process to next byte

$P_Pack_End_BY_EOL:
	dec	si			;AN000; backup si pointer
$P_Pack_End:
	mov	psdata_seg:$P_SI_Save,si     ;AC034; save next pointer, SI
	mov	byte ptr psdata_seg:[bx],$P_NULL ;AN000; put NULL at the end
	mov	psdata_seg:$P_Save_EOB,bx    ;AC034; 3/17/87 keep the address for later use of complex
	mov	bx,es:[di].$P_PARMSX_Address ;AN000; get PARMSX address
	lea	si,psdata_seg:$P_STRING_BUF
	cmp	byte ptr psdata_seg:[si],$P_Switch ;AN000; the operand begins w/ switch char ?
	je	$P_SW_Manager		     ;AN000; if yes, process as switch

	test	psdata_seg:$P_Flags2,$P_equ   ;AC034; the operand includes equal char ?
	jne	$P_Key_manager		     ;AN000; if yes, process as keyword

$P_Positional_Manager:			;AN000; else process as positional
	mov	al,es:[bx].$P_MaxP	;AN000; get maxp
	xor	ah,ah			;AN000; ax = maxp
	cmp	psdata_seg:$P_ORDINAL,ax ;AC034; too many positional ?
	jae	$P_Too_Many_Error	;AN000; if yes, set exit code to too many

	mov	ax,psdata_seg:$P_ORDINAL ;AC034; see what the current ordinal
	shl	ax,1			;AN000; ax = ax*2
	inc	bx			;AC035; add '2' to
	inc	bx			;AC035;  BX reg
					;AN000; now bx points to 1st CONTROL
;(changed ;AC035;) add	   bx,2 	;AN000; now bx points to 1st CONTROL
	add	bx,ax			;AN000; now bx points to specified CONTROL address
	mov	bx,es:[bx]		;AN000; now bx points to specified CONTROL itself
	call	$P_Chk_Pos_Control	;AN000; Do process for positional
	jmp	short $P_Return_to_Caller ;AN000; and return to the caller

$P_Too_Many_Error:
	mov	psdata_seg:$P_RC,$P_Too_Many ;AC034; set exit code
	jmp	short $P_Return_to_Caller ;AN000; and return to the caller
;
$P_SW_Manager:
	mov	al,es:[bx].$P_MaxP	;AN000; get maxp
	xor	ah,ah			;AN000; ax = maxp
	inc	ax
	shl	ax,1			;AN000; ax = (ax+1)*2
	add	bx,ax			;AN000; now bx points to maxs
	mov	cl,es:[bx]
	xor	ch,ch			;AN000; cx = maxs
	or	cx,cx			;AN000; at least one switch ?
	je	$P_SW_Not_Found

	inc	bx			;AN000; now bx points to 1st CONTROL address

$P_SW_Mgr_Loop:
	push	bx
	mov	bx,es:[bx]		;AN000; bx points to Switch CONTROL itself
	call	$P_Chk_SW_Control	;AN000; do process for switch
	pop	bx
	jnc	$P_Return_to_Caller	;AN000; if the CONTROL is for the switch, exit

	inc	bx			;AC035; add '2' to
	inc	bx			;AC035;  BX reg
					;AN000; else bx points to the next CONTROL
;(changed ;AC035;)  add     bx,2	;AN000; else bx points to the next CONTROL
	loop	$P_SW_Mgr_Loop		;AN000; and loop

$P_SW_Not_Found:
	mov	psdata_seg:$P_RC,$P_Not_In_SW ;AC034; here no CONTROL for the switch has
	jmp	short $P_Return_to_Caller0    ;AN000; not been found, means error.
;
$P_Key_Manager:
	mov	al,es:[bx].$P_MaxP	;AN000; get maxp
	xor	ah,ah			;AN000; ax = maxp
	inc	ax
	shl	ax,1			;AN000; ax = (ax+1)*2
	add	bx,ax			;AN000; now bx points to maxs
	mov	al,es:[bx]
	xor	ah,ah			;AN000; ax = maxs
	shl	ax,1
	inc	ax			;AN000; ax = ax*2+1
	add	bx,ax			;AN000; now bx points to maxk
	mov	cl,es:[bx]
	xor	ch,ch			;AN000; cx = maxk
	or	cx,cx			;AN000; at least one keyword ?
	je	$P_Key_Not_Found

	inc	bx			;AN000; now bx points to 1st CONTROL

$P_Key_Mgr_Loop:
	push	bx
	mov	bx,es:[bx]		;AN000; bx points to keyword CONTROL itself
	call	$P_Chk_Key_Control	;AN000; do process for keyword
	pop	bx
	jnc	$P_Return_to_Caller	;AN000; if the CONTROL is for the keyword, exit

	inc	bx			;AC035; add '2' to
	inc	bx			;AC035;  BX reg
					;AN000; else bx points to the next CONTROL
;(changed ;AC035;)  add     bx,2	;AN000; else bx points to the next CONTROL
	loop	$P_Key_Mgr_Loop 	;AN000; and loop

$P_Key_Not_Found:
	mov	psdata_seg:$P_RC,$P_Not_In_Key ;AC034; here no CONTROL for the keyword has
$P_Return_to_Caller0:			;AN000; not been found, means error.

;(deleted ;AN024;)	 mov	 bx,es:[bx-2]		 ;AN000; (tm13) backup bx

;(deleted ;AN024;)	 mov	 al,$P_String		 ;AN000; Set
;(deleted ;AN024;)	 mov	 ah,$P_No_Tag		 ;AN000;     result
;(deleted ;AN024;)	 call	 $P_Fill_Result 	 ;AN000;	    buffer

$P_Return_to_Caller:
	pop	bp
	pop	di
	pop	bx
	mov	cx,psdata_seg:$P_Ordinal    ;AC034; return next ordinal
	mov	ax,psdata_seg:$P_RC	    ;AC034; return exit code
	mov	si,psdata_seg:$P_SI_Save    ;AC034; return next operand pointer
	mov	dx,psdata_seg:$P_DX	    ;AC034; return result buffer address
	mov	bl,psdata_seg:$P_Terminator ;AC034; return delimiter code found
$P_Single_Exit:
	clc
	ret
SysParse endp
PAGE
;***********************************************************************
; $P_Chk_Pos_Control
;
; Function: Parse CONTROL block for a positional
;
; Input:     ES:BX -> CONTROL block
;	     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    None
;
; Use:	 $P_Fill_Result, $P_Check_Match_Flags
;
; Vars: $P_Ordinal(W), $P_RC(W)
;***********************************************************************
$P_Chk_Pos_Control proc
	push	ax
	mov	ax,es:[bx].$P_Match_Flag
	test	ax,$P_Repeat		;AN000; repeat allowed ?
	jne	$P_CPC00		;AN000; then do not increment ORDINAL

	inc	psdata_seg:$P_ORDINAL	;AC034; update the ordinal
$P_CPC00:
	cmp	byte ptr psdata_seg:[si],$P_NULL ;AN000; no data ?
	jne	$P_CPC01

	test	ax,$P_Optional		;AN000; yes, then is it optional ?
	jne	$P_CPC02

	mov	psdata_seg:$P_RC,$P_Op_Missing ;AC034; no, then error	     3/17/87
	jmp	short $P_CPC_Exit

$P_CPC02:
	push	ax
	mov	al,$P_String		;AN000; if it is optional return NULL
	mov	ah,$P_No_Tag		;AN000; no item tag indication
	call	$P_Fill_Result
	pop	ax
	jmp	short $P_CPC_Exit

$P_CPC01:
	call	$P_Check_Match_Flags
$P_CPC_Exit:
	pop	ax
	ret
$P_Chk_Pos_Control endp
PAGE
;***********************************************************************
; $P_Chk_Key_Control
;
; Function: Parse CONTROL block for a keyword
;
; Input:     ES:BX -> CONTROL block
;	     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    CY = 1 : not match
;
; Use:	 $P_Fill_Result, $P_Search_KEYorSW, $P_Check_Match_Flags
;
; Vars: $P_RC(W), $P_SaveSI_Cmpx(W), $P_KEYorSW_Ptr(R), $P_Flags(W)
;***********************************************************************
$P_Chk_Key_Control proc
IF	KeySW				;AN000;(Check if keyword is supported)
	or	psdata_seg:$P_Flags2,$P_Key_Cmp ;AC034; Indicate keyword for later string comparison
	call	$P_Search_KEYorSW	;AN000; Search the keyword in the CONTROL block
	jc	$P_Chk_Key_Err0 	;AN000; not found, then try next CONTROL

	and	psdata_seg:$P_Flags2,0ffh-$P_Key_Cmp ;AC034; reset the indicator previously set
;
	push	ax			     ;AN000;	      keyword=
	mov	ax,psdata_seg:$P_KEYorSW_Ptr ;AC034;	      ^       ^
	sub	ax,si			;AN000;  SI	KEYorSW
	add	psdata_seg:$P_SaveSI_Cmpx,ax ;AC034; update for complex, quoted or file spec.
	pop	ax
;
	mov	si,psdata_seg:$P_KEYorSW_Ptr ;AC034; set si just after equal char
	cmp	byte ptr psdata_seg:[si],$P_NULL ;AN000; any data after equal ?
	je	$P_Chk_Key_Err1 	;AN000; if no, syntax error

	call	$P_Check_Match_Flags	;AN000; else, process match flags
	clc
	jmp	short $P_Chk_Key_Exit

$P_Chk_Key_Err0:
	stc				;AN000; not found in keyword synonym list
	jmp	short $P_Chk_Key_Exit

$P_Chk_Key_Err1:
	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; no parameter is not specified after "="
$P_Chk_Key_ErrExit:
	push	ax
	mov	al,$P_String		;AN000; set
	mov	ah,$P_No_Tag		;AN000;    result
	call	$P_Fill_Result		;AN000; 	 buffer
	pop	ax
	clc
$P_Chk_Key_Exit:
	ret
ELSE					;AN000;(of IF KeySW)
	stc				;AN000;this logic works when the KeySW
	ret				;AN000;is reset.
ENDIF					;AN000;(of KeySW)
$P_Chk_Key_Control endp
PAGE
;***********************************************************************
IF	KeySW+SwSW			;AN000;(Check if keyword or switch is supported)
; $P_Search_KEYorSW:
;
; Function: Seach specified keyword or switch from CONTROL
;
; Input:     ES:BX -> CONTROL block
;	     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    CY = 1 : not match
;
; Use:	 $P_String_Comp, $P_MoveBP_NUL, $P_Found_SYNONYM
;***********************************************************************
$P_Search_KEYorSW proc
	push	bp
	push	cx
	mov	cl,es:[bx].$P_nid	;AN000; Get synonym count
	xor	ch,ch			;AN000; and set it to cx
	or	cx,cx			;AN000; No synonyms specified ?
	je	$P_KEYorSW_Not_Found	;AN000; then indicate not found by CY

	lea	bp,es:[bx].$P_KEYorSW	;AN000; BP points to the 1st synonym
$P_KEYorSW_Loop:
	call	$P_String_Comp		;AN000; compare string in buffer w/ the synonym
	jnc	$P_KEYorSW_Found	;AN000; If match, set it to synonym pointer

	call	$P_MoveBP_NUL		;AN000; else, bp points to the next string
	loop	$P_KEYorSW_Loop 	;AN000; loop nid times
$P_KEYorSW_Not_Found:
	stc				;AN000; indicate not found in synonym list
	jmp	short $P_KEYorSW_Exit	;AN000; and exit

$P_KEYorSW_Found:
	mov	psdata_seg:$P_Found_SYNONYM,bp ;AC034; set synonym pointer
	clc				;AN000; indicate found
$P_KEYorSW_Exit:
	pop	cx
	pop	bp
	ret
$P_Search_KEYorSW endp
;***********************************************************************
; $P_MoveBP_NUL
;***********************************************************************
$P_MoveBP_NUL proc
$P_MBP_Loop:
	cmp	byte ptr es:[bp],$P_NULL ;AN000; Increment BP that points
	je	$P_MBP_Exit		;AN000; to the synomym list

	inc	bp			;AN000; until
	jmp	short $P_MBP_Loop	;AN000; NULL encountered.

$P_MBP_Exit:
	inc	bp			;AN000; bp points to next to NULL
	ret
$P_MoveBP_NUL endp
ENDIF					;AN000;(of KeySW+SwSW)
PAGE
;***********************************************************************
; $P_Chk_SW_Control
;
; Function: Parse CONTROL block for a switch
;
; Input:     ES:BX -> CONTROL block
;	     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    CY = 1 : not match
;
; Use:	 $P_Fill_Result, $P_Search_KEYorSW, $P_Check_Match_Flags
;
; Vars:  $P_SaveSI_Cmpx(W), $P_KEYorSW_Ptr(R), $P_Flags(W)
;***********************************************************************
$P_Chk_SW_Control proc


IF	SwSW				;AN000;(Check if switch is supported)
	or	psdata_seg:$P_Flags2,$P_Sw_Cmp ;AC034; Indicate switch for later string comparison
	call	$P_Search_KEYorSW	;AN000; Search the switch in the CONTROL block
	jc	$P_Chk_SW_Err0		;AN000; not found, then try next CONTROL

	and	psdata_seg:$P_Flags2,0ffh-$P_Sw_Cmp ;AC034; reset the indicator previously set
;
	push	ax			;AN000; 	      /switch:
	mov	ax,psdata_seg:$P_KEYorSW_Ptr ;AC034;	      ^       ^
	sub	ax,si			;AN000;  SI	KEYorSW
	add	psdata_seg:$P_SaveSI_Cmpx,ax ;AC034; update for complex list
	pop	ax
;
	mov	si,psdata_seg:$P_KEYorSW_Ptr ;AC034; set si at the end or colon
	cmp	byte ptr psdata_seg:[si],$P_NULL ;AN000; any data after colon
	jne	$P_CSW00		;AN000; if yes, process match flags

	cmp	byte ptr psdata_seg:[si-1],$P_Colon ;AN000; if no, the switch terminated by colon ?
	jne	$P_Chk_if_data_required ;AN000; if yes,

	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; return syntax error
	jmp	short $P_Chk_SW_Exit

$P_Chk_if_data_required:		;AN018; no data, no colon
	cmp	es:[bx].$P_Match_Flag,0 ;AN018; should have data? zero match flag means switch followed by nothing is OK
	je	$P_Chk_SW_Exit		;AN018; match flags not zero so should have something if optional bit is not on

	test	es:[bx].$P_Match_Flag,$P_Optional ;AN019; see if no value is valid
	jnz	$P_Chk_SW_Exit		;AN019; if so, then leave, else yell

	mov	psdata_seg:$P_RC,$P_Op_Missing ;AC034; return required operand missing
	jmp	short $P_Chk_SW_Exit

$P_CSW00:
	call	$P_Check_Match_Flags	;AN000; process match flag
	clc				;AN000; indicate match
	jmp	short $P_Chk_SW_Single_Exit

$P_Chk_SW_Err0:
	stc				;AN000; not found in switch synonym list
	jmp	short $P_Chk_SW_Single_Exit

$P_Chk_SW_Exit:
	push	ax
	mov	al,$P_String		;AN000; set
	mov	ah,$P_No_Tag		;AN000;    result
	call	$P_Fill_Result		;AN000; 	 buffer
	pop	ax
	clc
$P_Chk_SW_Single_Exit:
	ret
ELSE					;AN000;(of IF SwSW)
	stc				;AN000; this logic works when the SwSW
	ret				;AN000; is reset.
ENDIF					;AN000;(of SwSW)
$P_Chk_SW_Control endp
PAGE
;***********************************************************************
; $P_Fill_Result
;
; Function: Fill the result buffer
;
; Input:    AH = Item tag
;	    AL = type
;		  AL = 1: CX,DX has 32bit number (CX = high)
;		  AL = 2: DX has index(offset) into value list
;		  AL = 6: DL has driver # (1-A, 2-B, ... , 26 - Z)
;		  AL = 7: DX has year, CL has month and CH has date
;		  AL = 8: DL has hours, DH has minutes, CL has secondsn,
;			  amd CH has hundredths
;		  AL = else: psdata_seg:SI points to returned string buffer
;	    ES:BX -> CONTROL block
;
; Output:   None
;
; Use:	$P_Do_CAPS_String, $P_Remove_Colon, $P_Found_SYNONYM
;
; Vars: $P_DX(W)
;***********************************************************************
$P_Fill_Result proc
	push	di
	mov	di,es:[bx].$P_Result_Buf ;AN000; di points to result buffer
	mov	psdata_seg:$P_DX,di	;AC034; set returned result address
	mov	es:[di].$P_Type,al	;AN000; store type
	mov	es:[di].$P_Item_Tag,ah	;AN000; store item tag
	push	ax
	mov	ax,psdata_seg:$P_Found_SYNONYM ;AC034; if yes,
	mov	es:[di].$P_SYNONYM_Ptr,ax ;AN000;   then set it to the result
	pop	ax
$P_RLT04:
	cmp	al,$P_Number		;AN000; if number
	jne	$P_RLT00

$P_RLT02:
	mov	word ptr es:[di].$P_Picked_Val,dx ;AN000; then store 32bit
	mov	word ptr es:[di+2].$P_Picked_Val,cx ;AN000;	number
	jmp	short $P_RLT_Exit

$P_RLT00:
	cmp	al,$P_List_Idx		;AN000; if list index
	jne	$P_RLT01

	mov	word ptr es:[di].$P_Picked_Val,dx ;AN000; then store list index
	jmp	short $P_RLT_Exit

$P_RLT01:
	cmp	al,$P_Date_F		;AN000; Date format ?
	je	$P_RLT02

	cmp	al,$P_Time_F		;AN000; Time format ?
	je	$P_RLT02
;
	cmp	al,$P_Drive		;AN000; drive format ?
	jne	$P_RLT03

	mov	byte ptr es:[di].$P_Picked_Val,dl ;AN000; store drive number
	jmp	short $P_RLT_Exit

$P_RLT03:
	cmp	al,$P_Complex		;AN000; complex format ?
	jne	$P_RLT05

	mov	ax,psdata_seg:$P_SaveSI_Cmpx ;AC034; then get pointer in command buffer
	inc	ax			;AN000; skip left Parentheses
	mov	word ptr es:[di].$P_Picked_Val,ax ;AN000; store offset
	mov	word ptr es:[di+2].$P_Picked_Val,ds ;AN000; store segment
	jmp	short $P_RLT_Exit

$P_RLT05:
;------------------------  AL = 3, 5, or 9
	mov	word ptr es:[di].$P_Picked_Val,si ;AN000; store offset of STRING_BUF
;(replaced ;AN031;)  mov word ptr es:[di+word].$P_Picked_Val,cs ;AN000; store segment of STRING_BUF
	mov	word ptr es:[di+2].$P_Picked_Val,Psdata_Seg ;AN031; store segment of STRING_BUF
;
	push	ax
	test	byte ptr es:[bx].$P_Function_Flag,$P_CAP_File ;AN000; need CAPS by file table?
	je	$P_RLT_CAP00

	mov	al,$P_DOSTBL_File	;AN000; use file upper case table
	jmp	short $P_RLT_CAP02

$P_RLT_CAP00:
	test	byte ptr es:[bx].$P_Function_Flag,$P_CAP_Char ;AN000; need CAPS by char table ?
	je	$P_RLT_CAP01

	mov	al,$P_DOSTBL_Char	;AN000; use character upper case table
$P_RLT_CAP02:
	call	$P_Do_CAPS_String	;AN000;  process CAPS along the table
$P_RLT_CAP01:
	pop	ax
	test	byte ptr es:[bx].$P_Function_Flag,$P_Rm_Colon ;AN000; removing colon at end ?
	je	$P_RLT_Exit

	call	$P_Remove_Colon 	;AN000; then process it.
$P_RLT_Exit:
	pop	di
	ret
$P_Fill_Result endp
PAGE
;***********************************************************************
; $P_Check_Match_Flags
;
; Function:  Check the mutch_flags and make the exit code and set the
;	     result buffer
;
;	    Check for types in this order:
;		Complex
;		Date
;		Time
;		Drive
;		Filespec
;		Quoted String
;		Simple String
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	     $P_Value, P$_SValue, $P_Simple_String, $P_Date_Format
;	     $P_Time_Format, $P_Complex_Format, $P_File_Foemat
;	     $P_Drive_Format
;***********************************************************************
$P_Check_Match_Flags proc
	mov	psdata_seg:$P_err_flag,$P_NULL ;AN033;AC034;; clear filespec error flag.
	push	ax
	mov	ax,es:[bx].$P_Match_Flag ;AN000; load match flag(16bit) to ax

	or	ax,ax			;AC035; test ax for zero
;(changed ;AC035;)  cmp     ax,0	;AN000; (tm12)
	jne	$P_Mat			;AN000; (tm12)

	push	ax			;AN000; (tm12)
	push	bx			;AN000; (tm12)
	push	dx			;AN000; (tm12)
	push	di			;AN000; (tm12)
	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; (tm12)
	mov	ah,$P_No_Tag		;AN000; (tm12)
	mov	al,$P_String		;AN000; (tm12)
	call	$P_Fill_Result		;AN000; (tm12)
	pop	di			;AN000; (tm12)
	pop	dx			;AN000; (tm12)
	pop	bx			;AN000; (tm12)
	pop	ax			;AN000; (tm12)
	jmp	short $P_Bridge 	;AC035; (tm12)

$P_Mat: 				;AN000; (tm12)

IF	CmpxSW				;AN000;(Check if complex item is supported)
	test	ax,$P_Cmpx_S		;AN000; Complex string
	je	$P_Match01

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Complex_Format	;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Bridge

$P_Match01:
ENDIF					;AN000;(of CmpxSW)
IF	DateSW				;AN000;(Check if date format is supported)
	test	ax,$P_Date_S		;AN000; Date string
	je	$P_Match02

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Date_Format		;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Bridge

$P_Match02:
ENDIF					;AN000;(of DateSW)
IF	TimeSW				;AN000;(Check if time format is supported)
	test	ax,$P_Time_S		;AN000; Time string
	je	$P_Match03

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Time_Format		;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
;	je	$P_Match03		;AN000:

	jne	$P_Bridge		;AN000; (tm09)

ENDIF					;AN000;(of TimeSW)  (tm04)
	jmp	short $P_Match03	;AN025; (tm09)

$P_Bridge:
;	jmp	short $P_Match_Exit (tm02)

IFDEF TPARSE_SHORT_JUMPS
       jmp	short $P_Match_Exit	; JWasm: COMMAND transient layout
ELSE
       jmp	$P_Match_Exit		;AN000; (tm02)
ENDIF

$P_Match03:
; ENDIF ;AN000;(of TimeSW) (tm04)
IF	NumSW				;AN000;(Check if numeric value is supported)
	test	ax,$P_Num_Val		;AN000; Numeric value
	je	$P_Match04

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Value		;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Match_Exit

$P_Match04:
	test	ax,$P_SNUM_Val		;AN000; Signed numeric value
	je	$P_Match05

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_SValue		;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Match_Exit

$P_Match05:
ENDIF					;AN000;(of NumSW)
IF	DrvSW				;AN000;(Check if drive only is supported)
	test	ax,$P_Drv_Only		;AN000; Drive only
	je	$P_Match06

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_File_Format		;AN000; 1st, call file format
	call	$P_Drive_Format 	;AN000; check drive format, next
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examinee the next type
	jne	$P_Match_Exit

$P_Match06:
ENDIF					;AN000;(of DrvSW)
IF	FileSW				;AN000;(Check if file spec is supported)
	test	ax,$P_File_Spc		;AN000; File spec
	je	$P_Match07

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_File_Format		;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Match_Exit

$P_Match07:
ENDIF					;AN000;(of FileSW)
IF	QusSW				;AN000;(Check if quoted string is supported)
	test	ax,$P_Qu_String 	;AN000; Quoted string
	je	$P_Match08

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Quoted_Format	;AN000; do process
	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; if error, examine the next type
	jne	$P_Match_Exit

$P_Match08:
ENDIF					;AN000;(of QusSW)
	test	ax,$P_Simple_S		;AN000; Simple string
	je	$P_Match09

	mov	psdata_seg:$P_RC,$P_No_Error ;AC034; assume no error
	call	$P_Simple_String	;AN000; do process
;;;;	cmp	psdata_seg:$P_RC,$P_Syntax ;AC034; These two lines will be alive
;;;;	jne	$P_Match_Exit			   ;when extending the match_flags.
$P_Match09:
$P_Match_Exit:
	cmp	psdata_seg:$P_err_flag,$P_error_filespec ;AC034; bad filespec ?
	jne	$P_Match2_Exit		;AN033; no, continue
	cmp	psdata_seg:$P_RC,$P_No_Error ;AN033;AC034;; check for other errors ?
	jne	$P_Match2_Exit		;AN033; no, continue
	mov	psdata_seg:$P_RC,$P_Syntax ;AN033;AC034;; set error flag
$P_Match2_Exit:
	pop	ax
	ret
$P_Check_Match_Flags endp
PAGE
;***********************************************************************
; $P_Remove_Colon;
;
; Function: Remove colon at end
;
; Input:    psdata_seg:SI points to string buffer to be examineed
;
; Output:   None
;
; Use:	$P_Chk_DBCS
;***********************************************************************
$P_Remove_Colon proc
	push	ax
	push	si
$P_RCOL_Loop:
	mov	al,psdata_seg:[si]	;AN000; get character
	or	al,al			;AN000; end of string ?
	je	$P_RCOL_Exit		;AN000; if yes, just exit

	cmp	al,$P_Colon		;AN000; is it colon ?
	jne	$P_RCOL00

	cmp	byte ptr psdata_seg:[si+byte],$P_NULL ;AN000; if so, next is NULL ?
	jne	$P_RCOL00		;AN000; no, then next char

	mov	byte ptr psdata_seg:[si],$P_NULL ;AN000; yes, remove colon
	jmp	short $P_RCOL_Exit	;AN000; and exit.

$P_RCOL00:
	call	$P_Chk_DBCS		;AN000; if not colon, then check if
	jnc	$P_RCOL01		;AN000; DBCS leading byte.

	inc	si			;AN000; if yes, skip trailing byte
$P_RCOL01:
	inc	si			;AN000; si points to next byte
	jmp	short $P_RCOL_Loop	;AN000; loop until NULL encountered

$P_RCOL_Exit:
	pop	si
	pop	ax
	ret
$P_Remove_Colon endp
PAGE
;***********************************************************************
; $P_Do_CAPS_String;
;
; Function: Perform capitalization along with the file case map table
;	    or character case map table.
;
; Input:    AL = 2 : Use character table
;	    AL = 4 : Use file table
;	    psdata_seg:SI points to string buffer to be capitalized
;
; Output:   None
;
; Use:	$P_Do_CAPS_Char, $P_Chk_DBCS
;***********************************************************************
$P_Do_CAPS_String proc
	push	si
	push	dx
	mov	dl,al			;AN000; save info id

$P_DCS_Loop:
	mov	al,psdata_seg:[si]	;AN000; load charater and
	call	$P_Chk_DBCS		;AN000; check if DBCS leading byte
	jc	$P_DCS00		;AN000; if yes, do not need CAPS

	or	al,al			;AN000; end of string ?
	je	$P_DCS_Exit		;AN000; then exit.

	call	$P_Do_CAPS_Char 	;AN000; Here a SBCS char need to be CAPS
	mov	psdata_seg:[si],al	;AN000; stored upper case char to buffer
	jmp	short $P_DCS01		;AN000; process nexit
$P_DCS00:
	inc	si			;AN000; skip DBCS leading and trailing byte
$P_DCS01:
	inc	si			;AN000; si point to next byte
	jmp	short $P_DCS_Loop	;AN000; loop until NULL encountered
$P_DCS_Exit:
	pop	dx
	pop	si
	ret
$P_Do_CAPS_String endp
PAGE
;***********************************************************************
; $P_Do_CAPS_Char;
;
; Function: Perform capitalization along with the file case map table
;	    or character case map table.
;
; Input:    DL = 2 : Use character table
;	    DL = 4 : Use file table
;	    AL = character to be capitalized
;
; Output:   None
;
; Use:	INT 21h /w AH=65h
;***********************************************************************
$P_Do_CAPS_Char proc
	cmp	al,$P_ASCII80		;AN000; need upper case table ?
	jae	$P_DCC_Go

	cmp	al,"a"                  ;AN000; if no,
	jb	$P_CAPS_Ret		;AN000;   check if  "a" <= AL <= "z"

	cmp	al,"z"
	ja	$P_CAPS_Ret		;AN000;   if yes, make CAPS

	and	al,$P_Make_Upper	;AN000;   else do nothing.
	jmp	short $P_CAPS_Ret

$P_DCC_Go:
	push	bx
	push	es
	push	di
IF	CAPSW				;AN000;(Check if uppercase conversion is supported)
	lea	di,psdata_seg:$P_File_CAP_Ptr
	cmp	dl,$P_DOSTBL_File	;AN000; Use file CAPS table ?
	je	$P_DCC00

ENDIF					;AN000;(of CAPSW)
	lea	di,psdata_seg:$P_Char_CAP_Ptr ;AC034; or use char CAPS table ?
$P_DCC00:
	cmp	psdata_seg:[di],dl	;AN000; already got table address ?
	je	$P_DCC01		;AN000; if no,

;In this next section, ES will be used to pass a 5 byte workarea to INT 21h,
; the GET COUNTYRY INFO call.  This usage of ES is required by the function
; call, regardless of what base register is currently be defined as PSDATA_SEG.
;BASESW EQU 0 means that ES is the psdata_seg reg.

IFDEF BASESW				;AN037; If BASESW has been defined, and
  IFE BASESW				;AN037; If ES is psdata base
	push	PSDATA_SEG		;AN037; save current base reg
  ENDIF
ENDIF

	push	ax			;AN000; get CAPS table thru DOS call
	push	cx
	push	dx


	push	PSDATA_SEG		;AC036; pass current base seg into
					;(Note: this used to push CS.  BUG...
	pop	es			;AN000;   ES reg, required for
					;get extended country information
	mov	ah,$P_DOS_Get_TBL	;AN000; get extended CDI
	mov	al,dl			;AN000; upper case table
	mov	bx,$P_DOSTBL_Def	;AN000; get active CON
	mov	cx,$P_DOSTBL_BL 	;AN000; buffer length
	mov	dx,$P_DOSTBL_Def	;AN000; get for default code page
					;DI already set to point to buffer
	int	21h			;AN000; es:di point to buffer that
					;now has been filled in with info
	pop	dx
	pop	cx
	pop	ax
IFDEF BASESW				;AN037; If BASESW has been defined, and
  IFE BASESW				;AN037; If ES is psdata base
	pop	PSDATA_SEG		;AN037; restore current base reg
  ENDIF
ENDIF
$P_DCC01:

;In this next section, ES will be used as the base of the XLAT table, provided
; by the previous GET COUNTRY INFO DOS call.  This usage of ES is made
; regardless of which base reg is currently the PSDATA_SEG reg.

IFDEF BASESW				;AN037; If BASESW has been defined, and
  IFE BASESW				;AN037; If ES is psdata base
	push	PSDATA_SEG		;AN037; save current base reg
  ENDIF
ENDIF
	mov	bx,psdata_seg:[di+$P_DOS_TBL_Off] ;AN000; get offset of table
	mov	es,psdata_seg:[di+$P_DOS_TBL_Seg] ;AN000; get segment of table
	inc	bx			;AC035; add '2' to
	inc	bx			;AC035;  BX reg
					;AN000; skip length field
;(changed ;AN035;) add	   bx,word	;AN000; skip length field
	sub	al,$P_ASCII80		;AN000; make char to index
	xlat	es:[bx] 		;AN000; perform case map

IFDEF BASESW				;AN037; If BASESW has been defined, and
  IFE BASESW				;AN037; If ES is psdata base
	pop	PSDATA_SEG		;AN037; restore current base reg
  ENDIF
ENDIF
	pop	di
	pop	es
	pop	bx
$P_CAPS_Ret:
	ret
$P_Do_CAPS_Char endp
PAGE
;***********************************************************************
IF	NumSW				;AN000;(Check if numeric value is supported)
; $P_Value / $P_SValue
;
; Function:  Make 32bit value from psdata_seg:SI and see value list
;	     and make result buffer.
;	     $P_SValue is an entry point for the signed value
;	     and this will simply call $P_Value after the handling
;	     of the sign character, "+" or "-"
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Check_OVF
;
; Vars: $P_RC(W), $P_Flags(RW)
;***********************************************************************
$P_SValue proc				;AN000; when signed value here
	push	ax
	or	psdata_seg:$P_Flags2,$P_Signed	    ;AC034; indicate a signed numeric
	and	psdata_seg:$P_Flags2,0ffh-$P_Neg  ;AC034; assume positive value
	mov	al,psdata_seg:[si]	;AN000; get sign
	cmp	al,$P_Plus		;AN000; "+" ?
	je	$P_SVal00

	cmp	al,$P_Minus		;AN000; "-" ?
	jne	$P_Sval01		;AN000; else

	or	psdata_seg:$P_Flags2,$P_Neg ;AC034; set this is negative value
$P_SVal00:
	inc	si			;AN000; skip sign char
$P_Sval01:
	call	$P_Value		;AN000; and process value
	pop	ax
	ret
$P_SValue endp
;***********************************************************************
$P_Value proc
	push	ax
	push	cx
	push	dx
	push	si
	xor	cx,cx			;AN000; cx = higher 16 bits
	xor	dx,dx			;AN000; dx = lower 16 bits
	push	bx			;AN000; save control pointer
$P_Value_Loop:
	mov	al,psdata_seg:[si]	;AN000; get character
	or	al,al			;AN000; end of line ?
	je	$P_Value00

	call	$P_0099 		;AN000; make asc(0..9) to bin(0..9)
	jc	$P_Value_Err0

	xor	ah,ah
	mov	bp,ax			;AN000; save binary number
	shl	dx,1			;AN000; to have 2*x
	rcl	cx,1			;AN000; shift left w/ carry
	call	$P_Check_OVF		;AN000; Overflow occurred ?
	jc	$P_Value_Err0		;AN000; then error, exit

	mov	bx,dx			;AN000; save low(2*x)
	mov	ax,cx			;AN000; save high(2*x)
	shl	dx,1			;AN000; to have 4*x
	rcl	cx,1			;AN000; shift left w/ carry
	call	$P_Check_OVF		;AN000; Overflow occurred ?
	jc	$P_Value_Err0		;AN000; then error, exit

	shl	dx,1			;AN000; to have 8*x
	rcl	cx,1			;AN000; shift left w/ carry
	call	$P_Check_OVF		;AN000; Overflow occurred ?
	jc	$P_Value_Err0		;AN000; then error, exit

	add	dx,bx			;AN000; now have 10*x
	adc	cx,ax			;AN000; 32bit ADD
	call	$P_Check_OVF		;AN000; Overflow occurred ?
	jc	$P_Value_Err0		;AN000; then error, exit

	add	dx,bp			;AN000; Add the current one degree decimal
	adc	cx,0			;AN000; if carry, add 1 to high 16bit
	call	$P_Check_OVF		;AN000; Overflow occurred ?
	jc	$P_Value_Err0		;AN000; then error, exit

	inc	si			;AN000; update pointer
	jmp	short $P_Value_Loop	;AN000; loop until NULL encountered
;
$P_Value_Err0:
	pop	bx
	jmp	$P_Value_Err		;AN000; Bridge
;
$P_Value00:
	pop	bx			;AN000; restore control pointer
	test	psdata_seg:$P_Flags2,$P_Neg ;AC034; here cx,dx = 32bit value
	je	$P_Value01		;AN000; was it negative ?

	not	cx			;AN000; +
	not	dx			;AN000; |- Make 2's complement
	add	dx,1			;AN000; |
	adc	cx,0			;AN000; +
$P_Value01:				;AN000; / nval =0
	mov	si,es:[bx].$P_Value_List ;AN000; si points to value list
	mov	al,es:[si]		;AN000; get nval
	cmp	al,$P_nval_None 	;AN000; no value list ?
	jne	$P_Value02

	mov	al,$P_Number		;AN000; Set type
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
IFDEF TPARSE_SHORT_JUMPS
	jmp	short $P_Value_Exit	; JWasm: COMMAND transient layout
ELSE
	jmp	$P_Value_Exit
ENDIF

$P_Value02:				;AN000; / nval = 1
IF	Val1SW				;AN000;(Check if value list id #1 is supported)
;(tm07) cmp	al,$P_nval_Range	;AN000; have range list ?
;(tm07) jne	$P_Value03

	inc	si
	mov	al,es:[si]		;AN000; al = number of range
	cmp	al,$P_No_nrng		;AN000; (tm07)
	je	$P_Value03		;AN000; (tm07)

	inc	si			;AN000; si points to 1st item_tag
$P_Val02_Loop:
	test	psdata_seg:$P_Flags2,$P_Signed
	jne	$P_Val02_Sign

	cmp	cx,es:[si+$P_Val_XH]	;AN000; comp cx with XH
	jb	$P_Val02_Next

	ja	$P_Val_In

	cmp	dx,es:[si+$P_Val_XL]	;AN000; comp dx with XL
	jb	$P_Val02_Next

$P_Val_In:
;;;;;;	cmp	cx,es:$P_Val_YH]	; comp cx with YH (tm01)
	cmp	cx,es:[si+$P_Val_YH]	;AN000; comp cx with YH (tm01)
	ja	$P_Val02_Next

	jb	$P_Val_Found

	cmp	dx,es:[si+$P_Val_YL]	;AN000; comp dx with YL
	ja	$P_Val02_Next

	jmp	short $P_Val_Found

$P_Val02_Sign:
	cmp	cx,es:[si+$P_Val_XH]	;AN000; comp cx with XH
	jl	$P_Val02_Next

	jg	$P_SVal_In

	cmp	dx,es:[si+$P_Val_XL]	;AN000; comp dx with XL
	jl	$P_Val02_Next

$P_SVal_In:
	cmp	cx,es:[si+$P_Val_YH]	;AN000; comp cx with YH
	jg	$P_Val02_Next

	jl	$P_Val_Found

	cmp	dx,es:[si+$P_Val_YL]	;AN000; comp dx with YL
	jg	$P_Val02_Next

	jmp	short $P_Val_Found

$P_Val02_Next:
	add	si,$P_Len_Range
	dec	al			;AN000; loop nrng times in AL
	jne	$P_Val02_Loop
					; / Not found
	mov	psdata_seg:$P_RC,$P_Out_of_Range
	mov	al,$P_Number
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
	jmp	short $P_Value_Exit

ENDIF					;AN000;(of Val1SW)
IF	Val1SW+Val2SW			;AN000;(Check if value list id #1 or #2 is supported)
$P_Val_Found:
	mov	al,$P_Number
	mov	ah,es:[si]		;AN000; found ITEM_TAG set
	jmp	short $P_Value_Exit

ENDIF					;AN000;(of Val1SW+Val2SW)
$P_Value03:				;AN000; / nval = 2
IF	Val2SW				;AN000;(Check if value list id #2 is supported)
;;;;	cmp	al,$P_nval_Value	; have match list ? ASSUME nval=2,
;;;;	jne	$P_Value04		; even if it is 3 or more.
;(tm07) inc	si
;(tm07) mov	al,es:[si]		;AN000; al = nrng
	mov	ah,$P_Len_Range
	mul	ah			;AN000;  Skip nrng field
	inc	ax
	add	si,ax			;AN000; si points to nnval
	mov	al,es:[si]		;AN000; get nnval
	inc	si			;AN000; si points to 1st item_tag
$P_Val03_Loop:
	cmp	cx,es:[si+$P_Val_XH]	;AN000; comp cx with XH
	jne	$P_Val03_Next

	cmp	dx,es:[si+$P_Val_XL]	;AN000; comp dx with XL
	je	$P_Val_Found

$P_Val03_Next:
	add	si,$P_Len_Value 	;AN000; points to next value choice
	dec	al			;AN000; loop nval times in AL
	jne	$P_Val03_Loop
					;AN000; / Not found
	mov	psdata_seg:$P_RC,$P_Not_in_Val
	mov	al,$P_Number
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
	jmp	short $P_Value_Exit

ENDIF					;AN000;(of Val2SW)
$P_Value04:				;AN000; / nval = 3 or else
$P_Value_Err:
	mov	psdata_seg:$P_RC,$P_Syntax
	mov	al,$P_String		;AN000; Set type
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
$P_Value_Exit:
	call	$P_Fill_Result
	pop	si
	pop	dx
	pop	cx
	pop	ax
	ret
$P_Value endp
PAGE
;***********************************************************************
; $P_Check_OVF
;
; Function:  Check if overflow is occurred with consideration of
;	     signed or un-signed numeric value
;
; Input:     Flag register
;
; Output:    CY = 1  :	Overflow
;
; Vars:     $P_Flags(R)
;***********************************************************************
$P_Check_OVF proc
	pushf
	test	psdata_seg:$P_Flags2,$P_Neg ;AC034; is it negative value ?
	jne	$P_COVF 		;AN000; if no, check overflow

	popf				;AN000; by the CY bit
	ret

$P_COVF:
	popf				;AN000; else,
	jo	$P_COVF00		;AN000; check overflow by the OF

	clc				;AN000; indicate it with CY bit
	ret				;AN000; CY=0 means no overflow

$P_COVF00:
	stc				;AN000; and CY=1 means overflow
	ret
$P_Check_OVF endp
ENDIF					;AN000;(of FarSW)
;***********************************************************************
; $P_0099;
;
; Function:  Make ASCII 0-9 to Binary 0-9
;
; Input:     AL = character code
;
; Output:    CY = 1 : AL is not number
;	     CY = 0 : AL contains binary value
;***********************************************************************
$P_0099 proc
	cmp	al,"0"
	jb	$P_0099Err		;AN000;  must be 0 =< al =< 9

	cmp	al,"9"
	ja	$P_0099Err		;AN000;  must be 0 =< al =< 9

	sub	al,"0"                  ;AN000; make char -> bin
	clc				;AN000; indicate no error
	ret

$P_0099Err:
	stc				;AN000; indicate error
	ret
$P_0099 endp
PAGE
;***********************************************************************
; $P_Simple_String
;
; Function:  See value list for the simple string
;	     and make result buffer.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_String_Comp
;
; Vars: $P_RC(W)
;***********************************************************************
$P_Simple_String proc
	push	ax
	push	bx
	push	dx
	push	di
	mov	di,es:[bx].$P_Value_List ;AN000; di points to value list
	mov	al,es:[di]		;AN000; get nval
	or	al,al			;AN000; no value list ?
	jne	$P_Sim00		;AN000; then

	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
	jmp	short $P_Sim_Exit	;AN000; and set result buffer

$P_Sim00:
IF	Val3SW+KeySW			;AN000;(Check if keyword or value list id #3 is supported)
	cmp	al,$P_nval_String	;AN000; String choice list provided ?
	jne	$P_Sim01		;AN000; if no, syntax error

	inc	di
	mov	al,es:[di]		;AN000; al = nrng
	mov	ah,$P_Len_Range
	mul	ah			;AN000;  Skip nrng field
	inc	ax			;AN000; ax = (nrng*9)+1
	add	di,ax			;AN000; di points to nnval
	mov	al,es:[di]		;AN000; get nnval
	mov	ah,$P_Len_Value
	mul	ah			;AN000; Skip nnval field
	inc	ax			;AN000; ax = (nnval*5)+1
	add	di,ax			;AN000; di points to nstrval
	mov	al,es:[di]		;AN000; get nstrval
	inc	di			;AC035; add '2' to
	inc	di			;AC035;  DI reg
					;AN000; di points to 1st string in list
;(replaced ;AC035;) add     di,2	;AN000; di points to 1st string in list
$P_Sim_Loop:
	mov	bp,es:[di]		;AN000; get string pointer
	call	$P_String_Comp		;AN000; compare it with operand
	jnc	$P_Sim_Found		;AN000; found on list ?

	add	di,$P_Len_String	;AN000; if no, point to next choice
	dec	al			;AN000; loop nstval times in AL
	jne	$P_Sim_Loop
					;AN000; / Not found
	mov	psdata_seg:$P_RC,$P_Not_In_Str
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
	jmp	short $P_Sim_Exit

$P_Sim_Found:
	mov	ah,es:[di-1]		;AN000; set item_tag
	mov	al,$P_List_Idx
	mov	dx,es:[di]		;AN000; get address of STRING
	jmp	short $P_Sim_Exit0
ENDIF					;AN000;(of Val3SW+KeySW)
$P_Sim01:
	mov	psdata_seg:$P_RC,$P_Syntax
	mov	ah,$P_No_Tag		;AN000; No ITEM_TAG set
$P_Sim_Exit:
	mov	al,$P_String		;AN000; Set type
$P_Sim_Exit0:
	call	$P_Fill_Result
	pop	di
	pop	dx
	pop	bx
	pop	ax
	ret
$P_Simple_String endp
PAGE
;***********************************************************************
; $P_String_Comp:
;
; Function:  Compare two string
;
; Input:     psdata_seg:SI -> 1st string
;	     ES:BP -> 2nd string  (Must be upper case)
;	     ES:BX -> CONTROL block
;
; Output:    CY = 1 if not match
;
; Use:	$P_Chk_DBCS, $P_Do_CAPS_Char
;
; Vars: $P_KEYor_SW_Ptr(W), $P_Flags(R). $P_KEYorSW_Ptr
;***********************************************************************
$P_String_Comp proc
	push	ax
	push	bp
	push	dx
	push	si
	mov	dl,$P_DOSTBL_Char	;AN000; use character case map table
$P_SCOM_Loop:
	mov	al,psdata_seg:[si]	;AN000; get command character
	call	$P_Chk_DBCS		;AN000; DBCS ?
	jc	$P_SCOM00		;AN000; yes,DBCS

	call	$P_Do_CAPS_Char 	;AN000; else, upper case map before comparison
IF	KeySW+SwSW			;AN000;(Check if keyword or switch is supported)
	test	psdata_seg:$P_Flags2,$P_Key_Cmp ;AC034; keyword search ?
	je	$P_SCOM04

	cmp	al,$P_Keyword		;AN000; "=" is delimiter
	jne	$P_SCOM03		;AN000;IF "=" on command line AND  (bp+1=> char after the "=" in synonym list)

	cmp	byte ptr es:[bp+1],$P_NULL ;AN021;   at end of keyword string in the control block THEN
	jne	$P_SCOM_DIFFER

	jmp	short $P_SCOM05 	;AN000;   keyword found in synonym list

$P_SCOM04:
	test	psdata_seg:$P_Flags2,$P_SW_Cmp ;AC034; switch search ?
	je	$P_SCOM03

	cmp	al,$P_Colon		;AN000; ":" is delimiter, at end of switch on command line
	jne	$P_SCOM03		;AN000; continue compares

	cmp	byte ptr es:[bp],$P_NULL ;AN021; IF at end of switch on command AND
	jne	$P_SCOM_DIFFER		;AN021;   at end of switch string in the control block THEN

$P_SCOM05:				;AN000;   found a match
	inc	si			;AN000; si points to just after "=" or ":"
	jmp	short $P_SCOM_Same	;AN000; exit

$P_SCOM03:
ENDIF					;AN000;(of KeySW+SwSW)
	cmp	al,es:[bp]		;AN000; compare operand w/ a synonym
	jne	$P_SCOM_Differ0 	;AN000; if different, check ignore colon option

	or	al,al			;AN000; end of line
	je	$P_SCOM_Same		;AN000; if so, exit

	inc	si			;AN000; update operand pointer
	inc	bp			;AN000; 	   and synonym pointer
	jmp	short $P_SCOM01 	;AN000; loop until NULL or "=" or ":" found in case

$P_SCOM00:				;AN000; Here al is DBCS leading byte
	cmp	al,es:[bp]		;AN000; compare leading byte
	jne	$P_SCOM_Differ		;AN000; if not match, say different

	inc	si			;AN000; else, load next byte
	mov	al,psdata_seg:[si]	;AN000; and
	inc	bp
	cmp	al,es:[bp]		;AN000; compare 2nd byte
	jne	$P_SCOM_Differ		;AN000; if not match, say different, too

	inc	si			;AN000; else update operand pointer
	inc	bp			;AN000; 		and synonym pointer
$P_SCOM01:
	jmp	short $P_SCOM_Loop	;AN000; loop until NULL or "=" or "/" found in case

$P_SCOM_Differ0:

IF	SwSW				;AN000;(tm10)
	test	psdata_seg:$P_Flags2,$P_SW ;AC034;(tm10)
	je	$P_not_applicable	;AN000;(tm10)

	test	es:[bx].$P_Function_Flag,$P_colon_is_not_necessary ;AN000;(tm10)
	je	$P_not_applicable	;AN000;(tm10)

	cmp	byte ptr es:[bp],$P_NULL ;AN000;(tm10)
;(deleted ;AN025;) jne $P_not_applicable ;AN000;(tm10)
	je	$P_SCOM_Same		;AN025;(tm10)

$P_not_applicable:			;AN000;(tm10)
ENDIF					;AN000;(tm10)

	test	es:[bx].$P_Match_Flag,$P_Ig_Colon ;AN000; ignore colon option specified ?
	je	$P_SCOM_Differ		;AN000; if no, say different.

	cmp	al,$P_Colon		;AN000; End up with ":" and
	jne	$P_SCOM02		;AN000;    subseqently

	cmp	byte ptr es:[bp],$P_NULL ;AN000;       NULL ?
	jne	$P_SCOM_Differ		;AN000; if no, say different

	jmp	short $p_SCOM_Same	;AN000; else, say same

$P_SCOM02:
	cmp	al,$P_NULL		;AN000; end up NULL and :
	jne	$P_SCOM_Differ

	cmp	byte ptr es:[bp],$P_Colon ;AN000; if no, say different
	je	$p_SCOM_Same		;AN000; else, say same

$P_SCOM_Differ:
	stc				;AN000; indicate not found
	jmp	short $P_SCOM_Exit

$P_SCOM_Same:
	mov	psdata_seg:$P_KEYorSW_Ptr,si ;AC034; for later use by keyword or switch
	clc				;AN000; indicate found
$P_SCOM_Exit:
	pop	si
	pop	dx
	pop	bp
	pop	ax
	ret
$P_String_Comp endp
PAGE
;***********************************************************************
IF	DateSW				;AN000;(Check if date format is supported)
; $P_Date_Format
;
; Function:  Convert a date string to DOS date format for int 21h
;	     with format validation.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Set_CDI, $P_Get_DecNum
;
; Vars: $P_RC(W), $P_1st_Val(RW), $P_2nd_Val(RW), $P_3rd_Val(RW)
;***********************************************************************
$P_Date_Format proc
	push	ax
	push	cx
	push	dx
	push	si
	push	bx
	push	si
	call	$P_Set_CDI		;AN000; set country dependent information before process
;	mov	bl,psdata_seg:[si].$P_CDI_DateS ;load date separator ;AN020; (deleted)
;					note: the country info is still needed
;					to determine the order of the fields,
;					but the separator char is no longer used.
	pop	si
	mov	psdata_seg:$P_1st_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_2nd_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_3rd_Val,0 ;AC034; set initial value
	call	$P_Get_DecNum		;AN000; get 1st number
	jc	$P_DateF_Err0		;AN000;-----------------------+

	mov	psdata_seg:$P_1st_Val,ax ;AC034;	      |
	or	bl,bl			;AN000; end of line ?	      |
	je	$P_DateF_YMD		;AN000; 		      |

	call	$P_Get_DecNum		;AN000; get 2nd number	      |
	jc	$P_DateF_Error		;AN000; 		      |

	mov	psdata_seg:$P_2nd_Val,ax ;AC034;	      |
	or	bl,bl			;AN000; end of line ?	      |
	je	$P_DateF_YMD		;AN000; 		      |

	call	$P_Get_DecNum		;AN000; get 3rd number	      |
$P_DateF_Err0:				;AN000; Bridge	  <-----------+
	jc	$P_DateF_Error

	mov	psdata_seg:$P_3rd_Val,ax
	or	bl,bl			;AN000; end of line ?
	jne	$P_DateF_Error

$P_DateF_YMD:
	mov	bx,psdata_seg:$P_Country_Info.$P_CDI_DateF ;AC034; get date format
	cmp	bx,$P_Date_YMD
	je	$P_DateF00

	mov	ax,psdata_seg:$P_1st_Val
	or	ah,ah
	jne	$P_DateF_Error

	mov	cl,al			;AN000; set month
	mov	ax,psdata_seg:$P_2nd_Val
	or	ah,ah			;AN000; if overflow, error.
	jne	$P_DateF_Error

	mov	ch,al			;AN000; set date
	mov	dx,psdata_seg:$P_3rd_Val ;AC034; set year
	cmp	bx,$P_Date_DMY		;AN000; from here format = MDY
	jne	$P_DateF01		;AN000; if it is DMY

	xchg	ch,cl			;AN000;  then swap M <-> D
$P_DateF01:
	jmp	short $P_DateF02

$P_DateF00:				;AN000; / here format = YMD
	mov	dx,psdata_seg:$P_1st_Val ;AC034; set year
	mov	ax,psdata_seg:$P_2nd_Val
	or	ah,ah			;AN000; if overflow, error
	jne	$P_DateF_Error

	mov	cl,al			;AN000; set month
	mov	ax,psdata_seg:$P_3rd_Val
	or	ah,ah			;AN000; if overflow, error
	jne	$P_DateF_Error

	mov	ch,al			;AN000; set date
$P_DateF02:
	cmp	dx,100			;AN000; year is less that 100 ?
	jae	$P_DateF03

	add	dx,1900 		;AN000; set year 19xx
$P_DateF03:
	pop	bx			;AN000; recover CONTROL block
	pop	si			;AN000; recover string pointer
	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_Date_F		;AN000;     result
	call	$P_Fill_Result		;AN000; 	   buffer
	jmp	short $P_Date_Format_Exit ;AN000;	to Date

$P_DateF_Error:
	pop	bx			;AN000; recover CONTROL block
	pop	si			;AN000; recover string pointer
	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_String		;AN000;     result
	call	$P_Fill_Result		;AN000; 	   buffer  to string
	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; indicate syntax error
$P_Date_Format_Exit:
	pop	dx
	pop	cx
	pop	ax
	ret
$P_Date_Format endp
ENDIF					;AN000;(of DateSW)
PAGE
;***********************************************************************
IF	TimeSW+DateSW			;AN000;(Check if time or date format is supported)
; $P_Set_CDI:
;
; Function: Read CDI from DOS if it has not been read yet
;
; Input:    None
;
; Output:   psdata_seg:SI -> CDI
;
; Use:	INT 21h w/ AH = 38h
;***********************************************************************
$P_Set_CDI proc
	lea	si,psdata_seg:$P_Country_Info
	cmp	psdata_seg:[si].$P_CDI_DateF,$P_NeedToBeRead ;AN000; already read ?
	je	$P_Read_CDI

	jmp	short $P_Set_CDI_Exit	;AN000; then do nothing

$P_Read_CDI:				;AN000; else read CDI thru DOS
	push	ds
	push	dx
	push	ax
	push	PSDATA_SEG
	pop	ds			;AN000; set segment register
	mov	ax,$P_DOS_Get_CDI	;AN000; get country information
	mov	dx,si			;AN000; set offset of CDI in local data area
	int	21h
	pop	ax
	pop	dx
	pop	ds
$P_Set_CDI_Exit:
	ret
$P_Set_CDI endp
PAGE
;***********************************************************************
; $P_Get_DecNum:
;
; Function:  Read a chcrater code from psdata_seg:SI until specified delimiter
;	     or NULL encountered. And make a decimal number.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    BL = delimiter code or NULL
;	     AX = Decimal number
;	     SI advanced to the next number
;	     CY = 1 : Syntax error, AL = Latest examineed number
;
; Use:	$P_0099
;***********************************************************************
$P_Get_DecNum proc
	push	cx
	push	dx
	xor	cx,cx			;AN000; cx will have final value
$P_GetNum_Loop:
	mov	al,psdata_seg:[si]	;AN000; load character
	or	al,al			;AN000; end of line ?
	je	$P_GetNum00		;AN000; if yes, exit

	cmp	psdata_seg:$P_Got_Time,0 ;AC034; ;is this numeric in a time field?
	je	$P_Do_Date_Delims	;AN000;no, go check out Date delimiters

; Determine which delimiter(s) to check for.  Colon & period  or period only
	cmp	bl,$P_colon_period	;AN032; ;Time
	jne	$P_Do_Time_Delim1	;AN032; ;only check for period

	cmp	al,$P_Colon		;AN032; ;Is this a valid delimiter ?
	je	$P_GetNum01		;AN032; ;yes, exit

$P_Do_Time_Delim1:
	cmp	al,$P_Period		;;AC032;;AC023;Is this a valid delimiter ?
	je	$P_GetNum01		;AC023; yes, exit

	jmp	short $P_Neither_Delims

$P_Do_Date_Delims:
;Regardless of the date delimiter character specified in the country
;dependent information, check for the presence of any one of these
;three field delimiters: "-", "/", or ".".
	cmp	al,$P_Minus		;AN020;is this a date delimiter character?
	je	$P_GetNum01		;AN020;if yes, exit

	cmp	al,$P_Slash		;AN020;is this a date delimiter character?
	je	$P_GetNum01		;AN020;if yes, exit

	cmp	al,$P_Period		;AN020;is this a date delimiter character?
	je	$P_GetNum01		;AN000; if yes, exit

$P_Neither_Delims:

	call	$P_0099 		;AN000; convert it to binary
	jc	$P_GetNum_Exit		;AN000; if error exit

	mov	ah,0
	xchg	ax,cx
	mov	dx,10
	mul	dx			;AN000; ax = ax * 10
	or	dx,dx			;AN000; overflow
	jne	$P_GetNum02		;AN000; then exit

	add	ax,cx
	jc	$P_GetNum_Exit

	xchg	ax,cx
	inc	si
	jmp	short $P_GetNum_Loop

$P_GetNum00:
	mov	bl,al			;AN000; set bl to NULL
	clc				;AN000; indicate no error
	jmp	short $P_GetNum_Exit

$P_GetNum01:
	inc	si			;AN000; si points to next number
	clc				;AN000; indicate no error
	jmp	short $P_GetNum_Exit

$P_GetNum02:
	stc				;AN000; indicate error
$P_GetNum_Exit:
	mov	ax,cx			;AN000;return value
	pop	dx
	pop	cx
	ret
$P_Get_DecNum endp
ENDIF					;AN000;(of TimeSW+DateSW)
PAGE
;***********************************************************************
IF	TimeSW				;AN000;(Check if time format is supported)
; $P_Time_Format
;
; Function:  Convert a time string to DOS time format for int 21h
;	     with format validation.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Set_CDI, $P_Get_DecNum, $P_Time_2412
;
; Vars: $P_RC(W), $P_Flags(R), $P_1st_Val(RW), $P_2nd_Val(RW)
;	$P_3rd_Val(RW), $P_4th_Val(RW)
;***********************************************************************
$P_Time_Format proc
	push	ax
	push	cx
	push	dx
	push	si
	push	bx
	push	si
	call	$P_Set_CDI		;AN000; Set country independent
					; information before process
;(AN032; deleted)  mov	   bl,psdata_seg:[si].$P_CDI_TimeS ;load time separator
;(AN032; deleted)  mov	   bh,psdata_seg:[si].$P_CDI_Dec ;load decimal separator
	test	byte ptr psdata_seg:[si].$P_CDI_TimeF,1 ;AN000; 24 hour system
	pop	si
	jne	$P_TimeF00		;AN000; if no, means 12 hour system

	call	$P_Time_2412		;AN000; this routine handle "am" "pm"
$P_TimeF00:
	mov	psdata_seg:$P_1st_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_2nd_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_3rd_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_4th_Val,0 ;AC034; set initial value
	mov	psdata_seg:$P_Got_Time,1 ;AN023;AC034;; use time delimiter
	mov	bl,$P_colon_period	;AN032; flag, indicates use of
					; delimiters between hours,
					;  minutes,seconds
	call	$P_Get_DecNum		;AN000; get 1st number
	jc	$P_TimeF_Err0

	mov	psdata_seg:$P_1st_Val,ax
	or	bl,bl			;AN000; end of line ?
	je	$P_TimeF_Rlt

	call	$P_Get_DecNum		;AN000; get 2nd number
	jc	$P_TimeF_Err0		;AC038; if OK

	mov	psdata_seg:$P_2nd_Val,ax
	or	bl,bl			;AN000; end of line ?
	je	$P_TimeF_Rlt

;(;AN032; deleted) mov	   bl,bh		   ;set decimal separator
	mov	bl,$P_period_only	;AN032; flag, which to decimal separator
	call	$P_Get_DecNum		;AN000; get 3rd number
	jc	$P_TimeF_Err0		;AC039; if problem, bridge to error

	mov	psdata_seg:$P_3rd_Val,ax
	or	bl,bl			;AN000; end of line ?
;(DELETED ;AN039;)  je $P_TimeF_Rlt
	jne	$P_Time_4		;AN039; NOT END OF LINE,
					;AN039;   GO TO 4TH NUMBER
	test	psdata_seg:$P_Flags1,$P_Time_Again ;AN039; HAS TIME PARSE
					;AN039;    BEEN REPEATED?
	jnz	$P_TimeF_Rlt		;AN039; yes, this is really
					;AN039;   the end of line
					;AN039; no, time has not been repeated
	mov	si,psdata_seg:$P_SI_Save ;AN039; get where parser quit
					 ;AN039;   in command line
	cmp	byte ptr [si-1],$P_Comma ;AN039; look at delimiter
					;AN039;   from command line
	jne	$P_TimeF_Rlt		;AN039; was not a comma, this is
					;AN039;  really end of line
					;AN039; is comma before hundredths,
					;AN039;   redo TIME
	mov	byte ptr [si-1],$P_Period ;AN039; change that ambiguous
					;AN039;    comma to a decimal point
					;AN039;     parse can understand
	mov	psdata_seg:$P_Flags,0	;AN039; Clear all internal flags
	or	psdata_seg:$P_Flags1,$P_Time_Again ;AN039; indicate TIME
					;AN039; is being repeated
	mov	cx,psdata_seg:$P_ORIG_ORD ;AN039; ORIGINAL ORDINAL FROM CX
	mov	sp,psdata_seg:$P_ORIG_STACK ;AN039; ORIGINAL VALUE
					 ;AN039;   OF STACK FROM SP
	mov	si,psdata_seg:$P_ORIG_SI ;AN039; ORIGINAL START
					 ;AN039;   PARSE POINTER FROM SI
	jmp	$P_Redo_Time		;AN039; go try TIME again
; ===============================================================
$P_Time_4:				;AN039; READY FOR 4TH (HUNDREDTHS) NUMBER
	call	$P_Get_DecNum		;AN000; get 4th number
$P_TimeF_Err0:				;AN000; Bridge
	jc	$P_TimeF_Error

	mov	psdata_seg:$P_4th_Val,ax
	or	bl,bl			;AN000; After hundredth, no data allowed
	jne	$P_TimeF_Error		;AN000; if some, then error

$P_TimeF_RLT:
	mov	ax,psdata_seg:$P_1st_Val
	or	ah,ah			;AN000; if overflow then error
	jne	$P_TimeF_Err

	test	psdata_seg:$P_Flags1,$P_Time12am ;AN038;if "am" specified
	jz	$P_Time_notAM		;AN038;skip if no "AM" specified
					;since "AM" was specified,
	cmp	al,12			;AN038: if hour specified as later than noon
	ja	$P_TimeF_Err		;AN038; error if "AM" on more than noon
	jne	$P_Time_notAM		;AN038; for noon exactly,

	xor	al,al			;AN038; set hour = zero
$P_Time_notAM:
	test	psdata_seg:$P_Flags2,$P_Time12 ;AC034; if 12 hour system and pm is specified
	je	$P_TimeSkip00		;AN000; then

	cmp	al,12			;AN038; if 12:00 o'clock already
	je	$P_TimeSkip00		;AN038; it is PM already

	add	al,12			;AN000; add 12 hours to make it afternoon
	jc	$P_TimeF_Err		;AN000; if overflow then error

	cmp	al,24			;AN038; after adding 12, now cannot be >24
	ja	$P_TimeF_Err		;AN038; if too big, error

$P_TimeSkip00:
	mov	dl,al			;AN000; set hour
	mov	ax,psdata_seg:$P_2nd_Val
	or	ah,ah			;AN000; if overflow then error
	jne	$P_TimeF_Err

	mov	dh,al			;AN000; set minute
	mov	ax,psdata_seg:$P_3rd_Val
	or	ah,ah			;AN000; if overflow then error
	jne	$P_TimeF_Err

	mov	cl,al			;AN000; set second
	mov	ax,psdata_seg:$P_4th_Val
	or	ah,ah			;AN000; if overflow then error
	jne	$P_TimeF_Err

	mov	ch,al			;AN000; set hundredth
	pop	bx			;AN000; recover CONTROL block
	pop	si			;AN000; recover string pointer
	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_Time_F		;AN000;    result
	call	$P_Fill_Result		;AN000; 	 buffer
	jmp	short $P_Time_Format_Exit ;AN000;    to time

$P_TimeF_Error:
$P_TimeF_Err:
	pop	bx			;AN000; recover CONTROL block
	pop	si			;AN000; recover string pointer
	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_String		;AN000;     result
	call	$P_Fill_Result		;AN000; 	  buffer to string
	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; return syntax error
$P_Time_Format_Exit:
	mov	psdata_seg:$P_Got_Time,0 ;AN023;AC034;; finished with this time field
	pop	dx
	pop	cx
	pop	ax
	ret
$P_Time_Format endp
PAGE
;***********************************************************************
; $P_Time_2412:
;
; Function:  Remove "a", "p", "am", or "pm" from the end of stinrg
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;
; Output:    Set $P_Time12 flag when the string is terminated by "p"
;	     or "pm"
;
; Vars:  $P_Flags(W)
;***********************************************************************
$P_Time_2412 proc
	push	ax
	push	si
$P_T12_Loop:
	mov	al,psdata_seg:[si]	;AN000; Move
	inc	si			;AN000;     si
	or	al,al			;AN000;       to
	jne	$P_T12_Loop		;AN000; 	end of string

	mov	al,psdata_seg:[si-word] ;AN000; get char just before NULL
	or	al,$P_Make_Lower	;AN000; lower case map
	cmp	al,"p"                  ;AN000; only "p" of "pm" ?
	je	$P_T1200

	cmp	al,"a"                  ;AN000; only "a" of "am" ?
	je	$P_T1201

	cmp	al,"m"                  ;AN000; "m" of "am" or "pm"
	jne	$P_T12_Exit

	dec	si
	mov	al,psdata_seg:[si-word]
	or	al,$P_Make_lower	;AN000; lower case map
	cmp	al,"p"                  ;AN000; "p" of "pm" ?
	je	$P_T1200

	cmp	al,"a"                  ;AN000; "a" of "am" ?
	je	$P_T1201		;AN000; go process "a"

	jmp	short $P_T12_Exit	;AN000; no special chars found

$P_T1200:				;AN000; "P" found
	or	psdata_seg:$P_Flags2,$P_Time12 ;AC034; flag "PM" found
	jmp	short $P_Tclr_chr	;AN038; go clear the special char

$P_T1201:				;AN000; "A" found
	or	psdata_seg:$P_Flags1,$P_Time12AM ;AN038; flag "AM" found
$P_Tclr_chr:
	mov	byte ptr psdata_seg:[si-2],$P_NULL ;AN000; null out special char
$P_T12_Exit:
	pop	si
	pop	ax
	ret
$P_Time_2412 endp
ENDIF					;AN000;(of TimeSW)
PAGE
;***********************************************************************
IF	CmpxSW				;AN000;(Check if complex item is supported)
; $P_Complex_Format:
;
; Function:  Check if the input string is valid complex format.
;	     And set the result buffer.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Chk_DBCS, $P_Chk_EOL, $P_Skip_Delim
;	$P_Quoted_str, $P_Chk_DSQuote
;
; Vars: $P_RC(W), $P_SI_Save(W), $P_SaveSI_Cmpx(R), $P_Save_EOB(R)
;***********************************************************************
$P_Complex_Format proc
	push	ax
	push	bx
	push	si
	mov	bx,psdata_seg:$P_SaveSI_Cmpx ;AC034; bx points to user buffer
	cmp	byte ptr [bx],$P_Lparen ;AN000; 1st char = left parentheses
	jne	$P_Cmpx_Err

	xor	ah,ah			;AN000; ah = parentheses counter
$P_Cmpx_Loop:
	mov	al,[bx] 		;AN000; load character from command buffer
	call	$P_Chk_EOL		;AN000; if it is one of EOL
	je	$P_CmpxErr0		;AN000; then error exit.

	cmp	al,$P_Lparen		;AN000; left parentheses ?
	jne	$P_Cmpx00		;AN000; then

	inc	ah			;AC035; add '1' to AH reg
					;AN000; increment parentheses counter
;(replaced ;AC035;) add     ah,1	;AN000; increment parentheses counter
	jc	$P_CmpxErr0		;AN000; if overflow, error
$P_Cmpx00:
	cmp	al,$P_Rparen		;AN000; right parentheses ?
	jne	$P_Cmpx01		;AN000; then

	dec	ah			;AC035; subtract '1' from AH reg
					;AN000; decrement parentheses counter
;(changed ;AC035;) sub	   ah,1 	;AN000; decrement parentheses counter
	jc	$P_CmpxErr0		;AN000; if overflow error

	je	$P_Cmpx03		;AN000; ok, valid complex

$P_Cmpx01:
;(deleted ;AN025;) call $P_Chk_DSQuote	;AN000; double or single quotation mark ? 3/17/KK
	cmp	al,$P_DQuote		;AN025; double quotation mark?
	jne	$P_Cmpx04		;AN000; 3/17/KK

	mov	psdata_seg:[si],al	;AN000; here quoted string is found in the complex list.
	inc	si
	inc	bx			;AN000; bx points to 2nd character
	call	$P_Quoted_Str		;AN000; skip pointers until closing of quoted string
	jc	$P_CmpxErr0		;AN000; if error in quoted string syntax then exit

	jmp	short $P_Cmpx05

$P_Cmpx04:
	call	$P_Chk_DBCS		;AN000; was it a lead byte of DBCS ?
	jnc	$P_Cmpx02

	mov	psdata_seg:[si],al	;AN000; then store 1st byte
	inc	si
	inc	bx
	mov	al,[bx] 		;AN000; load 2nd byte
$P_Cmpx02:
	mov	psdata_seg:[si],al	;AN000; store SBCS or 2nd byte of DBCS
$P_Cmpx05:
	inc	si
	inc	bx
	jmp	short $P_Cmpx_Loop	;AN000; loop
;----
$P_Cmpx03:
	mov	byte ptr psdata_seg:[si],al
	mov	byte ptr psdata_seg:[si+byte],$P_NULL
	mov	byte ptr [bx],$P_NULL	;AN000; replace right parentheses with NULL
	mov	si,bx			;AN000; skip whitespaces
	inc	si			;AN000;     after
	call	$P_Skip_Delim		;AN000;        right parentheses
	mov	psdata_seg:$P_SI_Save,si ;AC034; save next pointer, SI
	jmp	short $P_Cmpx_Exit

$P_CmpxErr0:
	mov	si,psdata_seg:$P_Save_EOB ;AC034; if EOF encountered, restore
	mov	byte ptr psdata_seg:[si],$P_NULL ;AN000; EOB mark
$P_Cmpx_Err:
	mov	psdata_seg:$P_RC,$P_Syntax
$P_Cmpx_Exit:
	mov	ah,$P_No_Tag
	mov	al,$P_Complex
	pop	si
	pop	bx
	call	$P_Fill_Result
	pop	ax
	ret
$P_Complex_Format endp
ENDIF					;AN000;(of CpmxSW)
PAGE
;***********************************************************************
IF	QusSW				;AN000;(Check if quoted string is supported)
; $P_Quoted_Format:
;
; Function:  Check if the input string is valid quoted string format.
;	     And set the result buffer.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Chk_DBCS, $P_Chk_EOL, $P_Skip_Delim
;	$P_Chk_DSQuote, $P_Quoted_Str
;
; Vars: $P_RC(W), $P_SI_Save(W), $P_SaveSI_Cmpx(R),$P_Save_EOB(R)
;***********************************************************************
$P_Quoted_Format proc
	push	ax
	push	bx
	push	si
	mov	bx,psdata_seg:$P_SaveSI_Cmpx ;AC034; bx points to user buffer
	mov	al,byte ptr [bx]	;AN000; get 1st character
;(deleted ;AN025;) call $P_Chk_DSQuote	;AN000; is it single or double quote ?
	cmp	al,$P_DQuote		;AN025; double quotation mark?
	jne	$P_Qus_Err		;AN000; if no, error

;	mov	psdata_seg:[si],al	;AN000; move it to internal buffer
;	inc	si
	inc	bx			;AN000; bx points to 2nd character
	call	$P_Quoted_Str		;AN000; skip pointers to the closing of quoted string
	jc	$P_Qus_Err0		;AN000; if invali quoted string syntax, exit

	mov	byte ptr psdata_seg:[si+byte],$P_NULL ;AN000; end up with NULL
	mov	si,bx
	inc	si
	call	$P_Skip_Delim		;AN000; skip whitespaces after closing quote
	mov	psdata_seg:$P_SI_Save,si ;AC034; save next pointer, SI
	jmp	short $P_Qus_Exit

$P_Qus_Err0:
	mov	si,psdata_seg:$P_Save_EOB ;AC034; if EOF encountered, restore
	mov	byte ptr psdata_seg:[si],$P_NULL ;AN000; EOB mark
$P_Qus_Err:
	mov	psdata_seg:$P_RC,$P_Syntax ;AC034; indicate syntax error
$P_Qus_Exit:
	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_Quoted_String	;AN000;    result
	pop	si			;AN000; 	 buffer
	pop	bx			;AN000; 	       to
	call	$P_Fill_Result		;AN000; 		 quoted string
	pop	ax
	ret
$P_Quoted_Format endp
ENDIF					;AN000;(of QusSW)
PAGE
;***********************************************************************
; $P_Chk_DSQuote;
;
; Function: Check if AL is double quotation or single quotation
;
; Input:    AL = byte to be examineed
;
; Output:   ZF on if AL is single or double quotetaion
;
; Vars:  $P_SorD_Quote(W)
;***********************************************************************
IF	QusSW+CmpxSW			;AN000;(Check if quoted string or complex item is supported)
;(deleted ;AN025;) $P_Chk_DSQuote proc			   ;
;(deleted ;AN025;)	   mov	   $P_SorD_Quote,$P_SQuote ; 3/17/87   assume single quote
;(deleted ;AN025;)	   cmp	   al,$P_DQuote 	   ; 1st char = double quotation ?
;(deleted ;AN025;)	   jne	   $P_CDSQ00		   ; 3/17/87
;(deleted ;AN025;)	   mov	   $P_SorD_Quote,al	   ; 3/17/87 set bigning w/ double quote
;(deleted ;AN025;)	   ret				   ; 3/17/87
;(deleted ;AN025;) $P_CDSQ00:				   ; 3/17/87
;(deleted ;AN025;)	   cmp	   al,$P_SQuote 	   ; 1st char = single quotation ?
;(deleted ;AN025;)	   ret				   ;
;(deleted ;AN025;) $P_Chk_DSQuote endp			   ;
    PAGE
;***********************************************************************
; $P_Quoted_Str:
;
; Function:  Copy chracacter from ES:BX to psdata_seg:SI until closing single
;	     (double) quotation found.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> Operand in command buffer
;
; Output:    CY on indicates EOF encounterd before closing quotation
;	     BX and SI
;
;
; Vars: $P_SorD_Quote(R)
;***********************************************************************
$P_Quoted_Str proc
	push	ax
$P_Qus_Loop:
	mov	ax,[bx] 		;AN000; 3/17/87
	call	$P_Chk_EOL
	je	$P_Qustr_Err0

;(deleted ;AN025;) cmp al,$P_SorD_Quote ;AN000; quotation ?   3/17/87
	cmp	al,$P_DQuote		;AN025; double quote?
	jne	$P_Qus00

;(deleted ;AN025;) cmp ah,$P_SorD_Quote ;AN000; contiguous quotation 3/17/87
	cmp	ah,$P_DQuote		;AN025; double quote?
	jne	$P_Qus02

;(deleted ;AN025:) mov word ptr psdata_seg:[si],ax ;AN000; 3/17/87
	mov	byte ptr psdata_seg:[si],al ;AN025; save one of the quotes
;(deleted ;AN025:) add si,2

	inc	si			;AC035; add '1' to SI reg
					;AN025; adjust target index
;(changed ;AC035;) add	   si,1 	;AN025; adjust target index
	inc	bx			;AC035; add '2' to
	inc	bx			;AC035;  BX reg
					;AN000; adjust source index by 2 to skip extra quote
;(changed ;AC035;) add	   bx,2 	;AN000; adjust source index by 2 to skip extra quote
	jmp	short $P_Qus_Loop

$P_Qus00:
	call	$P_Chk_DBCS		;AN000; was it a lead byte of DBCS ?
	jnc	$P_Qus01

	mov	psdata_seg:[si],al	;AN000; store 1st byte
	inc	si
	inc	bx
	mov	al,[bx] 		;AN000; load 2nd byte
$P_Qus01:
	mov	psdata_seg:[si],al	;AN000; store SBCS or 2nd byte of DBCS
	inc	si
	inc	bx
	jmp	short $P_Qus_Loop

$P_Qustr_Err0:
	stc				;AN000; indicate error
	jmp	short $P_Quoted_Str_Exit

$P_Qus02:
	mov	byte ptr psdata_seg:[si],0
	clc				;AN000; indicate no error
$P_Quoted_Str_Exit:
	pop	ax
	ret
$P_Quoted_Str endp
ENDIF					;AN000;(of QusSW+CmpxSW)
PAGE
;***********************************************************************
IF	FileSW+DrvSW			;AN000;(Check if file spec or drive only is supported)
; $P_File_Format;
;
; Function:  Check if the input string is valid file spec format.
;	     And set the result buffer.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Chk_DBCS, $P_FileSp_Chk
;
; Vars: $P_RC(W), $P_SI_Save(W), $P_Terminator(W), $P_SaveSI_Cmpx(R)
;	$P_SaveSI_Cmpx(R)
;***********************************************************************
$P_File_Format proc
	push	ax
	push	di
	push	si
	mov	di,psdata_seg:$P_SaveSI_cmpx ;AC034; get user buffer address
$P_FileF_Loop0: 			;AN000; / skip special characters
	mov	al,psdata_seg:[si]	;AN000; load character
	or	al,al			;AN000; end of line ?
	je	$P_FileF_Err		;AN000; if yes, error exit

	call	$P_FileSp_Chk		;AN000; else, check if file special character
	jne	$P_FileF03		;AN000; if yes,

;AN033; deleted   inc	  di			  ;skip
;AN033; deleted   inc	  si			  ;   the
;AN033; deleted   jmp	  short $P_FileF_Loop0	  ;	  character
	mov	psdata_seg:$P_err_flag,$P_error_filespec ;AN033;AC034;; set error flag- bad char.
	pop	si
	mov	byte ptr psdata_seg:[si],$P_NULL
	pop	di
	jmp	short $P_FileF02


$P_FileF_Err:
	pop	si
	mov	byte ptr psdata_seg:[si],$P_NULL
;(deleted ;AN030;) mov di,$P_SaveSI_cmpx ;AN000; get user buffer address
;(deleted ;AN030;) mov $P_SI_Save,di	 ;AN000; update pointer to user buffer
	pop	di
	test	es:[bx].$P_Match_Flag,$P_Optional ;AN000; is it optional ?
	jne	$P_FileF02

	mov	psdata_seg:$P_RC,$P_Op_Missing ;AC034; 3/17/87
	jmp	short $P_FileF02

$P_FileF03:
	pop	ax			;AN000; discard save si
	push	si			;AN000; save new si
$P_FileF_Loop1:
	mov	al,psdata_seg:[si]	;AN000; load character (not special char)
	or	al,al			;AN000; end of line ?
	je	$P_FileF_RLT

	call	$P_FileSp_Chk		;AN000; File special character ?
	je	$P_FileF00

	call	$P_Chk_DBCS		;AN000; no, then DBCS ?
	jnc	$P_FileF01
	inc	di			;AN000; if yes, skip next byte
	inc	si
$P_FileF01:
	inc	di
	inc	si
	jmp	short $P_FileF_Loop1
;
$P_FileF00:
	mov	psdata_seg:$P_Terminator,al
	mov	byte ptr psdata_seg:[si],$P_NULL ;AN000; update end of string
	inc	di
	mov	psdata_seg:$P_SI_Save,di ;AC034; update next pointer in command line
$P_FileF_RLT:
	pop	si
	pop	di
$P_FileF02:

	pop	ax			;AN000; (tm14)
	test	ax,$P_File_Spc		;AN000; (tm14)
	je	$P_Drv_Only_Exit	;AN000; (tm14)

	push	ax			;AN000;  (tm14)

	mov	ah,$P_No_Tag		;AN000; set
	mov	al,$P_File_Spec 	;AN000;    result
	call	$P_Fill_Result		;AN000; 	 buffer to file spec
	pop	ax

$P_Drv_Only_Exit:			;AN000; (tm14)

	ret
$P_File_Format endp
PAGE
;***********************************************************************
; $P_FileSp_Chk
;
; Function:  Check if the input byte is one of file special characters
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     AL = character code to be examineed
;
; Output:    ZF = 1 , AL is one of special characters
;***********************************************************************
$P_FileSp_Chk proc
	push	bx
	push	cx
	lea	bx,psdata_seg:$P_FileSp_Char ;AC034; special character table
	mov	cx,$P_FileSp_Len	;AN000; load length of it
$P_FileSp_Loop:
	cmp	al,psdata_seg:[bx]	;AN000; is it one of special character ?
	je	$P_FileSp_Exit

	inc	bx
	loop	$P_FileSp_Loop

	inc	cx			;AN000; reset ZF
$P_FileSp_Exit:
	pop	cx
	pop	bx
	ret
$P_FileSp_Chk endp
ENDIF					;AN000;(of FileSW+DrvSW)
PAGE
;***********************************************************************
IF	DrvSW				;AN000;(Check if drive only is supported)
; $P_Drive_Format;
;
; Function:  Check if the input string is valid drive only format.
;	     And set the result buffer.
;
; Input:     psdata_seg:SI -> $P_STRING_BUF
;	     ES:BX -> CONTROL block
;
; Output:    None
;
; Use:	$P_Fill_Result, $P_Chk_DBCS
;
; Vars: $P_RC(W)
;***********************************************************************
$P_Drive_Format proc
	push	ax
	push	dx
	mov	al,psdata_seg:[si]
	or	al,al			;AN000; if null string
	je	$P_Drv_Exit		;AN000; do nothing

	call	$P_Chk_DBCS		;AN000; is it leading byte ?
	jc	$P_Drv_Err

	cmp	word ptr psdata_seg:[si+byte],$P_Colon ;AN000; "d", ":", 0  ?
	je	$P_DrvF00

	test	es:[bx].$P_Match_Flag,$P_Ig_Colon ;AN000; colon can be ignored?
	je	$P_Drv_Err

	cmp	byte ptr psdata_seg:[si+byte],$P_NULL ;AN000; "d", 0  ?
	jne	$P_Drv_Err

$P_DrvF00:
	or	al,$P_Make_Lower	;AN000; lower case
	cmp	al,"a"                  ;AN000; drive letter must
	jb	$P_Drv_Err		;AN000; in range of

	cmp	al,"z"                  ;AN000; "a" - "z"
	ja	$P_Drv_Err		;AN000; if no, error

	sub	al,"a"-1                ;AN000; make text drive to binary drive
	mov	dl,al			;AN000; set
	mov	ah,$P_No_Tag		;AN000;    result
	mov	al,$P_Drive		;AN000; 	 buffer
	call	$P_Fill_Result		;AN000; 	       to drive
	jmp	short $P_Drv_Exit

$P_Drv_Err:
	mov	psdata_seg:$P_RC,$P_Syntax
$P_Drv_Exit:
	pop	dx
	pop	ax
	ret
$P_Drive_Format endp
ENDIF					;AN000;(of DrvSW)
PAGE
;***********************************************************************
; $P_Skip_Delim;
;
; Function: Skip delimiters specified in the PARMS list, white space
;	    and comma.
;
; Input:    DS:SI -> Command String
;	    ES:DI -> Parameter List
;
; Output:   CY = 1 if the end of line encounterd
;	    CY = 0 then SI move to 1st non-delimiter character
;	    AL = Last examineed character
;
; Use:	    $P_Chk_EOL, $P_Chk_Delim,
;
; Vars:     $P_Flags(R)
;***********************************************************************
$P_Skip_Delim proc
$P_Skip_Delim_Loop:
	LODSB
	call	$P_Chk_EOL		;AN000; is it EOL character ?
	je	$P_Skip_Delim_CY	;AN000; if yes, exit w/ CY on

	call	$P_Chk_Delim		;AN000; is it one of delimiters ?
	jne	$P_Skip_Delim_NCY	;AN000; if no, exit w/ CY off

	test	psdata_seg:$P_Flags2,$P_Extra ;AC034; extra delim or comma found ?
	je	$P_Skip_Delim_Loop	;AN000; if no, loop

	test	psdata_seg:$P_Flags2,$P_SW+$P_equ ;AC034; /x , or xxx=zzz , (tm08)
	je	short $P_Exit_At_Extra	;AN000; no switch, no keyword (tm08)

	dec	si			;AN000; backup si for next call (tm08)
	jmp	short $P_Exit_At_Extra	;AN000; else exit w/ CY off

$P_Skip_Delim_CY:
	stc				;AN000; indicate EOL
	jmp	short $P_Skip_Delim_Exit

$P_Skip_Delim_NCY:
	clc				;AN000; indicate non delim
$P_Skip_Delim_Exit:			;AN000; in this case, need
	dec	si			;AN000;  backup index pointer
	ret

$P_Exit_At_Extra:
	clc				;AN000; indicate extra delim
	ret
$P_Skip_Delim endp
PAGE
;***********************************************************************
; $P_Chk_EOL;
;
; Function: Check if AL is one of End of Line characters.
;
; Input:    AL = character code
;	    ES:DI -> Parameter List
;
; Output:   ZF = 1 if one of End of Line characters
;**********************************************************************
$P_Chk_EOL proc
	push	bx
	push	cx
	cmp	al,$P_CR		;AN000; Carriage return ?
	je	$P_Chk_EOL_Exit

	cmp	al,$P_NULL		;AN000; zero ?
	je	$P_Chk_EOL_Exit

IF LFEOLSW				;AN028; IF LF TO BE ACCEPTED AS EOL
	cmp	al,$P_LF		;AN000; Line feed ?
	je	$P_Chk_EOL_Exit
ENDIF

	cmp	byte ptr es:[di].$P_Num_Extra,$P_I_Have_EOL ;AN000; EOL character specified ?
	jb	$P_Chk_EOL_Exit

	xor	bx,bx
	mov	bl,es:[di].$P_Len_Extra_Delim ;AN000; get length of delimiter list
	add	bx,$P_Len_PARMS 	;AN000; skip it
	cmp	byte ptr es:[bx+di],$P_I_Use_Default ;AN000; No extra EOL character ?
	je	$P_Chk_EOL_NZ

	xor	cx,cx			;AN000; Get number of extra chcracter
	mov	cl,es:[bx+di]
$P_Chk_EOL_Loop:
	inc	bx
	cmp	al,es:[bx+di]		;AN000; Check extra EOL character
	je	$P_Chk_EOL_Exit

	loop	$P_Chk_EOL_Loop

$P_Chk_EOL_NZ:
	cmp	al,$P_CR		;AN000; reset ZF
$P_Chk_EOL_Exit:
	pop	cx
	pop	bx
	ret
$P_Chk_EOL endp
PAGE
;***********************************************************************
; $P_Chk_Delim;
;
; Function: Check if AL is one of delimiter characters.
;	    if AL+[si] is DBCS blank, it is replaced with two SBCS
;	    blanks.
;
; Input:    AL = character code
;	    DS:SI -> Next Character
;	    ES:DI -> Parameter List
;
; Output:   ZF = 1 if one of delimiter characters
;	    SI points to the next character
; Vars:  $P_Terminator(W), $P_Flags(W)
;***********************************************************************
$P_Chk_Delim proc
	push	bx
	push	cx
	mov	psdata_seg:$P_Terminator,$P_Space   ;AC034; Assume terminated by space
	and	psdata_seg:$P_Flags2,0ffh-$P_Extra
	cmp	al,$P_Space		;AN000; Space ?
	je	$P_Chk_Delim_Exit

	cmp	al,$P_TAB		;AN000; TAB ?
	je	$P_Chk_Delim_Exit

	cmp	al,$P_Comma		;AN000; Comma ?
	je	$P_Chk_Delim_Exit0

$P_Chk_Delim00:
	cmp	al,$P_DBSP1		;AN000; 1st byte of DBCS Space ?
	jne	$P_Chk_Delim01

	cmp	byte ptr [si],$P_DBSP2	;AN000; 2nd byte of DBCS Space ?
	jne	$P_Chk_Delim01

	mov	al,$P_Space
	inc	si			;AN000; make si point to next character
	cmp	al,al			;AN000; Set ZF
	jmp	short $P_Chk_Delim_Exit

$P_Chk_Delim01:
	cmp	byte ptr es:[di].$P_Num_Extra,$P_I_Have_Delim ;AN000; delimiter character specified ?
	jb	$P_Chk_Delim_Exit

	xor	cx,cx
	mov	cl,es:[di].$P_Len_Extra_Delim ;AN000; get length of delimiter list
	or	cx,cx			;AN000; No extra Delim character ?
	je	$P_Chk_Delim_NZ

	mov	bx,$P_Len_PARMS-1	;AN000; set bx to 1st extra delimiter
$P_Chk_Delim_Loop:
	inc	bx
	cmp	al,es:[bx+di]		;AN000; Check extra Delim character
	je	$P_Chk_Delim_Exit0

	loop	$P_Chk_Delim_Loop	;AN000; examine all extra delimiter

$P_Chk_Delim_NZ:
	cmp	al,$P_Space		;AN000; reset ZF
$P_Chk_Delim_Exit:
;;;;	jne	$P_ChkDfin
;;;;	mov	psdata_seg:$P_Terminator,al
$P_ChkDfin:
	pop	cx
	pop	bx
	ret

$P_Chk_Delim_Exit0:
	mov	psdata_seg:$P_Terminator,al ;AC034; keep terminated delimiter
	test	psdata_seg:$P_Flags2,$P_Equ  ;AN027;AC034;; if terminating a key=
	jnz	$P_No_Set_Extra 	;AN027; then do not set the EXTRA bit

	or	psdata_seg:$P_Flags2,$P_Extra ;AC034; flag terminated extra delimiter or comma
$P_No_Set_Extra:
	cmp	al,al			;AN000; set ZF
	jmp	short $P_Chk_Delim_Exit

$P_Chk_Delim endp
PAGE
;***********************************************************************
; $P_Chk_Switch;
;
; Function: Check if AL is the switch character not in first position of
;	    $P_STRING_BUF
;
; Input:    AL = character code
;	    BX = current pointer within $P_String_Buf
;	    SI =>next char on command line (following the one in AL)
;
; Output:   CF = 1 (set)if AL is switch character, and not in first
;		 position, and has no chance of being part of a date string,
;		 i.e. should be treated as a delimiter.

;	    CF = 0 (reset, cleared) if AL is not a switch char, is in the first
;		 position, or is a slash but may be part of a date string, i.e.
;		 should not be treated as a delimiter.
;
; Vars:  $P_Terminator(W)

; Use:	 $P_0099
;***********************************************************************
$P_Chk_Switch proc

;AN020;; Function: Check if AL is the switch character from 2nd position of $P_STRING_BUF
;AN020;; Output:   ZF = 1 if switch character
;AN020;;	lea	bp,$P_STRING_BUF
;AN020;;	cmp	bx,bp		 ;AN000; 1st position ?
;AN020;;	je	$P_Chk_S_Exit_1
;AN020;;	cmp	al,$P_Switch
;AN020;;	jmp	short $P_Chk_S_Exit_0
;AN020;;$P_Chk_S_Exit_1:
;AN020;;	cmp	al,$P_Switch	 ;AN000; (tm08)
;AN020;;	jne	$P_Nop		;AN000; (tm08)
;AN020;;	or	$P_Flags2,$P_SW  ;AN000; (tm08) It could be valid switch
;AN020;;$P_Nop: 			;AN000; (tm08)
;AN020;;	inc	bp
;AN020;;	cmp	bx,bp		       ;AN000; reset ZF
;AN020;;$P_Chk_S_Exit_0:
;AN020;;	jne	$P_Chk_S_Exit
;AN020;;	mov	   $P_Terminator,al    ;AN000; store switch character
;AN020;;$P_Chk_S_Exit:

	LEA	BP,psdata_seg:$P_String_Buf ;AN020;AC034; BP=OFFSET of $P_String_Buf even in group addressing
;	.IF <BX NE BP> THEN		;AN020;IF not first char THEN
	cmp	BX,BP
	je	$P_STRUC_L2

;	    .IF <AL EQ $P_Switch> THEN	;AN020;otherwise see if a slash
	    cmp     AL,$P_Switch
	    jne     $P_STRUC_L5

		STC			;AN020;not in first position and is slash, now see if might be in date string
IF	DateSw				;AN020;caller looking for date, see if this may be part of one
		PUSH	AX		;AN020;save input char
		MOV	AL,PSDATA_SEG:[BX-1] ;AN026;AL=char before the current char
		CALL	$P_0099 	;AN020;return carry set if not numeric
;		.IF   NC ;AND		;AN020;IF previous char numeric AND
		jc	$P_STRUC_L7

		    MOV     AL,[SI]	;AN020;AL=char after the current char
		    CALL    $P_0099	;AN020;return carry set if not numeric
;(deleted)	    .IF     NC THEN	;AN020;IF next char numeric THEN could be a date
;(deleted)		CLC		;AN020;reset CF so "/" not treated as a delimiter
;(deleted)	    .ENDIF
;		.ENDIF			;AN020;ENDIF looks like date (number/number)
$P_STRUC_L7:
		POP	AX		;AN020;restore AL to input char
ENDIF					;AN020;DateSw
;	    .ELSE
	    jmp     short $P_STRUC_L1

$P_STRUC_L5:
		CLC			;AN020;not a slash
;	    .ENDIF
;	.ELSE				;AN020;is first char in the buffer, ZF=0
	jmp	short $P_STRUC_L1

$P_STRUC_L2:
;	    .IF <AL EQ $P_Switch> THEN
	    cmp     AL,$P_Switch
	    jne     $P_STRUC_L12

		OR	psdata_seg:$P_Flags2,$P_SW ;AN020;AC034;;could be valid switch, first char and is slash
;	    .ENDIF
$P_STRUC_L12:
	    CLC 			;AN020;CF=0 indicating first char
;	.ENDIF
$P_STRUC_L1:

	ret
$P_Chk_Switch endp
	PAGE
;**************************************************************************
; $P_Chk_DBCS:
;
;  Function: Check if a specified byte is in ranges of the DBCS lead bytes
;
;  Input:
;	  AL	= Code to be examineed
;
;  Output:
;	  If CF is on then a lead byte of DBCS
;
; Use: INT 21h w/AH=63
;
; Vars:  $P_DBCSEV_Seg(RW), $P_DBCSEV_Off(RW)
;***************************************************************************
$P_Chk_DBCS PROC
;
	PUSH	DS
	PUSH	SI
	PUSH	bx			;AN000; (tm11)
	CMP	psdata_seg:$P_DBCSEV_SEG,0 ;AC034; ALREADY SET ?
	JNE	$P_DBCS00

	PUSH	AX
;	PUSH	BX			;AN000; (tm11)
	PUSH	ds			;AN000; (tm11)
	PUSH	CX
	PUSH	DX
	PUSH	DI
	PUSH	BP
	PUSH	ES
	XOR	SI,SI
	MOV	DS,SI
	MOV	AX,$P_DOS_GetEV 	;AN000; GET DBCS EV CALL
	INT	21H

;	MOV	AX,DS			;AN000; (tm11)
;	OR	AX,AX			;AN000; (tm11)
	MOV	bx,DS			;AN000; (tm11)
	OR	bx,bx			;AN000; (tm11)
	POP	ES
	POP	BP
	POP	DI
	POP	DX
	POP	CX
;	POP	BX			;AN000; (tm11)
	POP	ds			;AN000; (tm11)
	POP	AX
	JE	$P_NON_DBCS

$P_DBCS02:
	MOV	psdata_seg:$P_DBCSEV_OFF,SI ;AC034; save EV offset
;	MOV	psdata_seg:$P_DBCSEV_SEG,DS ;AC034; save EV segment
	MOV	psdata_seg:$P_DBCSEV_SEG,bx ;AC034; save EV segment (tm11)
$P_DBCS00:
	MOV	SI,psdata_seg:$P_DBCSEV_OFF ;AC034; load EV offset
	MOV	DS,psdata_seg:$P_DBCSEV_SEG ;AC034; and segment

$P_DBCS_LOOP:
	CMP	WORD PTR [SI],0 	;AN000; zero vector ?
	JE	$P_NON_DBCS		;AN000; then exit

	CMP	AL,[SI]
	JB	$P_DBCS01		;AN000; Check if AL is in

	CMP	AL,[SI+BYTE]		;AN000;   range of
	JA	$P_DBCS01		;AN000;      the vector

	STC				;AN000; if yes, indicate DBCS and exit
	JMP	short $P_DBCS_EXIT

$P_DBCS01:
	INC	SI			;AC035; add '2' to
	INC	SI			;AC035;  SI reg
					;AN000; get next vector
;(changed ;AC035;) ADD	   SI,2 	;AN000; get next vector
	JMP	short $P_DBCS_LOOP	;AN000; loop until zero vector found

$P_NON_DBCS:
	CLC				;AN000; indicate SBCS
$P_DBCS_EXIT:
	POP	bx			;AN000; (tm11)
	POP	SI
	POP	DS
	RET
$P_Chk_DBCS ENDP
