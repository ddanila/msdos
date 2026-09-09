; Installation-only 386 memory test. The legacy BIOS test remains the 286
; and protected-environment fallback. No byte below 1 MiB or above the
; BIOS-reported XMS span is touched. Both patterns cover every dword.
;
; Keep each protected-mode interval to at most 64 KiB; restore real-mode
; addressing, GDTR/IDTR, CR0, A20 and interrupt state before returning to DOS.
        .386p
TEST386_INJECT macro phase
        local skip_fault
ifdef TESTMEM_FAULT
ifndef TESTMEM_FAULT_PATTERN
TESTMEM_FAULT_PATTERN equ 1
endif
if TESTMEM_FAULT_PATTERN eq phase
ifdef TESTMEM_FAULT_PHYSICAL
        mov     edi, TESTMEM_FAULT_PHYSICAL
        sub     edi, ebx
        jc      short skip_fault
        cmp     edi, esi
        jae     short skip_fault
        add     edi, ebx
        xor     byte ptr es:[edi], 1
skip_fault:
else
        xor     byte ptr es:[ebx], 1
endif
endif
endif
endm
TEST386_NMI macro phase
ifdef TESTMEM_NMI_AT
if TESTMEM_NMI_AT eq phase
        int     2
endif
endif
endm
test_memory_386 proc near
        pushfd
        pushad
        push    es
        cld
        mov     byte ptr [test386_result], 0
        mov     [test386_es], es
        ; Explicit 32-bit operand size retains the complete GDTR base.
        db      066h
        sgdt    fword ptr [test386_old_gdtr]
        db      066h
        sidt    fword ptr [test386_old_idtr]
        mov     eax, cr0
        mov     [test386_cr0], eax
        call    query_a20_hardware
        mov     [test386_a20], al
        call    enable_a20
        jc      test386_cleanup
        xor     eax, eax
        mov     ax, cs
        mov     [test386_real_segment], ax
        mov     [test386_nmi_real_segment], ax
        shl     eax, 4
        mov     word ptr [test386_code+2], ax
        shr     eax, 16
        mov     byte ptr [test386_code+4], al
        mov     byte ptr [test386_code+7], ah
        xor     eax, eax
        mov     ax, cs
        shl     eax, 4
        add     eax, offset test386_gdt
        mov     dword ptr [test386_gdtr+2], eax
        add     eax, test386_idt-test386_gdt
        mov     dword ptr [test386_idtr+2], eax
        mov     ebp, [test386_cr0]
        movzx   edx, word ptr [extended_kb]
        shl     edx, 10
        mov     ebx, 00100000h
test386_block:
        mov     esi, edx
        cmp     esi, 00010000h
        jbe     short test386_size_ready
        mov     esi, 00010000h
test386_size_ready:
        pushfd
        cli
        ; A temporary protected interrupt must not inherit real-mode NT or
        ; single-step state. Restore caller flags outside the switch interval.
        pushfd
        pop     eax
        and     eax, 0ffffbeffh
        push    eax
        popfd
        mov     byte ptr [test386_nmi_pending], 0
        db      066h
        lgdt    fword ptr [test386_gdtr]
        ; A dual-layout vector handles NMI on either side of the PE switch.
        ; CMOS port 70h is not readable on all chipsets, so do not guess its
        ; previous NMI mask. Deliver a deferred NMI through the original real
        ; vector once the complete real-mode context is restored.
        db      066h
        lidt    fword ptr [test386_idtr]
        TEST386_NMI 1
        mov     eax, ebp
        or      al, 1
        mov     cr0, eax
        TEST386_NMI 2
        db      0eah
        dw      offset test386_protected, 8
test386_protected::
        TEST386_NMI 3
        mov     ax, 10h
        mov     es, ax
        mov     eax, 0aa55aa55h
        mov     edi, ebx
        mov     ecx, esi
        shr     ecx, 2
        db      067h
        rep     stosd
        TEST386_INJECT 1
        mov     edi, ebx
        mov     ecx, esi
        shr     ecx, 2
        db      067h
        repe    scasd
        jne     short test386_bad
        mov     eax, 055aa55aah
        mov     edi, ebx
        mov     ecx, esi
        shr     ecx, 2
        db      067h
        rep     stosd
        TEST386_INJECT 2
        mov     edi, ebx
        mov     ecx, esi
        shr     ecx, 2
        db      067h
        repe    scasd
        jne     short test386_bad
        mov     byte ptr cs:[test386_result], 1
        jmp     short test386_leave
test386_bad:
        mov     byte ptr cs:[test386_result], 0
test386_leave:
        ; Drop the flat ES limit before returning to ordinary real mode.
        mov     ax, 18h
        mov     es, ax
        mov     eax, ebp
        mov     cr0, eax
        TEST386_NMI 4
        db      0eah
        dw      offset test386_real
test386_real_segment dw 0
test386_real::
        TEST386_NMI 5
        mov     es, [test386_es]
        db      066h
        lgdt    fword ptr [test386_old_gdtr]
        db      066h
        lidt    fword ptr [test386_old_idtr]
        cmp     byte ptr [test386_nmi_pending], 0
        je      short test386_no_nmi
        int     2
test386_no_nmi:
        popfd
        cmp     byte ptr [test386_result], 0
        je      short test386_cleanup
        add     ebx, esi
        sub     edx, esi
        jnz     test386_block
test386_cleanup:
        mov     al, [test386_a20]
        call    set_a20_hardware
        jnc     short test386_restored
        mov     byte ptr [test386_result], 0
test386_restored:
        ; BIOS-backed A20 methods may use their own temporary descriptors too.
        pushfd
        cli
        mov     eax, [test386_cr0]
        mov     cr0, eax
        db      066h
        lgdt    fword ptr [test386_old_gdtr]
        db      066h
        lidt    fword ptr [test386_old_idtr]
        popfd
        pop     es
        popad
        popfd
        cmp     byte ptr cs:[test386_result], 1
        jne     short test386_failure
        clc
        ret
test386_failure:
        stc
        ret
test_memory_386 endp

; NMI can arrive after MOV CR0 but before the far jump changes CS. Normalize
; that transitional return frame to the next phase's valid CS:IP. In the
; stable phase, preserve the interrupted instruction exactly. Neither handler
; calls BIOS code while the machine has temporary descriptors installed.
test386_nmi_protected:
        mov     byte ptr cs:[test386_nmi_pending], 1
        push    bp
        mov     bp, sp
        cmp     word ptr [bp+4], 8
        je      short test386_nmi_pm_return
        mov     word ptr [bp+4], 8
        mov     word ptr [bp+2], offset test386_protected
test386_nmi_pm_return:
        pop     bp
        iret
test386_nmi_real:
        mov     byte ptr cs:[test386_nmi_pending], 1
        push    bp
        mov     bp, sp
        push    ax
        mov     ax, cs
        cmp     word ptr [bp+4], ax
        je      short test386_nmi_rm_return
        mov     word ptr [bp+4], ax
        mov     word ptr [bp+2], offset test386_real
test386_nmi_rm_return:
        pop     ax
        pop     bp
        iret

test386_result db 0
test386_a20 db 0
test386_nmi_pending db 0
test386_es dw 0
test386_cr0 dd 0
test386_old_gdtr df 0
test386_old_idtr df 0
test386_gdtr dw test386_gdt_end-test386_gdt-1
        dd 0
test386_idtr dw test386_idt_end-test386_idt-1
        dd 0
test386_gdt:
        dq 0
test386_code:
        dw 0ffffh,0
        db 0,09ah,0,0
        dw 0ffffh,0
        db 0,092h,0cfh,0
        dw 0ffffh,0
        db 0,092h,0,0
test386_gdt_end label byte
; Real vector 2 occupies bytes 8..11; protected gate 2 occupies bytes 16..23.
; All maskable interrupts stay disabled until the original IDTR is restored.
test386_idt:
        dq 0
        dw offset test386_nmi_real
test386_nmi_real_segment dw 0
        dd 0
        dw offset test386_nmi_protected,8
        db 0,086h
        dw 0
test386_idt_end label byte
        .286
