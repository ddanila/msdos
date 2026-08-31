bits 16
org 100h

; Queue F1 followed by F4 and mark Alt held in the BIOS keyboard state.
; INTERSVR displays its live status for F1, then consumes Alt+F4 and exits.
mov ax, 40h
mov ds, ax
or byte [17h], 08h
mov ax, 0500h
mov cx, 3b00h
int 16h
mov ax, 0500h
mov cx, 3e00h
int 16h
mov ax, 4c00h
int 21h
