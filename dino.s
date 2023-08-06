; 6052 has 16 address lines: 0000 to FFFF
; ROM has 15 address lines: 0000 to 7FFF
; Use addresses from 8000 to FFFF since 6052 looks at FFFD and FFFE on startup to get first instructions 

; Use # for data (i.e raw numeric values)

; 6052 interface uses addresses 6000 to 7FFF


; push onto stack   pha
; pull off stack    pla
; stack from 0100 to 01ff

; txs transfer register x to stack

; and updates zero flag


;0x00 to 0x27 for first line
;0x40 to 0x67 for second line
; There are 16 spots per line

    ;lda #%10000001
    ;jsr send_lcd_cmd

    ;lda #%00100101
    ;jsr send_lcd_data

    ;lda #%11000010
    ;jsr send_lcd_cmd

    ;lda #%00100101
    ;jsr send_lcd_data 

    ;cli ; allow for interrupts   


DDRB = $6002    ; data direction register "B" (do we use it for input or output)
PORTB = $6000

DDRA = $6003
PORTA = $6001

port_a_output = $0200
prev_port_a_output = $0201
jump_height = $0202
next_tree = $0203
trees_bitboard = $0204
bit_shift_state = $0206
lcd_location = $0207
game_running = $0208
score = $0209


E  = %10000000
RW = %01000000
RS = %00100000

    .org $8000 ; tell processor that we start at address 8000, where to look first

reset:

;### Set IO LCD ports    
    lda #%11111111 ; Port B: set all pins to output
    sta DDRB

    lda #%11100000 ; Port A: set last 3 pins to output
    sta DDRA
;### End

;### Init LCD display
    ; Set 8-bit mode; 2-line display; 5x8 font
    lda #%00111000 
    jsr send_lcd_cmd

    ; Display on; cursor on; blink off
    lda #%00001100 
    jsr send_lcd_cmd

    ; Increment and shift cursor; don't shift display
    lda #%00000110 
    jsr send_lcd_cmd

    ; Clear display
    lda #$00000001 
    jsr send_lcd_cmd
;### End

;#### Load dino
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
;### End 

;#### Load tree
    lda #%01001000 ; going to next 8 bytes
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
;### End

    jsr init_global_variables

;### Show start message
    ; Clear display and set DDRAM address back to 0
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
;### End


loop:
    ; store previous port a output before getting new one
    lda port_a_output
    sta prev_port_a_output 

    ; store new port a output
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

    lda port_a_output ; check if button was pressed
    and #%00001000
    beq loop ; if zero user has not started game yet

    lda #1
    sta game_running

    ; set button press to zero
    lda port_a_output
    and #%11110111 
    sta port_a_output  

draw_game:
    ; clear display before drawing everything
    lda #%00000001 
    jsr send_lcd_cmd

;### Draw dino
    lda jump_height
    bne in_a_jump ; check if dino is currently in a jump

    lda port_a_output
    and #%00001000 
    bne button_press ; check if button was pressed

    ; no button pressed nor in a jump
    lda #%11000010 ; set cursor to bottom third spot
    jsr send_lcd_cmd 
    jmp draw_dino

button_press:
    lda #%10000010 ; set cursor to top third spot
    jsr send_lcd_cmd

    lda #1
    sta jump_height

    jmp draw_dino

in_a_jump:
    lda jump_height
    cmp #3
    beq at_peak_of_jump

    lda #%10000010 ; set cursor to top third spot
    jsr send_lcd_cmd

    ldx jump_height ; increment jump height
    inx
    stx jump_height

    jmp draw_dino

at_peak_of_jump:
    lda #%11000010 ; set cursor to bottom third spot (jump back down)
    jsr send_lcd_cmd

    lda #0
    sta jump_height

    ; set jump to zero
    lda port_a_output
    and #%11110111 
    sta port_a_output 

draw_dino:
    lda #%00000000
    jsr send_lcd_data
; ### End draw dino


    ; draw trees
    lda #15
    sta lcd_location

    lda #1
    sta bit_shift_state

    ldx #0
cycle_tree_bits:
    lda trees_bitboard, x
    and bit_shift_state
    beq end_tree_draw

    lda #%11000000 ; set cursor for tree
    ora lcd_location
    jsr send_lcd_cmd

    lda #%00000001 ; draw tree
    jsr send_lcd_data

end_tree_draw:
    lda lcd_location
    beq shift_trees

    clc ; clear carry bit
    lda bit_shift_state
    adc bit_shift_state ; double it
    sta bit_shift_state

    lda lcd_location
    cmp #8
    bne not_next_tree_byte
    inx
    lda #1
    sta bit_shift_state

not_next_tree_byte:
    ldy lcd_location
    dey
    sty lcd_location

    jmp cycle_tree_bits

shift_trees:
    clc
    lda trees_bitboard + 1
    adc trees_bitboard + 1
    sta trees_bitboard + 1

    clc
    lda trees_bitboard
    adc trees_bitboard
    sta trees_bitboard

    lda trees_bitboard + 1
    bcc no_tree_move ; check carry
    ora #1
    sta trees_bitboard + 1

no_tree_move:
    ; add new tree
    lda next_tree
    cmp #10
    bne tree_count_inc

    lda trees_bitboard
    ora #1
    sta trees_bitboard

    lda #0
    sta next_tree

    jmp tree_end_end

tree_count_inc:
    ldy next_tree
    iny
    sty next_tree

tree_end_end:

    
    
;### Check if game is over
    lda trees_bitboard + 1
    and #%00100000
    beq end_collision_check

    lda jump_height
    bne update_score

    ; game over
    lda #0
    sta game_running

    ; Print game over messsage
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
    ldx score
    inx
    stx score

end_collision_check:
;### End "game over" check


;### Draw score
    lda #%10001111 ; set cursor to last position
    jsr send_lcd_cmd

    ; print last digit
    lda score
    jsr div_10
    clc
    adc #"0"
    jsr send_lcd_data

    ; print first digit
    lda #%10001110 ; set cursor to second position
    jsr send_lcd_cmd
    txa
    clc
    adc #"0"
    jsr send_lcd_data
;### End draw score

    lda game_running
    bne repeat_main_loop
    jsr init_global_variables ; reset game

repeat_main_loop:
    jmp loop

press_to_play_msg: .asciiz "Press to play "
game_over_msg: .asciiz "Game over!"

; subroutines

; assumes number is loaded into "a" register
div_10:
    ldx #0
div_10_loop:
    sec ; set carry bit
    sbc #10
    bmi div_10_done
    inx 
    jmp div_10_loop
div_10_done:
    clc
    adc #10
    rts

init_global_variables:
;### Initialize variables
    lda #0
    sta port_a_output
    sta jump_height
    sta trees_bitboard
    sta trees_bitboard + 1
    sta next_tree
    sta game_running
    sta score
;###
    rts

lcd_wait:
    pha

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

; assumes lda instruction beforehand
send_lcd_cmd:
    jsr lcd_wait

    sta PORTB

    lda #0         ; Clear RS/RW/E bits
    sta PORTA
    
    lda #E         ; Set E bit to send instruction
    sta PORTA
    
    lda #0         ; Clear RS/RW/E bits
    sta PORTA

    rts

; assumes lda data beforehand
send_lcd_data:
    jsr lcd_wait

    sta PORTB

    lda #RS         ; Set RS; Clear RW/E bits
    sta PORTA

    lda #(RS | E)   ; Set E bit to send instruction
    sta PORTA

    lda #RS         ; Clear E bits
    sta PORTA
    
    rts

; end of subroutines

    .org $fffc  ; after fffc write the .word items
    .word reset
    .word $0000 ; padding to ensure correct file length
