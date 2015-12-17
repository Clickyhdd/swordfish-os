	BITS 16
	ORG 32768
	%INCLUDE 'mikedev.inc'
start: 	mov ax, .title_msg
	mov bx, .footer_msg
	mov cx, 00100000b	; Colour
	call os_draw_background

	

	.title_msg	db 'File manager', 0
	.footer_msg	db 'Choose an option...', 0
