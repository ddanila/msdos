; First AUTOEXEC application: report readiness and exit the test VM.
bits 16
org 100h
    cld
    mov si,marker
.mark:
    lodsb
    test al,al
    jz .marked
    out 0e9h,al
    jmp .mark
.marked:
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    mov ax,4c00h
    int 21h
marker: db '~BOOTBENCH_READY~',10,0
