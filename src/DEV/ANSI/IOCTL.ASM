PAGE    ,132
TITLE   ANSI Generic IOCTL Code

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: IOCTL.ASM
;
;  DESCRIPTIVE NAME: PERFORM THE GENERIC IOCTL CALL IN ANSI.SYS
;
;  FUNCTION: THE GENERIC DEVICE IOCTL IS USED TO SET AND GET THE
;            MODE OF THE DISPLAY DEVICE ACCORDING TO PARAMETERS PASSED
;            IN A BUFFER. ADDITIONALLY, THE CALL CAN TOGGLE THE
;            USE OF THE INTENSITY BIT, AND CAN LOAD THE 8X8 CHARACTER
;            SET, EFFECTIVELY GIVING MORE LINES PER SCREEN. THE
;            AVAILABILITY OF THIS FUNCTION VARIES STRONGLY WITH HARDWARE
;            ATTACHED.
;
;  ENTRY POINT: GENERIC_IOCTL
;
;  INPUT: LOCATION OF REQUEST PACKET STORED DURING STRATEGY CALL.
;
;  AT EXIT:
;     NORMAL: CARRY CLEAR - DEVICE CHARACTERISTICS SET
;
;     ERROR: CARRY SET - ERROR CODE IN AX.
;            AX = 1  - INVALID FUNCTION. EXTENDED ERROR = 20
;            AX = 10 - UNSUPPORTED FUNCTION ON CURRENT HARDWARE.
;                      EXTENDED ERROR = 29
;            AX = 12 - DISPLAY.SYS DOES NOT HAVE 8X8 RAM CHARACTER SET.
;                      EXTENDED ERROR = 31
;
;  INTERNAL REFERENCES:
;
;     ROUTINES: GET_IOCTL - PERFORMS THE GET DEVICE CHARACTERISTICS
;               SET_IOCTL - PERFORMS THE SET DEVICE CHARACTERISTICS
;               TEST_LENGTH - TESTS FOR VALIDITY OF A SCREEN SIZE VALUE
;               CTL_FLAG - READS THE CURRENT USE FOR THE INT/BLINK BIT
;               SET_CTL_FLAG - SETS THE USE FOR THE INT/BLINK BIT
;               GET_SEARCH - SEARCHES THE INTERNAL VIDEO TABLE FOR THE
;                            CURRENT MODE MATCH
;               SET_SEARCH - SEARCHES THE INTERNAL VIDEO TABEL FOR THE
;                            CURRENT MODE MATCH
;               SET_CURSOR_EMUL - SETS THE BIT THAT CONTROLS CURSOR EMULATION
;               INT10_COM - INTERRUPT 10H HANDLER TO KEEP CURRENT SCREEN SIZE
;               INT2F_COM - INTERRUPT 2FH INTERFACE TO GENERIC IOCTL
;               MAP_DOWN - PERFORMS CURSOR TYPE MAPPING FOR EGA WITH MONOCHROME
;               SET_VIDEO_MODE - SETS THE VIDEO MODE
;               ROM_LOAD_8X8 - LOADS THE 8X8 CHARACTER SET.
;               PROCESS_NORMAL - DOES THE SET PROCESS FOR ADAPTERS OTHER THAN
;                                THE VGA
;               PROCESS_VGA - DOES THE SET PROCESS FOR THE VGA ADAPTER
;               CHECK_FOR_DISPLAY - CHECKS FOR DISPLAY.SYS SUPPORT
;
;     DATA AREAS: SCAN_LINE_TABLE - HOLDS SCAN LINE INFORMATION FOR PS/2
;                 FUNC_INFO - BUFFER FOR PS/2 FUNCTIONALITY CALL.
;
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: INT 10H SERVICES
;
;     DATA AREAS: VIDEO_MODE_TABLE - INTERNAL TABLE FOR CHARACTERISTICS TO MODE
;                                    MATCH-UPS
;
;  NOTES:
;
;      Label: "DOS ANSI.SYS Device Driver"
;             "Version 4.00 (C) Copyright 1988 Microsoft"
;             "Licensed Material - Program Property of Microsoft"
;
;****************** END OF SPECIFICATIONS ****************************
;******************************************************************************

INCLUDE     ANSI.INC
.XLIST
INCLUDE     STRUC.INC
.LIST
PUBLIC      GENERIC_IOCTL
PUBLIC      FUNC_INFO
PUBLIC      MAX_SCANS
PUBLIC      INT10_COM
PUBLIC      ROM_INT10
PUBLIC      INT2F_COM
PUBLIC      ROM_INT2F
PUBLIC      ABORT
PUBLIC      REQ_TXT_LENGTH
PUBLIC      GRAPHICS_FLAG
public      Display_Loaded_Before_Me
CODE        SEGMENT  PUBLIC  BYTE
            ASSUME CS:CODE,DS:CODE
EXTRN       PTRSAV:DWORD
EXTRN       NO_OPERATION:NEAR
EXTRN       ERR1:NEAR
EXTRN       VIDEO_MODE_TABLE:BYTE
extrn       MAX_VIDEO_TAB_NUM:ABS
EXTRN       HDWR_FLAG:WORD
EXTRN       SCAN_LINES:BYTE
extrn       Switch_L:Byte                       ;AN010;Defined in ANSI.ASM
SCAN_LINE_TABLE  LABEL    BYTE
   SCAN_LINE_STR <200,000000001B,0>            ; 200 scan lines
   SCAN_LINE_STR <344,000000010B,1>            ; 350 scan lines
   SCAN_LINE_STR <400,000000100B,2>            ; 400 scan lines
SCANS_AVAILABLE  EQU  ($ - SCAN_LINE_TABLE)/TYPE SCAN_LINE_STR
;This is used when ANSI calls Get_IOCTL, Set_IOCTL by itself.
In_Generic_IOCTL_flag   db      0
I_AM_IN_NOW          EQU     00000001b
SET_MODE_BY_DISPLAY  EQU     00000010b                          ;AN004;Display.sys calls Set mode INT 10h.
CALLED_BY_INT10COM   EQU     00000100b                          ;AN009;To prevent from calling set mode int 10h again.

INT10_V_Mode    db      0ffh                                    ;AN006;Used by INT10_COM

My_IOCTL_Req_Packet REQ_PCKT <0,0,0Eh,0,?,0,?,?,?,?,?>
FUNC_INFO        INFO_BLOCK <>                 ; data block for functionality call
ROM_INT10        DW    ?                       ; segment and offset of original..
                 DW    ?                       ; interrupt 10h vector.
ROM_INT2F        DW    ?                       ; segment and offset of original..
                 DW    ?                       ; interrupt 2Fh vector.
INTENSITY_FLAG   DW    OFF                     ; intensity flag initially off
REQ_TXT_LENGTH   DW    DEFAULT_LENGTH          ; requested text screen length
SCAN_DESIRED     DB    0                       ; scan lines desired
MAX_SCANS        DB    0                       ; maximum scan line setting
GRAPHICS_FLAG    DB    TEXT_MODE               ; flag for graphics mode
ERROR_FLAG       DB    OFF                     ; flag for error conditions
Display_Loaded_Before_Me db     0              ;AN008;flag
ANSI_SetMode_Call_Flag   db     0              ;AN008;Ansi is issuing INT10,AH=0.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: GENERIC_IOCTL
;
; FUNCTION:
; TO GET OR SET DEVICE CHARACTERISTICS ACCORDING TO THE BUFFER PASSED
; IN THE REQUEST PACKET.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - DEVICE CHARACTERISTICS SET
;
;    ERROR: CARRY SET - ERROR CODE IN AL. (SEE MODULE DESCRIPTION ABOVE).
;
; NOTE: THIS PROC IS PERFORMED AS A JMP AS WITH THE OLD ANSI CALLS.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

GENERIC_IOCTL:                                 ;
        LES     BX,[PTRSAV]                    ; establish addressability to request header
        .SELECT                                ; check for get or set subfunction
          .WHEN <ES:[BX].MIN_FUNC EQ GET_FUNC> ; is this the get subfunction?
            LES     DI,ES:[BX].REQ_PCKT_PTR    ; point to request packet
            CALL    GET_IOCTL                  ; yes...execute routine
          .WHEN <ES:[BX].MIN_FUNC EQ SET_FUNC> ; is this the set subfunction?
            LES     DI,ES:[BX].REQ_PCKT_PTR    ; point to request packet
            CALL    SET_IOCTL                  ; yes....execute routine
          .OTHERWISE                           ; not for us....so..
            JMP     NO_OPERATION               ; call lower CON device
        .ENDSELECT                             ;
        .IF C                                  ; error?....
          OR     AX,CMD_ERROR                  ; yes...set error bit in status
        .ENDIF                                 ;
        OR     AX,DONE                         ; add done bit to status
        JMP    ERR1                            ; return with status in AX
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: GET_IOCTL
;
; FUNCTION:
; THIS PROCEDURE RETURNS DEVICE CHARACTERISTICS.
;
; AT ENTRY: ES:DI POINTS TO REQUEST BUFFER
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - REQUEST BUFFER CONTAINS DEVICE CHARACTERISTICS
;
;    ERROR: CARRY SET - ERROR CONDITION IN AX
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

GET_IOCTL PROC    NEAR
     .IF <ES:[DI].INFO_LEVEL NE 0> OR            ; check for valid info level
     .IF <ES:[DI].DATA_LENGTH LT <TYPE MODE_TABLE+1>> ; and buffer size.
       MOV    AX,INVALID_FUNC                    ; not valid...unsupported
       STC                                       ; function..set error flag and
     .ELSE                                       ;
       MOV     ES:[DI].INFO_LEVEL+1,0            ; set reserved byte to 0.
       MOV     AH,REQ_VID_MODE                   ; request current video mode
       INT     10H                               ;
       AND     AL,VIDEO_MASK                     ;
       LEA     SI,VIDEO_MODE_TABLE               ; point to resident video table
       CALL    GET_SEARCH                        ; perform search
       .IF C                                     ; found?
         MOV     AX,NOT_SUPPORTED                ; no....load unsupported function
       .ELSE                                     ;
         push    di                              ;AN001;AN003;Save Request Buffer pointer
         MOV     WORD PTR ES:[DI].DATA_LENGTH,(TYPE MODE_TABLE)+1 ;length of data is struc size
         INC     SI                              ; skip mode value
         ADD     DI,RP_FLAGS                     ; point to flag word
         .IF <HDWR_FLAG GE MCGA_ACTIVE>          ; if we have an EGA or better
           CALL    CTL_FLAG                      ; then ..process control flag
         .ELSE                                   ; else...
           MOV     WORD PTR ES:[DI],OFF          ; we always have blink.
         .ENDIF                                  ;
         INC     DI                              ; point to next field..
         INC     DI                              ; ..(display mode)
         MOV     CX,(TYPE MODE_TABLE)-1          ; load count
         REP     MOVSB                           ; transfer data from video table to request packet
         SUB     SI,TYPE MODE_TABLE              ; point back to start of mode data
         .IF <[SI].D_MODE EQ TEXT_MODE> AND      ; if we are in text mode and..
         .IF <[SI].SCR_ROWS NE DEFAULT_LENGTH>   ; length <> 25 then we have an EGA or VGA
           DEC    DI                             ; point back to length entry in req packet
           DEC    DI                             ;
           PUSH   DS                             ;
           MOV    AX,ROM_BIOS                    ; load ROM BIOS data area segment
           MOV    DS,AX                          ;
           MOV    AL,BYTE PTR DS:[NUM_ROWS]      ; load current number of rows
           CBW                                   ;
           INC    AX                             ; add 1 to row count
           MOV    WORD PTR ES:[DI],AX            ; and copy to request packet
           POP    DS                             ;
         .ENDIF                                  ;
         XOR    AX,AX                            ; no errors
         CLC                                     ; clear error flag
         pop    di                               ;AN001; AN003;Restore Request Buffer pointer
       .ENDIF                                    ;
     .ENDIF                                      ;
     RET                                         ; return to calling module
GET_IOCTL ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: SET_IOCTL
;
; FUNCTION:
; THIS PROCEDURE SETS THE VIDEO MODE AND CHARACTER SET ACCORDING
; TO THE CHARACTERSTICS PROVIDED.
;
; AT ENTRY:
;    ES:[DI] POINTS TO REQUEST BUFFER
;
; AT EXIT:
;    NORMAL: CLEAR CARRY - VIDEO MODE SET
;
;    ERROR: CARRY SET - ERROR CONDITION IN AX
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SET_IOCTL PROC  NEAR
     or cs:In_Generic_IOCTL_Flag, I_AM_IN_NOW  ;AN004; Signal GENERIC_IOCTL request being processed
     MOV    ERROR_FLAG,OFF                     ; clear any errors
    .IF <ES:[DI].INFO_LEVEL NE 0> OR           ; check for valid info level
    .IF <ES:[DI].DATA_LENGTH NE <TYPE MODE_TABLE+1>> OR ; and buffer size.
     MOV    AX,ES:[DI].RP_FLAGS                ; test for invalid flags.
    .IF <BIT AX AND INVALID_FLAGS> OR          ;
    .IF <BIT ES:[DI].RP_FLAGS AND ON> AND      ; if intensity is requested and..
    .IF <HDWR_FLAG LT MCGA_ACTIVE>             ; hardware does not support it then..
        MOV    AX,INVALID_FUNC                 ; not valid...unsupported..
        MOV    ERROR_FLAG,ON                   ; function..set error and..
    .ELSE                                      ;
        CALL    SET_SEARCH                     ; search table for match
       .IF C                                   ; if match not found then..
          MOV    AX,NOT_SUPPORTED              ; not supported....
          MOV    ERROR_FLAG,ON                 ;
       .ELSE                                   ;
         .IF <[SI].D_MODE EQ TEXT_MODE>        ; is a text mode being requested?
            PUSH   REQ_TXT_LENGTH              ; save old value in case of error
            MOV    AX,ES:[DI].RP_ROWS          ; save new requested value.
            MOV    REQ_TXT_LENGTH,AX           ;
;           .IF <[SI].SCR_ROWS NE UNOCCUPIED>   ; yes...check for VGA support..
;             CALL   PROCESS_NORMAL             ; no..process other adapters..
;           .ELSE                               ; VGA support available..
;             CALL   PROCESS_VGA                ; process the VGA support code.
;           .ENDIF                              ;
           .IF <[SI].SCR_ROWS E UNOCCUPIED> OR
           .IF <BIT Hdwr_Flag AND VGA_ACTIVE>
               call  process_VGA
           .ELSE
               call  process_Normal
           .ENDIF
           .IF <ERROR_FLAG EQ OFF>             ; if we had no errors then..
              POP    AX                        ; discard saved text length
              call   DO_ROWS
             .IF <HDWR_FLAG GE E5151_ACTIVE>   ; does hardware support gt 25 lines?
                CALL   SET_CURSOR_EMUL         ; yes..ensure cursor emulation is..
             .ENDIF                            ; set accordingly.
           .ELSE                               ;
              POP    REQ_TXT_LENGTH            ; error...so restore old value.
           .ENDIF                              ;
         .ELSE                                 ; request is for graphics mode
            CALL   SET_VIDEO_MODE              ; so set video mode.
         .ENDIF                                ;
         .IF <ERROR_FLAG EQ OFF> AND           ; no errors? then..
         .IF <HDWR_FLAG GE MCGA_ACTIVE> AND    ; for the EGA and better ....
         .IF <[SI].V_MODE EQ TEXT_MODE>        ; and in text mode do...
             CALL   SET_CTL_FLAG               ; set intensity bit to control value
         .ENDIF                                ;
       .ENDIF                                  ;
    .ENDIF                                     ;
     and cs:In_Generic_IOCTL_Flag, NOT I_AM_IN_NOW  ;AN004; Turn the flag off
    .IF <ERROR_FLAG EQ OFF>                    ; no errors?
       XOR    AX,AX                            ; clear error register
       CLC                                     ; clear error flag
    .ELSE                                      ;
       STC                                     ;
    .ENDIF                                     ; yes...set error flag
     RET                                       ;
SET_IOCTL ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PROCESS_NORMAL
;
; FUNCTION:
; THIS PROCEDURE PROCESSES THE SET IOCTL FOR ADAPTERS OTHER THAN
; THE VGA.
;
; AT ENTRY: AX - SCREEN LENGTH DESIRED
;           DS:SI - POINTS TO MODE RECORD IN VIDEO TABLE.
;
; AT EXIT:
;    NORMAL: MODE SET
;
;    ERROR: ERROR_FLAG IS ON. ERROR CODE IN AX.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PROCESS_NORMAL PROC   NEAR
             .IF <AX NE DEFAULT_LENGTH>  AND   ; no..see if length requested..
             .IF <AX NE [SI].SCR_ROWS>         ; is valid....
               MOV    AX,NOT_SUPPORTED         ; not valid....so
               MOV    ERROR_FLAG,ON            ; set error flag and..
             .ELSE                             ; length is valid so..
               CALL   CHECK_FOR_DISPLAY        ; see if we need and have DISPLAY.SYS..
               .IF NC                          ; support...if no problems then..
                 .IF <HDWR_FLAG GE E5151_ACTIVE>; yes...check for cursor emulation
                   CALL    SET_CURSOR_EMUL     ;
                 .ENDIF                        ;
                 CALL    SET_VIDEO_MODE        ; ..and set the mode.
               .ELSE                           ; no..
                 MOV     AX,NOT_AVAILABLE      ; font not available..
                 MOV     ERROR_FLAG,ON         ;
               .ENDIF                          ;
             .ENDIF                            ;
             RET
PROCESS_NORMAL ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PROCESS_VGA
;
; FUNCTION:
; THIS PROCEDURE PROCESSES THE SET IOCTL FOR THE VGA ADAPTER
;
; AT ENTRY: AX - SCREEN LENGTH DESIRED
;           DS:SI - POINTS TO MODE RECORD IN VIDEO TABLE.
;
; AT EXIT:
;    NORMAL: MODE SET
;
;    ERROR: ERROR_FLAG IS ON. ERROR CODE IN AX.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PROCESS_VGA  PROC    NEAR
             CALL    TEST_LENGTH               ; check to see if screen length
             .IF C                             ; is applicable....
               MOV    AX,NOT_SUPPORTED         ; no..so set error condition
               MOV    ERROR_FLAG,ON            ;
             .ELSE                             ;
               CALL   CHECK_FOR_DISPLAY        ; see if we need and have DISPLAY.SYS..
               .IF NC                          ; support.....yes so..
                 .IF <REQ_TXT_LENGTH EQ DEFAULT_LENGTH> ; 25 lines requested?
                   MOV    AL,MAX_SCANS         ; desired scan setting should be..
                   MOV    SCAN_DESIRED,AL      ; the maximum.
                 .ENDIF                        ;
                 MOV    AH,ALT_SELECT          ; set the appropriate number..
                 MOV    BL,SELECT_SCAN         ; of scan lines..
                 MOV    AL,SCAN_DESIRED        ;
                 INT    10H                    ;
                 CALL   SET_VIDEO_MODE         ; and set the mode.
               .ELSE                           ; DISPLAY.SYS does not have the font.
                 MOV    AX,NOT_AVAILABLE       ; so...load error code..
                 MOV    ERROR_FLAG,ON          ;
               .ENDIF                          ;
             .ENDIF                            ;
             RET
PROCESS_VGA  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Procedure name: DO_ROWS
; Function:
;  Only called for TEXT_MODE.
;  If (REQ_TXT_LENGTH <> DEFAULT_LENGTH) &
;     (DISPLAY.SYS not loaded or CODEPAGE not active)
;  then
;     LOAD ROM 8X8 charater.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DO_ROWS         proc    near
       .IF <REQ_TXT_LENGTH NE DEFAULT_LENGTH>
           push ds
           push es
           push di
           push si
           mov  ax, DISPLAY_CHECK
           int  2fh
          .IF <al NE INSTALLED> OR
           mov  ax, CHECK_ACTIVE
           int  2fh
          .IF  C
               call     ROM_LOAD_8X8
          .ENDIF
           pop  si
           pop  di
           pop  es
           pop  ds
       .ENDIF
        ret
DO_ROWS         endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: TEST_LENGTH
;
; FUNCTION:
; THIS PROCEDURE ENSURES THAT THE SCREEN LENGTH REQUESTED CAN BE
; OBTAINED USING THE AVAILABLE SCAN LINE SETTINGS.  (VGA ONLY!)
;
; AT ENTRY:
;
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - SCAN_DESIRED CONTAINS SETTING REQUIRED
;
;    ERROR: CARRY SET
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

TEST_LENGTH PROC   NEAR
            push   bp
            MOV    AX,REQ_TXT_LENGTH         ; load AX with length requested
            MOV    BP,EIGHT                  ;
            MUL    BP                        ; mulitply by 8 to get scan lines
            LEA    BX,SCAN_LINE_TABLE        ; load BX with scan line table start
            MOV    CX,SCANS_AVAILABLE        ; total number of scan lines settings
            MOV    BP,NOT_FOUND              ; set flag
            .WHILE <BP EQ NOT_FOUND> AND     ; while not found and still valid..
            .WHILE <CX NE 0>                 ; settings left..do..
              .IF <AX EQ [BX].NUM_LINES>     ; pointing at the right setting..
                MOV    DL,[BX].REP_1BH       ;
                .IF <BIT SCAN_LINES AND DL>  ; does the hardware have it?..
                  MOV    BP,FOUND            ; yes....found!!
                .ELSE                        ;
                  XOR    CX,CX               ; no...set CX to exit loop.
                .ENDIF                       ;
              .ELSE                          ;
                ADD    BX,TYPE SCAN_LINE_STR ; not this setting..point to next
                DEC    CX                    ; record and decrement count
              .ENDIF                         ;
            .ENDWHILE                        ;
            .IF <BP EQ NOT_FOUND>            ; was it found and available?
              STC                            ; no....set error flag
            .ELSE                            ; yes so.....
              MOV    CL,[BX].REP_12H         ; store value to set it.
              MOV    SCAN_DESIRED,CL         ;
              CLC                            ; clear error flag
            .ENDIF                           ;
            pop  bp
            RET                              ; return to calling module
TEST_LENGTH ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: CTL_FLAG
;
; FUNCTION:
; THIS PROCEDURE RETURNS THE CURRENT USE FOR THE INTENSITY/BLINKING
; BIT.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL:
;      VGA,MCGA: VALUE RETURNED FROM FUNCTIONALITY CALL
;      EGA: VALUE LAST SET THROUGH IOCTL. DEFAULT IS BLINKING.
;      CGA,MONO: BLINKING
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CTL_FLAG  PROC    NEAR
          .IF <BIT HDWR_FLAG AND VGA_ACTIVE>      ; VGA supported?
            PUSH    ES                            ; yes...prepare for
            PUSH    DI                            ; functionality call
            PUSH    DS                            ;
            POP     ES                            ;
            LEA     DI,FUNC_INFO                  ; point to data block
            MOV     AH,FUNC_CALL                  ; load function number
            XOR     BX,BX                         ; implementation type 0
            INT     10H                           ;
            MOV     AL,ES:[DI].MISC_INFO          ; load misc info byte
            .IF <BIT AL AND INT_BIT>              ; is blink bit set?
              AND    INTENSITY_FLAG,NOT ON        ; yes....turn off intensity flag
            .ELSE                                 ; no...
              OR     INTENSITY_FLAG,ON            ; ensure that intensity is set
            .ENDIF                                ;
            POP     DI                            ; restore registers
            POP     ES                            ;
          .ENDIF                                  ;
          MOV     AX,INTENSITY_FLAG               ; write the control flag..
          MOV     ES:[DI],AX                      ; to the request packet
          RET                                     ;
CTL_FLAG  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: SET_CTL_FLAG
;
; FUNCTION:
; THIS PROCEDURE SET THE TOGGLE/INTENSITY BIT AS SPECIFIED IN THE
; CONTROL FLAG IOCTL SET SUBFUNCTION. THIS ROUTINE IS ONLY CALLED FOR
; AN EGA, MCGA, OR VGA.
;
; AT ENTRY: ES:DI POINTS TO REQUEST BUFFER
;
; AT EXIT:
;    NORMAL: INTENSITY_FLAG SET APPROPRIATELY AND SYSTEM BIT SET
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SET_CTL_FLAG PROC   NEAR
             .IF <BIT ES:[DI].RP_FLAGS AND ON>
               OR     INTENSITY_FLAG,ON
               MOV    BL,SET_INTENSIFY
             .ELSE
               AND    INTENSITY_FLAG,NOT ON
               MOV    BL,SET_BLINK
             .ENDIF
             MOV    AX,BLINK_TOGGLE
             INT    10H
             RET
SET_CTL_FLAG ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: SET_SEARCH
;
; FUNCTION:
; THIS PROCEDURE SEARCHES THE RESIDENT VIDEO TABLE IN ATTEMPT TO
; FIND A MODE THAT MATHCES THE CHARACTERISTICS REQUESTED.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - SI POINTS TO APPLICABLE RECORD
;
;    ERROR: CARRY SET
;
;AN006; When INT10_V_Mode <> 0FFH, then assumes that the user
;       issuing INT10h, Set mode function call.  Unlike Generic IOCTL
;       set mode call, the user already has taken care of the video mode.
;       So, we also find the matching V_MODE.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SET_SEARCH PROC   NEAR
            push   bp
            LEA    SI,VIDEO_MODE_TABLE              ; point to video table
            MOV    BP,NOT_FOUND                     ; set flag indicating not found
            MOV    CX,MAX_VIDEO_TAB_NUM             ; load counter, # of tables
           .WHILE <BP EQ NOT_FOUND> AND             ; while not found and we still..
           .WHILE <[SI].V_MODE NE UNOCCUPIED> AND   ; have valid entries..
           .WHILE <CX NE 0>                         ; do...
             mov al, cs:INT10_V_Mode
            .if <AL NE 0FFh> AND                    ;AN006;if issued by INT10h Set Mode call,
            .if <[SI].V_MODE NE AL>                 ;AN006; and V_MODE <> AL
               add si, type MODE_TABLE              ;AN006; then, this is not the correct entry.
               dec cx                               ;AN006;Let's find the next entry.
            .else                                   ;AN006; Else, continue...
               MOV    AL,ES:[DI].RP_MODE             ; load register for compare.
              .IF <[SI].D_MODE EQ AL>                ; match?......
                 MOV    AX,ES:[DI].RP_COLORS         ; yes...prepare next field
                .IF <[SI].COLORS EQ AX>              ; match?...
                  .IF <ES:[DI].RESERVED2 EQ 0>       ; yes...ensure reserved byte is 0
                    .IF <ES:[DI].RP_MODE EQ GRAPHICS_MODE> ; for graphics mode..check the following;AN000;.
                       MOV    AX,ES:[DI].RP_WIDTH    ; screen width.
                      .IF <[SI].SCR_WIDTH EQ AX>     ;
                         MOV    AX,ES:[DI].RP_LENGTH ; screen length
                        .IF <[SI].SCR_LENGTH EQ AX>  ; (ignore #rows and #columns
                           MOV    BP,FOUND           ; found...set flag
                        .ENDIF                       ;
                      .ENDIF                         ;
                    .ELSE                            ; and for text check the columns..
                       MOV    AX,ES:[DI].RP_COLS     ; the rows are matched in the main routine.
                      .IF <[SI].SCR_COLS EQ AX>      ;
                         MOV    BP,FOUND             ; found...set flag
                      .ENDIF                         ;
                    .ENDIF                           ;
                  .ENDIF                             ;
                .ENDIF                               ;
              .ENDIF                                 ;
               ADD    SI,TYPE MODE_TABLE             ; point to next record and..
               DEC    CX                             ; decrement count
            .endif
           .ENDWHILE                                 ;
           .IF <BP EQ NOT_FOUND>                     ; if we never found it then..
              STC                                    ; set error flag and..
           .ELSE                                     ;
              SUB    SI,TYPE MODE_TABLE              ; position us at the appropriate record
              CLC                                    ; clear error flag
           .ENDIF                                    ;
            mov cs:INT10_V_Mode, 0FFh                ;AN006; Done. Reset the value
            pop bp
            RET                                      ; return to calling module
SET_SEARCH  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: GET_SEARCH
;
; FUNCTION:
; THIS PROCEDURE SEARCHES THE VIDEO TABLE LOOKING FOR A MATCHING
; VIDEO MODE.
;
; AT ENTRY: DS:SI POINTS TO VIDEO TABLE
;           AL CONTAINS THE MODE REQUESTED
;
; AT EXIT:
;    NORMAL: CARRY CLEAR, DS:SI POINTS TO MATCHING RECORD
;
;    ERROR: CARRY SET
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

GET_SEARCH  PROC   NEAR
            MOV     CX,MAX_VIDEO_TAB_NUM            ; # of total tables
            .WHILE <[SI].V_MODE NE AL> AND          ; while we are not pointing to
            .WHILE <[SI].V_MODE NE UNOCCUPIED> AND  ; the right mode and we are still
            .WHILE <CX NE 0>                        ; looking at valid data..do..
              ADD     SI,TYPE MODE_TABLE            ; point to the next mode
              DEC     CX                            ; decrement counter
            .ENDWHILE                               ;
            .IF <CX EQ 0> OR                        ; did we find the mode?
            .IF <[SI].V_MODE EQ UNOCCUPIED>         ;
              STC                                   ; no ...so set error flag
            .ELSE                                   ;
              CLC                                   ; yes...clear error flag
            .ENDIF                                  ;
            RET                                     ;
GET_SEARCH  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: SET_CURSOR_EMUL
;
; FUNCTION:
; THIS PROCEDURE SETS THE CURSOR EMULATION BIT OFF IN ROM BIOS. THIS
; IS TO PROVIDE A CURSOR ON THE EGA WITH THE 5154 LOADED WITH AN 8X8
; CHARACTER SET.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: CURSOR EMULATION BIT SET FOR APPLICABLE HARDWARE
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SET_CURSOR_EMUL PROC   NEAR
                .IF <BIT HDWR_FLAG AND E5154_ACTIVE> ; EGA with 5154?..
                  PUSH   SI                          ;
                  PUSH   DS                          ; yes..so..
                  MOV    AX,ROM_BIOS                 ; check cursor emulation..
                  MOV    DS,AX                       ;
                  MOV    SI,CURSOR_FLAG              ;
                  MOV    AL,BYTE PTR [SI]            ;
                  .IF <CS:REQ_TXT_LENGTH EQ DEFAULT_LENGTH> gt 25 lines requested?
                    AND    AL,TURN_OFF               ; no....set it OFF
                  .ELSE                              ;
                    OR     AL,TURN_ON                ; yes...set it ON
                  .ENDIF                             ;
                  MOV    BYTE PTR [SI],AL            ;
                  POP    DS                          ;
                  POP    SI                          ;
                .ENDIF                               ;
                RET                                  ; return to calling module
SET_CURSOR_EMUL ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: INT10_COM
;
; FUNCTION:
; THIS IS THE INTERRUPT 10H HANDLER TO CAPTURE THE FOLLOWING FUNCTIONS:
;
;   AH=1H (SET CURSOR TYPE). CURSOR EMULATION IS PERFORMED IF WE HAVE
;         AND EGA WITH A 5151 MONITOR, AND 43 LINES IS REQUESTED.
;
;   AH=0H (SET MODE) SCREEN LENGTH IS MAINTAINED WHEN POSSIBLE. (IE. IN
;          TEXT MODES ONLY.)
;   AN004; Capturing Set Mode call and enforcing the # of Rows based on the
;          previous Set_IOCTL request lines was a design mistake.  ANSI cannot
;          covers the all the application program out there which use INT 10h
;          directly to make a full screen interface by their own way.
;          This part of logic has been taken out by the management decision.
;          Instead, for each set mdoe INT 10h function call, if it were not
;          issued by SET_IOCTL procedures itself, or by DISPLAY.SYS program,
;          then we assume that it was issued by an APPS, that usually does not
;          know the new ANSI GET_IOCTL/SET_IOCTL interfaces.
;          In this case, ANSI is going to call GET_IOCTL and SET_IOCTL function
;          call - This is not to lose the local data consistency in ANSI.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL:
;
;    ERROR:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INT10_COM  PROC   NEAR
            STI                                      ; restore interrupts
           .IF <AH NE SET_CURSOR_CALL> AND           ;
           .IF <AH NE SET_MODE>
              JMP    DWORD PTR CS:ROM_INT10          ; no...pass it on.
           .ENDIF
           .IF <AH EQ SET_CURSOR_CALL>               ;Set cursor call?
              PUSH   AX                              ;
             .IF <BIT CS:HDWR_FLAG AND E5151_ACTIVE> AND ; yes...check if we have an ega..
             .IF <CS:REQ_TXT_LENGTH NE DEFAULT_LENGTH> AND ;
             .IF <CS:GRAPHICS_FLAG EQ TEXT_MODE> AND ; with 5151..so perform cursor mapping
             .IF <CL GE 8>                           ;
                MOV    AL,CH                         ; check for cursor..
;               AND    AL,06H                        ; off emulation.!!!!!Wrong!!! TypeO error
                and    al, 60h                       ; off emulation. J.K.
               .IF <AL NE 020H>                      ;
                  MOV    AL,CH                       ; start position for cursor
                  CALL   MAP_DOWN                    ;
                  MOV    CH,AL                       ;
                  MOV    AL,CL                       ; end position for cursor
                  CALL   MAP_DOWN                    ;
                  MOV    CL,AL                       ;
               .ENDIF                                ;
             .ENDIF                                  ;
              POP    AX                              ;
              JMP    DWORD PTR CS:ROM_INT10          ; continue interrupt processing
           .ELSE NEAR                                ; must be set mode call..
              PUSHF                                  ; prepare for IRET
              mov    cs:ANSI_SetMode_Call_Flag, 1    ;AN008; Used by INT2F_COM
              CALL   DWORD PTR CS:ROM_INT10          ; call INT10 routine
              mov    cs:ANSI_SetMode_Call_Flag, 0    ;AN008; Reset it
              push   bp
              push   es
              PUSH   DS                              ;
              PUSH   SI                              ;
              PUSH   DI                              ;
              PUSH   DX                              ;
              PUSH   CX                              ;
              PUSH   BX                              ;
              PUSH   AX                              ;
              PUSH   CS                              ;
              POP    DS                              ;
              MOV    AH,REQ_VID_MODE                 ; get current mode..
              PUSHF                                  ;
              CALL   DWORD PTR CS:ROM_INT10          ;
              AND    AL,VIDEO_MASK                   ; mask bit 7 (refresh)
              test   In_Generic_IOCTL_Flag, (I_AM_IN_NOW + SET_MODE_BY_DISPLAY)  ;AN004; Flag is on?
             .IF Z   AND                          ;AN010;AN004;If not (I_AM_IN_NOW or SET_MODE_BY_DISPLAY),
             .if <Switch_L EQ 0>
                 push   ax                              ;AN004;Save mode
                 push   es
                 push   cs
                 pop    es
                 mov    di, offset My_IOCTL_Req_Packet
                 mov    INT10_V_Mode, al                ;AN006;Save current mode for SET_SEARCH
                 call   Get_IOCTL
                .IF NC
                    mov    di, offset MY_IOCTL_Req_Packet
                    or     In_Generic_IOCTL_Flag, CALLED_BY_INT10COM ;AN009;Do not set mode INT 10h again. Already done.
                    call   Set_IOCTL
                    and    In_Generic_IOCTL_Flag, not CALLED_BY_INT10COM
                .ENDIF
                 pop    es
                 pop    ax                              ;AN004;Restore mode
                 mov    INT10_V_Mode, 0FFh
             .ENDIF
              LEA    SI,VIDEO_MODE_TABLE             ;
              CALL   GET_SEARCH                      ; look through table for mode selected.
             .IF NC                                  ; if found then..
                .IF <[SI].D_MODE NE TEXT_MODE>       ; text mode?....
                   MOV   GRAPHICS_FLAG,GRAPHICS_MODE ; no...set graphics flag.
                .ELSE                                ;
                   MOV   GRAPHICS_FLAG,TEXT_MODE     ; yes...set text flag..
                .ENDIF                               ;
             .ENDIF                                  ;

              test   In_Generic_IOCTL_Flag, I_AM_IN_NOW
             .if z   AND
             .if <Graphics_Flag EQ TEXT_MODE> AND    ;
             .if <Switch_L EQ 1>
                  call  DO_ROWS
             .endif

;AN004;The following has been taken out!
;AN004;              .IF <REQ_TXT_LENGTH NE DEFAULT_LENGTH> ; 25 lines active?
;AN004;                MOV    AX,DISPLAY_CHECK              ; is DISPLAY.SYS there?
;AN004;                INT    2FH                           ;
;AN004;                .IF <AL NE INSTALLED> OR             ; if not installed or..
;AN004;                MOV    AX,CHECK_ACTIVE               ; if a code page has not..
;AN004;                INT    2FH                           ; been selected then..
;AN004;                .IF C                                ;
;AN004;                  .IF <GRAPHICS_FLAG EQ TEXT_MODE>   ; is this a text mode?
;AN004;                    CALL   ROM_LOAD_8X8              ; yes..load ROM 8x8 character set.
;AN004;                  .ENDIF                             ;
;AN004;                .ENDIF                               ;
;AN004;              .ENDIF                                 ;
;AN004;Instead, for each SET mode function int 10h function call, if it is not
;AN004;issued by ANSI GET_IOCTL and SET_IOCTL procedure themselves, we assume
;AN004;that the APPS, which usually does not know the ANSI GET_IOCTL/SET_IOCTL
;AN004;interfaces, intend to change the screen mode.  In this case, ANSI is
;AN004;kind enough to call GET_IOCTL and SET_IOCTL function call for themselves.

              POP    AX                              ;
              POP    BX                              ;
              POP    CX                              ;
              POP    DX                              ;
              POP    DI                              ;
              POP    SI                              ;
              POP    DS                              ;
              pop    es
              pop    bp
           .ENDIF                                    ;
            IRET                                     ;
INT10_COM  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: INT2F_COM
;
; FUNCTION:
; THIS IS THE INTERRUPT 2FH HANDLER TO CAPTURE THE FOLLOWING FUNCTIONS:
;
;   AX=1A00H INSTALL REQUEST. ANSI WILL RETURN AL=FFH IF LOADED.
;
;   AH=1A01H THIS IS THE INT2FH INTERFACE TO THE GENERIC IOCTL.
;      NOTE: THE GET CHARACTERISTICS FUNCTION CALL WILL RETURN
;            THE REQ_TXT_LENGTH IN THE BUFFER AS OPPOSED TO
;            THE ACTUAL HARDWARE SCREEN_LENGTH
;   Ax=1A02h This is an information passing from DISPLAY.SYS about
;            the INT 10h, SET MODE call.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL:
;
;    ERROR:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INT2F_COM  PROC   NEAR
           STI                                  ;
           .IF <AH NE MULT_ANSI> OR             ; is this for ANSI?
;           .IF <AL GT IOCTL_2F>                 ;
           .IF <AL GT DA_INFO_2F>               ;AN004;=2h
             JMP    DWORD PTR CS:ROM_INT2F      ; no....jump to old INT2F
           .ENDIF                               ;
           .SELECT                              ;
             .WHEN <AL EQ INSTALL_CHECK> NEAR   ; if install check then..
               MOV     AL,INSTALLED             ; load value to indicate installed
               CLC                              ; clear error flag.
;             .WHEN <AL EQ IOCTL_2F>             ; request for IOCTL?
             .WHEN <AL BE DA_INFO_2F> NEAR      ;AN004;IOCTL or INFO passing?
               PUSH   BP                        ;
               PUSH   AX                        ; s
               PUSH   CX                        ;  a
               PUSH   DX                        ;   v
               PUSH   DS                        ;    e  r
               PUSH   ES                        ;        e
               PUSH   DI                        ;         g
               PUSH   SI                        ;          s.
               PUSH   BX                        ;
               PUSH   DS                        ; load ES with DS (for call)
               POP    ES                        ;
               MOV    DI,DX                     ; load DI with DX (for call)
               PUSH   CS                        ; setup local addressability
               POP    DS                        ;
              .IF <AL EQ IOCTL_2F>              ;IOCTL request
                 .IF <CL EQ GET_FUNC>           ; get function requested.
                    CALL   GET_IOCTL            ;
                   .IF NC AND                   ; if no error and...
                   .IF <HDWR_FLAG GE E5151_ACTIVE> AND ; gt 25 lines supported and..
                   .IF <[SI].D_MODE EQ TEXT_MODE> ; this is a text mode then..
                     .if <cs:Switch_L EQ 1> OR
                     .if <cs:ANSI_SetMode_Call_Flag NE 1> OR  ;AN008; if not originated by ANSI thru. AH=0, INT10,
                     .if <cs:Display_Loaded_Before_Me NE 1>   ;AN008;  or Display.sys not loaded before ANSI,
                         MOV    BX,REQ_TXT_LENGTH    ; then use REQ_TXT_LENGTH instead..
                         MOV    ES:[DI].RP_ROWS,BX   ;
                     .endif
                      CLC                         ;
                   .ENDIF                         ;
                 .ELSEIF <CL EQ SET_FUNC>         ;
                    CALL   SET_IOCTL              ; set function requested.
                 .ELSE                            ; invalid function...
                    MOV    AX,INVALID_FUNC        ; load error and...
                    STC                           ; set error flag.
                 .ENDIF                           ;
              .ELSE                               ;AN004;Info. passing
                 .IF <ES:[DI].DA_INFO_LEVEL EQ 0> ;AN004; 0 = DA_SETMODE_FLAG request.
                   .IF  <ES:[DI].DA_SETMODE_FLAG EQ 1>
                        or cs:In_Generic_IOCTL_Flag, SET_MODE_BY_DISPLAY       ;AN004;Turn the flag on
                   .ELSE
                        and cs:In_Generic_IOCTL_Flag, not SET_MODE_BY_DISPLAY  ;AN004;Turn the flag off
                   .ENDIF
                 .ELSE
                   .IF <ES:[DI].DA_INFO_LEVEL EQ 1>        ;AN011; 1 = DA_OPTION_L_STATE query
                        mov al, cs:[Switch_L]
                        mov es:[di].DA_OPTION_L_STATE, al
                   .ENDIF
                 .ENDIF
                  clc                           ;AN004;clear carry. There is no Error in DOS 4.00 for this call.
              .ENDIF
               POP    BX                        ; restore all..
               POP    SI                        ;
               POP    DI                        ;   registers except..
               POP    ES                        ;
               POP    DS                        ;     BP.
               POP    DX                        ;
               POP    CX                        ;
               PUSH   AX                        ; save error condition
               MOV    BP,SP                     ; setup frame pointer
               MOV    AX,[BP+10]                ; load stack flags
               .IF NC                           ; carry set?..
                 AND    AX,NOT_CY               ; no.. set carry off.
                 MOV    [BP+10],AX              ; put back on stack.
                 POP    AX                      ; remove error flag from stack
                 POP    AX                      ; no error so bring back function call
                 XCHG   AH,AL                   ; exchange to show that ANSI present
               .ELSE                            ;
                 OR     AX,CY                   ; yes...set carry on.
                 MOV    [BP+10],AX              ; put back on stack.
                 POP    AX                      ; restore error flag
                 POP    BP                      ; pop off saved value of AX (destroyed)
               .ENDIF                           ;
               POP    BP                        ; restore final register.
           .ENDSELECT                           ;
ABORT:     IRET                                 ;
INT2F_COM  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: MAP_DOWN
;
; FUNCTION:
; THIS PROCEDURE MAPS THE CURSOR START (END) POSITION FROM A 14 PEL
; BOX SIZE TO AN 8 PEL BOX SIZE.
;
; AT ENTRY: AL HAS THE CURSOR START (END) TO BE MAPPED.
;
; AT EXIT:
;    NORMAL: AL CONTAINS THE MAPPED POSITION FOR CURSOR START (END)
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MAP_DOWN   PROC   NEAR
           PUSH   BX                   ;
           XOR    AH,AH                ; clear upper byte of cursor position
           MOV    BL,EIGHT             ; multiply by current box size.
           PUSH   DX                   ;    al     x
           MUL    BL                   ;   ---- = ---
           POP    DX                   ;    14     8
           MOV    BL,FOURTEEN          ;
           DIV    BL                   ; divide by box size expected.
           POP    BX                   ;
           RET                         ;
MAP_DOWN   ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: SET_VIDEO_MODE
;
; FUNCTION:
; THIS PROCEDURE SETS THE VIDEO MODE SPECIFIED IN DS:[SI].V_MODE.
;
; AT ENTRY: DS:SI.V_MODE CONTAINS MODE NUMBER
;
; AT EXIT:
;    NORMAL: MODE SET
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SET_VIDEO_MODE PROC   NEAR
            .if <BIT cs:In_Generic_IOCTL_Flag NAND CALLED_BY_INT10COM>
               MOV    AL,[SI].V_MODE             ; ..issue set mode
               .IF <BIT HDWR_FLAG AND LCD_ACTIVE> OR ; is this the LCD?
               .IF <BIT HDWR_FLAG AND VGA_ACTIVE> ; or VGA (done for BRECON card)
                 PUSH   DS                       ; yes...
                 MOV    BL,AL                    ; save mode
                 MOV    AX,ROM_BIOS              ;
                 MOV    DS,AX                    ; get equipment status flag..
                 MOV    AX,DS:[EQUIP_FLAG]       ;
                 AND    AX,INIT_VID_MASK         ; clear initial video bits..
                 .IF <BL EQ MODE7> OR            ; are we setting mono?
                 .IF <BL EQ MODE15>              ;
                   OR    AX,LCD_MONO_MODE        ; yes...set bits as mono
                 .ELSE                           ;
                   OR    AX,LCD_COLOR_MODE       ; no...set bits as color
                 .ENDIF                          ;
                 MOV    DS:[EQUIP_FLAG],AX       ; replace updated flag.
                 MOV    AL,BL                    ; restore mode.
                 POP    DS                       ;
               .ENDIF                            ;
               MOV    AH,SET_MODE                ; set mode
               INT    10H
            .endif
               RET
SET_VIDEO_MODE ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: ROM_LOAD_8X8
;
; FUNCTION:
; THIS PROCEDURE LOADS THE ROM 8X8 CHARACTER SET AND ACTIVATES BLOCK=0
; FONT.
;
; AT ENTRY:
;
; AT EXIT:
;    NORMAL: 8X8 ROM CHARACTER SET LOADED
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ROM_LOAD_8X8 PROC   NEAR
             MOV    AX,LOAD_8X8              ; load 8x8 ROM font
             XOR    BL,BL                    ;
             PUSHF
             CALL   DWORD PTR CS:ROM_INT10
             MOV    AX,SET_BLOCK_0           ; activate block = 0
             XOR    BL,BL
             PUSHF
             CALL   DWORD PTR CS:ROM_INT10
             RET
ROM_LOAD_8X8 ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: CHECK_FOR_DISPLAY
;
; FUNCTION:
; THIS PROCEDURE CHECKS TO SEE IF WE DISPLAY.SYS IS THERE, AND IF
; IT IS..IT HAS THE REQUIRED FONT.
;
; AT ENTRY: AX - DESIRED SCREEN LENGTH
;
; AT EXIT:
;    NORMAL: CARRY CLEAR IF ALL OKAY
;
;    ERROR: CARRY SET IF FONT NOT AVAILABLE.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CHECK_FOR_DISPLAY PROC   NEAR
               .IF <AX EQ DEFAULT_LENGTH> OR   ; is it just 25 lines needed?
               MOV    AX,DISPLAY_CHECK         ;
               INT    2FH                      ;
               .IF <AL NE INSTALLED> OR        ; or is DISPLAY.SYS not there?
               MOV    AX,CHECK_FOR_FONT        ;
               INT    2FH                      ; or if it is does it have the..
               .IF NC                          ; 8X8 font then.
                 CLC                           ; clear carry
               .ELSE                           ;
                 STC                           ; no font...set carry
               .ENDIF                          ;
               RET                             ;
CHECK_FOR_DISPLAY ENDP

CODE        ENDS
            END
