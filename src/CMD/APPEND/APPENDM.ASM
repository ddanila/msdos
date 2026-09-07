page	60,120
cseg	segment public para 'CODE'
	assume	cs:cseg

	public	bad_append_msg			;@@11
	public	path_error_msg			;@@11
	public	parm_error_msg			;@@11
	public	path_parm_error_msg		;@@11
	public	no_append_msg			;@@11
	public	append_assign_msg		;@@11
	public	append_tv_msg			;@@11
	public	bad_DOS_msg			;@@11
	public	second_append_msg		;@@11

	public	len_bad_append_msg		;@@11
	public	len_path_error_msg		;@@11
	public	len_parm_error_msg		;@@11
	public	len_path_parm_error_msg 	;@@11
	public	len_no_append_msg		;@@11
	public	len_append_assign_msg		;@@11
	public	len_append_tv_msg		;@@11
	public	len_bad_DOS_msg 		;@@11
	public	len_second_append_msg		;@@11

cr	equ	13
lf	equ	10

include appendm.inc

cseg		ends
		end
