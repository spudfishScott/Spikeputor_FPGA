--------------------------------------------------------------------------------
--
--   FileName:         ps2_keyboard.vhd
--   Dependencies:     debounce.vhd
--   Design Software:  Quartus II 32-bit Version 12.1 Build 177 SJ Full Version
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 11/25/2013 Scott Larson
--     Initial Public Release
--    
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY PS2_KEYBOARD IS
  GENERIC(
    clk_freq              : INTEGER := 50_000_000       -- system clock frequency in Hz
--    debounce_counter_size : INTEGER := 8                -- set such that (2^size)/clk_freq = 5us (size = 8 for 50MHz)
  );

  PORT(
    clk          : IN  STD_LOGIC;                       -- system clock
    ps2_clk      : IN  STD_LOGIC;                       -- clock signal from PS/2 keyboard
    ps2_data     : IN  STD_LOGIC;                       -- data signal from PS/2 keyboard
    ps2_code_new : OUT STD_LOGIC;                       -- flag that new PS/2 code is available on ps2_code bus
    ps2_code     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)     -- code received from PS/2
  );
END PS2_KEYBOARD;

ARCHITECTURE logic OF PS2_KEYBOARD IS
 -- SIGNAL ps2_clk_int  : STD_LOGIC;                   -- debounced clock signal from PS/2 keyboard
 -- SIGNAL ps2_data_int : STD_LOGIC;                   -- debounced data signal from PS/2 keyboard
  
  SIGNAL ps2_prev_clk : STD_LOGIC;                   -- previous PS/2 clock signal for synchronous edge detection
  SIGNAL ps2_word     : STD_LOGIC_VECTOR(10 DOWNTO 0);      -- stores the ps2 data word
  SIGNAL error        : STD_LOGIC;                          -- validate parity, start, and stop bits
  SIGNAL count_idle   : INTEGER RANGE 0 TO clk_freq/18_000; -- counter to determine PS/2 is idle - 55 uSec
	 
BEGIN

    --debounce PS2 input signals - apparently, these are required to screen out noisy PS2 signals
--    debounce_ps2_clk: entity work.DEBOUNCE 
--        GENERIC MAP (
--            counter_size => debounce_counter_size
--        ) 
--        
--        PORT MAP (
--            clk    => clk,
--            button => ps2_clk,
--            result => ps2_clk_int
--        );
--
--    debounce_ps2_data: entity work.DEBOUNCE
--        GENERIC MAP (
--            counter_size => debounce_counter_size
--        )
--
--        PORT MAP ( 
--            clk    => clk,
--            button => ps2_data,
--            result => ps2_data_int
--        );
	
    -- verify that parity, start, and stop bits are all correct
    error <= NOT (NOT ps2_word(0) AND ps2_word(10) AND (ps2_word(9) XOR ps2_word(8) XOR
            ps2_word(7) XOR ps2_word(6) XOR ps2_word(5) XOR ps2_word(4) XOR ps2_word(3) XOR 
            ps2_word(2) XOR ps2_word(1)));  

    -- determine if PS2 port is idle (i.e. last transaction is finished) and output result
    PROCESS(clk)
    BEGIN
        IF (rising_edge(clk)) THEN              -- rising edge of system clock
				
		      ps2_prev_clk <= ps2_clk;			-- capture previous ps2 clock value every system clock tick
				
		      IF (ps2_clk = '0' and ps2_prev_clk = '1') THEN      -- detect falling edge of PS2 clock
                ps2_word <= ps2_data & ps2_word(10 DOWNTO 1);   -- shift in PS2 data bit
				END IF;
				                                                -- keep track of how long ps2 clock is high
            IF (ps2_clk = '0') THEN                     -- low PS2 clock, PS/2 is active
                count_idle <= 0;                            -- reset idle counter
            ELSIF (count_idle /= clk_freq/18_000) THEN      -- PS2 clock has been high less than a half clock period (<55us)
                count_idle <= count_idle + 1;               -- continue counting
            END IF;
            
            IF (count_idle = clk_freq/18_000 AND error = '0') THEN  -- idle threshold reached and no errors detected
                ps2_code_new <= '1';                                -- set flag that new PS/2 code is available
					 ps2_code <= ps2_word(8 DOWNTO 1);                   -- output new PS/2 code
            ELSE                                                    -- PS/2 port active or error detected
                ps2_code_new <= '0';                                -- set flag that PS/2 transaction is in progress
            END IF;
        END IF;
    END PROCESS;
  
END logic;
