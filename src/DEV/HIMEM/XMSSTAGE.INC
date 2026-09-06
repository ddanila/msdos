; Stage a quiescent allocator context, without publishing it.
; DS = stable source, ES = private destination, same embedding field layout.
; CX/BX = caller-proved readable/writable source/destination record capacities.
; Both contexts and all fields must be backed, physically disjoint and remain
; inaccessible to concurrent mutation. Selector inequality alone is not proof.
; Requires XMSSTATE.INC. CF clear = staged, set = rejected before any write.
; Preserves 16-bit general/segment registers and DF. Source is never modified.
; Copies pool bound, handle count and every active/free record in the limit;
; resets the idle copy workspace (move_length/source/dest, contiguous dwords).
; HMA, A20 and UMB state are separate owners.
; Caller must validate the staged owner before publishing it and keep source
; authoritative until commit. This is not a public XMS API or atomic handoff.
xms_stage_allocator proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        or      bx, bx
        jz      short stage_invalid
        cmp     bx, MAX_HANDLES
        ja      short stage_invalid
        call    xms_validate_owner
        jc      short stage_invalid
        cmp     bx, [handle_limit]
        jb      short stage_invalid
        mov     ax, [handle_limit]
        mov     es:[handle_limit], ax
        mov     cx, ax
        imul    cx, HANDLE_SIZE
        mov     ax, [extended_kb]
        mov     es:[extended_kb], ax
        mov     si, offset handles
stage_record:
        mov     dl, [si]
        mov     es:[si], dl
        inc     si
        loop    stage_record
        xor     ax, ax
        mov     di, offset move_length
        mov     cx, 6
stage_workspace:
        mov     es:[di], ax
        add     di, 2
        loop    stage_workspace
        clc
        jmp     short stage_return
stage_invalid:
        stc
stage_return:
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
xms_stage_allocator endp
