	PAGE	,132				;
;******************************************************************************
;   IFS Symbol File
;
SUBTTL	IFS Driver Header
PAGE
IFSHEADER	STRUC
IFS_NEXT	DD	-1	; Next header in list (-1=end)
IFS_NAME	DB	"        " ; IFS name
IFS_ATTRIBUTE	DW	?	; Attributes
IFS_VERSION	DW	0	; Request level supported
IFS_DOSCALL@	DD	?	; DOS interface routine
				;   (set by TUPPER before the init call)
IFS_CALL@	DW	?	; Function entry point
IFSHEADER	ENDS
; ifs_attribute equates
IFSDEVICE	EQU	8000H	;  Supports single device/file functions
IFSDISK 	EQU	4000H	;  Supports multi-file functions
IFSUNC		EQU	2000H	;  Support UNC (nameless) connection
IFSREMOTE	EQU	0800H	;  File system is remote
IFSFILTER	EQU	0400H	;  FS will filter (if off, use DOS
				;    standard, cap & 8.3)
IFSIOCTL	EQU	0002H	;  Supports IOCTL functions
IFSUSESHARE	EQU	0001H	;  Uses DOS share support (vs own share)
SUBTTL	IFSRH - IFS Request Header
PAGE
; IFS Request Header
IFSRH		STRUC
IFSR_LENGTH	DW    ? 		; Total length of request
IFSR_FUNCTION	DB    ? 		; Requested function
IFSR_RETCODE	DW    ? 		; Explicit error
IFSR_RETCLASS	DB    ? 		; Error class
IFSR_RESV1	DB    16 DUP(0) 	; DOS reserved
IFSR_FCN_PARMS	DB    50 DUP(0) 	; Additional parameters
IFSRH		ENDS
; IFSR_FUNCTION codes
;	Control requests:
IFSINIT        EQU     1
IFSATTSTART    EQU     2
IFSATTSTAT     EQU     3
IFSATTEND      EQU     4
IFSEXECAPI     EQU     5
IFSCRITMSG     EQU     6
IFSUPDATECB    EQU     7
; IFSR_APIFUNC	codes:
;      Int 21 mapped requests:
IFSDRIVERESET	   EQU	 1
IFSDISKATTR	   EQU	 2
IFSMKDIR	   EQU	 3
IFSRMDIR	   EQU	 4
IFSCHDIR	   EQU	 5
IFSDELFILE	   EQU	 6
IFSRENFILE	   EQU	 7
IFSSEARCHFILE	   EQU	 8
IFSOPENFILE	   EQU	 9
IFSLSEEKFILE	   EQU	10
IFSREADFILE	   EQU	11
IFSWRITEFILE	   EQU	12
IFSLOCKFILE	   EQU	13
IFSCLOSEFILE	   EQU	14
IFSFILEATTR	   EQU	15
IFSDEPIOCTL	   EQU	16
IFSDEVIOCTL	   EQU	17
IFSEOP		   EQU	18
IFSEOCID	   EQU	19
SUBTTL	Control Request Parameter Macro
PAGE
IFSR_FCN_DEF	    MACRO  fcn
		    IFIDN  <fcn>,<INIT>
 IFSR_PARMS@	    =  DWORD PTR  IFSR_FCN_PARMS    ; command parameters
 IFSR_RESSIZE	    =  WORD  PTR  IFSR_FCN_PARMS+4  ; driver total size
 LENGTH_INIT	    EQU IFSR_RESSIZE-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<ATTSTART>
 IFSR_TYPE	    =  BYTE  PTR  IFSR_FCN_PARMS    ; attach type
 IFSR_PARMS@	    =  DWORD PTR  IFSR_FCN_PARMS+2  ; command parameters
 IFSR_DEVICE_CB@    =  DWORD PTR  IFSR_FCN_PARMS+6  ; CD/DF
 IFSR_USER_WORD     =  WORD  PTR  IFSR_FCN_PARMS+10 ; for unc deviceless attach
 LENGTH_ATTSTART    EQU IFSR_USER_WORD-IFSRH+2						 ;AC001;/
		    ELSE
		    IFIDN  <fcn>,<ATTSTAT>
 IFSR_TYPE	    =  BYTE  PTR  IFSR_FCN_PARMS    ; attach type
 IFSR_PARMS@	    =  DWORD PTR  IFSR_FCN_PARMS+2  ; command parameters
 IFSR_DEVICE_CB@    =  DWORD PTR  IFSR_FCN_PARMS+6  ; CD/DF
 IFSR_USER_WORD     =  WORD  PTR  IFSR_FCN_PARMS+10 ; for unc deviceless attach
 IFSR_MAX_XMITT_SIZE = WORD  PTR  IFSR_FCN_PARMS+12 ; redir-maximum transmit size
 IFSR_NET_NAME_ID   =  WORD  PTR  IFSR_FCN_PARMS+14 ; redir-net name id
 IFSR_LSN	    =  WORD  PTR  IFSR_FCN_PARMS+16 ; redir-low byte=local session #
 IFSR_DEVICE_STATUS =  BYTE  PTR  IFSR_FCN_PARMS+18 ; redir-interesting bits
 LENGTH_ATTSTAT     EQU IFSR_DEVICE_STATUS-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<ATTEND>
 IFSR_DEVICE_CB@    =  DWORD PTR  IFSR_FCN_PARMS    ; CD/DF
 IFSR_NAME@	    =  DWORD PTR  IFSR_FCN_PARMS+4  ; UNC deviceless detach
 LENGTH_ATTEND	    EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<EXECAPI>
 IFSR_APIFUNC	    =  BYTE  PTR  IFSR_FCN_PARMS    ; API function code
 IFSR_ERROR_CLASS   =  BYTE  PTR  IFSR_FCN_PARMS+1  ; DOS extended error class
 IFSR_ERROR_ACTION  =  BYTE  PTR  IFSR_FCN_PARMS+2  ; DOS extended error action
 IFSR_ERROR_LOCUS   =  BYTE  PTR  IFSR_FCN_PARMS+3  ; DOS extended error locus
 IFSR_ALLOWED	    =  BYTE  PTR  IFSR_FCN_PARMS+4  ; DOS extended error locus
 IFSR_I24_COUNT     =  BYTE  PTR  IFSR_FCN_PARMS+5  ; critical error retry count
						    ;  0=first time
 IFSR_I24_RESP	    =  BYTE  PTR  IFSR_FCN_PARMS+6  ; critical error response
						    ;	 0=ignore  1=retry
 IFSR_DEVICE_CB@    =  DWORD PTR  IFSR_FCN_PARMS+8  ; device (CD or DF)
 IFSR_OPEN_CB@	    =  DWORD PTR  IFSR_FCN_PARMS+12 ; open file instance  (SF)
 IFSR_API_PARMS     =  BYTE  PTR  IFSR_FCN_PARMS+16
		    ELSE
		    IFIDN  <fcn>,<CRITMSG>
 IFSR_MSG@	    =  DWORD PTR  IFSR_FCN_PARMS    ; message buffer address
 IFSR_MSG_TYPE	    =  BYTE  PTR  IFSR_FCN_PARMS+4  ; message type
						 ; 1=message is printed in form
						 ;    <message>
						 ;    Abort,Retry,Ignore,Fail
						 ; 0=message is printed in form
				 ; <message> error (read/writ)ing (drive/device) XXX ;
				 ; Abort,Retry,Ignore,Fail
 LENGTH_CRITMSG     EQU IFSR_MSG_TYPE-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<UPDATECB>
 IFSR_CB@	    =  DWORD PTR      IFSR_FCN_PARMS	; control block address
 IFSR_TYPE	    =  BYTE  PTR      IFSR_FCN_PARMS+4	; control block type
 IFSOPEN	    EQU   0		  ; open instance (SFT) entry
 IFSCB		    EQU   -1		  ; see control block type field
 LENGTH_UPDATECB    EQU IFSR_TYPE-IFSRH+2
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDM
SUBTTL	INT 21H Mapped Request Parameter Macro
PAGE
IFSR_API_DEF	    MACRO  fcn
		    IFIDN  <fcn>,<DRIVERESET>
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 0=flush
 LENGTH_DRIVERESET  EQU IFSR_FUNC-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<DISKATTR>
 IFSR_ALLOCUNITS    =  WORD  PTR  IFSR_API_PARMS    ; # allocation units
 IFSR_ALLOCSIZE     =  WORD  PTR  IFSR_API_PARMS+2  ; allocation unit sectors
 IFSR_SECTSIZE	    =  WORD  PTR  IFSR_API_PARMS+4  ; sector size
 IFSR_AVAILALLOC    =  WORD  PTR  IFSR_API_PARMS+6  ; free allocation units
 IFSR_FSID	    =  BYTE  PTR  IFSR_API_PARMS+8  ; file system media id
 LENGTH_DISKATTR    EQU IFSR_FSID-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<MKDIR>
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS    ; asciiz name to process
 LENGTH_MKDIR	    EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<RMDIR>
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS    ; asciiz name to process
 LENGTH_RMDIR	    EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<CHDIR>
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS    ; asciiz name to process
 LENGTH_CHDIR	    EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<DELFILE>
 IFSR_MATCHATTR_47  =  WORD  PTR  IFSR_API_PARMS    ; format 00000000e0a00shr
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS+2  ; file to delete
 LENGTH_DELFILE     EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<RENFILE>
 IFSR_MATCHATTR     =  WORD  PTR  IFSR_API_PARMS    ; format 00000000e0a00shr
 IFSR_NAME1@	    =  DWORD PTR  IFSR_API_PARMS+2  ; file to rename
 IFSR_NAME2@	    =  DWORD PTR  IFSR_API_PARMS+6  ; new file name
 LENGTH_RENFILE     EQU IFSR_NAME2@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<SEARCHFILE>
 IFSR_SUBFUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 1=first, 2=next
 IFSR_CONTINFO@     =  DWORD PTR  IFSR_API_PARMS+2  ; continuation info addr
 IFSR_MATCHATTR     =  WORD  PTR  IFSR_API_PARMS+6  ; format 0000000re0advshr  (1st)
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS+8  ; asciiz name to process   (1st)
 LENGTH_SEARCHFILE  EQU IFSR_NAME@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<OPENFILE>
 IFSR_MODE	    =  WORD  PTR  IFSR_API_PARMS    ; open mode
						 ;  format: 0WF0000CISSS0AAA
						 ;  AAA=access code 0=read,1=write
						 ;		    2=read/write
						 ;  SSS=sharing mode 0=compatibility
						 ;	1=deny r/w, 2=deny write
						 ;	3=deny read, 4=deny none
						 ;  I 0=pass handle to child, 1=no inheri;AN000;t
						 ;  C 0=validate cp, 1=no cp check
						 ;  F 0=int 24H, 1=return error on
						 ;  this open & any I/O to this handle
						 ;  W 0=no commit, 1=auto-commit on
						 ;		     write
 IFSR_FLAG	    =  WORD  PTR  IFSR_API_PARMS+2  ; function control;  format=CE
						 ; C=does not exist action
						 ; 0=fail, 1=create
						 ; E=exists action
						 ; 0=fail, 1=open, 2=replace/open
 IFSR_CP	    =  WORD  PTR  IFSR_API_PARMS+4  ; global code page
 IFSR_CPSW	    =  BYTE  PTR  IFSR_API_PARMS+6  ; CPSW flag
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS+8  ; asciiz name to open
 IFSR_PARMS@	    =  DWORD PTR  IFSR_API_PARMS+12 ; format:
						 ;	     DD  EA address
						 ;	     DW  #parms
						 ;	     DB  IOMODE ID
						 ;	     DW  IO Mode
 IFSR_MATCHATTR     =  WORD  PTR  IFSR_API_PARMS+16 ; format 00000000e0advshr
 IFSR_ACTION	    =  WORD  PTR  IFSR_API_PARMS+18
 LENGTH_OPENFILE    EQU IFSR_ACTION-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<LSEEKFILE>
 IFSR_MODE	    =  BYTE  PTR  IFSR_API_PARMS    ; see INT 21H AH=42H
 IFSR_POSITION	    =  DWORD PTR  IFSR_API_PARMS+2  ; displacement of LSEEK
 LENGTH_LSEEKFILE   EQU IFSR_POSITION-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<READFILE>
;IFSR_MODE	    =  BYTE  PTR  IFSR_API_PARMS					 ;AD005;
 IFSR_COUNT	    =  WORD  PTR  IFSR_API_PARMS+2
 IFSR_BUFFER@	    =  DWORD PTR  IFSR_API_PARMS+4
 LENGTH_READFILE    EQU IFSR_BUFFER@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<WRITEFILE>
;IFSR_MODE	    =  BYTE  PTR  IFSR_API_PARMS					 ;AD005;
 IFSR_COUNT	    =  WORD  PTR  IFSR_API_PARMS+2
 IFSR_BUFFER@	    =  DWORD PTR  IFSR_API_PARMS+4
 LENGTH_WRITEFILE   EQU IFSR_BUFFER@-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<LOCKFILE>
;IFSR_MODE	    =  BYTE  PTR  IFSR_API_PARMS    ;  bit 0: 0=lock all operations	 ;AD005;
						    ;  1=lock only write operations	 ;AD005;
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 0=LOCK, 1=UNLOCK
;IFSR_COUNT	    =  WORD  PTR  IFSR_API_PARMS+2					 ;AD005;
;IFSR_RANGE@	    =  DWORD PTR  IFSR_API_PARMS+4					 ;AD005;
 IFSR_LK_POSITION   =  DWORD PTR  IFSR_API_PARMS+2
 IFSR_LK_LENGTH     =  DWORD PTR  IFSR_API_PARMS+6
 LENGTH_LOCKFILE    EQU IFSR_LK_LENGTH-IFSRH+4
		    ELSE
		    IFIDN  <fcn>,<CLOSEFILE>
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 0=CLOSE, 1=COMMIT
 LENGTH_CLOSEFILE   EQU IFSR_FUNC-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<FILEATTR>
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 0=get, 1=set by handle
						    ; 2=get, 3=set by name
 IFSR_SUBFUNC	    =  BYTE  PTR  IFSR_API_PARMS+2  ; 0=none,2=EA List, 3-EA names
						    ; 2,3 used only on IFSR_FUNC=0,1
 IFSR_BUFFER1@	    =  DWORD PTR  IFSR_API_PARMS+4  ; if IFSR_TYPE=2,3
 IFSR_BUFFER2@	    =  DWORD PTR  IFSR_API_PARMS+8  ; if IFSR_TYPE=2
 IFSR_COUNT	    =  WORD  PTR  IFSR_API_PARMS+12 ; if IFSR_TYPE=2,3
 ; Following present only if IFSR_FUNC=2,3
 IFSR_MATCHATTR     =  WORD  PTR  IFSR_API_PARMS+14 ; format 0000000re0advshr
 IFSR_NAME@	    =  DWORD PTR  IFSR_API_PARMS+16 ; ASCIIZ file name
 IFSR_SIZE	    =  DWORD PTR  IFSR_API_PARMS+20 ; file size
 IFSR_DATE	    =  WORD  PTR  IFSR_API_PARMS+24 ; file date
 IFSR_TIME	    =  WORD  PTR  IFSR_API_PARMS+26 ; file time
 IFSR_ATTR	    =  WORD  PTR  IFSR_API_PARMS+28 ; format 0000000re0advshr
 LENGTH_FILEATTR    EQU IFSR_ATTR-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<DEPIOCTL>
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 00 Generic IOCTL by device #
						    ; 01 Generic IOCTL by handle
						    ; 02 FS IOCTL query OS type
 IFSR_BUFFER@	    =  DWORD PTR  IFSR_API_PARMS+2  ; set on queries
 IFSR_BUFSIZE	    =  WORD  PTR  IFSR_API_PARMS+6  ; Buffer size set for IFSR_FUNC=2
 ; FUNC dependent parameters
 ; For generic
 IFSR_CATEGORY	    =  BYTE  PTR  IFSR_API_PARMS+8  ; generic subfunctions
 IFSR_CTLFUNC	    =  BYTE  PTR  IFSR_API_PARMS+9  ; see INT 21H AH=6BH
 LENGTH_DEPIOCTL    EQU IFSR_CTLFUNC-IFSRH+1
		    ELSE
		    IFIDN  <fcn>,<DEVIOCTL>
 IFSR_FUNC	    =  BYTE  PTR  IFSR_API_PARMS    ; 00 Generic IOCTL by device #
						 ; 01 Generic IOCTL by handle
						 ; 02 FS IOCTL query OS type
 IFSR_BUFFER@	    =  DWORD PTR  IFSR_API_PARMS+2  ; set on queries
 IFSR_BUFSIZE	    =  WORD  PTR  IFSR_API_PARMS+6  ; buffer size set for IFSR_FUNC=2
 ; FUNC dependent parameters
 ; For generic
 IFSR_CATEGORY	    =  BYTE  PTR  IFSR_API_PARMS+8  ; generic subfunctions
 IFSR_CTLFUNC	    =  BYTE  PTR  IFSR_API_PARMS+9  ; see INT 21H AH=6BH
 LENGTH_DEVIOCTL    EQU IFSR_CTLFUNC-IFSRH+1
		    ELSE
		    IFIDN  <fcn>,<EOP>
 IFSR_PID	    =  WORD  PTR  IFSR_API_PARMS    ; process ID
 IFSR_SUBFUNC	    =  BYTE  PTR  IFSR_API_PARMS+2  ; 0=NORMAL EXIT, 1=ABORT EXIT
 LENGTH_EOP	    EQU IFSR_SUBFUNC-IFSRH+2
		    ELSE
		    IFIDN  <fcn>,<EOCID>
 IFSR_UID	    =  WORD  PTR  IFSR_API_PARMS    ; process ID
 LENGTH_EOCID	    EQU IFSR_UID-IFSRH+2
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDIF
		    ENDM
SUBTTL	Request Data
PAGE
;	     Attach types
;;;aliasTYPE_ALIAS	EQU	0
TYPE_DEVICE	EQU	1
TYPE_DRIVE	EQU	2
TYPE_NET_DEVICE EQU	3
TYPE_NET_DRIVE	EQU	4
;	     Attach cmds
GET_MODE	EQU	0
SET_MODE	EQU	1
GET_ASSIGN_LIST EQU	2
DEFINE_MACRO	EQU	3
CANCEL_ATTACH	EQU	4
ATTACH_PARMS	STRUC
AP_COUNT	DW	?
AP_STRING	DB	?
ATTACH_PARMS	ENDS
;	     Critical Error Message types
CRIT_MSG_TYPE_1 	equ	1
TYPE1		EQU	1
TYPE0		EQU	0
;	     Control Block types
CBTYPE_SFF	EQU	0
CBTYPE_CD	EQU	1
CBTYPE_DF	EQU	2
CBTYPE_DUMMYCD	EQU	3
;	     Drive Reset equates
FUNC_FLUSH		EQU	0
FUNC_FLUSH_INVALIDATE	EQU	1
;	     Search File equates
IFSSEARCH_FIRST EQU	1
IFSSEARCH_NEXT	EQU	2
;	     Open/Create type
TYPE_NONE	EQU	0
NOTEXIST_ACT_FAIL      = 0						   ;+BAF
NOTEXIST_ACT_CREATE    = 1						   ;+BAF
EXIST_ACT_FAIL	       = 0						   ;+BAF
EXIST_ACT_OPEN	       = 1						   ;+BAF
EXIST_ACT_REP_OPEN     = 2						   ;+BAF

FILE_OPENED	       = 1
FILE_CREATED	       = 2
FILE_REPLACED	       = 3
;	     Read/Write equates
;MODE_READ	   EQU	 0								 ;AD005;
;MODE_WRITE	   EQU	 0								 ;AD005;
;MODE_LOCK_READ    EQU	1								 ;AD005;
;MODE_WRITE_UNLOCK EQU	1								 ;AD005;
;MODE_WRITE_SFPOS  EQU	  00H								 ;AD005;
;MODE_WRITE_SFSIZE EQU	  02H								 ;AD005;
;MODE_ADD_MASK	      EQU  00000010B	 ; do I need this???				 ;AD005;
;	     Lock equates
;MODE_LOCK_ALL	      EQU  0								 ;AD005;
;MODE_LOCK_WRITE      EQU  1								 ;AD005;
FUNC_LOCK	     EQU  0
FUNC_UNLOCK	     EQU  1
;MODE_ADD_MASK	      EQU  00000010B							 ;AD005;
;MODE_WO_MASK	      EQU  10000000B							 ;AN004; BAF ;AD005;
;LOCK_RANGE_STRUC	 STRUC								 ;AD005;
;   IFSR_LOCK_POSITION	 DD	 ?							 ;AD005;
;   IFSR_LOCK_LENGTH	 DD	 ?							 ;AD005;
;LOCK_RANGE_STRUC	 ENDS								 ;AD005;

;	     Close equates
FUNC_CLOSE	  EQU	0
FUNC_COMMIT	  EQU	1
;	     LSeek equates
MODE2		  EQU	2
;	     File Attribute equates
FUNC_GET_BY_HANDLE	EQU	0
FUNC_SET_BY_HANDLE	EQU	1
FUNC_GET_BY_NAME	EQU	2
FUNC_SET_BY_NAME	EQU	3
SUBFUNC_INLINE		EQU	0
SUBFUNC_EA		EQU	2
SUBFUNC_EA_NAMES	EQU	3
;	     FS Dependent IOCTL
GEN_IOCTL_BY_DEVNUM	    EQU     0
GEN_IOCTL_BY_HANDLE	    EQU     1
QUERY_OS_TYPE		    EQU     2
CATEGORY_FS		    EQU     0
CATEGORY_REDIR		    EQU     1
PRINTER_SET_STRING	    EQU     2
PRINTER_GET_STRING	    EQU     3
PRINTER_SET_FLAGS	    EQU     4
PRINTER_GET_FLAGS	    EQU     5
CTLFUNC_PRINTER_SET_STRING  EQU   00100001B
CTLFUNC_PRINTER_GET_STRING  EQU   00000001B
CTLFUNC_PRINTER_SET_FLAGS   EQU   00100010B
CTLFUNC_PRINTER_GET_FLAGS   EQU   00000010B
CTLFUNC_DEVECHOCHECK	    EQU   00000011B
CTLFUNC_GET_UNC_ITEM	    EQU   00000100B
CTLFUNC_DEVCLOSE	    EQU   00000101B
CTLFUNC_DEVOPER 	    EQU   00000110B
CTLFUNC_PRINT_ON	    EQU   00100111B
CTLFUNC_PRINT_OFF	    EQU   00000111B
CLOSE_SPOOL_FILES	    EQU     9
LENGTH_DEVECHOCHECK_BUFFER  EQU 1
;	     FS Device IOCTL
READ_DEVICE		    EQU     2
WRITE_DEVICE		    EQU     3
CHAR_GENERIC		    EQU     0CH
BLOCK_GENERIC		    EQU     0DH
;	     End of Process equates
EOP_NORMAL	EQU	0
EOP_ABORT	EQU	1
RESET_ENVIRONMENT EQU	2
SUBTTL	Request Return Classes/Codes
PAGE
;  IFS Request Return Codes
IFSR_NO_ERROR		EQU	0
IFSR_NONSPEC_ERROR	EQU	1
IFSR_NOT_FOUND_ERROR	EQU	2
IFSR_ACCESS_DENIED	EQU	3
IFSR_DEVICE_TYPE_MISMATCH EQU	4
IFSR_NO_SUBFCN_SUPPORT	EQU    -2
IFSR_NO_FCN_SUPPORT	EQU    -1
;  IFS Request Return Classes
IFSR_INT21H_ERROR	EQU	1
IFSR_DRIVER_ERROR	EQU	2
IFSR_INT21H_CRITER	EQU	3
IFSR_DEVICE_ERROR	EQU	4
IFSR_BAD_FORMAT 	EQU    -1

;
;  Int 24H
NO_RETRY	=	0
I24_RESP_IGNORE =	0
I24_RESP_RETRY	=	1

;  IFS_DOSCALL@ function equates
;  Block Device Driver Requests
CALL_INTERRUPT_ROUTINE	EQU	1
READ_SECTORS		EQU	2
WRITE_SECTORS		EQU	3
FIND_SECTOR		EQU	8
MARK_SECTOR_CHANGED	EQU	9
;  Buffer Cache Requests
WRITE_DOS_BUFFER	EQU	10
READ_DOS_BUFFER 	EQU	11
FREE_DOS_BUFFER 	EQU	12
FLUSH_DOS_BUFFERS	EQU	13
;  Get DOS Variable
GET_DOS_VALUE		EQU	32
ACTIVE_PROCESS_INFO	EQU	1
CPSW_INFORMATION	EQU	2
BREAK_INFORMATION	EQU	3
VERIFY_INFORMATION	EQU	4
CONFIG_SYS_VALUES	EQU	5
    DOS_VALUE_BUFFER	    STRUC
       VAL_BUF_SIZE    DW      14
       VAL_BUF_FILES   DW      0
       VAL_BUF_FCBS    DW      0
		       DW      0
       VAL_BUF_BUFS    DW      0
		       DW      0
       VAL_BUF_LDRV    DW      0
       VAL_BUF_SSZ     DW      0
    DOS_VALUE_BUFFER	    ENDS
MACHINE_NAME		EQU	6
COUNTRY_INFO		EQU	7
SHARE_RETRY_COUNT	EQU	8
;  Get Assign Mode
GET_ASSIGN_MODE 	EQU	33
DEVICE_MACRO	=	3
DRIVE_MACRO    =	4
PAUSE_MODE_ON	=	1
PAUSE_MODE_OFF	=	0
;
DOS2NET_DATE	=	34
NET2DOS_DATE	=	35
DOS_STRCMP	=	36
DOS_STRCPY	=	37
USE_SYSTEM_TIMEDATE  =	0
USE_USER_TIMEDATE    =	1
;
SUBTTL	Pseudo Block Structures: SF, CD, DF
PAGE
; SFF - Pseudo SFT
;	 This structure is used to pass pertinent SFT information
;	 to IFS driver.
SFF		 STRUC			  ; Open File Control Block
SFF_TYPE	 DB	0,0		  ; Identifies SFF
SFF_FLAGS	 DW	 ?		  ; Control flags
					  ;   4000H=don't set date/time on close
					  ;   0080H=device (vs file)
					  ;   0040H=File clean
SFF_MODE	 DW	 ?		  ; Mode of access.
					  ;   8000H=FCB (vs handle)[this moved from flags]
SFF_RESV1	 DW	 ?		  ; IO mode.					 ;AC023; iomode
SFF_ATTR	 DW	 ?		  ; File attr.FORMAT : 0000000re0advshr
SFF_UID 	 DW	 ?		  ; User ID
SFF_PID 	 DW	 ?		  ; Process ID
SFF_SIZE	 DD	 ?		  ; File size
SFF_POSITION	 DD	 ?		  ; Read/Write pointer
SFF_TIME	 DW	 ?		  ; File time
SFF_DATE	 DW	 ?		  ; File date
SFF_NAME	 DB	 8 DUP (?)	  ; Name
SFF_EXT 	 DB	 3 DUP (?)	  ; Extension
SFF_RESV2	 DW	 0		  ; Code page					 ;AC024; cp
SFF_SF_ID	 DW	 0		  ; Unique SFT entry identifier
SFF_RESV	 DB	12 DUP(0)	  ; Reserved
SFF_FSDA	 DB	 8 DUP(?)	  ; File System Dependent Data Area
SFF		ENDS
; sff_flags bits
SFF_Close_NoDate EQU	4000H		  ;   4000H=don't set date/time on close
SFF_IsDevice	 EQU	0080H		  ;   0080H=device (vs file)
SFF_FileClean	 EQU	0040H		  ;   0040H=File clean
SFF_Device_Raw	 EQU	0020H		  ;   0020H=Device raw
SFF_Net_Spool	 EQU	0000100000000000B
; sff_mode  bits
SFF_IsFCB	 EQU	8000H		  ;   8000H=FCB (vs handle)[this moved from flags]

; CD  - Pseudo CDS
;	 This structure is used to pass pertinent CDS information
;	 to IFS driver.
CD		STRUC
CD_TYPE 	DB	1,0		  ; Identifies CD
CD_END		DW	?		  ; End of assignment in CD_TEXT
CD_TEXT 	DB	67 DUP (?)	  ; Text of assignment and curdir
CD_RESV 	DB	5 DUP(0)	  ; Reserved
CD_FSDA 	DB	8 DUP(?)	  ; File System Dependent Data Area
CD		ENDS
; DF  - Pseudo DFL
;	 This structure is used to pass pertinent DFL information
;	 to IFS driver.

DFL		STRUC
DFL_TYPE 	DB	2,0		  ; Identifies DFL
DFL_DEV_NAME	DB	8 DUP (?)	  ; Device name
DFL_FSDA 	DB	8 DUP (?)	  ; File System Dependent Data Area
DFL		ENDS
SUBTTL	Search Continuation Information
PAGE
CONTINFO	STRUC
CI_SEARCH_FN	DB	8 DUP(?)   ; SEARCH FILE NAME
CI_SEARCH_FN_EXT DB	3 DUP(?)   ; SEARCH FILE EXTENSION
CI_SEARCH_ATTR	DB	?	   ; SEARCH ATTRIBUTE
CI_FSDA 	DB	8 DUP(?)   ; FSDA
				   ; Directory entry:
CI_FOUND_FN	DB	8 DUP(?)   ; FOUND FILE NAME
CI_FOUND_FN_EXT DB	3 DUP(?)   ; FOUND FILE EXTENSION
CI_FOUND_ATTRL	DB	?	   ; FOUND ATTRIBUTE LOW  ??? DB/DD
CI_CP		DW	?	   ; FILE CODE PAGE (OR 0)
CI_RESV1	DW	?	   ; RESERVED
CI_FOUND_ATTRH	DB	?	   ; FOUND ATTRIBUTE HIGH
CI_RESV2	DB	5  DUP(?)  ; RESERVED
CI_FILE_TIME	DW	?	   ; FILE TIME
CI_FILE_DATE	DW	?	   ; FILE DATE
CI_FSWORD	DW	?	   ; MEANING FILE SYSTEM SPECIFIC
				   ; (STARTING CLUSTER IN FAT)
CI_FILE_SIZE	DD	?	   ; FILE SIZE
CONTINFO	ENDS


CATEGORY_PRINTER       EQU	5

CTLFUNC_SELECT	       EQU	4AH
CTLFUNC_QUERY_SELECTED EQU	6AH
CTLFUNC_QUERY_PREPLIST EQU	6BH

DEV_OPER_BUFFER        STRUC
  OPER_FUNC	DB	?
  TRUNC_FLAG	DB	?
DEV_OPER_BUFFER        ENDS

PACKET		       STRUC	; device ioctl buffer info
  PACKLEN	DW	2	; length of packet in bytes
  PACKCPID	DW	?	; code page id
PACKET		       ENDS

