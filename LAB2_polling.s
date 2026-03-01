// Constants
.equ UART_BASE, 0xFF201000
.equ UART_DATA, 0 
.equ UART_CTRL, 4 
.equ STACK_BASE, 0x10000000

.equ HEX3_0_BASE, 0xFF200020
.equ UART_RVALID_MASK, 0x8000

.data
/* 7-seg lookup table ifrån kursmatrial
Bits 6 to 0: HEX0 6-0
Bits 14 to 8: HEX1 6-0
Bits 22 to 16: HEX2 6-0
Bits 30 to 24: HEX3 6-0 

Posstiv / Negativ
HEX2 = hundratal / minus
HEX1 = tiotal
HEX0 = ental
Max = 999 Min = -99 */
segLUT:
    .byte 0x3F  // 0
    .byte 0x06  // 1
    .byte 0x5B  // 2
    .byte 0x4F  // 3
    .byte 0x66  // 4
    .byte 0x6D  // 5
    .byte 0x7D  // 6
    .byte 0x07  // 7
    .byte 0x7F  // 8
    .byte 0x6F  // 9
	.byte 0x40  // '-' (minus)
	.byte 0x00  // blank
	
	.text
	.global _start
	
_start:
	// Range -99 to 999
	LDR sp, =STACK_BASE     // init stack pointer
	MOV r4, #0	// counter = 0
	MOV r0, r4
	BL display_7seg

main_loop:
	// Poll UART for one char
	BL poll_uart_char	// r0 = char, or 0 if none
	CMP r0, #0
	BEQ main_loop	// No imput -> keep polling

	// '+' => counter++
	CMP r0, #'+'
	BEQ	counter_inc

	// '-' => counter--
	CMP r0, #'-'
	BEQ	counter_dec

	B	main_loop
	
counter_inc:
	// if counter < 999 then counter++
	LDR r1, =999
	CMP r4, r1
	BGE redraw	//already max
	ADD r4, r4, #1
	B	redraw
	
counter_dec:
	// if counter > -99 then counter--
	LDR r1, =-99
	CMP r4, r1
	BLE redraw	//already min
	SUB r4, r4, #1
		
redraw:
	MOV r0, r4
	BL display_7seg
	B	main_loop
		
//----------------------------------------------
//poll_uart_char
//Returns
//	r0 = ASCII char
//	r0 = 0 if no char available
//----------------------------------------------
poll_uart_char:
	PUSH {r1-r3, lr}
	
	LDR r1, =UART_BASE
	LDR r2, [r1, #UART_DATA]  // Read UART DATA reg 
	
	TST  r2, #UART_RVALID_MASK     // is data valid?
    BEQ  no_char
	
	AND r0, r2, #0xFF             // extract ASCII
  	POP {r1-r3, pc}

no_char:
	MOV r0, #0
	POP {r1-r3, pc}

// -------------------------------------------------------
// idiv
// Integer division by repeated subtraction
// Parameters:
//   r0 = numerator
//   r1 = denominator
// Returns:
//   r0 = quotient
//   r1 = remainder
// -------------------------------------------------------
idiv:
	PUSH {r2, lr}
	MOV r2, r1	// r2 = denominator
	MOV r1, r0	// r1 = working numerator
	MOV r0, #0	// r0 = quotient
	
_div_loop_check:
	CMP r1, r2
	BLO _div_done
	ADD r0, r0, #1
	SUB r1, r1, r2
	B	_div_loop_check
	
_div_done:
	// r0 = quotient, r1 = remainder
	POP {r2, pc}
	
// -------------------------------------------------------
// display_7seg
// Shows signed value on HEX2 HEX1 HEX0.
// Intended range: -99..999
// Input:
//   r0 = value (signed)
// Uses:
//   r1-r7 (caller-saved). Preserves lr.
// -------------------------------------------------------
display_7seg:
	PUSH {r1-r7, lr}
	
	MOV r7,r0	// r7 = Old Counter
	
	// Determine sign and abs
	CMP r0, #0
	BGE _pos
	
	// negative:
	RSBS r0, r0, #0
	MOV	r6, #10	// LUT index for '-'
	B	_split
	
_pos:
	MOV r6, #11	// LUT index for blank
	
_split:
	// Compute ones: abs % 10, tens: abs/10, hundreds: abs/100
	MOV r1, #10	// divisor 10
	BL	idiv	// r0 = abs/10, r1 = abs%10
	MOV r4, r1	// ones
	MOV r5, r0	// tmp = abs /10
		
	MOV r0,r5
	MOV r1, #10
	BL idiv		//r0 = (abs/10)/10, r1 = (abs/10)%10
	MOV r3, r1	// tens
	MOV r2, r0	// hunreds
	
	// Load LUT base
	LDR r1, =segLUT
	
	// pattern for ones, HEX0
	ADD r0, r1, r4
	LDRB r0, [r0]
	
	// patterns for tens, HEX1
	ADD r4, r1, r3
	LDRB r4, [r4]
	
	//HEX2: neg = '-', pos = hundreds or 'blank'
	CMP r7, #0
	BLT _hex2_sign
	
	// possitive: if hundreds == 0 => Blank
	CMP r2, #0
	MOVEQ r2, #11	// Blank index
	B _hex2_load
	
_hex2_sign:
	MOV r2,r6	//'-' index
	
_hex2_load:
	ADD r5, r1, r2
	LDRB r5, [r5]
	
	// Pack into 32-bit: HEX0<< 0, HEX1<< 8, HEX2<< 16
	LSL r4, r4, #8
	LSL r5, r5, #16
	ORR r0, r0, r4
	ORR r0, r0, r5
	
	LDR r1, =HEX3_0_BASE
	STR r0, [r1]
	
	POP {r1-r7, pc}
	
.end