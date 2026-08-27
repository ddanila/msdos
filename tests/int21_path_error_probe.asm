bits 16
org 100h

%macro require_error 2
    jc %%carried
    mov dx, %2
    jmp fail
%%carried:
    cmp ax, %1
    je %%ok
    mov dx, %2
    jmp fail
%%ok:
%endmacro

start:
    push cs
    pop ds

    mov dx, test_directory
    mov ah, 39h
    int 21h
    jc setup_failed
    mov dx, test_directory          ; Existing directory.
    mov ah, 39h
    int 21h
    require_error 5, fail_mkdir_exists
    mov dx, missing_child           ; Parent component does not exist.
    mov ah, 39h
    int 21h
    require_error 3, fail_mkdir_path

    mov dx, missing_directory
    mov ah, 3bh
    int 21h
    require_error 3, fail_chdir_path
    mov dx, test_directory
    mov ah, 3bh
    int 21h
    jc setup_failed
    mov dx, dot_path                ; The current directory cannot be removed.
    mov ah, 3ah
    int 21h
    require_error 16, fail_rmdir_current

    xor cx, cx
    mov dx, local_file
    mov ah, 3ch
    int 21h
    jc setup_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc setup_failed
    mov dx, root_directory
    mov ah, 3bh
    int 21h
    jc setup_failed
    mov dx, test_directory          ; A nonempty directory cannot be removed.
    mov ah, 3ah
    int 21h
    require_error 5, fail_rmdir_nonempty

    mov dx, missing_file
    mov ah, 41h
    int 21h
    require_error 2, fail_delete_file
    mov dx, missing_path_file
    mov ah, 41h
    int 21h
    require_error 3, fail_delete_path
    mov ax, 3d00h
    mov dx, missing_path_file
    int 21h
    require_error 3, fail_open_path

    xor cx, cx
    mov dx, missing_path_file
    mov ah, 3ch
    int 21h
    require_error 3, fail_create_path
    mov ax, 4300h
    mov dx, missing_file
    int 21h
    require_error 2, fail_attr_file
    mov ax, 4300h
    mov dx, missing_path_file
    int 21h
    require_error 3, fail_attr_path

    mov dx, dta
    mov ah, 1ah
    int 21h
    xor cx, cx
    mov dx, missing_glob
    mov ah, 4eh
    int 21h
    require_error 18, fail_find_none

    mov dx, local_file_path
    mov ah, 41h
    int 21h
    jc setup_failed
    mov dx, test_directory
    mov ah, 3ah
    int 21h
    jc setup_failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

setup_failed:
    mov dx, fail_setup
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

test_directory   db 'ERRDIR', 0
missing_directory db 'NOEXIST', 0
missing_child    db 'NOEXIST\CHILD', 0
dot_path         db '.', 0
root_directory   db '\', 0
local_file       db 'LOCAL.TST', 0
local_file_path  db 'ERRDIR\LOCAL.TST', 0
missing_file     db 'MISSING.TST', 0
missing_path_file db 'NOEXIST\MISSING.TST', 0
missing_glob     db 'NOFILES.*', 0
pass_message     db 'INT21_PATH_ERRORS_PASS', 13, 10, '$'
fail_setup       db 'INT21_PATH_SETUP_FAIL', 13, 10, '$'
fail_mkdir_exists db 'INT21_MKDIR_EXISTS_FAIL', 13, 10, '$'
fail_mkdir_path  db 'INT21_MKDIR_PATH_FAIL', 13, 10, '$'
fail_chdir_path  db 'INT21_CHDIR_PATH_FAIL', 13, 10, '$'
fail_rmdir_current db 'INT21_RMDIR_CURRENT_FAIL', 13, 10, '$'
fail_rmdir_nonempty db 'INT21_RMDIR_NONEMPTY_FAIL', 13, 10, '$'
fail_delete_file db 'INT21_DELETE_FILE_FAIL', 13, 10, '$'
fail_delete_path db 'INT21_DELETE_PATH_FAIL', 13, 10, '$'
fail_open_path   db 'INT21_OPEN_PATH_FAIL', 13, 10, '$'
fail_create_path db 'INT21_CREATE_PATH_FAIL', 13, 10, '$'
fail_attr_file   db 'INT21_ATTR_FILE_FAIL', 13, 10, '$'
fail_attr_path   db 'INT21_ATTR_PATH_FAIL', 13, 10, '$'
fail_find_none   db 'INT21_FIND_NONE_FAIL', 13, 10, '$'
dta              times 128 db 0
