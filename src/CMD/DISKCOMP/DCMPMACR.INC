	IF1
	    %OUT INCLUDING DCMPMACR.INC...
	ELSE
;	    %OUT INCLUDING DCMPMACR.INC...
	ENDIF
;***************************************************************************;
;			     MACRO DEFINITION				    ;
;***************************************************************************;

HEADER	MACRO	TEXT		       ;
.XLIST				       ;
	SUBTTL	&TEXT		       ;
.LIST				       ;
	PAGE			       ;
	ENDM			       ;
;  =  =  =  =  =  =  =	=  =
DOSCALL 			   MACRO FUNC,SUBFUNC  ;
				   IFNB <FUNC> ;;AN000;IS THERE ANY PARMS AT ALL?
				   IFNB <SUBFUNC> ;
				   MOV AX,(FUNC SHL 8)+SUBFUNC ;;AN000;FUNC TO AH,SUBFUNC TO AL
				   ELSE    ;;AN000;SINCE THERE IS NO SUBFUNC
				   MOV AH,FUNC ;
				   ENDIF   ;
				   ENDIF   ;
				   INT 21H ;
				   ENDM    ;
;  =  =  =  =  =  =  =	=  =
PRINT	MACRO	MESSAGE 		   ;
				   MOV	   DI,OFFSET MESSAGE ;
				   CALL    SENDMSG ;
	ENDM					   ;
;  =  =  =  =  =  =  =	=  =
.xlist
;INPUT	 MACRO	 MESSAGE
;				    PRINT   MESSAGE
;				    CALL PROMPT
;	 ENDM
.list
;	       $SALUT (0,16,22,36)
MY_TRACKLAYOUT MACRO		   ;
	       LOCAL CSECT_F	   ;
CSECT_F        DW    0		   ;;AN000;# OF SECTORS IN A TRACK. Currently 18 is max.
				   ;;  THE REST IS FOR FUTURE MEDIA
	       DW    1		   ;;AN000;1 ST SECTOR
	       DW    512	   ;;AN000;# OF BYTES
	       DW    2		   ;
	       DW    512	   ;
	       DW    3		   ;
	       DW    512	   ;
	       DW    4		   ;
	       DW    512	   ;
	       DW    5		   ;
	       DW    512	   ;
	       DW    6		   ;
	       DW    512	   ;
	       DW    7		   ;
	       DW    512	   ;
	       DW    8		   ;
	       DW    512	   ;
	       DW    9		   ;
	       DW    512	   ;
	       DW    10 	   ;
	       DW    512	   ;
	       DW    11 	   ;
	       DW    512	   ;
	       DW    12 	   ;
	       DW    512	   ;
	       DW    13 	   ;
	       DW    512	   ;
	       DW    14 	   ;
	       DW    512	   ;
	       DW    15 	   ;
	       DW    512	   ;
	       DW    16 	   ;
	       DW    512	   ;
	       DW    17 	   ;
	       DW    512	   ;
	       DW    18 	   ;
	       DW    512	   ;;AN000;CURRENTLY 18 SECTORS/TRACK IS MAXIMUM
	       DW    19 	   ;;AN000;BELOW IS FOR THE FUTURE MEDIA.
	       DW    512	   ;
	       DW    20 	   ;
	       DW    512	   ;
	       DW    21 	   ;
	       DW    512	   ;
	       DW    22 	   ;
	       DW    512	   ;
	       DW    23 	   ;
	       DW    512	   ;
	       DW    24 	   ;
	       DW    512	   ;
	       DW    25 	   ;
	       DW    512	   ;
	       DW    26 	   ;
	       DW    512	   ;
	       DW    27 	   ;
	       DW    512	   ;
	       DW    28 	   ;
	       DW    512	   ;
	       DW    29 	   ;
	       DW    512	   ;
	       DW    30 	   ;
	       DW    512	   ;
	       DW    31 	   ;
	       DW    512	   ;
	       DW    32 	   ;
	       DW    512	   ;
	       DW    33 	   ;
	       DW    512	   ;
	       DW    34 	   ;
	       DW    512	   ;
	       DW    35 	   ;
	       DW    512	   ;
	       DW    36 	   ;
	       DW    512	   ;
	       DW    37 	   ;
	       DW    512	   ;
	       DW    38 	   ;
	       DW    512	   ;
	       DW    39 	   ;
	       DW    512	   ;
	       DW    40 	   ;
	       DW    512	   ;
	       DW    41 	   ;
	       DW    512	   ;
	       DW    42 	   ;
	       DW    512	   ;
	       DW    43 	   ;
	       DW    512	   ;
	       DW    44 	   ;
	       DW    512	   ;
	       DW    45 	   ;
	       DW    512	   ;
	       DW    46 	   ;
	       DW    512	   ;
	       DW    47 	   ;
	       DW    512	   ;
	       DW    48 	   ;
	       DW    512	   ;
	       DW    49 	   ;
	       DW    512	   ;
	       DW    50 	   ;
	       DW    512	   ;
	       DW    51 	   ;
	       DW    512	   ;
	       DW    52 	   ;
	       DW    512	   ;
	       DW    53 	   ;
	       DW    512	   ;
	       DW    54 	   ;
	       DW    512	   ;
	       DW    55 	   ;
	       DW    512	   ;
	       DW    56 	   ;
	       DW    512	   ;
	       DW    57 	   ;
	       DW    512	   ;
	       DW    58 	   ;
	       DW    512	   ;
	       DW    59 	   ;
	       DW    512	   ;
	       DW    60 	   ;
	       DW    512	   ;
	       DW    61 	   ;
	       DW    512	   ;
	       DW    62 	   ;
	       DW    512	   ;
	       DW    63 	   ;
	       DW    512	   ;
	       ENDM
