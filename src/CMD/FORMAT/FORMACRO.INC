






;
;******************************************************************************
; Message Macro Definitions
;******************************************************************************
;

      EXTRN Display_Interface:near


;-----------------------------------------------------------------------------

Message macro   Message_Name                    ;
                                                ;
        mov     dx,offset data:Message_Name     ;
        call    Display_Interface               ;
        endm                                    ;

;-----------------------------------------------------------------------------

Parse_Message macro                             ;

                                                ;
        push    ds
        mov     dx,data
        mov     ds,dx
        mov     word ptr Parse_Error_Msg,ax     ;
        mov     dx,offset Parse_Error_Msg       ;
        call    Display_Interface               ;
        pop     ds                              ;
        endm                                    ;

;-----------------------------------------------------------------------------

Extended_Message macro                          ;
                                                ;

        push    ds
        mov     dx,data
        mov     ds,dx
        mov     word ptr Extended_Error_Msg,ax       ;
        mov     dx,offset data:Extended_Error_Msg    ;
        call    Display_Interface               ;
        pop     ds
        endm                                    ;

;
;*****************************************************************************
; General Macro's
;*****************************************************************************
;

Procedure       macro   Proc_Name

Public  Proc_Name
Proc_Name    proc

        endm
;-----------------------------------------------------------------------------

DOS_Call        macro   Function

        mov     ah,Function
        int     21h

        endm
;-----------------------------------------------------------------------------

Popff   macro

        jmp     $+3
        iret
        push    cs
        call    $-2

        endm


;-----------------------------------------------------------------------------

Set_Data_Segment     macro

        push    ax
        mov     ax,data                         ;Point to data segment
        mov     ds,ax                           ;
        push    ds
        pop     es
        pop     ax

assume  ds:data,es:data

        endm



