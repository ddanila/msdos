data    segment

;
;*****************************************************************************
; Macro's
;*****************************************************************************
;


Define_Msg macro Message_Name                   ;
                                                ;
Create_Msg Message_Name,Message_Number,Handle,Sublist,Count,Class,Function,Input
                                                ;
        endm                                    ;

;-----------------------------------------------------------------------------

Create_Msg macro Parm1,Parm2,Parm3,Parm4,Parm5,Parm6,Parm7,Parm8;

Parm1   label   word                            ;
        dw      Parm2                           ;
        dw      Parm3                           ;
        dw      Parm4                           ;
        dw      Parm5                           ;
        db      Parm6                           ;
        db      Parm7                           ;
        dw      Parm8                           ;
        endm                                    ;


;---------------------------                    ;
Sublist_msg_parserr     label   dword           ;
        db              Sublist_Length          ;11
        db              Reserved                ;0
parsoff dw              ?                       ;off
parseg  dw              ?                       ;
        db              0                       ;USE PERCENT ZERO
        db              Left_Align+Char_Field_ASCIIZ ;type of data
        db              128                     ;max width
        db              1                       ;min width
        db              Blank                   ;pad char
;---------------------------                    ;

Sublist_msg_exterror label word

        db              Sublist_Length
        db              Reserved
FileNamePointer         label dword
FileNameOffset  dw      ?
FileNameSegment dw      ?
        db              0                              ; SPECIAL %0 - Extended Errors only
        db              Left_Align+Char_Field_ASCIIZ
        db              132
        db              0
        db              Blank
;-----------------------------------------------------------------------------
;
;*****************************************************************************
; Message Retriever equates
;*****************************************************************************
;

Format_Msg              equ     'C'

N_A                     equ     0

Blank                   equ     " "
No_Function             equ     0

No_Input                equ     0


;
;*****************************************************************************
; Message Description Tables
;*****************************************************************************
;

;----------------------                         ;
Message_Number  = 1                             ;
Handle          = No_Handle                     ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgBadDOSVersion        ;
;----------------------                         ;
Message_Number  = 2                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgOutOfMemory          ;
;----------------------                         ;
Message_Number  = 3                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgLoadFailure          ;
;----------------------                         ;
Message_Number  = 4                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgNoAccess             ;
;----------------------                         ;
Message_Number  = 5                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgNoConvert            ;
;----------------------                         ;
Message_Number  = 6                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgNoFile               ;
;----------------------                         ;
Message_Number  = 7                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgFileCreateError      ;
;----------------------                         ;
Message_Number  = 8                             ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = DOS_BUF_KEYB_INP              ;
Input           EQU <INBUF>                         ;
        Define_Msg      msgFixUp                ;
;----------------------                         ;
Message_Number  = 0                             ;
Handle          = STDERR                        ;
Sublist         EQU <ds:sublist_msg_parserr>        ;
Count           = 1                             ;
Class           = Parse_Err_Class               ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      parse_error_msg         ;
;----------------------                         ;
Message_Number  = 0                             ;
Handle          = STDERR                        ;
Sublist         EQU <ds:sublist_msg_exterror>       ;
Count           = 1                             ;
Class           = ext_Err_Class                 ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      extend_error_msg        ;
;----------------------                         ;
Message_Number  = 10                            ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgNoDiskSpace          ;
;----------------------                         ;
Message_Number  = 12                            ;
Handle          = STDOUT                        ;
Sublist         EQU <No_Replace>                    ;
Count           = N_A                           ;
Class           = Utility_Msg_Class             ;
Function        = No_Input                      ;
Input           EQU <N_A>                           ;
        Define_Msg      msgNoFileName           ;
;----------------------                         ;
data ends
