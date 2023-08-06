;###############################################################################
;#
;# Dino game for 8-bit 6052 microprocessor 
;# Nikolai Herrmann, 06/08/2023
;# Based on examples described at https://eater.net/6502
;#
;###############################################################################

;### IO ports 
    ; DDR_ indicates data direction (i.e. input or output), PORT_ the actual port
DDRB = $6002
PORTB = $6000
DDRA = $6003
PORTA = $6001
;###

;### Global variables 
port_a_output = $0200
prev_port_a_output = $0201
jump_height = $0202
next_tree = $0203
trees_bitboard = $0204
bit_shift_state = $0206
lcd_location = $0207
game_running = $0208
score = $0209
;###

;### Labels for LCD pins
E  = %10000000
RW = %01000000
RS = %00100000
;###

    .org $8000 ; start program at address 8000

reset:
;### Set IO LCD ports    
    lda #%11111111 ; Port B: set all pins to output
    sta DDRB

    lda #%11100000 ; Port A: set last 3 pins to output
    sta DDRA
;### 

;### Init LCD display
    ; set 8-bit mode, 2-line display and 5x8 font
    lda #%00111000 
    jsr send_lcd_cmd

    ; set display on, cursor on and blink off
    lda #%00001100 
    jsr send_lcd_cmd

    ; set increment and shift cursor and don't shift display
    lda #%00000110 
    jsr send_lcd_cmd

    ; clear display
    lda #$00000001 
    jsr send_lcd_cmd
;###

;#### Load custom dino char to lcd ram
    ; store character in 1st of 8 available positions
    lda #%01000000
    jsr send_lcd_cmd
    ;---
    lda #%00000111
    jsr send_lcd_data
    lda #%00000101
    jsr send_lcd_data
    lda #%00000111
    jsr send_lcd_data
    lda #%00010110
    jsr send_lcd_data
    lda #%00011111
    jsr send_lcd_data
    lda #%00011110
    jsr send_lcd_data
    lda #%00001010
    jsr send_lcd_data
    lda #%00001010
    jsr send_lcd_data
;###

;#### Load custom tree char 
    lda #%01001000 ; go to next byte (8 * location)
    jsr send_lcd_cmd
    ;---
    lda #%00000100
    jsr send_lcd_data
    lda #%00000101
    jsr send_lcd_data
    lda #%00010101
    jsr send_lcd_data
    lda #%00010101
    jsr send_lcd_data
    lda #%00010110
    jsr send_lcd_data
    lda #%00001100
    jsr send_lcd_data
    lda #%00000100
    jsr send_lcd_data
    lda #%00000100
    jsr send_lcd_data
;###

;### Init all global variables to zero
    jsr init_global_variables
;###

;### Show start message ("Press to play [dino]")
    ; clear display and set DDRAM address back to 0
    lda #%00000001 
    jsr send_lcd_cmd

    ldx #0
print_press_to_play:
    lda press_to_play_msg, x
    beq print_start_dino
    jsr send_lcd_data
    inx
    jmp print_press_to_play
print_start_dino:
    lda #%00000000
    jsr send_lcd_data
;### 

;### Main game loop after reset
loop:
    ; store previous port "a" output before getting new one
    ; bit 7 6 5 are used by lcd, bit 4 is used for graphics update, bit 3 for button press
    lda port_a_output
    sta prev_port_a_output 

    ; store new port "a" output
    lda PORTA
    sta port_a_output

    ; check if graphics need to be updated
    lda prev_port_a_output
    eor port_a_output ; check where bits are different
    and #%00010000 ; check if the set bit has changed (from 0 to 1) or (from 1 to 0)
    beq loop ; if Z=1 (so zero) nothing has changed, no update needs to be performed

    ; check if user has started the game (game_running should be set to 1)
    lda game_running
    and #1
    bne draw_game

    ; check if button was pressed
    lda port_a_output 
    and #%00001000
    beq loop ; if zero user has not started game yet

    ; indicate that game has started
    lda #1 
    sta game_running

    ; set button press back to zero so it doesn't interfere with game logic
    lda port_a_output
    and #%11110111 
    sta port_a_output  

draw_game:
    ; clear display before drawing everything
    lda #%00000001 
    jsr send_lcd_cmd

;### Draw dino
    ; check if dino is currently in a jump
    lda jump_height
    bne in_a_jump 

    ; check if button was pressed
    lda port_a_output
    and #%00001000 
    bne button_press 

    ; no button pressed nor in a jump
    lda #%11000010 ; set cursor to bottom third spot (on ground)
    jsr send_lcd_cmd 
    jmp draw_dino

button_press:
    ; set cursor to top third spot
    lda #%10000010 
    jsr send_lcd_cmd

    ; now in air
    lda #1
    sta jump_height

    jmp draw_dino

in_a_jump:
    ; check if dino has reached top
    lda jump_height
    cmp #3
    beq at_peak_of_jump

    ; set cursor to top third spot (still in air)
    lda #%10000010 
    jsr send_lcd_cmd

    ; increment jump height
    ldx jump_height 
    inx
    stx jump_height

    jmp draw_dino

at_peak_of_jump:
    ; set cursor to bottom third spot (jump back down)
    lda #%11000010 
    jsr send_lcd_cmd

    lda #0
    sta jump_height

    ; set button press to zero
    lda port_a_output
    and #%11110111 
    sta port_a_output 

draw_dino:
    ; after cursor has been set, draw dino
    lda #%00000000
    jsr send_lcd_data
;###

;### Draw trees
    ; bottom row is represented by two 8-bit numbers
    lda #15
    sta lcd_location

    ; which bit we check (goes from 0 to 7, then reset)
    lda #1
    sta bit_shift_state

    ldx #0
cycle_tree_bits:
    ; check each if there is a tree (set bit)
    lda trees_bitboard, x
    and bit_shift_state
    beq end_tree_draw

    ; set cursor for tree
    lda #%11000000 
    ora lcd_location
    jsr send_lcd_cmd

    ; draw tree
    lda #%00000001 
    jsr send_lcd_data

end_tree_draw:
    ; have we drawn all trees?
    lda lcd_location
    beq shift_trees

    clc ; clear carry bit for adc operation
    ; move onto next tree
    lda bit_shift_state
    adc bit_shift_state ; double it
    sta bit_shift_state

    ; do we need to switch to second byte?
    lda lcd_location
    cmp #8
    bne not_next_tree_byte
    inx ; for lda trees_bitboard, x
    lda #1 ; reset
    sta bit_shift_state

not_next_tree_byte:
    ; go next spot in lcd
    ldy lcd_location
    dey
    sty lcd_location

    jmp cycle_tree_bits

shift_trees:
    ; shift all trees down for the two bytes
    clc
    lda trees_bitboard + 1
    adc trees_bitboard + 1
    sta trees_bitboard + 1

    clc
    lda trees_bitboard
    adc trees_bitboard
    sta trees_bitboard

    ; do we need to add tree from the first byte to the second?
    lda trees_bitboard + 1
    bcc no_tree_move ; check carry
    ora #1 ; add tree
    sta trees_bitboard + 1

no_tree_move:
    ; every 10 spaces add a new tree
    lda next_tree
    cmp #10
    bne tree_count_inc

    ; add tree
    lda trees_bitboard
    ora #1
    sta trees_bitboard

    ; reset counter
    lda #0
    sta next_tree

    jmp tree_end_end

tree_count_inc:
    ; increase next tree counter
    ldy next_tree
    iny
    sty next_tree

tree_end_end:
;###

;### Game over check
    ; is a tree at the same space as the dino?
    lda trees_bitboard + 1
    and #%00100000
    beq end_collision_check

    ; is the dino in a jump?
    lda jump_height
    bne update_score

    ; game over
    lda #0
    sta game_running

    ; print game over messsage
    lda #%10000000 ; set cursor to home before printing
    jsr send_lcd_cmd
    ldx #0
print_game_over:
    lda game_over_msg, x
    beq end_collision_check
    jsr send_lcd_data
    inx
    jmp print_game_over

update_score: 
    ; successful jump, increase player score
    ldx score
    inx
    stx score

end_collision_check:
;###

;### Draw player score (super lazy here, only work for digits [0, 99])
    ; set cursor to last position
    lda #%10001111 
    jsr send_lcd_cmd

    ; print last digit
    lda score
    jsr div_10
    clc
    adc #"0" ;add number to ascii "0"
    jsr send_lcd_data

    ; print first digit
    lda #%10001110 ; set cursor to second position
    jsr send_lcd_cmd
    txa ; move value in "x" register to "a" register
    clc
    adc #"0"
    jsr send_lcd_data
;###

;### Reset game incase player has lost
    lda game_running
    bne repeat_main_loop
    jsr init_global_variables
;###

repeat_main_loop:
    jmp loop

;--- String data ---

press_to_play_msg: .asciiz "Press to play "
game_over_msg: .asciiz "Game over!"

;--- Subroutines ---

;### Divide number by 10, answer in "x" register, remainder in "a" register
    ; assumes number is loaded into "a" register before calling
div_10:
    ldx #0
div_10_loop:
    sec ; set carry bit for sbc operation
    sbc #10
    bmi div_10_done
    inx 
    jmp div_10_loop
div_10_done:
    clc
    adc #10 ; went one step too far, so add back to get remainder
    rts
;###

;### Iinitialize variables (resets the game)
init_global_variables:
    lda #0

    sta port_a_output
    sta jump_height
    sta trees_bitboard
    sta trees_bitboard + 1
    sta next_tree
    sta game_running
    sta score

    rts
;###

;### Check busy flag of lcd to ensure instructions don't get lost
lcd_wait:
    pha ; temp store contents of "a" register

    lda #%00000000
    sta DDRB
lcd_busy:
    lda #RW
    sta PORTA

    lda #(RW | E)
    sta PORTA
    lda PORTB
    and #%10000000
    bne lcd_busy

    lda #RW
    sta PORTA

    lda #%11111111
    sta DDRB

    pla

    rts
; ###

; ### Send a command to the lcd (e.g. set cursor position)
    ; assumes number is loaded into "a" register before calling
send_lcd_cmd:
    jsr lcd_wait ; ensure it's not already doing something

    sta PORTB

    ; clear RS/RW/E bits
    lda #0         
    sta PORTA
    
    ; set E bit to send instruction
    lda #E         
    sta PORTA
    
    ; clear RS/RW/E bits
    lda #0         
    sta PORTA

    rts

; ### Send a data to the lcd (e.g. which character to pring)
    ; assumes number is loaded into "a" register before calling
send_lcd_data:
    jsr lcd_wait

    sta PORTB

    ; set RS and clear RW/E bits
    lda #RS         
    sta PORTA

    ; set E bit to send instruction
    lda #(RS | E)   
    sta PORTA

    ; clear E bits
    lda #RS         
    sta PORTA
    
    rts
;###

    .org $fffc  ; after fffc write the .word items
    .word reset
    .word $0000 ; padding to ensure correct file length
