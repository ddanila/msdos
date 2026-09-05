; Cold/failed preparation must work with unbound high pointers and no HIMEM.
.8086
_TEXT SEGMENT PARA PUBLIC 'CODE'
ASSUME CS:_TEXT
org 100h
BIOS_SERVICE_LOW_CALLS EQU 1
include MSBSEG.INC
start:
        mov cs:[saved_sp],sp
        stc
        call call_wrapper
        jnc fail
        cmp ax,1111h
        jne fail
        stc
        call jump_wrapper
        jnc fail
        cmp ax,2222h
        jne fail
        cmp word ptr cs:[restore_count],0
        jne fail
        cmp sp,cs:[saved_sp]
        jne fail
        ; Binding by itself must not activate high calls.
        mov word ptr cs:[high_entry],OFFSET BIOS_HMA_ENTER_NEAR
        mov word ptr cs:[high_entry+2],cs
        ; A partially bound call cycle must still select the low service.
        stc
        call call_wrapper
        jnc fail
        cmp ax,1111h
        jne fail
        mov word ptr cs:[high_offset],OFFSET high_service
        mov word ptr cs:[high_jump],OFFSET high_continue
        mov word ptr cs:[high_jump+2],cs
        stc
        call call_wrapper
        jnc fail
        cmp ax,1111h
        jne fail
        cmp word ptr cs:[restore_count],0
        jne fail
        pushf
        cli
        mov byte ptr cs:[BIOS_SERVICE_ACTIVE],1
        popf
        stc
        call call_wrapper
        jnc fail
        cmp ax,3333h
        jne fail
        stc
        call jump_wrapper
        jnc fail
        cmp ax,4444h
        jne fail
        cmp word ptr cs:[restore_count],2
        jne fail
        cmp sp,cs:[saved_sp]
        jne fail
        mov ax,4c00h
        int 21h
fail:
        mov ax,4c01h
        int 21h
call_wrapper:
        BIOS_CALL_HIGH low_service,high_offset,high_entry
        ret
jump_wrapper:
        BIOS_JUMP_HIGH low_continue,high_jump
low_service:
        jnc fail
        mov ax,1111h
        ret
low_continue:
        jnc fail
        mov ax,2222h
        ret
high_service:
        jnc fail
        mov ax,3333h
        ret
high_continue:
        jnc fail
        mov ax,4444h
        ret
BIOS_HMA_ROM_RESTORE:
        pushf
        inc word ptr cs:[restore_count]
        popf
        ret
include HIGHNEAR.INC
BIOS_SERVICE_ACTIVE db 0
high_offset dw 0
high_entry dd 0
high_jump dd 0
saved_sp dw 0
restore_count dw 0
_TEXT ENDS
END start
