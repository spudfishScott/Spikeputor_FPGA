--------------------------------------------------------------------------------
--
--   FileName:         ps2_transceiver.vhd
--   Dependencies:     debounce.vhd
--   Design Software:  Quartus II 64-bit Version 13.1.0 Build 162 SJ Web Edition
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
--   Version 1.0 1/19/2018 Scott Larson
--     Initial Public Release
--    Modified by Scott Berk
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY ps2_transceiver IS
    GENERIC(
        CLK_FREQ     : INTEGER := 50_000_000            -- system clock frequency in Hz (default 50 MHz)
    );
    PORT(
        clk          : IN     STD_LOGIC;                            -- system clock
        reset_n      : IN     STD_LOGIC;                            -- active low asynchronous reset
        tx_ena       : IN     STD_LOGIC;                            -- enable transmit
        tx_cmd       : IN     STD_LOGIC_VECTOR(8 DOWNTO 0);         -- 8-bit command to transmit, MSB is parity bit
        tx_busy      : OUT    STD_LOGIC;                            -- indicates transmit in progress
        ack_error    : OUT    STD_LOGIC;                            -- device acknowledge from transmit, '1' is error
        ps2_code     : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0);         -- code received from PS/2
        ps2_code_new : OUT    STD_LOGIC;                            -- flag that new PS/2 code is available on ps2_code bus
        rx_error     : OUT    STD_LOGIC;                            -- start, stop, or parity receive error detected, '1' is error
        ps2_clk      : INOUT  STD_LOGIC;                            -- PS/2 port clock signal
        ps2_data     : INOUT  STD_LOGIC
    );                   --PS/2 port data signal
END ps2_transceiver;

ARCHITECTURE logic OF ps2_transceiver IS
    TYPE machine IS(receive, inhibit, transact, tx_complete);          -- needed states
    SIGNAL state            : machine := receive;                      -- state machine
    SIGNAL ps2_clk_sync     : STD_LOGIC;                               -- synchronizer flip-flop for PS/2 clock signal
    SIGNAL ps2_clk_int      : STD_LOGIC;                               -- debounced input clock signal from PS/2 port
    SIGNAL ps2_clk_int_prev : STD_LOGIC;                               -- previous state of the ps2_clk_int signal
    SIGNAL ps2_data_sync    : STD_LOGIC;                               -- synchronoizer flip-flop for PS/2 data signal
    SIGNAL ps2_data_int     : STD_LOGIC;                               -- debounced input data signal from PS/2 port
    SIGNAL ps2_word         : STD_LOGIC_VECTOR(10 DOWNTO 0);           -- stores the ps2 data word (both tx and rx)
    SIGNAL error            : STD_LOGIC;                               -- validate parity, start, and stop bits for received data
    SIGNAL timer            : INTEGER RANGE 0 TO CLK_FREQ/10_000 := 0; -- counter to determine both inhibit period and when PS/2 is idle
    SIGNAL bit_cnt          : INTEGER RANGE 0 TO 11 := 0;              -- count the number of clock pulses during transmit

    -- Quartus Prime specific synchronizer attributes to identify synchronized signals for analysis
    attribute altera_attribute : string;
    attribute altera_attribute of ps2_clk_sync, ps2_clk_int   : signal is "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
    attribute altera_attribute of ps2_data_sync, ps2_data_int : signal is "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";

BEGIN
    -- synchronize incoming PS/2 signals
    PROCESS(clk)
    BEGIN
        IF (rising_edge(clk)) THEN      -- rising edge of system clock
            ps2_clk_sync  <= ps2_clk;            -- synchronize PS/2 clock signal
            ps2_clk_int   <= ps2_clk_sync;

            ps2_data_sync <= ps2_data;           -- synchronize PS/2 data signal
            ps2_data_int  <= ps2_data_sync;
        END IF;
    END PROCESS;

  -- verify that parity, start, and stop bits are all correct for received data
  error <= NOT (NOT ps2_word(0) AND ps2_word(10) AND (ps2_word(9) XOR ps2_word(8) XOR
        ps2_word(7) XOR ps2_word(6) XOR ps2_word(5) XOR ps2_word(4) XOR ps2_word(3) XOR 
        ps2_word(2) XOR ps2_word(1)));  

  -- state machine to control transmit and receive processes
  PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN        -- rising edge of system clock
        IF (reset_n = '0') THEN                  -- reset PS/2 transceiver
            ps2_clk      <= '0';                    -- inhibit communication on PS/2 bus
            ps2_data     <= 'Z';                    -- release PS/2 data line
            tx_busy      <= '1';                    -- indicate that no transmit is in progress
            ack_error    <= '0';                    -- clear acknowledge error flag
            ps2_code     <= (OTHERS => '0');        -- clear received PS/2 code
            ps2_code_new <= '0';                    -- clear new received PS/2 code flag
            rx_error     <= '0';                    -- clear receive error flag
            ps2_clk_int_prev <= '0';                -- clear previous value of the PS/2 clock signal
            ps2_word      <= (OTHERS => '0');       -- clear PS/2 data buffer
            state        <= receive;                -- set state machine to receive state
        ELSE                        -- not reset
            ps2_clk_int_prev <= ps2_clk_int;        -- store previous value of the PS/2 clock signal

            CASE state IS                           -- implement state machine
                WHEN receive =>
                    IF (tx_ena = '1') THEN                                  -- transmit requested
                        tx_busy <= '1';                                        -- indicate transmit in progress
                        timer   <= 0;                                          -- reset timer for inhibit timing
                        ps2_word(9 DOWNTO 0) <= tx_cmd & '0';                  -- load parity, command, and start bit into PS/2 data buffer
                        bit_cnt <= 0;                                          -- clear bit counter
                        state <= inhibit;                                      -- inhibit communication to begin transaction
                    ELSE                                                   -- transmit not requested
                        tx_busy <= '0';                                        -- indicate no transmit in progress
                        ps2_clk <= 'Z';                                        -- release PS/2 clock port
                        ps2_data <= 'Z';                                       -- release PS/2 data port

                        -- clock in receive data
                        IF (ps2_clk_int_prev = '1' AND ps2_clk_int = '0') THEN      -- falling edge of PS2 clock
                            ps2_word <= ps2_data_int & ps2_word(10 DOWNTO 1);       -- shift contents of PS/2 data buffer
                        END IF;

                        -- determine if PS/2 port is idle 
                        IF (ps2_clk_int = '0') THEN                            -- low PS2 clock, PS/2 is active
                            timer <= 0;                                            -- reset idle counter
                        ELSIF (timer < CLK_FREQ/18_000) THEN                   -- PS2 clock has been high less than a half clock period (<55us)
                            timer <= timer + 1;                                    -- continue counting
                        END IF;

                        -- output received data and port status          
                        IF (timer = CLK_FREQ/18_000) THEN                      -- idle threshold reached
                            IF (error = '0') THEN                                  -- no error detected
                                ps2_code_new <= '1';                                   -- set flag that new PS/2 code is available
                                ps2_code <= ps2_word(8 DOWNTO 1);                      -- output new PS/2 code
                            ELSIF (error = '1') THEN                               -- error detected
                                rx_error <= '1';                                       -- set receive error flag
                            END IF;
                        ELSE                                                   -- PS/2 port active
                            rx_error <= '0';                                       -- clear receive error flag
                            ps2_code_new <= '0';                                   -- set flag that PS/2 transaction is in progress
                        END IF;
                        state <= receive;                                      -- continue streaming receive transactions
                    END IF;
                
                WHEN inhibit =>
                    IF (timer < CLK_FREQ/10_000) THEN     -- first 100us not complete
                        timer <= timer + 1;                  -- increment timer
                        ps2_data <= 'Z';                     -- release data port
                        ps2_clk <= '0';                      -- inhibit communication
                        state <= inhibit;                    -- continue inhibit
                    ELSE                                  -- 100us complete
                        ps2_data <= ps2_word(0);             -- output start bit to PS/2 data port
                        state <= transact;                   -- proceed to send bits
                    END IF;
                
                WHEN transact =>
                    ps2_clk <= 'Z';                                         -- release clock port
                    IF (ps2_clk_int_prev = '1' AND ps2_clk_int = '0') THEN  -- falling edge of PS2 clock
                        ps2_word <= ps2_data_int & ps2_word(10 DOWNTO 1);       -- shift contents of PS/2 data buffer
                        bit_cnt <= bit_cnt + 1;                                 -- count clock falling edges
                    END IF;

                    IF (bit_cnt < 10) THEN                                  -- all bits not sent
                        ps2_data <= ps2_word(0);                                -- connect serial output of PS/2 data buffer to data port
                    ELSE                                                    -- all bits sent
                        ps2_data <= 'Z';                                        -- release data port
                    END IF;

                    IF (bit_cnt = 11) THEN                                  -- acknowledge bit received
                        ack_error <= ps2_data_int;                              -- set error flag if acknowledge is not '0'
                        state <= tx_complete;                                   -- proceed to wait until the slave releases the bus
                    ELSE                                                    -- acknowledge bit not received
                        state <= transact;                                      -- continue transaction
                    END IF;
                    
                WHEN tx_complete =>
                    IF (ps2_clk_int = '1' AND ps2_data_int = '1') THEN  -- device has released the bus
                        state <= receive;                                   -- proceed to receive data state
                    ELSE                                                -- bus not released by device
                        state <= tx_complete;                               -- wait for device to release bus                    
                    END IF;

                WHEN others =>          -- should never happen
                    state <= receive;
            END CASE;
            END IF;
        END IF;
  END PROCESS;
  
END logic;


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
--    modified by Scott Berk, 2025
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY PS2_KEYBOARD IS
    GENERIC (
        CLK_FREQ              : INTEGER := 50_000_000       -- system clock frequency in Hz
    );

    PORT (
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
    SIGNAL count_idle   : INTEGER RANGE 0 TO CLK_FREQ/18_000; -- counter to determine PS/2 is idle - 55 uSec

BEGIN

    -- verify that parity, start, and stop bits are all correct
    error <= NOT (NOT ps2_word(0) AND ps2_word(10) AND (ps2_word(9) XOR ps2_word(8) XOR
            ps2_word(7) XOR ps2_word(6) XOR ps2_word(5) XOR ps2_word(4) XOR ps2_word(3) XOR 
            ps2_word(2) XOR ps2_word(1)));  

    -- determine if PS2 port is idle (i.e. last transaction is finished) and output result
    PROCESS(clk)
    BEGIN
        IF (rising_edge(clk)) THEN              -- rising edge of system clock

            ps2_prev_clk <= ps2_clk;            -- capture previous ps2 clock value every system clock tick

            IF (ps2_clk = '0' and ps2_prev_clk = '1') THEN      -- detect falling edge of PS2 clock
                ps2_word <= ps2_data & ps2_word(10 DOWNTO 1);   -- shift in PS2 data bit
            END IF;
                                                        -- keep track of how long ps2 clock is high
            IF (ps2_clk = '0') THEN                     -- low PS2 clock, PS/2 is active
                count_idle <= 0;                            -- reset idle counter
            ELSIF (count_idle /= CLK_FREQ/18_000) THEN      -- PS2 clock has been high less than a half clock period (<55us)
                count_idle <= count_idle + 1;               -- continue counting
            END IF;

            IF (count_idle = CLK_FREQ/18_000 AND error = '0') THEN  -- idle threshold reached and no errors detected
                ps2_code_new <= '1';                                -- set flag that new PS/2 code is available
                ps2_code <= ps2_word(8 DOWNTO 1);                   -- output new PS/2 code
            ELSE                                                    -- PS/2 port active or error detected
                ps2_code_new <= '0';                                -- set flag that PS/2 transaction is in progress
            END IF;
        END IF;
    END PROCESS;

END logic;

