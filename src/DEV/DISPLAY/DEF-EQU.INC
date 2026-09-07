;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; *** DEF-EQU *** DEF-EQU *** DEF-EQU ***
;
;       EQU's, STRUC's, and OTHER
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IF1                                     ;
        %OUT .               ®DEF-EQU .INC¯
ENDIF                                   ;
ZERO    EQU     0H                      ;
ONE     EQU     1H                      ;
TWO     EQU     2H                      ;
THREE   EQU     3H                      ;
FOUR    EQU     4H                      ;
FIVE    EQU     5H                      ;
SIX     EQU     6H                      ;
SEVEN   EQU     7H                      ;
EIGHT   EQU     8H                      ;
NINE    EQU     9H                      ;
TEN     EQU    0AH                      ;
ELEVEN  EQU    0BH                      ;
TWELVE  EQU    0CH                      ;
                                        ;
FAIL    EQU     8000H                   ; fail in designate
                                        ;
NOT_CY  EQU     0FFFEH                  ;
CY      EQU     ONE                     ;
                                        ;
ID_IOCTL       EQU     5                ; MAJOR FNCT # FOR 'other' DEVICE
                                        ;
RH      EQU     ES:[DI]                 ; addressability to Request Header
                                        ;
RHC      STRUC                          ; fields common to all request types
         DB      ?                      ; length of Request Header
         DB      ?                      ; unit code (subunit)
RHC_CMD  DB      ?                      ; command code
RHC_STA  DW      ?                      ; status
         DQ      ?                      ; reserved for DOS
RHC      ENDS                           ; end of common portion
                                        ;
CMD_INPUT EQU   4                       ; RHC_CMD is INPUT request
                                        ;
                                        ; Status values for RHC_STA
STAT_DONE EQU   0001H                   ; function complete - high order byte
STAT_CMDERR EQU 8000H                   ; Error code
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;      DEVICE  Header     DS:[SI]      -- to locate the next CON header
;      NEXT device header ES:[DI]
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
HP      EQU     DS:[SI]                 ;
NHD     EQU     ES:[DI]                 ;
                                        ;
NAME_LEN EQU    8                       ;
                                        ;
DHS     STRUC                           ;
DH_NEXTO DW     ?                       ; offset of pointer to next header
DH_NEXTS DW     ?                       ; segment of pointer to next header
        DW      ?                       ; attribute
DH_STRAO DW     ?                       ; offset to strategy routine
DH_INTRO DW     ?                       ; offset to interrupt routine
DH_NAME DB      NAME_LEN DUP(0)         ; device name in this header
DHS     ENDS                            ; end of common portion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;      Request Header for INIT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RH0     STRUC                           ;
        DB      (TYPE RHC) DUP (?)      ;
                                        ;
RH0_UNIT DB     ?                       ; not used for CHAR devices
RH0_ENDO DW     ?                       ; offset  of ending address
RH0_ENDS DW     ?                       ; segment of ending address
RH0_BPBA DD     ?                       ; POINTER TO BPB FOR CHAR DEVICES
         db     ?                       ;
RH0     ENDS                            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;      Request Header for IOCTL
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RH3     STRUC                           ;
        DB      (TYPE RHC) DUP (?)      ; common portion
                                        ;
                                        ;
        DB      ?                       ; media descriptor
RH3_DTAO DW     ?                       ; offset  of transfer address
RH3_DTAS DW     ?                       ; segment of transfer address
RH3_CNT DW      ?                       ; byte count
RH3     ENDS                            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       IOCTL header format
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RH_IOCTL STRUC                          ;
STATIC_RH       DB 13 DUP(?)            ; STANDARD STATIC REQUEST HEADER
MAJOR_F         DB      ?               ; MAJOR FUNCTION CALL (SEE DOS 3.30)
MINOR_F         DB      ?               ; MINOR FUNCTION CALL (SEE DOS 3.30)
CONTENT_SI      DW      ?               ; CONTENTS OF SI
CONTENT_DI      DW      ?               ; CONTENTS OF DI
REQUEST_PACKET  DD      ?               ; POINTER TO GENERIC IOCTL REQ. PACKET
RH_IOCTL ENDS                           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       DESIGNATE BUFFER FORMAT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DESG_BUFFER     STRUC                   ;
DESG_CARTRIDGE  DW      ?               ; 0=NO CARTRIDGE, 1=CARTRIDGE
DESG_LENGTH     DW      ?               ; LENGTH OF REMAINING HEADER
DESG_N          DW      ?               ; NUMBER OF CP's DESIGNATED
DESG_CP         DW      ?               ; FIRST CP DESIGNATED
DESG_BUFFER     ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       INVOKE BUFFER FORMAT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INVK_BUFFER     STRUC                   ;
INVK_LENGTH     DW      ?               ; LENGTH OF REMAINING HEADER
INVK_CP         DW      ?               ; CP TO INVOKE
INVK_BUFFER     ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       QUERY LIST BUFFER FORMAT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
QLST_BUFFER     STRUC                   ;
QLST_LENGTH     DW      ?               ; LENGTH OF REMAINING HEADER
QLST_N_HDWR     DW      ?               ; NUMBER OF HARDWARE CP's
QLST_HDWR_CP    DW      ?               ; FIRST HDWR CODE PAGE
QLST_N_DESG     DW      ?               ; NUMBER OF DESIGNATED CP's
QLST_DESG_CP    DW      ?               ; DESINATED CODE PAGES
                                        ; ...there is more data to be
                                        ;    filled in by the DRIVER
QLST_BUFFER     ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       PARSER STRUC STATEMENTS
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PARSE_TABLE1    STRUC                   ; [[[ TABLE 1 ]]]
NUM_DEVICES     DW      ?               ; NUMBER OF DEVICES TO SUPPORT
DEVICE1_OFFSET  DW      ?               ; (hopefully) CON!!!
PARSE_TABLE1    ENDS                    ;
                                        ;
PARSE_TABLE2    STRUC                   ; [[[ TABLE 2 ]]]
NUM_ITEMS       DW      ?               ; NUMBER OF ITEMS CREATED BY THE
OFFSET_LIST     DW      ?               ; THE 1ST OFFSET OF [ TABLE 2 ]
PARSE_TABLE2    ENDS                    ; PARSER!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       CODE PAGE POINTER STRUCTURE
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CP_PNTER_STRUC  STRUC                   ;
HDWR_CP_STRUC   DW      ?               ;
DESG_CP_STRUC   DW      ?               ;
FONT_CP_STRUC   DW      ?               ;
WRITE_DATA_STRUC DW     ?               ;
FONT_DATA_STRUC DW      ?               ;
CP_PNTER_STRUC  ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; CON data structure  CS:[BX]
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BUF     EQU     CS:[BX]                 ;
                                        ; STATES
BUF_DATA STRUC                          ;
DEV_HDRO DW     -1                      ; device driver header offset
DEV_HDRS DW     -1                      ;
CON_STRAO DW    -1                      ; dos CON strategy offset
CON_STRAS DW    -1                      ;
CON_INTRO DW    -1                      ; dos CON strategy offset
CON_INTRS DW    -1                      ;
RH_PTRO DW      -1                      ; request header offset
RH_PTRS DW      -1                      ; segment
STATE   DW       ?                      ;
STATUS  DW       ?                      ;
BUF_DATA ENDS                           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;       General  Constants
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INT_2F_LOW EQU  (4*2FH)                 ; INTERRUPT 2FH CON/KEYB COMMUNICATION
INT_2F_HI EQU    (4*2FH)+2              ;
INT_43_LOW EQU  (4*43H)                 ; INTERRUPT 43H 0-255 CHARACTER VECTOR
INT_43_HI EQU    (4*43H)+2              ;
INT_44_LOW EQU  (4*44H)                 ; INTERRUPT 44H 0-255 CHARACTER VECTOR
INT_44_HI EQU    (4*44H)+2              ;
INT_1F_LOW EQU  (4*1FH)                 ; INTERRUPT 1FH EXTENDED CHARACTER SUPPORT
INT_1F_HI EQU    (4*1FH)+2              ;
INT_10_LOW EQU  (4*10H)                 ; INTERRUPT 10H fix FOR PALACE
INT_10_HI EQU    (4*10H)+2              ;
GET_MODE      EQU    0FH                ; WGR
ON            EQU    1                  ; WGR
OFF           EQU    0                  ; WGR
RECALC_ON     EQU    0010H              ; WGR
VIDEO_CTRL    EQU    487H               ; WGR
ANSI_BUF_SIZE EQU    14                 ; WGR
DEFAULT_LEN   EQU    25                 ; WGR
NUMBER        EQU    1                  ; WGR
STRING        EQU    3                  ; WGR
COMPLEX       EQU    4                  ; WGR
RC_EOL        EQU    -1                 ; WGR
RC_NO_ERROR   EQU    0                  ; WGR
FUNC_CALL     EQU    1BH                ; WGR
VGA_FOUND     EQU    00000001B          ; WGR
EGA_FOUND     EQU    00000001B          ; WGR
LCD_FOUND     EQU    00000010B          ; WGR
CGA_FOUND     EQU    00000100B          ; WGR
MONO_FOUND    EQU    00001000B          ; WGR
ALT_SELECT    EQU    12H                ; WGR
EGA_INFO_CALL EQU    10H                ; WGR
GET_SYS_ID    EQU    0C0H               ; WGR
GET_STATUS    EQU    43H                ; WGR
LCD_MODEL     EQU    0F9H               ; WGR
COLOR_ADDRESS EQU    0B800H             ; WGR
MONO_ADDRESS  EQU    0B000H             ; WGR
ERROR_1       EQU    2                  ; WGR
ERROR_2       EQU    12                 ; WGR
ERROR_3       EQU    8                  ; WGR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; *** INT 2Fh used
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ANSI_2F       EQU    1Ah                ; WGR Muliflex number for ANSI
;Catagory code
IOCTL_2F      EQU     1h                ;
DA_INFO_2F    EQU     2h                ;J.K. Information passing to ANSI.
;Subfunction code for IOCTL_2F
GET_SUBFUNC   EQU    7FH                ; WGR Same structure as GET_IOCTL(ANSI)

;Info Struture for DA_INFO_2F. (DS:DX point to this packet)
;J.K. Note: For DOS 4.00, DA_INFO_PACKET is used to signal ANSI.SYS that
;DISPLAY.SYS is calling/finishing INT 10h SET MODE call.  ANSI.SYS needs this
;infomration since it also hooks INT 10h vector.
;For this DA_SETMODE_FLAG purpose, DA_INFO_LEVEL and DA_INFO_DIRECTION should always be
;set to 0.  This can be extended for another information passing scheme between
;DISPLAY.SYS and ANSI.SYS in the future version.
;For DA_SETMODE_FLAG, DISPLAY.SYS should be extremely careful that when it calls
;with DA_SETMODE_FLAG =1, then it should calls with DA_SETMODE_FLAG=0
;when it finished INT 10h function call. Otherwise, the system goes .....
DA_INFO_PACKET   struc
DA_INFO_LEVEL       db      0           ; 0 for DA_SETMODE_FLAG,  1 for DA_OPTION_L_STATE query (for OS2 compat. box).
DA_SETMODE_FLAG     db      0           ; 1: DISPLAY.SYS is calling INT 10h call, SET MODE. 0= finished.
DA_OPTION_L_STATE   db      0           ; on return from ANSI, 1 = ANSI /L option active, 0 = inactive.
DA_INFO_PACKET   ends

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; *** DEF-EQU *** DEF-EQU *** DEF-EQU ***
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Information Block Structure
;    (for functionality call)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INFO_BLOCK      STRUC                   ; info block for functionality call
STATIC_ADDRESS  DD   ?                  ; address of static functionality table
                DB   33 DUP(?)          ; don't care
ACTIVE_DISPLAY  DB   ?                  ; active display code
ALT_DISPLAY     DB   ?                  ; alternate display code
                DB   3  DUP(?)          ; don't care
CURRENT_SCANS   DB   ?                  ; current number of scan lines
                DB   2  DUP(?)          ; don't care
MISC_INFO       DB   ?                  ; miscellaneous state information
                DB   18 DUP(?)          ; don't care
INFO_BLOCK      ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Structure of System ID call return block
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SYS_ID          STRUC                   ; format of return system config data
                DW   ?                  ; don't care
MODEL_BYTE      DB   ?                  ; model byte
SYS_ID          ENDS                    ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
