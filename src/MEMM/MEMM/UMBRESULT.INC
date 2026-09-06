; Trusted serialized XUMB v2 result journal. ES:BP is a bounded 24-byte
; packet; DS owns state. Sequence zero is reserved. Only the next sequence
; may begin a service; duplicate/stale submissions never repeat a mutation.
; Publishing sequence with valid=0 BEFORE dispatch distinguishes interrupted
; execution from a request which never began. No new service may bypass it.
umb_result_begin proc near
        cmp word ptr es:[bp+4],2
        je result_sequenced
        cmp [XmsUmbSequence],0
        jne result_begin_bad    ; v1 cannot mutate a sequenced owner
        clc
        ret
result_sequenced:
        cmp [XmsUmbSequence],0
        je result_next
        cmp [XmsUmbResultValid],1
        jne result_begin_bad
result_next:
        mov eax,[XmsUmbSequence]
        inc eax
        jnz result_next_ready
        inc eax
result_next_ready:
        cmp eax,es:[bp+20]
        jne result_begin_bad
IFDEF EMM_UMB_RESULT_DROP_BEFORE
        cmp [XmsUmbDropped],0
        jne result_begin_publish
        cmp word ptr es:[bp+6],10h
        jne result_begin_publish
        cmp dx,1
        jne result_begin_publish
        mov [XmsUmbDropped],1
        jmp short result_begin_bad
result_begin_publish:
ENDIF
        mov [XmsUmbSequence],eax
        mov [XmsUmbResultValid],0
        clc
        ret
result_begin_bad:
        stc
        ret
umb_result_begin endp

umb_result_save proc near
        cmp word ptr es:[bp+4],2
        jne result_saved
        mov [XmsUmbResultAx],ax
        mov [XmsUmbResultDx],dx
        mov [XmsUmbResultBx],bx
IFDEF EMM_UMB_RESULT_UNKNOWN
        cmp [XmsUmbDropped],0
        jne result_mark_complete
        cmp word ptr es:[bp+6],10h
        jne result_mark_complete
        cmp word ptr es:[bp+12],1
        jne result_mark_complete
        cmp ax,1
        jne result_mark_complete
        mov [XmsUmbDropped],1
        stc                     ; mutation happened, but completion stays invalid
        ret
result_mark_complete:
ENDIF
        mov [XmsUmbResultValid],1
        mov word ptr es:[bp+8],1
IFDEF EMM_UMB_RESULT_DROP_AFTER
        cmp [XmsUmbDropped],0
        jne result_saved
        cmp word ptr es:[bp+6],10h
        jne result_saved
        cmp word ptr es:[bp+12],1
        jne result_saved
        cmp ax,1
        jne result_saved
        mov [XmsUmbDropped],1
        stc                     ; result remains available through operation 02
        ret
ENDIF
result_saved:
        clc
        ret
umb_result_save endp

umb_result_query proc near
        cmp word ptr es:[bp+4],2
        jne result_query_bad
        mov eax,es:[bp+20]
        or eax,eax
        jz result_query_bad
        cmp eax,[XmsUmbSequence]
        jne result_query_next
        cmp [XmsUmbResultValid],1
        jne result_query_bad    ; began, but completion is unknown
        mov ax,[XmsUmbResultAx]
        mov dx,[XmsUmbResultDx]
        mov bx,[XmsUmbResultBx]
        mov word ptr es:[bp+8],1
        clc
        ret
result_query_next:
        cmp [XmsUmbSequence],0
        je result_query_expected
        cmp [XmsUmbResultValid],1
        jne result_query_bad
result_query_expected:
        mov ecx,[XmsUmbSequence]
        inc ecx
        jnz result_query_compare
        inc ecx
result_query_compare:
        cmp eax,ecx
        jne result_query_bad
        ; Exactly the next sequence has not begun. No other receipt means
        ; non-execution. Leave the journal untouched and return an error result.
        mov word ptr es:[bp+8],0
        xor ax,ax
        mov bl,ERR_GENERAL
        clc
        ret
result_query_bad:
        stc
        ret
umb_result_query endp

IFDEF EMM_UMB_SEQUENCE_WRAP_TEST
XmsUmbSequence dd 0fffffffeh
XmsUmbResultValid db 1
ELSE
XmsUmbSequence dd 0
XmsUmbResultValid db 0
ENDIF
XmsUmbResultAx dw 0
XmsUmbResultDx dw 0
XmsUmbResultBx dw 0
IFDEF EMM_UMB_RESULT_DROP_BEFORE
XmsUmbDropped db 0
ELSE
IFDEF EMM_UMB_RESULT_DROP_AFTER
XmsUmbDropped db 0
ELSE
IFDEF EMM_UMB_RESULT_UNKNOWN
XmsUmbDropped db 0
ENDIF
ENDIF
ENDIF
