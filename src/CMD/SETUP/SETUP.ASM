.model small
.stack 512
.data

title_msg       db 'MS-DOS 6.22 Setup',13,10,'$'
usage_msg       db 'Usage: SETUP [drive:\directory] [/Y] [/B] [/F]',13,10
                db '       SETUP /E',13,10,'$'
fresh_msg       db 'Fresh installation to $'
upgrade_msg     db 'Upgrade installation in $'
floppy_msg      db 'Minimal startup-disk installation to $'
confirm_msg     db 13,10,'Continue (Y/N)? $'
disk2_msg       db 13,10,'Insert MS-DOS 6.22 Disk 2 in drive A and press ENTER.',13,10,'$'
wrong_disk_msg  db 'Disk 2 was not found. Press ENTER to try again.',13,10,'$'
complete_msg    db 13,10,'Setup completed successfully.',13,10,'$'
cancel_msg      db 13,10,'Setup cancelled.',13,10,'$'
error_msg       db 13,10,'Setup could not complete.',13,10,'$'
windows_msg     db 13,10,'SETUP /E configures Windows companion programs,',13,10
                db 'which are not included in this distribution.',13,10,'$'
crlf            db 13,10,'$'

default_dest    db 'C:\DOS',0
floppy_dest     db 'B:\DOS',0
sys_program     db 'A:\SYS.COM',0
data_file       db 'A:\SETUP.DAT',0
config_suffix   db '\CONFIG.SYS',0
auto_suffix     db '\AUTOEXEC.BAT',0
expand_suffix   db '\EXPAND.EXE',0
command_suffix  db '\COMMAND.COM',0
config_prefix   db 'DEVICE=',0
config_himem    db '\HIMEM.SYS',13,10,0
config_device   db 'DEVICE=',0
config_memory   db '\EMM386.EXE NOEMS',13,10,0
config_high     db 'DOS=HIGH,UMB',13,10,'FILES=30',13,10
                db 'BUFFERS=20',13,10,0
auto_prefix     db '@ECHO OFF',13,10,'PATH ',0
auto_cache      db 13,10,0
smartdrv_suffix db '\SMARTDRV.EXE',13,10,0
recovery_config db 'FILES=20',13,10,'BUFFERS=10',13,10,'LASTDRIVE=Z',13,10,0

core_sources    dw offset core_command, offset core_expand, offset core_sys
                dw offset core_format, offset core_fdisk, offset core_setup, 0
core_command    db 'A:\COMMAND.COM',0
core_expand     db 'A:\EXPAND.EXE',0
core_sys        db 'A:\SYS.COM',0
core_format     db 'A:\FORMAT.COM',0
core_fdisk      db 'A:\FDISK.EXE',0
core_setup      db 'A:\SETUP.EXE',0

psp_segment     dw 0
auto_yes        db 0
upgrade_mode    db 0
cpu_386         db 0
mono_mode       db 0
floppy_mode     db 0
windows_mode    db 0
core_index      dw 0
destination     db 64 dup (0)
source_path     db 128 dup (0)
target_path     db 128 dup (0)
program_path    db 128 dup (0)
command_tail    db 128 dup (0)
input_buffer    db 127,0,127 dup (0)
copy_buffer     db 4096 dup (0)
setup_data      db 4096 dup (0)
setup_size      dw 0

exec_block      dw 0
exec_tail_off   dw offset command_tail
exec_tail_seg   dw 0
exec_fcb1_off   dw 5ch
exec_fcb1_seg   dw 0
exec_fcb2_off   dw 6ch
exec_fcb2_seg   dw 0
data_end        label byte

.code
start:
        cld
        mov     bx,ds
        mov     ax,@data
        mov     dx,ax
        mov     es,ax
        mov     es:psp_segment,bx
        mov     es:exec_fcb1_seg,bx
        mov     es:exec_fcb2_seg,bx
        mov     es:exec_tail_seg,ax
        xor     ch,ch
        mov     cl,ds:[80h]
        mov     al,cl
        mov     es:command_tail,al
        mov     si,81h
        mov     di,offset command_tail+1
        rep     movsb
        mov     ds,dx
        push    ds
        pop     es
        mov     ax,ss
        sub     ax,psp_segment
        add     ax,32                  ; retain the 512-byte stack
        mov     bx,ax
        mov     ax,psp_segment
        mov     es,ax
        mov     ah,4ah
        int     21h
        push    ds
        pop     es
        call    main
        mov     ax,4c00h
        int     21h

main proc near
        mov     dx,offset title_msg
        call    print
        call    parse_arguments
        jc      setup_fail
        cmp     windows_mode,0
        jne     setup_windows
        call    detect_386
        call    ensure_destination
        jc      setup_fail
        call    detect_upgrade
        mov     dx,offset fresh_msg
        cmp     floppy_mode,0
        jne     show_floppy_mode
        cmp     upgrade_mode,0
        je      show_mode
        mov     dx,offset upgrade_msg
        jmp     show_mode
show_floppy_mode:
        mov     dx,offset floppy_msg
show_mode:
        call    print
        mov     dx,offset destination
        call    print_asciiz
        mov     dx,offset crlf
        call    print
        cmp     auto_yes,0
        jne     confirmed
        mov     dx,offset confirm_msg
        call    print
        call    read_line
        mov     al,input_buffer[2]
        and     al,0dfh
        cmp     al,'Y'
        jne     setup_cancel
confirmed:
        call    copy_core_files
        jc      setup_fail
        call    transfer_system
        jc      setup_fail
        call    install_root_command
        jc      setup_fail
        cmp     floppy_mode,0
        jne     setup_floppy_config
        call    wait_for_disk2
        jc      setup_cancel
        call    install_compressed
        jc      setup_fail
        cmp     upgrade_mode,0
        jne     setup_done
        call    create_fresh_configuration
        jc      setup_fail
        jmp     setup_done
setup_floppy_config:
        call    create_recovery_configuration
        jc      setup_fail
setup_done:
        mov     dx,offset complete_msg
        call    print
        clc
        ret
setup_cancel:
        mov     dx,offset cancel_msg
        call    print
        mov     ax,4c01h
        int     21h
setup_fail:
        mov     dx,offset error_msg
        call    print
        mov     ax,4c01h
        int     21h
setup_windows:
        mov     dx,offset windows_msg
        call    print
        mov     ax,4c01h
        int     21h
main endp

parse_arguments proc near
        mov     si,offset command_tail+1
        mov     cl,command_tail
        xor     ch,ch
        mov     di,offset destination
        mov     bx,offset default_dest
copy_default:
        mov     al,[bx]
        mov     [di],al
        inc     bx
        inc     di
        or      al,al
        jnz     copy_default
        xor     bp,bp
parse_next:
        or      cx,cx
        jz      parse_ok
        mov     al,[si]
        cmp     al,' '
        je      parse_advance
        cmp     al,9
        jne     parse_start
parse_advance:
        inc     si
        dec     cx
        jmp     parse_next
parse_start:
        mov     di,si
parse_find_end:
        jcxz    parse_at_end
        mov     al,[si]
        cmp     al,' '
        je      parse_terminate
        cmp     al,9
        je      parse_terminate
        inc     si
        dec     cx
        jmp     parse_find_end
parse_terminate:
        mov     byte ptr [si],0
        inc     si
        dec     cx
parse_at_end:
        cmp     byte ptr [di],'/'
        jne     parse_destination
        mov     al,[di+1]
        and     al,0dfh
        cmp     al,'Y'
        jne     parse_blackwhite
        cmp     byte ptr [di+2],0
        jne     parse_bad
        mov     auto_yes,1
        jmp     parse_next
parse_blackwhite:
        cmp     al,'B'
        jne     parse_floppy
        cmp     byte ptr [di+2],0
        jne     parse_bad
        mov     mono_mode,1
        jmp     parse_next
parse_floppy:
        cmp     al,'F'
        jne     parse_windows
        cmp     byte ptr [di+2],0
        jne     parse_bad
        mov     floppy_mode,1
        jmp     parse_next
parse_windows:
        cmp     al,'E'
        jne     parse_help
        cmp     byte ptr [di+2],0
        jne     parse_bad
        mov     windows_mode,1
        jmp     parse_next
parse_help:
        cmp     byte ptr [di+1],'?'
        jne     parse_bad
        cmp     byte ptr [di+2],0
        jne     parse_bad
        mov     dx,offset usage_msg
        call    print
        mov     ax,4c00h
        int     21h
parse_destination:
        cmp     bp,0
        jne     parse_bad
        inc     bp
        push    si
        push    cx
        mov     si,di
        mov     di,offset destination
        mov     cx,63
parse_copy_dest:
        lodsb
        stosb
        or      al,al
        jz      parse_copy_done
        loop    parse_copy_dest
        mov     byte ptr [di-1],0
parse_copy_done:
        pop     cx
        pop     si
        jmp     parse_next
parse_bad:
        mov     dx,offset usage_msg
        call    print
        stc
        ret
parse_ok:
        cmp     floppy_mode,0
        je      short parse_really_ok
        cmp     bp,0
        jne     short parse_really_ok
        mov     si,offset floppy_dest
        mov     di,offset destination
        call    copy_string
parse_really_ok:
        clc
        ret
parse_arguments endp

ensure_destination proc near
        mov     dx,offset destination
        mov     ax,4300h
        int     21h
        jc      make_destination
        test    cx,10h
        jz      destination_error
        clc
        ret
make_destination:
        mov     ah,39h
        int     21h
        ret
destination_error:
        stc
        ret
ensure_destination endp

detect_upgrade proc near
        mov     si,offset destination
        mov     di,offset target_path
        call    copy_string
        dec     di
        mov     si,offset command_suffix
        call    append_string
        mov     dx,offset target_path
        mov     ax,4300h
        int     21h
        jc      not_upgrade
        mov     upgrade_mode,1
not_upgrade:
        ret
detect_upgrade endp

copy_core_files proc near
        mov     core_index,0
core_loop:
        mov     bx,core_index
        mov     si,core_sources[bx]
        or      si,si
        jz      core_done
        mov     dx,si
        mov     di,offset source_path
        call    copy_string_from_dx
        call    basename_from_source
        mov     di,offset target_path
        mov     si,offset destination
        call    copy_string
        call    append_backslash
        mov     si,bx
        call    append_string
        call    copy_file
        jc      core_error
        add     core_index,2
        jmp     core_loop
core_done:
        clc
        ret
core_error:
        mov     dx,offset source_path
        call    print_asciiz
        mov     dx,offset crlf
        call    print
        stc
        ret
copy_core_files endp

basename_from_source proc near
        mov     si,offset source_path
        mov     bx,si
basename_loop:
        lodsb
        or      al,al
        jz      basename_done
        cmp     al,'\'
        jne     basename_loop
        mov     bx,si
        jmp     basename_loop
basename_done:
        ret
basename_from_source endp

copy_file proc near
        mov     dx,offset source_path
        mov     ax,3d00h
        int     21h
        jc      copy_failed
        mov     si,ax
        mov     dx,offset target_path
        xor     cx,cx
        mov     ah,3ch
        int     21h
        jc      copy_close_source
        mov     di,ax
copy_read:
        mov     bx,si
        mov     dx,offset copy_buffer
        mov     cx,4096
        mov     ah,3fh
        int     21h
        jc      copy_close_both
        or      ax,ax
        jz      copy_success
        mov     cx,ax
        mov     bx,di
        mov     ah,40h
        int     21h
        jc      copy_close_both
        cmp     ax,cx
        jne     copy_close_both
        jmp     copy_read
copy_success:
        mov     bx,di
        mov     ah,3eh
        int     21h
        mov     bx,si
        mov     ah,3eh
        int     21h
        clc
        ret
copy_close_both:
        mov     bx,di
        mov     ah,3eh
        int     21h
copy_close_source:
        mov     bx,si
        mov     ah,3eh
        int     21h
copy_failed:
        stc
        ret
copy_file endp

transfer_system proc near
        mov     di,offset command_tail
        mov     byte ptr [di],3
        mov     byte ptr [di+1],' '
        mov     al,destination
        mov     [di+2],al
        mov     byte ptr [di+3],':'
        mov     byte ptr [di+4],13
        mov     dx,offset sys_program
        call    execute
        ret
transfer_system endp

install_root_command proc near
        mov     si,offset destination
        mov     di,offset source_path
        call    copy_string
        dec     di
        mov     si,offset command_suffix
        call    append_string
        mov     al,destination
        mov     target_path,al
        mov     byte ptr target_path[1],':'
        mov     byte ptr target_path[2],0
        mov     di,offset target_path+2
        mov     si,offset command_suffix
        call    append_string
        call    copy_file
        ret
install_root_command endp

wait_for_disk2 proc near
        mov     dx,offset disk2_msg
        call    print
disk2_retry:
        call    read_line
        mov     dx,offset data_file
        mov     ax,3d00h
        int     21h
        jnc     disk2_found
        mov     dx,offset wrong_disk_msg
        call    print
        jmp     disk2_retry
disk2_found:
        mov     bx,ax
        mov     dx,offset setup_data
        mov     cx,4095
        mov     ah,3fh
        int     21h
        jc      disk2_read_error
        mov     setup_size,ax
        mov     si,offset setup_data
        add     si,ax
        mov     byte ptr [si],0
        mov     ah,3eh
        int     21h
        clc
        ret
disk2_read_error:
        mov     ah,3eh
        int     21h
        stc
        ret
wait_for_disk2 endp

install_compressed proc near
        mov     si,offset destination
        mov     di,offset program_path
        call    copy_string
        dec     di
        mov     si,offset expand_suffix
        call    append_string
        mov     si,offset setup_data
install_line:
        cmp     byte ptr [si],0
        je      install_done
        cmp     byte ptr [si],13
        je      install_skip_eol
        cmp     byte ptr [si],10
        je      install_skip_eol
        mov     di,offset source_path
        mov     byte ptr [di],'A'
        mov     byte ptr [di+1],':'
        mov     byte ptr [di+2],'\'
        add     di,3
install_source_name:
        lodsb
        cmp     al,'|'
        je      install_source_done
        or      al,al
        jz      install_error
        stosb
        jmp     install_source_name
install_source_done:
        mov     byte ptr [di],0
        mov     di,offset target_path
        push    si
        mov     si,offset destination
        call    copy_string
        call    append_backslash
        pop     si
install_target_name:
        lodsb
        cmp     al,13
        je      install_target_done
        cmp     al,10
        je      install_target_done
        or      al,al
        jz      install_target_done
        stosb
        jmp     install_target_name
install_target_done:
        mov     byte ptr [di],0
        push    si
        call    build_expand_tail
        mov     dx,offset program_path
        call    execute
        pop     si
        jc      install_error
        jmp     install_line
install_skip_eol:
        inc     si
        jmp     install_line
install_done:
        clc
        ret
install_error:
        mov     dx,offset source_path
        call    print_asciiz
        mov     dx,offset crlf
        call    print
        mov     dx,offset target_path
        call    print_asciiz
        mov     dx,offset crlf
        call    print
        stc
        ret
install_compressed endp

build_expand_tail proc near
        mov     di,offset command_tail+1
        mov     byte ptr [di],' '
        inc     di
        mov     si,offset source_path
        call    append_string
        dec     di
        mov     byte ptr [di],' '
        inc     di
        mov     si,offset target_path
        call    append_string
        dec     di
        mov     byte ptr [di],13
        mov     ax,di
        sub     ax,offset command_tail+1
        mov     command_tail,al
        ret
build_expand_tail endp

execute proc near
        push    ds
        pop     es
        mov     bx,offset exec_block
        mov     ax,4b00h
        int     21h
        jc      execute_failed
        mov     ah,4dh
        int     21h
        or      al,al
        jnz     execute_failed
        clc
        ret
execute_failed:
        stc
        ret
execute endp

create_fresh_configuration proc near
        mov     al,destination
        mov     target_path,al
        mov     byte ptr target_path[1],':'
        mov     byte ptr target_path[2],0
        mov     di,offset target_path+2
        mov     si,offset config_suffix
        call    append_string
        mov     dx,offset target_path
        mov     ax,4300h
        int     21h
        jnc     config_exists
        mov     di,offset copy_buffer
        mov     si,offset config_prefix
        call    copy_string
        dec     di
        mov     si,offset destination
        call    copy_string
        dec     di
        mov     si,offset config_himem
        call    copy_string
        dec     di
        cmp     cpu_386,0
        je      config_without_emm386
        mov     si,offset config_device
        call    copy_string
        dec     di
        mov     si,offset destination
        call    copy_string
        dec     di
        mov     si,offset config_memory
        call    copy_string
        dec     di
config_without_emm386:
        mov     si,offset config_high
        call    copy_string
        dec     di
        mov     cx,di
        sub     cx,offset copy_buffer
        mov     dx,offset target_path
        mov     si,offset copy_buffer
        call    create_data_file
        jc      config_failed
config_exists:
        mov     al,destination
        mov     target_path,al
        mov     byte ptr target_path[1],':'
        mov     byte ptr target_path[2],0
        mov     di,offset target_path+2
        mov     si,offset auto_suffix
        call    append_string
        mov     dx,offset target_path
        mov     ax,4300h
        int     21h
        jnc     config_ok
        mov     di,offset copy_buffer
        mov     si,offset auto_prefix
        call    copy_string
        dec     di
        mov     si,offset destination
        call    copy_string
        dec     di
        mov     si,offset auto_cache
        call    copy_string
        dec     di
        mov     si,offset destination
        call    copy_string
        dec     di
        mov     si,offset smartdrv_suffix
        call    copy_string
        dec     di
        mov     cx,di
        sub     cx,offset copy_buffer
        mov     dx,offset target_path
        mov     si,offset copy_buffer
        call    create_data_file
        jc      config_failed
config_ok:
        clc
        ret
config_failed:
        stc
        ret
create_fresh_configuration endp

; A /F system is intentionally self-contained on the target floppy and does
; not reference compressed Disk 2 components that were not copied there.
create_recovery_configuration proc near
        mov     al,destination
        mov     target_path,al
        mov     byte ptr target_path[1],':'
        mov     byte ptr target_path[2],0
        mov     di,offset target_path+2
        mov     si,offset config_suffix
        call    append_string
        mov     di,offset copy_buffer
        mov     si,offset recovery_config
        call    copy_string
        dec     di
        mov     cx,di
        sub     cx,offset copy_buffer
        mov     dx,offset target_path
        mov     si,offset copy_buffer
        call    create_data_file
        jc      short recovery_config_failed

        mov     al,destination
        mov     target_path,al
        mov     byte ptr target_path[1],':'
        mov     byte ptr target_path[2],0
        mov     di,offset target_path+2
        mov     si,offset auto_suffix
        call    append_string
        mov     di,offset copy_buffer
        mov     si,offset auto_prefix
        call    copy_string
        dec     di
        mov     si,offset destination
        call    copy_string
        dec     di
        mov     byte ptr [di],13
        mov     byte ptr [di+1],10
        add     di,2
        mov     cx,di
        sub     cx,offset copy_buffer
        mov     dx,offset target_path
        mov     si,offset copy_buffer
        call    create_data_file
        ret
recovery_config_failed:
        stc
        ret
create_recovery_configuration endp

; In real mode a 286 clears IOPL/NT when POPF attempts to set them; a 386 or
; newer retains those bits.  Do not install EMM386 in a 286 startup file.
detect_386 proc near
        push    ax
        pushf
        mov     ax,07000h
        push    ax
        popf
        pushf
        pop     ax
        and     ax,07000h
        jz      short detect_386_done
        mov     cpu_386,1
detect_386_done:
        popf
        pop     ax
        ret
detect_386 endp

create_data_file proc near
        push    si
        push    cx
        xor     cx,cx
        mov     ah,3ch
        int     21h
        pop     cx
        pop     dx
        jc      data_failed
        mov     bx,ax
        mov     ah,40h
        int     21h
        jc      data_close_fail
        cmp     ax,cx
        jne     data_close_fail
        mov     ah,3eh
        int     21h
        clc
        ret
data_close_fail:
        mov     ah,3eh
        int     21h
data_failed:
        stc
        ret
create_data_file endp

copy_string_from_dx proc near
        mov     si,dx
copy_string proc near
copy_string_loop:
        lodsb
        stosb
        or      al,al
        jnz     copy_string_loop
        ret
copy_string endp
copy_string_from_dx endp

append_string proc near
append_loop:
        lodsb
        stosb
        or      al,al
        jnz     append_loop
        ret
append_string endp

append_backslash proc near
        dec     di
        cmp     byte ptr [di-1],'\'
        je      backslash_done
        mov     byte ptr [di],'\'
        inc     di
backslash_done:
        ret
append_backslash endp

print proc near
        mov     ah,9
        int     21h
        ret
print endp

print_asciiz proc near
        mov     si,dx
print_char:
        lodsb
        or      al,al
        jz      print_done
        mov     dl,al
        mov     ah,2
        int     21h
        jmp     print_char
print_done:
        ret
print_asciiz endp

read_line proc near
        mov     dx,offset input_buffer
        mov     ah,0ah
        int     21h
        ret
read_line endp

end start
