;m
	PAGE	,132			;
	TITLE	ANALYZE_AND_INVOKE - call appropriate routine based on request
.XLIST
   INCLUDE STRUC.INC
.LIST
;.SALL


;ษออออออออออออออออออออออออออออออออ  P R O L O G  อออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
;  AC000 - P2944: Was displaying the lines and column settings for CON even
;		  though couldn't get them when ANSI.SYS isn't loaded.  Now
;		  check if ANSI loaded before trying to display the settings.

;  AC002 - P3331: ES was getting zeroed, which caused problems later in MODECP.

;  AC003 - P3541: The retry status routine was assuming different format than
;		  the retry type byte was in.  I fixed the status checking
;		  routine.

;  AX004 - P3982: The screen was being cleared after the "Unable to shift
;		  screen ..." message.

;  AC005 - P4934: The multiplex number for ANSI.SYS was changed due to a
;     5/20/88	  conflict with a Microsoft product that has already been
;		  shipped.

;บ											  บ
;ศออออออออออออออออออออออออออออออออ  P R O L O G  อออออออออออออออออออออออออออออออออออออออออผ
;ษออออออออออออออออออออออออออออออออ  M A C R O S  อออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
GET_EXTENDED_ERROR   MACRO
MOV   BX,0		;level for 3.00 to 4.00
MOV   AH,59H		;function number for get extended error
INT   21H
ENDM
BREAK	MACRO	X
   JMP	   endcase_&X
ENDM
DISPLAY MACRO	MESSAGE
	MOV	DX,OFFSET MESSAGE
	CALL	PRINTF
ENDM
;บ											  บ
;ศออออออออออออออออออออออออออออออออ  M A C R O S  อออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออออ  E Q U A T E S  ออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
INCLUDE modequat.inc
ANSIINT2F   EQU   1AH	   ;INT 2F multiplex number for ANSI.SYS
ASCII_0  EQU   "0"         ;change one based binary printer number into ASCII printer number
ASCII_1  EQU   "1"
B	 EQU   2	   ;retry setting
blink	 EQU   0000H	  ;value for flags field of IOCTL data block
busy_retry_active	EQU   2     ;indicates bust retry is active
check_installed   EQU	0  ;request installed state for INT2F (ANSI)
;COLUMNS	   EQU	 00000010B   ;
com1_retry_type_status	EQU   0     ;request for retry status on com1
com2_retry_type_status	EQU   2     ;request for retry status on com2
com3_retry_type_status	EQU   4     ;request for retry status on com3
com4_retry_type_status	EQU   6     ;request for retry status on com4
display_device EQU   3	   ;type of device, used for calls to IOCTL 0C function
E	 EQU   1	   ;retry setting
error_retry_active	EQU   1     ;indicates error retry is active
false	 EQU   00H
font_not_loaded      EQU   31	    ;return from IOCTL 0C (via ext err) indicating DISPLAY.SYS don't have necessary font loaded
get_current_settings EQU   07FH     ;request for IOCTL 0C call
installed	     EQU   0FFH     ;return from get_installed_state function
intense  EQU   0001H	  ;value for flags field of IOCTL data block
IOCTL0C  EQU   [SI]
;LINES		   EQU	 00000001B   ;flag for IOCTL0C_functions_requested
lowercase	     EQU   020H     ;when ORed with char value it changes it to lowercase
LPT1		     EQU   1	    ;mask for input to display_device_reroute_status, see modeecho
LPT2		     EQU   2	    ;mask for input to display_device_reroute_status, see modeecho
LPT3		     EQU   4	    ;mask for input to display_device_reroute_status, see modeecho
lpt1_retry_type_status	EQU   0     ;request for retry status on lpt1
lpt2_retry_type_status	EQU   1     ;request for retry status on lpt2
lpt3_retry_type_status	EQU   2     ;request for retry status on lpt3
MODE_INT2F_MULTIPLEX_NUMBER   EQU   0
no_retry       EQU   3	   ;retry setting
no_retry_active 	EQU   0     ;indicates no retry active on device
not_supported_on_machine   EQU	 29 ;return from IOCTL 0C (via ext err) indicating hardware don't support the function
parm_list_BX   EQU   [BX]
prn_ports_attached	EQU   CL    ;used in printer_reroute_case and check_prn_ports_attached
R	 EQU   3	   ;retry setting for com ports
ready_retry_active	EQU   3     ;indicates ready retry is active
redirected		EQU   2     ;network puts a 2 in printer address word for printers redirected
rerouted_printer_mask	EQU   BL    ;holds the mask to check ptsflag1 with, see modeecho.asm
returned_retry_type	EQU   AL    ;holds the returned status value
set_display_characteristics   EQU   05FH  ;request for IOCTL 0C call
status	 EQU   0		    ;request for modecp
StdOut			equ	1
text	 EQU   01	   ;mode field of IOCTL 0C call indicating screen mode type (vs APA mode)
true	 EQU   0FFH
unspecified		EQU   0FFH  ;state of item_tags in parm_list if the positonal parm was not specified
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  E Q U A T E S  ออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออ  S T R U C T U R E S  ออออออออออออออออออออออออออออออออออออป
;บ											  บ
des_strt_packet   STRUC
   des_strt_pkfl  DW	0000	       ;assume a filename specified
   des_strt_pklen DW	02	       ;start with size of 'des_strt_pknum'
   des_strt_pknum DW	0	       ;number of cp numbers in the packet
   des_strt_pkcp1 DW	-1	       ;code page number for 1st slot
   des_strt_pkcp2 DW	-1
   des_strt_pkcp3 DW	-1
   des_strt_pkcp4 DW	-1
   des_strt_pkcp5 DW	-1
   des_strt_pkcp6 DW	-1
   des_strt_pkcp7 DW	-1
   des_strt_pkcp8 DW	-1
   des_strt_pkcp9 DW	-1
   des_strt_pkcpA DW	-1
   des_strt_pkcpB DW	-1
   des_strt_pkcpC DW	-1	       ;code page number for 12th slot
des_strt_packet   ENDS
;The info_level is 0 on input, and contains a return code on exit. If carry set
;and 2 then the requested function is not supported on this machine.  If carry
;set and 3 then DISPLAY.SYS does not have the appropriate RAM font loaded to
;support the requested function.
IOCTL0C_def STRUC
info_level  DB	  0	;return code: 0 on input, 1 ?, 2 or 3 as returns
	    DB	  0	;reserved
data_length DW	  14	;length of the data block not including this field
flags	    DW	  0	;filled with intense or blink
mode	    DB	  text	;filled with text, may be returned as 2 which means APA
	    DB	  0	;reserved
colors	    DW	  16	;0 means monochrome
	    DW	  bogus ;width in pixels for APA modes
	    DW	  bogus ;length in pixels for APA modes
cols	    DW	  bogus ;nubmer of text columns
rows	    DW	  bogus ;number of text rows
IOCTL0C_def ENDS
INCLUDE COMMON.STC	;includes the following strucs
;codepage_parms STRUC
;   cp_device	   DW	 ?
;   des_pack_ptr   DW	 ?
;   font_filespec  DW	 ?
;   request_typ    DW	 ?
;codepage_parms ENDS
;parm_list_entry   STRUC		   ;used by parse_parameters and invoke
;parm_type	      DB       bogus
;item_tag	      DB       0FFH
;value1 	      DW       bogus	   ;used only for filespecs and code page numbers
;value2 	      DW       bogus	   ;used only for filespecs and code page numbers
;keyword_switch_ptr   DW    0
;parm_list_entry   ENDS
;บ											  บ
;ศอออออออออออออออออออออออออออออ  S T R U C T U R E S  ออออออออออออออออออออออออออออออออออออผ
ROM    SEGMENT AT 0
	ORG	530H
resseg	LABEL	DWORD		;location of resident mode code vector
ROM    ENDS
	PAGE
PRINTF_CODE SEGMENT PUBLIC
	ASSUME	CS:PRINTF_CODE,DS:PRINTF_CODE,SS:PRINTF_CODE
;ษอออออออออออออออออออออออออออออออ  P U B L I C S  ออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
PUBLIC	 analyze_and_invoke	 ;make available to "MAIN"
PUBLIC	 busy_retry_active	      ;used by modecom
PUBLIC	 cp_cb			    ;modepars needs to set the font file name
PUBLIC	 error_retry_active	       ;used by modecom
PUBLIC	 initialize_printer_port_case
PUBLIC	 no_retry_active	    ;used by modecom
PUBLIC	 parm_list_holder	    ;used by modeprin
PUBLIC	 ready_retry_active	       ;used by modecom
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  P U B L I C S  ออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออออ  E X T R N S	ออออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
EXTRN	 ANSI_not_loaded:BYTE	   ;see modedefs.inc
EXTRN	 BAUD_equal:BYTE			;the string "BAUD=", see modepars
EXTRN	 BAUD_index:WORD			;see modecom.asm
EXTRN	 B_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 BW40:NEAR	      ;see modedefs.inc
EXTRN	 BW40_item_tag:ABS		 ;see MODEPARS.ASM
EXTRN	 BW80:NEAR	      ;see modedefs.inc
EXTRN	 BW80_item_tag:ABS		 ;see MODEPARS.ASM
EXTRN	 busy_status:ABS
EXTRN	 close:ABS	      ;EQU  3EH   ;CLOSE A FILE HANDLE,see modecpeq.inc
EXTRN	 columns_ptr:WORD		  ;see modesubs.inc
EXTRN	 CO40:NEAR	      ;see modedefs.inc
EXTRN	 CO40_item_tag:ABS		 ;see MODEPARS.ASM
EXTRN	 CO80:NEAR	      ;see modedefs.inc
EXTRN	 CO80_item_tag:ABS		 ;see MODEPARS.ASM
EXTRN	 codepage_index_holder:WORD	     ;see MODEPARS.ASM
EXTRN	 codepage_item_tag:ABS		     ;see MODEPARS.ASM
EXTRN	 columns_equal:BYTE		 ;see MODEPARS.ASM
EXTRN	 columns_equal_msg:BYTE 	     ;see MODEdefS.inc
EXTRN	 columns_holder:BYTE		  ;holder for printer chars per line (binary) value, see modeprin
EXTRN	 COLS_equal:BYTE		 ;see MODEPARS.ASM
EXTRN	 columns_item_tag:ABS		    ;see MODEPARS.ASM
EXTRN	 COM1_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 COM2_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 COM3_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 COM4_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 COMX:ABS			     ;one of two possible values for "device_type"
EXTRN	 CON_str:BYTE			     ;"CON"see MODEPARS.ASM
EXTRN	 CRLF:BYTE			 ;see MODEDEFS.ASM, used before "Invalid parameter - " for consistent spacing
EXTRN	 data_bits_index:WORD		     ;see modecom.asm
EXTRN	 DATA_equal:BYTE		       ;see MODEPARS.ASM
EXTRN	 DELAY_equal:BYTE		     ;see MODEPars.asm
EXTRN	 DEL_equal:BYTE 		     ;see MODEPARS.ASM
EXTRN	 des_start_packet:WORD	       ;AX000; des_strt_packet <>, see modepars
EXTRN	 device:BYTE		       ;holder of com number for invoke and modeecho
EXTRN	 device_name:WORD
EXTRN	 device_type:BYTE		     ;see MODEPARS.ASM
EXTRN	 dev_name_size:WORD		     ;see MODEPARS.ASM
EXTRN	 dev_open_mode:ABS	       ;read write access
EXTRN	 display_printer_reroute_status:NEAR ;see modeecho.asm
EXTRN	 eighty_item_tag:ABS		     ;see MODEPARS.ASM
EXTRN	 eighty_str:BYTE		     ;see MODEPARS.ASM
EXTRN	 error_status:ABS		     ;see MODEPRIN
EXTRN	 five_char_underline:BYTE	     ;see modedefs.inc
EXTRN	 four_char_underline:BYTE	     ;see modedefs.inc
EXTRN	 function_not_supported:BYTE		;see modedefs.inc
EXTRN	 err1:BYTE			     ;see modedefs.inc
EXTRN	 E_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 fourty_item_tag:ABS		     ;see MODEPARS.ASM
EXTRN	 fourty_str:BYTE		     ;see MODEPARS.ASM
EXTRN	 handle_40_or_80:NEAR			;see modescrn
EXTRN	 illegal_device_ptr:WORD	     ;see modesubs.inc
EXTRN	 keyword:ABS			     ;see MODEPARS
EXTRN	 invalid_number_of_parameters:WORD
;EXTRN	  invalid_parameter:WORD      ;<CR><LF>"Invalid parameter '????'",beep
EXTRN	 len_COMX_str:ABS		     ;see MODEPARS.ASM
EXTRN	 len_CON_str:ABS		     ;see MODEPARS.ASM
EXTRN	 len_LPTX_str:ABS		     ;see MODEPARS.ASM
EXTRN	 L_item_tag:ABS 		     ;see MODEPARS.ASM
EXTRN	 LINES_equal:BYTE		    ;see MODEPARS.ASM
EXTRN	 LINES_equal_msg:BYTE			;see MODEDEFS.INC
EXTRN	 lines_item_tag:ABS		  ;see MODEPARS.ASM
EXTRN	 long_underline:BYTE		     ;see modedefs.inc
EXTRN	 lptno:BYTE			  ;holder of printer number for invoke and modeecho
EXTRN	 lpt1_retry_type:BYTE		     ;see RESCODE
EXTRN	 LPT1_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 LPT2_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 LPT3_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 notredpt:BYTE			  ;printer number in "LPTn not rerouted"
EXTRN	 max_request_type:ABS		     ;see MODEPARS.ASM
EXTRN	 modecom:NEAR
EXTRN	 modecp:NEAR
EXTRN	 modeecho:NEAR
EXTRN	 modeecno:NEAR
EXTRN	 modeprin:NEAR
EXTRN	 modify_resident_code:NEAR		   ;see modeprin
EXTRN	 MONO:NEAR	      ;see modedefs.inc
EXTRN	 MONO_item_tag:ABS		 ;see MODEPARS.ASM
EXTRN	 no_retry_flag:ABS		  ;see MODEPRIN
EXTRN	 noerror:BYTE
EXTRN	 none_item_tag:ABS		     ;see modepars.asm
EXTRN	 none_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 offending_parameter:BYTE	;see MODEMES
EXTRN	 OFF_item_tag:ABS		      ;see pares.asm
EXTRN	 off_str:BYTE			    ;see MODEPARS.ASM
EXTRN	 onethirtytwo_item_tag:ABS	  ;see modepars.asm
EXTRN	 ON_item_tag:ABS		     ;see pares.asm
EXTRN	 on_str:BYTE			   ;see MODEPARS.ASM
EXTRN	 open:ABS		    ;open a device handle, see modecpeq.inc
EXTRN	 parity_equal:BYTE	    ;see modepars.asm
EXTRN	 parity_index:WORD	    ;see modecom
EXTRN	 parm2:BYTE		    ;see MODEPRIN.ASM
EXTRN	 parm3:BYTE		    ;see MODEPARS.ASM
;EXTRN	  parm_lst:BYTE 	     ;parm_list_entry  max_pos_parms DUP (<>), see MODEPARS.ASM
EXTRN	 parms_form:byte	    ;indicator of whether the parameters were entered as positionals or as keywords
EXTRN	 pbaud_ptr:WORD 	;AN000;;pointer to the baud rate string in the initialization message for COM, see modesubs.inc
EXTRN	 pdata:BYTE		       ;see modesubs.inc
EXTRN	 pparity_ptr:WORD	       ;see modesubs.inc
EXTRN	 pparm:BYTE		       ;used by modecom and for message, see modesubs.inc
EXTRN	 prepare:ABS
EXTRN	 prepare_item_tag:ABS		    ;see MODEPARS.ASM
EXTRN	 PRINTR:WORD		 ;PRINTER BASE (40:8), HOLDS PORT ADDRESSES OF PRINTER CARDS
EXTRN	 pstop_ptr:WORD 	       ;see modesubs.inc
EXTRN	 PRINTF:NEAR
EXTRN	 rate_equal:BYTE	      ;see MODEPARS.ASM
EXTRN	 ready_status:ABS	       ;see modeprin
EXTRN	 redpt:BYTE		       ;printer number (n) in message "LPTn rerouted to COMm"
EXTRN	 refresh:ABS
EXTRN	 retry_item_tag:ABS		  ;see MODEPARS.ASM
EXTRN	 request_type:BYTE	       ;see "MODEPARS.ASM"
EXTRN	 retry_equal:BYTE	       ;see MODEDEFS.INC
EXTRN	 retry_equal_str:BYTE
EXTRN	 retry_index:WORD	       ;see MODECOM.ASM
EXTRN	 retry_type_ptr:WORD	       ;see MODESUBS.INC
EXTRN	 row_ptr:WORD			       ;see modesubs.inc
EXTRN	 row_type:WORD				;see modesubs.inc
EXTRN	 R_item_tag:ABS 		     ;see MODEPARS.ASM
EXTRN	 R_str:BYTE			     ;see MODEPARS.ASM
EXTRN	 Required_font_not_loaded:BYTE	  ;see modedefs.asm
EXTRN	 res_com_retry_type:BYTE 	     ;see RESCODE.SAL
;EXTRN	  res_lpt_retry_type:ABS	      ;see RESCODE.SAL
EXTRN	 select:ABS			      ;request type for 'modecp'
EXTRN	 select_item_tag:ABS		   ;see MODEPARS.ASM
EXTRN	 serial_base:WORD		     ;see modecom
EXTRN	 set_con_features:ABS
EXTRN	 set_retry_type:NEAR		     ;see modeprin
EXTRN	 shift_screen:NEAR		     ;see modescrn
EXTRN	 stat_dev_ptr:WORD		     ;see modedefs.inc
EXTRN	 status_for_device:BYTE 	     ;"Status for device %1:" see modedefs.inc
EXTRN	 status_for_everything:ABS
EXTRN	 stop_bits_index:WORD		     ;see modecom.asm
EXTRN	 stop_equal:BYTE		     ;"STOP=", see modepars
EXTRN	 typamat:NEAR		       ;see "typamat.asm"
;possible values of "request_type"
EXTRN	 all_con_status:ABS
EXTRN	 codepage_prepare:ABS
EXTRN	 codepage_refresh:ABS
EXTRN	 codepage_select:ABS
EXTRN	 codepage_status:ABS
EXTRN	 codepage_prepared_status:ABS
EXTRN	 codepage_selected_status:ABS
EXTRN	 com_status:ABS
;EXTRN	  con_status:ABS
EXTRN	 initialize_com_port:ABS
EXTRN	 initialize_printer_port:ABS
EXTRN	 old_initialize_printer_port:ABS
EXTRN	 old_video_mode_set:ABS
EXTRN	 printer_reroute:ABS
EXTRN	 printer_status:ABS
EXTRN	 turn_off_reroute:ABS
;บ											  บ
;ศอออออออออออออออออออออออออออออออ  E X T R N S	ออออออออออออออออออออออออออออออออออออออออออผ
;ษอออออออออออออออออออออออออออออออออออ  D A T A	ออออออออออออออออออออออออออออออออออออออออออป
;บ											  บ
ANSI_installed		DB    false	  ;boolean indicator of whether ANSI.SYS is installed
columns_specified	DB    false	  ;indicates if columns= was on the command line, see set_con_features_case
code_page_numbers_encountered	 DB    0
cp_cb			codepage_parms <> ;codepage subroutine parameter block
com_ports_attached	DB    0 	  ;number of com ports in the machine
current_packet_cp_number   DW	 -2	  ;adjustment for accessing current 'des_strt_pkcp?' in 'des_start_packet'
delay_holder		DB    1 	  ;holder for binary form of delay requested
device_request		DB    ? 	  ;holds device request value
;JWASM max_pknum		EQU	 ($ - OFFSET des_start_packet.des_strt_pkcp1)/2        ;most cp numbers can send at once   ;AN000;  ; dead: max_pknum unused; $-OFFSET<extern des_start_packet> uncomputable
;IOCTL0C_functions_requested   DB 0	   ;for displaying messages, flag byte indicating IOCTL functions requested
need_typamat_call	DB	 false	  ;boolean for saving up delay and rate settings
need_IOCTL0C		DB	 false	  ;boolean for saving up parts of an IOCTL 0CH call
parm_list_holder	DW    bogus	  ;holder for address of parsed parameter list for when BX is needed elsewhere
parm_list_index_holder	DW    bogus	  ;holder for index of parsed parameter list for when DI is needed elsewhere
i			DB    0 	  ;index for status loop
rate_holder		DB    32	  ;holder for binary form of rate value
row_value		DB	 ?	  ;holder for binary form of row value during status display
IOCTL0C_data_block   IOCTL0C_def<>

PUBLIC IOCTL0C_data_block
;บ											  บ
;ศอออออออออออออออออออออออออออออออออออ  D A T A	ออออออออออออออออออออออออออออออออออออออออออผ
check_ANSI_installed PROC  NEAR 	  ;See if ANSI.SYS is installed

   MOV	 AH,ANSIINT2F
   MOV	 AL,check_installed
   INT	 2FH
   .IF <AL EQ installed> THEN
      MOV   ANSI_installed,true 	  ;initialized to false, so no ELSE needed
   .ENDIF

check_ANSI_installed ENDP

;------------------------------------------------------------------------------



setup_device_name PROC	NEAR
MOV   DX,device_name	      ;DX=pointer to ASCIIZ device name
MOV   cp_cb.cp_device,DX	 ;Set the pointer to the device name ASCIIZ in the parameter block for 'modecp'.
RET
setup_device_name ENDP
;-------------------------------------------------------------------------------
do_IOCTL0C  PROC  NEAR
PUBLIC	 DO_IOCTL0C
      MOV   AH,open		 ;open device
      MOV   AL,dev_open_mode	 ;AL=open mode for devices, see modecpeq.inc
      MOV   DX,OFFSET CON_str	 ;know that CON is being opened, avoid using user input and having to remove colon
      INT   21H
      MOV   BX,AX		 ;BX=handle of CON
      MOV   AX,440CH
      MOV   CH,display_device	 ;type of device
      MOV   DX,OFFSET IOCTL0C_data_block
      INT   21H 			  ;the IOCTL data block is filled with the current settings
      PUSHF				  ;save result of the IOCTL
      MOV   AH,3EH		 ;assume that BX still has the handle
      INT   21H 		 ;close CON, open and close each time because if error may not be back to close
      POPF			 ;restore result of the IOCTL
      RET
do_IOCTL0C  ENDP
;-------------------------------------------------------------------------------
display_columns_status	PROC  NEAR
MOV   CL,get_current_settings
CALL  do_IOCTL0C		    ;get current settings of CON
.IF <IOCTL0C_data_block.mode EQ text> THEN
   .IF <IOCTL0C_data_block.cols EQ 80> THEN
      MOV columns_ptr,OFFSET eighty_str      ;set up message block with pointer to "80"
   .ELSE
      MOV columns_ptr,OFFSET fourty_str
   .ENDIF
.ELSE
   MOV columns_ptr,OFFSET NONE_str
.ENDIF
display  COLUMNS_equal_msg
RET
display_columns_status	ENDP
;-------------------------------------------------------------------------------
display_lines_status PROC  NEAR
MOV   CL,get_current_settings
CALL  do_IOCTL0C		    ;get current settings of CON
.IF <IOCTL0C_data_block.mode EQ text> THEN
   MOV	 AX,IOCTL0C_data_block.rows
   MOV	 row_value,AL			 ;row_value=binary row value
   MOV	 row_type,right_align+unsgn_bin_byte  ;set up sublist so msg ret knows it is a binary byte
   MOV	 row_ptr,OFFSET row_value	 ;set up LINES_equal sublist
.ELSE
   MOV	 row_ptr,OFFSET  NONE_str
.ENDIF
display  LINES_equal_msg
RET
display_lines_status ENDP

;-------------------------------------------------------------------------------

old_video_mode_set_IOCTL   PROC  NEAR

MOV   CL,set_display_characteristics
CALL do_IOCTL0C
.IF C THEN
   get_extended_error
   .IF <AX EQ not_supported_on_machine> THEN
      DISPLAY Function_not_supported
   .ELSEIF <AX EQ font_not_loaded> THEN
      DISPLAY Required_font_not_loaded
   .ENDIF
   MOV	 noerror,false
.ENDIF			   ;AN000;carry

RET
old_video_mode_set_IOCTL   ENDP

;-------------------------------------------------------------------------------
;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
;ณ
;ณ CHECK_COM_PORTS_ATTACHED
;ณ ------------------------
;ณ
;ณ  Return the number of com ports in the machine.
;ณ
;ณ  INPUT: none
;ณ
;ณ
;ณ  RETURN: com_ports_attached - number of com ports
;ณ
;ณ
;ณ  MESSAGES: none
;ณ
;ณ  REGISTER
;ณ  USAGE:	SI - index of the FOR loop and displacement from serial_base
;ณ		ES - holds segment of ROM data area
;ณ
;ณ
;ณ  ASSUMPTIONS: The user has initialized com_ports_attached to zero.
;ณ
;ณ
;ณ  SIDE EFFECT: ES is lost
;ณ		 SI is lost
;ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ

check_com_ports_attached   PROC  NEAR

MOV   SI,0
MOV   ES,SI	  ;now ES:SERIAL_BASE addresses 40:0=0:400

.FOR SI,=,0,TO,6,STEP,2	;JWASM: explicit commas (.FOR args)

   .IF <<WORD PTR ES:SERIAL_BASE[SI]> NE 0> THEN       ;SEE IF THE COM PORT EXISTS
      INC   com_ports_attached
   .ENDIF

.NEXT SI

RET

check_com_ports_attached   ENDP


;-------------------------------------------------------------------------------
;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
;ณ
;ณ CHECK_PRN_PORTS_ATTACHED
;ณ ------------------------
;ณ
;ณ  Return the number of printer ports in the machine. The network will put a 2
;ณ  in th address word if the printer is redirected, so for the printer to
;ณ  actually exist the address must be greater than 2 ("redirected").  Since
;ณ  can't have infinite retry on redirected printers only want to count ports
;ณ  with >2 for addresses.
;ณ
;ณ  INPUT: none
;ณ
;ณ
;ณ  RETURN: prn_ports_attached - number of printer ports
;ณ
;ณ
;ณ  MESSAGES: none
;ณ
;ณ  REGISTER
;ณ  USAGE:	SI - index of the FOR loop and displacement from printr
;ณ		ES - holds segment of ROM data area (0 in this case)
;ณ
;ณ
;ณ  ASSUMPTIONS: All valid printer port addresses are >2.
;ณ
;ณ
;ณ  SIDE EFFECT: ES is lost
;ณ		 SI is lost
;ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ

check_prn_ports_attached   PROC  NEAR


MOV   SI,0
MOV   ES,SI	  ;now ES:printr addresses 40:8=0:408

.FOR SI,=,0,TO,4,STEP,2       ;for each of 3 printer port address holder words	;JWASM: explicit commas (.FOR args)

   .IF <<WORD PTR ES:printr[SI]> GT redirected> THEN	   ;SEE IF THE PORT EXISTS
      INC   prn_ports_attached
   .ENDIF

.NEXT SI

RET

check_prn_ports_attached   ENDP


;-------------------------------------------------------------------------------
;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
;ณ
;ณ GET_DEVICE_RETRY_TYPE
;ณ ---------------------
;ณ
;ณ  Return the type of retry active for comX or lptX.
;ณ
;ณ  INPUT: device_request - scalar indicating what status the user requested.
;ณ		use the following equates:
;ณ
;ณ		    com1_retry_type_status   EQU  0
;ณ		    com2_retry_type_status   EQU  2
;ณ		    com3_retry_type_status   EQU  4
;ณ		    com4_retry_type_status   EQU  6
;ณ		    lpt1_retry_type_status
;ณ		    lpt2_retry_type_status
;ณ		    lpt3_retry_type_status
;ณ
;ณ
;ณ  RETURN: returned_retry_type - scalar indicating type of retry active for
;ณ		 the requested device. compare with the following equates:
;ณ
;ณ		    no_retry_flag
;ณ		    error_status
;ณ		    busy_status
;ณ		    ready_status
;ณ
;ณ	     retry_type_ptr - set to proper string
;ณ
;ณ
;ณ  MESSAGES: none
;ณ
;ณ  REGISTER
;ณ  USAGE:	CL - For com ports it serves as bit shift count for the retry type byte.
;ณ
;ณ		AL - On exit holds retry type scalar on exit (returned_retry_type)
;ณ
;ณ		ES - holds segment of resident mode code
;ณ
;ณ
;ณ  CONVENTIONS: The value in device_request is used as an index into the LPTX
;ณ		  array of retry type flags, or as a bit shift count for the
;ณ		  COM retry type byte.
;ณ
;ณ
;ณ  ASSUMPTIONS: The user has initialized device_request on entry with
;ณ		 the equates provided.
;ณ
;ณ
;ณ  SIDE EFFECT: none.
;ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
get_device_retry_type PROC NEAR

PUBLIC get_device_retry_type

PUSH BX
PUSH ES

XOR  BX,BX
MOV  ES,BX			       ;set segment to zero

.IF <<ES:WORD PTR resseg> NE 0000H> THEN    ;IF code resident THEN
   MOV	ES,ES:WORD PTR resseg[2]	    ;ES=seg of resident code
   .IF <device_type EQ COMx> THEN
      MOV   CL,device_request		     ;CL has 0, 2, 4 or 6 for COM 1, 2, 3 or 4 respectively
      MOV   returned_retry_type,BYTE PTR ES:res_com_retry_type		 ;AL=the status byte for all 4 com ports
      SHR   returned_retry_type,CL	 ;AL=XXXXXX??, where ?? is the retry bits for port in question
      AND   returned_retry_type,00000011B ;AL=000000??, where ?? is the retry bits for port in question
   .ELSE
      MOV  BL,device_request		       ;BX=index into retry bytes in resident code
      MOV  returned_retry_type,BYTE PTR ES:lpt1_retry_type[BX]
   .ENDIF
.ELSE
   MOV	returned_retry_type,no_retry_flag
.ENDIF

.IF <returned_retry_type EQ B> OR		;COM form of busy flag
.IF <returned_retry_type EQ busy_status> THEN
   MOV	 retry_type_ptr,OFFSET B_str
.ELSEIF <returned_retry_type EQ E> OR		;COM form of error flag
.IF <returned_retry_type EQ error_status> THEN
   MOV	 retry_type_ptr,OFFSET E_str
.ELSEIF <returned_retry_type EQ R> OR		;COM form of ready flag
.IF <returned_retry_type EQ ready_status> THEN
   MOV	 retry_type_ptr,OFFSET R_str
.ELSE
   MOV	 retry_type_ptr,OFFSET NONE_str    ;not E, B or R.
.ENDIF

POP  ES
POP  BX
RET

get_device_retry_type ENDP
;ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
;ณ
;ณ ANALYZE_AND_INVOKE
;ณ ------------------
;ณ
;ณ The command line is boken down into pieces by "parse_parameters".  Each piece
;ณ is analyzed here, and the appropriate routine called to setup and/or execute
;ณ the requested function.
;ณ
;ณ
;ณ
;ณ
;ณ
;ณ
;ณ  INPUT: request_type - scalar indicating what operation the user requested.
;ณ
;ณ
;ณ
;ณ
;ณ  RETURN: none
;ณ
;ณ
;ณ  MESSAGES: none
;ณ
;ณ
;ณ
;ณ
;ณ  REGISTER
;ณ  USAGE:	 DI - index into the list of parsed parms, the array parm_list.
;ณ
;ณ		 CX - temporary holder for memory to memory MOVs
;ณ
;ณ
;ณ  CONVENTIONS:
;ณ
;ณ
;ณ
;ณ  ASSUMPTIONS: All the input are valid. The parm_list entry past the last one
;ณ		 has a parm_type of bogus.
;ณ
;ณ		 The lines and columns values are in binary for request_type=
;ณ		 set_con_features
;ณ
;ณ		 The codepage numbers were put into des_start_packet.
;ณ
;ณ
;ณ
;ณ
;ณ  SIDE EFFECT:
;ณ
;ณ
;ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤ
analyze_and_invoke  PROC  NEAR
;CASE request_type=
   MOV	 cp_cb.des_pack_ptr,OFFSET des_start_packet	;AX000;In case a codepage request
   MOV	 DI,0	   ;initialize index into the list of parsed parameters
   ;calculate the displacement for the jump to the jump
   MOV	 parm_list_holder,BX	       ;save parm_list_BX
   XOR	 BX,BX
   MOV	 BL,max_request_type
   SUB	 BL,request_type	    ;AX000;see the list of equates for request_type
   SHL	 BX,1			    ;AX000;BX=word displacement into jump table
   JMP	 jump_table1[BX]	    ;AX000;jump to appropriate jump
   jump_table1	  LABEL    WORD        ;the order of the following entries is critical
   DW	OFFSET all_con_status_case
   DW	OFFSET codepage_prepare_case
   DW	OFFSET codepage_refresh_case
   DW	OFFSET codepage_select_case
   DW	OFFSET codepage_status_case
   DW	OFFSET codepage_prepared_status_case
   DW	OFFSET codepage_selected_status_case
   DW	OFFSET com_status_case
   DW	OFFSET initialize_com_port_case
   DW	OFFSET initialize_printer_port_case
   DW	OFFSET old_initialize_printer_port_case
   DW	OFFSET old_video_mode_set_case
   DW	OFFSET printer_reroute_case
   DW	OFFSET printer_status_case
   DW	OFFSET set_con_features_case
   DW	OFFSET status_for_everything_case
   DW	OFFSET turn_off_reroute_case
   all_con_status_case: 	       ;know that all con status is requested
      MOV      stat_dev_ptr,OFFSET CON_str	;set up msg ser input
      MOV      dev_name_size,len_CON_str	;set up for msg service, see MODEPARS.ASM
      display  status_for_device
      display  long_underline	       ;Status for device CON:
      display  four_char_underline     ;----------------------
      CAll  check_ANSI_installed       ;see if ANSI.SYS is installed
      .IF   <ANSI_installed EQ true> THEN    ;IF can get info on settings THEN display them ELSE don't display them
	 CALL  display_columns_status
	 CALL  display_lines_status
      .ENDIF
      MOV   cp_cb.request_typ,status	     ;set up variables for modecp
      MOV   cp_cb.cp_device,OFFSET CON_str
      CALL  modecp			  ;display codepage status
      BREAK 0
   codepage_prepare_case:
      MOV   cp_cb.request_typ,prepare
      CALL  setup_device_name	     ;Set the pointer to the device name ASCIIZ in the parameter block for 'modecp'.
      call  modecp
      BREAK 0
   codepage_refresh_case:
      MOV   cp_cb.request_typ,refresh
      CALL  setup_device_name	     ;Set the pointer to the device name ASCIIZ in the parameter block for 'modecp'.
      call  modecp
      BREAK 0
   codepage_select_case:
      MOV   cp_cb.request_typ,select
      CALL  setup_device_name	     ;Set the pointer to the device name ASCIIZ in the parameter block for 'modecp'.
      MOV   des_start_packet.des_strt_pknum,1	   ;one cp number
      MOV   des_start_packet.des_strt_pklen,4	   ;bytes for count (word) and one number (word)
      MOV   BX,parm_list_holder 			;restore parm_list_BX
      MOV   DI,codepage_index_holder			;DI=index in parm list of the entry for the codepage to be selected
      MOV   AX,parm_list_BX[DI].value1		      ;AX=codepage number in binary form
      MOV   des_start_packet.des_strt_pkcp1,AX	   ;setup parm block with the (single) cp number
      CALL  modecp
      BREAK 0
   codepage_status_case:
   codepage_prepared_status_case:
   codepage_selected_status_case:
      MOV   cp_cb.request_typ,status
      CALL  setup_device_name	     ;Set the pointer to the device name ASCIIZ in the parameter block for 'modecp'.
      CALL  modecp
      BREAK 0
   com_status_case:
	     ; INPUT: device_type = COMx
	     ;	      device	  = ASCII COM number


      CALL  check_com_ports_attached	     ;return number of com ports in com_ports_attached
      .IF <device_name EQ <OFFSET COM1_str>> AND
      .IF <com_ports_attached GE 1> THEN		;COM1 exists
	 MOV   BL,COM1
	 MOV   stat_dev_ptr,OFFSET COM1_str	 ;set up msg ser input
	 MOV   device_request,com1_retry_type_status
      .ELSEIF <device_name EQ <OFFSET COM2_str>> AND
      .IF <com_ports_attached GE 2> THEN		;COM2 exists
	 MOV   BL,COM2
	 MOV   stat_dev_ptr,OFFSET COM2_str	 ;set up msg ser input
	 MOV   device_request,com2_retry_type_status
      .ELSEIF <device_name EQ <OFFSET COM3_str>> AND
      .IF <com_ports_attached GE 3> THEN		;COM3 exists
	 MOV   BL,COM3
	 MOV   stat_dev_ptr,OFFSET COM3_str	 ;set up msg ser input
	 MOV   device_request,com3_retry_type_status
      .ELSEIF <device_name EQ <OFFSET COM4_str>> AND
      .IF <com_ports_attached EQ 4> THEN		;COM4 exists
	 MOV   BL,COM4
	 MOV   stat_dev_ptr,OFFSET COM4_str	 ;set up msg ser input
	 MOV   device_request,com4_retry_type_status
      .ELSE						;device does not exist
	  MOV  CX,device_name
	  MOV  illegal_device_ptr,CX	  ;put pointer to com port string in message
	  DISPLAY err1			 ;AN000;"Illegal device name - COMX"
	  MOV  noerror,false			;set flag for displaying status to be skipped
      .ENDIF
      .IF <noerror EQ true> THEN
	 MOV	  dev_name_size,len_COMX_str	   ;set up for msg service, see MODEPARS.ASM
	 display  status_for_device		   ;"Status for device COM?:"
	 display  long_underline		   ;"------------------"
	 display  five_char_underline		;has CRLF on it       "-----"
	 call  get_device_retry_type
	 display  retry_equal
      .ENDIF
      BREAK 0
;  con_status_case:	;don't know which con status is requested
;     MOV   request_type,all_con_status   ;AC000;DCR76
;     CALL  analyze_and_invoke		  ;AC000;DCR76
;     MOV      dev_name_size,len_CON_str       ;set up for msg service, see MODEPARS.ASM
;     MOV      stat_dev_ptr,OFFSET CON_str	;set up msg ser input
;     display  status_for_device
;     display  long_underline	       ;Status for device CON:
;     display  four_char_underline     ;----------------------
;     MOV   DI,0
;     .WHILE <parm_list_BX[DI].parm_type NE bogus> DO	   ;the entry after the last has parm_type of bogus
;	 ;CASE parm_list_BX[DI].item_tag=
;	    ;CODEPAGE,
;	    ;PREPARE,
;	    ;SELECT:
;		  .IF <parm_list_BX[DI].item_tag EQ CODEPAGE_item_tag> OR
;		  .IF <parm_list_BX[DI].item_tag EQ SELECT_item_tag> OR
;		  .IF <parm_list_BX[DI].item_tag EQ PREPARE_item_tag> THEN
;	       MOV   cp_cb.request_typ,status
;	       MOV   cp_cb.cp_device,OFFSET CON_str
;	       CALL  modecp			   ;display codepage status
;	       BREAK 2
;		  .ENDIF
;	    ;BLINK:
;		  .IF <parm_list_BX[DI].item_tag EQ BLINK_item_tag> THEN
;	       CALL  display_blink_status
;	       BREAK 2
;		  .ENDIF
;	    ;COLUMNS:
;		  .IF <parm_list_BX[DI].item_tag EQ COLUMNS_item_tag> THEN
;	       CALL  display_COLUMNS_status
;	       BREAK 2
;		  .ENDIF
;	    ;LINES:
;		  .IF <parm_list_BX[DI].item_tag EQ LINES_item_tag> THEN
;	       CALL  display_lines_status
;	       BREAK 2
;		  .ENDIF
;	 ENDCASE_2:
;	 ADD   DI,TYPE parm_list_entry
;     .ENDWHILE
;     BREAK 0
   initialize_com_port_case:

      MOV   BX,parm_list_holder 		;restore parm_list_BX

      .IF <parms_form EQ keyword> THEN	      ;IF the parms were input as keywords THEN
	 MOV   DI,TYPE parm_list_entry		;skip COMN parm
	 .WHILE <parm_list_BX[DI].parm_type NE bogus> DO NEAR ;the entry after the last has parm_type of bogus
	    ;CASE parm_list_BX[DI].keyword_switch_ptr=
	       ;BAUD_equal:
		     .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET BAUD_equal>> THEN
		  MOV	AX,parm_list_BX[DI].value1  ;AX= pointer to the baud rate string
		  MOV	pbaud_ptr,AX		    ;set pointer to the baud rate string in the messge
		  MOV	baud_index,DI			   ;set index into parm list for setcom
		  BREAK 3
		     .ENDIF
	       ;PARITY_equal:
		     .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET PARITY_equal>> THEN
		  MOV	SI,parm_list_BX[DI].value1    ;AX= pointer to the parity string
		  MOV	pparity_ptr,SI		      ;set pointer to the parity string in the messge
		  OR	BYTE PTR [SI],lowercase 	;convert to lowercase for compatibility with previous versions
		  MOV	parity_index,DI 	      ;set index into parm list for setcom
		  BREAK 3
		     .ENDIF
	       ;DATA_equal:
		     .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET DATA_equal>> THEN
		  MOV	BP,parm_list_BX[DI].value1    ;BP= pointer to the data bits string
		  MOV	AL,[BP] 		      ;AL= data bits character
		  MOV	pdata,AL		      ;set the data bits string in the messge
		  MOV	data_bits_index,DI		 ;set index into parm list for setcom
		  BREAK 3
		     .ENDIF
	       ;STOP_equal:
		     .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET STOP_equal>> THEN
		  MOV	AX,parm_list_BX[DI].value1    ;AX= pointer to the stop bit string
		  MOV	pstop_ptr,AX		      ;set pointer to the parity string in the messge
		  MOV	stop_bits_index,DI		 ;set index into parm list for setcom
		  BREAK 3
		     .ENDIF
	       ;RETRY_equal:
		     .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET RETRY_equal_str>> THEN
		  MOV	retry_index,DI	     ;indicate to modecom which parm is retry
;		  BREAK 3
		     .ENDIF
	    ENDCASE_3:
	    ADD   DI,TYPE parm_list_entry
	 .ENDWHILE
      .ELSE			    ;the parms were entered as positionals (the old form)
	 MOV   baud_index,TYPE parm_list_entry
	 MOV   DI,2 * (TYPE parm_list_entry)
	 .IF <parm_list_BX[DI].item_tag NE unspecified> THEN				   ;AN000;IF stopbits requested THEN
	    MOV   parity_index,DI
	 .ENDIF
	 MOV   DI,3 * (TYPE parm_list_entry)
	 .IF <parm_list_BX[DI].item_tag NE unspecified> THEN				   ;AN000;IF stopbits requested THEN
	    MOV   data_bits_index,DI
	 .ENDIF
	 MOV   DI,4 * (TYPE parm_list_entry)						   ;DI=stopbits index
	 .IF <parm_list_BX[DI].item_tag NE unspecified> THEN				   ;AN000;IF stopbits requested THEN
	    MOV   stop_bits_index,DI
	 .ENDIF
	 MOV   DI,5 * (TYPE parm_list_entry)		      ;AN000;DI=index of retry parm
	 .IF <parm_list_BX[DI].item_tag NE unspecified> THEN				   ;AN000;IF retry requested THEN
	    MOV   retry_index,DI							   ;AN000;set up index for modecom
	 .ENDIF
      .ENDIF
      CALL  modecom
      BREAK 0

   old_initialize_printer_port_case:   ;Assume that parms not specified have an entry in parm_list that is in initial state

				       ;printer_no has ASCII form of printer number
				       ;need to put binary form of columns in columns_holder (80 or 132)
				       ;need to put "6" or "8" in parm2
				       ;need to set retry_index


PUBLIC	 old_initialize_printer_port_case

      MOV   BX,parm_list_holder 	     ;restore parm_list_BX
      MOV   DI,TYPE parm_list_entry	     ;skip LPTN parm, point at chars per line

      .IF <parm_list_BX[DI].item_tag EQ onethirtytwo_item_tag> THEN
	 MOV   columns_holder,132
      .ELSEIF <parm_list_BX[DI].item_tag EQ eighty_item_tag> THEN
	 MOV   columns_holder,80
      .ENDIF				     ;if not 80 or 132 modeprin assumes not specified, and makes no change
      ADD   DI,TYPE parm_list_entry	     ;look at lines per inch

      .IF <parm_list_BX[DI].item_tag NE unspecified> THEN	;IF chars per line specified THEN
	 MOV   SI,parm_list_BX[DI].value1	  ;SI=>"6" or "8"
	 MOV   AL,BYTE PTR DS:[SI]
	 MOV   parm2,AL 		      ;parm2="6" or "8"
      .ENDIF   ;otherwise leave parm2=0FFH (unspecified)

      ADD   DI,TYPE parm_list_entry	     ;look at retry request
      .IF <parm_list_BX[DI].item_tag NE unspecified> THEN
	 MOV   retry_index,DI		     ;AN000;let modeprin know retry was requested and the index of it.
      .ENDIF

      CALL  modeecno
      CALL  modeprin
      BREAK 0



   initialize_printer_port_case:    ;printer_no has ASCII form of printer number
				    ;need to put binary form of columns in columns_holder (80 or 132)
				    ;need to put "6" or "8" in parm2
				    ;need to set retry_index
      MOV   BX,parm_list_holder 		;restore parm_list_BX
      MOV   DI,TYPE parm_list_entry	     ;skip LPTN parm

      .WHILE <parm_list_BX[DI].parm_type NE bogus> DO	   ;the entry after the last has parm_type of bogus
	 ;CASE parm_list_BX[DI].keyword_switch_ptr=
	    ;LINES_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET LINES_equal>> THEN
	       MOV   SI,parm_list_BX[DI].value1 	;SI=>"6" or "8"
	       MOV   AL,BYTE PTR DS:[SI]
	       MOV   parm2,AL				;parm2="6" or "8"
	       BREAK 4
		  .ENDIF
	    ;COLUMNS_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET COLUMNS_equal>> OR
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET COLS_equal>> THEN
	       .IF <parm_list_BX[DI].item_tag EQ onethirtytwo_item_tag> THEN
		  MOV	columns_holder,132
	       .ELSE
		  MOV	columns_holder,80
	       .ENDIF
	       BREAK 4
		  .ENDIF
	    ;RETRY_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET RETRY_equal_str>> THEN

	       MOV   retry_index,DI
	       BREAK 4
		  .ENDIF
	 ENDCASE_4:
	 ADD   DI,TYPE parm_list_entry
      .ENDWHILE

      CALL  modeecno	   ;turn of rerouting
      CALL  modeprin
      BREAK 0
   old_video_mode_set_case:
   PUBLIC   old_video_mode_set_case
      ;first see if ANSI.SYS is loaded
      CALL  check_ANSI_installed
      .IF <ANSI_installed EQ true> THEN
	 MOV   CL,get_current_settings
	 PUSH  BX			  ;save parm_list
	 CALL  do_IOCTL0C		     ;get current settings of CON
	 POP   BX				  ;restore parm_list
	 MOV   IOCTL0C_data_block.mode,text
      .ENDIF			    ;AN000;ANSI installed
      MOV   BX,parm_list_holder 		;restore parm_list_BX
      PUSH  DI					;save parm list index
      .IF <parm_list_BX[DI].item_tag NE unspecified> THEN
	 .IF <parm_list_BX[DI].item_tag EQ BW40_item_tag> THEN ;IF BW40 REQUESTED
	    CALL BW40
	 .ELSEIF <parm_list_BX[DI].item_tag EQ BW80_item_tag> THEN ;IF BW80 REQUESTED
	    CALL  BW80
	 .ELSEIF <parm_list_BX[DI].item_tag EQ CO40_item_tag> THEN ;IF CO40 REQUESTED
	    CALL  CO40
	 .ELSEIF <parm_list_BX[DI].item_tag EQ CO80_item_tag> THEN ;IF CO80 REQUESTED
	    CALL  CO80
	 .ELSEIF <parm_list_BX[DI].item_tag EQ MONO_item_tag> THEN ;IF MONO REQUESTED
	    CALL  MONO
	 .ELSE
	    .IF <ANSI_installed EQ true> THEN
;AC004;        MOV   need_IOCTL0C,true			     ;use IOCTL if possible to retain lines setting
	       .IF <parm_list_BX[DI].value1 EQ <OFFSET fourty_str>> THEN
		  MOV	IOCTL0C_data_block.cols,40	;setup IOCTL input block with the columns requested
	       .ELSE
		  MOV	IOCTL0C_data_block.cols,80	;setup IOCTL input block with the columns requested
	       .ENDIF
	       CALL  old_video_mode_set_IOCTL			;AN004;use IOCTL if possible to retain lines setting
	    .ELSE
	       .IF <parm_list_BX[DI].item_tag EQ fourty_item_tag> THEN ;IF 40 REQUESTED
		   MOV	BL,40					    ;set up for handle_40_or_80
	       .ELSE
		   MOV	BL,80					    ;set up for handle_40_or_80
	       .ENDIF
	       CALL HANDLE_40_OR_80
	    .ENDIF
	 .ENDIF
      .ENDIF

dummy9:
PUBLIC dummy9
      POP   DI					;restore parm list index

      .IF <NOERROR EQ TRUE> AND 	     ;process ,r ณ l,[T]
      MOV   BX,parm_list_holder 		;restore parm_list_BX
      ADD   DI,TYPE parm_list_entry	  ;process second parm, shift direction
      .IF <parm_list_BX[DI].item_tag NE unspecified> THEN
	 .IF <parm_list_BX[DI].item_tag EQ R_item_tag> OR
	 .IF <parm_list_BX[DI].item_tag EQ L_item_tag> THEN
	    MOV   CL,parm_list_BX[DI].item_tag
	    MOV   PARM2,CL	    ;set up for SHIFT_SCREEN
	    ADD   DI,TYPE parm_list_entry	;look at third parm
	    MOV   CL,parm_list_BX[DI].item_tag	;CL=T_item_tag or bogus
	    MOV   PARM3,CL	    ;may be bogus, but shift_screen will handle it correctly
	    CALL  SHIFT_SCREEN
	 .ELSE			    ;AN000;must be a rows value
	    .IF <ANSI_installed EQ true> THEN
;AC004;        MOV   need_IOCTL0C,true			     ;use IOCTL if possible to retain lines setting
	       MOV   DX,parm_list_BX[DI].value1
	       MOV   IOCTL0C_data_block.rows,DX 	;the IOCTL input block has the columns requested
	       CALL  old_video_mode_set_IOCTL		     ;AN004;use IOCTL if possible to retain lines setting
	    .ELSE			  ;AN000;ANSI not installed
	       DISPLAY ANSI_not_loaded
	       MOV   noerror,false
	    .ENDIF			  ;AN000;ANSI installed
	 .ENDIF
      .ENDIF
      BREAK 0


PUBLIC	 printer_reroute_case
   printer_reroute_case:
			;INPUT:lptno=zero based printer number OUTPUT:;AH=printer number mask: lpt1=1, lpt2=2, lpt3=4
			      ;device=COM number in ASCII form	      ;SI=printer number value (one based)
								      ;AL=com number character
      XOR   CX,CX
      MOV   CL,lptno	      ;lptno always <= 255
      MOV   SI,CX	      ;SI=zero based printer number (0, 1, or 2)
      INC   SI		      ;SI=one based printer number (1, 2, or 3)
      MOV   AH,1
      SAL   AH,CL	      ;AH=2**SI,AH=printer number mask for MODEECHO
      MOV   DH,CL
      ADD   DH,ASCII_1	      ;DH=ASCII printer number
      MOV   AL,device	      ;AL=ASCII form of com device number
      MOV   REDPT,DH	      ;PUT n OF LPTn IN REDIRECT MESSAGE
      MOV   NOTREDPT,DH       ;AND INTO NOT REDIRECTED MSG
      CALL  modeecho
      BREAK 0
   printer_status_case:

PUBLIC	 printer_status_case

	     ; INPUT: device_type = LPTx
	     ;	      device	  = ASCII printer number
	     ;	      lptno	  = ASCII printer number
	     ;	      device_name = offset of printer string

      MOV   cp_cb.request_typ,status
      MOV   AX,device_name
      MOV   stat_dev_ptr,AX		;AC665;set up msg ser input
      MOV   dev_name_size,len_LPTX_str	;AN000;set up for msg service, see MODEPARS.ASM
      MOV   cp_cb.cp_device,AX	       ;AN665;set up for call to modecp
      .IF <device_name EQ <OFFSET LPT1_str>> THEN
	 MOV   device_request,lpt1_retry_type_status
	 MOV   rerouted_printer_mask,LPT1
	 MOV   redpt,"1"                                ;set up for reroute message
	 MOV   notredpt,"1"                             ;set up for not rerouted message
      .ELSEIF <device_name EQ <OFFSET LPT2_str>> THEN
	 MOV   device_request,lpt2_retry_type_status
	 MOV   rerouted_printer_mask,LPT2
	 MOV   redpt,"2"                                ;set up for reroute message
	 MOV   notredpt,"2"                             ;set up for not rerouted message
      .ELSEIF <device_name EQ <OFFSET LPT3_str>> THEN
	 MOV   device_request,lpt3_retry_type_status
	 MOV   rerouted_printer_mask,LPT3
	 MOV   redpt,"3"                                ;set up for reroute message
	 MOV   notredpt,"3"                             ;set up for not rerouted message
      .ENDIF
      PUSH  ES				     ;save ES, used in MODECP
;AC002;PUSH  AX 	 ;AN000;save
      display  status_for_device
      display  long_underline				      ;JWASM: stranded string -> "Status for device LPTX?"
      display  five_char_underline	     ;has CRLF on it   -----------------------
      call  display_printer_reroute_status		 ;see modeecho.asm
;AC002;POP   AX 					 ;restore "device_request"
      XOR   CX,CX	      ;initialize prn_ports_attached
      CALL  check_prn_ports_attached   ;return number of printer cards in prn_ports_attached
      POP   ES				     ;restore ES
      ADD   prn_ports_attached,ASCII_0	      ;CX=ASCII form of last printer number
      .IF <prn_ports_attached GE redpt> THEN	;IF the printer exists THEN
	 call  get_device_retry_type
	 display  retry_equal
	 CALL  modecp			     ;display codepage status
      .ENDIF
      BREAK 0
;m
   set_con_features_case:	 ;the command line was nothing but con keywords
      ;first see if ANSI.SYS is loaded
      CALL  check_ANSI_installed
      .IF <ANSI_installed EQ true> THEN
	 MOV   CL,get_current_settings
	 CALL  do_IOCTL0C		     ;get current settings of CON
	 ;MOV	SI,OFFSET IOCTL0C_data_block  ;set up IOCTL0C, addressablitiy to the IOCTL data block
	 MOV   IOCTL0C_data_block.mode,text
      .ENDIF   ;ANSI.SYS installed
      MOV   BX,parm_list_holder 		;restore parm_list_BX
      ADD   DI,TYPE parm_list_entry		;skip CON parm
      .WHILE <parm_list_BX[DI].parm_type NE bogus> DO NEAR ;the entry after the last has parm_type of bogus
	 ;CASE parm_list_BX[DI].keyword_switch_ptr=
	    ;LINES_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET LINES_equal>> THEN
	       MOV   DX,parm_list_BX[DI].value1
	       MOV   IOCTL0C_data_block.rows,DX 	;the IOCTL input block has the columns requested
	       MOV   need_IOCTL0C,true
	       BREAK 1
		  .ENDIF
	    ;COLUMNS_equal:	  ;the value is binary
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET COLUMNS_equal>> OR
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET COLS_equal>> THEN
	       .IF <ANSI_installed EQ true> THEN
		  MOV	need_IOCTL0C,true			;use IOCTL if possible to retain lines setting
		  MOV	DX,parm_list_BX[DI].value1
		  MOV	IOCTL0C_data_block.cols,DX	   ;the IOCTL input block has the columns requested
	       .ELSE
		  .IF <parm_list_BX[DI].item_tag EQ fourty_item_tag> THEN ;IF 40 REQUESTED
		      MOV  columns_specified,40 				      ;set up for handle_40_or_80
		  .ELSE
		      MOV  columns_specified,80 				      ;set up for handle_40_or_80
		  .ENDIF
	       .ENDIF
	       BREAK 1
		  .ENDIF
	    ;RATE_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET RATE_equal>> THEN
	       MOV   AL,BYTE PTR parm_list_BX[DI].value1       ;save the rate requested in binary form, always <255
	       MOV   rate_holder,AL
	       MOV   need_typamat_call,true
	       BREAK 1
		  .ENDIF
	    ;DELAY_equal:
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET DELAY_equal>> OR
		  .IF <parm_list_BX[DI].keyword_switch_ptr EQ <OFFSET DEL_equal>> THEN
	       MOV   AL,BYTE PTR parm_list_BX[DI].value1      ;save delay requested (binary), always <255
	       MOV   delay_holder,AL
	       MOV   need_typamat_call,true
	       BREAK 1
		  .ENDIF
	 ENDCASE_1:
	 ADD   DI,TYPE parm_list_entry	     ;address next parm
      .ENDWHILE
DUMMY3:
PUBLIC DUMMY3
      .IF <need_IOCTL0C EQ true> THEN
	 .IF <ANSI_installed EQ true> THEN
	    MOV   CL,set_display_characteristics
	    CALL do_IOCTL0C
	    .IF C THEN
	       get_extended_error
	       .IF <AX EQ not_supported_on_machine> THEN
		  DISPLAY Function_not_supported
	       .ELSEIF <AX EQ font_not_loaded> THEN
		  DISPLAY Required_font_not_loaded
	       .ENDIF
	       MOV   noerror,false
	    .ENDIF
	 .ELSE
	    DISPLAY ANSI_not_loaded
	    MOV   noerror,false
	 .ENDIF
      .ELSEIF <columns_specified NE false> THEN
	 MOV   BL,columns_specified			;set up for call to handle_40_or_80
	 CALL  HANDLE_40_OR_80
      .ENDIF

      .IF <need_typamat_call EQ true> THEN
	 MOV   BL,rate_holder
	 MOV   BH,delay_holder
	 CALL  typamat
      .ENDIF
      BREAK 0
   status_for_everything_case:
      MOV   request_type,printer_status 	;status routine for printers
      MOV   device_name,OFFSET LPT1_str 	;will display the reroute
      CALL  analyze_and_invoke			;status for the printer whether
      MOV   device_name,OFFSET LPT2_str 	;it exists or not, so call for
      CALL  analyze_and_invoke			;all of them
      MOV   device_name,OFFSET LPT3_str
      CALL  analyze_and_invoke
      MOV   request_type,all_con_status
      CALL  analyze_and_invoke

      CALL  check_com_ports_attached	     ;return number of com ports in com_ports_attached

      MOV   request_type,com_status
      MOV   CL,com_ports_attached
      .FOR i,=,1,TO,CL 												   ;AN000;	;JWASM: explicit commas (.FOR args)

	 .SELECT

	    .WHEN <i EQ 1>
	       MOV   device_name,OFFSET COM1_str

	    .WHEN <i EQ 2>
	       MOV   device_name,OFFSET COM2_str

	    .WHEN <i EQ 3>
	       MOV   device_name,OFFSET COM3_str

	    .WHEN <i EQ 4>
	       MOV   device_name,OFFSET COM4_str								       ;AN0

	 .ENDSELECT

	 CALL  analyze_and_invoke
      .NEXT i

      BREAK 0



   turn_off_reroute_case:		;user specified only LPTx[:]
			;INPUT:lptno=ASCII printer number



      CALL  modeecno	;turn off rerouting
      XOR   CX,CX	      ;initialize prn_ports_attached
      CALL  check_prn_ports_attached   ;return number of printer cards in prn_ports_attached
      ADD   prn_ports_attached,ASCII_0	      ;CX=ASCII form of last printer number
      .IF <prn_ports_attached GE LPTNO> THEN	;IF the printer exists THEN
	 CALL  set_retry_type			;turn off infinit retry
	 CALL  modify_resident_code		;modify resident code to reflect retry turned off
      .ENDIF

      BREAK 0

ENDCASE_0:
RET
analyze_and_invoke  ENDP
PRINTF_CODE ENDS
	END
