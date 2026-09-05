; Isolated QEMU fixture: DMA channels 3 and 5 have no requesting device.
; Never use this probe on a machine with active users of those channels.
; Changing the address while page/count still name live EMS windows must not
; remap memory while masked. Test both controllers and preserve byte ordering.
%macro DMA_PHASE 9
    mov al,4+%9
    out %5,al                       ; mask channel
    mov al,40h+%9                  ; single, verify; no device request
    out %4,al
    xor al,al
    out %6,al                       ; clear byte pointer, not mask bits
    mov al,60h
    out %1,al
    mov al,74h
    out %1,al
    mov al,0dh
    out %3,al
    mov al,0ffh
    out %2,al
    mov al,1fh
    out %2,al
    xor al,al
    out %6,al
    mov al,60h                     ; old page + new base + old count
    out %1,al
    mov al,74h
    out %1,al
    xor al,al
    out %3,al                       ; final request is conventional
    out %6,al
    in al,%1
    cmp al,60h
    jne dma_phase_fail
    in al,%1
    cmp al,74h
    jne dma_phase_fail
    in al,%2
    cmp al,0ffh
    jne dma_phase_fail
    in al,%2
    cmp al,1fh
    jne dma_phase_fail
    mov al,%9
    out %5,al                       ; translate before enabling
    mov al,0fh
    out %8,al                       ; all-mask write
    mov al,0fh ^ (1 << %9)
    out %8,al                       ; enable selected channel
    mov al,0fh
    out %8,al
    xor al,al
    out %7,al                       ; clear all masks
    mov al,4+%9
    out %5,al
%endmacro

dma_mask_sequence:
    pusha
    ; First test an explicitly masked request, then repeat after master clear
    ; resets an intentionally odd byte pointer and masks the whole controller.
    DMA_PHASE 06h,07h,82h,0bh,0ah,0ch,0eh,0fh,3
    xor al,al
    out 06h,al
    out 0dh,al
    DMA_PHASE 06h,07h,82h,0bh,0ah,0ch,0eh,0fh,3
    DMA_PHASE 0c4h,0c6h,8bh,0d6h,0d4h,0d8h,0dch,0deh,1
    xor al,al
    out 0c4h,al
    out 0dah,al
    DMA_PHASE 0c4h,0c6h,8bh,0d6h,0d4h,0d8h,0dch,0deh,1
    mov al,0c0h                    ; restore AT cascade channel
    out 0d6h,al
    xor al,al
    out 0d4h,al
    mov dx,dma_phase_passed
    mov ah,09h
    int 21h
    popa
    ret
dma_phase_fail:
    mov dx,dma_phase_failed
    jmp print_fail
dma_phase_passed db 'DMA_PROGRAM_PHASE_PASS',13,10,'$'
dma_phase_failed db 'UMB_FILE_READ_DMA_PHASE_FAIL',13,10,'$'
