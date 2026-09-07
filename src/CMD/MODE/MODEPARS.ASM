
	PAGE	,132			;
	TITLE	MODE COMMAND - COMMAND PARSING
.XLIST
   INCLUDE STRUC.INC
.LIST
;.SALL


;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P R O L O G  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º

;  AC001 - P3259: When "/STATUS" was only parameter was returning "Invalid
;		  number of parameters".  When "/STATUS" was first parameter
;		  the device name was not being recognized.

;  AC002 - P3258, PS/2 only COM parameters were being allowed on non-PS/2
;	   P3540: machines.  Added checks for baud=19200, parity=mark or space,
;		  data=5 or 6, stop=1.5 for both keyword and positional forms.

;  AC003 - P3451: Wasn't treating semicolons as a valid blank-like delimeter.


;  AC004 - P3456: /STAT wasn't included in all checks for valid forms of /STATUS.
;		  "BW" and "CO" were being accepted as valid parms.

;  AC005 - P3796: PRN /STA returned "Invalid parameter -" when worked OK for
;		  LPT1.

;  AC006 - P3932: Was issuing "Invalid parameter - ???" for switches that are
;		  not valid, now issue "Invalid switch - ???".

;  AC007 - P3931: "CON SEL=850" acts like a status request, should return
;		  "Invalid number of parameters" because user forgot "CP".

;  AX008 - P5183: Was denying 19200 baud on PS/2 model 30s and 25s and VAILs.

;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P R O L O G  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼



;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  M A C R O S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º


BREAK	MACRO	X
   JMP	   endcase_&X
ENDM

;-------------------------------------------------------------------------------

DISPLAY MACRO	MESSAGE
	MOV	DX,MESSAGE
	CALL	PRINTF
ENDM

;-------------------------------------------------------------------------------

check_for_lpt_keyword	MACRO

MOV   DL,number_of_lpt_keywords     ;;AN000;Initialize
MOV   number_of_keywords,DL	    ;;AN000;		for call to check_for_keyword
MOV   BP,OFFSET start_lpt_keyword_ptrs	;;AN000;start_of_keyword_ptrs=[BP]
CALL  check_for_keyword

ENDM

;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ DELETE_PARSER_VALUE_LIST_ENTRY
;³ -------------------------------
;³
;³ As the logic in PARSE_PARAMETERS proceeds the posibilities for the next parm
;³ become apparent and the parser control blocks need to be changed to correctly
;³ parse the next parm.  This MACRO is the interface to the approptiate routine which
;³ modifies the list of strings or keywords in the VALUES block.
;³
;³
;³
;³
;³
;³  INPUT: item_type - scalar indicating that a string or keyword is to be deleted
;³
;³	   item   - A scalar immediate that indicates the string or keyword to
;³		     be "deleted"
;³
;³
;³  RETURN: none
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:     "item" is put into BX.
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³  ASSUMPTIONS: All the input are valid.
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

delete_parser_value_list_entry	 MACRO item_type,item

;MOV   BX,item
CALL  item_type

ENDM


;-------------------------------------------------------------------------------

;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ MODIFY_PARSER_CONTROL_BLOCK
;³ ---------------------------
;³
;³ As the logic in PARSE_PARAMETERS proceeds the posibilities for the next parm
;³ become apparent and the parser control blocks need to be changed to correctly
;³ parse the next parm.  This MACRO is the interface to the routines that modify
;³ those control blocks.
;³
;³
;³
;³
;³
;³  INPUT: control_structure - A scalar immediate indicating the control block
;³			       to be modified, and the routine to call.
;³
;³	   action - A scalar immediate that indicates the nature
;³		      of the modification to be made.
;³
;³	   item   - A scalar immediate that indicates the string, number,
;³		      keywords, switch, or match flags mask involved.
;³
;³  RETURN: none
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:	 The scalar value for the modifier will be put in a register
;³		 for passing to the routine that actually does the work.
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³  ASSUMPTIONS: All the input are valid.
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

modify_parser_control_block  MACRO    control_structure,action,item

PUSH  BX

MOV   BX,action
MOV   AL,item
CALL  control_structure

POP   BX

ENDM

;-------------------------------------------------------------------------------


;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  M A C R O S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼



;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  E Q U A T E S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º


INCLUDE modequat.inc


addd		     EQU   0  ;;AN000;used for "seperator_list"
binary_to_ASCII      EQU   30H	    ;AN000;used to convert bytes from binary to ASCII
blank		     EQU   " ";;AN000;used for "seperator_list"
both		     EQU   2	    ;AN000;value of rate_and_delay_found when both have been found
comma		     EQU   ","      ;AN000;used to tell the difference between a blank delimeter and missing parm, see LPTX,:
current_parm	     EQU   0  ;;AN000;scalar for parser control block modifing routine "keywords"
current_parm_DI     EQU     DI	    ;;AN000;index for parm_list array
delete		     EQU   1  ;AN000;;used for "seperator_list"
deleted        EQU	0     ;AN000;;used to make keywords unmatchable and strings of length zero
end_of_line_char_0D  EQU   0DH	    ;AN000;put at end of the command line by the loader
end_of_line_char_00  EQU   00H	    ;AN000;put at end of the complex parm by the parser
i_CL		     EQU   CL	    ;;AN000;loop index
include_string_list  EQU   3	    ;;AN000;number of value definitions so strings are included
include_number_list  EQU   2	    ;;AN000;See "nrng" in description of "values" block input for generalized parser
keyword 	     EQU   58H	    ;;AN000;indicator parms are in keyword form vs positional, value for parms_form
first_com_keyword    EQU   SI	    ;;AN000;holder for "first_com_keyword_ptr"
last_com_keyword     EQU   SI	    ;;AN000;holder for "last_com_keyword_ptr"
first_LPT_keyword    EQU   SI	    ;;AN000;holder for "first_LPT_keyword_ptr"
last_LPT_keyword     EQU   SI	    ;;AN000;holder for "last_LPT_keyword_ptr"
first_CON_keyword    EQU   SI	    ;;AN000;holder for "first_con_keyword_ptr"
last_CON_keyword     EQU   SI	    ;;AN000;holder for "last_con_keyword_ptr"
max_parms	     EQU   16	    ;;AN000;con cp prep=((1,2,3,4,5,6,7,8,9,10,11,12) filespec.cpi)
min_codepage_value   EQU   0
max_codepage_value   EQU   999	    ;;AN000;three digits
max_number_of_codepages EQU   12     ;AN000;assure that user does not specify too many code page numbers
min_number_of_codepages EQU   1
min_old_com_pos_parms  EQU	0    ;AN000;could have nothing else meaning status request
max_old_com_pos_parms  EQU	5    ;AN000; ;baud, parity, data bits, stop bits, P
max_switches	     EQU   1  ;AN000;;only switch is /status
no_message	     EQU   0  ;AN000;indicate to message handler interface that no message to issue
none_found	     EQU   0  ;AN000;;if keyword_switch_ptr is returned as zero then parser did not encounter a keyword or switch
not_in_switch_list   EQU   3
number_of_printer_status_qualifiers    EQU   4	;;AN000;codepage, prepare, select, RETRY
parm_list	     EQU   [BX]
parms_BX	     EQU   [BX]
parser_return_code_AX	EQU   AX
PS2		     EQU   44H			;AC002;flag for "type_of_machine"
result_BP	     EQU   [BP]
range_item_tag	     EQU   55H	    ;AN000;;marker for checks in memory, otherwise just a holder
ranges_only	     EQU   1  ;;AN000;See "nrng" in description of "values" block input for generalized parser
start_of_keyword_ptrs	EQU   [BP]	  ;AN000;;used for indexing the list of offsets in check_for_keyword
tab			EQU   09
unspecified		EQU   0FFH	  ;AN000;item tag of parm not specified: skipped optional positional parm


;possible values for "parm_type", the type of parm returned by parser

complx		     EQU   4
number		     EQU   1
string		     EQU   3

;possible values for "return_code_AX"

no_error	     EQU   0		  ;AN000;;not the same as "noerror"
operand_missing      EQU   2
syntax_error_rc      EQU   9
end_of_command_line  EQU   -1
end_of_complex	     EQU   -1		  ;AN000;found 0 that parser wrote over closing ")" of complex



;possible values of "device_type"

COMX				 EQU   09CH
;CON				  EQU	0
LPTX				 EQU   09BH
;LPT1				  EQU	0


;possible values of "request_type"

max_request_type		 EQU   09AH	;AN000;;must be same as following value
all_con_status			 EQU   09AH
codepage_prepare		 EQU   099H
codepage_refresh		 EQU   098H
codepage_select 		 EQU   097H
codepage_status 		 EQU   096H
codepage_prepared_status	 EQU   095H
codepage_selected_status	 EQU   094H
com_status			 EQU   093H
initialize_com_port		 EQU   092H
initialize_printer_port 	 EQU   091H
old_initialize_printer_port	 EQU   090H	;AN000;;found traditional syntax
old_video_mode_set		 EQU   08FH	;AN000;;found traditional syntax
printer_reroute 		 EQU   08EH
printer_status			 EQU   08DH
set_con_features		 EQU   08CH
status_for_everything		 EQU   08BH
turn_off_reroute		 EQU   08AH
last_request_type		 EQU   08AH	;AN000;;must be same as previous value


;possible codepage requests, used by modecp

select	       EQU   086H
prepare        EQU   085H
refresh        EQU   084H
;status 		;AN000;;see request_type possibilities



;possible values of "looking_for"


codepage					  EQU	  6FH
codepage_prms					  EQU	  6EH
com_keyword					  EQU	  6DH
com_keyword_or_baud				  EQU	  6CH
CON_keyword					  EQU	  6BH
con_kwrd_status_or_cp				  EQU	  6AH
databits_or_null				  EQU	  69H
device_name_or_eol				  EQU	  68H
eol						  EQU	  67H	;;AN000;end of line
first_parm					  EQU	  66H
li_or_null					  EQU	  65H
P						  EQU	  64H
parity_or_null					  EQU	  63H
prn_kw_status_cp_cl_null			  EQU	  62H
sd_or_dl					  EQU	  61H
sd_or_dl_or_eol 				  EQU	  60H
status_or_eol					  EQU	  5FH
stopbits_or_null				  EQU	  5EH
T_or_EOL					  EQU	  5DH

max_looking_for     EQU     6FH     ;AN000;;used for calculating the displacement into jump table for "CASE looking_for="




;item tags for COM port names strings

COM1_item_tag	     EQU   1	       ;;AN000;these values must be 1 through 4 because
COM2_item_tag	     EQU   2	       ;;AN000;parsing for COM special cases depends
COM3_item_tag	     EQU   3	       ;;AN000;on it.
COM4_item_tag	     EQU   4

;item tags for paritys

first_parity_item_tag	EQU   86H
mark_item_tag		EQU   86H
space_item_tag		EQU   85H
none_item_tag		EQU   84H
odd_item_tag		EQU   83H
even_item_tag		EQU   82H
last_parity_item_tag	EQU   82H


;item tags for printer port names

PRN_item_tag	     EQU   5
LPT1_item_tag	     EQU   6
LPT2_item_tag	     EQU   7
LPT3_item_tag	     EQU   8

;item tags for screen modes

first_screen_mode_item_tag    EQU   9
BW40_item_tag	     EQU   0BH
BW80_item_tag	     EQU   0CH
CO40_item_tag	     EQU   0DH
CO80_item_tag	     EQU   0EH
eighty_item_tag      EQU   0FH
fourty_item_tag      EQU   10H
MONO_item_tag	     EQU   11H
last_screen_mode_item_tag     EQU   11H

con_item_tag	     EQU   12H


;item tags for LPT special cases

first_lpt_special_case_item_tag  EQU   13H   ;;AN000;following value must be the same as this one
LPT1132_item_tag     EQU   13H
LPT2132_item_tag     EQU   14H
LPT3132_item_tag     EQU   15H
LPT180_item_tag      EQU   16H
LPT280_item_tag      EQU   17H
LPT380_item_tag      EQU   18H
last_lpt_special_case_item_tag	 EQU   18H   ;;AN000;this value must be the same as the previous

P_item_tag	     EQU   19H
RETRY_item_tag	     EQU   1AH
B_item_tag	     EQU   1BH
E_item_tag	     EQU   1CH
R_item_tag	     EQU   1DH

codepage_item_tag    EQU   1EH		  ;;AN000;for the range defining codepage possibilities
PREPARE_item_tag     EQU   1FH
SELECT_item_tag      EQU   20H
REFRESH_item_tag     EQU   21H

COLUMNS_item_tag     EQU   23H
DELAY_item_tag	     EQU   24H
LINES_item_tag	     EQU   25H
RATE_item_tag	     EQU   26H

COM_item_tag	     EQU   27H

ON_item_tag	     EQU   28H
OFF_item_tag	     EQU   29H

L_item_tag	     EQU   2AH
T_item_tag	     EQU   2BH

;item tags for numbers not in other lists

zero_item_tag		       EQU  2CH
first_stopbit_item_tag	       EQU  2DH
one_item_tag		       EQU  2EH
one_point_five_item_tag        EQU  2FH
two_item_tag		       EQU  30H
last_stopbit_item_tag	       EQU  31H
three_item_tag		       EQU  32H
four_item_tag		       EQU  33H
first_databit_item_tag	       EQU  34H
five_item_tag		       EQU  35H    ;AN000; ;data bit, typamatic rate
six_item_tag		       EQU  36H
seven_item_tag		       EQU  37H
eight_item_tag		       EQU  38H
last_databit_item_tag	       EQU  39H
nine_item_tag		       EQU  3AH
ten_item_tag		       EQU  3BH
eleven_item_tag 	       EQU  3CH    ;AN000;;first two chars of 110
twelve_item_tag 	       EQU  3DH
thirteen_item_tag	       EQU  3EH
fourteen_item_tag	       EQU  3FH
fifteen_item_tag	       EQU  40H    ;AN000;;abbreviated form of 150, 15 is also a RATE= candidate
sixteen_item_tag	       EQU  41H
seventeen_item_tag	       EQU  42H
eighteen_item_tag	       EQU  43H
nineteen_item_tag	       EQU  44H    ;AN000;;used for baud rates and RATE=
twenty_item_tag 	       EQU  45H
twentyone_item_tag	       EQU  46H
twentytwo_item_tag	       EQU  47H
twentythree_item_tag	       EQU  48H
twentyfour_item_tag	       EQU  49H    ;AN000;    ;24 is also a typamatic rate
twentyfive_item_tag	       EQU  4AH
twentysix_item_tag	       EQU  4BH
twentyseven_item_tag	       EQU  4CH
twentyeight_item_tag	       EQU  4DH
twentynine_item_tag	       EQU  4EH
thirty_item_tag 	       EQU  4FH
thirtyone_item_tag	       EQU  50H
thirtytwo_item_tag	       EQU  51H
fourtythree_item_tag	       EQU  52H
fifty_item_tag		       EQU  53H
sixty_item_tag		       EQU  54H
oneten_item_tag 	       EQU  55H
onethirtytwo_item_tag	       EQU  56H
onefifty_item_tag	       EQU  57H
threehundred_item_tag	       EQU  58H
sixhundred_item_tag	       EQU  59H
twelvehundred_item_tag	       EQU  5AH
twentyfourhundred_item_tag     EQU  5BH
fourtyeighthundred_item_tag    EQU  5CH
ninetysixhundred_item_tag      EQU  5DH
nineteentwohundred_item_tag    EQU  5EH


;mask values for function_flags

capitalize     EQU   0001H     ;AN000;capitalize by file table


;mask values for match flags

numeric        EQU   8000H
simple_string  EQU   2000H
complex        EQU   0400H
filespec       EQU   0200H
ignore_colon   EQU   0010H
optional       EQU   0001H
clear_all      EQU   0000H

;delete_simple_string	 EQU   0CFFFH	;AN000;;NOT (simple_string), to turn off simple_string bit in the match_flags




;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  E Q U A T E S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼



;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  S T R U C T U R E S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º


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


INCLUDE  COMMON.STC	;contains the following strucs, needed in invoke also


;parm_list_entry   STRUC
;
;parm_type	      DB       bogus
;item_tag	      DB       0FFH
;value1 	      DW       bogus
;value2 	      DW       bogus
;keyword_switch_ptr   DW    0
;
;parm_list_entry   ENDS


;codepage_parms STRUC
;   cp_device	   DW	 ?
;   des_pack_ptr   DW	 ?
;   font_filespec  DW	 ?
;   request_typ    DW	 ?
;codepage_parms ENDS


parms_def      STRUC

parmsx_ptr	  DW	  bogus 	  ;AN000;changed as the possibilities for parms following are determined
		  DB	  1		  ;AN000;have extra delimiter list
seperators_len	  DB	  1		  ;AN000;length of extra delimiter list
seperators	  DB	  ";"             ;AC003;EXTRA DELIMITER LIST
		  DB	  8 DUP (" ")     ;AC003; extra blanks for adding more delimeters (. " \ [ ] : + =)

parms_def      ENDS



result_def     STRUC

ret_type  DB	   0
ret_tag   DB	   0FFH
synonym   DW	   0
ret_value1 DW	    bogus
ret_value2 DW	    bogus

result_def     ENDS







;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  S T R U C T U R E S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼



	PAGE
PRINTF_CODE SEGMENT PUBLIC
	ASSUME	CS:PRINTF_CODE,DS:PRINTF_CODE,SS:PRINTF_CODE


;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P U B L I C S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º

PUBLIC	 all_con_status
PUBLIC	 baud_equal
PUBLIC	 B_item_tag	   ;needed by modecom
PUBLIC	 B_str
PUBLIC	 BW40_item_tag
PUBLIC	 BW80_item_tag
PUBLIC	 codepage_index_holder	    ;make available to invoke
PUBLIC	 codepage_item_tag
PUBLIC	 codepage_prepare
PUBLIC	 codepage_prepared_status
PUBLIC	 codepage_refresh
PUBLIC	 codepage_selected_status
PUBLIC	 COM_status
PUBLIC	 COMX			    ;make available to rescode
PUBLIC	 CON_str	      ;AN000;make available to invoke for messages
PUBLIC	 CO40_item_tag
PUBLIC	 CO80_item_tag
PUBLIC	 codepage_item_tag
PUBLIC	 codepage_select
PUBLIC	 codepage_status
PUBLIC	 columns_equal
PUBLIC	 COLS_equal
PUBLIC	 columns_item_tag
PUBLIC	 COM1_str
PUBLIC	 COM2_str
PUBLIC	 COM3_str
PUBLIC	 COM4_str
PUBLIC	 data_equal	      ;AN000;used by invoke
PUBLIC	 delay_equal
PUBLIC	 del_equal
PUBLIC	 des_start_packet
PUBLIC	 device_name
PUBLIC	 device_type	      ;AN000;make available to rescode
PUBLIC	 E_item_tag		    ;needed by modecom
PUBLIC	 E_str
PUBLIC	 eight_item_tag       ;AN000;used by setcom
PUBLIC	 eighty_item_tag
PUBLIC	 eighty_str
PUBLIC	 even_item_tag	      ;AN000;used by setcom
PUBLIC	 five_item_tag	      ;AN000;used in setcom
PUBLIC	 fourtyeighthundred_item_tag	  ;used by setcom
PUBLIC	 fourtyeighthundred_str 	  ;used by setcom
PUBLIC	 fourty_item_tag
PUBLIC	 fourty_str
PUBLIC	 initialize_com_port
PUBLIC	 initialize_printer_port
PUBLIC	 keyword	      ;AN000;make available to invoke.asm
PUBLIC	 len_COMX_str	      ;AN000;make available to invoke.asm
PUBLIC	 len_CON_str	      ;AN000;make available to invoke.asm for message service
PUBLIC	 len_LPTX_str	      ;AN000;make available to invoke.asm
PUBLIC	 lines_equal
PUBLIC	 lines_item_tag
PUBLIC	 L_item_tag
PUBLIC	 LPTX		      ;AN000;make available to rescode
PUBLIC	 LPT1_str
PUBLIC	 LPT2_str
PUBLIC	 LPT3_str
PUBLIC	 mark_item_tag	      ;AN000;used in setcom
PUBLIC	 max_request_type
PUBLIC	 mono_item_tag
PUBLIC	 new_com_initialize		  ;AC002;make available for modecom
PUBLIC	 nineteentwohundred_item_tag	   ;AN000;used by modecom
PUBLIC	 nineteentwohundred_str 	   ;AN000;used by modecom
PUBLIC	 ninetysixhundred_item_tag
PUBLIC	 ninetysixhundred_str
PUBLIC	 none_item_tag	      ;AN000;used in invoke
PUBLIC	 NONE_str
PUBLIC	 OFF_item_tag
PUBLIC	 OFF_str
PUBLIC	 odd_item_tag	      ;AN000;  ;used by setcom
PUBLIC	 old_initialize_printer_port
PUBLIC	 old_video_mode_set
PUBLIC	 one_item_tag		    ;used in setcom
PUBLIC	 one_point_five_item_tag    ;used in setcom
PUBLIC	 one_point_five_str	    ;used in setcom
PUBLIC	 onefifty_item_tag	    ;used in setcom
PUBLIC	 onefifty_str		    ;used in setcom
PUBLIC	 oneten_item_tag	    ;used in modecom
PUBLIC	 oneten_str		    ;used in modecom
PUBLIC	 onethirtytwo_item_tag
PUBLIC	 ON_item_tag
PUBLIC	 ON_str
PUBLIC	 P_item_tag		    ;make available to modecom
PUBLIC	 parity_equal		    ;used in analyze_and_invoke
PUBLIC	 parm_lst		    ;used in modecom.asm
PUBLIC	 parms_form		    ;make available to invoke
PUBLIC	 parse_parameters
PUBLIC	 prepare
PUBLIC	 prepare_item_tag
PUBLIC	 printer_reroute
PUBLIC	 printer_status
PUBLIC	 R_item_tag
PUBLIC	 R_str
PUBLIC	 rate_equal
PUBLIC	 refresh
PUBLIC	 request_type
PUBLIC	 reroute_requested	      ;make available to rescode
PUBLIC	 retry_equal_str	       ;make available to invoke
PUBLIC	 retry_item_tag
PUBLIC	 retry_requested	    ;make available to rescode
PUBLIC	 select
PUBLIC	 select_item_tag
PUBLIC	 set_con_features
PUBLIC	 seven_item_tag 	    ;used by setcom
PUBLIC	 sixhundred_item_tag	    ;used by setcom
PUBLIC	 sixhundred_str 	    ;used by setcom
PUBLIC	 six_item_tag		    ;used by setcom
PUBLIC	 space_item_tag 	    ;used by setcom
PUBLIC	 status_for_everything
PUBLIC	 stop_equal
PUBLIC	 T_item_tag
PUBLIC	 threehundred_item_tag	    ;used by setcom
PUBLIC	 threehundred_str	    ;used by setcom
PUBLIC	 turn_off_reroute
PUBLIC	 twelvehundred_item_tag      ;used by setcom
PUBLIC	 twelvehundred_str	     ;used by setcom
PUBLIC	 twentyfourhundred_item_tag	 ;used by setcom
PUBLIC	 twentyfourhundred_str		 ;used by setcom
PUBLIC	 two_item_tag		    ;used by setcom

;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P U B L I C S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼


;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  E X T R N S	ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º

;EXTRN	 command_line:BYTE		 ;AN000;PARM AREA
;EXTRN	 command_line_length:BYTE	 ;AN000;NUMBER OF BYTES OF PARM AREA
EXTRN	com1_or_com2:BYTE	    ;AN000;see modedefs.inc
EXTRN	cp_cb:WORD	      ;AN000;codepage_parms <> ;codepage subroutine parameter block
EXTRN	CRLF:WORD		       ;displayed before "Invalid parameter - " for consistent spacing
EXTRN	DES_STRT_FL_CART:ABS		     ;AN000;;CARTRIDGE prepare
EXTRN	device:BYTE		       ;AN000;holder for com number, used in setcom
EXTRN	first_char_in_command_line:BYTE ;AN000;location of the command line parameters
EXTRN	 function_not_supported:BYTE   ;AN000;see modedefs.inc
EXTRN	get_machine_type:NEAR		;AN000;get model and sub-model bytes
EXTRN	invalid_parameter:BYTE		;AN000;CR,LF,"Invalid parameter - '????'"CR,LF,BEEP
EXTRN	LPTNO:BYTE	      ;AN000;holder of ASCII version of printer number, see first_parm_case and modeprin
EXTRN	machine_type:BYTE	    ;AN000;see get_machine_type
EXTRN	modecp:NEAR
EXTRN	move_destination:ABS	    ;AN000;location of res code after it has been moved
EXTRN	noerror:BYTE
EXTRN	 not_supported_ptr:WORD     ;AN000;holder of address of string that describes what is not supported, see modedefs.inc
EXTRN	 offending_parameter:BYTE	  ;AC006;the holder of the text string that was wrong.
EXTRN	offending_parameter_ptr:WORD	   ;AN000;;see MODEMES
EXTRN	printer_no:BYTE 	       ;AN000;;see modeprin
EXTRN	PRINTF:NEAR
EXTRN	rate_and_delay_together:BYTE   ;AN000;RATE and DELAY must be specified together
EXTRN	 syntax_error_ptr:WORD	       ;AN000;pointer to parameter with bad format

;possible values of "message"

EXTRN	baud_rate_required:BYTE
EXTRN	invalid_number_of_parameters:WORD
EXTRN	Invalid_switch:BYTE
EXTRN	syntax_error:BYTE


;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  E X T R N S	ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼


;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  D A T A	ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º

code_page_numbers_encountered	 DB    0
current_packet_cp_number   DW	 -2  ;adjustment for accessing current 'des_strt_pkcp?' in 'des_start_packet'
EOL_found		DB	 false
looking_for		DB	 bogus	  ;semantic analysis state, can be one of:
match_not_found 	DB	 true	  ;indication that a token was found in the list of keywords



des_start_packet	des_strt_packet <>

;----------------------------	   NEW DATA  ---------------------------------



baud_specified		DB    false
codepage_index_holder	DW    bogus	  ;AN000;;holder for index in parm_list of the selected code page
colon			DB    ":"
command_line		DW    0081H	  ;AN000;  ;holder for pointer to unparsed part of the command line, see "parse_parm"
device_name		DW    0 	  ;AN000;;OFFSET device name string, see "analyze_and_invoke" in invoke.asm
device_type		DB    bogus
end_of_seperator_list	DW    bogus	  ;AN000;;loop terminator,word because compared with DI
match_found		DB    false	  ;AN000;   ;boolean loop terminator
message 		DW    no_message
new_com_initialize	DB    false	  ;AC002;flag for modecom to indicate PS/2 only parm specified
number_of_keywords	DB    0 	  ;AN000;;input for check_for_keyword
parms_form		DB    0 	  ;AN000;;holder for indicator of whether the parms were in keyword or positonal form
ordinal 		DW    0
rate_and_delay_found	DB    false	  ;AN000;need to have both, this byte keeps track of what has been found
request_type		DB    bogus
reroute_requested	DB    false
retry_requested 	DB    false
search_stop		DB    0 	  ;AN000;;loop stopper for search_item_tags
status_found		DB    false	  ;AN000;;boolean indicator that /status has been found
status_request		DB    bogus	  ;AN000;;furthur clarification. possible values are: bogus, true, and false
terminating_delimeter	DB    bogus	  ;AN000;;save return from sysparse
type_of_machine 	DB    bogus	  ;AC000;"get_machine_type" determines "machine_type", this byte is general flag for PS/2s


;	PARSER interface data
;---------------------------------------

start_com_keyword_ptrs	LABEL WORD
first_com_keyword_ptr	DW    OFFSET   baud_equal
			DW    OFFSET   parity_equal
			DW    OFFSET   data_equal
			DW    OFFSET   stop_equal
last_com_keyword_ptr	DW    OFFSET   retry_equal_str
number_of_com_keywords	EQU   ($ - start_com_keyword_ptrs)/2


start_LPT_keyword_ptrs	LABEL WORD
first_LPT_keyword_ptr	DW    OFFSET   retry_equal_str
			DW    OFFSET   COLUMNS_equal
			DW    OFFSET   COLS_equal
last_LPT_keyword_ptr	DW    OFFSET   LINES_equal
number_of_LPT_keywords	EQU   ($ - start_LPT_keyword_ptrs)/2


start_CON_keyword_ptrs	LABEL WORD
first_CON_keyword_ptr	DW    OFFSET   COLUMNS_equal
			DW    OFFSET   COLS_equal
			DW    OFFSET   LINES_equal
			DW    OFFSET   RATE_equal
			DW    OFFSET   DELAY_equal
last_CON_keyword_ptr	DW    OFFSET   DEL_equal
number_of_CON_keywords	EQU   ($ - start_CON_keyword_ptrs)/2



parms	 parms_def<>		 ;AN000;set up for first_parm_case, except parmsx_ptr needs to be set


parmsx	 LABEL	BYTE

   DB	    0		       ;AN000;how many non-switch/non-keyword parms are required
   DB	    3		       ;AN000;max pos parms for this parmsx, use others for further parms
   DW	    first_pos_control  ;AN000;control block for every possible (non-mutatant) first positional parm
   DW	    second_pos_control
   DW	    third_pos_control

   DB	    max_switches
   DW	    max_switches DUP (Sw_control)

   DB	    max_keywords	 ;AN000;number of unique keywords for all options

start_keyword_list   LABEL BYTE

   DW	    LPT1_colon_equal_control
   DW	    LPT1_equal_control
   DW	    LPT2_colon_equal_control
   DW	    LPT2_equal_control
   DW	    LPT3_colon_equal_control
   DW	    LPT3_equal_control

   DW	    RETRY_equal_control  ;AN000;for parallel and serial printers

   DW	    COLUMNS_equal_control
   DW	    LINES_equal_control     ;AN000;;this and previous MUST OCCUR IN THIS ORDER
   DW	    PREPARE_equal_control
   DW	    SELECT_equal_control

max_keywords   EQU   ($ - start_keyword_list) / 2   ;AN000;two bytes per entry



con_parmsx   LABEL  BYTE	     ;AN000;for keyword form of con support

   DB	    0		       ;AN000;no positional parms required after CON
   DB	    2		       ;AN000;CP and REFRESH allowed
   DW	    first_CON_pos_control    ;AN000;control block for CP
   DW	    second_CON_pos_control  ;AN000;control block for REFRESH

   DB	    max_switches
   DW	    max_switches DUP (Sw_control)

   DB	    number_of_CON_keywords	   ;AN000;number of unique keywords for CON

start_con_keyword_list	 LABEL BYTE

   DW	    COLUMNS_equal_control
   DW	    LINES_equal_control
   DW	    PREPARE_equal_control
   DW	    SELECT_equal_control

   DW	    DELAY_equal_control
   DW	    RATE_equal_control

number_of_con_keywords	 EQU   ($ - start_con_keyword_list) / 2   ;AN000;two bytes per entry


old_con_parmsx	 LABEL	BYTE

   DB	    0		       ;AN000;no positional parms required after 80, co40 etc.
   DB	    2		       ;AN000;shift direction and "T" allowed
   DW	    first_old_CON_pos_control	 ;AN000;shift direction and display lines
   DW	    second_old_CON_pos_control	;AN000;control block for T

   DB	    0				  ;AN000;no switches

   DB	    0				  ;AN000;no keywords for old CON


lpt_parmsx   LABEL  BYTE	     ;AN664;for the second thru 4th parms, [[chars/line][[,lines/inch][[,P]]]]

   DB	    0		       ;AN000;how many non-switch/non-keyword parms are required
   DB	    3		       ;AN000;max pos parms for this parmsx, use others for further parms
   DW	    first_lpt_pos_control  ;AN000;control block for every possible chars per line value
   DW	    second_lpt_pos_control
   DW	    third_lpt_pos_control

   DB	    max_switches
   DW	    max_switches DUP (Sw_control)

   DB	    max_lpt_keywords	     ;AN000;number of unique keywords for all options

start_lpt_keyword_list	 LABEL BYTE

   DW	    RETRY_equal_control  ;AN000;for parallel printers

   DW	    COLUMNS_equal_control
   DW	    LINES_equal_control     ;AN000;;this and previous MUST OCCUR IN THIS ORDER
   DW	    PREPARE_equal_control
   DW	    SELECT_equal_control

max_lpt_keywords   EQU	 ($ - start_keyword_list) / 2	;AN000;two bytes per entry


prepare_equal_parmsx LABEL BYTE

   prepare_min_parms LABEL BYTE 				;AN000;changed by hardware cp code to allow no filename
   DB	    min_number_of_codepages
   DB	    max_number_of_codepages
   DW	    max_number_of_codepages DUP (prepare_equal_control)
   DB	    max_switches
   DW	    max_switches DUP (Sw_control)
   DB	    0				  ;AN000;no more keywords allowed

com_parmsx   LABEL  BYTE

		    DB	     min_old_com_pos_parms	;AN000;nothing or /STATUS
		    DB	     max_old_com_pos_parms	;AN000;baud, parity, data, stop, p
		    DW	     baud_control
		    DW	     old_com_parity_control
		    DW	     old_com_databits_control	;AN000;control block for old com data bits
		    DW	     old_com_stopbits_control
retry_control_ptr   DW	     old_com_retry_control

		    DB	     max_switches
		    DW	     max_switches DUP (Sw_control)

		    DB	     number_of_com_keywords

start_com_keyword_list	 LABEL BYTE

		    DW	     BAUD_control
		    DW	     PARITY_equal_control
		    DW	     DATA_equal_control
		    DW	     STOP_equal_control
		    DW	     RETRY_equal_control	;AN000;same as for printers

number_of_com_keywords	 EQU   ($ - start_com_keyword_list) / 2  ;AN000;two bytes per entry


com_keywords_parmsx   LABEL  BYTE

   DB	    0			       ;AC663;no positional parms valid
   DB	    0

   DB	    0

   DB	    number_of_com_keywords

   DW	    BAUD_control
   DW	    PARITY_equal_control
   DW	    DATA_equal_control
   DW	    STOP_equal_control
   DW	    RETRY_equal_control        ;AC663;same as for printers



mutant_com_parmsx   LABEL  BYTE 	     ;AN000;for trash like COM19600

   DB	  2			    ;AN000;;must find "COM" and a baud rate
   DB	  2			    ;AN000;;"COM", baud
   DW	  COM_control
   DW	  baud_control	    ;AN000;use same as other com parmsx

   DB	    0			       ;AN000;no switches

   DB	    0			       ;AN000;no keywords

com_control  LABEL BYTE 	       ;AN000;for mutant_com_parmsx

	       DW	simple_string	 ;AN000;"COM", not optional
	       DW	0		  ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	com_value
	       DB	0		  ;AN000;no synonyms



old_com_parity_control	LABEL BYTE

	       DW	simple_string+optional	;AC000;n, o, e are strings
	       DW	0			;AC000;don't capitalize, leave colon
	       DW	result
	       DW	PARITY_values
	       DB	0			;AC000;;no synonyms


old_com_DATAbits_control   LABEL BYTE

	       DW	simple_string+optional
	       DW	0			;AC000;;don't capitalize, leave colon
	       DW	result
	       DW	DATA_values
	       DB	0



old_com_STOPbits_control   LABEL BYTE

	       DW	simple_string+optional
	       DW	0			;AC000;;don't capitalize, leave colon
	       DW	result
	       DW	STOP_values
	       DB	0



old_com_RETRY_control	LABEL BYTE

	       DW	simple_string+optional	;AC000;;all that is legal for RETRY is P for old com format
	       DW	0			;AC000;;don't capitalize, never need to display to user
	       DW	result
	       DW	RETRY_values
	       DB	0


com_value    LABEL    BYTE	     ;AC000;"COM" for mutant_com_parmsx

   DB	    include_string_list      ;AC000;have list of strings

   DB	    0

   DB	    0			     ;AC000;no number choices

   DB	    1			     ;AC000;just "COM"

   DB	    COM_item_tag
   DW	    OFFSET COM_str


first_pos_control  LABEL BYTE		     ;AN000;initialized for first_parm_case

match_flags    DW	simple_string+optional	 ;***  +ignore_colon  *** ;AN000;2011, all that is legal for non-/status first parm
function_flags DW	0010H			;AN000;don't capitalize, remove colon at end
	       DW	result
values_ptr     DW	first_pos_values
	       DB	0		     ;AN000;no keywords as positionals


second_pos_control  LABEL BYTE		      ;AN000;initialized for first_parm_case

match_flags2	  DW	   simple_string+optional+ignore_colon	;AN000;2011, all that is legal for non-/status first parm
function_flags2   DW	   0010H		   ;AN000;don't capitalize, remove colon at end
		  DW	   result
values_ptr2	  DW	   second_pos_values
		  DB	   0			;AN000;;no keywords as positionals

third_pos_control  LABEL BYTE		     ;AN000;initialized for first_parm_case

match_flags3	  DW	   simple_string+optional+ignore_colon	;AN000;2011, all that is legal for non-/status first parm
function_flags3   DW	   0010H		   ;AN000;don't capitalize, remove colon at end
		  DW	   result
values_ptr3	  DW	   third_pos_values
		  DB	   0			;AN000;;no keywords as positionals

first_lpt_pos_control  LABEL BYTE		 ;AN000;chars per line

	       DW	simple_string+optional	;AN000;2001, all that is legal for chars per line
	       DW	0000H			;AN000;don't capitalize
	       DW	result
	       DW	first_lpt_pos_values
	       DB	0		     ;AN000;no keywords as positionals


second_lpt_pos_control	LABEL BYTE		  ;AN000;lines per inch

		  DW	   simple_string+optional  ;AN000;2001, all that is legal for chars per line
		  DW	   0000H		   ;AN000;don't capitalize
		  DW	   result
		  DW	   second_lpt_pos_values
		  DB	   0			;AN000;;no keywords as positionals

third_lpt_pos_control  LABEL BYTE		 ;AN000;P

		  DW	   simple_string+optional  ;AN000;2001, all that is legal for retry settings
		  DW	   0000H		   ;AN000;don't capitalize
		  DW	   result
		  DW	   third_lpt_pos_values
		  DB	   0			;AN000;;no keywords as positionals



BAUD_control  LABEL BYTE		  ;AN000;used for positional and keyword form

	       DW	simple_string	  ;AN000;required
	       DW	0			;AN000;don't capitalize
	       DW	result
	       DW	BAUD_values
	       DB	1		    ;AN000;;only one form of the keyword

BAUD_equal     DB    "BAUD=",0


parity_equal_control  LABEL BYTE		    ;AN000;initialized for first_parm_case

	       DW	simple_string		;AN000;n, o, even, m, space etc are strings
	       DW	0			;AN000;don't capitalize, leave colon
	       DW	result
	       DW	PARITY_values
	       DB	2			;two ways to specify it

parity_equal   DB    "PARITY=",0
par_equal      DB    "PAR=",0



DATA_equal_control   LABEL BYTE

	       DW	simple_string
	       DW	0			;AN000;;don't capitalize, leave colon
	       DW	result
	       DW	DATA_values
	       DB	1

data_equal     DB    "DATA=",0



STOP_equal_control   LABEL BYTE

	       DW	simple_string
	       DW	0			;AN000;;don't capitalize, leave colon
	       DW	result
	       DW	STOP_values
	       DB	1

stop_equal     DB    "STOP=",0



RETRY_equal_control   LABEL BYTE

	       DW	simple_string		;AN000;;all that is legal for RETRY is on and off
	       DW	0			;AN000;;don't capitalize, never need to display to user
	       DW	result
	       DW	RETRY_values
	       DB	1

retry_equal_str DB    "RETRY=",0



PREPARE_equal_control	LABEL BYTE

prepare_equal_match_flags  LABEL WORD
	       DW	numeric+complex+filespec  ;AN000;has to be complex at first, then numbers and filespec inside the parens
	       DW	capitalize	  ;AN000;capitalize the filespec
	       DW	result
	       DW	prepare_values
	       DB	2

prepare_equal  DB    "PREPARE=",0
prep_equal     DB    "PREP=",0


SELECT_equal_control   LABEL BYTE

	       DW	numeric 	  ;AN000;range of codepage numbers
	       DW	0		  ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	SELECT_values
	       DB	2	       ;AN000;no keywords as positionals

select_equal   DB    "SELECT=",0
sel_equal      DB    "SEL=",0


DELAY_equal_control   LABEL BYTE

	       DW	numeric        ;AN000;	;takes less space than number definitions
	       DW	0	       ;AN000;	;don't capitalize, leave colon
	       DW	result
	       DW	DELAY_values
	       DB	2

del_equal      DB    "DEL=",0
delay_equal    DB    "DELAY=",0


RATE_equal_control   LABEL BYTE

	       DW	numeric
	       DW	0	       ;AN000;	;don't capitalize, leave colon
	       DW	result
	       DW	RATE_values
	       DB	1

rate_equal     DB    "RATE=",0



LINES_equal_control   LABEL BYTE

LINES_match_flag  DW	   numeric     ;AN000;	   ;setup for CON, changed if find LPTX
		  DW	   0	       ;AN000;	   ;don't capitalize, leave colon
		  DW	   result
LINES_value_ptr   DW	   CON_LINES_values
		  DB	   1

lines_equal	  DB	"LINES=",0



COLUMNS_equal_control	LABEL BYTE

COLUMNS_match_flag   DW       numeric	    ;AN000;   ;setup for CON changed when find LPTX
		     DW       0 	    ;AN000;   ;don't capitalize, leave colon
		     DW       result
COLUMNS_value_ptr    DW       CON_COLUMNS_values      ;AN000;setup for CON, changed if find LPTX
		     DB       2

COLUMNS_equal	     DB    "COLUMNS=",0      ;AN000;printer keyword
COLS_equal	     DB    "COLS=",0


LPT1_colon_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;COM?[:] is all that is valid
	       DW	0		 ;AN000;;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT1_colon_equal  DB "LPT1:=",0



LPT1_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;COM?[:] is all that is valid
	       DW	0			;AN000;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT1_equal	  DB "LPT1=",0



LPT2_colon_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;COM?[:] is all that is valid
	       DW	0		 ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT2_colon_equal  DB "LPT2:=",0



LPT2_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;;COM?[:] is all that is valid
	       DW	0		 ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT2_equal	  DB "LPT2=",0



LPT3_colon_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;COM?[:] is all that is valid
	       DW	0		 ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT3_colon_equal  DB "LPT3:=",0



LPT3_equal_control   LABEL BYTE

	       DW	simple_string+ignore_colon   ;AN000;COM?[:] is all that is valid
	       DW	0		  ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	reroute_values
	       DB	1

LPT3_equal	  DB "LPT3=",0

first_con_pos_control	LABEL BYTE

	       DW	simple_string	  ;AN000;CP, code, codepage
	       DW	0		  ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	OFFSET	 first_CON_pos_values
	       DB	0		  ;AN000;no synonyms


second_con_pos_control	 LABEL BYTE

	       DW	simple_string	  ;AN000;REFRESH
	       DW	0		  ;AN000;don't capitalize, leave colon
	       DW	result
	       DW	OFFSET	 second_CON_pos_values
	       DB	0		  ;AN000;no synonyms

first_old_con_pos_control   LABEL BYTE

	       DW	simple_string+numeric  ;AN000;r, l or screen lines request
	       DW	0		  ;AN000;don't capitalize
	       DW	result
	       DW	OFFSET	 first_old_CON_pos_values
	       DB	0		  ;AN000;no synonyms


second_old_con_pos_control   LABEL BYTE

	       DW	simple_string+optional	   ;AN000;T
	       DW	0		  ;AN000;don't capitalize
	       DW	result
	       DW	OFFSET	 second_old_CON_pos_values
	       DB	0		  ;AN000;no synonyms

first_old_CON_pos_values    LABEL    BYTE      ;all valid forms of shift direction, and screen line values

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0			     ;no number ranges

   DB	    number_of_CON_lines_numbers      ;number of rows choices

   DB	    twentyfive_item_tag
   DD	    25
   DB	    fourtythree_item_tag
   DD	    43
   DB	    fifty_item_tag
   DD	    50

   DB	    number_of_shift_forms      ;number of shift strings AN000;

   start_shift_forms   LABEL	BYTE


   DB	    R_item_tag
   DW	    OFFSET R_str
   DB	    L_item_tag
   DW	    OFFSET L_str


   number_of_shift_forms  EQU	($ - start_shift_forms)/3	;3 bytes per entry


second_old_CON_pos_values    LABEL    BYTE	;all valid forms of T

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0			     ;no number ranges

   DB	    0			    ;no number list

   DB	    number_of_T_forms	   ;number of T strings AN000;

   start_T_forms   LABEL    BYTE


   DB	    T_item_tag
   DW	    OFFSET T_str


   number_of_T_forms  EQU   ($ - start_T_forms)/3	;3 bytes per entry


first_CON_pos_values	LABEL	 BYTE	   ;all valid forms of codepage

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0			     ;no number ranges

   DB	    0			    ;no number list

   DB	    number_of_CP_forms	    ;number of cp strings AN000;

   start_CP_forms   LABEL    BYTE


   ;codepage strings

   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODEPAGE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CP_str

   ;invalid choice, included for usable error reporting: if come across refresh right after CON then issue invalid number of parms

   DB	    REFRESH_item_tag
   DW	    OFFSET REF_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REFRESH_str

   number_of_CP_forms  EQU   ($ - start_CP_forms)/3	  ;3 bytes per entry


second_CON_pos_values	 LABEL	  BYTE	    ;all valid forms of REFRESH

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0			     ;no number ranges

   DB	    0			    ;no number list

   DB	    number_of_REFRESH_forms	 ;number of REFRESH strings AN000;

   start_REFRESH_forms	 LABEL	  BYTE

   DB	    REFRESH_item_tag
   DW	    OFFSET REF_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REFRESH_str

   number_of_REFRESH_forms  EQU   ($ - start_REFRESH_forms)/3	    ;3 bytes per entry


BAUD_values    LABEL	BYTE		 ;AN000;;all valid baud rates

   DB	    include_string_list      ;AN000;have list of numbers and two strings

   DB	    0

   DB	    0			 ;AN000;no numeric representations

   DB	    number_of_baud_strings   ;AN000;number of baud rates that are being used for other parameters also

   start_baud_strings	LABEL	 BYTE

   DB	    oneten_item_tag
   DW	    OFFSET oneten_str
   DB	    oneten_item_tag
   DW	    OFFSET eleven_str	;AN000;;"11" first two chars of 110
   DB	    onefifty_item_tag
   DW	    OFFSET fifteen_str
   DB	    onefifty_item_tag
   DW	    OFFSET onefifty_str
   DB	    threehundred_item_tag
   DW	    OFFSET thirty_str
   DB	    threehundred_item_tag
   DW	    OFFSET threehundred_str
   DB	    sixhundred_item_tag
   DW	    OFFSET sixty_str
   DB	    sixhundred_item_tag
   DW	    OFFSET sixhundred_str
   DB	    twelvehundred_item_tag
   DW	    OFFSET twelve_str
   DB	    twelvehundred_item_tag
   DW	    OFFSET twelvehundred_str
   DB	    twentyfourhundred_item_tag
   DW	    OFFSET twentyfour_str      ;AN000;24 is also a typamatic rate
   DB	    twentyfourhundred_item_tag
   DW	    OFFSET twentyfourhundred_str
   DB	    fourtyeighthundred_item_tag
   DW	    OFFSET fourtyeight_str
   DB	    fourtyeighthundred_item_tag
   DW	    OFFSET fourtyeighthundred_str
   DB	    ninetysixhundred_item_tag
   DW	    OFFSET ninetysix_str
   DB	    ninetysixhundred_item_tag
   DW	    OFFSET ninetysixhundred_str
   DB	    nineteentwohundred_item_tag      ;AN000;;item tag
   DW	    OFFSET nineteentwohundred_str ;AN000;;pointer to string
   DB	    nineteentwohundred_item_tag   ;AN000;;item tag
   DW	    OFFSET nineteen_point_two_str
   DB	    nineteentwohundred_item_tag   ;AN000;  ;item tag
   DW	    OFFSET nineteen_str 	  ;AN000;   ;used for RATE= also
   DB	    nineteentwohundred_item_tag   ;AN000;  ;item tag
   DW	    OFFSET nineteen_point_two_K_str ;AN000;pointer to string "19.2K"

   number_of_baud_strings  EQU	 ($ - start_baud_strings)/3  ;AN000;3 bytes per entry



PARITY_values	 LABEL	  BYTE		    ;AN000;all valid paritys

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0

   DB	    0			;AN000;;no number choices

   DB	    number_of_paritys	;AN000;;number of valid paritys

   start_paritys   LABEL    BYTE

   DB	    none_item_tag
   DW	    OFFSET N_str
   DB	    none_item_tag
   DW	    OFFSET NONE_str
   DB	    even_item_tag
   DW	    OFFSET EVEN_str
   DB	    even_item_tag
   DW	    OFFSET E_str
   DB	    odd_item_tag
   DW	    OFFSET O_str
   DB	    odd_item_tag
   DW	    OFFSET ODD_str
   DB	    MARK_item_tag
   DW	    OFFSET m_str
   DB	    MARK_item_tag
   DW	    OFFSET mark_str
   DB	    SPACE_item_tag
   DW	    OFFSET s_str
   DB	    SPACE_item_tag
   DW	    OFFSET space_str

   number_of_paritys  EQU   ($ - start_paritys)/3 ;AN000;3 bytes per entry


DATA_values    LABEL	BYTE		  ;AN000;all valid DATA values

   DB	    include_string_list  ;AC663;have list of numbers

   DB	    0			 ;AN000;no number ranges

   DB	    0			 ;AN000;no number choices

   DB	    number_of_databits	 ;AN000;string choices

   start_databits   LABEL    BYTE

   DB	    five_item_tag
   DW	    OFFSET five_str
   DB	    six_item_tag
   DW	    OFFSET six_str
   DB	    seven_item_tag
   DW	    OFFSET seven_str
   DB	    eight_item_tag
   DW	    OFFSET eight_str

   number_of_databits  EQU   ($ - start_databits)/3 ;AN000;3 bytes per entry


STOP_values    LABEL	BYTE		 ;AN000;;all valid stop bits

   DB	    include_string_list      ;AN000;have list of numbers and list of strings

   DB	    0

   DB	    0			      ;AN000; ;no number choices

   DB	    number_of_stopbit_strings  ;AN000;;choices in string form

   start_stopbit_strings   LABEL    BYTE

   DB	    one_item_tag
   DW	    OFFSET one_str
   DB	    one_point_five_item_tag
   DW	    OFFSET one_point_five_str
   DB	    two_item_tag
   DW	    OFFSET two_str

   number_of_stopbit_strings  EQU   ($ - start_stopbit_strings)/3  ;AN000;3 bytes per entry



RETRY_values	LABEL	 BYTE		  ;AN000;;all valid RETRY settings

   DB	    include_string_list      ;AN000;have list of strings

   DB	    0

   DB	    0			;AN000;;no number choices

   DB	    number_of_retry_settings

   start_retry_settings   LABEL    BYTE

   DB	    B_item_tag
   DW	    OFFSET B_str
   DB	    E_item_tag
   DW	    OFFSET E_str
   DB	    R_item_tag
   DW	    OFFSET R_str
   DB	    NONE_item_tag
   DW	    OFFSET N_str
   DB	    NONE_item_tag
   DW	    OFFSET NONE_str
   DB	    P_item_tag
   DW	    OFFSET P_str

   number_of_retry_settings  EQU   ($ - start_retry_settings)/3 ;AN000;3 bytes per entry



PREPARE_values	  LABEL    BYTE        ;AN000;almost any numeric value is valid

   DB	    ranges_only 	       ;AN000;;have range of numbers

   DB	    1			       ;AN000;;one range

   DB	    codepage_item_tag
   DD	    min_codepage_value
   DD	    max_codepage_value




SELECT_values	 LABEL	  BYTE		    ;AN000;all valid baud rates

   DB	    ranges_only 	;AN000;;have range of numbers

   DB	    1

   DB	    codepage_item_tag	;AN000;;item tag for the range
   DD	    min_codepage_value
   DD	    max_codepage_value


DELAY_values	LABEL	 BYTE		  ;AN000;;all valid delay rates

   DB	    ranges_only 	;AN000;;have range of numbers

   DB	    1			;AN000;;1 range
   DB	    range_item_tag	;AN000;;don't ever need this item tag
   DD	    1			;AN000;;smallest valid delay value
   DD	    4			;AN000;;largest valid delay value



RATE_values    LABEL	BYTE		 ;AN000;;all valid typamatic rates

   DB	    ranges_only 	;AN000;;have range of numbers

   DB	    1			;AN000;;1 range
   DB	    range_item_tag	;AN000;;never used
   DD	    1			;AN000;;smallest valid rate
   DD	    32			;AN000;;largest valid rate




CON_COLUMNS_values    LABEL    BYTE ;AN000;all valid columns values for the screen

   DB	    include_number_list     ;AN000;    ;have list of numbers

   DB	    0			    ;AN000;only numeric representations

   DB	    number_of_CON_columns_numbers   ;AN000;choices represented as numbers

   start_CON_columns_numbers   LABEL	BYTE

   DB	    fourty_item_tag
   DD	    40
   DB	    eighty_item_tag	    ;
   DD	    80			     ;AN000;numbers because used in call to IOCTL

   number_of_CON_columns_numbers  EQU	($ - start_CON_columns_numbers)/5	;5 bytes per entry



CON_LINES_values    LABEL    BYTE      ;all valid LINES= values for the screen

   DB	    include_number_list 	   ;have list of numbers

   DB	    0

   DB	    number_of_CON_lines_numbers 	     ; number ch

   start_CON_lines_numbers   LABEL    BYTE

   DB	    twentyfive_item_tag
   DD	    25
   DB	    fourtythree_item_tag
   DD	    43
   DB	    fifty_item_tag
   DD	    50

   number_of_CON_lines_numbers	EQU   ($ - start_CON_lines_numbers)/5	    ;5 bytes per entry




LPT_COLUMNS_values    LABEL    BYTE ;AN000;all valid columns values for parallel printers

   DB	    include_string_list     ;AN000;;have list of strings

   DB	    0

   DB	    0			    ;AN000;no numeric representations

   DB	    number_of_lpt_columns_strings  ;AN000;;choices represented as strings

   start_LPT_columns_strings   LABEL	BYTE

   DB	    eighty_item_tag	    ;
   DW	    OFFSET eighty_str	    ;AN000;;strings because values also used as positional parms
   DB	    onethirtytwo_item_tag
   DW	    OFFSET onethirtytwo_str

   number_of_LPT_columns_strings  EQU	($ - start_LPT_columns_strings)/3	;3 bytes per entry



LPT_LINES_values    LABEL    BYTE ;AN000;all valid LINES= values for the screen

   DB	    include_string_list       ;AN000;have list of strings

   DB	    0

   DB	    0			      ;AN000;	 ;no number choices

   DB	    number_of_LPT_lines_strings

   start_LPT_lines_strings   LABEL    BYTE

   DB	    six_item_tag		 ;AN000;;for printer
   DW	    OFFSET six_str
   DB	    eight_item_tag		 ;AN000;;for printer
   DW	    OFFSET eight_str

   number_of_LPT_lines_strings	EQU   ($ - start_LPT_lines_strings)/3 ;AN000;3 bytes per entry


reroute_values	  LABEL    BYTE    ;AN000;;all valid destination devices for parallel printer reroute

   DB	    include_string_list    ;AN000; ;have list of numbers and one string

   DB	    0

   DB	    0			;AN000;;no number choices

   DB	    number_of_reroute_strings

   start_reroute_strings   LABEL    BYTE

   DB	    COM1_item_tag
   DW	    OFFSET COM1_str
   DB	    COM2_item_tag
   DW	    OFFSET COM2_str
   DB	    COM3_item_tag
   DW	    OFFSET COM3_str
   DB	    COM4_item_tag
   DW	    OFFSET COM4_str

   number_of_reroute_strings  EQU   ($ - start_reroute_strings)/3 ;AN000;3 bytes per entry




Sw_control  LABEL BYTE

	       DW	0		  ;AN000;no values allowed on /STATUS
function_flag  DW	0		  ;AN000;no values allowed on /STATUS
	       DW	result		  ;AN000;same buffer as for other parms
	       DW	Sw_values
num_synonyms   DB	3		  ;AN000;3 ways to specify /STATUS
slash_sta      DB	"/STA",0
slash_stat     DB	"/STAT",0
slash_status   DB	"/STATUS",0






Sw_values   LABEL    BYTE

   DB	 0		;AN000;no values allowed on /STATUS


first_pos_values    LABEL BYTE	 ;AN000;value list for all positional parameters that appear first

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;numerics treated as strings

   DB	    0			 ;AN000;no number choices

   DB	    number_of_first_positional_strings

   start_first_positional_strings   LABEL    BYTE     ;used to calculate previous field

   ;screen modes

   DB	    BW40_item_tag
   DW	    OFFSET BW40_str
   DB	    BW80_item_tag
   DW	    OFFSET BW80_str
   DB	    CO40_item_tag
   DW	    OFFSET CO40_str
   DB	    CO80_item_tag
   DW	    OFFSET CO80_str
   DB	    MONO_item_tag
   DW	    OFFSET MONO_str
   DB	    fourty_item_tag
   DW	    OFFSET fourty_str
   DB	    eighty_item_tag
   DW	    OFFSET eighty_str


   DB	    con_item_tag
   DW	    OFFSET con_str

   ;com port names

   DB	    COM1_item_tag
   DW	    OFFSET COM1_str
   DB	    COM2_item_tag
   DW	    OFFSET COM2_str
   DB	    COM3_item_tag
   DW	    OFFSET COM3_str
   DB	    COM4_item_tag
   DW	    OFFSET COM4_str

   ;printer port names

   DB	    PRN_item_tag
   DW	    OFFSET PRN_str
   DB	    LPT1_item_tag
   DW	    OFFSET LPT1_str
   DB	    LPT2_item_tag
   DW	    OFFSET LPT2_str
   DB	    LPT3_item_tag
   DW	    OFFSET LPT3_str

   ;LPT special cases

   DB	    LPT1132_item_tag
   DW	    OFFSET LPT1132_str
   DB	    LPT2132_item_tag
   DW	    OFFSET LPT2132_str
   DB	    LPT3132_item_tag
   DW	    OFFSET LPT3132_str
   DB	    LPT180_item_tag
   DW	    OFFSET LPT180_str
   DB	    LPT280_item_tag
   DW	    OFFSET LPT280_str
   DB	    LPT380_item_tag
   DW	    OFFSET LPT380_str


number_of_first_positional_strings  EQU   ($ - start_first_positional_strings)/3 ;each entry is 3 bytes (byte, word)



second_pos_values    LABEL BYTE  ;AN000;;value list for all positional parameters that appear second

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;numerics treated as strings

   DB	    0			 ;AN000;no number choices

   DB	    number_of_second_positional_strings

   start_second_positional_strings   LABEL    BYTE     ;used to calculate previous field


   ;codepage strings

   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODEPAGE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CP_str

   ;invalid choice, included for usable error reporting: if come across refresh right after CON then issue invalid number of parms

   DB	    REFRESH_item_tag
   DW	    OFFSET REF_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REFRESH_str

   ;shift directions

   DB	    L_item_tag
   DW	    OFFSET L_str
   DB	    R_item_tag
   DW	    OFFSET R_str


   ;columns values

;  DB	    eighty_item_tag
;  DW	    OFFSET eighty_str	 ;AN000;   ;strings because values also used as positional parms
   DB	    onethirtytwo_item_tag
   DW	    OFFSET onethirtytwo_str

number_of_second_positional_strings  EQU   ($ - start_second_positional_strings)/3 ;each entry is 3 bytes (byte, word)


third_pos_values    LABEL BYTE	 ;AN000;value list for all positional parameters that appear third

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;numerics treated as strings

   DB	    0			 ;AN000;no number choices

   DB	    number_of_third_positional_strings

   start_third_positional_strings   LABEL    BYTE     ;used to calculate previous field

number_of_third_positional_strings  EQU   ($ - start_third_positional_strings)/3 ;each entry is 3 bytes (byte, word)


first_lpt_pos_values	LABEL BYTE   ;AN000;value list for all possible chars per line

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;numerics treated as strings

   DB	    0			 ;AN000;no number choices

   DB	    number_of_first_lpt_positional_strings

   start_first_lpt_positional_strings	LABEL	 BYTE	  ;used to calculate previous field

   DB	    eighty_item_tag
   DW	    OFFSET eighty_str
   DB	    onethirtytwo_item_tag
   DW	    OFFSET onethirtytwo_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CODEPAGE_str
   DB	    CODEPAGE_item_tag
   DW	    OFFSET CP_str

   ;invalid choice, included for usable error reporting: if come across refresh right after CON then issue invalid number of parms

   DB	    REFRESH_item_tag
   DW	    OFFSET REF_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REFRESH_str

number_of_first_lpt_positional_strings	EQU   ($ - start_first_lpt_positional_strings)/3 ;each entry is 3 bytes (byte, word)


second_lpt_pos_values	 LABEL BYTE   ;AN000;value list for all possible lines per inch

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;numerics treated as strings

   DB	    0			 ;AN000;no number choices

   DB	    number_of_second_lpt_positional_strings

   start_second_lpt_positional_strings	 LABEL	  BYTE	   ;used to calculate previous field

   DB	    eight_item_tag
   DW	    OFFSET eight_str
   DB	    six_item_tag
   DW	    OFFSET six_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REF_str
   DB	    REFRESH_item_tag
   DW	    OFFSET REFRESH_str

number_of_second_lpt_positional_strings  EQU   ($ - start_second_lpt_positional_strings)/3 ;3 bytes per entry (byte,word)


third_lpt_pos_values	LABEL BYTE   ;AN000;value list for all possible retry settings

   DB	    include_string_list  ;AN000;   ;have string values

   DB	    0			 ;AN000;no numeric ranges

   DB	    0			 ;AN000;no number choices

   DB	    number_of_third_lpt_positional_strings

   start_third_lpt_positional_strings	LABEL	 BYTE	  ;used to calculate previous field

   DB	    B_item_tag
   DW	    OFFSET B_str
   DB	    E_item_tag
   DW	    OFFSET E_str
   DB	    R_item_tag
   DW	    OFFSET R_str
   DB	    NONE_item_tag
   DW	    OFFSET N_str
   DB	    NONE_item_tag
   DW	    OFFSET NONE_str
   DB	    OFF_item_tag
   DW	    OFFSET OFF_str
   DB	    P_item_tag
   DW	    OFFSET P_str

number_of_third_lpt_positional_strings	EQU   ($ - start_third_lpt_positional_strings)/3 ;each entry is 3 bytes (byte, word)



;strings

zero_str		  DB  "0",0
one_str 		  DB  "1",0
one_point_five_str	  DB  "1.5",0
two_str 		  DB  "2",0
three_str		  DB  "3",0
four_str		  DB  "4",0
five_str		  DB  "5",0       ;AN000;  ;data bit, typamatic rate
six_str 		  DB  "6",0
seven_str		  DB  "7",0
eight_str		  DB  "8",0
nine_str		  DB  "9",0
eleven_str		  DB  "11",0      ;AN000; ;first two chars of 110
twelve_str		  DB  "12",0
fifteen_str		  DB  "15",0      ;AN000; ;abbreviated form of 150, 15 is also a RATE= candidate
nineteen_str		  DB  "19",0      ;AN000; ;used for baud rates and RATE=
nineteen_point_two_str	  DB  "19.2",0
nineteen_point_two_K_str  DB  "19.2K",0   ;AN000; ;mutant baud rate
twentyfour_str		  DB  "24",0      ;AN000; ;24 is also a typamatic rate
thirty_str		  DB  "30",0
fourty_str		  DB  "40",0
fourtyeight_str 	  DB  "48",0
sixty_str		  DB  "60",0
eighty_str		  DB  "80",0
ninetysix_str		  DB  "96",0
oneten_str		  DB  "110",0
onethirtytwo_str	  DB  "132",0
onefifty_str		  DB  "150",0
threehundred_str	  DB  "300",0
sixhundred_str		  DB  "600",0
twelvehundred_str	  DB  "1200",0
twentyfourhundred_str	  DB  "2400",0
fourtyeighthundred_str	  DB  "4800",0
ninetysixhundred_str	  DB  "9600",0
nineteentwohundred_str	  DB  "19200",0
B_str			  DB  "B",0
BW40_str		  DB  "BW40",0
BW80_str		  DB  "BW80",0
CO40_str		  DB  "CO40",0
CO80_str		  DB  "CO80",0
CODE_str		  DB  "CODE",0
CODEPAGE_str		  DB  "CODEPAGE",0
COM_str 		  DB  "COM",0
start_COM1_str	  LABEL BYTE		  ;AN000;  ;used to calculate len_COMX_str, see invoke
COM1_str		  DB  "COM1",0
len_COMX_str	  EQU	$ - start_COM1_str;AN000;  ;all COMX strings are the same length
COM2_str		  DB  "COM2",0
COM3_str		  DB  "COM3",0
COM4_str		  DB  "COM4",0
CON_str 		  DB  "CON",0
len_CON_str	  EQU  ($ - (OFFSET CON_str))
CP_str			  DB  "CP",0
E_str			  DB  "E",0             ;RETRY=setting
EVEN_str		  DB  "EVEN",0
L_str			  DB  "L",0
start_LPT1_str	  LABEL BYTE		     ;used to calculate len_LPTX_str, see invoke
LPT1_str		  DB  "LPT1",0
len_LPTX_str	  EQU	$ - start_LPT1_str   ;all LPTX strings are the same length
LPT2_str		  DB  "LPT2",0
LPT3_str		  DB  "LPT3",0
LPT1132_str		  DB  "LPT1132",0
LPT2132_str		  DB  "LPT2132",0
LPT3132_str		  DB  "LPT3132",0
LPT180_str		  DB  "LPT180",0
LPT280_str		  DB  "LPT280",0
LPT380_str		  DB  "LPT380",0
M_str			  DB  "M",0
MARK_str		  DB  "MARK",0
MONO_str		  DB  "MONO",0
N_str			  DB  "N",0
NONE_str		  DB  "NONE",0
O_str			  DB  "O",0
ODD_str 		  DB  "ODD",0
OFF_str 		  DB  "OFF",0
ON_str			  DB  "ON",0
P_str			  DB  "P",0
PRN_str 		  DB  "PRN",0
R_str			  DB  "R",0
REF_str 		  DB  "REF",0
REFRESH_str		  DB  "REFRESH",0
S_str			  DB  "S",0
SPACE_str		  DB  "SPACE",0
T_str			  DB  "T",0


result	     result_def<>

parm_lst    parm_list_entry  max_parms DUP (<>)



;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  D A T A	ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼


;
;******************************************************************************************

;-------------------------------------------------------------------------------
;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ SEARCH_ITEM_TAGS
;³ ----------------
;³  Search the item tags in input value list for the input item tag.
;³
;³
;³
;³
;³
;³
;³  INPUT: i_CL - first item tag in the group
;³	   search_stop - last item_tag in the group, the sentinal for the REPEAT
;³			 loop.
;³
;³
;³  RETURN: match_found indicates that the item tag returned by the parser was
;³	    found in the group passed in.
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:	 To be determined at I2 time.
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³
;³  ASSUMPTIONS:
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

search_item_tags  PROC	NEAR


MOV   match_found,false
.REPEAT
   .IF <parm_list[current_parm_DI].item_tag EQ i_CL> THEN
      MOV   match_found,true
      MOV   i_CL,last_databit_item_tag		 ;AN000;set end of loop trigger
   .ENDIF
   INC	 i_CL
.UNTIL <i_CL GT search_stop>

RET

search_item_tags  ENDP

;-------------------------------------------------------------------------------
;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ CHECK_FOR_KEYWORD
;³ ---------------------
;³
;³ Scan the list of keywords (OFFSETS) looking for a match with
;³ parm_list[current_parm_DI].keyword_switch_ptr.
;³
;³
;³
;³  INPUT: uses global variables.
;³
;³
;³  RETURN: match_found is set to true if a match is found.
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³  REGISTER
;³  USAGE:	 DX - loop index
;³		 SI - displacement into the list of pointers
;³		 CX - holder of pointer to keywords for compare
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³
;³
;³
;³  ASSUMPTIONS: The list of con_keyword pointers is consecutive words.
;³		 number_of_keywords has the number of OFFSETS in the list
;³		 start_of_keyword_ptrs has the first OFFSET in the list and can
;³		 be addressed off of.
;³
;³
;³
;³  SIDE EFFECT: DL - lost
;³		 SI - lost
;³		 CX - lost
;³		 match_found - lost
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

check_for_keyword   PROC  NEAR

MOV   match_found,false
MOV   SI,0
MOV   DL,0			    ;AN000;;index for the loop
.WHILE <DL LT number_of_keywords> AND	 ;AN000;;check each pointer in the list
.WHILE <match_found EQ false> DO
   MOV	 CX,start_of_keyword_ptrs[SI]
   .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ CX> THEN ;AN000;IF synonym ptr=CON keyword ptr THEN
       MOV   match_found,true
   .ENDIF
   INC	 SI
   INC	 SI
   INC	 DL			   ;AN000;;increment loop counter
.ENDWHILE

RET

check_for_keyword   ENDP

;-------------------------------------------------------------------------------

setup_invalid_parameter  PROC  NEAR

PUBLIC setup_invalid_parameter

MOV   message,OFFSET CRLF	 ;AN000;the common message doesn't have a CR,LF in it and all my other messages do
PUSH  parser_return_code_AX	 ;AC006;AX destroyed by sysdispmsg
display  message
POP   parser_return_code_AX


MOV   BP,command_line		;AN000;BP points to end of current (invalid) parm
.IF <<BYTE PTR [BP]> NE end_of_line_char_0D> AND    ;AN000;IF a whitespace char or comma in the string
.IF <<BYTE PTR [BP]> NE end_of_line_char_00> THEN   ;AN000;THEN
   DEC	 BP				     ;AN000;don't include the delimeter in the display of the invalid parm
.ENDIF
MOV   BYTE PTR [BP],0		;AN000;make the string an ASCIIZ

;offending_parameter is where the text of the bad parm is,
;offending_parameter_ptr is the address of offending_parameter By incrementing
;offending_parameter_ptr the first characters of the text string are skipped.
;This is done to skip leading whitespace.


MOV   BP,offending_parameter_ptr       ;AC006;BP=>first char in the text string
.WHILE <<BYTE PTR [BP]> EQ tab> OR	 ;AC006;WHILE the char in the text string
.WHILE <<BYTE PTR [BP]> EQ " "> DO       ;AC006;      is white space DO
   INC	 offending_parameter_ptr       ;AC006;point past the whitespace char
   INC	 BP			       ;AC006;index next char in the string
.ENDWHILE

.IF <parser_return_code_AX EQ syntax_error_rc> THEN   ;AN000;syntax error, like "RETRY= E"
   MOV	 message,OFFSET syntax_error
   PUSH  offending_parameter_ptr
   POP	 syntax_error_ptr				;AN000;point to the offending parameter
.ELSEIF <parser_return_code_AX EQ not_in_switch_list> THEN
   MOV	 message,OFFSET Invalid_switch
.ELSE
   MOV	 message,OFFSET Invalid_parameter ;AN000;user mispelled, misordered etc.
.ENDIF
MOV   noerror,false

RET

setup_invalid_parameter  ENDP

;-------------------------------------------------------------------------------

setup_for_not_supported    PROC  NEAR	  ;AC002;prepare replacable parm for "Function not supported on this machine - ????".

MOV   CX,offending_parameter_ptr
MOV   not_supported_ptr,CX	;AN000;point to string describing what is not supported for message
MOV   BP,command_line		;AN000;BP points to end of current (invalid) parm
.IF <<BYTE PTR [BP]> NE end_of_line_char_0D> AND    ;AN000;IF a whitespace char or comma in the string
.IF <<BYTE PTR [BP]> NE end_of_line_char_00> THEN   ;AN000;THEN
   DEC	 BP				     ;AN000;don't include the delimeter in the display of the invalid parm
.ENDIF
MOV   BYTE PTR [BP],0		;AN000;make the string an ASCIIZ
MOV   message,OFFSET function_not_supported ;AN000;"Function not supported on the computer - mark"
MOV   noerror,false
MOV   looking_for,eol

RET

setup_for_not_supported    ENDP


;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ PARSE_PARAMETERS
;³ ----------------
;³
;³ All parameters entered on the command line are reduced to a list of values
;³ which completely describes the parms.  The syntactic and semantic correctness
;³ will be checked.  The routines that use the lists created by this routine
;³ can have complete trust in the validity of the parms.
;³
;³ Most of the states of looking_for allow null, even if it is not mentioned in
;³ the name of the value looking_for is assigned.
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  INPUT: none, uses global variables.
;³
;³
;³  RETURN: noerror is set to false if an error is encountered.
;³
;³
;³  MESSAGES: "Invalid parameter  'bdprm'", where "bdprm" is the first 5 or less
;³	      characters of the parameter that is incorrect or unexpected.
;³
;³	      "Must specify COM1, COM2, COM3 or COM4"
;³
;³	      "Illegal device name"
;³
;³	      "Invalid baud rate specified"
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:	 To be determined at I2 time.
;³
;³
;³  CONVENTIONS: "looking_for" indicates the valid possibilities for the next parm.
;³
;³		 "current_parm" refers to the parm just returned.  It can be an
;³			      item tag, a type.
;³
;³		 When "/STATUS" is a valid possibility it is checked for even
;³		 though the value of "looking_for" may not indicate it as a
;³		 choice.
;³
;³		 When possible the parser control blocks will be modified at
;³		 the case where looking_for is being checked for rather than
;³		 where looking_for was set.  This will save code when more than
;³		 one place sets looking_for to the same state.
;³
;³
;³
;³
;³  ASSUMPTIONS: The parser control blocks are setup to be the following:
;³		 seperators are defaults and colon (:)
;³		 match_flags=2011 (simple string, ignore colon, optional)
;³		 function_flags=0
;³		 keyword/switch list has only /STATUS
;³		 nval (number of value definitions) is 3
;³		 Initially no number choices.  Most numeric values will treated as strings.
;³		   This is because for most of them the numeric value doesn't
;³		   mean anything. Since we do not want to restrict the choices
;³		   code pages they cannot be enumerated, so a range will be used.
;³		 The list of strings in the values block contains all the
;³		   device names, all the screen modes, all the status qualifiers,
;³		   and all numeric values that have no meaning in binary form,
;³		   can be enumerated, or are non-integer.
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

parse_parameters PROC

;determine if on a PS/2 for checking COMx parameters

.IF <machine_type EQ PS2Model30> OR
.IF <machine_type EQ PS2Model50> OR
.IF <machine_type EQ PS2Model60> OR
.IF <machine_type EQ PS2Model80> THEN  ;AC002;IF the machine is a PS/2 THEN
   MOV	 type_of_machine,PS2			       ;AC002;set flag
.ENDIF


MOV   looking_for,first_parm	 ;AN000;looking_for:=first_parm

.WHILE <eol_found NE true> AND NEAR
.WHILE <noerror EQ true> NEAR DO ;AN000;WHILE (NOT EOL) AND noerror=true DO

;  CASE looking_for=

   ;calculate the displacement for the jump to appropriate case
   XOR	 AX,AX
   MOV	 AL,max_looking_for	 ;AN000;see the list of equates for looking_for
   SUB	 AL,looking_for        ;AN000;AX=byte displacement into table of OFFSETS
   SHL	 AX,1			;AN000;each displacement is 2 bytes
   MOV	 SI,AX			;AN000;SI=appropriate displacement into table of offsets
   JMP	 jump_table1[SI]	    ;AN000;jump to case

   jump_table1	  LABEL    WORD    ;AN000;    ;these entries must be in same order as the values in list of equates for looking_for

   DW OFFSET codepage_case
   DW OFFSET codepage_prms_case
   DW OFFSET COM_keyword_case
   DW OFFSET com_keyword_or_baud_case
   DW OFFSET CON_keyword_case
   DW OFFSET con_kwrd_status_or_cp_case
   DW OFFSET databits_or_null_case
   DW OFFSET device_name_or_eol_case
   DW OFFSET eol_case
   DW OFFSET first_parm_case
   DW OFFSET li_or_null_case
   DW OFFSET P_case
   DW OFFSET parity_or_null_case
   DW OFFSET prn_kw_status_cp_cl_null_case
   DW OFFSET sd_or_dl_case
   DW OFFSET sd_or_dl_or_eol_case
   DW OFFSET status_or_eol_case
   DW OFFSET stopbits_or_null_case
   DW OFFSET T_or_eol_case


      com_keyword_or_baud_case:

PUBLIC	    com_keyword_or_baud_case

	 ;The com keywords are in "com_parmsx", as well as the values for the
	 ;positional and keyword forms of the com parameters.  If
	 ;keyword_switch_ptr comes back from parse_parm nonzero then a valid
	 ;com keyword or /STATUS was found.

	 CALL  parse_parm     ;AN000;/status allowed

	 ;CASE current_parm=


;	    /status:

		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_sta>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_status>> THEN

;	       MOV   slash_status,deleted	;AN000;make it so /status again is an error,also deletes /STA
;	       MOV   slash_stat,deleted
;	       MOV   slash_sta,deleted
	       MOV   looking_for,eol		;AN000;eol only valid
	       MOV   request_type,com_status

	       BREAK  1

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,com_status
	       MOV   eol_found,true
	       BREAK 1

		  .ENDIF


;	    com_keyword:

		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr NE 0> THEN  ;AN000;wasn't /STATUS so must be a keyword

	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET baud_equal>> THEN	 ;AN000;IF synonym ptr=> BAUD= THEN
		  MOV	baud_specified,true
	       .ENDIF
	       delete_parser_value_list_entry keywords,current_parm
	       MOV   looking_for,com_keyword
	       MOV   parms_form,keyword 				;AN000;tell analyze_and_invoke how to look at the parms
	       BREAK 1

		  .ENDIF


;	    baud:    ;found a number that is a valid baud, know that have old com style com request



		  .IF <parser_return_code_AX EQ no_error> THEN	 ;AN000;IF have a baud rate THEN (none of above, must be baud rate)

	       .IF <parm_list[current_parm_DI].item_tag EQ nineteentwohundred_item_tag> THEN	;AC002;IF PS2 only baud rate AND
		  MOV	new_com_initialize,true
		  .IF <type_of_machine NE PS2> THEN						;AC002;not on PS/2
		     CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		  .ENDIF
	       .ENDIF
;AD008;        .ELSE
	       MOV   looking_for,parity_or_null
	       MOV   request_type,initialize_com_port
;AD008;        .ENDIF
	       BREAK 1

		  .ELSE


;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK 1

		  .ENDIF

	 ENDCASE_1:

	 BREAK 0



      com_keyword_case:

	 ;At this point the com keywords are in the keyword list, the only valid
	 ;parms that can follow are com keywords.  Assume that one and only one
	 ;com keyword has been found and removed from the list of keywords.

PUBLIC com_keyword_case

	 MOV   parms.parmsx_ptr,OFFSET com_keywords_parmsx ;AN000;only com keywords are in the control blocks
	 MOV   i_CL,1

com_keyword_loop:
	 CMP   i_CL,number_of_com_keywords		   ;AN000;one iteration more than number of parms left so will find eol
	 JG    com_keyword_loop_done
	 CMP   eol_found,false
	 JNE   com_keyword_loop_done
	 CMP   noerror,true
	 JNE   com_keyword_loop_done

	    .SELECT		       ;AC002;check for PS/2 specific parms
	    .WHEN <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET baud_equal>> THEN	;AC002;IF synonym ptr=> BAUD= THEN
	       .IF <parm_list[current_parm_DI].item_tag EQ nineteentwohundred_item_tag> THEN	;AC002;IF PS2 only baud rate AND
		  MOV	new_com_initialize,true
		  .IF <type_of_machine NE PS2> THEN						;AC002;not on PS/2
		     CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		  .ENDIF
	       .ENDIF
	    .WHEN <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET parity_equal>> THEN   ;AC002;IF parity= THEN
	       .IF <parm_list[current_parm_DI].item_tag EQ mark_item_tag> OR	  ;AC002;IF PS2 only parity
	       .IF <parm_list[current_parm_DI].item_tag EQ space_item_tag> THEN    ;AC002;IF PS2 only parity AND
		  MOV	new_com_initialize,true
		  .IF <type_of_machine NE PS2> THEN						;AC002;not on PS/2
		     CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		  .ENDIF
	       .ENDIF
	    .WHEN <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET data_equal>> THEN	;AC002;IF data= THEN
	       .IF <parm_list[current_parm_DI].item_tag EQ five_item_tag> OR	  ;AC002;IF PS2 only data bits
	       .IF <parm_list[current_parm_DI].item_tag EQ six_item_tag> THEN	 ;AC002;IF PS2 only data bits AND
		  MOV	new_com_initialize,true
		  .IF <type_of_machine NE PS2> THEN						;AC002;not on PS/2
		     CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		  .ENDIF
	       .ENDIF
	    .WHEN <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET stop_equal>> THEN	;AC002;IF stop= THEN
	       .IF <parm_list[current_parm_DI].item_tag EQ one_point_five_item_tag> THEN    ;AC002;IF PS2 only stop bits AND
		  MOV	new_com_initialize,true
		  .IF <type_of_machine NE PS2> THEN						;AC002;not on PS/2
		     CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		  .ENDIF
	       .ENDIF
	    .ENDSELECT

	    PUSH  CX			     ;save the loop index
	    CALL  parse_parm
	    POP   CX

	    .IF <noerror EQ true> AND
	    .IF <parser_return_code_AX EQ no_error> THEN

	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET baud_equal>> THEN	 ;AN000;IF synonym ptr=> BAUD= THEN
		  MOV	baud_specified,true
	       .ENDIF
	       delete_parser_value_list_entry keywords,current_parm
	       INC   i_CL
	       JMP   com_keyword_loop

	    .ELSEIF <parser_return_code_AX EQ end_of_command_line> THEN

	       .IF <baud_specified EQ true> THEN
		  MOV	request_type,initialize_com_port
	       .ELSE
		  MOV	message,OFFSET baud_rate_required
		  MOV	noerror,false
	       .ENDIF
	       MOV   eol_found,true

	    .ELSE NEAR

	       CALL  setup_invalid_parameter

	    .ENDIF

	 JMP   com_keyword_loop

com_keyword_loop_done:

	 MOV   looking_for,eol		 ;AN000;if haven't already encountered an error then check for extraneous parms

	 BREAK 0    ;AN000;com_keyword


      status_or_eol_case:

;     status_or_eol:	;Have found the only or the last status qualifier, must find /STATUS or eol_found NExt
			;Assume that /STATUS is the only switch in the appropriate parser control block
			;Assume that request_type has already been set

	 CALL  parse_parm

	 .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_sta>> OR
	 .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
	 .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_status>> THEN   ;AN000;found /status

	    MOV   looking_for,eol

	 .ELSEIF <parser_return_code_AX EQ end_of_command_line> THEN ;AN000;encountered EOL

	    MOV   eol_found,true

	 .ELSE

	    CALL  setup_invalid_parameter

	 .ENDIF

	 BREAK 0   ;status_or_eol



      parity_or_null_case:

PUBLIC	 parity_or_null_case

	 ;the parser control blocks have paritys as strings
	 ;modify parser control blocks list of valid paritys based on the
	 ;machine type.


	 CALL  parse_parm
	 .IF <parser_return_code_AX EQ operand_missing> THEN   ;AN000;valid null
	    MOV   looking_for,databits_or_null	    ;AN000;can't have baud,,eol
	 .ELSE
;	    CASE current_parm=


;	       eol:

		     .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

		  MOV	request_type,initialize_com_port
		  MOV	eol_found,true
		  BREAK 5

		     .ENDIF

;	       parity:

		     .IF <parser_return_code_AX EQ no_error> THEN    ;AN000;IF have a parity THEN (none of above, must be parity)

		  MOV	looking_for,databits_or_null
		  .IF <parm_list[current_parm_DI].item_tag EQ mark_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ space_item_tag> THEN
		     MOV   new_com_initialize,true
		     .IF <type_of_machine NE PS2> THEN	;AN000;IF not Roundup or later
			CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		     .ENDIF
		  .ENDIF

		     .ELSE

;	       otherwise:

		  CALL	setup_invalid_parameter
;		  BREAK

		     .ENDIF

	    ENDCASE_5:		 ;current_parm

	 .ENDIF
	 BREAK 0  ;AN000;parity_or_null




      databits_or_null_case:


PUBLIC	    databits_or_null_case

	 ;parser control blocks have all databits (as strings).
	 ;modify parser control blocks to handle list of valid databits
	 ;based on the machine type.

;AC002;  .IF <type_of_machine NE PS2> THEN  ;AN000;IF not Roundup or later
;AC002;     MOV   five_str,deleted     ;delete parser value list entry
;AC002;     MOV   six_str,deleted	   ;delete_parser_value_list_entry
;AC002;  .ENDIF

	 ;the parser control blocks have data bits valid for this machine
	 CALL  parse_parm
	 .IF <parser_return_code_AX EQ operand_missing> THEN   ;AN000;valid null
	    MOV   looking_for,stopbits_or_null		  ;can't have databits,,eol
	 .ELSE
;	    CASE current_parm=


;	       eol:

		     .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

		  MOV	request_type,initialize_com_port
		  MOV	eol_found,true
		  BREAK 6

		     .ENDIF


;	       databits:

		     .IF <parser_return_code_AX EQ no_error> THEN    ;AN000;IF have a parity THEN (none of above, must be parity)

		  MOV	looking_for,stopbits_or_null
		  .IF <parm_list[current_parm_DI].item_tag EQ five_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ six_item_tag> THEN
		     MOV   new_com_initialize,true
		     .IF <type_of_machine NE PS2> THEN	;AC002;IF not Roundup or later
			CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		     .ENDIF
		  .ENDIF
;		  BREAK 6

		     .ELSE


;	       otherwise:

		  CALL	setup_invalid_parameter
;		  BREAK

		     .ENDIF

	    ENDCASE_6: ;current_parm

	 .ENDIF
	 BREAK 0  ;AN000;databits_or_null



      stopbits_or_null_case:


PUBLIC	    stopbits_or_null_case

	 ;parser control blocks have all stopbits (as strings).
	 ;modify parser control blocks to handle list of valid stopbits
	 ;based on the machine type.

;AC002;  .IF <type_of_machine NE PS2> THEN  ;AN000;IF not Roundup or later
;AC002;     MOV   one_point_five_str,deleted   ;delete_parser_value_list_entry
;AC002;  .ENDIF


	 CALL  parse_parm
	 .IF <parser_return_code_AX EQ operand_missing> THEN   ;AN000;valid null
	    MOV   looking_for,P 		;AN000;no null just before eol
	 .ELSE
;	    CASE current_parm=


;	       eol:

		     .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

		  MOV	BYTE PTR request_type,initialize_com_port
		  MOV	eol_found,true
		  BREAK 7

		     .ENDIF


;	       stopbits:


		     .IF <parser_return_code_AX EQ no_error> THEN    ;AN000;IF have a parity THEN (none of above, must be parity)

		  MOV	looking_for,P		  ;AN000;P or eol valid next
		  .IF <parm_list[current_parm_DI].item_tag EQ one_point_five_item_tag> THEN
		     MOV   new_com_initialize,true
		     .IF <type_of_machine NE PS2> THEN	;AC002;IF not Roundup or later
			CALL  setup_for_not_supported  ;AC002;set up for "Function not supported on this computer" message
		     .ENDIF
		  .ENDIF

		     .ELSE


;	       otherwise:

		  CALL	setup_invalid_parameter
;		  BREAK

		     .ENDIF

	    ENDCASE_7: ;current_parm

	 .ENDIF
	 BREAK 0 ;AN000;stopbits_or_null




      P_case:		;P or eol valid


PUBLIC P_case

	 ;P is in the parser control blocks' list of strings.

	 CALL parse_parm
;	 CASE current_parm=





;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

	       MOV   eol_found,true
	       BREAK 8

		  .ENDIF



;	    P:

		  .IF <parser_return_code_AX EQ no_error> THEN	 ;AN000;found one of: p,e,b,r,n,none,off

	       MOV   looking_for,eol	  ;AN000;found last positional
	       MOV   retry_requested,true

		  .ELSE


;	    otherwise:

	       CALL  setup_invalid_parameter

		  .ENDIF


	 ENDCASE_8: ;current_parm

	 BREAK 0  ;AN000;P



;m
      prn_kw_status_cp_cl_null_case:

      PUBLIC   prn_kw_status_cp_cl_null_case

      ;Have encountered only LPTX so far, so any printer stuff including codepage
      ;requests can follow. All necessary keywords and switches are in the control blocks.


	 CALL  parse_parm

;	 CASE current_parm=

;	    LPT_mode_keyword:		   ;nothing but printer keywords allowed


		  .IF <parser_return_code_AX EQ no_error> AND NEAR
;		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET COLUMNS_equal>> OR
;		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET COLS_equal>> OR
;		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET lines_equal>> OR
;		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET retry_equal_str>> THEN ;AN000;found a printer keyword


		  check_for_lpt_keyword      ;check for COLS= or LINES= or RETRY=, return results in match_found
		  .IF <match_found EQ true> THEN NEAR

	       delete_parser_value_list_entry keywords,current_parm
	       MOV   parms_form,keyword 		;AN000;indicate to modeprin how to deal with retry
	       CALL  parse_parm
	       MOV   DL,1			;AN000;one keyword found so far

	       .REPEAT

;		  CASE return_code=

;		     LPT_keyword:


			   .IF <parser_return_code_AX EQ no_error> AND
			   PUSH  DX			;save loop index
			   check_for_lpt_keyword      ;return results in match_found
			   POP	 DX
			   .IF <match_found EQ true> THEN

			.IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET retry_equal_str>> AND
			.IF <parm_list[current_parm_DI].item_tag NE NONE_item_tag> THEN
			   MOV	 retry_requested,true	;set up for rescode
			.ENDIF
			delete_parser_value_list_entry keywords,current_parm
			INC   DL		;AN000;found another keyword
			BREAK 9

			   .ENDIF


;		     eol:

			   .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

			;had at least one keyword
			MOV   request_type,initialize_printer_port
			MOV   eol_found,true
			BREAK 9

			   .ENDIF


;		     otherwise:     ;wrong type of keywords, /STATUS etc.

			CALL  setup_invalid_parameter
;			BREAK

		  ENDCASE_9:

		  PUSH	DX
		  CALL	parse_parm
		  POP	DX

	       .UNTIL <DL EQ number_of_LPT_keywords> OR
	       .UNTIL <eol_found EQ true> OR
	       .UNTIL <noerror EQ false>

;	       .IF <eol_found NE true> AND
	       .IF <noerror EQ true> AND
	       .IF <DL EQ number_of_LPT_keywords> THEN
		  MOV	looking_for,eol 	  ;AN000;check for extraneous parms
	       .ENDIF

	       BREAK 10

		  .ENDIF   ;AN000;LPT_keyword


;	    /STATUS:

		  .IF <parser_return_code_AX EQ no_error> AND		;make sure don't have /STA:value
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_sta>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_status>> THEN  ;AN000;found /STATUS

	       MOV   looking_for,eol  ;AN000;look for RETRY or codepage
	       MOV   slash_status,deleted
	       MOV   slash_stat,deleted
	       MOV   slash_sta,deleted
	       MOV   request_type,printer_status
	       BREAK 10 ;AN000;keyword

		  .ENDIF   ;/STATUS found


;	    codepage:


		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ 0> AND		  ;AC007;wasn't SEL=cpnum or PREP=cpnum
		  .IF <parm_list[current_parm_DI].item_tag EQ codepage_item_tag> THEN	  ;AN000;IF found "codepage" or "cp" THEN

	       MOV   looking_for,codepage_prms
	       MOV   codepage_str,deleted
	       MOV   code_str,deleted
	       MOV   cp_str,deleted
	       BREAK 10

		  .ENDIF



;	    cl:

		  .IF <parm_list[current_parm_DI].item_tag EQ onethirtytwo_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ eighty_item_tag> THEN

	       MOV   REFRESH_str,deleted			;AC007;no codepage stuff legal
	       MOV   REF_str,deleted
	       MOV   SEL_equal,deleted
	       MOV   SELECT_equal,deleted
	       MOV   PREP_equal,deleted
	       MOV   PREPARE_equal,deleted
	       MOV   slash_status,deleted
	       MOV   slash_stat,deleted
	       MOV   slash_sta,deleted
	       MOV   looking_for,li_or_null
	       MOV   request_type,old_initialize_printer_port		;AN000;found enough to know that it isn't status or keyword
	       BREAK 10

		  .ENDIF



;	    eol:


		  .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

	       MOV   request_type,turn_off_reroute ;compatible with previous MODE
	       MOV   eol_found,true
	       BREAK 10

		  .ENDIF



;	    codepage_keyword_out_of_order:


		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREPARE_equal>> OR  ;AC007;if got here and have
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREP_equal>> OR 	;AC007;one of the codepage
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SEL_equal>> OR		;AC007;keywords then user
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SELECT_equal>> THEN	;AC007;forgot "CP"

	       MOV   message,OFFSET Invalid_number_of_parameters
	       MOV   noerror,false
	       BREAK 10  ;AN000;CON_keyword

		  .ENDIF



;	    REFRESH_out_of_order:   ;AC007;forgot to include "CP"


		  .IF <parm_list[current_parm_DI].item_tag EQ REFRESH_item_tag> THEN

	       MOV   message,OFFSET Invalid_number_of_parameters
	       MOV   noerror,false
	       BREAK 10

		  .ENDIF



;	    null:

		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].item_tag EQ unspecified> THEN   ;AN007;valid null

	       MOV   REFRESH_str,deleted			;AC007;no codepage stuff legal
	       MOV   REF_str,deleted
	       MOV   SEL_equal,deleted
	       MOV   SELECT_equal,deleted
	       MOV   PREP_equal,deleted
	       MOV   PREPARE_equal,deleted
	       MOV   slash_status,deleted
	       MOV   slash_stat,deleted
	       MOV   slash_sta,deleted
	       MOV   looking_for,li_or_null
	       MOV   request_type,old_initialize_printer_port		;AN000;found enough to know that it isn't status or keyword



;	    otherwise:

		  .ELSE

	       CALL  setup_invalid_parameter
;	       BREAK

		  .ENDIF


	 ENDCASE_10: ;current_parm=
	 BREAK 0   ;AN000;prn_kw_status_cp_cl_null_case:




      li_or_null_case:			     ;look for lines per inch or null, eol valid

PUBLIC li_or_null_case


	 CALL  parse_parm
;	 CASE current_parm=

;	    li:

		  .IF <parm_list[current_parm_DI].item_tag EQ six_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ eight_item_tag> THEN     ;AN000;IF found 6 or 8 THEN

	       MOV   looking_for,P
	       BREAK 11

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN   ;AN000;valid

	       MOV   request_type,old_initialize_printer_port
	       MOV   eol_found,true
	       BREAK 11

		  .ENDIF


;	    null:

		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].item_tag EQ unspecified> THEN   ;AN007;valid null

	       MOV   looking_for,P
	       BREAK 11

		  .ENDIF


;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK


	 ENDCASE_11:  ;current_parm
	 BREAK 0   ;AN000;li_or_null


;m
      codepage_prms_case:


	 ;The desired codepage parameters are in the parser control blocks, such
	 ;as: the keywords, PREPARE, REFRESH, and /STATUS.
	 CALL  parse_parm
;	 CASE current_parm=


;	    REFRESH:

		  .IF <parm_list[current_parm_DI].item_tag EQ REFRESH_item_tag> THEN

	       MOV   request_type,codepage_refresh
	       MOV   looking_for,eol
	       BREAK 12

		  .ENDIF


;	    PREPARE=:


	       ;Have to parse ((cplist) [filename])

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREPARE_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREP_equal>> THEN NEAR	;AN000;IF PREPARE= THEN

	       .IF <parm_list[current_parm_DI].parm_type EQ complx> THEN NEAR  ;AN000;should have found ((cplist) filename)
		  PUSH	SI  ;AN000;save pointer to first char past the closing right paren
		  MOV	AX,parm_list[current_parm_DI].value1
		  MOV	command_line,AX 			;AN000;point at first char past the left paren
		  SUB	DI,TYPE parm_list_entry 		;AN000;not parm, just indication of complex, delete from parm list
		  MOV	parms.parmsx_ptr,OFFSET prepare_equal_parmsx
		  MOV	prepare_equal_match_flags,complex     ;AN000;only thing valid next
		  CALL	parse_parm
		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].parm_type EQ complx> THEN	  ;AN000;assume have ((cplist) filename)
		     PUSH  SI  ;AN000;save pointer to first char past the closing right paren
		     MOV   AX,parm_list[current_parm_DI].value1
		     MOV   command_line,AX			   ;AN000;point at first char past the left paren
		     SUB   DI,TYPE parm_list_entry		;AN000;not parm, just indication of complex, delete from parm list
		     MOV   prepare_equal_match_flags,numeric+optional ;AN000;number or delimeter only things valid next
		     MOV   ordinal,0		     ;AN000;zap parms count,make parser count codepage numbers
		     .REPEAT
			CALL  parse_parm
			.IF <parser_return_code_AX EQ no_error> THEN
			   ADD	 des_start_packet.des_strt_pklen,2     ;increment size of parm block for another cp number
			   INC	 des_start_packet.des_strt_pknum       ;increment number of cp numbers
			   ADD	 current_packet_cp_number,2	       ;address next code page number slot
			   MOV	 SI,current_packet_cp_number
			   MOV	 BP,OFFSET des_start_packet
			   .IF <parm_list[current_parm_DI].item_tag EQ codepage_item_tag> THEN	;AN000;IF not skipped slot THEN
			      MOV   DX,parm_list[current_parm_DI].value1  ;AN000;store the number if one specified for this slot
			      MOV   [SI][BP].des_strt_pkcp1,DX		  ;put the number in the slot for the cp number
			   .ENDIF   ;AN000;not valid skipped codepage number, i.e. not (,850,,865) for example
			.ELSEIF <parser_return_code_AX EQ end_of_complex> THEN
			   SUB	 DI,TYPE parm_list_entry	;don't want an entry in the parm list for the zeroed out ")"
			.ELSE
			   CALL  setup_invalid_parameter
			.ENDIF
		     .UNTIL <parser_return_code_AX EQ end_of_complex> OR ;AN000;came to end of the cplist
		     .UNTIL <noerror EQ false>
		     POP   command_line      ;AN000;resume just after the closing paren of (cplist), should be at ) or filename
		  .ELSE    ;AN000;must be an error
		     MOV   message,OFFSET invalid_number_of_parameters
		     MOV   noerror,false
		  .ENDIF
		  .IF <noerror EQ true> THEN	;AN000;IF successfully broke down cplist and file name THEN
		     MOV   prepare_equal_match_flags,filespec+optional ;AN000;only thing valid is filespec
		     MOV   ordinal,0					;AN000;don't need parser to count the parms anymore
		     MOV   prepare_min_parms,0			;AN000;filename is optional
;		     A filespec may be next so colon cannot be a delimeter.
		     modify_parser_control_block seperator_list,delete,colon  ;AN000;want to find a keyword so don't stop on colons
		     CALL  parse_parm
		     .IF <parser_return_code_AX EQ no_error> THEN
			MOV   AX,parm_list[current_parm_DI].value1	   ;AN000;AX=OFFSET of filespec just encountered
			MOV   cp_cb.font_filespec,AX		   ;AN000;set up pointer to filespec for modecp
		     .ELSEIF <parser_return_code_AX EQ end_of_complex> THEN  ;AN000;cartridge prepare, no filename
			MOV   des_start_packet.des_strt_pkfl,DES_STRT_FL_CART	  ; 0001H=CARTRIDGE PREPARE,
		     .ELSE
			CALL  setup_invalid_parameter
		     .ENDIF
		     MOV   request_type,codepage_prepare		;AN000;if encountered an error won't continue anyways
		  .ENDIF
		  POP	command_line	     ;AN000;continue parsing after the origional complex, should be eol
	       .ELSE
		  MOV	message,OFFSET invalid_number_of_parameters ;AN000;should have found a complex
		  MOV	noerror,false
	       .ENDIF

	       MOV   looking_for,eol

	       BREAK 12

		  .ENDIF


;	    SELECT=:


dummy1:
PUBLIC DUMMY1
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SEL_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SELECT_equal>> THEN

	       .IF <parser_return_code_AX EQ no_error> THEN
		  MOV	codepage_index_holder,current_parm_DI		;AN000;save index of the codepage parm list entry for invoke
		  MOV	request_type,codepage_select
		  MOV	looking_for,eol
	       .ELSE
		  CALL	setup_invalid_parameter
	       .ENDIF

	       BREAK 12

		  .ENDIF



;	    /STATUS:


		  .IF <parser_return_code_AX EQ no_error> AND		;make sure don't have /STA:value
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STA>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STATUS>> THEN

	       MOV   request_type,codepage_status
;AX322;        .IF   <device_name EQ <OFFSET CON_str>> THEN
		  MOV	looking_for,eol
;AX322;        .ELSE
;AX322; 	  MOV	looking_for,eol
;AX322;        .ENDIF
	       BREAK 12

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,codepage_status
	       MOV   eol_found,true
	       BREAK 12

		  .ENDIF


;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK


	 ENDCASE_12: ;current_parm=


	 BREAK 0




      codepage_case:	   ;found PRN, only valid parms are CODEPAGE, and /STATUS
			   ;/STATUS is in the the parser control blocks

	 CALL  parse_parm
;	 CASE current_parm=

;	    CODEPAGE:

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ 0> AND		  ;AC007;wasn't SEL=cpnum or PREP=cpnum
		  .IF <parm_list[current_parm_DI].item_tag EQ codepage_item_tag> THEN	  ;AN000;IF found "codepage" or "cp" THEN

	       ;set up for codepage_prms_case
;	       modify_parser_control_block keywords,addd,codepage_keywords  ;AN000;codepage parms handler assumes keywords setup
	       MOV   looking_for,codepage_prms
	       BREAK 13

		  .ENDIF


;	    /STATUS:	   ;only CODEPAGE or end of line valid next

		  .IF <parser_return_code_AX EQ no_error> AND		;make sure don't have /STA:value
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STA>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STATUS>> THEN

	       CALL  parse_parm
	       .IF <parm_list[current_parm_DI].item_tag EQ codepage_item_tag> THEN
		  MOV	looking_for,eol
		  MOV	status_request,true
		  MOV	request_type,codepage_status
	       .ELSEIF <parser_return_code_AX EQ end_of_command_line> THEN
		  MOV	eol_found,true
		  MOV	status_request,true
		  MOV	request_type,codepage_status
	       .ELSE
		  CALL	setup_invalid_parameter
	       .ENDIF
	       BREAK 13

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,codepage_status
	       MOV   eol_found,true
	       BREAK 13

		  .ENDIF



;	    codepage_keyword_out_of_order:


		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREPARE_equal>> OR  ;AC007;if got here and have
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREP_equal>> OR 	;AC007;one of the codepage
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SEL_equal>> OR		;AC007;keywords then user
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SELECT_equal>> THEN	;AC007;forgot "CP"

	       MOV   message,OFFSET Invalid_number_of_parameters
	       MOV   noerror,false
	       BREAK 13  ;AN000;CON_keyword

		  .ENDIF



;	    REFRESH_out_of_order:   ;AC007;forgot to include "CP"


		  .IF <parm_list[current_parm_DI].item_tag EQ REFRESH_item_tag> THEN

	       MOV   message,OFFSET Invalid_number_of_parameters
	       MOV   noerror,false
;	       BREAK 13

		  .ELSE



;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK

		  .ENDIF

	 ENDCASE_13:

	 BREAK 0



      con_kwrd_status_or_cp_case:

      PUBLIC   con_kwrd_status_or_cp_case

	 MOV   parms.parmsx_ptr,OFFSET con_parmsx
	 CALL  parse_parm

;	 CASE current_parm=



;	    codepage:

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ 0> AND		  ;AC007;wasn't SEL=cpnum or PREP=cpnum
		  .IF <parm_list[current_parm_DI].item_tag EQ codepage_item_tag> THEN	  ;AN000;IF found "codepage" or "cp" THEN

	       MOV   looking_for,codepage_prms
	       BREAK 14

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,all_con_status	;AN000;found only CON on the command line
	       MOV   eol_found,true
	       BREAK 14

		  .ENDIF



;	    /STATUS:

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STA>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STATUS>> THEN

	       MOV   slash_status,deleted
	       MOV   slash_stat,deleted
	       MOV   slash_sta,deleted
	       MOV   request_type,all_con_status	;AN000;found only CON on the command line
	       MOV   looking_for,eol			;AC665;have MODE CON /STATUS, must find eol now
	       BREAK 14

		  .ENDIF



;	    con_keyword:


		  .IF <parser_return_code_AX EQ no_error> AND		;make sure invalid value not specified
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr NE 0> THEN  ;not pointing to /sta, not 0, must be a keyword

	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET rate_equal>> OR
	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET del_equal>> OR
	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET delay_equal>> THEN
		  INC	rate_and_delay_found		;found one, needs to be 2 before valid
	       .ELSEIF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREPARE_equal>> OR  ;AC007;if got here and have
	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET PREP_equal>> OR	     ;AC007;one of the codepage
	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SEL_equal>> OR	     ;AC007;keywords then user
	       .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET SELECT_equal>> THEN     ;AC007;forgot "CP"
		  MOV	message,OFFSET Invalid_number_of_parameters
		  MOV	noerror,false
	       .ELSE
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr NE <OFFSET COLUMNS_equal>> AND
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr NE <OFFSET COLS_equal>> AND
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr NE <OFFSET lines_equal>> THEN
		     CALL  setup_invalid_parameter	 ;AC007;keyword other than LINES=, COLS=, RATE= or DELAY= would require CP
		  .ENDIF				 ;AC007;and be handled above
	       .ENDIF
	       delete_parser_value_list_entry keywords,current_parm ;AN000;doesn't affect anything if invalid parm
	       MOV   looking_for,CON_keyword				;AN000;doesn't affect anything if invalid parm
	       BREAK 14  ;AN000;CON_keyword

		  .ENDIF



;	    REFRESH:		    ;AC007;forgot to include "CP"


		  .IF <parm_list[current_parm_DI].item_tag EQ REFRESH_item_tag> THEN

	       MOV   message,OFFSET Invalid_number_of_parameters
	       MOV   noerror,false
;	       BREAK

		  .ELSE



;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK

		  .ENDIF



	 ENDCASE_14:
	 BREAK 0   ;AN000;con_kwrd_status_or_cp_case:




      con_keyword_case: 	 ;found one, it has been deleted from the parser control blocks
      PUBLIC con_keyword_case

	 MOV   slash_status,deleted  ;AN000;remove /STA /STAT and STATUS
	 MOV   slash_stat,deleted
	 MOV   slash_sta,deleted

	 MOV   i_CL,1
	 .WHILE <i_CL LT number_of_con_keywords> AND
	 .WHILE <eol_found EQ false> AND
	 .WHILE <noerror EQ true> DO
	    PUSH  CX

	    CALL  parse_parm

;	    CASE return_code=

;	       con_keyword:

		     .IF <parser_return_code_AX EQ no_error> AND	   ;make sure don't have /STA:value
		     .IF <parm_list[current_parm_DI].keyword_switch_ptr NE 0> THEN  ;not 0, must be a keyword

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET rate_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET del_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET delay_equal>> THEN
		     INC   rate_and_delay_found 	   ;found one, needs to be 2 before valid
		  .ENDIF
		  delete_parser_value_list_entry keywords,current_parm
		  INC	i_CL
		  BREAK 15

		     .ENDIF


;	       eol:

		     .IF <parser_return_code_AX EQ end_of_command_line> THEN

		  .IF <rate_and_delay_found EQ both> OR 		;IF both OR neither found THEN
		  .IF <rate_and_delay_found EQ false> THEN
		     MOV   request_type,set_con_features
		     MOV   eol_found,true
		  .ELSE
		     MOV   message,OFFSET rate_and_delay_together	;RATE and DELAY must be specified together
		     MOV   noerror,false
		  .ENDIF
		  BREAK 15

		     .ENDIF


;	       otherwise:

		  CALL	setup_invalid_parameter
;		  BREAK

	    ENDCASE_15:

	    POP   CX

	 .ENDWHILE

	 MOV   looking_for,eol		 ;AN000;check for extraneous parms

	 BREAK 0 ;AN000;CON_keyword




      sd_or_dl_or_eol_case:

PUBLIC sd_or_dl_or_eol_case

	 ;have found a screen mode, now may find sd, dl, or eol

	 CALL	parse_parm
;	 CASE current_parm=

;	    sd: 		       ;found R or L

		  .IF <parm_list[current_parm_DI].item_tag EQ L_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ R_item_tag> THEN

	       MOV   looking_for,T_or_EOL			;AN000;request_type already set
	       BREAK 17

		  .ENDIF

;	    dl:

		  .IF <parm_list[current_parm_DI].item_tag EQ fourtythree_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ fifty_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ twentyfive_item_tag> THEN

	       MOV   looking_for,eol		;AN000;request_type already set
	       BREAK 17

		  .ENDIF



;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   eol_found,true		      ;AN000;request_type already set
	       BREAK 17

		  .ENDIF


;	    otherwise:	   regardless of what follows must have a parm here, didn't so yell

	       .IF <parser_return_code_AX EQ operand_missing> THEN	;AN000;two commas with nothing in between
		  MOV	message,OFFSET Invalid_number_of_parameters
		  MOV	noerror,false
	       .ELSE
		  CALL	setup_invalid_parameter 		      ;AN000;some bogus value or string
	       .ENDIF

;	       BREAK


	 ENDCASE_17:
	 BREAK 0  ;AN000;sd_or_dl_or_null



      sd_or_dl_case:

PUBLIC sd_or_dl_case

	 ;have no first parm, now must find shift direction or screen lines


	 CALL	parse_parm
;	 CASE current_parm=

;	    sd:

		  .IF <parm_list[current_parm_DI].item_tag EQ L_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ R_item_tag> THEN

	       MOV   looking_for,T_or_EOL
	       MOV   request_type,old_video_mode_set
	       BREAK 18

		  .ENDIF


;	    dl:

		  .IF <parm_list[current_parm_DI].item_tag EQ fourtythree_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ fifty_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ twentyfive_item_tag> THEN

	       MOV   request_type,old_video_mode_set
	       MOV   looking_for,eol
	       BREAK 18

		  .ENDIF



;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   message,OFFSET invalid_number_of_parameters
	       MOV   noerror,false
	       MOV   eol_found,true
	       BREAK 18

		  .ENDIF


;	    otherwise:

	       .IF <parser_return_code_AX EQ operand_missing> THEN	;AN000;two commas with nothing in between
		  MOV	message,OFFSET Invalid_number_of_parameters
		  MOV	noerror,false
	       .ELSE
		  CALL	setup_invalid_parameter 		      ;AN000;some bogus value or string
	       .ENDIF
;	       BREAK

	 ENDCASE_18:
	 BREAK 0   ;AN000;sd_or_dl



      T_or_EOL_case:


	 CALL  parse_parm

;	 CASE current_parm=

;	    T:

		  .IF <parm_list[current_parm_DI].item_tag EQ T_item_tag> THEN

	       MOV   looking_for,eol	  ;AN000;request_type already set
	       BREAK 19

		  .ENDIF

;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   eol_found,true		;AN000;request_type already set
	       BREAK 19

		  .ENDIF


;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK

	 ENDCASE_19:
	 BREAK 0



      device_name_or_eol_case:	      ;have only /status so far

	 ;The device names are in the parser control blocks

	 CALL	parse_parm
;	 CASE current_parm=

;	    COM?:

		  MOV  device_name,OFFSET COM1_str
		  .IF <parm_list[current_parm_DI].item_tag EQ COM1_item_tag> OR
		  MOV  device_name,OFFSET COM2_str
		  .IF <parm_list[current_parm_DI].item_tag EQ COM2_item_tag> OR
		  MOV  device_name,OFFSET COM3_str
		  .IF <parm_list[current_parm_DI].item_tag EQ COM3_item_tag> OR
		  MOV  device_name,OFFSET COM4_str
		  .IF <parm_list[current_parm_DI].item_tag EQ COM4_item_tag> THEN

	       MOV   looking_for,eol
	       MOV   request_type,com_status

	       BREAK 20

		  .ENDIF


;	    LPT?,
	    PRN:

		  MOV  device_name,OFFSET LPT1_str
		  .IF <parm_list[current_parm_DI].item_tag EQ PRN_item_tag> OR
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT1_item_tag> OR
		  MOV  device_name,OFFSET LPT2_str
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT2_item_tag> OR
		  MOV  device_name,OFFSET LPT3_str
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT3_item_tag> THEN

	       MOV   looking_for,eol
	       MOV   request_type,printer_status
	       BREAK 20

		  .ENDIF



;	    CON:

		  .IF <parm_list[current_parm_DI].item_tag EQ CON_item_tag> THEN

	       MOV   looking_for,eol
	       MOV   request_type,all_con_status
	       BREAK 20

		  .ENDIF


;	    eol:

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,status_for_everything
	       MOV   eol_found,true
	       BREAK 20

		  .ENDIF


;	    otherwise:

	       CALL  setup_invalid_parameter
;	       BREAK

	 ENDCASE_20:
	 BREAK 0  ;AN000;device_name_or_eol


      first_parm_case:


PUBLIC	 first_parm_case

	 ;set up for calls to system parser

	 MOV   command_line,OFFSET first_char_in_command_line	;AN000;start parser at beginning of the command line
	 MOV   BX,OFFSET parm_lst      ;set up parm_list
	 XOR   DI,DI
	 SUB   DI,TYPE parm_list_entry	     ;AN000;DI is negative, set up for first call to parse_parm

	 MOV   parms.parmsx_ptr,OFFSET parmsx	   ;AN000;set up parms block for parser input

	 CALL	parse_parm     ;AN000;parse first parm, fill in "parm_list[current_parm_DI]" with the results

;	 CASE current_parm=

dummy5:
PUBLIC	 dummy5

;	    /status:

		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STA>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_stat>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET slash_STATUS>> THEN

	       MOV   slash_status,deleted				;AN000;make it so /status again is an error
	       MOV   slash_stat,deleted
	       MOV   slash_sta,deleted
	       MOV   looking_for,device_name_or_eol
	       BREAK 21

		  .ENDIF


;	    null:		 ;no first parm

		  .IF <parser_return_code_AX EQ no_error> AND
		  .IF <parm_list[current_parm_DI].item_tag EQ unspecified> THEN   ;AN000;valid null

	       MOV   looking_for,sd_or_dl
	       MOV   parms.parmsx_ptr,OFFSET old_con_parmsx
	       MOV   ordinal,0					;AN000;start over with new parmsx block
	       MOV   device_name,OFFSET CON_str
	       MOV   request_type,old_video_mode_set
	       BREAK 21

		  .ENDIF


	    screen_modes:	  ;first parm is 80, BW80, MONO etc.

	    PUBLIC   screen_modes

		  .IF <parm_list[current_parm_DI].item_tag GE first_screen_mode_item_tag> AND
		  .IF <parm_list[current_parm_DI].item_tag LE last_screen_mode_item_tag> THEN

	       MOV   parms.parmsx_ptr,OFFSET old_con_parmsx
	       MOV   ordinal,0					;AN000;start over with new parmsx block
	       MOV   device_name,OFFSET CON_str
	       MOV   looking_for,sd_or_dl_or_eol
	       MOV   request_type,old_video_mode_set
	       BREAK 21

		  .ENDIF



;	    LPT?132,
;	    LPT?80:

		  MOV	device_name,OFFSET LPT1_str			  ;AN000;assume LPT1
		  MOV	device,"1"                              ;AC664;set up message
		  MOV	LPTNO,"1"                  ;see modeprin
		  MOV	parm_list[current_parm_DI+TYPE parm_list_entry].item_tag,onethirtytwo_item_tag   ;AN000;save chars/line
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT1132_item_tag> OR
		  MOV	device_name,OFFSET LPT2_str			  ;AN000;assume LPT2
		  MOV	LPTNO,"2"                  ;see modeprin
		  MOV	device,"2"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT2132_item_tag> OR
		  MOV	device_name,OFFSET LPT3_str			  ;AN000;assume LPT3
		  MOV	LPTNO,"3"                  ;see modeprin
		  MOV	device,"3"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT3132_item_tag> OR
		  MOV	device_name,OFFSET LPT1_str			  ;AN000;assume LPT1
		  MOV	device,"1"                              ;AC664;set up message
		  MOV	LPTNO,"1"                  ;see modeprin
		  MOV	parm_list[current_parm_DI+TYPE parm_list_entry].item_tag,eighty_item_tag	  ;AN000;save chars/line
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT180_item_tag > OR
		  MOV	device_name,OFFSET LPT2_str			  ;AN000;assume LPT2
		  MOV	LPTNO,"2"                  ;see modeprin
		  MOV	device,"2"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT280_item_tag > OR
		  MOV	device_name,OFFSET LPT3_str			  ;AN000;assume LPT3
		  MOV	LPTNO,"3"                  ;see modeprin
		  MOV	device,"3"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT380_item_tag > THEN


	       ADD   DI,TYPE parm_list_entry			;AN000;already have chars per line so skip to next element in list
	       MOV   parms.parmsx_ptr,OFFSET lpt_parmsx
	       MOV   REFRESH_str,deleted			;AN007;no codepage stuff legal
	       MOV   REF_str,deleted
	       MOV   SEL_equal,deleted
	       MOV   SELECT_equal,deleted
	       MOV   PREP_equal,deleted
	       MOV   PREPARE_equal,deleted
	       MOV   ordinal,1				;AN000;already found chars per line (cl)
	       MOV   looking_for,li_or_null
	       MOV   device_type,LPTX
	       MOV   request_type,old_initialize_printer_port
	       BREAK 21

		  .ELSE 		  ;AN000;clean up after dorking the next parameter
		     ADD   DI,TYPE parm_list_entry	;AN000;point to next entry, the one that needs to be reinitialized
		     CALL  reset_parm_pointer		;AN000;reinitialize the second parm entry, DEC DI
		  .ENDIF



;	    LPT1:=,
;	    LPT1=,
;	    LPT2:=,
;	    LPT2=,
;	    LPT3:=,
;	    LPT3=:


		  ;have control blocks set up to find COM strings as value of keyword

		  MOV  lptno,0				   ;lptno=BIOS digestable printer number for LPT1 set up for modeecho
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT1_colon_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT1_equal>> OR
		  MOV	lptno,1 									  ;set up for modeecho
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT2_colon_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT2_equal>> OR
		  MOV	lptno,2 									  ;set up for modeecho
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT3_colon_equal>> OR
		  .IF <parm_list[current_parm_DI].keyword_switch_ptr EQ <OFFSET LPT3_equal>> THEN
		     MOV   device,"1"                                                    ;set up for call to modeecho
		     .IF <parm_list[current_parm_DI].item_tag EQ COM1_item_tag> OR
		     MOV   device,"2"                                                    ;set up for call to modeecho
		     .IF <parm_list[current_parm_DI].item_tag EQ COM2_item_tag> OR
		     MOV   device,"3"                                                    ;set up for call to modeecho
		     .IF <parm_list[current_parm_DI].item_tag EQ COM3_item_tag> OR
		     MOV   device,"4"                                                    ;set up for call to modeecho
		     .IF <parm_list[current_parm_DI].item_tag EQ COM4_item_tag> THEN

	       MOV   looking_for,eol
	       MOV   request_type,printer_reroute
	       MOV   reroute_requested,true
	       MOV   device_type,LPTX
	       BREAK 21

		     .ELSE
			MOV   message,OFFSET com1_or_com2      ;AN000;"Must specify COM1, COM2, COM3 or COM4"
		     .ENDIF
		  .ENDIF



;	    LPTX,:		       found "LPTX," so chars per line has been skipped

		  .IF <terminating_delimeter EQ comma> AND NEAR ;AC007;handle other cases later, looking only for "LPTX," now
		  MOV	device_name,OFFSET LPT1_str			  ;AN000;assume LPT1
		  MOV	device,"1"                              ;AC664;set up message
		  MOV	LPTNO,"1"                  ;see modeprin
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT1_item_tag> OR
		  MOV	device_name,OFFSET LPT2_str			  ;AN000;assume LPT2
		  MOV	LPTNO,"2"                  ;see modeprin
		  MOV	device,"2"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT2_item_tag> OR
		  MOV	device_name,OFFSET LPT3_str			  ;AN000;assume LPT3
		  MOV	LPTNO,"3"                  ;see modeprin
		  MOV	device,"3"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT3_item_tag> THEN

	       MOV   parms.parmsx_ptr,OFFSET lpt_parmsx
	       MOV   lines_value_ptr,OFFSET LPT_lines_values
	       MOV   lines_match_flag,simple_string		;AN000;printer lines values are strings
	       MOV   REFRESH_str,deleted			;AN007;no codepage stuff legal
	       MOV   REF_str,deleted
	       MOV   SEL_equal,deleted
	       MOV   SELECT_equal,deleted
	       MOV   PREP_equal,deleted
	       MOV   PREPARE_equal,deleted
	       MOV   ordinal,1					;AN000;new parmsx, skip chars per line positional
	       ADD   DI,TYPE parm_list_entry			;create entry for skipped chars per line
	       MOV   looking_for,li_or_null
	       MOV   device_type,LPTX				;for rescode
	       MOV   request_type,old_initialize_printer_port
	       BREAK 21

		  .ENDIF




;		  need to use colon as a delimeter in following cases

		  modify_parser_control_block seperator_list,addd,colon  ;AN000;want to stop on colons

		  CALL	reset_parm_pointer	;reset to first entry in the parm list
		  MOV	ordinal,0		;start with the first parm again
		  MOV	command_line,OFFSET first_char_in_command_line	;look at first part of command line again
		  CALL	parse_parm	     ;AN000;parse the first parm again


;	    COM?:


		  MOV	device_name,OFFSET COM1_str			  ;AN000;assume COM1
		  MOV	device,"1"                              ;AN000;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ COM1_item_tag> OR
		  MOV	device_name,OFFSET COM2_str			  ;AN000;assume COM2
		  MOV	device,"2"                              ;AN000;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ COM2_item_tag> OR
		  MOV	device_name,OFFSET COM3_str			  ;AN000;assume COM3
		  MOV	device,"3"                              ;AN000;;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ COM3_item_tag> OR
		  MOV	device_name,OFFSET COM4_str			  ;AN000;assume COM4
		  MOV	device,"4"                              ;AN000;;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ COM4_item_tag> THEN

	       MOV   parms.parmsx_ptr,OFFSET com_parmsx
	       MOV   ordinal,0				;AN000;new parmsx, start with new number of positionals, start at first one
	       MOV   looking_for,com_keyword_or_baud
	       MOV   device_type,COMX			 ;AN000;;set up for rescode
	       BREAK 21

		  .ENDIF



;	    LPT?:

		  MOV	device_name,OFFSET LPT1_str			  ;AN000;assume LPT1
		  MOV	device,"1"                              ;AC664;set up message
		  MOV	LPTNO,"1"                  ;see modeprin
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT1_item_tag> OR
		  MOV	device_name,OFFSET LPT2_str			  ;AN000;assume LPT2
		  MOV	LPTNO,"2"                  ;see modeprin
		  MOV	device,"2"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT2_item_tag> OR
		  MOV	device_name,OFFSET LPT3_str			  ;AN000;assume LPT3
		  MOV	LPTNO,"3"                  ;see modeprin
		  MOV	device,"3"                              ;AC664;set up message
		  .IF <parm_list[current_parm_DI].item_tag EQ LPT3_item_tag> THEN

	       MOV   parms.parmsx_ptr,OFFSET lpt_parmsx
	       MOV   columns_value_ptr,OFFSET LPT_columns_values
	       MOV   lines_value_ptr,OFFSET LPT_lines_values
	       MOV   columns_match_flag,simple_string		;AN000;printer columns values are strings
	       MOV   lines_match_flag,simple_string		;AN000;printer lines values are strings
	       MOV   ordinal,0					;AN000;new parmsx so start over counting positionals
	       MOV   looking_for,prn_kw_status_cp_cl_null
	       MOV   device_type,LPTX				;for rescode
	       BREAK 21

		  .ENDIF


;	    PRN:

		  .IF <parm_list[current_parm_DI].item_tag EQ PRN_item_tag> THEN

	       MOV   looking_for,codepage
	       MOV   device_name,OFFSET LPT1_str
	       BREAK 21

		  .ENDIF


;	    CON:

		  .IF <parm_list[current_parm_DI].item_tag EQ CON_item_tag> THEN

	       MOV   parms.parmsx_ptr,OFFSET con_parmsx 	;AN000;set up for con parms
	       MOV   ordinal,0					;AN000;start over with new parmsx block
	       MOV   looking_for,BYTE PTR con_kwrd_status_or_cp
	       MOV   device_name,OFFSET CON_str
	       BREAK 21

		  .ENDIF



;	    eol:		 ;no parms specified

		  .IF <parser_return_code_AX EQ end_of_command_line> THEN

	       MOV   request_type,status_for_everything
	       MOV   eol_found,true
	       BREAK 21

		  .ENDIF



;	    COM?baud:


		  MOV	parms.parmsx_ptr, OFFSET mutant_COM_parmsx
		  ;for i in 1 through 4 see if the parm is COMi
		  MOV	match_found,false
		  MOV	i_CL,0				   ;AN000;CL:="1"
		  .WHILE <i_CL LT 4> AND
		  .WHILE <match_found EQ false> DO
		     CALL  reset_parm_pointer		   ;AN000;prepare to reparse the parm
		     INC   i_CL        ;AN000;use next number as a delimeter
		     MOV   parm_list[current_parm_DI].item_tag,i_CL	   ;AN000;depends on COM1 thru 4 item tags being 1 thru 4
		     PUSH  CX					;AN000;save the loop counter (the binary form)
		     ADD   i_CL,binary_to_ASCII 		;CL=ASCII representation of the index
		     modify_parser_control_block seperator_list,addd,i_CL   ;AN000;make the number (1 to 4)a seperator
		     MOV   ordinal,0					;AN000;look at first parm each time
		     MOV   command_line,OFFSET first_char_in_command_line   ;set parser up at start of the command line each time
		     PUSH  CX				   ;AN000;save the delimeter (ASCII form)
		     CALL   parse_parm
;		     .IF <parm_list[current_parm_DI].item_tag EQ COM_item_tag> THEN ;AN000;isloated "COM" so found "COM?"
		     .IF <parser_return_code_AX EQ no_error> THEN ;AN000;isloated "COM" so found "COMx"
			MOV   match_found,true
		     .ENDIF
		     POP   CX				      ;AN000;restore the ASCII delimeter
		     modify_parser_control_block seperator_list,delete,i_CL  ;AN000;fix parser control blocks
		     POP   CX				      ;restore the loop counter
		  .ENDWHILE
		  .IF <match_found EQ true> THEN   ;AN000;IF have COMX THEN look for valid baud
		     .IF <i_CL EQ 1> THEN
			MOV   device_name,OFFSET COM1_str
			MOV   parm_list[current_parm_DI].value1,OFFSET COM1_str ;AN000;setup for modecom existence check
			MOV   device,"1"                              ;AN000;set up message
		     .ELSEIF <i_CL EQ 2> THEN
			MOV   device_name,OFFSET COM2_str
			MOV   parm_list[current_parm_DI].value1,OFFSET COM2_str ;AN000;setup for modecom existence check
			MOV   device,"2"                              ;AN000;set up message
		     .ELSEIF <i_CL EQ 3> THEN
			MOV   device_name,OFFSET COM3_str
			MOV   parm_list[current_parm_DI].value1,OFFSET COM3_str ;AN000;setup for modecom existence check
			MOV   device,"3"                              ;AN000;set up message
		     .ELSE;IF <i_CL EQ 4> THEN
			MOV   device_name,OFFSET COM4_str
			MOV   parm_list[current_parm_DI].value1,OFFSET COM4_str ;AN000;setup for modecom existence check
			MOV   device,"4"                              ;AN000;set up message
		     .ENDIF

	       MOV   parms.parmsx_ptr,OFFSET com_parmsx
	       MOV   ordinal,0				;AN000;start with baud in new parmsx
	       MOV   looking_for,com_keyword_or_baud
	       MOV   device_type,COMX				;set up for rescode
	       BREAK 21


;	    otherwise:		  ;first parm was nothing recognizable

		  .ELSE

dummy4:
PUBLIC	 dummy4

	       MOV   ordinal,0					  ;AN000;parse first parm again
	       MOV   command_line,OFFSET first_char_in_command_line   ;set parser up at start of the command line one more time
	       modify_parser_control_block seperator_list,addd,"."    ;AN000;want to stop on periods
	       modify_parser_control_block seperator_list,addd,'"'    ;AN000;want to stop on quotes
	       modify_parser_control_block seperator_list,addd,'\'    ;AN000;want to stop on back slashes
	       modify_parser_control_block seperator_list,addd,'['    ;AN000;want to stop on left brackets
	       modify_parser_control_block seperator_list,addd,']'    ;AN000;want to stop on right brackets
	       modify_parser_control_block seperator_list,addd,'+'    ;AN000;want to stop on plus signs
;AC003;        modify_parser_control_block seperator_list,addd,';'    ;AN000;want to stop on semicolons

	       CALL  parse_parm
	       CALL  setup_invalid_parameter
;	       BREAK

		  .ENDIF

	 ENDCASE_21:

	 BREAK 0  ;AN000;first_parm



      eol_case:

	 CALL	parse_parm
	 .IF <parser_return_code_AX NE end_of_command_line> THEN
	    MOV   message,OFFSET invalid_number_of_parameters
	    MOV   noerror,false
	 .ELSE NEAR
	    MOV   eol_found,true
	 .ENDIF
;	 BREAK



   ENDCASE_0: ;AN000;looking_for=

.ENDWHILE

.IF <message NE no_message> THEN
   display  message
.ENDIF

RET

parse_parameters  ENDP







;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ SEPERATOR_LIST
;³ --------------
;³
;³ As the logic in PARSE_PARAMETERS proceeds the posibilities for the next parm
;³ become apparent and the parser control blocks need to be changed to correctly
;³ parse the next parm.  This procedure is responsible for manipulating the
;³ list of seperators as requested.
;³
;³
;³
;³
;³  INPUT: action (in BX) - A scalar immediate indicating whether the seperator
;³			     is to be added or deleted.
;³
;³	   seperator_charactor (in AL) - The seperator character to be added or
;³					  deleted from the seperator list
;³
;³
;³  RETURN: none
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³  REGISTER
;³  USAGE:
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³  ASSUMPTIONS: The character exists in the list before it is deleted.
;³		 A character being added is not already in the list.
;³		 There is no "extra end of line list".
;³		 Direction flag is cleared so REPs will increment index reg
;³		 ES and DS are the same and address data
;³
;³
;³
;³
;³
;³
;³  SIDE EFFECT:
;³
;³
;³
;³
;³
;³  LOGIC:
;³
;³
;³  CASE action=
;³
;³     add:
;³
;³	  skip to end of seperators list  ;use parms.seperators_len to find end
;³	  overwrite zero with AL
;³	  overwrite blank space holder in the delimeter list with AL
;³	  INC	parms.seperators_len
;³	  BREAK
;³
;³
;³     delete:
;³
;³	  DEC	parms.seperators_len
;³	  scan to seperator char to be deleted
;³	  shift remaining chars to left
;³	  put zero at end for length of the extra EOL list
;³	  BREAK
;³
;³  ENDCASE
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ


seperator_list	PROC  NEAR

;CASE modifier=

SHL   BX,1			 ;AN000;BX=word displacement into jump table
JMP   jump_table2[BX]		 ;AN000;jump to appropriate jump

jump_table2 LABEL WORD

DW    OFFSET add_case
DW    OFFSET delete_case


   add_case:


      XOR   BX,BX
      MOV   BL,parms.seperators_len	  ;AN000;BX=length of seperators list
      ADD   BX,OFFSET parms
      MOV   [BX].seperators,AL		  ;AN000;overwrite blank with AL
      INC   parms.seperators_len	  ;AN000;adjust for added seperator
      BREAK 22


   delete_case:

      ;scan to seperator char to be deleted

      PUSH  DI

      MOV   DI,OFFSET parms
      ADD   DI,OFFSET seperators       ;ES:DI=>seperator list
      REPNE SCASB
      DEC   DI			       ;AN000;DI=>char to be deleted
      MOV   ES:[DI],BYTE PTR blank		;duplicate but harmless blank

      POP   DI

      BREAK 22

ENDCASE_22:

RET

seperator_list	ENDP


;-------------------------------------------------------------------------------
;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ KEYWORDS
;³ --------
;³
;³ As the logic in PARSE_PARAMETERS proceeds the posibilities for the next parm
;³ become apparent and the parser control blocks need to be changed to correctly
;³ parse the next parm.  This procedure is responsible for manipulating the
;³ list of keywords as requested.
;³
;³
;³
;³
;³# INPUT: action (in BX) - A scalar immediate indicating whether the keyword
;³#			      is to be added or deleted.
;³#
;³#
;³#	   string (in RL) - A scalar immediate or OFFSET, indicating/pointing
;³#			      to the keyword or set of keywords to be added
;³#			      or deleted.
;³
;³
;³
;³  RETURN: none
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³
;³  ASSUMPTIONS:
;³
;³
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ


keywords PROC NEAR

;	    use result.synonym to find the the keyword to delete

	    MOV   SI,parm_list[current_parm_DI].keyword_switch_ptr	;SI=>the keyword string to be deleted
	    MOV   BYTE PTR ES:[SI],deleted	  ;AN000;zilch out first byte of the keyword string


   RET

keywords  ENDP

;-------------------------------------------------------------------------------


;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ PARSE_PARM
;³ ----------
;³
;³ Add the parm found to the parm_list.  Save the pointer to the current parm
;³ for use by CALL  reset_parm_pointer.  When a reset call from  reset_parm
;³ happens the pointer to the last entry in the parm list is decremented, which
;³ will put the results of the next parse over that entry.
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  INPUT:
;³
;³
;³  RETURN: The next parm list entry is filled with the results of the call to
;³	    the parser.  If the parser returns an error other than "end of
;³	    command line" the entry is not filled in.  If the parser returns
;³	    "end of command line" the .type field is set to end_of_command_line.
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³
;³
;³
;³
;³  ASSUMPTIONS:
;³
;³
;³
;³
;³
;³
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

parse_parm  PROC

PUBLIC	 PARSE_PARM

   ADD	 current_parm_DI, TYPE parm_list_entry

   PUSH  current_parm_DI	  ;save index into parsed parms list
   PUSH  BX			 ;save the address of the parsed parms list

   MOV	   DI,OFFSET PARMS	   ; ES:DI=>PARSE CONTROL DEFINITON
   MOV	   SI,COMMAND_line	   ; DS:SI=>unparsed portion of the command line
   MOV	   DX,0 		   ; RESERVED
   MOV	   CX,ordinal		   ; OPERAND ORDINAL
   EXTRN   SYSPARSE:NEAR
   CALL    SYSPARSE		    ;AX=return code, DX=>result buffer
   MOV	   ordinal,CX		    ;save for next call
   MOV	   terminating_delimeter,BL ;save the character that delimited the parm

   POP	 BX			 ;restore parm_list
   POP	 current_parm_DI	 ;nothing returned in DI anyway

   MOV	 CX,command_line	    ;AN000;CX=>first char of the bad parm
   MOV	 offending_parameter_ptr,CX ;AN000;set pointer in message

;  .IF <parser_return_code_AX EQ no_error> THEN
      MOV   command_line,SI	       ;save pointer to remainder of the command line
      .IF <parser_return_code_AX NE end_of_command_line> THEN
	 MOV   DL,result.ret_type
	 MOV   parm_list[current_parm_DI].parm_type,DL
	 MOV   DL,result.item_tag
	 MOV   parm_list[current_parm_DI].item_tag,DL
	 MOV   DX,result.ret_value1
	 MOV   parm_list[current_parm_DI].value1,DX
	 MOV   DX,result.ret_value2
	 MOV   parm_list[current_parm_DI].value2,DX
	 MOV   DX,result.synonym
	 MOV   parm_list[current_parm_DI].keyword_switch_ptr,DX
      .ENDIF
;  .ELSE			       ;AN000;encountered an error
;     MOV   CX,command_line	       ;AN000;CX=>first char of the bad parm
;     MOV   offending_parameter_ptr,CX ;AN000;set pointer in message
;     MOV   BYTE PTR [SI],0	       ;AN000;make the offending parm an ASCIIZ string
;  .ENDIF			       ;AN000;leave the call to msg services to the calling routine

   RET

parse_parm  ENDP



;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ RESET_PARM_POINTER
;³ ------------------
;³
;³
;³
;³ The last entry in the parm list is decremented, which
;³ will put the results of the next parse over that entry.
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  INPUT:
;³
;³
;³  RETURN: The current parm list entry is filled with recognizable trash
;³
;³
;³
;³
;³  MESSAGES: none
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³
;³  REGISTER
;³  USAGE:
;³
;³
;³
;³  CONVENTIONS:
;³
;³
;³
;³
;³
;³
;³
;³  ASSUMPTIONS:
;³
;³
;³
;³
;³
;³
;³
;³
;³  SIDE EFFECT:
;³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
reset_parm_pointer  PROC



   MOV	 parm_list[current_parm_DI].parm_type,bogus
   MOV	 parm_list[current_parm_DI].item_tag,0FFH
   MOV	 parm_list[current_parm_DI].synonym,bogus
   MOV	 parm_list[current_parm_DI].value1,bogus
   MOV	 parm_list[current_parm_DI].value2,bogus
   MOV	 parm_list[current_parm_DI].keyword_switch_ptr,0
   SUB	 current_parm_DI,TYPE parm_list_entry
   DEC	 ordinal


   RET

reset_parm_pointer ENDP


PRINTF_CODE ENDS
	END
