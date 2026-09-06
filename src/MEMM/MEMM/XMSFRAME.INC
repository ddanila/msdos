; One steady-state caller frame, separate from bootstrap import packets.
; XAPI v2 reuses the XUMB result fields; Move adds a 16-byte snapshot named
; by +16, capacity=16. All mutations share the existing sequenced journal.
; Query/info/private lookup (08/0E/14) are read-only and require sequence zero.
public XmsCommonRequest, XmsCommonRequestEnd
XmsCommonRequest proc near
        pushad
        push ds
        cmp si,65536-24
        ja frame_bad
        cmp word ptr es:[si+4],2
        jne frame_bad
        cmp word ptr es:[si+8],0
        jne frame_bad
        mov bp,si
        mov ax,VDMCA_GSEL
        mov ds,ax
        mov ax,es:[bp+6]
        cmp ax,2
        je frame_receipt
        cmp ax,8
        jb frame_bad
        cmp ax,14h
        ja frame_bad
        cmp [XmsOwnerActive],1
        jne frame_bad
        cmp ax,10h
        jb frame_handle_owner_ready
        cmp ax,13h
        ja frame_handle_owner_ready
        cmp [XmsUmbActive],1
        jne frame_bad
frame_handle_owner_ready:
        cmp ax,0bh
        jne frame_check_peer
        cmp word ptr es:[bp+18],16
        jne frame_bad
        cmp word ptr es:[bp+16],65536-16
        ja frame_bad
frame_check_peer:
        cmp ax,12h
        jne frame_begin
        mov si,es:[bp+16]
        cmp si,65536-4
        ja frame_bad
        mov cx,es:[bp+18]
        push ds
        push es
        pop ds
        add si,2
        call xms_validate_umb
        pop ds
        jc frame_bad
frame_begin:
        mov dx,es:[bp+12]
        mov bx,es:[bp+14]
        mov ax,es:[bp+6]
        cmp ax,8
        je frame_readonly
        cmp ax,0eh
        je frame_readonly
        cmp ax,14h
        je frame_readonly
        call umb_result_begin
        jc frame_bad
        jmp short frame_dispatch
frame_readonly:
        cmp dword ptr es:[bp+20],0
        jne frame_bad
frame_dispatch:
        mov [XmsCommonActive],1
        mov ax,es:[bp+6]
        mov si,es:[bp+16]
        push bp
        mov bp,ax
        cmp bp,0bh
        jne frame_service
        mov bp,15h              ; public descriptor, not resolved-copy primitive
        push bx
        push dx
        call XmsServiceCore
        pop dx
        cmp ax,1
        jne frame_move_error
        pop bx
        jmp short frame_service_done
frame_move_error:
        add sp,2
        jmp short frame_service_done
frame_service:
        call XmsServiceCore
frame_service_done:
        pop bp
        cmp word ptr es:[bp+6],8
        je frame_complete_read
        cmp word ptr es:[bp+6],0eh
        je frame_complete_read
        cmp word ptr es:[bp+6],14h
        je frame_complete_read
        call umb_result_save
        jc frame_bad
        jmp short frame_write
frame_complete_read:
        mov word ptr es:[bp+8],1
        jmp short frame_write
frame_receipt:
        call umb_result_query
        jc frame_bad
frame_write:
        mov es:[bp+10],ax
        mov es:[bp+12],dx
        mov es:[bp+14],bx
        pop ds
        popad
        clc
        ret
frame_bad:
        pop ds
        popad
        stc
        ret
XmsCommonRequest endp
XmsCommonRequestEnd label near
XmsCommonActive db 0
