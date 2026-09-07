PAGE ,132 ;
TITLE MODECOM.ASM - RS232 SUPPORT FOR THE MODE COMMAND
.XLIST
INCLUDE STRUC.INC
.LIST

;ษออออออออออออออออออออออออออออออออ  P R O L O G  อออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
;  AC000 - P2852: Loading resident code trashed CX which was used as a shift
;		  count.

;  AC001 - P3540: PS/2 only parms other than baud not being treated properly.

;บ											  บ
;ศออออออออออออออออออออออออออออออออ  P R O L O G  อออออออออออออออออออออออออออออออออออออออออผ
DISPLAY MACRO	MESSAGE
	MOV	DX,OFFSET MESSAGE
	CALL	PRINTF
ENDM
;------------------------------------------------------------------------
ABORT	MACRO
	JMP	ENDIF01
ENDM
;------------------------------------------------------------------------
INCLUDE  common.stc	   ;contains the following structure
;parm_list_entry   STRUC		   ;used by parse_parameters and invoke
;parm_type	      DB       bogus
;item_tag	      DB       0FFH
;value1 	      DW       bogus	   ;used only for filespecs and code page numbers
;value2 	      DW       bogus	   ;used only for filespecs and code page numbers
;keyword_switch_ptr   DW       0
;parm_list_entry   ENDS
;ษอออออออออออออออออออออออออออออออ E Q U A T E S ออออออออออออออออออออออออออออออออออออออออป
;บ											บ

INCLUDE modequat.inc		 ;AN000;include definition of false, machine types

AT_family   EQU 0FCH		 ;model byte for 286 boxes
DEV1	    EQU "1"              ;CHAR IN "COM1:"
DEV2	    EQU "2"              ;CHAR IN "COM2:"
DEV3	    EQU "3"              ;CHAR IN "COM3:"
DEV4	    EQU "4"              ;CHAR IN "COM4:"
OFFTO	    EQU modeto		 ;OFFSET OF MODETO IN RESIDENT CODE FROM SEGMENT
				 ; STORED AT 530H BY MODELOAD
not_specified	     EQU   0
parm_list	     EQU   [BP]
;Roughrider  EQU 05		  ;sub model byte
SPACE	    EQU " "              ;BLANK CHARACTER
;Trailboss   EQU 04		  ;sub model byte for 'Trailboss'
true	    EQU 0FFH
;Wrangler    EQU 0F8H		  ;primary model byte
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  E Q U A T E S  ออออออออออออออออออออออออออออออออออออออออผ

				; BEGINNING OF PROC MODETO)
ROM    SEGMENT AT 0
    ORG    50H
VECT14H    LABEL  DWORD 	;RS232 CALL, POINTS TO PROC MODETO WHEN
				; WHEN CODE IS RESIDENT
    ORG    400H
SERIAL_BASE	LABEL	WORD	;SERIAL PORT ADDRESSES
	ORG	530H
RESSEG	LABEL	DWORD		;VECTOR OF MODETO, WHEN RESIDENT
ROM	   ENDS
PAGE
PRINTF_CODE	   SEGMENT  PUBLIC
	   ASSUME CS:PRINTF_CODE,DS:PRINTF_CODE
;ษอออออออออออออออออออออออออออออออ  E X T R N S	ออออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
EXTRN  B_item_tag:ABS		 ;see modepars
EXTRN  baud_19200:BYTE
EXTRN  busy_retry_active:ABS	 ;see invoke.asm
EXTRN  E_item_tag:ABS		 ;see modepars
EXTRN  eight_item_tag:ABS	 ;see modepars
EXTRN  ERR1:WORD
EXTRN  even_item_tag:ABS	 ;see modepars
EXTRN  error_retry_active:ABS	 ;see invoke.asm
EXTRN  five_item_tag:ABS	 ;see modepars
EXTRN  fourtyeighthundred_item_tag:ABS	   ;see modepars.asm
EXTRN  fourtyeighthundred_str:BYTE
EXTRN  illegal_device_ptr:WORD	  ;see modesubs.inc
EXTRN  INITMSG:BYTE,DEVICE:BYTE,PPARITY:BYTE,PDATA:BYTE,PSTOP:BYTE,PPARM:BYTE
EXTRN  keyword:ABS
EXTRN  machine_type:BYTE	 ;see 'rescode'
EXTRN  mark_item_tag:ABS	 ;see modepars
EXTRN  MODELOAD:NEAR
EXTRN  MODETO:WORD
EXTRN  new_com_initialize:BYTE		     ;flag indicating that a PS/2 only parm was specified
EXTRN  nineteentwohundred_item_tag:ABS	     ;see modepars.asm
EXTRN  nineteentwohundred_str:BYTE	;see modepars.asm
EXTRN  ninetysixhundred_item_tag:ABS
EXTRN  ninetysixhundred_str:BYTE
EXTRN  no_retry_active:ABS	 ;see invoke.asm
EXTRN  noerror:byte		 ;boolean indicating success of previous actions
EXTRN  none_item_tag:ABS	 ;see modepars
EXTRN  onefifty_str:BYTE
EXTRN  oneten_item_tag:ABS	 ;see modepars.asm
EXTRN  oneten_str:BYTE
EXTRN  onefifty_item_tag:ABS	 ;see modepars.asm
EXTRN  one_point_five_item_tag:ABS     ;see modepars.asm
EXTRN  one_point_five_str:BYTE	  ;see modesubs.inc
EXTRN  p_item_tag:ABS		 ;see modepars.asm
EXTRN  parm_lst:BYTE		 ;parm_list_entry  max_pos_parms DUP (<>)
EXTRN  parms_form:BYTE
EXTRN  pstop_ptr:WORD		;see modedefs.inc
EXTRN  odd_item_tag:ABS 	 ;see modepars
EXTRN  one_item_tag:ABS 	 ;see modepars
EXTRN  PBAUD_ptr:WORD		 ;see 'modemes'
EXTRN  PRINTF:NEAR
EXTRN  PARM1:BYTE,PARM2:BYTE,PARM3:BYTE,MODE:BYTE,FLAG:BYTE
;PARM1	DB	10 DUP(0)
;PARM2	DB	0
;PARM3	DB	0
;MODE	DB	0
;FLAG	DB	0
EXTRN  R_item_tag:ABS
EXTRN  RATEMSG:WORD	  ;CR,LF,"Invalid baud rate specified",BEEP,CR,LF,"$"
EXTRN  ready_retry_active:ABS	 ;see invoke.asm
;EXTRN	RES_MODEFLAG:ABS	;RETRY FLAG IN RESIDENT CODE, (OFFSET FROM
EXTRN  res_com_retry_type:BYTE	 ;retry type flag, displacement from address pointed to by 50:30 when code is resident, see rescode
EXTRN  seven_item_tag:ABS	  ;see modepars
EXTRN  sixhundred_item_tag:ABS	   ;see modepars.asm
EXTRN  sixhundred_str:BYTE
EXTRN  six_item_tag:ABS       ;see modepars
EXTRN  space_item_tag:ABS     ;see modepars
EXTRN  submodel_byte:BYTE     ;see 'rescode'
EXTRN  threehundred_item_tag:ABS     ;see modepars.asm
EXTRN  threehundred_str:BYTE
EXTRN  twelvehundred_item_tag:ABS     ;see modepars.asm
EXTRN  twelvehundred_str:BYTE
EXTRN  twentyfourhundred_str:BYTE
EXTRN  twentyfourhundred_item_tag:ABS	  ;see modepars.asm
EXTRN  two_item_tag:ABS 	;see modepars
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  E X T R N S	ออออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออออ  P U B L I C S  ออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
PUBLIC	baud_index		;holder of the index in the parm list of the baud rate requested
PUBLIC	data_bits_index 	;set by invoke
PUBLIC	MODECOM
PUBLIC	parity_index		;set by invoke
PUBLIC	SERIAL_BASE		;Make available to RESCODE and MAIN
PUBLIC	retry_index		;make available to analyze_and_invoke
PUBLIC	setcom			;get it listed in the link map
PUBLIC	setto			;get it listed in link map for debugging
PUBLIC	stop_bits_index 	;set by invoke
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  P U B L I C S  ออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออออออออ  D A T A	ออออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
;THESE FOLLOWING BAUD RATES REPRESENT THE 1ST 2 CHAR
baud_index  DW	     TYPE parm_list_entry ;holder of the index into the parm list of the baud rate
data_bits_index DW   0	   ;holder of the index into the parm list of the data bits
parity_index	DW   0	   ;holder of the index into the parm list of the parity
stop_bits_index DW   0	   ;holder of the index into the parm list of the stop bits
retry_index	DW   0
;INITMSG    DB	  CR,LF
;	    DB	  "COM"
;DEVICE     DB	  " "
;	    DB	  ": "             ;SEPARATOR BLANK
;PBAUD	    DB	  4 DUP(" ")
;	    DB	  ","    ;SEPARATOR
;PPARITY    DB	  "e"    ;DEFAULT IS EVEN PARITY
;	    DB	  ","    ;SEPARATOR
;PDATA	    DB	  "7"    ;DEFAULT IS 7 DATA BITS PER BYTE
;	    DB	  ","    ;SEPARATOR
;PSTOP	    DB	  "1"    ;DEFAULT FOR BAUD > 110, CHANGED TO 2 FOR 110
;	    DB	  ","    ;SEPARATOR
;PPARM	    DB	  " "
;	    DB	  CR,LF,"$"    ;END OF 'INITMSG'
;บ											  บ
;ศอออออออออออออออออออออออออออออออออออ  D A T A	ออออออออออออออออออออออออออออออออออออออออออผ
SUBTTL SET UP FOR SERIAL RETRY
PAGE
;
;
;-------------------------------------------------------------------------------
;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฟ
;ณ									       ณ
;ณ SETTO								       ณ
;ณ -----								       ณ
;ณ									       ณ
;ณ  Set the resident retry flag to type of retry active for comx.	       ณ
;ณ									       ณ
;ณ  INPUT:  device - holds '1', '2', '3' or '4' (ascii) for x of lptx.         ณ
;ณ	    retry_index - holds index value for the parsed retry parameter.    ณ
;ณ	    resseg - holds offset of resident code in memory		       ณ
;ณ	    res_com_retry_type - holds offset of com retry flag in resident    ณ
;ณ	      code.							       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  RETURN: pparm - set to 'P', 'B', 'R', 'E', or '-' for type of retry active.ณ
;ณ	    flag in resident code set					       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  MESSAGES: none.							       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  REGISTER								       ณ
;ณ  USAGE:	AL - new setting for resident flag. (see RESCODE.SAL for       ณ
;ณ		     format)						       ณ
;ณ		CL - shift bit count					       ณ
;ณ		ES - holds segment of resident code			       ณ
;ณ		BP - offset of parameter list				       ณ
;ณ		DI - offset of retry index within parameter list	       ณ
;ณ		DL - current resident flag setting			       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  PSUEDO CODE:							       ณ
;ณ									       ณ
;ณ	SAVE REGISTERS							       ณ
;ณ	SET UP SEGMENT REGISTER AND BIT MASKS				       ณ
;ณ	IF <RETRY REQUESTED>						       ณ
;ณ	   SET UP PARAMETER LIST STRUCTURE				       ณ
;ณ	   SET BIT MASK FOR TYPE OF RETRY AND SET pparm TO PROPER LETTER       ณ
;ณ	   IF <RESIDENT CODE IS NOT LOADED>				       ณ
;ณ	      LOAD RESIDENT CODE					       ณ
;ณ	   ENDIF							       ณ
;ณ	   GET CURRENT com_lpt_retry_type				       ณ
;ณ	   SET AND STORE NEW com_lpt_retry_type 			       ณ
;ณ	ELSEIF <RESIDENT CODE ALREADY LOADED>				       ณ
;ณ	   GET CURRENT com_lpt_retry_type				       ณ
;ณ	   IF <POSITIONAL PARAMETER SPECIFIED>				       ณ
;ณ	      SET FLAG TO ZERO, SET pparm TO PROPER LETTER		       ณ
;ณ	   ELSE 							       ณ
;ณ	      SET pparm TO PROPER LETTER FOR CURRENT SETTING		       ณ
;ณ	   ENDIF							       ณ
;ณ	ELSE								       ณ
;ณ	   SET pparm TO '-'                                                    ณ
;ณ	ENDIF								       ณ
;ณ	RESTORE REGISTERS						       ณ
;ณ	RETURN								       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  SIDE EFFECT: Loads resident code if it is needed and has not been loaded.  ณ
;ณ									       ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤู
;
SETTO	 PROC	 NEAR
      PUSH ES			;save registers
      PUSH DI
      PUSH AX
      PUSH DX
      XOR  AX,AX		;clear a reg
      MOV  ES,AX		;set to segment at 0
      MOV  CL,device
      AND  CL,07H
      DEC  CL
      SHL  CL,1
      MOV  DH,11111100B 	;set bit mask to clear old flag setting
      ROL  DH,CL
      .IF <retry_index NE 0> THEN			;retry specified, set
							;  byte in resident code
	 MOV  DI,retry_index				;  to proper setting.
							;  if code is not loaded,
	 .SELECT					;  loaded it.
	 .WHEN <parm_list[DI].item_tag EQ P_item_tag>
	    MOV  AL,busy_retry_active
	    MOV  pparm,'p'
	 .WHEN <parm_list[DI].item_tag EQ E_item_tag>
	    MOV  AL,error_retry_active
	    MOV  pparm,'e'
	 .WHEN <parm_list[DI].item_tag EQ B_item_tag>
	    MOV  AL,busy_retry_active
	    MOV  pparm,'b'
	 .WHEN <parm_list[DI].item_tag EQ R_item_tag>
	    MOV  AL,ready_retry_active
	    MOV  pparm,'r'
	 .ENDSELECT
	 .IF <<WORD PTR ES:resseg> EQ 0000H> THEN
	    PUSH  CX					;save shift count
	    CALL modeload				;load the resident code
	    POP   CX					;restore shift count
	 .ENDIF
	 MOV  ES,ES:WORD PTR resseg[2]
	 MOV  DL,BYTE PTR ES:res_com_retry_type
							;get the old setting
	 ROL  AL,CL
	 AND  DL,DH
	 OR   DL,AL
	 MOV  BYTE PTR ES:res_com_retry_type,DL 	;store the new setting
      .ELSEIF <<WORD PTR ES:resseg> NE 0000H> THEN	;if code is loaded but no
							;  retry is specified then
	 MOV  ES,ES:WORD PTR resseg[2]
	 MOV  DL,BYTE PTR ES:res_com_retry_type
	 .IF <parms_form NE keyword>			;if 'NONE' was specified
							;  with positional parameter
	    AND  DL,DH					;  set bits to zero
	    MOV  BYTE PTR ES:res_com_retry_type,DL
	 .ELSE						;else update pparm with
							;  current retry type
	    NOT  DH
	    AND  DL,DH
	    SHR  DL,CL
	    .SELECT					;set pparm to proper letter
	    .WHEN <DL EQ no_retry_active>
	       MOV  pparm,'-'
	    .WHEN <DL EQ error_retry_active>
	       MOV  pparm,'e'
	    .WHEN <DL EQ busy_retry_active>
	       MOV  pparm,'b'
	    .WHEN <DL EQ ready_retry_active>
	       MOV  pparm,'r'
	    .ENDSELECT
	 .ENDIF
      .ELSE						;no retry, no code resident
	 MOV  pparm,'-'
      .ENDIF
      POP  DX
      POP  AX			;restore registers
      POP  DI
      POP  ES
      RET
SETTO ENDP



SUBTTL SET SERIAL PROTOCOL
PAGE

;------------------------------------------------------------------------------

;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฟ
;ณ									       ณ
;ณ SETCOM								       ณ
;ณ ------								       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  INPUT:								       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  RETURN:								       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  MESSAGES: none.							       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  REGISTER								       ณ
;ณ  USAGE:								       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  ASSUMPTIONS: All parms have been checked for validity as being possible andณ
;ณ		 supported on the machine.				       ณ
;ณ									       ณ
;ณ									       ณ
;ณ									       ณ
;ณ  SIDE EFFECT:							       ณ
;ณ									       ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤู

SETCOM PROC    NEAR
MOV   BP,OFFSET parm_lst   ;address the parm list via parm_list which is [BP]
MOV    DI,baud_index	    ;DI=index into parm list of the baud rate entry

.SELECT 		   ;prepare AL for old init and CL for new init

   .WHEN <parm_list[DI].item_tag EQ oneten_item_tag>
      MOV   AL,0
      MOV   CL,0
      MOV   pbaud_ptr,OFFSET oneten_str
   .WHEN <parm_list[DI].item_tag EQ onefifty_item_tag> THEN
      MOV   AL,00100000B
      MOV   CL,1
      MOV   pbaud_ptr,OFFSET onefifty_str
   .WHEN <parm_list[DI].item_tag EQ threehundred_item_tag> THEN
      MOV   AL,01000000B
      MOV   CL,2
      MOV   pbaud_ptr,OFFSET threehundred_str
   .WHEN <parm_list[DI].item_tag EQ sixhundred_item_tag> THEN
      MOV   AL,01100000B
      MOV   CL,3
      MOV   pbaud_ptr,OFFSET sixhundred_str
   .WHEN <parm_list[DI].item_tag EQ twelvehundred_item_tag> THEN
      MOV   AL,10000000B
      MOV   CL,4
      MOV   pbaud_ptr,OFFSET twelvehundred_str
   .WHEN <parm_list[DI].item_tag EQ twentyfourhundred_item_tag> THEN
      MOV   AL,10100000B
      MOV   CL,5
      MOV   pbaud_ptr,OFFSET twentyfourhundred_str
   .WHEN <parm_list[DI].item_tag EQ fourtyeighthundred_item_tag> THEN
      MOV   AL,11000000B
      MOV   CL,6
      MOV   pbaud_ptr,OFFSET fourtyeighthundred_str
   .WHEN <parm_list[DI].item_tag EQ ninetysixhundred_item_tag> THEN
      MOV   AL,11100000B
      MOV   CL,7
      MOV   pbaud_ptr,OFFSET ninetysixhundred_str
   .WHEN <parm_list[DI].item_tag EQ nineteentwohundred_item_tag> NEAR THEN   ;handle 19200 case if 19, 19200, 19.2 or 19.2K specified
      MOV   CL,8	      ;value for 19200 baud, no old equivalent
      MOV   pbaud_ptr,OFFSET nineteentwohundred_str

.ENDSELECT
;	   AL IS:  XXX00000 for the baud rate, CL has appropriate value for baud

MOV   DI,parity_index
.IF <parm_list[DI].item_tag EQ none_item_tag> THEN
   MOV PPARITY,"n"          ;set up message for no PARITY
   MOV	 BH,0		    ;AL already set properly for old init
.ELSEIF <parm_list[DI].item_tag EQ odd_item_tag> THEN
   MOV PPARITY,"o"          ;set up message for odd PARITY
   OR	 AL,08H 	    ;PUT THE 000XX000 BITS TO AL PARM WHERE XX=01 FOR PARITY=ODD
   MOV	 BH,1		    ;new initialize
.ELSEIF <parm_list[DI].item_tag EQ space_item_tag> THEN
   MOV PPARITY,"s"          ;set up message for space PARITY
   MOV	 BH,4		    ;SPACE not supported in old init
.ELSEIF <parm_list[DI].item_tag EQ mark_item_tag> THEN
   MOV PPARITY,"m"          ;set up message for mark PARITY
   MOV	 BH,3		    ;MARK parity not supported in old init
.ELSE			   ;not specified or asked for even
   MOV PPARITY,"e"          ;set up message for even PARITY, the default if not specified
   OR	 AL,18H 	    ;PUT THE 000XX000 BITS TO AL PARM WHERE XX=11 FOR PARITY=EVEN
   MOV	 BH,2			 ;even parity for new initialize
.ENDIF

MOV   DI,data_bits_index
.IF <parm_list[DI].item_tag EQ five_item_tag> THEN
   MOV	 pdata,"5"            ;set up message for 5 bits
   MOV	 CH,0		      ;not old init for 5 data bits
.ELSEIF <parm_list[DI].item_tag EQ six_item_tag> THEN
   MOV	 pdata,"6"            ;set up message for 6 bits
   MOV	 CH,1		      ;no old init for 6 data bits
.ELSEIF <parm_list[DI].item_tag EQ eight_item_tag> THEN
   MOV	 pdata,"8"            ;set up message for 8 bits
   OR	 AL,03H 	    ;IN THE 000000XX POSITION, SET XX=11 TO MEAN 8 DATA BITS
   MOV	 CH,3
.ELSE			      ;asked for 7 or skipped the parm and will get 7 as default
   OR	 AL,02H 	    ;IN THE 000000XX POSITION, SET XX=10 TO MEAN 7 DATA BITS
   MOV	 CH,2		      ;message already set up for 7 bits
.ENDIF

;PUT THE NO. STOP BITS TO AL PARM IN THE 00000X00 POSITION and BL for new init
MOV   DI,stop_bits_index
MOV   BL,0		      ;assume stop bits was 1, message already set up
.SELECT
   .WHEN <parm_list[DI].item_tag EQ two_item_tag>
      MOV   pstop,"2"         ;set up message for 2 stop bits
      MOV   BL,1	      ;value for two or 1.5

   .WHEN <parm_list[DI].item_tag EQ one_point_five_item_tag>
      MOV   pstop_ptr,OFFSET one_point_five_str 	       ;set up message for 1.5 stop bits
      MOV   BL,1	      ;new init for 1.5

   .WHEN <stop_bits_index EQ not_specified>		 ;if stop bits not specified
      MOV   DI,baud_index
      .IF <parm_list[DI].item_tag EQ oneten_item_tag>	  ;BAUD=110 SPECIFIED THEN SET DEFAULT STOP BITS TO TWO
	 OR    AL,04H		  ;TURN ON BIT IN 00000X00 POSITION TO REQUEST 2 STOP BITS
	 MOV   pstop,"2"         ;set up message for 2 stop bits
      .ENDIF			 ;FOR STOPBITS=1, LEAVE THAT BIT OFF, message already set by modecom

;  .OTHERWISE specified 1, everything set up

.ENDSELECT		   ;IF not 1.5 or two, already set up for 1
.IF <new_com_initialize EQ true> THEN
   XOR	 AL,AL		   ;ask for no break
   MOV	 AH,4		   ;new set baud BIOS call
.ELSE			   ;old style com initialization
   XOR	 AH,AH		   ;AH=0 requests initialization
.ENDIF

;SET DX PARM TO REQUEST WHICH COM DEVICE
 XOR   DX,DX
 MOV   DL,DEVICE	       ;device set by modepars in first_parm_case:
 AND   DL,07		       ;convert to binary 1 thru 4
 DEC   DL		       ;put in BIOS digestable 0 thru 3
;	    AH ALREADY IS 0 or 4, WHICH REQUESTS
;	    INITIALIZATION OF THE RS232
;	    ACCORDING TO PARMS IN AL and/or BX and CX.
 .IF <noerror EQ true> THEN
    INT 14H		       ;INIT THE RS232
;	    NOW THAT THE RS232 IS INITIALIZED,
    CALL    SETTO	 ;LOOK AT P PARM, MAYBE TIMEOUT TO BE RETRIED
    DISPLAY INITMSG	       ;TELL USER RS232 IS INITIALIZED
 .ENDIF

     RET
SETCOM ENDP
SUBTTL
PAGE

MODECOM PROC	NEAR


       MOV    AL,DEVICE 	  ;AL= DEVICE ID OF "1", "2", "3" or "4"
       AND    AL,07		  ;TRANSLATE TO BINARY
       DEC    AL		  ;PUT IN ZERO BASE
       SAL    AL,1		  ;POSITION OF PORT ADDRESS WORD (2*AL)
       XOR    AH,AH		  ;CLEAR AH
       MOV    SI,AX
       XOR    AL,AL		  ;CLEAR AX
       PUSH   DS
       MOV    DS,AX
       CMP    WORD PTR DS:SERIAL_BASE[SI],0	  ;SEE IF THE COM PORT EXISTS
       POP    DS
       JNE    THEN01A
	  MOV	DI,0			  ;the device name is always the first parm
	  MOV	BP,OFFSET parm_lst   ;address the parm list via parm_list which is [BP]
	  MOV	CX,parm_list[DI].value1
	  MOV  illegal_device_ptr,CX
	  DISPLAY err1			 ;AN000;"Illegal device name - COMX"
	  MOV  noerror,false
	 ABORT
;
THEN01A:

;		     DEFINE DEFAULTS:
	 MOV PSTOP,"1"            ;ONE STOP BIT, OK FOR BAUD>110
	 MOV PDATA,"7"            ;7 DATA BITS
	 MOV PPARM,"-"            ;NO SERIAL TIMEOUT RETRY
;

;WE HAVE THE INFORMATION NEEDED TO INITIALIZE THE RS232 DEVICE
;
	 CALL SETCOM		  ;SET THE RS232 DEVICE
;
;    : ELSE ,SINCE COUNT WAS NOT BIG ENUF
ENDIF01:			 ;jump to here if the port does not exist
     RET			  ;RETURN TO MODE MAIN ROUTINE
MODECOM ENDP
PRINTF_CODE	ENDS
    END
