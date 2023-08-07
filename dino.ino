//##############################################################################
//#
//# Dino game for arduino (no library required)
//# Wrote this to check my game logic for assembly code (not identical)
//# Nikolai Herrmann, 06/08/2023
//#
//##############################################################################

// Arduino Pins
#define RS 13
#define RW 12
#define E 11
#define BUTTON 10
uint8_t const DATA_PINS[8] = {2, 3, 4, 5, 6, 7, 8, 9};
//

// Custom characters
uint8_t const DINO[8] = {0b00000111, 0b00000101, 0b00000111, 0b00010110, 0b00011111, 0b00011110, 0b00001010, 0b00001010};
#define DINO_CGRAM_LOC 0
uint8_t const TREE[8] = {0b00000100, 0b00000101, 0b00010101, 0b00010101, 0b00010110, 0b00001100, 0b00000100, 0b00000100};
#define TREE_CGRAM_LOC 1
//

// Global variables
#define STARTING_UPDATE_RATE 250
uint64_t update_rate = STARTING_UPDATE_RATE;
uint64_t past_millis = 0;
uint8_t button_pressed = 0;
uint8_t jump_height = 0;
uint8_t game_running = 0;
uint16_t trees_bitboard = 0;
uint16_t next_tree = 0;
uint64_t score = 0;
//

void send_8_bits(uint8_t data)
{
  for (uint8_t pin_idx = 0, bit_idx = 1; pin_idx < 8; ++pin_idx, bit_idx <<= 1)
    digitalWrite(DATA_PINS[pin_idx], data & bit_idx);
}

void send_lcd_cmd(uint8_t data)
{
  send_8_bits(data);

  digitalWrite(RS, LOW);
  digitalWrite(RW, LOW);
  digitalWrite(E, LOW);
  delayMicroseconds(1);

  digitalWrite(E, HIGH);
  delayMicroseconds(1);

  digitalWrite(RS, LOW);
  digitalWrite(RW, LOW);
  digitalWrite(E, LOW);
  delayMicroseconds(100);
}

void send_lcd_data(uint8_t data)
{
  send_8_bits(data);

  digitalWrite(RS, HIGH);
  digitalWrite(RW, LOW);
  digitalWrite(E, LOW);
  delayMicroseconds(1);

  digitalWrite(E, HIGH);
  delayMicroseconds(1);

  digitalWrite(E, LOW);
  delayMicroseconds(100);
}

void upload_custom_char(uint8_t const *const data, uint8_t location)
{
  uint8_t cgram_address = 0b01000000 + (8 * location);
  send_lcd_cmd(cgram_address);

  for (uint8_t i = 0; i < 8; ++i)
    send_lcd_data(data[i]);
}

void display_text(char const *const data, uint64_t length)
{
  for (uint64_t i = 0; i < length; ++i)
    send_lcd_data(data[i]);
}

void clear_display()
{
  send_lcd_cmd(0b00000001);
  delayMicroseconds(2000);
}

/*
  row: [0, 1]
  col: [0, 15]
*/
void set_cursor(uint8_t row, uint8_t col)
{
  uint8_t ddram_address = 0b10000000 | (row * 64) | col;
  send_lcd_cmd(ddram_address);
}

void setup()
{
  // Arduino pin setup
  pinMode(RS, OUTPUT);
  pinMode(RW, OUTPUT);
  pinMode(E, OUTPUT);
  pinMode(BUTTON, INPUT);

  for (uint8_t i = 0; i < 8; ++i)
    pinMode(DATA_PINS[i], OUTPUT);
  //

  // Setup lcd screen
  delayMicroseconds(50000); // wait for lcd to startup

  send_lcd_cmd(0b00111000); // set 8-bit mode, 2-line display and 5x8 font
  send_lcd_cmd(0b00001100); // turn on display, turn off cursor and blinking cursor

  upload_custom_char(DINO, DINO_CGRAM_LOC);
  upload_custom_char(TREE, TREE_CGRAM_LOC);

  clear_display();

  display_text("Press to start ", 15);
  send_lcd_data(DINO_CGRAM_LOC);
  //
}

void loop()
{
  // Check user interaction
  if (digitalRead(BUTTON))
    button_pressed = 1;
  //

  // Has enough time passed since last screen update
  uint64_t current_millis = millis();
  if (current_millis - past_millis < update_rate)
    return;
  past_millis = current_millis;
  //

  // Check if game has started with initial button press
  if (!game_running)
  {
    if (button_pressed)
    {
      game_running = 1;
      button_pressed = 0;
      delay(250);
    }
    else
      return;
  }
  //

  // Clear screen before drawing all items
  clear_display();
  //

  // Draw dino on top (0) or bottom row (1)
  if (jump_height)
  {
    if (jump_height == 3)
    {
      set_cursor(1, 2);
      jump_height = 0;
      button_pressed = 0;
    }
    else
    {
      set_cursor(0, 2);
      jump_height++;
    }
  }
  else if (button_pressed)
  {
    set_cursor(0, 2);
    jump_height = 1;
  }
  else
    set_cursor(1, 2);

  send_lcd_data(DINO_CGRAM_LOC);
  //

  // Draw trees
  for (uint16_t i = 0; i < 16; ++i)
  {
    if (trees_bitboard & (1 << i))
    {
      set_cursor(1, 15 - i);
      send_lcd_data(TREE_CGRAM_LOC);
    }
  }

  trees_bitboard <<= 1; // move all trees up one bit
  //

  // Add new trees on right side of lcd
  if (next_tree == 10)
  {
    trees_bitboard |= 1;
    next_tree = 0;
  }
  else
    next_tree++;
  //

  // Check collision, either stop game or increase player score
  if (trees_bitboard & 0b0010000000000000)
  {
    if (jump_height == 0)
      game_running = 0;
    else
    {
      score++;
      if (score % 5 == 0)
        update_rate -= update_rate / 4; // increase game speed
    }
  }
  //

  // Draw score on lcd
  uint64_t score_remainder = score;
  uint8_t col = 15;
  do
  {
    set_cursor(0, col--);
    send_lcd_data('0' + (score_remainder % 10));
    score_remainder /= 10;
  } while (score_remainder);
  //

  // Reset game variables and display "game over" text if player lost
  if (!game_running)
  {
    button_pressed = 0;
    trees_bitboard = 0;
    jump_height = 0;
    next_tree = 0;
    score = 0;
    update_rate = STARTING_UPDATE_RATE;
    delay(500); // briefly pause before showing text
    set_cursor(0, 0);
    display_text("Game over!", 10);
  }
  //
}
