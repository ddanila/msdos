; criterr.asm -- standalone INT 24h critical-error handler for ATTRIB, extracted
; from the old attriba.asm (XCMAIN startup) so it can be used with OW's cstart
; entry (option b). wcc small-model segments (_TEXT / DGROUP).
        .8086
ABORT      equ 2
RET_EXIT   equ 4ch
XABORT     equ 1

DGROUP  group _DATA
_DATA   segment word public 'DATA'
_DATA   ends

_TEXT   segment byte public 'CODE'
        assume cs:_TEXT
        public _crit_err_handler
        extrn  _old_int24_off:dword
        extrn  _Reset_appendx:near
vector  dd 0
_crit_err_handler proc near
        pushf
        push  ax
        push  ds
        mov   ax,DGROUP
        mov   ds,ax
        mov   ax,word ptr ds:_old_int24_off
        mov   word ptr cs:vector,ax
        mov   ax,word ptr ds:_old_int24_off+2
        mov   word ptr cs:vector+2,ax
        pop   ds
        pop   ax
        call  dword ptr cs:vector
        cmp   al,ABORT
        jnge  retry
        mov   ax,DGROUP
        mov   ds,ax
        mov   es,ax
        call  _Reset_appendx
        mov   ax,(RET_EXIT shl 8)+XABORT
        int   21h
retry:
        iret
_crit_err_handler endp
_TEXT   ends
        end
