	PAGE	,132				; 

;************************************************************************************
;
; IFSFUNC Symbols
;
; Old Redirector Stuff
TRUE	    EQU 0FFFFh
FALSE	    EQU 0
PATHGEN = TRUE
DEBUG = FALSE
REDIRECTOR = TRUE
Installed = TRUE
MSNET_TIMING = FALSE
IF1
	IF MSNET_TIMING
		%out  MSNET_TIMING version
	ENDIF
	IF DEBUG
		%out  DEBUGGING version
	ENDIF
		%out  INSTALLED version
ENDIF
; Structures and equates for the network support
;Net call interrupt - used to generate critical sections
NET_CALL_INT	EQU	2AH
;Max size of PRINT_PRE_STRING
MAX_PRE_STRING	EQU	64
;AH function code for $GET_IN_VARS INT 21 function
GET_IN_VAR	EQU	52H
; The following EQUates control the replacement of the FCB SFT cache by
;   IFSFUNC. If the current FCB Cache Size,Keepcount is DefNumFCB,DefKeepVal
;   then IFSFUNC will set up a new cache of NewNumFCB,NewKeepVal.
DefNumFCB	EQU	4
DefKeepVal	EQU	0
NewNumFCB	EQU    16
NewKeepVal	EQU	8
SUBTTL	IFSFUNC Data
PAGE
; miscellaneous IFS equates
MINUS_ONE	EQU	-1
NULL_PTR	EQU	-1
ERROR_INFO_NOT_SET EQU	-1
CHECK_REMOVABLE EQU	4408H
ICOLON		EQU	":"
ZERO		EQU	0
OLDOPEN_MODE	EQU   2180H
OLDOPEN_FLAG	EQU   0101H
OLDCREATE_MODE	EQU   0002H
OLDCREATE_FLAG	EQU   0112H
OLDCREATENEW_FLAG EQU	10H
;INT21AL_LOCK_READ    EQU  4								 ;AD004;
;INT21AL_WRITE_UNLOCK EQU  5								 ;AD004;
IFSFINSTALLED	EQU    0FFH
GET_TRUNCATE_FLAG EQU	7
SET_TRUNCATE_FLAG EQU	8
;;;alias COMPLEX  EQU	  4
PARSE_ERR_1	EQU	1
PARSE_ERR_5	EQU	5
PARSE_ERR_6	EQU	6
PARSE_ERR_10	EQU	10
COMMON_ERR_2	EQU	2
COMMON_ERR_3	EQU	3
UTIL_ERR_4	EQU	4
RETRY		EQU	1
I2F5_MsgRet	EQU	2
; ifsproc flags
IsCDS		EQU	80H
IsSFT		EQU	40H
IsSEQ		EQU	20H
IsGet		EQU	10H	; vs. set
IsOldOpen	EQU	10H
IsOldCreate	EQU	08H
IsCreate	EQU	8000H	; used in IFS_OPEN in setting sf date/time
IsClose 	EQU	10H	; vs. commit
IsRen		EQU	10H	; vs. delete
;IsLockRead	 EQU	 10H								 ;AD005;
;IsWriteUnlock	 EQU	 08H								 ;AD005;
;IsAdd		 EQU	 04H								 ;AD005;
THISIFS_SET	EQU	02H
IsShare 	EQU	80H	; used by auto-attach
IsCTLFCN	EQU	01H	; used by IFS_UPDATE_CB@
IsCritIFS	EQU	02H	; indicates ifs cs
Print_On	EQU	80H	; sess
SetDeviceCB	EQU	0100H	; indicates to sft_to_sff to set ifs_device_cb@
IsDummyCDS	EQU	0200H	; used to indicate dummy cds (AttStrt/CDS-CD)
IsNetwork	EQU	0400H	; indicates types 3 or 4 attach
SetBP		EQU	0800H	; set if return lsn
Filesys_Status	EQU	1000H	; indicates new style get ifsfunc item
;Filesys_Network_Attach EQU 1000H ; flag used to determine if move ptr direct to parms	 ;AN003;;AD009;
;IsWOLock	 EQU	 2000H	 ; write operation only lock - flag moved RMG		 ;AD004;
IsInit		EQU	2000H	; this set in AutoAttach for CI-error area
IsResetEnvirn	EQU	4000H	; used in sess - diff abort from reset environment
IsMsgRet	EQU	8000H	; used in ifserror - int2f5 to distinguish msg ret
				;		     from command.com
; ifsfunc flags
UNC_INSTALLED	EQU	80H	; unc file system installed
NO_IFS_DRIVERS	EQU	40H	; no ifs drivers installed

; ifs semaphores IFSSEM equates
MR_ERRMSG_SEM	EQU	80H	; used by ifserror INT2F AH=5 as gate for msgret entry
; DFL -  This structure stores IFS/NETUSE/ALIAS Device information
;	 to IFS driver.

DFLL_LIST	STRUC
DFLL_FLAGS	DB	?		  ; Flags
DFLL_TYPE	DB	?		  ; 1=IFS, 3=NETUSE, 0=ALIAS
DFLL_DEV_NAME	DB	8 DUP (?)	  ; Device name
DFLL_USER_WORD	DW	?		  ; attach user word
DFLL_ALIAS_INDEX DW	?		  ; Byte index into alias names list (resv)
DFLL_IFS_HDR	DD	?		  ; Pointer to IFSHDR
DFLL_FSDA	DB	8 DUP (?)	  ; File System Dependent Data Area
DFLL_DEVPTR	DD	?		  ; sft_devptr
DFLL_LIST	ENDS
; dfl flags
DFL_INPROG	EQU	80H		  ; in progress
DFL_INUSE	EQU	40H		  ; in use
DFL_PAUSED	EQU	20H		  ; device is paused
DFL_DEV_REAL	EQU	10H		  ; device is real
; error codes
device_not_attached	equ	0FH	  ;
fs_driver_not_found	equ	67	  ;
error_out_of_structs	equ	56	  ;
