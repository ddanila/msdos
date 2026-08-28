bits 16
org 100h

start:
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc fail
    mov bx, 40h
    mov ah, 48h
    int 21h
    jc fail
    mov es, ax
    mov word [es:0], 0cafeh
    mov ax, 4c2ah
    int 21h
fail:
    mov ax, 4c7fh
    int 21h

program_end:
