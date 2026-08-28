bits 16
org 100h

start:
    ; Commit DOS buffers before asking the keyboard controller to pulse reset.
    mov ah, 0dh
    int 21h

    mov bx, 1
    mov dx, ready
    mov cx, ready_end - ready
    mov ah, 40h
    int 21h

    ; The host issues QEMU's system_reset after observing the message.  Waiting
    ; here makes the reset point deterministic and prevents COMMAND.COM from
    ; modifying the just-flushed filesystem first.
    sti
wait_for_reset:
    hlt
    jmp wait_for_reset

ready db 'WARM_RESET_READY', 13, 10
ready_end:
