
	PAGE	,132  ;
	TITLE	NLSFUNC - GET/SET CP & COUNTRY INFO   CHCP SUPPORT
;**************************************************************************
;This is the NLSFUNC int2f command that supports the INT21h functions
;Get_Extended Country Information and the Set_codepage...
;NLSFUNC will read the COUNTRY.SYS information from disk , store the
;data in a buffer , then move the information into a buffer
;area specified by DOS.
;d:NLSFUNC {path}
subttl get extended country data
page
; Functions 1 and 3 load country/code-page tables into DOS; function 1 also
; selects the device code page. Functions 2 and 4 return country data to
; the caller, with function 4 adapting the older INT 21h/38h format.
; Country-table requests use BX=code page, DX=country, CX=size.
; Extended-information requests select the information type in BP.
;
subttl	Revision History
page
subttl macros
page
PUSHALL       macro  reg1,reg2,reg3			;used to save all
		push reg1				;registers needed
		push reg2				;for DOS interactions
		push reg3
	      endm

POPALL	     macro   reg1,reg2,reg3			;used to restore all
		pop reg3				;for DOS interactions
		pop reg2
		pop reg1
	      endm



EXTRN		SYSPARSE:NEAR

subttl NLSFUNC data
page
NLS_DATA	SEGMENT byte PUBLIC 'DATA'

;Copyright 1988 Microsoft
;***************************** MSG DATA ************************************
UTILITY 	db	"NLSFUNC",0
;***************************** MSG DATA ************************************

.xlist
include copyrigh.inc
include struc.inc
include DOESMAC.INC
include MULT.INC
include sf.inc
include DOSCNTRY.INC
include DEVSYM.INC
include SYSMSG.INC
include FUNCDBCS.INC
include MSG2NLS.INC
include FUNCPARM.INC

MSG_UTILNAME <NLSFUNC>

.list
MULT_NLSFUNC	equ	14h
INSTALLED	equ	0ffh
; nlsfunc function codes
CHG_CODEPAGE	 equ	1
GET_EXT_CTY_INFO equ	2
SET_CODEPAGE	 equ	3
GET_CTY_INFO	 equ	4

INVALID_FUNCTION equ	1		     ;=J
INVALID_DATA	 equ	13		     ;=L
PAD_CHAR	 equ	' '
BAD_INVOKE	 equ	65		     ;=E
UPCASE_A	 equ	'A'
; The external-query API returns a pointer into this buffer. Its data half
; must hold a complete 266-byte collation record (tag, length, 256 weights).
BUFFSIZE	 equ	528
LOCATE_INFOTYPE  equ	18	      ;THE DEVICE LIST & THE OLD COUNTRY INFO
CTL_BUFF	 equ	256 ;
ID_TAG		 equ	8
DATA_BUFF_LENG	 equ	(BUFFSIZE - CTL_BUFF)
MAXBUFF_FIT	 equ	(BUFFSIZE - (CTL_BUFF + ID_TAG))
DATA_N_ID	 equ	(CTL_BUFF + ID_TAG)
SETCTY_LENG	 equ	38
;SPACE		  equ	 ' '
BACKSLASH	 equ	'\'
PERIOD		 equ	'.'
;COLON		  equ	 ':'
;
;**************** NEW VARIABLE	****************
subttl NLSFUNC data
page
IN_DEX		  equ	 bp
FILESPEC_PTR	  equ	 byte ptr ds:[in_dex]
FILEVAL 	 equ	0100h	;convert data block after checking for the
				;drive only to look for the filespec
CL_NUM		 equ	81h	;command line at the PSP
;**************** NEW VARIABLE	****************
;interrupts
SET_INT 	 equ	25h
GET_INT 	 equ	35h
;
;dos call backs
;dosopen	 equ	38
;dosclose	 equ	39
;lseek		 equ	40
;dosread	 equ	41
;
;NO_ERRORS	 equ	0FFh

;variable definition area
;initialization area

MSG_SERVICES <MSGDATA>

ID_CHECK	db	1		;resident variable re-initialize
ALL_DONE	db	0		;resident variable re-initialize
GET_EXT 	db	0		;resident variable re-initialize
INFO_ID 	db	0		;resident variable re-initialize
DONT_CLOSE	db	0		;if open or close error,this is set

RES_PARASIZE	dw	0		;adjusted size for terminate & stay func.
ERROR_CODE	db	0		;contains extended error code val
FUNC_CODE	db	0		;save function number
GOOD_PAR	db	0
PARSE_ERR	db	0

SI_DOSLOCATE	dw	0
DS_DOSLOCATE	dw	0
SAVEDX		dw	0		;=FC  file offset
SAVECX		dw	0		;=FC
NOFFSET 	dw	2		;=FC
CSIZE		dw	0
CCODE		dw	0
CPAGE		dw	0
VALID_FUNC	db	0		;Flag to check for valid function #
EXIT_STAY	db	0
FILENAME	db     "COUNTRY.SYS",0
PATH_SPEC	db	64 dup(0)	;used to build path parameter
USER_PATH	db	0		;=I
PAR_RETC	dw     0
NO_PARMS	db     0
GOOD_PATH	db     0
PATHSEG 	DW     0
SW_SPEC 	dW     0
LENGTH_HOLD	db     0
;***CNS
CUR_PTR        DW	0		   ;AN003;; keeps track of parameter position
OLD_PTR        DW	0		   ;AN003;; keeps track of parameter position
;***CNS
;********************************************************************************
NLS_BUFFER	db	BUFFSIZE dup (?)  ;NLS BUFFER to transfer data



NLSFUNC_HELP_STR DB "Loads country-specific information for national language support.",0Dh,0Ah
		DB 0Dh,0Ah
		DB "NLSFUNC [[drive:][path]filename]",0Dh,0Ah
		DB 0Dh,0Ah
		DB "  filename   National Language Support definition file (default: COUNTRY.SYS)",0Dh,0Ah,"$"

NLS_DATA ENDS

NLS_INIT_CODE	SEGMENT BYTE PUBLIC 'CODE'

		ASSUME CS:NLS_INIT_CODE,DS:NOTHING,ES:NOTHING,SS:NOTHING



INT_2f_NEXT	DD	?	;Chain location.
TEMPHOLD	DW	0
subttl resident code
page
;**************************** resident portion ********************************

NLSRES_CODE	PROC	NEAR
		cmp	ah,MULT_NLSFUNC 	;Check the mutliplex value
		je	IS_NLSFUNC		;the # is mine
		jmp	dword ptr INT_2F_NEXT	;Chain to* the next handler

IS_NLSFUNC:


		cmp	al,0f8h 	;Make sure AL does not have reserved
					;DOS value 0F8 - 0FFH
		jb	SEL_FUNC	;Select the function code between 0,
					;1,2,3,4

		iret			;return on reserved functions

SEL_FUNC:


		push	es		;=C
		push	ds		;save the user's data segment
		push	si
		push	ds
		push	ax		;save the function value
		mov	TEMPHOLD,ax


		mov	ax,NLS_DATA	;so it won't be hosed
		mov	ds,ax		;set the data segment to mine

		ASSUME DS:NLS_DATA

		pop	ax
		pop	DS_DOSLOCATE
		pop	SI_DOSLOCATE

		mov	ID_CHECK,1	;re-intialize flags
		mov	ALL_DONE,0	;from resident portion
		mov	GET_EXT ,0
		mov	INFO_ID ,0
		mov	VALID_FUNC,0	;Flag to check for valid function #
		mov	DONT_CLOSE,0	;no open or close error yet

		pushall bx,cx,dx	;save all DOS registers
		pushall bp,si,di	;save all DOS registers
; *************************** CNS **********************************************
		sti			;;AN000;the interrupt for external devices
; *************************** CNS **********************************************
		mov	FUNC_CODE,al	;save function #
		cmp	al,0
		jne	FUNCODE_DOSTATE ;state is not 0
		mov	al,INSTALLED	;Tell DOS I am installed
					;state is 0
		jmp	RES_EXIT	;exit


FUNCODE_DOSTATE:
		cmp	al,CHG_CODEPAGE
		je	FUNCODE3_1
		cmp	al,GET_EXT_CTY_INFO
		je	FUNCODE2
		cmp	al,SET_CODEPAGE
		je	FUNCODE3_1
		jmp	FUNCODE4


FUNCODE4:     ;Get Country Data - old 38 call =F
		mov	bp,1		;set info_id to 1 =F
		jmp	short FUNCODE2	;		  =F


FUNCODE3_1:    ;Set Codepage/Get Country Information =E
		les	di,dword ptr SI_DOSLOCATE
;		cmp	es:[di].ccDosCodePage,bx	;=E
;		jne	fc3_1_10			;=E
;		cmp	es:[di].ccDosCountry,dx 	;=E
;		jne	fc3_1_10			;=E
;		mov	CPAGE,bx	     ;get the codepage value =E
;		jmp	short fc3_1_20			;=E
;
;fc3_1_10:
		call	RES_MAIN
		jc	ERROR_ROUTINE
		CallInstall Dosclose,multdos,39,<ax,bx,cx,dx,ds,es>,<es,ds,dx,cx,bx,ax> ;close the file
		jc	NO_CLOSE

fc3_1_20:
		cmp	FUNC_CODE,1	       ;=E
		je	FUNCODE1	       ;=E
		mov	al,ALL_DONE	       ;=E
		jmp	short RES_EXIT	       ;=E


FUNCODE2:      ;Get Extended Country Information
		mov	ax,bp		;information requested by the user
		mov	INFO_ID,al
		mov	GET_EXT,1	;get extended cty into user buffer
		call	RES_MAIN
		jc	ERROR_ROUTINE

		jmp	short CLOSE_FILE	  ;=E


FUNCODE1:      ;CHCP - Change Code Page    =E
		call	WALK_DEVICES	    ;=E
		mov	al,ALL_DONE	    ;=E
		jmp	short RES_EXIT	    ;=E



CLOSE_FILE:				     ;DOS  3eh function close COUNTRY.SYS
		mov	al,ALL_DONE

		CallInstall Dosclose,multdos,39,<ax,bx,cx,dx,ds,es>,<es,ds,dx,cx,bx,ax> ;close the file
		jc	NO_CLOSE
						;clear to let DOS know ok


RES_EXIT:
		popall	bp,si,di	;restore all DOS registers
		popall	bx,cx,dx	;restore all DOS registers

		cmp	FUNC_CODE,GET_EXT_CTY_INFO ;			  =K
		jne	NC_IRET 	;				  =K
		cmp	al,0		;if successful 65 call, put size  =K
		jne	NC_IRET 	;of info returned in CX 	  =K
		mov	cx,CSIZE	;				  =K

NC_IRET:				;				  =K
		pop	ds		;restore user's data segment  =K moved
		pop	es		;=C			      =K moved
		iret			;Return to DOS

NO_CLOSE:
		mov	ALL_DONE,al	;=J
		inc	DONT_CLOSE

;if an error was detected

ERROR_ROUTINE:
		mov	al,ALL_DONE
		cmp	DONT_CLOSE,1
		je	RES_EXIT
		jmp	CLOSE_FILE


NLSRES_CODE	ENDP
;*******************************END OF NLSRES_CODE******************************
subttl resident main routine
page
;*******************************RES_MAIN****************************************
RES_MAIN	PROC	NEAR

		mov    VALID_FUNC,1	;function exist
		mov    CPAGE,bx 	;get the codepage value
		mov    CCODE,dx 	;get the country code
		mov    CSIZE,cx 	;size of the buffer
		call   CHK_OPEN 	;go open file if possible
		jc     END_RES		;scan and read country info

		mov	ax,CCODE
		mov	dx,CPAGE
		mov	si,offset NLS_BUFFER
		call	Trans_Cty_Data
					;into my buffer & the dos buffer
  END_RES:
		ret

RES_MAIN	ENDP
;*******************************END RES_MAIN************************************
subttl	check open procedure
page
;******************************CHECK OPEN PROCEDURE****************************
CHK_OPEN	PROC	NEAR


		xor	cx,cx				;zero cx for open
		cmp	USER_PATH,1			;either user supplied=I
		je	co_user 			;or default DOS

co_dos: 	push	ds				;save current ds value
		push	si				;save current si value
		lds	si,dword ptr SI_DOSLOCATE	;old dos ds si value
		lea	dx,ds:[si].ccPATH_COUNTRYSYS
		CallInstall Dosopen,Multdos,38,<BX,DS,ES,SI,DI>,<DI,SI,ES,DS,BX>
		pop	si				;restore current si
		pop	ds				;restore current ds
		jmp	short co_10

co_user:	lea	dx,PATH_SPEC
		CallInstall Dosopen,Multdos,38,<BX,DS,ES,SI,DI>,<DI,SI,ES,DS,BX>

co_10:		jc	BADREP_FILE			;bx contains the
		mov	bx,ax				;file handle
		jmp	short END_OPEN

BADREP_FILE:
		mov	ALL_DONE,al			;=J
		inc	DONT_CLOSE

END_OPEN:
		ret

   CHK_OPEN	ENDP
;******************************END OF CHKOPEN**********************************
subttl transfer country data
page
;******************************TRANS_CTY__DATA ********************************
TRANS_CTY_DATA	PROC	NEAR

TRANSTART:
		push	di			;save start of CTY/CP INFO
						;get the size of the file
		xor	cx,cx			;clear cx to start at
		xor	dx,dx			;at the beginning of the
						;file
		call	READ_CTLBUFF		;Read in the file header
		jnc	CHECK_HEADER
		jmp	END_TRANS		;=G

CHECK_HEADER:
		; Reject a short or unidentified file before using buffered offsets.
		cmp	ax,23
		jb	INVALID_HEADER
		cmp	word ptr ds:[si],043ffh
		jne	INVALID_HEADER
		cmp	word ptr ds:[si+2],0554fh
		jne	INVALID_HEADER
		cmp	word ptr ds:[si+4],0544eh
		jne	INVALID_HEADER
		cmp	word ptr ds:[si+6],05952h
		jne	INVALID_HEADER
		jmp	short CHK_INFOTYPE
INVALID_HEADER:
		jmp	BAD_FILE

CHK_INFOTYPE:
		add	si,LOCATE_INFOTYPE	;si > Country info type
		cmp	byte ptr ds:[si],1	;only 1 type exist currently
		je	GET_INFOIDS
		jmp	BAD_FILE
GET_INFOIDS:
		inc	si			;si > set to file offset
		mov	dx,word ptr ds:[si]	;Get the Info file offset
		mov	cx,word ptr ds:[si+2]	;Doubleword

		mov	SAVEDX,dx		;=FC save offset
		mov	SAVECX,cx		;=FC for more than 1 buffer
		mov	NOFFSET,2		;=FC start from beginning

		call	READ_CTLBUFF		;Read Info
		jnc	COUNT_ENTRIES
		jmp	END_TRANS		;=G

COUNT_ENTRIES:

		mov	cx,word ptr ds:[si]	;Get count of entries
						;in info
		inc	si			;next word
		inc	si			;si >  Entry info packet

FIND_CTY:					;Search for CTY/CP combo

		mov	ax,word ptr ds:[si]	;=FC get size of entry
		add	ax,2			;=FC include length filed
		add	NOFFSET,ax		;=FC look ahead
		cmp	NOFFSET,CTL_BUFF-4	;=FC < (256 - 4)
		jb	IN_BUFF 		;=FC
		sub	NOFFSET,ax		;=FC restore to old offset
		push	cx			;=FC save number of cntries
		mov	cx,SAVECX		;=FC get file offset
		mov	dx,SAVEDX		;=FC
		add	dx,NOFFSET		;=FC update to the entry
		adc	cx,0			;=FC beginning
		mov	SAVECX,cx		;=FC save them for next use
		mov	SAVEDX,dx		;=FC
		call	READ_CTLBUFF		;=FC read next buffer in
		jc	READERROR		;=FC read error occurs
		pop	cx			;=FC restore number of cntries
		; READ_CTLBUFF starts at the current entry. Account for that
		; entry just as the non-refill path does, so later refills do
		; not reread entries and exhaust the directory count early.
		mov	ax,word ptr ds:[si]
		add	ax,2
		mov	NOFFSET,ax
IN_BUFF:

		mov	dx,CPAGE
		mov	ax,CCODE
		cmp	ax,word ptr ds:[si+2]	 ;compare country id
		jne	NEXT_CTY
		cmp	dx, word ptr ds:[si+4]	;compare code page id
		je	FOUND_CTY
		cmp	dx,0		  ;=FC	  if default pick the
		jz	FOUND_CTY2	  ;=FC	  1st country

NEXT_CTY:
		add	si, word ptr ds:[si]	;next entry
		inc	si
		inc	si			;take a word for size of entry itself
		loop	FIND_CTY

		mov	ALL_DONE,INVALID_DATA	;if it exits the loop	=J =L
		jmp	FINDCTY_FAIL		;then no cp/cty match

READERROR:	pop	cx			;=FC
		jmp	END_TRANS		;=FC

FOUND_CTY2:	mov	dx,word ptr ds:[si+4]	;=FC from now on,this is
		mov	CPAGE,dx		;=FC the code page

FOUND_CTY:		       ;found the matching entry
		mov	dx, word ptr ds:[si+10] ;get the file offset of country data
		mov	cx, word ptr ds:[si+12]
		call	READ_CTLBUFF
		jnc	NUM_ENTRY
		jmp	END_TRANS		;=G
NUM_ENTRY:
		mov	cx, word ptr ds:[si]	;get the number of entries to handle.
		inc	si
		inc	si			;SI -> first entry

SETDOSCTY_DATA:
.REPEAT
		 push	 di			 ;ES:DI -> DOS_COUNTRY_CDPG_INFO
		 push	 si			 ;si -> current entry in Control buffer
		 push	 cx			 ;save # of entry left

		mov	al, byte ptr ds:[si+2]	;get data entry id
		xor	ah,ah			;clear out for comparison with
						;info-id in case id is > 256



		cmp	GET_EXT,1		;check to see if function 2
						;get_extended info was needed
		jne	TRANSALL		;if not assume function code 1
						;set codepage

		cmp	INFO_ID,-1		;Minus 1 means return all of the
		jne	CHK_ID			;country info to the user
						;otherwise get the specific
						;info id and return only that info


		pop	cx			;error can not return all
		pop	si			;info accept for currently
		pop	di			;loaded control info in DOS
		jmp	BAD_SETID		;area

CHK_ID: 	cmp	al,INFO_ID		;check to see if the selected
						;id is the same as the id in the
						;ctrl buffer area

		jne	SETDOSCTY_NEXT		;if not equal go search for the
						;next information id

		pop	cx			;Bingo!! Found it set counter
		mov	cx,1			;to zero to exit loop
		push	cx
		mov	ID_CHECK,0		;found a valid id
		cmp	GET_EXT,1		;after transferring data to USER
		je	GET_ADDR		;area

						;set cx image in stack to force
						;exit loop
TRANSALL:



		call	GetDOSCTY_Dest		   ;get the address of destination in ES:DI
		jc	SetDOSCTY_NEXT		   ;No matching data entry id in DOS

GET_ADDR:

		mov	dx, word ptr ds:[si+4]	   ;get offset of data
		mov	cx, word ptr ds:[si+6]



SEEK_READ:

		push	ax			   ;=A	save data id.
		xor	bp,bp						;DOS 4200h function
		CallInstall Lseek,multdos,40,<bx,cx,ds,es,di,si>,<si,di,es,ds,cx,bx>		 ;move ptr
		pop	ax			   ;=A
		jc	DATASEEKNREAD
										     ;when ptr moved
		mov	dx,offset NLS_BUFFER +CTL_BUFF							;set the buffer to the beginning of the
										     ;data buffer area

		mov	cx,DATA_BUFF_LENG					     ;set to number of bytes in the
										     ;data buffer area
		push	ax			   ;=A
								       ;DOS 3fh
		CallInstall Dosread,Multdos,41,<bx,cx,ds,es,di,si>,<si,di,es,ds,cx,bx>		 ;Read cx many bytes into the buffer
		pop	ax			   ;=A
		jc    DATASEEKNREAD

IS_EXTENDED:
		cmp	GET_EXT,1
		jne	CHK_OVERWRITE
		call	GETEXT_CTY
		jmp	short SETDOSCTY_NEXT


CHK_OVERWRITE:					   ;=A
						   ; If SetCountryInfo, then
						   ; put DOS monocase routine
						   ; entry point into
						   ; NLS_BUFFER so don't
						   ; write over.  =A
		cmp	al,SetCountryInfo	   ;=A
		jne	DOS_MOVE		   ;=A
		mov	ax,word ptr es:[di+24]	   ;=A
		mov	word ptr ds:[NLS_BUFFER+CTL_BUFF + 32],ax  ;=A
		mov	ax,word ptr es:[di+26]	   ;=A
		mov	word ptr ds:[NLS_BUFFER+CTL_BUFF + 34],ax  ;=A

		mov	ax,CPAGE		   ;=FC, CPAGE is right
		mov	word ptr ds:[NLS_BUFFER+CTL_BUFF + 12],ax  ;=FC

DOS_MOVE:
		call	CHK_ADJUST						     ;now check to see if the entire
										     ;table fits

SETDOSCTY_NEXT:

		pop	cx
		pop	si
		pop	di
		add	si, word ptr ds:[si]
		inc	si
		inc	si
		dec	cx
		.UNTIL <cx eq 0>    NEAR		     ;loop    SETDOSCTY_DATA

		;Check for an invalid id
		cmp	GET_EXT,1		;Check to see if a get_ext func 2 was issued
		jne	CTLSEEKnREAD		;if not move on
		cmp	ID_CHECK,1		;if so check to see if an id was found
		je	BAD_SETID		;if none was found report an error
						;otherwise continue


CTLSEEKnREAD:
		clc				;=G
		jmp	short END_TRANS 	;exit



DATASEEKnREAD:
		mov    ALL_DONE,al		;=J
		pop	cx
		pop	si
		pop	di
		jmp    short END_TRANS

BAD_SETID:
		mov	ALL_DONE,INVALID_FUNCTION  ;=J
		jmp    short FINDCTY_FAIL	   ;=J

BAD_FILE:
		mov	ALL_DONE,INVALID_FUNCTION  ;=J

FINDCTY_FAIL:
		stc

END_TRANS:
		pop	di			;Restore header start
		ret



TRANS_CTY_DATA	ENDP

;******************************END TRANS_CTY_DATA ******************************
subttl get DOS country destination
page
;****************************GETCTY_DEST***********************************************
GetDOSCty_Dest	 proc	 near
;Get the destination address in the DOS country info table.
;Input: AL - Data ID
;	ES:DI -> DOS_COUNTRY_CDPG_INFO
;On return:
;	ES:DI -> Destination address of the matching data id
;	carry set if no matching data id found in DOS.

	push	cx
	add	di, ccNumber_of_entries ;skip the reserved area, syscodepage etc.
	mov	cx, word ptr es:[di]	;get the number of entries
	inc	di
	inc	di			;SI -> the first start entry id
GetCntryDest:
	cmp	byte ptr es:[di], al
	je	GetCntryDest_OK
	cmp	byte ptr es:[di], SetCountryInfo ;was it SetCountryInfo entry?
	je	GetCntryDest_1
	add	di, 5			;next data id
	jmp	short GetCntryDest_loop

GetCntryDest_1:
	add	di, NEW_COUNTRY_SIZE + 1 ;next data id

GetCntryDest_loop:
	loop	GetCntryDest
	stc
	jmp	short	GetCntryDest_exit

GetCntryDest_OK:

	cmp	al, SetCountryInfo	;select country info?
	jne	GetCntryDest_OK1
	inc	di			;now DI -> ccCountryInfoLen
	clc				;clear the carry
	jmp	short	GetCntryDest_exit

GetCntryDest_OK1:

	les	di, dword ptr es:[di+1] ;get the destination in ES:DI
	clc

GetCntryDest_Exit:
	pop	cx
	ret

GetDOSCty_Dest	 endp
;****************************GETDOSCTY_DEST*************************************
subttl get extended country data
page
;****************************GETEXT_CTY*****************************************
GETEXT_CTY	proc

JUSTONE_ID:
		mov	ah,func_code	;=F
		cmp	ah,GET_CTY_INFO ;=F
		je	id_ctyinfo1	;=F

		mov	al,INFO_ID
		mov	byte ptr es:[di],al

		cmp	INFO_ID,SetCountryInfo ;SETCTY_INFO  =D moved.
		je	ID_CTYINFO	       ;=D don't want ptr if 1.

		mov	word ptr es:[di+1],offset nls_buffer + ctl_buff+8  ;=H
		mov	word ptr es:[di+3],ds	     ;my current ds value
		mov	CSIZE,5 		     ;=K

		jmp	GET_EXT_END

ID_CTYINFO:
		inc	di		;=D  (old code - add di,5) =F(moved).
id_ctyinfo1:				;=F
		mov	cx,CSIZE
					;next line used to be "add si,5"
					;si needs to point to cty info. =D
		mov	si,offset nls_buffer + ctl_buff + 8  ;=D

		push	es		;=A  put DOS Monocase Routine
		push	di		;=A  entry point in user buffer.
		push	ax		;=A
		les	di,dword ptr si_doslocate ;=A
		mov	ax,word ptr es:[di].ccMono_Ptr	  ;=A
		mov	word ptr ds:[si+24],ax		  ;=A
		mov	ax,word ptr es:[di].ccMono_Ptr+2  ;=A
		mov	word ptr ds:[si+26],ax		  ;=A

		mov	ax,CPAGE			  ;=FC trust CPAGE
		mov	word ptr ds:[si+4],ax		  ;=FC

		pop	ax		;=A
		pop	di		;=A
		pop	es		;=A

		push	bx		;=F
		cmp	ah,GET_CTY_INFO ;=F if get cty info(38) slide info
		jne	id_ctyinfo2	;=F ptr up to date.
		add	si,6		;=F
		mov	cx,old_country_size ;=FC
		jmp	MOVE_CTY	 ;=FC

id_ctyinfo2:	mov	bx,word ptr ds:[si]	;=FC get table size


		sub	CSIZE,3 	;=FC  size begins after length field
		mov	cx,CSIZE	;=FC

		cmp	cx,bx			;=D was cmped to SETCTR_LENG
		ja	TRUNC_SIZE	;=FC  used to be jg
		jmp	short  MOV_SIZE
TRUNC_SIZE:
		mov	cx,bx		;=F
MOV_SIZE:
		mov	es:[di],cx	;=FC  move actual length to user's buff
		add	di,2		;=FC  update index
		add	si,2		;=FC  skip length field

MOVE_CTY:	pop	bx		;=F
		mov	CSIZE,cx	;=K
		add	CSIZE,3 	;=K
		rep	movsb

GET_EXT_END:
		ret

GETEXT_CTY	endp
;*****************************END GETEXT_CTY*************************************
subttl read into control buffer
page
;**************************READ_CTLBUFF*****************************************
;
READ_CTLBUFF		proc	near
;Move file pointer to CX:DX
;Read 64 bytes into the control buffer.  Assume that the necessary data
;is within that limit.
;SI will be set to beginning of the offset my NLS_BUFFER hence DS:SI points to the control buffer.
;Entry:  CX,DX offset from the start of the file where the read/write pointer
;	 be moved.
;	 BX - file handle
;	 DS - buffer seg.
;Return: The control data information is read into DS:0 - DS:0200.
;	 CX,DX value destroyed.
;	 Carry set if error in Reading file.
;
								    ;Function 4200h
		xor	bp,bp
		CallInstall Lseek,multdos,40,<bx,cx,ds,es,di,si>,<si,di,es,ds,cx,bx>	;move pointer
		jc	NO_SEEK1

		mov	dx,offset NLS_BUFFER	  ;ds:dx -> control buffer
		mov	si,dx			  ;index for the entire buffer
						  ;read into the buffer function 3fh
		mov	cx, CTL_BUFF		  ;XXX bytes. Size of the information
		CallInstall Dosread,multdos,41,<bx,cx,dx,ds,es,di,si>,<si,di,es,ds,dx,cx,bx>	;should be less than XXX bytes.
		jc	NO_READ1
		jmp	short RICB_exit


NO_SEEK1:
		 mov	ALL_DONE,al		  ;=J
		 jmp	short RICB_exit

NO_READ1:
		 mov	ALL_DONE,al		  ;=J

RICB_exit:				  ;In this case 64 bytes
		  ret

READ_CTLBUFF	  endp
;****************************END READ_CTLBUFF***********************************
subttl check / adjust / move data into DOS buffer
page
;****************************CHK_ADJUST*****************************************
CHK_ADJUST	PROC  NEAR

		push	ax			;save info id
		mov	si,offset NLS_BUFFER+DATA_N_ID		  ;start of buffer + tag id
		mov	cx, word ptr ds:[si]	;get the length of the structure

		inc	cx
		inc	cx

		cmp	cx,MAXBUFF_FIT
		jbe	MOVE_DATA
		push	cx
		mov	cx,MAXBUFF_FIT
		rep	movsb
		pop	cx
		sub	cx,MAXBUFF_FIT

NEED_ADJUST:
		mov	dx,offset NLS_BUFFER+CTL_BUFF		  ;reset to the beginning of the data buffer
		mov	si,dx			;reset to the beginning of the data buffer
		cmp	cx,DATA_BUFF_LENG	;check to see if it fits for the nth read
		jbe	LAST_READ		;last portion fits
		push	cx			;save how much is left to read
		mov	cx,DATA_BUFF_LENG	;set to how much you read at one time

		;read again					      ;function 3fh
						      ;read into the data buffer
		CallInstall Dosread,multdos,41,<bx,cx,dx,ds,es,di,si>,<si,di,es,ds,dx,cx,bx>  ;save the file handle
		jc	ADJUST_END

		rep	movsb			      ;move data into DOS area
		pop	cx			      ;restore size remaining to
		sub	cx,DATA_BUFF_LENG	      ;be read get new size
		jmp	NEED_ADJUST			  ;must read agian

LAST_READ:
						      ;one more read 3f
		 CallInstall Dosread,multdos,41,<bx,cx,dx,ds,es,di,si>,<si,di,es,ds,dx,cx,bx>
		 jc	ADJUST_END

MOVE_DATA:
		rep	movsb			      ;move data into DOS area

ADJUST_END:
		pop	ax
		ret
CHK_ADJUST	ENDP
;*******************************END CHK_ADJUST *********************************
subttl walk through device drivers and invoke
page
;************************ WALK DEVICE DRIVERS **********************************
;=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=E=

WALK_DEVICES	PROC  NEAR

		mov	si,offset NLS_BUFFER ;Prepare to hold device name
		push	es			;AN001; Clear out NLS_BUFFER to 0
		push	ds
		pop	es
		mov	di, si			;AN001; ES:DI-> NLS_BUFFER
		xor	ax, ax			;AN001; AX=0
		mov	cx, BUFFSIZE
		shr	cx, 1			;AN001; /2 to make a # of words
		rep	stosw
		pop	es			;AN001; Restore es
						;Get ptr to hdr of 1st device.
		push	si
		CallInstall GetDevLst,Multdos,44,<DS>,<DS>
		pop	si
		mov	es,bx		    ;bx:ax -> hdr.
		mov	di,ax
char_test:
		test	es:[di].sdevatt,devtyp ;check attribute word for
		jne	open_device
		jmp	GET_NEXT_DEVICE        ;character device.

OPEN_DEVICE:
		push	si
		push	di		    ;set up asciiz filename
		add	di,10		    ;for DOS file open
		mov	cx,8

set_asciiz:	mov	al,es:[di]
		cmp	al,20h
		je	done_set_asciiz
		mov	ds:[si],al
		inc	di
		inc	si
		loop	set_asciiz

done_set_asciiz:xor	al,al
		mov	ds:[si],al

		pop	di
		pop	si

		mov	cx,1		    ;open for write
		mov	dx,si
		CallInstall Dosopen,Multdos,38,<DS,SI,ES,DI>,<DI,ES,SI,DS>
		jnc	end_open_device
		jmp	GET_NEXT_DEVICE     ; ignore this =FC

end_open_device:
		mov	bx,ax		    ;put handle in bx
		call	Chk_Revisit	    ;AN001; Have been here already?
		jnc	INVOKE_DEVICE	    ;AN001; No, a new one.
		jmp	CLOSE_DEVICE	    ;AN001; Yes. Close and ignore this.

INVOKE_DEVICE:
		push	ds		    ;Check print queue first.
		push	si		    ;Set up for 2f print call.
		clc
		mov	ax,0106h	    ;2f call to command.com.
		int	2fh		    ;If print active: carry set,
		jnc	invoke_it	    ;DS:SI -> hdr of printing device.
		cmp	si,di		    ;Check if printing device is this
		jne	invoke_it	    ;device.  Match on ptr to device.
		mov	ax,ds
		mov	cx,es
		cmp	ax,cx
		jne	invoke_it

		pop	si
		pop	ds
		mov	ALL_DONE,BAD_INVOKE ;Match.  Set invoke error.
		jmp	CLOSE_DEVICE

invoke_it:	pop	si			     ;save the current
		pop	ds				;environment

;*************** CNS *********** Start of DBCS Support
;  PUSH    DS			   ;ICE
;  push    bx			   ;ICE
;  push    ax			   ;ICE
;  mov	   bx,0140H		   ;ICE
;  xor	   ax,ax		   ;ICE
;  mov	   ds,ax		   ;ICE
;  mov	   ax,word ptr ds:[bx]	   ;ICE
;  mov	   word ptr ds:[bx],ax	   ;ICE
;  POP	   ax			   ;ICE
;  pop	   bx			   ;ICE
;  pop	   ds			   ;ICE
	       push    di
	       push    bx
	       push    cx
	       push    es
	       les     di,dword ptr SI_DOSLOCATE     ;get the environmental
;*************** CNS ******************
;	       mov     bx,es:[di].ccDBCS_ptr	     ;values to allow
;	       mov     es,es:[di].ccDBCS_ptr+2	     ;recognition and
;*************** CNS ******************
	       les     bx,es:[di].ccDBCS_ptr
	       mov     cx,es:[bx]		     ;invocation of data
	       add     cx,2
	       add     bx,2			     ;and ID for start
	       mov     di,offset pk.DBCS_EV	     ;and stop values for
						     ;otherwise it is a DBCS
;****CHANGE					     ;or custom designed codepage

	       mov     PK.PACKLEN,cx		     ;if packet length is zero

NODBCS_CP:
	       add     cx,-2			     ;AN002; reset counter before CP addition

;****CHANGE

DB_EVECS:
	       cmp     cx,0			     ;AN002;no need to alter packet
	       je      NO_LOAD			     ;An002;initialized to zero


	 .REPEAT				      ;;AN000;DBCS transmission
	       mov     al,es:[bx]		     ;;AN000;get the the contents
;***CNS
	       mov     ds:[di],al			;;AN002;of where the DBCS Points
;***CNS
	       inc     di			     ;;AN000;data packet for ioctl
	       inc     bx			     ;AN000;;call--- get the start
						     ;stop values to load
		dec	cx

	  .UNTIL <CX EQ 0 >
						      ;invocation of 1 codepage
						     ;standard codepage selection


NO_LOAD:

		 pop	 es			       ;AN000;;accordingly & restore
		 pop	 cx			       ;AN000;;values
		 pop	 bx
		 pop	 di
						       ;AN000;;invoke codepage
;************************ CNS*** End of DBCS

					    ;Set up data packet for generic
		mov	ax,cpage	    ;ioctl call.
		mov	pk.packcpid,ax
		lea	dx,pk

		mov	cx,004ah
		mov	bp,0ch		    ;generic ioctl
		CallInstall IOCTL,multdos,43,<DS,SI,ES,DI,BX>,<BX,DI,ES,SI,DS>
		jc	device_error


CLOSE_DEVICE:
		CallInstall Dosclose,multdos,39,<DS,SI,ES,DI>,<DI,ES,SI,DS>
		jc	dev_open_close_error  ; ignore this =FC

GET_NEXT_DEVICE:
		cmp	word ptr es:[di],0FFFFH
		je	END_WALK_DEVICES
		les	di,dword ptr es:[di]
		jmp	char_test

DEVICE_ERROR:
		cmp	ax,1
		je	CLOSE_DEVICE
		CallInstall GetExtErr,multdos,45,<DS,SI,ES,DI,BX>,<BX,DI,ES,SI,DS>
		cmp	ax,22
		je	CLOSE_DEVICE
		mov	ALL_DONE,BAD_INVOKE
		jmp	CLOSE_DEVICE

dev_open_close_error:
		mov	ALL_DONE,BAD_INVOKE
		jmp	GET_NEXT_DEVICE

END_WALK_DEVICES:


		ret

WALK_DEVICES	endp
;*********************** END WALK DEVICE DRIVERS *******************************
;************************ Chk_Revisit******************************************
;This routine will check if we are opening the same device driver again.
;If it is, then carry bit will set.
;This routine will use the NLS_BUFFER to keep the history of already
;visited device driver address (OFFSET,SEGMENT).  NLS_BUFFER will be
;used from the end of the buffer towards to the front of the buffer.
;For 512 byte length and considering the front part used for OPEN device
;driver name string, this will handle appr. 126 devices maximum. which is
;sufficient enough. - J.K. 1/15/88
;IN: BX = file handle
;    DS = NLS_BUFFER segment
;OUT: carry set = visited
;     carry not set = new one.
;     Other registers saved.

Chk_Revisit	proc	near
	push	ax
	push	bx
	push	es
	push	di
	mov	ax, 1220h			;AN001; Get the spot of SFT
	int	2fh
	jc	Chk_Rvst_Ret			;AN001; This won't happen
	xor	bx, bx
	mov	bl, byte ptr es:[di]
	mov	ax, 1216h			;AN001; Get the SFT pointer
	int	2fh				;AN001; es:di-> SFT table
	jc	Chk_Rvst_Ret			;AN001; This won't happen
	mov	ax, word ptr es:[di].SF_DEVPTR	;AN001; offset of device
	mov	bx, word ptr es:[di].SF_DEVPTR+2;AN001; Segment of device
	mov	di, offset NLS_BUFFER
	add	di, BUFFSIZE-2			;AN001; ds:di-> last word of the buffer
Chk_Rvst_While:
	cmp	word ptr ds:[di], 0		;AN001; di-> segment value
	jne	Chk_Rvst_Cont
	cmp	word ptr ds:[di-2], 0		;AN001; offset
	jne	Chk_Rvst_Cont
	jmp	Chk_Rvst_New			;AN001; Encountered a blank entry in the buffer
Chk_Rvst_Cont:
	cmp	word ptr ds:[di], bx
	jne	Chk_Rvst_Next
	cmp	word ptr ds:[di-2], ax
	jne	Chk_Rvst_Next
	stc					;AN001; found a match
	jmp	Chk_Rvst_Ret
Chk_Rvst_Next:
	sub	di, 4				;AN001; move the pointer to the next entry
	jmp	Chk_Rvst_While
Chk_Rvst_New:
	mov	word ptr ds:[di],bx		;AN001; Keep the current open device segment
	mov	word ptr ds:[di-2], ax		;AN001; and offset
	clc					;AN001; New device
Chk_Rvst_Ret:
	pop	di
	pop	es
	pop	bx
	pop	ax
	ret
Chk_Revisit	endp

subttl end nlsfunc resident code
page
NLS_RES_END label byte
subttl initialization
page
;***************************** NLSFUNC Initialization **************************

		ASSUME	CS:NLS_INIT_CODE,SS:STACK



MAIN		PROC	FAR

		; Check for /? help (DS=PSP at EXE startup, before DS is changed)
		mov	si, 081h
NLSFUNC_SKIP_SP:
		cmp	byte ptr [si], ' '
		jne	NLSFUNC_CHK_SL
		inc	si
		jmp	NLSFUNC_SKIP_SP
NLSFUNC_CHK_SL:
		cmp	byte ptr [si], '/'
		jne	NLSFUNC_NO_HELP
		cmp	byte ptr [si+1], '?'
		jne	NLSFUNC_NO_HELP
		mov	ax, NLS_DATA
		mov	ds, ax
		lea	dx, NLSFUNC_HELP_STR
		mov	ah, 09h
		int	21h
		mov	ax, 4C00h
		int	21h
NLSFUNC_NO_HELP:
		mov	ax,NLS_DATA		;set up data segment
		mov	ds,ax
		assume	ds:NLS_DATA

		mov	PATHSEG,ax

		 call	 SYSLOADMSG		 ;does DOS version check

	      .IF <NC>
		; Keep through the actual end of resident code. Data before CS
		; includes help text and linker alignment, not just NLS_BUFFER.
		mov	ah,62h
		int	21h			; BX = this program's PSP
		mov	ax,cs
		sub	ax,bx
		mov	dx,offset NLS_RES_END
		add	dx,15
		shr	dx,1
		shr	dx,1
		shr	dx,1
		shr	dx,1
		add	dx,ax
		mov	RES_PARASIZE,dx
		call	PROCESS_PATH

	      .ELSE

		call	SYSDISPMSG

	      .ENDIF

	  .IF <NO_PARMS eq 1>  or
	  .IF <GOOD_PATH eq 1>
		call INSTALL_NLS			    ;let's install NLSFUNC
	      .IF <NC>
		   mov	EXIT_STAY,1			       ;if nothing wrong occured
	      .ENDIF
	  .ENDIF
								;determine path of exit
								;error or residency
;****************************** EXIT PROG *********************************************
		  push	  ax			  ;AN004;save existing values
		  push	  es			  ;
		  xor	  ax,ax
		  mov	  ax,es:[2ch]
		  cmp	  ax,0
		  je	  NO_FREEDOM
		  mov	  es,ax
		  mov	  ax,4900H		    ;AN004;make the free allocate mem func
		  int	  21h			  ;

NO_FREEDOM:
		  pop	  es			  ;AN004;restore existing values
		  pop	  ax			  ;

       .IF <EXIT_STAY eq 1>			       ;Terminate and stay resident
	     mov     bx,4		     ;1st close file handles
	 .REPEAT
	     mov  ah,3eh
	     int  21h
	     dec  bx
	.UNTIL <BX eq 0>

	     mov     ah,031h		     ;
	     mov     dx,RES_PARASIZE	     ;paragraphs allocated
      .ELSE
	     clc
	     mov     ah,04ch		     ;value passed to ERRORLEVEL
      .ENDIF

	     mov     al,ERROR_CODE	     ;check for an error
	     int     21H






		MAIN	ENDP

;****************************** EXIT PROG *********************************************
subttl parse
page
; On entry: ES points at the PSP
;	    DS points at NLS_DATA
;	    DX was used to calculate paragraph size
;
;	    PARSER EFFECTS  ES & DS wil be swapped
;
; Changes : ES:DI seg:off containing PARM Input Block
; to	    DS:SI seg:off containing command line
; segments
;
;
;
;
;
;
;****************************** PROCESS PATH ***********************************
;=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=I=

PROCESS_PATH	PROC	NEAR

					;to command line parms


		push	es		;;AC000;e original es (nothing)
		push	ds		;AC000;he original ds (Nls_data)
		push	ds		;save for both es & ds to point at data

		push	es		;AC000;hat's in my es the PSP value
		push	ds		;AN000;he segment id that points to my
					;es now points to data
		pop	es
					;input parameter control block (NLS_DATA)

		pop	ds		;AN000; points to the segment for
					;the command line string

		ASSUME	DS:NOTHING,ES:NLS_DATA

		xor	dx,dx
		xor	cx,cx

;***CNS
RE_START:
		mov	si,80h		;get the command line length

		mov	cl,byte ptr ds:[si]	;get the length for the counter
;
		mov	LENGTH_HOLD,cl		;save the length of the command line
;



;		.IF <dx eq 0>

		     mov     di,OFFSET NLS_BUFFER    ;
 ;		     mov     dx,1
 ;		.ELSE
 ;		     mov     di,OFFSET PATH_SPEC    ;
 ;		     mov     dx,-1
 ;		.ENDIF

		mov	si,CL_NUM	;AN000; points to the offset command
					;line input string at value 81h

		rep	movsb			;transfer command line to NLS_BUFFER

;		.IF <dx eq 1>
;		    jmp RE_START
;		.ENDIF

;***CNS




		mov	di,OFFSET NLS_PARMS    ;AN000; into ES of the PARMS INPUT
					;BLOCK
		pop	ds		       ; ds also point at NLS_DATA


		ASSUME	DS:NLS_DATA


		mov	si,OFFSET NLS_BUFFER   ;si now points to the offset command
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment

;***CNS



		xor	cx,cx		;AN000;l value should be atleast 1
		xor	dx,dx		;AN000;ut dx for input into the PARSER

	 .WHILE <PAR_RETC eq 0>
		call	SYSPARSE	;AN000;empt to parse
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment

;***CNS
	       .IF <Res_type eq 5>	;AN000;ound
		    mov USER_PATH,1		;AN000;;path specified
	       .ENDIF

		mov	PAR_RETC,AX		;AN000;;keep parsing until eoln
	 .ENDWHILE


	       .IF <PAR_RETC gt 0>		     ;AN000;;parse error
;***CNS
;		.IF <PAR_RETC eq 3>		     ;AN003;IF invalid switch return command line
;
;		   mov	   ax,10


	LEA   DI,PATH_SPEC	      ;AN003;Set PTR to look at the STRING
	PUSH  SI		      ;AN003;Save current SI index
	PUSH  AX
	MOV   AX,OLD_PTR	      ;AN003;Last locale of the end of a PARAM
	SUB   CUR_PTR,AX		   ;AN003;Get the length via the PSP
	MOV   SI,CUR_PTR
	MOV   CX,SI		      ;AN003;Save it in CX to move in the chars
	POP   AX		      ;AN003;Restore the PTR to the command line position

	MOV   SI,OLD_PTR	      ;AN003;Last locale of the end of a PARAM
	REP   MOVSB		      ;AN003;Move in the chars until no more

	LEA   DI,PATH_SPEC	      ;AN003;Set PTR to look at the STRING

	POP   SI		      ;AN003;Restore the PTR to the command line position




		   mov	   cx,1 		       ;AN003;;
		   mov	   bx,STDERR
		   mov	   dl,no_input
		   mov	   dh,PARSE_ERR_CLASS
		   mov	   ds,PATHSEG
		   mov	   si,OFFSET PARMLIST3
		   call    SYSDISPMSG
		   mov	   PARSE_ERR,1		      ;AN003;;PARSE ERROR OCCURED
;***CNS
;		.ELSE

;		   xor	   cx,cx		     ;AN000;;
;		   mov	   bx,STDERR
;		   mov	   dl,no_input
;		   mov	   dh,PARSE_ERR_CLASS
;		   mov	   ds,PATHSEG
;		   mov	   si,0
;		   call    SYSDISPMSG
;		   mov	   PARSE_ERR,1		      ;AN000;;PARSE ERROR OCCURED
;***CNS
 ;	       .ENDIF
;***CNS
	       .ELSEIF <CX eq 1>		      ;AN000;ordinal check
		      mov  GOOD_PAR,1		      ;AN000;you are at the end of the line
		   .ELSE
		      mov NO_PARMS,1		      ;AN000;there is no argument go install
	       .ENDIF				      ;AN000;NLSFUNC

       .IF <PARSE_ERR eq 0> NEAR		      ;AN000;if not true you encountered a parse error
	 .IF <GOOD_PAR eq 1> NEAR		      ;AN000;there is a parameter line available
						      ;to parse
						      ;Check the flags to see what
						      ;was returned in the return block

	       lea     di,path_spec		      ;AC000;es:di > final path_spec
						      ;that will be used after fixup

	   .IF <USER_PATH gt 0> 			  ;AC000;drive has been solved need
							  ;to check the filespec
							  ;now
		xor in_dex,in_dex			  ;AN000;clear ctr
		mov bx,Res_POFF 			  ;AN000;get file spec ptr to text
		push	ds				  ;AN000;prepare for entry
		mov ds,Res_PSEG
		mov in_dex,bx			 ;AN000;string seg value if filename
	  .ENDIF	      ;user path


	  .WHILE <Filespec_PTR ne NULL> 		 ;load chars until no more
		mov	al,FILESPEC_PTR
		mov	byte ptr es:[di],al	     ;move value into pathspec and
		inc	in_dex			     ;increment to next char position
		inc	di
	  .ENDWHILE

;************************** CNS **********************************************
;The new method of checking for a "bogus" file will be to attempt an
;open on the path_spec if pathspec exist close path and continue if
;carry set stuff error code with 02 and exit.....
;*****************************************************************************
;		push	es
		pop	ds				;into find first
		mov	si,di
		xor	cx,cx
;
		ASSUME	DS:NLS_DATA
;
		mov	byte ptr ds:[si],NULL	       ;add asciiz value
		lea	dx,PATH_SPEC		       ;check full pathname
		mov	ah,4eh
		int	21h
					;set up addressability
	    .IF <NC>
		clc				       ;ok-clear carry/exit
		mov GOOD_PATH,1
	    .ELSE
		   mov	   ax,FNF
		   mov	   cx,1 		     ;
		   mov	   bx,STDERR
		   mov	   dl,no_input
		   mov	   dh,UTILITY_MSG_CLASS
		   mov	   ds,PATHSEG
		   mov	   si,OFFSET PARMLIST1
		call	SYSDISPMSG
		mov	ERROR_CODE,02		       ;
		stc
	    .ENDIF







	 .ENDIF 					 ;EXIT on bad parse
      .ENDIF						     ;END OF PROCESS PATH


		pop	ds		;AN000;;restore original ds (NLS_DATA)
		pop	es		;AN000;;restore original es (nothing)
					;AN000;;after munging around with the PARSER

		ASSUME	DS:NLS_DATA,ES:NOTHING

		ret



PROCESS_PATH	ENDP

;

;****************************** CNS *******************************************
subttl install NLSFUNC
page
;******************************** INSTALL NLSFUNC *****************************

INSTALL_NLS	PROC	NEAR

		xor	ax,ax			  ;clear the ax
		mov	ah,MULT_NLSFUNC 	  ;load in my multiplex
		INT	2fh			  ;id value 14
		or	al,al			  ;check to see if
;		jz	DO_INSTALL		  ;hooked in the chain
; *********************** CNS *************************************************

	   .IF <Z>

						  ;Install NLSFUNC
		mov	al,2fh			  ;Get interrupt
		mov	ah,GET_INT		  ;2f in the chain
		int	21h
		mov	word ptr INT_2f_NEXT+2,ES ;store the address
		mov	word ptr INT_2f_NEXT,BX   ;to make the current
		push	ds			  ;2f handler next in
		push	cs			  ;the chain
		pop	ds			  ;set Dataseg to the Code
		mov	dx,offset NLSRES_CODE	  ;give start address
		mov	al,2fh			  ;of resident logic
		mov	ah,SET_INT		  ;set the 2f in the
		int	21h			  ;chain
		pop	ds			  ;restore original ds
						  ;terminate &
						  ;stay
;FREE THE ENVIRONMENT				  ;no then install

;		  push	  ax			  ;AN004;save existing values
;		  push	  es			  ;
;		  mov	  ah,49H		  ;AN004;make the free allocate mem func
;		  mov	  es,es:[2ch]		    ;AN004;get the segment address
;		  int	  21h			  ;
;		  pop	  es			  ;AN004;restore existing values
;		  pop	  ax			  ;

	   .ELSE
;TBR Message retriever				  ;otherwise
		   mov	   ax,ALLINS		     ;
		   mov	   cx,1 		     ;
		   mov	   bx,STDERR
		   mov	   dl,no_input
		   mov	   dh,UTILITY_MSG_CLASS
		   mov	   ds,PATHSEG
		   mov	   si,OFFSET PARMLIST2
		   call    SYSDISPMSG
		   mov	   ERROR_CODE,80	      ;UTILITY ERROR CODE
		   stc

.ENDIF

		ret

INSTALL_NLS	ENDP

msg_services <LOADmsg>
msg_services <DISPLAYmsg,CHARmsg>
msg_services <nlsfunc.cl1,nlsfunc.cl2,nlsfunc.cla>

;******************************** END OF NLS_INIT_CODE **************************
NLS_INIT_CODE	 ENDS
subttl stack
page

STACK	SEGMENT   PARA	STACK 'STACK'
	DB	  512 DUP (?)
STACK	ENDS

	END	MAIN
