; Execute the production adapter/epilogue with a simulated copy completion.+; This tests the near-call ABI only, not protected copying, NMI or A20.
.model tiny
.386
.code
org 100h
start:
    push cs
    pop ds
    push cs
    pop es
    mov byte ptr [MB_Stat],0
next_case:
    mov byte ptr [restore_calls],0
    mov [saved_sp],sp
    mov word ptr [client_flags],0201h
    mov bp,offset client_flags
    mov ax,0aa55h
    mov bx,1234h
    mov cx,2345h
    mov si,3456h
    mov di,4567h
    call Move_Block_Core
    pushf
    pop dx
    cmp word ptr [client_flags],0201h
    jne failed
    cmp ah,[MB_Stat]
    jne failed
    cmp al,55h
    jne failed
    and dx,FLAGS_CY OR FLAGS_ZF
    cmp byte ptr [MB_Stat],0
    jne expect_failure
    cmp dx,FLAGS_ZF
    jne failed
    jmp check_preserved
expect_failure:
    cmp dx,FLAGS_CY
    jne failed
check_preserved:
    cmp sp,[saved_sp]
    jne failed
    cmp bx,1234h
    jne failed
    cmp cx,2345h
    jne failed
    cmp si,3456h
    jne failed
    cmp di,4567h
    jne failed
    cmp bp,offset client_flags
    jne failed
    cmp byte ptr [MB_ParityOwned],0
    jne failed
    mov al,[owned_case]
    cmp al,[restore_calls]
    jne failed
    call Move_Block
    cmp sp,[saved_sp]
    jne failed
    cmp byte ptr [MB_Stat],0
    jne expect_client_failure
    cmp word ptr [client_flags],0240h
    jne failed
    jmp case_done
expect_client_failure:
    cmp word ptr [client_flags],0201h
    jne failed
case_done:
    cmp byte ptr [MB_ParityOwned],0
    jne failed
    mov al,[owned_case]
    shl al,1
    cmp al,[restore_calls]
    jne failed
    inc byte ptr [MB_Stat]
    cmp byte ptr [MB_Stat],4
    jb next_case
    inc byte ptr [owned_case]
    mov byte ptr [MB_Stat],0
    cmp byte ptr [owned_case],2
    jb next_case
    mov al,'B'
    out 0e9h,al
    mov al,'C'
    out 0e9h,al
    mov ax,10h
    jmp done
failed:
    mov al,'F'
    out 0e9h,al
    mov ax,11h
done:
    mov dx,0f4h
    out dx,ax
    cli
    hlt

; Match the production save frame; no VMTF is created for the direct call.
Move_Block_Core proc near
    push ds
    push es
    push eax
    push cx
    push si
    push di
    mov al,[owned_case]
    mov [MB_ParityOwned],al
    jmp MB_Exit
Move_Block_Core endp
Rest_Par_Vect proc near
    inc byte ptr [restore_calls]
    ret
Rest_Par_Vect endp
POP_EAX macro
    pop eax
endm
FLAGS_CY equ 1
FLAGS_ZF equ 40h
VTFOE equ 0
; Preserve the production field's WORD type for the extracted adapter.
VM_TRAP_FRAME struc
VMTF_EFLAGS dw ?
VM_TRAP_FRAME ends
include COPY_ABI.INC
MB_Stat db 0
MB_ParityOwned db 0
owned_case db 0
restore_calls db 0
saved_sp dw 0
client_flags dw 0
end start
