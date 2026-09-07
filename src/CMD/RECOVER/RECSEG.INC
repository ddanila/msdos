; define the segment ordering
data	segment public para 'DATA'
data	ends ;put this 1st so that the recmsg works
code	segment public PARA 'CODE'
code	ends
const	segment public para 'const'
const	ends
cstack	segment stack word 'stack'
	db	(362 - 80h) + 256 dup (?) ; (362 - 80h) == IBM's ROM requirements
cstack	ends	; (New - Old) == size of growth
lastseg segment public para 'last'
lastseg ends			 ;put last because 'table' writes over memory
dg	group	data,const,code,cstack,lastseg
	assume	cs:dg,ds:dg,es:dg,ss:CSTACK
