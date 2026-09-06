; Execute the production decoder with distinct code/data and the real device
; stack shape. This is a segment-binding witness, not an HMA/A20 boot test.
.8086
UNIT equ 1
CMD equ 2
MEDIA equ 13
TRANS equ 14
COUNT equ 18
START equ 20
START_L equ 26
START_H equ 28
CODE segment para public 'CODE'
assume cs:CODE
ifdef HMA_TEST
include MSBSEG.INC
endif
main:
        mov ax,cs
        mov ds,ax
        mov word ptr [PTRSAV+2],ax
        mov word ptr [packet+TRANS+2],ax
        mov word ptr [entry_slot+2],ax
ifdef SEPARATE_TEST
        mov ax,seg HIGHCODE
        mov bx,cs
        cmp ax,bx
        je failed
        mov es,ax
        mov word ptr [decoder+2],ax
        mov ax,cs
        mov es:[BIOS_DISPATCH_LOW_SEGMENT],ax
        mov word ptr es:[BIOS_DISPATCH_ERROR_ENTRY+2],ax
ifdef WRONG_ERROR_ENTRY
        mov word ptr es:[BIOS_DISPATCH_ERROR_ENTRY],offset accepted_target
endif
endif
ifdef HMA_TEST
        call install_hma_decoder
        mov al,'B'
        out 0e9h,al
endif
        ; Ordinary disk request clears stale high-sector state.
        mov word ptr [START_SEC_H],0deadH
        call run_request
        cmp word ptr cs:[START_SEC_H],0
        jne failed
        ; Extended disk request uses both words, not the FFFFh sentinel.
        mov byte ptr cs:[failure_code],2
        mov word ptr cs:[packet+START],0ffffh
        mov word ptr cs:[expected_dx],5678h
        call run_request
        cmp word ptr cs:[START_SEC_H],1234h
        jne failed
        ; Non-disk request leaves the disk high word untouched.
        mov byte ptr cs:[failure_code],3
        mov word ptr cs:[table_offset],offset CONTBL
        mov word ptr cs:[expected_dx],0ffffh
        call run_request
        cmp word ptr cs:[START_SEC_H],1234h
        jne failed
        ; Observe a table patched after decoder binding, not a stale copy.
        mov byte ptr cs:[failure_code],4
ifndef STALE_TABLE
        mov word ptr cs:[CONTBL+1+8],offset alternate
endif
        call run_request
        mov byte ptr cs:[failure_code],4
        cmp byte ptr cs:[alternate_seen],1
        jne failed
        ; Reject one past this table's maximum without touching a target.
        mov byte ptr cs:[failure_code],5
        mov byte ptr cs:[packet+CMD],11
        call run_request
        mov byte ptr cs:[packet+CMD],80h
        call run_request
        mov byte ptr cs:[packet+CMD],0ffh
        call run_request
        cmp byte ptr cs:[rejected],3
        jne failed
        cmp byte ptr cs:[accepted],4
        jne failed
ifdef HMA_TEST
        mov al,'P'
        out 0e9h,al
        mov al,10h
        out 0f4h,al
        cli
        hlt
else
        mov ax,4c00h
        int 21h
endif
failed:
ifdef HMA_TEST
        mov al,'F'
        out 0e9h,al
        mov al,11h
        out 0f4h,al
        cli
        hlt
else
        mov al,cs:[failure_code]
        mov ah,4ch
        int 21h
endif

run_request proc near
        mov cs:[saved_sp],sp
        mov ax,1102h
        mov bx,2222h
        mov cx,3333h
        mov dx,4444h
        mov si,5555h
        mov di,6666h
        mov bp,7777h
        mov ds,bx
        mov es,cx
ifdef HMA_TEST
        call force_a20_off
endif
        std
        call dword ptr cs:[entry_slot]
        cmp sp,cs:[saved_sp]
        jne failed
        cmp ax,1102h
        jne failed
        cmp bx,2222h
        jne failed
        cmp cx,3333h
        jne failed
        cmp dx,4444h
        jne failed
        cmp si,5555h
        jne failed
        cmp di,6666h
        jne failed
        cmp bp,7777h
        jne failed
        mov ax,ds
        cmp ax,2222h
        jne failed
        mov ax,es
        cmp ax,3333h
        jne failed
        ret
run_request endp

device_entry proc far
        push si
        mov si,cs:[table_offset]
        push ax
        push cx
        push dx
        push di
        push bp
        push ds
        push es
        push bx
ifdef SEPARATE_TEST
ifdef HMA_TEST
        jmp dispatch_gate
else
        jmp dword ptr cs:[decoder]
endif
else
        include DISPATCH.INC
endif
device_entry endp

alternate:
        inc byte ptr cs:[alternate_seen]
accepted_target:
        mov byte ptr cs:[failure_code],11
        cmp ax,0ab03h
        jne failed
        cmp cx,123
        jne failed
        cmp dx,cs:[expected_dx]
        jne failed
        cmp di,offset buffer
        jne failed
        mov byte ptr cs:[failure_code],12
        mov ax,ds
        mov bx,cs
        cmp ax,bx
        jne failed
        mov ax,es
        cmp ax,bx
        jne failed
        mov byte ptr cs:[failure_code],13
        pushf
        pop ax
        test ax,400h
        jnz failed
        cmp byte ptr [AUXNUM],2
        jne failed
ifdef HMA_TEST
        call check_a20_on
endif
        inc byte ptr [accepted]
        jmp short completion
CMDERR:
ifdef HMA_TEST
        call check_a20_on
endif
        inc byte ptr cs:[rejected]
completion:
        mov byte ptr cs:[failure_code],14
        mov ax,sp
        add ax,22
        cmp ax,cs:[saved_sp]
        jne failed
        pop bx
        pop es
        pop ds
        pop bp
        pop di
        pop dx
        pop cx
        pop ax
        pop si
        retf

entry_slot dw offset device_entry,0
ifdef SEPARATE_TEST
ifndef HMA_TEST
decoder dw offset high_decoder,0
endif
endif
saved_sp dw 0
expected_dx dw 4321h
table_offset dw offset DSKTBL
accepted db 0
rejected db 0
alternate_seen db 0
failure_code db 1
AUXNUM db 0
PTRSAV label dword
        dw offset packet,0
START_SEC_H dw 0
DSKTBL db 24
        dw 25 dup (offset accepted_target)
CONTBL db 10
        dw 11 dup (offset accepted_target)
packet db 30,3,4
        db 10 dup (0)
        db 0abh
        dw offset buffer,0,123,4321h
        dw 0,0,5678h,1234h
buffer db 0
ifdef HMA_TEST
; Same retained-low tail-entry macro and E705h restore used by the BIOS.
BIOS_DEVICE_ENTRY 0,dispatch_gate,decoder,high_decoder
ifdef OMIT_A20_RESTORE
BIOS_HMA_ROM_RESTORE:
        ret
else
        include HIGHROM.INC
endif
hma_sentinel dw 0
low_alias_value dw 0
install_hma_decoder proc near
        mov ax,1236h
        mov cx,offset high_end+2
        int 2fh
        or ax,ax
        jz failed
        mov ax,es
        cmp ax,0ffffh
        jne failed
        mov bx,di
        mov word ptr [decoder],di
        add word ptr [decoder],offset high_decoder
        mov word ptr [decoder+2],0ffffh
        ; The three instruction operands name metadata in the copied block.
        ; Low-owner offsets and the low completion pointer must NOT be rebased.
        mov ax,seg HIGHCODE
        mov ds,ax
        assume ds:HIGHCODE
        add word ptr [BIOS_DISPATCH_DATA_FIXUP1],bx
        add word ptr [BIOS_DISPATCH_DATA_FIXUP2],bx
        add word ptr [BIOS_DISPATCH_ERROR_FIXUP],bx
        xor si,si
        mov cx,offset high_end
        cld
        rep movsb
        push cs
        pop ds
        assume ds:CODE
        mov [hma_sentinel],di
        push ds
        xor ax,ax
        mov ds,ax
        mov si,di
        sub si,16
        mov ax,[si]
        pop ds
        mov [low_alias_value],ax
        not ax
        mov es:[di],ax
        ; No low staging copy may accidentally satisfy the dispatch witness.
        mov ax,seg HIGHCODE
        mov es,ax
        xor di,di
        mov al,0f4h
        mov cx,offset high_end
        rep stosb
        ret
install_hma_decoder endp
force_a20_off proc near
        push ax
        push bx
        push ds
        in al,92h
        and al,0fdh
        out 92h,al
        mov ax,0ffffh
        mov ds,ax
        mov bx,cs:[hma_sentinel]
        mov ax,[bx]
        cmp ax,cs:[low_alias_value]
        jne failed
        pop ds
        pop bx
        pop ax
        ret
force_a20_off endp
check_a20_on proc near
        push ax
        push bx
        push ds
        mov ax,0ffffh
        mov ds,ax
        mov bx,cs:[hma_sentinel]
        mov ax,cs:[low_alias_value]
        not ax
        cmp [bx],ax
        jne failed
        pop ds
        pop bx
        pop ax
        ret
check_a20_on endp
endif
CODE ends
ifdef SEPARATE_TEST
HIGHCODE segment para public 'HIGHCODE'
assume cs:HIGHCODE
BIOS_DISPATCH_LOW_SEGMENT dw 0
BIOS_DISPATCH_ERROR_ENTRY dw offset CMDERR,0
high_decoder:
BIOS_DISPATCH_SEPARATE equ 1
        include DISPATCH.INC
high_end label byte
HIGHCODE ends
endif
STACKSEG segment para stack 'STACK'
        db 512 dup (0)
STACKSEG ends
end main
