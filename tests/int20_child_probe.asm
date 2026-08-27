bits 16
org 100h

; A COM image starts with CS equal to its PSP, as required by old-style INT 20h.
int 20h
