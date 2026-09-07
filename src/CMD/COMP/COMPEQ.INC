;*****************************************************************************
;
; MODULE: compeq.inc
;
               if1
                     %OUT INCLUDING COMPEQ.INC...
               endif

EAISBINARY     equ  02h           ;extended attribute is a binary integer
EASYSTEM       equ  8000h         ;extended attr. is system defined

VERSION        EQU  00H           ;DOS VERSION, =00H (NOT USED)
NUL            EQU  00H           ;END OF STRING (ASCIIZ) MARKER
ONE_PARM       EQU  01H           ;ONLY PARSE ONE PARAMETER
ZERO_PARM_CT   EQU  00H           ;ORDINAL # BEFORE PARSING FIRST PARM.
FIRST_PARM_CT  EQU  01H           ;ORDINAL # AFTER PARSING FIRST PARM.
TRICK_PARM_CT  EQU  02H           ;TRICK PARSER SO THAT FILENAME GOES TO PATH2
                                  ;INSTEAD OF PATH1
YES            EQU  01H           ;A VALID YES RESPONSE EQUALS 1
KEYB_INP_CLR   EQU  0C1H          ; does an INT 21H fuction 0CH, 01H
KEYB_INPUT     EQU  0FFH          ;DO A READ ON CLEAR KEYBOARD
INPUT_LEN      EQU  127           ;LENGTH OF INPUT BUFFER ON BUFFERED INPUT
KEYIN          EQU  01H           ;WAIT FOR KEYBOARD INPUT TO AL
DISP_OUT       EQU  02H           ;DL = CHAR TO BE DISPLAYED TO STD OUT
DIRECT_IO      EQU  06H           ;DUMBY CALL, USED IN CLEARING KEYBOARD
BUFFD_KEYBD    EQU  0AH           ;BUFFERED KEYBOARD INPUT TO DX
IN_STAT        EQU  0BH           ;check keyboard status
CLEAR_KEYBD    EQU  0CH           ;CLEAR KEYB, DO KEYB FUNC IN AL
FCBOpen        equ  0FH           ;fcb open
FCBCLOSE       EQU  10H           ;FCB CLOSE FILE
SearchF        equ  11H           ;FCB Search function call
SEARCHN        EQU  12H           ;FCB SEARCH NEXT
SetDTA         equ  1AH           ;Set DTA
DEFDRV         equ  19H           ;get default drive
YESNO_CHECK    EQU  23H           ;CHECK (Y/N) RESPONSE ON INPUT (EXTENDED COUNTRY INFO)
SETVECTOR      equ  25H           ;set interrupt vector in AL to DS:DX
FCBRndBlkRead  equ  27H           ;Read function call
PARSE_FILENAME EQU  29H           ;PARSE FILENAME
GETVER         equ  30H           ;get dos version
CHDIR          equ  3BH           ;CHDIR function call
HandleOpen     equ  3DH           ;Handle open function call
HANDLECLOSE    EQU  3EH           ;HANDLE CLOSE FUNCTION CALL
Write          equ  40H           ;Write function call
CURDIR         equ  47H           ;get current directory for drive in [dl]
RET_FN         EQU  4CH           ;"RETURN TO DOS" NOT REMAIN RESIDENT
GET_EXT_CNTRY_INFO EQU 65H        ;EXTENED COUNTRY INFO DOS CALL

STDOUT          equ  0001H        ;Standard output device
STDERR          equ  0002H        ;Standard error device

ReadOnlyAccess  equ  00H          ;Access code for Handle Open function call

CPSW_CHECK      EQU  33H          ;CODE PAGE SWITCHING CONTROL
GET_CPSW_STATE  EQU  03H          ;AL=3, GET STATE TO DL
SET_CPSW_STATE  EQU  04H          ;AL=4, SET STATE FROM DL
CPSW_OFF        EQU  00H          ; DL=0, OFF
CPSW_ON         EQU  01H          ; DL=1, ON
CPSW            EQU  40H          ;IN CPSW_ORIG: ON, CPSW=ON
ZERO_CP         EQU  00H          ; A ZERO CODE PAGE

;   EXTENDED OPEN EQUATES         ;                                    LOOK
NO_ATTR_LIST    EQU  00H          ;NO ATTRIBUTE LIST NEEDED            ||
OPEN_MODE       EQU  82H          ;OPEN MODE FOR EXTENDED OPEN         ||
FUNC_CNTRL      EQU  0101H        ;FUNCTION CONTROL FOR EXTENDED OPEN  ||
EXT_OPEN_RD     EQU  00H          ;READ MODE ON EXTENDED OPEN          \/
EXT_OPEN        EQU  6CH          ;EXTENDED OPEN
                                  ;AL=FUNCTION CONTROL, IN FORMAT=CE
                                  ; C=DOES NOT EXIST ACTION:
                                  ;   0=FAIL, 1=CREATE
                                  ; E=EXISTS ACTION
                                  ;   0=FAIL, 1=OPEN, 2=REPLACE/OPEN
                                  ;BX=OPEN MODE, FORMAT=0WF00000ISSS0AAA
                                  ;   AAA=ACCESS CODE: 0=READ, 1=WRITE
                                  ;    2=READ/WRITE, 4=EXECUTE (UNDOC)
                                  ;    7=FCB (UNDOC)
                                  ;   SSS=SHARING MODE: 0=COMPATIBILITY
                                  ;    1=DENY READ/WRITE, 2=DENY WRITE
                                  ;    2=DENY READ, 3=DENY NONE
                                  ;   I=0, PASS HANDLE TO CHILD, 1=NO INHERIT
                                  ;   F=0, INT 24H, 1=RETURN ERROR
                                  ;ON THIS OPEN AND ANY IO TO THIS HANDLE
                                  ;   W=0, NO COMMIT, 1=AUTO-COMMIT ON WRITE
                                  ;CX=SCARCH/CREATE ATTRIBUTE
                                  ;DX=FUNCTION CONTROL, 0000000C NNNNEEEE
                                  ; NNNN=DOES NOT EXIST ACTION:
                                  ;  0=FAIL,1=CREATE
                                  ; EEEE=DOES EXIST ACTION:
                                  ;  0=FAIL,1=OPEN,2=REPLACE/OPEN
                                  ; C=CODEPAGE ACTION:
                                  ;  0=VALIDATE, 1=NO CHECK CODE PAGE
                                  ;DS:SI=PARM LIST:
                                  ;    DD POINT TO NAME TO OPEN
                                  ;    DB NUMBER OF ADDITIONAL PARMS
                                  ;    DB 1  IO MODE
                                  ;    DB IOMODE
                                  ;       ???0H=UNSPECIFIED (DEFAULT)
                                  ;       ???1H=MAINLY SEQUENTIAL
                                  ;       ???2H=MAINLY RANDOM
                                  ;       ???3H=RANDOM WITH LOCALITY
                                  ;       ???=RESERVED (SET TO ZERO)
                                  ;ES:DI=EXTENTED ATTR LIST

                                  ;OUTPUT: CY SET ON ERROR
                                  ; AX=HANDLE
                                  ; CX=ACTION TAKEN: 1=FILE OPENED,
                                  ;  2=FILE CREATED/OPENED,
                                  ;  3=FILE REPLACED/OPENED

EXT_ATTR_LIST   EQU  57H          ;FUNCTION # : EXTENDED ATTR LIST
GET_EXT_ATTR_LIST EQU 02H         ;SUB-FUNC. # : GET EXTENDED ATTR TO LIST
                                  ;BX=HANDLE
                                  ;ES:DI=LIST
                                  ;CY SET IF ERROR


EXTERROR        EQU  59H          ;EXTENDED ERROR
                                  ;BX = 40 VERSION NUMBER (FOR 3.40)
                                  ;OUTPUT:
                                  ;AX=EXTENDED ERROR
                                  ;BH=ERROR CLASS
                                  ;BL=SUGGESTED ACTION
                                  ;CH=LOCUS

;               ERRORLEVEL RETURN CODES, PASSED IN "EXITFL"
EXOK            EQU  0            ;NORMAL RETURN CODE, NO PROBLEM
EXCB            EQU  1            ;CONTROL BREAK EXIT
EXVER           EQU  1            ;BAD DOS VERSION OR OTHER
                                  ; SYSLOADMSG DIFFICULTY

;               VALUES FOR THE MSG_DESC CONTROL BLOCK
NO_SUBS        EQU   0            ;NO VARIABLE FIELDS IN MESSAGE
ONE_SUBS       EQU   1            ;ONE VARIABLE FIELD IN MESSAGE
TWO_SUBS       EQU   2            ;TWO VARIABLE FIELDS IN MESSAGE
THREE_SUBS     EQU   3            ;THREE VARIABLE FIELDS IN MESSAGE
CLASS_1        EQU   1            ;CLASS 1 (DOS EXTENDED ERRORS)
CLASS_2        EQU   2            ;CLASS 2 (PARSE ERRORS)
CLASS_A        EQU   -1           ;CLASS A TYPE MESSAGE

;*****************************
; Message Retriever structures
;*****************************

msg_desc          struc
msg_num           dw    0         ;MESSAGE NUMBER (TO AX)
msg_handle        dw    STDOUT    ;HANDLE OF OUTPUT DEVICE (TO BX)
msg_sublist       dw    0         ;POINTER TO SUBLIST (TO SI)
msg_count         dw    0         ;SUBSTITUTION COUNT (TO CX)
msg_class         dw    CLASS_A shl 8 ;MESSAGE CLASS (IN HIGH BYTE, TO DH)
                                  ;LOW BYTE HAS 0 (FUNCTION "NO INPUT", TO DL)
msg_input         dw    ?         ;######EXTRA WORD - ONLY FOR MESSAGES WITH BUFFERED INPUT
                                  ;######OTHERWISE THIS WORD IS NOT VALID AS PART OF THE STRUCT
                                  ;POINTER TO INPUT BUFFER
msg_desc          ends

MAX_0             equ   0         ;MAXIMUM WIDTH OF STRING FIELD (0=NO LIMIT)
PAD_BLK           equ   " "       ;CHAR FOR PAD FIELD


sublist           struc
sub_size          db    11        ;SUBLIST SIZE (POINTER TO NEXT SUBLIST)
sub_res           db    0         ;RESERVED
                                  ;NEXT FIELD IS TO BE USED AS A DOUBLE WORD
sub_value         dw    0         ;TIME, DATE, OR PTR TO DATA ITEM
sub_value_seg     dw    0         ;SEG ID OF PTR
                                  ;(ABOVE FIELD MUST BE FILLED AT EXECUTION TIME
                                  ; IF THIS IS A .COM FILE)
sub_id            db    0         ;N OF %N
sub_flags         db    0         ;DATA TYPE FLAGS
sub_max_width     db    MAX_0     ;MAXIMUM FIELD WIDTH (0=UNLIMITED)
sub_min_width     db    0         ;MINIMUM FIELD WIDTH
sub_pad_char      db    PAD_BLK   ;CHARACTER FOR PAD FIELD
                                  ; CAN BE " ", "0" OR ",".
                                  ; "," CAUSES INSERTION OF THE ACTIVE
                                  ; THOUSANDS SEPARATOR BETWEEN EVERY 3 DIGITS.
sublist           ends

;end of COMPEQ.INC
