	BITS 16
	%INCLUDE "mikedev.inc"
	ORG 32768

BUFLEN	equ 16
ESC	equ 27

start:		
	mov ax, warnmsg_1		; Warn the user that the program might
	mov bx, warnmsg_2		; hang if he has no serial ports
	mov cx, 0
	mov dx, 1
	call os_dialog_box
	
	cmp ax, 0			; If he selects OK, then go on...
	je .proceed
	
	call os_clear_screen		; ...otherwise, quit
	ret

.proceed:
	call os_clear_screen
	mov ax, 0			; 9600 baud mode
	call os_serial_port_enable
	mov si, startmsg
	call os_print_string

	
main:	xor ax, ax			; Zero the buffer offset
	mov [bufoff], ax
	mov [bufbot], ax

	mov ax, 0300h			; Check COM1
	mov dx, 0
	int 14h
	
	bt ax, 8			; Char received?
	jc rx				; If so, handle it
	
	mov ax, 0			; Something to send?
	call os_check_for_key
	cmp al, 1			; Ctrl-A?
	je ctl_a
	
	cmp ax, 0			; Nothing?
	je main				; If so, look again

	cmp ah, KEY_UP			; Specially process arrow keys
	je .ku
	
	cmp ah, KEY_DOWN
	je .kd
	
	cmp ah, KEY_LEFT
	je .kl
	
	cmp ah, KEY_RIGHT
	je .kr
	
	call os_send_via_serial
	jmp main
	
.ku:	mov al, ESC
	call os_send_via_serial
	mov al, '['
	call os_send_via_serial
	mov al, 'A'
	call os_send_via_serial
	jmp main

.kd:	mov al, ESC
	call os_send_via_serial
	mov al, '['
	call os_send_via_serial
	mov al, 'B'
	call os_send_via_serial
	jmp main

.kl:	mov al, ESC
	call os_send_via_serial
	mov al, '['
	call os_send_via_serial
	mov al, 'D'
	call os_send_via_serial
	jmp main

.kr:	mov al, ESC
	call os_send_via_serial
	mov al, '['
	call os_send_via_serial
	mov al, 'C'
	call os_send_via_serial
	jmp main

rx:	call os_get_via_serial		; Get the character
	cmp al, ESC			; <ESC>?
	je esc				; If so, process an escape code

	cmp al, 13			; <CR>?
	je .cr				; If so, do a carriage return
	
	cmp al, 10			; <LF>?
	je .lf
	
	cmp al, 7			; <BEL>?
	je .bel

	cmp al, 8			; <BS>?
	je .bs
	
	cmp al, 9			; <HT>?
	je .ht

	cmp al, 19			; <XOFF>?
	je .xoff
	
	call print_char			; If none of those things, print it...
	mov [char], al			; ...and save it (in case we get REP)
	jmp main

.bs:					; Just use TTY fn to do <BS>...
.bel:					; ...<BEL>...
.lf:					; ...<LF>...
.cr:	mov ah, 0Eh			; ...and <CR>
	mov bx, 0
	int 10h
	jmp main

.ht:	mov al, 8			; Use the CUF routine to go forward
	jmp cuf_n			; 8 spaces

.xoff:	call os_get_via_serial		; Get a character
	cmp al, 17			; Is it <XON>?
	jne .xoff			; If not, ignore it and try again
	
	jmp main			; But if it is, break the loop

ctl_a:	call os_wait_for_key		; Get another key
	cmp al, 1			; C-a?
	je .print_ctl_a			; If so, output C-a
	
	cmp al, 24			; C-x?
	je .ctl_x			; If so, exit

	cmp al, 4			; C-d?
	je .ctl_d			; If so, dump registers
	
	cmp al, 8			; C-h?
	je .ctl_h			; If so, print help message
	
	jmp main

.print_ctl_a:
	call os_send_via_serial		; Transmit our C-a
	jmp main

.ctl_x:	mov ax, 0E0Dh			; Do CRLF, then exit
	mov bx, 0
	int 10h
	mov al, 0Ah
	int 10h
	ret

.ctl_d:	call os_dump_registers
	jmp main

.ctl_h:	mov si, help			; Print help message
	call os_print_string
	jmp main

esc:	call wait_for_char		; Get a character
	cmp al, 'c'			; <ESC>c means reset terminal
	je reset
	
	cmp al, '['			; <ESC>[ introduces "control sequence"
	jne main

csi:	call wait_for_char		; Get a character
	cmp al, 'A'
	je cuu
	
	cmp al, 'B'
	je cud
	
	cmp al, 'C'
	je cuf
	
	cmp al, 'D'
	je cub

	cmp al, 'E'
	je cnl
	
	cmp al, 'F'
	je cpl

	cmp al, 'H'
	je home
	
	cmp al, 'J'
	je ed
	
	cmp al, 'K'
	je el

	cmp al, 'S'
	je su
	
	cmp al, 'T'
	je sd
	
	cmp al, 'f'
	je home

	cmp al, 's'
	je scp
	
	cmp al, 'u'
	je rcp
	
	cmp al, 'm'
	je attres

	cmp al, '?'
	je ques

	cmp al, '0'		; Digit?
	jl main
	
	cmp al, '9'
	jg main			; If not, esc code is invalid; back to main loop

digit:	call clrstrbuf		; Clear the string buffer preparing for a param
	mov di, numstrbuf	; Store digit in the buffer
	stosb
	
	call wait_for_char	; Get another character

	cmp al, '0'		; Digit?
	jl escode		; If not, move on to processing escape codes
	
	cmp al, '9'
	jg escode

digit2:	stosb			; But if it was, store digit
	call wait_for_char

escode:	mov bl, al		; Preserve our character
				; (os_string_to_int overwrites AX)
	mov si, numstrbuf	; Convert string buffer to a number
	call os_string_to_int
	call pshnum		; Put our number in the stack
	mov al, bl		; Get the character back
	
	cmp al, 'A'		; Process escape codes
	je .cuu			; (get a number off the stack, then use it)

	cmp al, 'B'
	je .cud

	cmp al, 'C'
	je .cuf
	
	cmp al, 'D'
	je .cub

	cmp al, 'E'
	je .cnl
	
	cmp al, 'F'
	je .cpl

	cmp al, 'G'
	je cha

	cmp al, 'K'
	je .el

	cmp al, 'J'
	je .ed

	cmp al, 'S'
	je .su
	
	cmp al, 'T'
	je .sd

	cmp al, 'b'
	je rept

	cmp al, 'm'		; <CSI>m uses the entire stack
	je sgr
	
	cmp al, 'n'
	je dsr

	cmp al, ';'		; If it's a semicolon, try to get another param
	je semi
	
	jmp main		; If it's none of these characters, give up

.cuu:	call popnum
	jmp cuu_n

.cud:	call popnum
	jmp cud_n

.cuf:	call popnum
	jmp cuf_n

.cub:	call popnum
	jmp cub_n

.cnl:	call popnum
	jmp cnl_n

.cpl:	call popnum
	jmp cpl_n

.el:	call popnum
	jmp el_n

.ed:	call popnum
	jmp ed_n

.su:	call popnum
	jmp su_n

.sd:	call popnum
	jmp sd_n

semi:	call clrstrbuf		; Clear the string buffer to get another param
	call wait_for_char	; Get another char

	cmp al, '0'		; If it's not a digit, give up
	jl main
	
	cmp al, '9'
	jg main
	
	mov di, numstrbuf	; Store the digit
	stosb
	
	call wait_for_char	; Get another character
	cmp al, '0'		; If it's not a digit, go on to codes
	jl mcode
	
	cmp al, '9'
	jg mcode
	
.nwdgt:	stosb			; Otherwise store the digit...
	call wait_for_char	; ...and get another character

	;; N.B.: "mcode" stands for "multiple parameter code".

mcode:	mov bl, al		; Save the character
	mov si, numstrbuf	; Convert the number string to an actual number
	call os_string_to_int
	call pshnum		; Push it onto the stack
	mov al, bl		; Restore the character
	
	cmp al, ';'		; Semicolon?
	je semi			; If so, get another parameter
		
	cmp al, 'H'
	je .cup

	cmp al, 'R'
	je orpos		; Handle other position
	
	cmp al, 'f'
	je .cup

	cmp al, 'm'
	je sgr
	
	jmp main		; If it's not a valid code, return

;;; CUrsor Position
.cup:	call popnum		; Pop the column number off the stack...
	mov dl, al
	cmp dl, 0		; If it's < 1, give up
	jle main

	cmp dl, 81		; If it's > 80, give up
	jge main

	dec dl			; ...and decrement it (for os_move_cursor)

	call popnum		; Pop the row number off the stack...
	mov dh, al
	cmp dh, 0		; If it's < 1, give up
	jle main
	
	cmp dl, 26		; If it's > 25, give up
	jge main

	dec dh			; ...and decrement it (for os_move_cursor)

	call os_move_cursor	; Move to the position
	jmp main

orpos:	mov si, .msg1
	call os_print_string
	call popnum		; Pop column off
	mov ah, 0
	call os_int_to_string
	mov si, ax
	call os_print_string
	mov si, .msg2
	call os_print_string
	call popnum
	mov ah, 0
	call os_int_to_string
	mov si, ax
	call os_print_string
	call os_print_newline
	jmp main
	
.msg1:	db "Other terminal's cursor is on column ", 0
.msg2:	db " and row ", 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; <CSI>?25l (lowercase L) hides the cursor; <CSI>?25h shows it
ques:	call wait_for_char
	cmp al, '2'
	jne main
	
	call wait_for_char
	cmp al, '5'
	jne main
	
	call wait_for_char
	cmp al, 'l'
	je .hide
	
	cmp al, 'h'
	jne main
	
.show:	call os_show_cursor
	jmp main

.hide:	call os_hide_cursor
	jmp main

;;; CUrsor Up
cuu:	mov al, 1		; Set AL to 1 (if no parameter given)
cuu_n:	;;call dump_regs_preserve_cursor
	call os_get_cursor_pos	; Get the cursor position
	sub dh, al		; Prepare to move up AL rows
	cmp dh, 0		; Too far?
	jge .continue		; If not, go ahead...
	mov dh, 0		; ...otherwise, just go as far as the top
.continue:
	call os_move_cursor	; Do the actual moving
	jmp main

;;; CUrsor Down
cud:	mov al, 1		; We're here if no parameter was given
cud_n:	call os_get_cursor_pos	; Get the cursor position
	add dh, al		; Prepare to move down AL rows
	cmp dh, 25		; Too far?
	jl .continue		; If not, go ahead...
	mov dh, 24		; ...otherwise, just go as far as the bottom
.continue:
	call os_move_cursor	; Do the actual moving
	jmp main

;;; CUrsor Right
cuf:	mov al, 1		; No parameter was given if we're here
cuf_n:	call os_get_cursor_pos	; Get cursor position
	add dl, al		; Prepare to move right AL columns
	cmp dl, 80		; Gone too far?
	jl .continue		; If not, go ahead...
	mov dl, 79		; ...otherwise, only go to the extreme right
.continue:
	call os_move_cursor	; Move the cursor
	jmp main

cub:	mov al, 1		; No parameter was given if we're here
cub_n:	call os_get_cursor_pos	; Get cursor position
	sub dl, al		; Prepare to move left AL columns
	cmp dl, 0		; Too far?
	jge .continue		; If not, go ahead...
	mov dl, 0		; ...otherwise, only go to the extreme left
.continue:
	call os_move_cursor	; Move the cursor
	jmp main

;;; Cursor to start of Next Line
cnl:	mov al, 1		; No parameter was given if we end up here
cnl_n:	call os_get_cursor_pos	; Get the cursor position
	add dh, al		; Prepare to go down AL rows...
	mov dl, 0		; ...and to the first column of the same
	cmp dh, 24		; Past the bottom?
	jle .continue		; If not, go ahead...
	mov dh, 24		; ...otherwise, just go as far as the bottom
.continue:
	call os_move_cursor	; Move the cursor
	jmp main

;;; Cursor to start of Previous Line
cpl:	mov al, 1		; No parameter was given if we end up here
cpl_n:	call os_get_cursor_pos	; Get cursor position
	sub dh, al		; Prepare to go up AL rows...
	mov dl, 0		; ...and to the first column of the same
	cmp dh, 0		; Past the top?
	jge .continue		; If not, go ahead...
	mov dh, 0		; ...otherwise, just go as far as the top
.continue:
	call os_move_cursor	; Move the cursor
	jmp main

;;; Cursor to Horizontal Absolute position
cha:	call popnum		; Get a number off the stack
	call os_get_cursor_pos	; Get the cursor position

	cmp al, 1		; Are we off the left edge?
	jge .ge
	mov al, 1		; If we are, only go as far as the left edge
	jmp .continue

.ge:	cmp al, 80		; Are we off the right edge?
	jle .continue
	mov al, 80		; If we are, only go as far as the right edge
.continue:
	dec al			; Decrement position (for os_move_cursor)
	mov dl, al
	call os_move_cursor	; Move the cursor
	jmp main

;;; Scroll Up
su:	mov al, 1		; Default parameter
su_n:	mov ah, 06h		; int 10h, ah=06h is the interrupt to scroll up
	mov bh, [attr]		; Create new lines using the current attribute
	mov cx, 0		; Upper left corner of screen
	mov dx, 0x1950		; Lower right corner of screen
	int 10h			; Scroll up (# of lines is in AL)
	jmp main

;;; Scroll DOwn
sd:	mov al, 1		; Default parameter
sd_n:	mov ah, 07h		; int 10h ah=07h is the interrupt to scroll down
	mov bh, [attr]		; Create new lines using the current attribute
	mov cx, 0		; Upper left corner of screen
	mov dx, 0x1950		; Lower right corner of screen
	int 10h			; Scroll down (# of lines is in AL)
	jmp main

home:	mov dx, 0101h 		; Default parameter
home_n:	;call dump_regs_preserve_cursor
	cmp dh, 0		; Minimum row number is 1
	jle main

	cmp dh, 25		; Maximum row number is 25
	jg main

	dec dh			; Decrement row for os_move_cursor

	cmp dl, 0		; Minimum column number is 1
	jle main

	cmp dl, 81		; Maximum is 80
	jge main

	dec dl			; Decrement col for os_move_cursor

	call os_move_cursor	; Move the cursor
	jmp main

;;; Erase Display
ed:	mov al, 0		; Default parameter
ed_n:	cmp al, 0		; If AL = 0, then erase to end of screen
	je ed0

	cmp al, 1		; If AL = 1, then erase to beginning of screen
	je ed1

	cmp al, 2		; If AL = 2, then erase whole screen
	je ed2
	
	jmp main

ed0:	call os_get_cursor_pos	; Save cursor position
	push dx
	
	call erase_sub		; Erase to end of this line

	inc dh			; Go to beginning of next line
	mov dl, 0
	call os_move_cursor

	pusha
	mov ax, 0920h		; Print 80 spaces using current attribute
	mov bh, 0
	mov bl, [attr]
	mov cx, 80
	
.loop:	int 10h
	inc dh			; Go to next line
	call os_move_cursor
	cmp dh, 25		; If we're at the bottom, finish
	jne .loop
	popa
	
	pop dx			; Restore the cursor position
	call os_move_cursor
	jmp main

ed1:	call os_get_cursor_pos	; Save cursor position
	push dx

	call erase_to_beg	; Erase to beginning of the line
	;call dump_regs_preserve_cursor
	cmp dh, 0		; If we're on the first row, we're done
	je main
	
	dec dh			; Otherwise, go to previous row...
	mov dl, 0
	call os_move_cursor
	
	pusha
	mov ax, 0920h		; ...and print 80 spaces...
	mov bh, 0
	mov bl, [attr]
	mov cx, 80

.loop:	int 10h
	dec dh			; ...and go up again
	call os_move_cursor
	jz .zero		; If we're at top, erase that row and finish
	jmp .loop

.zero:	int 10h
	
	popa
	pop dx			; Restore cursor position
	call os_move_cursor
	jmp main

ed2:	call os_get_cursor_pos	; Save cursor position
	pusha
	mov dx, 0		; Go to upper left corner
	call os_move_cursor

	mov ax, 0x0920		; Print 2'000 (80x25) spaces...
	mov bh, 0
	mov bl, [attr]
	mov cx, 2000
	int 10h

	popa			; ...and restore the cursor
	call os_move_cursor
	jmp main

;;; Erase Line
el:	mov al, 0		; Default parameter
el_n:	cmp al, 0		; Erase to end of line
	je el0

	cmp al, 1		; Erase to beginning of line
	je el1

	cmp al, 2		; Erase whole line
	je el2
	
	jmp main

el0:	call erase_sub
	jmp main

el1:	call erase_to_beg
	jmp main

el2:	call os_get_cursor_pos	; Save cursor position
	push dx
	mov dl, 0		; Go to beginning of line...
	call os_move_cursor
	call erase_sub		; ...and erase the whole thing
	pop dx			; Go back to where we were before
	call os_move_cursor
	jmp main

reset:	call os_clear_screen	; To reset, clear the screen...
	call clrstrbuf		; ...the string buffer...
	call clrbuf		; ...and the parameter stack, then...
	jmp start		; ...go back to start

;;; Save Cursor Position
scp:	call os_get_cursor_pos	; Simply get it and squirrel it away
	mov [cpos], dx
	jmp main

rcp:	mov dx, [cpos]		; Retrieve it from where we squirreled it...
	call os_move_cursor	; ...and go there
	jmp main

dsr:	call popnum		; Get number
	cmp al, 6		; Is it 6?
	jne main		; If not, it's invalid

	call os_get_cursor_pos	; Get the cursor position...
	push dx			; ...save it and...
	inc dh			; ...increment it for standards compliance
	inc dl
	
	mov al, ESC		; Send <ESC>
	call os_send_via_serial
	mov al, '['
	call os_send_via_serial
	
	mov ah, 0		; Zero AH so we can...
	mov al, dh
	call os_int_to_string	; ...convert the row to a string so we can...
	mov si, ax
.loop1:	lodsb			; ...send it in a readable form
	cmp al, 0
	je .end1
	call os_send_via_serial
	jmp .loop1
	
.end1:	mov al, ';'
	call os_send_via_serial	

	mov ah, 0		; Do the same for the column
	mov al, dl
	call os_int_to_string
	mov si, ax
.loop2:	lodsb
	cmp al, 0
	je .end2
	call os_send_via_serial
	jmp .loop2

.end2:	mov al, 'R'
	call os_send_via_serial

	pop dx			; Get cursor back
	call os_move_cursor
	jmp main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

attres:	mov dx, 0		; Clear parameter queue...
	call clrbuf
	mov al, 0		; ...and push a 0, so default behaviour
	call pshnum		; will be to reset attributes
sgr:	call behead		; Take a number off the bottom

	mov bl, [attr]		; Load the current attribute

	cmp al, 0		; Is the number we popped a 0?
	je .reset		; If so, reset attributes

	cmp al, 1
	je .bold

	cmp al, 4
	je .under
	
	cmp al, 7
	je .inv

	cmp al, 21
	je .norm
	
	cmp al, 22
	je .norm

	cmp al, 30		; Is the number 30 or more?
	jge .thirty		; If so, check numbers greater than 30
	
	jmp main		; Otherwise, we're done

.thirty:
	cmp al, 37
	jle .fg
	
	cmp al, 39
	je .fg
	
	cmp al, 40		; Is the number 40 or more?
	jl main			; If not, we're done
	
	cmp al, 47
	jle .bg
	
	cmp al, 49
	je .bg
	
	jmp main
	
.reset:	mov bl, 0b00000111	; Set text to black-on-white
	jmp .end

.under:
.bold:	or bl, 0b00001000	; Set bold bit
	jmp .end

.inv:	ror bl, 4		; Rotate attribute byte (to swap f.g. & b.g.)
	bt bx, 7		; Was the text bold?
	jnc .end

	and bl, 0b01111111	; If it was, mask out the upper bold bit...
	or bl, 0b00001000	; ...and mask in the lower bold bit
	jmp .end

.norm:	and bl, 0b11110111	; Reset bold bit
	jmp .end

.fg:	and bl, 0b11111000	; Nix lower 3 bits for easier colour-setting
	jmp .col

.bg:	and bl, 0b10001111	; Nix bits 6-4 for easier colour-setting
	
.col:	;call dump_regs_preserve_cursor
	mov si, coltab		; Build pointer to proper colour by...
	mov ah, 0		; ...zeroing AH (so no mucking about in RAM)...
	sub al, 30		; ...and subtracting 30 (to get into the table)
	add si, ax
	mov cl, [si]		; Get the colour...
	add bl, cl		; ...and set it
	;jmp .end

.end:	mov [attr], bl		; Set attribute
	cmp word [bufbot], BUFLEN
	je main
	
	jmp sgr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

rept:	call popnum		; Get the repeat count
	mov dh, 0
	mov dl, al

	mov al, [char]		; Get back the character we saved
	
.loop:	cmp dx, 0
	je main
	call print_char
	dec dx
	jmp .loop
	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

wait_for_char:
	pusha			; Save registers

.loop:	call os_get_via_serial	; Try to get a character
	bt ax, 15		; Did it work?
	jc .loop		; If not, try again
	
	mov [.tmp], al		; Return the character we got
	popa
	mov al, [.tmp]
	ret
.tmp:	db 0

print_char:			; Prints char in AL using current attribute
	pusha
.print:	mov ah, 09h		; Print char with attribute
	mov bh, 0		; Current page
	mov bl, [attr]		; Current attribute
	mov cx, 1		; Print the character once only
	int 10h

.curs:	call os_get_cursor_pos	; Get cursor position
	cmp dl, 79		; End of the line?
	je .lfcr		; If so, print <LF><CR>
	inc dl			; Otherwise, advance cursor
	call os_move_cursor
	popa
	ret

.lfcr:	mov ax, 0x0E0A		; Print linefeed
	mov bx, 0
	int 10h
	mov al, 0x0D		; Print carriage return
	int 10h
	
	popa
	ret

clrstrbuf:
	pusha
	mov di, numstrbuf	; Set DI to the string buffer
	mov cx, 3
	mov al, 0
	rep stosb		; Fill the buffer with 0
	popa
	ret

clrbuf:	pusha			; Reset the pointers
	mov dx, 0
	mov [bufoff], dx
	mov [bufbot], dx
	popa
	ret

;;; Erase to the end of the current line
erase_sub:
	call os_get_cursor_pos	; Get the cursor position
	
	mov cl, 80		; We need to print (80-current_column) spaces
	sub cl, dl
	
	mov ax, 0920h		; Prepare to print the spaces...
	mov bh, 0
	mov bl, [attr]
	int 10h			; ...and do so
	
	ret

;;; Erase to the beginning of the current line
erase_to_beg:
	pusha
	call os_get_cursor_pos	; Get the cursor position
	push dx			; Save it
	mov cl, dl		; We need to print (current_column) spaces
	inc cl			; One more, b.c. os_get_cursor_pos is 0-indexed
	mov dl, 0		; Go to beginning of line
	call os_move_cursor
	
	mov ax, 0x0920		; Prepare to print the spaces...
	mov bh, 0
	mov bl, [attr]
	int 10h			; ...and print them
	
	pop dx			; Move back to first position, just in case
	call os_move_cursor
	popa
	ret

;;; Dump the registers, saving the cursor position
dump_regs_preserve_cursor:
	push dx
	call os_get_cursor_pos
	mov [.tmp], dx
	pop dx

	call os_dump_registers
	mov dx, [.tmp]
	call os_move_cursor
	
	ret
.tmp:	dw 0


;;; Pushes AL onto numbuf
pshnum:	pusha			; Save registers
	mov di, numbuf		; Set DI to the start of the stack...
	mov dx, [bufoff]	; ...and add the offset
	add di, dx		
	stosb			; Store AL
	inc dx			; Update the offset
	mov [bufoff], dx
	popa			; Restore registers
	ret

;;; Removes the top of numbuf and puts it into AL
popnum:	pusha			; Save registers
	mov si, numbuf		; Set SI to the top of the stack
	mov dx, [bufoff]
	dec dx			; Update the offset
	add si, dx
	lodsb			; Get the top and put it in AL
	mov [.tmp], al
	mov [bufoff], dx
	popa			; Restore registers
	mov al, [.tmp]
	ret

.tmp:	db 0

;;; Removes the bottom (head) of numbuf and puts it into AL
behead:	pusha			; Save registers
	mov si, numbuf		; Get the head of numbuf
	mov dx, [bufbot]
	add si, dx
	lodsb			; Get the head
	inc dx			; Update head pointer (bufbot)
	mov [bufbot], dx
	mov [.tmp], al
	popa
	mov al, [.tmp]
	ret
.tmp:	db 0

startmsg:
	db 154,'berterm for MikeOS', 13, 10	; Überterm
help:	db 'Press C-a C-x to exit, C-a C-a to transmit C-a,', 13, 10
	db 'C-a C-d to dump registers, C-a C-h to print help message'
	db 13, 10, 13, 10, 0

warnmsg_1:
	db 'Serial terminal program - may hang if', 0
warnmsg_2:
	db 'you have no serial ports! Proceed?', 0

numstrbuf:
	db 0, 0, 0

bufoff:	dw 0
bufbot:	dw 0

cpos:	dw 0

char:	db 0

attr:	db 0b00000111

;;; Colour table
coltab:	db 0x00, 0x04, 0x02, 0x06, 0x01, 0x05, 0x03, 0x07
	db 0xfe, 0x07
	db 0x00, 0x40, 0x20, 0x60, 0x10, 0x50, 0x30, 0x70
	db 0xfe, 0x00

numbuf:	times BUFLEN db 0xff

