;*****************************************************************************
; Macro's
;*****************************************************************************
Define_Msg macro Message_Name                   ;
Create_Msg Message_Name,Message_Number,Handle,Sublist,Count,Class,Function,Input
        endm                                    ;
;-----------------------------------------------------------------------------
Create_Msg macro Parm1,Parm2,Parm3,Parm4,Parm5,Parm6,Parm7,Parm8;
Public  Parm1
Parm1   label   word                            ;
        dw      Parm2                           ;
        dw      Parm3                           ;
        dw      Parm4                           ;
        dw      Parm5                           ;
        db      Parm6                           ;
        db      Parm7                           ;
        dw      Parm8                           ;
        endm                                    ;
;*****************************************************************************
; External data declarations
;*****************************************************************************
        Extrn   Arg_Buf:Byte
ifdef fsexec
        Extrn   Drive_Letter_Msg:Byte
endif
        Extrn   TChar:Byte
        Extrn   Cross_Clus:Byte
        extrn   sernum:word
;*****************************************************************************
; Public Data
;*****************************************************************************
        Public  Sublist_msg_Idmes
        Public  BadDrvm
        Public  YES_BYTE
        Public  NO_BYTE
        Public  yn_arg
        Public  orphcnt
        Public  report_arg
        Public  rarg1
        Public  rarg3
        Public  badrw_str
        Public  badrw_num
        Public  block_num
        Public  fatal_arg1
        Public  fatal_arg2
        Public  file_arg1
        Public  file_arg2
        Public  free_arg1
        Public  free_arg2
        Public  free_arg3
        Public  Fatal_End
        Public  MonTab
        public  fatmsg1
        public  fatmsg2
        extrn   orphsiz:word
;*****************************************************************************
; Message Retriever equates
;*****************************************************************************
Format_Msg              equ     'C'
N_A                     equ     0
None                    equ     0
Blank                   equ     " "
No_Function             equ     0
data    segment public para 'data'
;*****************************************************************************
; Message Sublist Tables
;*****************************************************************************
;The  following  control  blocks  are   used   for   messages  with
;replaceable  paramters.  These  control  blocks  are  used by  the
;SysDispMsg routine.
;---------------------------                    ;
Sublist_msg_Orphmes2    label dword             ;
Sublist_msg_Orphmes3    label dword             ;
Sublist_msg_HidMes      label dword             ;
Sublist_msg_DirMes      label dword             ;
Sublist_msg_FileMes     label dword             ;
        db              Sublist_Length          ;0bh
        db              Reserved                ;00h
        dw              rarg1                   ;offset of value
        dw              dg                      ;segment of value
        db              1                       ;the first parm
        db              Right_Align+Unsgn_Bin_DWord ;type of data
        db              10                      ;max length of data
        db              10                      ;min length of data
        db              Blank                   ;pad character
        db              Sublist_Length          ;0bh
        db              Reserved                ;00h
        dw              rarg3                   ;offset of value
        dw              dg                      ;segment of value
        db              2                       ;the second parm
        db              Left_Align+Unsgn_Bin_DWord;type of data
        db              10                      ;max length of data
        db              1                       ;min length of data
        db              Blank                   ;pad character
;---------------------------                    ;
Sublist_msg_dskspc      label dword             ;
Sublist_msg_badspc      label dword             ;
Sublist_msg_frespc      label dword             ;
Sublist_msg_totmem      label dword             ;
Sublist_msg_fremem      label dword             ;
Sublist_msg_Freebymes   label dword             ;
Sublist_msg_alloc       label dword             ;
        db              Sublist_Length          ;0bh
        db              Reserved                ;00h
        dw              dg:rarg1                ;offset  of data
        dw              dg                      ;segment of data
        db              1                       ;1st parm
        db              Right_Align+Unsgn_Bin_DWord ;type of data
        db              10                      ;max length of data
        db              10                      ;min length of data
        db              Blank                   ;pad character
;---------------------------                    ;
Sublist_msg_Extents     label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:rarg1                ;
        dw              dg                      ;
        db              2                       ;
        db              Left_Align+Unsgn_Bin_Word ;                            ;
        db              5                       ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_msg_Badr_arg    label   dword           ;
Sublist_msg_Badw_arg    label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:Badrw_Num            ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Unsgn_Bin_Word ;                            ;
        db              5                       ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_msg_Badrdmes    label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:Fatal_End            ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              1                       ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_msg_Crossmes    label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:Cross_Clus           ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Unsgn_Bin_Word  ;
        db              5                       ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_msg_BadTarg     label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_msg_IDmes       label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              11                      ;
        db              1                       ;
        db              Blank                   ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              0                       ;Date will be entered
        dw              0                       ; by PrintID routine
        db              2                       ;
        db              Left_Align+Date_MDY_4   ;
        db              10                      ;
        db              1                       ;
        db              Blank                   ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              0                       ;Time will be entered
        dw              0                       ; by PrintID routine
        db              3                       ;
        db              Left_Align+Time_HHMM_Cty;
        db              6                       ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_Msg_File_Arg    label   dword
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_Msg_Noisy       label   dword
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
Sublist_Msg_Orphmes     label   dword
        db              Sublist_Length          ;0bh
        db              Reserved                ;00h
        dw              dg:orphsiz              ;offset of data
        dw              dg                      ;segment
        db              1                       ;1st of 2 replaceable parms
        db              Left_Align+Unsgn_Bin_Word ;only 64k clusters
        db              05                      ;max length
        db              1                       ;min length
        db              Blank                   ;pad
        db              Sublist_Length          ;0b
        db              Reserved                ;00
        dw              dg:orphcnt              ;offset
        dw              dg                      ;seg
        db              2                       ;2nd replaceable parm
        db              Left_Align+Unsgn_Bin_dword ;double word
        db              10                      ;max len
        db              1                       ;min len
        db              Blank                   ;pad char
;---------------------------                    ;
Sublist_Msg_Direcmes    label   dword
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:arg_buf              ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
Sublist_Msg_Fatalmes    label   dword
        db              Sublist_Length          ;
        db              Reserved                ;
fatmsg1 dw              dg:fatal_arg1           ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
        db              Sublist_Length          ;
        db              Reserved                ;
fatmsg2 dw              dg:fatal_arg2           ;
        dw              dg                      ;
        db              2                       ;number 2 of 2 subs
        db              Left_Align+Char_Field_ASCIIZ ;
        db              64                      ;
        db              1                       ;
        db              Blank                   ;
;---------------------------                    ;
ifdef   fsexec
Sublist_msg_EXECFailure label   dword           ;
        db              Sublist_Length          ;
        db              Reserved                ;
        dw              dg:Drive_Letter_Msg     ;
        dw              dg                      ;
        db              1                       ;
        db              Left_Align+Char_Field_ASCIIZ ;
        db              2                       ;
        db              2                       ;
        db              Blank                   ;
endif
;---------------------------                    ;
Sublist_msgSerialNumber label dword             ;
        db              Sublist_Length          ;0b
        db              Reserved                ;00
        dw              offset word ptr sernum+2 ;data field
        dw              data                    ;
        db              1                       ;#1 of 2
        db              Right_Align+Bin_Hex_Word ;format
        db              4                       ;min len
        db              4                       ;max len
        db              '0'                     ;Display leading 0's
        db              Sublist_Length          ;0b
        db              Reserved                ;00
        dw              offset sernum           ;data field
        dw              data                    ;
        db              2                       ;#2 of 2
        db              Right_Align+Bin_hex_Word ;format
        db              4                       ;min len
        db              4                       ;max len
        db              '0'                     ;pad char
;---------------------------                    ;
Sublist_msg_parserr     label   dword           ;
        db              Sublist_Length          ;11
        db              Reserved                ;0
public movsi
movsi   dw              dg:command_line_buffer  ;off
        dw              dg                      ;seg
        db              0                       ;USE PERCENT ZERO
        db              Left_Align+Char_Field_ASCIIZ ;type of data
        db              128                     ;max width
        db              1                       ;min width
        db              Blank                   ;pad char
;---------------------------                    ;
;*****************************************************************************
; Message Description Tables
;*****************************************************************************
;----------------------                         ;
Message_Number  = 1
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = EXT_ERR_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badver                     ; AN000;SM Incorrect DOS version
;----------------------                         ;
Message_Number  = 19
Handle          = STDERR
Sublist         EQU <None>
Count           = N_A
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badidbyt                   ; AN000;SM Probable non_DOS disk;an000;bgb (CRLF) Continue (Y/N)?
;----------------------                         ;
Message_Number  = 3
Handle          = STDOUT
Sublist         EQU <None>
Count           = N_A
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   freemes                    ; AN000;SM Convert lost chains t;an000;bgbo files (Y/N)?
;----------------------                         ;
Message_Number  = 4
Handle          = STDOUT
Sublist         EQU <None>
Count           = N_A
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   ptrandir                   ; AN000;SM Unrecoverable error i;an000;bgbn directory
;----------------------                         ;
Message_Number  = 5
Handle          = STDOUT
Sublist         EQU <None>
Count           = N_A
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   ptrandir2                  ; AN000;SM Convert directory to ;an000;bgbfile (Y/N)?
;----------------------                         ;
Message_Number  = 7
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_dskspc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   dskspc                     ; AN000;SM %1 bytes total disk s;an000;bgbpace
;----------------------                         ;
Message_Number  = 8
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_badspc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badspc                     ; AN000;SM %1 bytes in bad secto;an000;bgbrs
;----------------------                         ;
Message_Number  =  9
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_hidmes>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   hidmes                     ; AN000;SM %1 bytes in %2 hidden;an000;bgb files
;----------------------                         ;
Message_Number  = 10
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_dirmes>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   dirmes                     ; AN000;SM %1 bytes in %2 direct;an000;bgbories
;----------------------                         ;
Message_Number  = 11                            ; message number 11
Handle          = STDOUT                        ; crt
Sublist         EQU <dg:Sublist_msg_filemes>        ; location of sublist
Count           = 2                             ; caontains 2 parameters
Class           = UTILITY_MSG_CLASS             ; type of msg
Function        = NO_INPUT                      ; no input from user
Input           = N_A                           ; not applicable
        Define_Msg   filemes                    ; AN000;SM %1 bytes in %2 user f;an000;bgbiles
;----------------------                         ;
Message_Number  = 12
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_orphmes2>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   orphmes2                   ; AN000;SM %1 bytes in %2 recove;an000;bgbred files
;----------------------                         ;
Message_Number  = 13
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_orphmes3>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   orphmes3                   ; AN000;SM %1 bytes would be in ;an000;bgb%2 recovered files
;----------------------                         ;
Message_Number  = 14
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_frespc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   frespc                     ; AN000;SM %1 bytes available on;an000;bgb disk
;----------------------                         ;
Message_Number  = 15
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_totmem>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   totmem                     ; AN000;SM %1 bytes total memory
;----------------------                         ;
Message_Number  = 16
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_fremem>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   fremem                     ; AN000;SM %1 bytes free
;----------------------                         ;
Message_Number  = 17
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   no_net_arg                 ; AN000;SM Cannot CHKDSK a netwo;an000;bgbrk drive
;----------------------                         ;
Message_Number  = 18
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   SubstErr                   ; AN000;SM Cannot CHKDSK a SUBST;an000;bgbed or ASSIGNed drive
;----------------------                         ;
Message_Number  = 20
Handle          = STDERR
Sublist         EQU <dg:Sublist_msg_badr_arg>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badr_arg                   ; AN000;SM Disk error reading FA;an000;bgbT %2
;----------------------                         ;
Message_Number  = 21
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_direcmes>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   direc_arg                  ; AN000;SM Directory %1
;----------------------                         ;
Message_Number  = 22
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_extents>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   extent_arg                 ; AN000;SM %1 Contains %2 non-co;an000;bgbntiguous blocks
;----------------------                         ;
Message_Number  = 23
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   noext_arg                  ; AN000;SM All specified file(s);an000;bgb are contiguous
;----------------------                         ;
Message_Number  = 24
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   fixmes_arg                 ; AN000;SM Errors found, F param;an000;bgbeter not specified (CRLF)
;----------------------                         ;          Corrections will not ;an000;bgbbe written to disk
Message_Number  = 25
Handle          = STDERR
Sublist         EQU <dg:Sublist_msg_fatalmes>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   fatal_arg                  ; AN000;SM Processing cannot con;an000;bgbtinue %1%2
;----------------------                         ;
Message_Number  = 26
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_badrdmes>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badrdmes                   ; AN000;SM File allocation table;an000;bgb bad, drive %1
;----------------------                         ;
Message_Number  = 2
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   stackmes                   ; AN000;SM Insufficient memory
        Define_Msg   stackmes1                  ; AN000;SM Cannot make directory;an000;bgb entry %1 (CRLF)
;----------------------                         ;          Move files from root ;an000;bgbdirectory and repeat CHKDSK
Message_Number  = 29
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   cdddmes                    ; AN000;SM CHDIR .. failed, tryi;an000;bgbng alternate method
;----------------------                         ;
Message_Number  = 30
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badchain                   ; AN000;SM Has invalid cluster, ;an000;bgbfile truncated
;----------------------                         ;
Message_Number  = 31
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badsubdir                  ; AN000;SM Invalid sub-directory;an000;bgb entry
;----------------------                         ;
Message_Number  = 32
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   ndotmes                    ; AN000;SM Does not exist
;----------------------                         ;
Message_Number  = 33
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   nulnz                      ; AN000;SM First cluster number ;an000;bgbis invalid, entry truncated
;----------------------                         ;
Message_Number  = 34
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badclus                    ; AN000;SM Allocation error, siz;an000;bgbe adjusted
;----------------------                         ;
Message_Number  = 35
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   norecdot                   ; AN000;SM Cannot recover .. ent;an000;bgbry, processing continued
;----------------------                         ;
Message_Number  = 36
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   nuldmes                    ; AN000;SM Directory is totally ;an000;bgbempty, no .. or ..
;----------------------                         ;
Message_Number  = 37
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   joinmes                    ; AN000;SM Directory is joined
;----------------------                         ;
Message_Number  = 38
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   norecddot                  ; AN000;SM Cannot recover .. ent;an000;bgbry
;----------------------                         ;
Message_Number  = 39
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   norecddot1                 ; AN000;SM Entry has a bad link
;----------------------                         ;
Message_Number  = 40
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   norecddot2                 ; AN000;SM Entry has a bad attri;an000;bgbbute
;----------------------                         ;
Message_Number  = 41
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   norecddot3                 ; AN000;SM Entry has a bad size
;----------------------                         ;
Message_Number  = 42
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_crossmes>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   cross_arg                  ; AN000;SM Is cross linked on cl;an000;bgbuster %2
;----------------------                         ;
Message_Number  = 43
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_badtarg>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badtarg_ptr                ; AN000;SM Cannot CHDIR to %1, (;an000;bgbCRLF)
;----------------------                         ;          tree past this point ;an000;bgbnot processed
Message_Number  = 44
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badtarg2                   ; AN000;SM tree past this point ;an000;bgbnot processed
;----------------------                         ;
Message_Number  = 45
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_freebymes>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   freeBymes1                 ; AN000;SM %1 bytes disk space f;an000;bgbreed
;----------------------                         ;
Message_Number  = 46
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_freebymes>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   freebymes2                 ; AN000;SM %1 bytes disk space w;an000;bgbould be freed
;----------------------                         ;
Message_Number  = 47
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_idmes>
Count           = 3
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   idmes_arg                  ; AN000;SM Volume %1 created %2 ;an000;bgb%3
;----------------------                         ;
Message_Number  = 48
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_alloc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   idmes1                     ; AN017;bgb %1 total allocation ;an000;bgbunits on disk
;----------------------                         ;
Message_Number  = 49
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_alloc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   idmes2                     ; AN000;SM %1 bytes in each allo;an000;bgbcation unit
;----------------------                         ;
ifdef   fsexec
Message_Number  = 50
Handle          = STDERR
Sublist         EQU <dg:Sublist_msg_ExecFailure>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   msgExecFailure             ; AN000;SM CHKDSK not available ;an038;bgb;an000;bgbon drive %1
        endif
;----------------------                         ;
Message_Number  = 51
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   Inv_XA_Msg                 ; AN000;SM Extended Attributes h;an000;bgbas invalid clusters,
;----------------------                         ;          attributes truncated
Message_Number  = 52
Handle          = STDOUT
Sublist         EQU <None>
Count           = None
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   Alloc_XA_Msg               ; AN000;SM Extended Attributes l;an000;bgbocation .. ,
;----------------------                         ;          attributes truncated
Message_Number  = 53
Handle          = STDERR
Sublist         EQU <dg:sublist_msg_parserr>
Count           = 1
Class           = PARSE_ERR_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badsw_arg                  ; AN000;SM Invalid parameter
;----------------------                         ;
Message_Number  = 54
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   baddrv_arg                 ; AN000;SM Invalid drive specifi;an000;bgbcation
;----------------------                         ;
Message_Number  = 55
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   invpath_arg                ; AN000;SM Path not found
;----------------------                         ;
Message_Number  = 56
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   opnerr_arg                 ; AN000;SM File not found
;----------------------                         ;
Message_Number  = 0                             ;
Handle          = STDERR                        ;
Sublist         EQU <No_Replace>                    ;                               ;AN;an000;bgb000;
Count           = N_A                           ;
Class           = Ext_Err_Class                 ;
Function        = No_Function                   ;
Input           = N_A                           ;
        Define_Msg      Extended_Error_Msg      ;
;-----------------------
Message_Number  = 0                             ;
Handle          = STDERR                        ;
Sublist         EQU <dg:sublist_msg_parserr>        ;                               ;an046;bgbbgb000;
Count           = 1                             ;
Class           = Parse_Err_Class               ;
Function        = No_Function                   ;
Input           = N_A                           ;
        Define_Msg      Parse_Error_Msg         ;
;-----------------------
Message_Number  = 58
Handle          = STDERR
Sublist         EQU <dg:Sublist_msg_orphmes>
Count           = 2
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   orph_arg                   ; AN000;dms "%1 lost clusters fo;an000;bgbund in %2 chains.",0
;----------------------                         ;
Message_Number  = 59
Handle          = STDout
Sublist         EQU <none>
Count           = none
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   crlf_arg                   ; AN000;dms CR,LF
;----------------------                         ;
Message_Number  = 60
Handle          = STDERR
Sublist         EQU <none>
Count           = none
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badcd_arg                  ; AN000;dms "Cannot CHDIR to roo;an000;bgbt",cr,lf
;----------------------                         ;
Message_Number  = 61
Handle          = STDERR
Sublist         EQU <dg:Sublist_Msg_Badw_arg>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   badw_arg                   ; AN000;dms "Disk error writing ;an000;bgbFAT %1"
;----------------------                         ;
Message_Number  = 62
Handle          = STDOUT
Sublist         EQU <dg:Sublist_Msg_Noisy>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   noisy_arg                  ; AN000;dms "       %1"
;----------------------                         ;
Message_Number  = 63
Handle          = STDERR
Sublist         EQU <none>
Count           = none
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   baddpbdir                  ; AN000;dms "Invalid current dir;an000;bgbectory"
;----------------------                         ;
Message_Number  = 64
Handle          = STDERR
Sublist         EQU <dg:Sublist_Msg_File_Arg>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   file_arg                   ; AN000;dms "%1",cr,lf
;----------------------                         ;
Message_Number  = 65
Handle          = STDERR
Sublist         EQU <none>
Count           = none
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   creatmes                   ; AN000;dms "Insufficient room i;an000;bgbn root directory"
;----------------------                         ;
Message_Number  = 70
Handle          = STDOUT
Sublist         EQU <dg:Sublist_msg_alloc>
Count           = 1
Class           = UTILITY_MSG_CLASS
Function        = NO_INPUT
Input           = N_A
        Define_Msg   idmes3                     ; AN017;bgb %1 allocation units ;an000;bgbavailable on disk
;----------------------                         ;
Message_Number  = 71                            ;
Handle          = STDOUT                        ;
Sublist         EQU <Sublist_msgSerialNumber>       ;
Count           = 2                             ;
Class           = Utility_Msg_Class             ;
Function        = No_Function                   ;
Input           = N_A                           ;
        Define_Msg      msgSerialNumber         ;
;----------------------                         ;
Message_Number  = 72
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   no_mem_arg                 ; AN030;bgb insufficient memory
;----------------------                         ;
Message_Number  = 73
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   inval_media                ; AN033;bgb invalid media type
;----------------------                         ;
Message_Number  = 74
Handle          = STDERR
Sublist         EQU <None>
Count           = None
Class           = utility_msg_class
Function        = NO_INPUT
Input           = N_A
        Define_Msg   write_fault                ; AN045;bgb write fault error
;*****************************************************************************
; Message Data Area
;*****************************************************************************
; THE FOLLOWING ONE BYTE CHARACTERS ARE THE PROMPT ANSWERS.
; THEY MUST BE LOWER CASE, AND THE UPPER TO LOWER, OR LOWER
; TO LOWER CONVERSION MUST BE DOABLE BY "OR  AL,20h".
; Yes/No Answers
YES_BYTE        DB      "y"
NO_BYTE         DB      "n"
;The following table is the list of abbreviated month names used to print
;  out the volume ID.
; MUST BE THREE BYTES PER MONTH
MONTAB          DB      "JanFebMarAprMayJunJulAugSepOctNovDec"
yn_arg      dw      ?
;orph_num    dw      ?  ;from orphsiz; = number of lost clusters
orphcnt     dd      ?  ;number of chains of lost clusters
report_arg  dw      ?
rarg1       dd      ? ;changed to dword
rarg3       dd      ? ;changed to dword
baddrvm     DB      " A.",0
badrw_str   dw      ?
badrw_num   dw      ?
block_num   dw      ?
fatal_arg1  dw      ?
fatal_arg2  dw      ?
file_arg1   dw      ?
file_arg2   dw      ?
free_arg1   dw      ?
free_arg2   dw      ?
free_arg3   dw      ?
fatal_end   db     ".",0
data ends
