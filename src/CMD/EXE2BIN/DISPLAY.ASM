

CODE    SEGMENT PARA PUBLIC 'CODE'
CODE    ENDS
DATA    SEGMENT PARA PUBLIC 'DATA'
DATA    ENDS
STACK   SEGMENT PARA STACK  'STACK'
STACK   ENDS
ZLOAD   SEGMENT PARA PUBLIC 'ZLOAD'
ZLOAD   ENDS

CODE    SEGMENT PARA PUBLIC 'CODE'
        assume  cs:code,ds:data
;
;*****************************************************************************
; External Declarations
;*****************************************************************************
;

        extrn   SysDispMsg:near

;
;***************************************************************************
; Message Structures
;***************************************************************************
;


Message_Table struc                             ;
                                                ;
Entry1  dw      0                               ;
Entry2  dw      0                               ;
Entry3  dw      0                               ;
Entry4  dw      0                               ;
Entry5  db      0                               ;
Entry6  db      0                               ;
Entry7  dw      0                               ;
                                                ;
Message_Table ends                              ;



;*****************************************************************************
;Routine name&gml Display_Interface
;*****************************************************************************
;
;DescriptioN&gml Save all registers, set up registers required for SysDispMsg
;             routine. This information is contained in a message description
;             table pointed to by the DX register. Call SysDispMsg, then
;             restore registers. This routine assumes that the only time an
;             error will be returned is if an extended error message was
;             requested, so it will ignore error returns
;
;Called Procedures: Message (macro)
;
;Input&gml ES&gmlDX = pointer to message description
;
;Output&gml None
;
;Psuedocode
;----------
;
;       Save all registers
;       Setup registers for SysDispMsg from Message Description Tables
;       CALL SysDispMsg
;       Restore registers
;       ret
;*****************************************************************************

Public  Display_Interface
Display_Interface   proc                        ;

        push    ds                              ;
        push    es                              ;
        push    ax                              ;Save registers
        push    bx                              ; "  "    "  "
        push    cx                              ; "  "    "  "
        push    dx                              ; "  "    "  "
        push    si                              ; "  "    "  "
        push    di                              ; "  "    "  "
        mov     di,dx                           ;Change pointer to table
        mov     dx,SEG data                     ;Point to data segment
        mov     ds,dx                           ;
        mov     es,dx
        mov     ax,[di].Entry1                  ;Message number
        mov     bx,[di].Entry2                  ;Handle
        mov     si,[di].Entry3                  ;Sublist
        mov     cx,[di].Entry4                  ;Count
        mov     dh,[di].Entry5                  ;Class
        mov     dl,[di].Entry6                  ;Function
        mov     di,[di].Entry7                  ;Input
        call    SysDispMsg                      ;Display the message
        pop     di                              ;Restore registers
        pop     si                              ; "  "    "  "
        pop     dx                              ; "  "    "  "
        pop     cx                              ; "  "    "  "
        pop     bx                              ; "  "    "  "
        pop     ax                              ; "  "    "  "
        pop     es                              ;
        pop     ds                              ;
        ret                                     ;All done

Display_Interface      endp                     ;
code    ends


        end
