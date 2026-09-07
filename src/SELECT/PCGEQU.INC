;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""          =B
;		 VIDEO REGISTER PORT ADDRESS EQUATES				  =B
;
;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""          =B
seq_addr	EQU	0C4H	;AN000;Sequencer  Address				=B
seq_data	EQU	0C5H	;AN000;Sequencer  Data					=B
crtc_addr	EQU	0D4H	;AN000;CRT Controller Address (Color)			=B
crtc_addr_b	EQU	0B4H	;AN000;CRT Controller Address (Mono)			=B
crtc_data	EQU	0D5H	;AN000;CRT Controller Data				=B
graph_1_pos	EQU	0CCH	;AN000;Graphics 1 Position				=B
graph_2_pos	EQU	0CAH	;AN000;Graphics 2 Position				=B
graph_addr	EQU	0CEH	;AN000;Graphics 1 & 2 Address				=B
graph_data	EQU	0CFH	;AN000;Graphics 1 & 2 Data				=B
misc_output	EQU	0C2H	;AN000;Miscellaneous Output				=B
misc_read	EQU	0CCH	;AN000;Miscellaneous Output Read Port Address		=B
in_stat_0	EQU	0C2H	;AN000;Input Status Register 0				=B
input_status_b	EQU	0BAH	;AN000;Feature Control (Mono)				=B
input_status	EQU	0DAH	;AN000;Feature Control (Color)				=B
attr_read	EQU	0C1H	;AN000;Attribute Controller Read Address		=B
attr_write	EQU	0C0H	;AN000;Attribute Controller Write Address		=B
fctrl_read	EQU	0CAH	;AN000;Feature Control Regiester Read Address		=B

;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
;	     SEQUENCER ADDRESS REGISTER EQUATES
;
;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
s_reset 	EQU	00H	;AN000;Reset						=B
s_clock 	EQU	01H	;AN000;Clocking Mode					=B
s_map		EQU	02H	;AN000;Map Mask 					=B
s_cgen		EQU	03H	;AN000;Character Map Select				=B
s_mem		EQU	04H	;AN000;Memory Mode					=B


;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
;	     GRAPHICS ADDRESS REGISTER EQUATES
;
;"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
g_set_reset	EQU	00H	;AN000;set/reset					=B
g_enbl_set	EQU	01H	;AN000;enable set/reset 				=B
g_clr_comp	EQU	02H	;AN000;color compare					=B
g_data_rot	EQU	03H	;AN000;data rotate					=B
g_read_map	EQU	04H	;AN000;read map select					=B
g_mode		EQU	05H	;AN000;mode						=B
g_misc		EQU	06H	;AN000;miscellaneous					=B
g_color 	EQU	07H	;AN000;color don't care                                 =B
g_bit_mask	EQU	08H	;AN000;bit mask 					=B

;---------------------------------------------------------------------+
;								      |
;	 Miscellaneous Equates					      |
;								      |
;---------------------------------------------------------------------+

LINELEN        EQU  80			     ;AN000; Length of a Graphics Buffer Line
COLPELS        EQU  8			     ;AN000; Number of pels per text column
DEFROFFU       EQU  0			     ;AN000; Default Pointer Icon Row Center Offset
DEFROFFD       EQU  14			     ;AN000; Default Pointer Icon Row Center Offset
DEFCOFFR       EQU  11			     ;AN000; Default Pointer Icon Column Center Offst
DEFCOFFL       EQU  4			     ;AN000; Default Pointer Icon Column Center Offst
ICONROWS       EQU  16			     ;AN000; Number of Rows in Pointer Icon
ICONCOLS       EQU  16			     ;AN000; Number of Columns in Pointer Icon
SHFTMSK        EQU  07H 		     ;AN000; Column Shift Count Bit Mask (Hi-Res)
M_BLACK        EQU  0			     ;AN000;default background color (icon)
M_WHITE        EQU  15			     ;AN000;default foreground color (icon)
M_DAXIS        EQU  11			     ;AN000;default axis mouse pointer
VSICONR        EQU  28			     ;AN000;# pel rows
VSICONC        EQU  2*8 		     ;AN000;# pel columns
MVSICONR       EQU  16			     ;AN000;minimun pel rows in sb icon
MHSICONC       EQU  3*8 		     ;AN000;minimum pel cols in sb icon

;;
;;  Long Conditional Jump Macros
;;
lja		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jna	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljae		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnae	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljb		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnb	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljc		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnc	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljbe		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnbe	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
lje		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jne	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljz		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnz	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljg		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jng	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljge		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnge	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljl		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnl	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljle		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jnle	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljnc		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jc	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljne		macro	Farlabel	     ;
		local	Nearlabel	     ;
		je	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljnz		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jz	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljno		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jo	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
ljo		macro	Farlabel	     ;
		local	Nearlabel	     ;
		jno	Nearlabel	     ;
		jmp	Farlabel	     ;
Nearlabel:				     ;
		endm			     ;
