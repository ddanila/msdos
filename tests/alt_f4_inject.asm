bits 16
org 100h

; Queue F4 and mark Alt held in the BIOS keyboard state. INTERSVR consumes the
; key and exits through its ordinary Alt+F4 shutdown path.
mov ax, 40h
mov ds, ax
or byte [17h], 08h
mov ax, 0500h
mov cx, 3e00h
int 16h
mov ax, 4c00h
int 21h
