; DOS 5 DIR extensions live after the inherited transient workspace.  Keeping
; this segment last preserves legacy workspace offsets below 8000h.

	INCLUDE comsw.asm
.xlist
.xcref
	INCLUDE DOSSYM.INC
	INCLUDE comseg.asm
	INCLUDE comequ.asm
.list
.cref

TRANCODE SEGMENT PUBLIC BYTE
	EXTRN find_name_in_environment:near
	EXTRN dir_display_record:near
TRANCODE ENDS

TRANDATA SEGMENT PUBLIC BYTE
	EXTRN file_optional2:byte
	EXTRN slash_p_switch:byte
	EXTRN no_values:word
TRANDATA ENDS

TRANSPACE SEGMENT PUBLIC BYTE
	EXTRN arg_buf:byte
	EXTRN bits:word
	EXTRN dirbuf:byte
	EXTRN filecnt:word
	EXTRN lincnt:byte
	EXTRN linlen:byte
	EXTRN parse1_addr:dword
	EXTRN parse1_output:byte
	EXTRN parse1_syn:word
	EXTRN parse1_type:byte
TRANSPACE ENDS

TRANEXT SEGMENT PUBLIC BYTE
	ASSUME cs:TRANGROUP,ds:TRANGROUP,es:TRANGROUP

	PUBLIC dir_prepare
	PUBLIC dir_next_source
	PUBLIC dir_apply_negative
	PUBLIC dir_sort_all
	PUBLIC dir_sort_next
	PUBLIC dir_sort_finish
	PUBLIC dir_recursive_capture
	PUBLIC dir_recursive_run
	PUBLIC dir_print_bare_prefix
	PUBLIC dir_external_record
	PUBLIC dir_recursive_selected
	PUBLIC parse_dir
	PUBLIC dir_w_syn
	PUBLIC dir_b_syn
	PUBLIC dir_l_syn
	PUBLIC dir_a_syn
	PUBLIC dir_attr_require
	PUBLIC dir_attr_deny
	PUBLIC dir_attr_selected
	PUBLIC dir_seen
	PUBLIC dir_parse_phase
	PUBLIC dir_help_str

dir_help_str DB "Displays a list of files and subdirectories in a directory.",13,10
	DB 13,10
	DB "DIR [drive:][path][filename] [/P] [/W] [/A[:attributes]]",13,10
	DB "    [/O[:sortorder]] [/S] [/B] [/L]",13,10
	DB 13,10
	DB "  [drive:][path][filename]  Specifies drive, directory, and/or files",13,10
	DB "                            to list.",13,10
	DB "  /P  Pauses after each screenful of information.",13,10
	DB "  /W  Uses wide list format.",13,10
	DB "  /B  Uses bare format (no heading information or summary).",13,10
	DB "  /L  Uses lowercase.",13,10
	DB "  /A  Displays files with specified D, R, H, A, or S attributes.",13,10
	DB "      Prefix an attribute with - to exclude it.",13,10
	DB "  /O  Sorts by N=name, E=extension, D=date, S=size, or G=directories.",13,10
	DB "      Prefix a sort key with - to reverse it.",13,10
	DB "  /S  Lists matching files in this directory and all subdirectories.",13,10,'$'

parse_dir LABEL BYTE
	DW TRANGROUP:dir_parms
	DB 0
dir_parms LABEL BYTE
	DB 0,1
	DW TRANGROUP:file_optional2
	DB 14
	DW TRANGROUP:slash_p_switch
	DW TRANGROUP:dir_switch_w
	DW TRANGROUP:dir_switch_b
	DW TRANGROUP:dir_switch_l
	DW TRANGROUP:dir_switch_a
	DW TRANGROUP:dir_switch_nw
	DW TRANGROUP:dir_switch_np
	DW TRANGROUP:dir_switch_nb
	DW TRANGROUP:dir_switch_nl
	DW TRANGROUP:dir_switch_na
	DW TRANGROUP:dir_switch_o
	DW TRANGROUP:dir_switch_s
	DW TRANGROUP:dir_switch_no
	DW TRANGROUP:dir_switch_ns
	DB 0

dir_switch_w LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_w_syn DB '/W',0
dir_switch_b LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_b_syn DB '/B',0
dir_switch_l LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_l_syn DB '/L',0
dir_switch_a LABEL BYTE
	DW 2001h,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_a_syn DB '/A',0
dir_switch_nw LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_nw_syn DB '/-W',0
dir_switch_np LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_np_syn DB '/-P',0
dir_switch_nb LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_nb_syn DB '/-B',0
dir_switch_nl LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_nl_syn DB '/-L',0
dir_switch_na LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_na_syn DB '/-A',0
dir_switch_o LABEL BYTE
	DW 2001h,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_o_syn DB '/O',0
dir_switch_s LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_s_syn DB '/S',0
dir_switch_no LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_no_syn DB '/-O',0
dir_switch_ns LABEL BYTE
	DW 0,2,TRANGROUP:parse1_output,TRANGROUP:no_values
	DB 1
dir_ns_syn DB '/-S',0

dir_attr_require DB 0
dir_attr_deny DB 0
dir_attr_selected DB 0
dir_seen DW 0
dir_parse_phase DB 0
dir_sort_selected DB 0
dir_recursive_selected DB 0
dir_sort_count DW 0
dir_sort_index DW 0
dir_sort_segment DW 0
dir_sort_capacity DW 0
dir_sort_end_error DW 0
dir_sort_failed DB 0
dir_sort_keys DB 5 DUP(0)
dir_sort_key_count DB 0
dir_external_record DB 0
dir_recursive_ready DB 0
dir_recursive_depth DB 0
dir_recursive_error DB 0
dir_recursive_drive DB 0
dir_recursive_current DW 0
dir_recursive_pattern DB 13 DUP(0)
dircmd_text DB 'DIRCMD=',0

; Return SI at DIRCMD's copied value, or at the PSP command tail if unset.
dir_prepare:
	mov dir_sort_selected,0
	mov dir_recursive_selected,0
	mov dir_sort_key_count,0
	mov dir_sort_segment,0
	mov dir_sort_failed,0
	mov si,OFFSET TRANGROUP:dircmd_text
	call find_name_in_environment
	jc dir_no_defaults
	mov bx,di
	mov di,OFFSET TRANGROUP:arg_buf
	mov cx,126
dir_copy_defaults:
	mov al,es:[bx]
	inc bx
	or al,al
	jz dir_defaults_done
	mov ds:[di],al
	inc di
	loop dir_copy_defaults
dir_defaults_done:
	mov byte ptr ds:[di],end_of_line_in
	push ds
	pop es
	mov si,OFFSET TRANGROUP:arg_buf
	mov dir_parse_phase,1
	ret
dir_no_defaults:
	push ds
	pop es
	mov si,81h
	mov dir_parse_phase,0
	ret

; Carry requests another parser pass over the explicit PSP command tail.
dir_next_source:
	cmp dir_parse_phase,0
	je dir_sources_done
	mov dir_parse_phase,0
	mov dir_seen,0
	mov si,81h
	xor cx,cx
	stc
	ret
dir_sources_done:
	clc
	ret

; AL=0 means the parsed item was not negative; AL=1 applied; AL=2 duplicate.
dir_apply_negative:
	mov ax,parse1_syn
	cmp ax,OFFSET TRANGROUP:dir_o_syn
	je dir_set_order
	cmp ax,OFFSET TRANGROUP:dir_s_syn
	je dir_set_recursive
	cmp ax,OFFSET TRANGROUP:dir_nw_syn
	je dir_clear_width
	cmp ax,OFFSET TRANGROUP:dir_np_syn
	je dir_clear_pause
	cmp ax,OFFSET TRANGROUP:dir_nb_syn
	je dir_clear_bare
	cmp ax,OFFSET TRANGROUP:dir_nl_syn
	je dir_clear_lower
	cmp ax,OFFSET TRANGROUP:dir_na_syn
	je dir_clear_attr
	cmp ax,OFFSET TRANGROUP:dir_no_syn
	je dir_clear_order
	cmp ax,OFFSET TRANGROUP:dir_ns_syn
	je dir_clear_recursive
	xor al,al
	ret

dir_clear_width:
	mov dx,SwitchW
	call dir_negative_seen
	jc dir_negative_duplicate
	and bits,NOT SwitchW
	mov linlen,normperlin
	mov lincnt,normperlin
	jmp dir_negative_done
dir_clear_pause:
	mov dx,SwitchP
	call dir_negative_seen
	jc dir_negative_duplicate
	and bits,NOT SwitchP
	jmp dir_negative_done
dir_clear_bare:
	mov dx,SwitchDirB
	call dir_negative_seen
	jc dir_negative_duplicate
	and bits,NOT SwitchDirB
	test bits,SwitchW
	jz dir_clear_bare_normal
	mov linlen,wideperlin
	mov lincnt,wideperlin
	jmp dir_negative_done
dir_clear_bare_normal:
	mov linlen,normperlin
	mov lincnt,normperlin
	jmp dir_negative_done
dir_clear_lower:
	mov dx,SwitchDirL
	call dir_negative_seen
	jc dir_negative_duplicate
	and bits,NOT SwitchDirL
	jmp dir_negative_done
dir_clear_attr:
	mov dx,0400h
	call dir_negative_seen
	jc dir_negative_duplicate
	mov dir_attr_selected,0
	mov dir_attr_require,0
	mov dir_attr_deny,0
	jmp dir_negative_done
dir_clear_order:
	mov dx,0800h
	call dir_negative_seen
	jc dir_negative_duplicate
	mov dir_sort_selected,0
	mov dir_sort_key_count,0
	jmp dir_negative_done
dir_clear_recursive:
	mov dx,1000h
	call dir_negative_seen
	jc dir_negative_duplicate
	mov dir_recursive_selected,0
	jmp dir_negative_done
dir_negative_done:
	mov al,1
	ret
dir_negative_duplicate:
	mov al,2
	ret
dir_negative_seen:
	test dir_seen,dx
	jnz dir_negative_seen_duplicate
	or dir_seen,dx
	clc
	ret
dir_negative_seen_duplicate:
	stc
	ret

dir_set_recursive:
	mov dx,1000h
	call dir_negative_seen
	jc dir_negative_duplicate
	mov dir_recursive_selected,1
	jmp dir_negative_done

dir_set_order:
	mov dx,0800h
	call dir_negative_seen
	jc dir_negative_duplicate
	mov dir_sort_selected,1
	mov dir_sort_key_count,0
	cmp parse1_type,result_string
	je dir_parse_order_value
	mov byte ptr dir_sort_keys,'G'
	mov byte ptr dir_sort_keys+1,'N'
	mov dir_sort_key_count,2
	jmp dir_negative_done
dir_parse_order_value:
	push ds
	push si
	lds si,parse1_addr
	xor bx,bx
	xor dx,dx                    ; DL: reverse next key
dir_order_loop:
	lodsb
	or al,al
	jz dir_order_complete
	cmp al,'-'
	jne dir_order_letter
	or dl,dl
	jnz dir_order_invalid
	mov dl,80h
	jmp dir_order_loop
dir_order_letter:
	cmp al,'N'
	je dir_order_valid
	cmp al,'E'
	je dir_order_valid
	cmp al,'D'
	je dir_order_valid
	cmp al,'S'
	je dir_order_valid
	cmp al,'G'
	jne dir_order_invalid
dir_order_valid:
	cmp bl,5
	jae dir_order_invalid
	or al,dl
	mov cs:[dir_sort_keys+bx],al
	inc bl
	xor dl,dl
	jmp dir_order_loop
dir_order_complete:
	or dl,dl
	jnz dir_order_invalid
	or bl,bl
	jz dir_order_invalid
	mov cs:dir_sort_key_count,bl
	pop si
	pop ds
	jmp dir_negative_done
dir_order_invalid:
	pop si
	pop ds
	jmp dir_negative_duplicate       ; common parser-error result

; Consume the current FCB result and the rest of its search into a DOS
; allocation, order the 32-byte directory records, and expose record zero.
dir_sort_all:
	cmp dir_sort_selected,0
	jne dir_sort_allocate
	clc
	ret
dir_sort_allocate:
	mov dir_sort_count,0
	mov dir_sort_index,0
	mov dir_sort_failed,0
	mov dir_sort_segment,cs
	mov dir_sort_capacity,256
dir_sort_collect:
	mov ax,dir_sort_count
	cmp ax,dir_sort_capacity
	jae dir_sort_overflow
	mov di,ax
	mov cl,5
	shl di,cl
	add di,OFFSET TRANGROUP:dir_sort_buffer
	mov ax,dir_sort_segment
	mov es,ax
	mov si,OFFSET TRANGROUP:dirbuf+8
	mov cx,16
	rep movsw
	push ds
	pop es
	inc dir_sort_count
	mov ah,Dir_Search_Next
	mov dx,FCB-7
	int int_command
	inc al
	jnz dir_sort_collect
	mov dir_sort_end_error,error_no_more_files
	call dir_sort_records
	mov dir_sort_index,0
	call dir_sort_copy_current
	xor al,al
	stc
	ret
dir_sort_overflow:
dir_sort_alloc_fail:
	mov dir_sort_segment,0
	mov dir_sort_failed,1
	mov al,0ffh
	stc
	ret

dir_sort_next:
	cmp dir_sort_segment,0
	je dir_sort_next_dos
	inc dir_sort_index
	mov ax,dir_sort_index
	cmp ax,dir_sort_count
	jae dir_sort_next_end
	call dir_sort_copy_current
	xor al,al
	stc
	ret
dir_sort_next_end:
	mov al,0ffh
	stc
	ret
dir_sort_next_dos:
	clc
	ret

dir_sort_copy_current:
	mov si,dir_sort_index
	mov cl,5
	shl si,cl
	add si,OFFSET TRANGROUP:dir_sort_buffer
	mov ax,dir_sort_segment
	mov ds,ax
	push cs
	pop es
	mov di,OFFSET TRANGROUP:dirbuf+8
	mov cx,16
	rep movsw
	push es
	pop ds
	ret

; Carry means AX already contains the final sorted-search status.
dir_sort_finish:
	cmp dir_sort_failed,0
	jne dir_sort_finish_nomem
	mov ax,dir_sort_segment
	or ax,ax
	jz dir_sort_finish_dos
	mov dir_sort_segment,0
	mov ax,dir_sort_end_error
	stc
	ret
dir_sort_finish_nomem:
	mov dir_sort_failed,0
	mov ax,error_not_enough_memory
	stc
	ret
dir_sort_finish_dos:
	cmp dir_recursive_selected,0
	je dir_sort_finish_plain_dos
	mov ax,error_no_more_files
	stc
	ret
dir_sort_finish_plain_dos:
	clc
	ret

dir_sort_records:
	mov ax,dir_sort_count
	cmp ax,1
	jbe dir_sort_records_done
	dec ax
	mov bp,ax
dir_sort_pass:
	mov si,OFFSET TRANGROUP:dir_sort_buffer
	mov di,OFFSET TRANGROUP:dir_sort_buffer+32
	mov cx,bp
	xor bl,bl
dir_sort_pair:
	call dir_sort_compare
	jnc dir_sort_no_swap
	call dir_sort_swap
	mov bl,1
dir_sort_no_swap:
	add si,32
	add di,32
	loop dir_sort_pair
	or bl,bl
	jz dir_sort_records_done
	dec bp
	jnz dir_sort_pass
dir_sort_records_done:
	ret

dir_sort_swap:
	push cx
	push si
	push di
	mov ax,dir_sort_segment
	mov es,ax
	mov cx,32
dir_sort_swap_byte:
	mov al,es:[si]
	mov dl,es:[di]
	mov es:[si],dl
	mov es:[di],al
	inc si
	inc di
	loop dir_sort_swap_byte
	push ds
	pop es
	pop di
	pop si
	pop cx
	ret

; Compare records ES:SI and ES:DI.  Carry means the left record sorts after
; the right record according to the ordered key list.
dir_sort_compare:
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	mov ax,dir_sort_segment
	mov es,ax
	xor bx,bx
dir_sort_compare_key:
	cmp bl,dir_sort_key_count
	jae dir_sort_compare_equal
	mov al,cs:[dir_sort_keys+bx]
	mov ah,al
	and al,7fh
	cmp al,'G'
	je dir_sort_compare_group
	cmp al,'N'
	je dir_sort_compare_name
	cmp al,'E'
	je dir_sort_compare_ext
	cmp al,'D'
	je dir_sort_compare_date
	jmp short dir_sort_compare_size

dir_sort_compare_group:
	mov dl,es:[si+11]
	mov dh,es:[di+11]
	and dl,attr_directory
	and dh,attr_directory
	cmp dl,dh
	je dir_sort_compare_next
	or dl,dl
	jnz dir_sort_compare_less
	jmp short dir_sort_compare_greater
dir_sort_compare_name:
	mov cx,11
	push si
	push di
	jmp short dir_sort_compare_bytes
dir_sort_compare_ext:
	mov cx,3
	push si
	push di
	add si,8
	add di,8
dir_sort_compare_bytes:
	mov dl,es:[si]
	mov dh,es:[di]
	cmp dl,dh
	jne dir_sort_compare_bytes_diff
	inc si
	inc di
	loop dir_sort_compare_bytes
	pop di
	pop si
	jmp short dir_sort_compare_next
dir_sort_compare_bytes_diff:
	pop di
	pop si
	jb dir_sort_compare_less
	jmp short dir_sort_compare_greater
dir_sort_compare_date:
	mov dx,es:[si+24]
	cmp dx,es:[di+24]
	jb dir_sort_compare_less
	ja dir_sort_compare_greater
	mov dx,es:[si+22]
	cmp dx,es:[di+22]
	jb dir_sort_compare_less
	ja dir_sort_compare_greater
	jmp short dir_sort_compare_next
dir_sort_compare_size:
	mov dx,es:[si+30]
	cmp dx,es:[di+30]
	jb dir_sort_compare_less
	ja dir_sort_compare_greater
	mov dx,es:[si+28]
	cmp dx,es:[di+28]
	jb dir_sort_compare_less
	ja dir_sort_compare_greater
	jmp short dir_sort_compare_next
dir_sort_compare_less:
	mov dl,0ffh
	jmp short dir_sort_compare_direction
dir_sort_compare_greater:
	mov dl,1
dir_sort_compare_direction:
	test ah,80h
	jz dir_sort_compare_result
	neg dl
dir_sort_compare_result:
	cmp dl,1
	je dir_sort_compare_after
	jmp short dir_sort_compare_before
dir_sort_compare_next:
	inc bl
	jmp dir_sort_compare_key
dir_sort_compare_equal:
dir_sort_compare_before:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	clc
	ret
dir_sort_compare_after:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	stc
	ret

; Capture the absolute directory selected by PATHCRUNCH while it is still the
; active directory, plus the parsed FCB wildcard used for every descendant.
dir_recursive_capture:
	cmp dir_recursive_selected,0
	jne dir_recursive_capture_go
	mov dir_recursive_ready,0
	ret
dir_recursive_capture_go:
	push es
	push ds
	pop es
	mov al,ds:[FCB]
	or al,al
	jnz dir_recursive_have_drive
	mov ah,19h
	int int_command
	inc al
dir_recursive_have_drive:
	mov dir_recursive_drive,al
	mov di,OFFSET TRANGROUP:dir_recursive_paths
	add al,'A'-1
	mov [di],al
	mov byte ptr [di+1],':'
	mov byte ptr [di+2],'\'
	lea si,[di+3]
	mov dl,dir_recursive_drive
	mov ah,47h
	int int_command
	jnc dir_recursive_pattern_start
	mov byte ptr [di+3],0
dir_recursive_pattern_start:
	mov si,FCB+1
	mov di,OFFSET TRANGROUP:dir_recursive_pattern
	mov cx,8
dir_recursive_pattern_name:
	lodsb
	cmp al,' '
	je dir_recursive_pattern_ext
	stosb
	loop dir_recursive_pattern_name
dir_recursive_pattern_ext:
	mov si,FCB+9
	cmp byte ptr [si],' '
	je dir_recursive_pattern_done
	mov al,'.'
	stosb
	mov cx,3
dir_recursive_pattern_ext_loop:
	lodsb
	cmp al,' '
	je dir_recursive_pattern_done
	stosb
	loop dir_recursive_pattern_ext_loop
dir_recursive_pattern_done:
	xor al,al
	stosb
	mov dir_recursive_ready,1
	pop es
	ret

dir_recursive_run:
	cmp dir_recursive_ready,0
	jne dir_recursive_run_go
	ret
dir_recursive_run_go:
	mov dir_recursive_ready,0
	mov dir_recursive_error,0
	mov dir_recursive_depth,0
	mov si,OFFSET TRANGROUP:dir_recursive_paths
	call dir_recursive_walk
	mov dir_external_record,0
	ret

; DS:SI points at the current absolute directory.  Enumerate each child,
; list its matching entries, then recurse while preserving FindNext state in
; the depth-specific DTA slot.
dir_recursive_walk:
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	push bp
	mov bp,si
	call dir_recursive_build_all_search
	call dir_recursive_parent_dta
	mov dx,di
	mov ah,1ah
	int int_command
	mov dx,OFFSET TRANGROUP:dir_recursive_search
	mov cx,attr_hidden+attr_system+attr_directory
	mov ah,4eh
	int int_command
	jc dir_recursive_walk_done
dir_recursive_child_loop:
	call dir_recursive_parent_dta
	mov al,[di+21]
	test al,attr_directory
	jz dir_recursive_child_next
	lea si,[di+30]
	cmp byte ptr [si],'.'
	jne dir_recursive_have_child
	cmp byte ptr [si+1],0
	je dir_recursive_child_next
	cmp byte ptr [si+1],'.'
	jne dir_recursive_have_child
	cmp byte ptr [si+2],0
	je dir_recursive_child_next
dir_recursive_have_child:
	mov si,bp
	call dir_recursive_child_slot
	jc dir_recursive_child_next
	push bp
	mov bx,di
	call dir_recursive_copy_path
	jc dir_recursive_child_path_long
	mov bp,bx
	mov si,bx
	call dir_recursive_list
	cmp dir_recursive_error,0
	jne dir_recursive_child_abort
	cmp dir_recursive_depth,15
	jae dir_recursive_child_no_descent
	inc dir_recursive_depth
	mov si,bp
	call dir_recursive_walk
	dec dir_recursive_depth
dir_recursive_child_no_descent:
	pop bp
	jmp short dir_recursive_child_restore
dir_recursive_child_abort:
	pop bp
	jmp short dir_recursive_walk_done
dir_recursive_child_path_long:
	pop bp
	jmp short dir_recursive_child_restore
dir_recursive_child_restore:
	call dir_recursive_parent_dta
	mov dx,di
	mov ah,1ah
	int int_command
dir_recursive_child_next:
	mov ah,4fh
	int int_command
	jnc dir_recursive_child_loop
dir_recursive_walk_done:
	pop bp
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret

; Return DI at this depth's 43-byte directory-search DTA.
dir_recursive_parent_dta:
	xor ax,ax
	mov al,dir_recursive_depth
	mov bx,43
	mul bx
	mov di,OFFSET TRANGROUP:dir_recursive_dtas
	add di,ax
	ret

; Return DI at the next 68-byte path slot and carry at the depth bound.
dir_recursive_child_slot:
	mov al,dir_recursive_depth
	cmp al,15
	jae dir_recursive_child_slot_fail
	inc al
	xor ah,ah
	mov bx,68
	mul bx
	mov di,OFFSET TRANGROUP:dir_recursive_paths
	add di,ax
	clc
	ret
dir_recursive_child_slot_fail:
	stc
	ret

; SI=current path, DI=child slot, parent DTA selected by current depth.
dir_recursive_copy_path:
	push bx
	mov cx,67
dir_recursive_copy_parent:
	lodsb
	or al,al
	jz dir_recursive_copy_separator
	jcxz dir_recursive_copy_too_long
	stosb
	dec cx
	jmp dir_recursive_copy_parent
dir_recursive_copy_separator:
	cmp byte ptr [di-1],'\'
	je dir_recursive_copy_name
	jcxz dir_recursive_copy_too_long
	mov al,'\'
	stosb
	dec cx
dir_recursive_copy_name:
	push di
	call dir_recursive_parent_dta
	lea si,[di+30]
	pop di
dir_recursive_copy_name_loop:
	lodsb
	or al,al
	jz dir_recursive_copy_terminator
	jcxz dir_recursive_copy_too_long
	mov [di],al
	inc di
	dec cx
	jmp dir_recursive_copy_name_loop
dir_recursive_copy_terminator:
	mov byte ptr [di],0
	pop bx
	clc
	ret
dir_recursive_copy_too_long:
	pop bx
	stc
	ret

dir_recursive_build_all_search:
	mov di,OFFSET TRANGROUP:dir_recursive_search
	call dir_recursive_copy_asciiz_prefix
	cmp byte ptr [di-1],'\'
	je dir_recursive_all_suffix
	mov al,'\'
	stosb
dir_recursive_all_suffix:
	mov al,'*'
	stosb
	mov al,'.'
	stosb
	mov al,'*'
	stosb
	xor al,al
	stosb
	ret

; Copy DS:SI to DS:DI, leaving DI on the terminating byte.
dir_recursive_copy_asciiz_prefix:
	lodsb
	or al,al
	jz dir_recursive_prefix_done
	stosb
	jmp dir_recursive_copy_asciiz_prefix
dir_recursive_prefix_done:
	ret

dir_recursive_list:
	mov dir_recursive_current,si
	test bits,SwitchDirB
	jnz dir_recursive_list_search
	call dir_recursive_print_header
dir_recursive_list_search:
	mov si,dir_recursive_current
	mov di,OFFSET TRANGROUP:dir_recursive_search
	call dir_recursive_copy_asciiz_prefix
	cmp byte ptr [di-1],'\'
	je dir_recursive_pattern_suffix
	mov al,'\'
	stosb
dir_recursive_pattern_suffix:
	mov si,OFFSET TRANGROUP:dir_recursive_pattern
dir_recursive_pattern_copy:
	lodsb
	stosb
	or al,al
	jnz dir_recursive_pattern_copy
	mov dx,OFFSET TRANGROUP:dir_recursive_file_dta
	mov ah,1ah
	int int_command
	mov cx,attr_directory
	cmp dir_attr_selected,0
	je dir_recursive_find
	mov cx,attr_hidden+attr_system+attr_directory
dir_recursive_find:
	mov dx,OFFSET TRANGROUP:dir_recursive_search
	mov ah,4eh
	int int_command
	jc dir_recursive_list_done
	mov dir_sort_count,0
	mov dir_sort_segment,cs
dir_recursive_file_loop:
	mov si,OFFSET TRANGROUP:dir_recursive_file_dta
	call dir_recursive_skip_dots
	jc dir_recursive_file_next
	cmp dir_sort_selected,0
	je dir_recursive_display_direct
	mov ax,dir_sort_count
	cmp ax,256
	jae dir_recursive_list_overflow
	mov di,ax
	mov cl,5
	shl di,cl
	add di,OFFSET TRANGROUP:dir_sort_buffer
	call dir_recursive_convert
	inc dir_sort_count
	jmp short dir_recursive_file_next
dir_recursive_display_direct:
	mov di,OFFSET TRANGROUP:dirbuf+8
	call dir_recursive_convert
	call dir_recursive_emit_record
dir_recursive_file_next:
	mov ah,4fh
	int int_command
	jnc dir_recursive_file_loop
	cmp dir_sort_selected,0
	je dir_recursive_list_done
	call dir_sort_records
	mov dir_sort_index,0
dir_recursive_sorted_loop:
	mov ax,dir_sort_index
	cmp ax,dir_sort_count
	jae dir_recursive_list_done
	call dir_sort_copy_current
	call dir_recursive_emit_record
	inc dir_sort_index
	jmp dir_recursive_sorted_loop
dir_recursive_list_overflow:
	mov dir_recursive_error,error_not_enough_memory
	mov dx,OFFSET TRANGROUP:dir_recursive_memory_msg
	mov ah,09h
	int int_command
dir_recursive_list_done:
	mov dir_sort_segment,0
	ret

dir_recursive_skip_dots:
	cmp byte ptr [si+30],'.'
	jne dir_recursive_not_dot
	cmp byte ptr [si+31],0
	je dir_recursive_is_dot
	cmp byte ptr [si+31],'.'
	jne dir_recursive_not_dot
	cmp byte ptr [si+32],0
	je dir_recursive_is_dot
dir_recursive_not_dot:
	clc
	ret
dir_recursive_is_dot:
	stc
	ret

; Convert DOS 4Eh DTA at DS:SI to a 32-byte FCB directory record at DS:DI.
dir_recursive_convert:
	push es
	push ds
	pop es
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	mov bx,di
	mov cx,32
	xor al,al
	rep stosb
	mov di,bx
	mov cx,11
	mov al,' '
	rep stosb
	mov al,[si+21]
	mov [bx+11],al
	mov ax,[si+22]
	mov [bx+22],ax
	mov ax,[si+24]
	mov [bx+24],ax
	mov ax,[si+26]
	mov [bx+28],ax
	mov ax,[si+28]
	mov [bx+30],ax
	lea si,[si+30]
	mov di,bx
	mov cx,8
dir_recursive_convert_name:
	lodsb
	or al,al
	jz dir_recursive_convert_done
	cmp al,'.'
	je dir_recursive_convert_ext
	stosb
	loop dir_recursive_convert_name
dir_recursive_convert_seek_dot:
	lodsb
	or al,al
	jz dir_recursive_convert_done
	cmp al,'.'
	jne dir_recursive_convert_seek_dot
dir_recursive_convert_ext:
	mov di,bx
	add di,8
	mov cx,3
dir_recursive_convert_ext_loop:
	lodsb
	or al,al
	jz dir_recursive_convert_done
	stosb
	loop dir_recursive_convert_ext_loop
dir_recursive_convert_done:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	pop es
	ret

dir_recursive_emit_record:
	push es
	push ds
	pop es
	mov dir_external_record,1
	call dir_display_record
	mov dir_external_record,0
	pop es
	ret

dir_recursive_print_header:
	call dir_recursive_newline
	mov si,OFFSET TRANGROUP:dir_recursive_header
	call dir_recursive_print_asciiz
	mov si,dir_recursive_current
	call dir_recursive_print_asciiz
	call dir_recursive_newline
	ret

dir_print_bare_prefix:
	push si
	cmp dir_recursive_selected,0
	je dir_bare_prefix_done
	mov si,dir_recursive_current
	or si,si
	jnz dir_recursive_prefix_have_path
	mov si,OFFSET TRANGROUP:dir_recursive_paths
dir_recursive_prefix_have_path:
	call dir_recursive_print_asciiz
	cmp byte ptr [si-2],'\'
	je dir_bare_prefix_done
	mov dl,'\'
	call dir_recursive_putc
dir_bare_prefix_done:
	pop si
	ret

dir_recursive_print_asciiz:
	lodsb
	or al,al
	jz dir_recursive_print_done
	test bits,SwitchDirL
	jz dir_recursive_print_char
	cmp al,'A'
	jb dir_recursive_print_char
	cmp al,'Z'
	ja dir_recursive_print_char
	or al,20h
dir_recursive_print_char:
	mov dl,al
	call dir_recursive_putc
	jmp dir_recursive_print_asciiz
dir_recursive_print_done:
	ret
dir_recursive_newline:
	mov dl,13
	call dir_recursive_putc
	mov dl,10
dir_recursive_putc:
	push ax
	mov ah,02h
	int int_command
	pop ax
	ret

dir_recursive_header DB ' Directory of ',0
dir_recursive_memory_msg DB 'Insufficient memory',13,10,'$'
dir_recursive_search DB 136 DUP(0)
dir_recursive_file_dta DB 43 DUP(0)
dir_recursive_dtas DB 16*43 DUP(0)
dir_recursive_paths DB 16*68 DUP(0)

; Bounded by COMMAND.COM's real-mode transient workspace.  Overflow is an
; explicit insufficient-memory error, never a silently truncated listing.
dir_sort_buffer DB 256*32 DUP(?)

	PUBLIC TRANSPACEEND
TRANSPACEEND LABEL BYTE
TRANEXT ENDS

	END
