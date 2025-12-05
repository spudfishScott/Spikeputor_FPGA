--------------------------------------------------------------------------------
--
--   FileName:         ps2_keyboard_to_ascii.vhd
--   Dependencies:     ps2_keyboard.vhd, debounce.vhd
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
--   Version 1.0 11/29/2013 Scott Larson
--     Initial Public Release
--   Modified by Scott Berk to include setting Caps Lock light on Keyboard
--      and implementing an eight character ring buffer
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY PS2_ASCII IS
    GENERIC (
        clk_freq                  : INTEGER := 50_000_000    -- system clock frequency in Hz
    );

    PORT (
        clk        : IN  STD_LOGIC;                           -- system clock input
        n_rst      : IN  STD_LOGIC;                           -- reset signal (active low)
        ps2_clk    : INOUT  STD_LOGIC;                        -- clock signal from PS2 keyboard
        ps2_data   : INOUT  STD_LOGIC;                        -- data signal from PS2 keyboard
        key_req    : IN STD_LOGIC;                            -- assert this input to request next key in buffer, clear it when data has been received
        ascii_new  : OUT STD_LOGIC;                           -- output flag to indicate key request has been fulfilled, 0x0000 = buffer empty
        ascii_code : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)         -- ASCII value
    );
END PS2_ASCII;

ARCHITECTURE behavior OF PS2_ASCII IS
    TYPE KEYBUF IS ARRAY(0 to 7) OF STD_LOGIC_VECTOR(6 DOWNTO 0);

    TYPE machine IS (ready, new_code, translate, addbuf, updatekb, updatekb2);   --needed states
    SIGNAL state             : machine := updatekb;                              --state machine starts with setting keyboard LEDs

    SIGNAL ps2_code_new      : STD_LOGIC := '0';                      -- new PS2 code flag from ps2_keyboard component
    SIGNAL ps2_code          : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00"; -- PS2 code input form ps2_keyboard component

    SIGNAL prev_ps2_code_new : STD_LOGIC := '1';                      -- value of ps2_code_new flag on previous clock
    SIGNAL break             : STD_LOGIC := '0';                      -- '1' for break code, '0' for make code
    SIGNAL e0_code           : STD_LOGIC := '0';                      -- '1' for multi-code commands, '0' for single code commands
    SIGNAL caps_lock         : STD_LOGIC := '0';                      -- '1' if caps lock is active, '0' if caps lock is inactive
    SIGNAL num_lock          : STD_LOGIC := '1';                      -- '1' if num lock is active, '0' if num lock is inactive
    SIGNAL control_r         : STD_LOGIC := '0';                      -- '1' if right control key is held down, else '0'
    SIGNAL control_l         : STD_LOGIC := '0';                      -- '1' if left control key is held down, else '0'
    SIGNAL shift_r           : STD_LOGIC := '0';                      -- '1' if right shift is held down, else '0'
    SIGNAL shift_l           : STD_LOGIC := '0';                      -- '1' if left shift is held down, else '0'
    SIGNAL ascii             : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"FF"; -- internal value of ASCII translation
    SIGNAL additionals       : STD_LOGIC_VECTOR(23 downto 0) := x"000000"; -- up to three additional characters to send for special control keys

    SIGNAL tx_busy_sig       : STD_LOGIC := '0';                      -- '1' if we're transmitting a command to PS/2
    SIGNAL tx_cmd_sig        : STD_LOGIC_VECTOR(8 DOWNTO 0) := "111101101"; -- command to send to PS/2, parity is bit 8
    SIGNAL tx_ena_sig        : STD_LOGIC := '0';                      -- '1' to latch the command and start sending it

    SIGNAL key_buffer        : KEYBUF := (others => (others => '0')); -- ring buffer for ASCII codes
    SIGNAL buffer_head       : INTEGER RANGE 0 TO 7 := 0;             -- points to next position to write new key
    SIGNAL buffer_tail       : INTEGER RANGE 0 TO 7 := 0;             -- points to next position to read key
    SIGNAL buffer_empty      : STD_LOGIC := '1';                      -- flag if buffer is empty

BEGIN

    --instantiate PS2 keyboard interface logic
    ps2_trans : entity work.ps2_transceiver
        GENERIC MAP (
            clk_freq        => clk_freq
        )

        PORT MAP (
            clk          => clk,                    -- system clock
            reset_n      => n_rst,                  -- active low synchronous reset
            tx_ena       => tx_ena_sig,             -- enable transmit
            tx_cmd       => tx_cmd_sig,             -- 8-bit command to transmit, MSB is parity bit
            tx_busy      => tx_busy_sig,            -- indicates transmit in progress
            ack_error    => open,                   -- device acknowledge from transmit, '1' is error
            ps2_code     => ps2_code,               -- code received from PS/2
            ps2_code_new => ps2_code_new,           -- flag that new PS/2 code is available on ps2_code bus
            rx_error     => open,                   -- start, stop, or parity receive error detected, '1' is error
            ps2_clk      => ps2_clk,                -- PS/2 port clock signal
            ps2_data     => ps2_data                -- PS/2 port data signal
        );

    -- state machine to process PS2 codes and output ASCII values
    PROCESS(clk)
    BEGIN
        IF (rising_edge(clk)) THEN

            IF (n_rst = '0') THEN                   -- reset all signals and variables
                state <= updatekb;                  -- start by sending caps lock state to keyboard
                break <= '0';
                e0_code <= '0';
                caps_lock <= '0';
                num_lock <= '1';
                control_r <= '0';
                control_l <= '0';
                shift_r <= '0';
                shift_l <= '0';
                ascii <= x"FF";
                buffer_head <= 0;
                buffer_tail <= 0;
                buffer_empty <= '1';
                ascii_new <= '0';
                ascii_code <= (others => '0');
            ELSE
                prev_ps2_code_new <= ps2_code_new;  -- keep track of previous ps2_code_new values to determine low-to-high transitions
                ascii_new <= '0';                                           --  ascii_new is a one-clock strobe

                CASE state IS
                    -- ready state: wait for a new PS2 code to be received or a new key request from the buffer
                    WHEN ready =>
                        tx_ena_sig <= '0';                                          -- turn off transmit signal

                        IF (prev_ps2_code_new = '0' AND ps2_code_new = '1') THEN    -- new PS2 code received
                            state <= new_code;                                      -- proceed to new_code state
                        ELSE                                                        -- no new PS2 code received yet
                            state <= ready;                                         -- remain in ready state
                        END IF;

                        IF (key_req = '1') THEN                                     -- key requested
                            IF buffer_empty = '0' THEN                              -- Buffer has characters in it
                                ascii_code <= key_buffer(buffer_tail);              -- output the next ASCII code from the buffer
                                buffer_tail <= (buffer_tail + 1) MOD 8;             -- advance tail pointer
                                IF (buffer_tail + 1) MOD 8 = buffer_head THEN       -- mark buffer empty if tail will = head after this character
                                    buffer_empty <= '1';
                                END IF;
                            ELSE                                                    -- ouput 0x00 when buffer is empty
                                ascii_code <= (others => '0');
                            END IF;
                            ascii_new <= '1';                                       -- set new ASCII code indicator
                        END IF;

                    -- new_code state: determine what to do with the new PS2 code  
                    WHEN new_code =>
                        IF (ps2_code = x"F0") THEN      -- code indicates that next command is break
                            break <= '1';               -- set break flag
                            state <= ready;             -- return to ready state to await next PS2 code
                        ELSIF (ps2_code = x"E0") THEN   -- code indicates multi-key command
                            e0_code <= '1';             -- set multi-code command flag
                            state <= ready;             -- return to ready state to await next PS2 code
                        ELSIF (ps2_code = x"FA") THEN   -- sent to acknowledge that the keyboard recived a command
                            IF tx_cmd_sig = "111101101" THEN -- last command sent was SET/RESET mode indicators
                                state <= updatekb2;     -- send the option byte
                            ELSE
                                state <= ready;         -- listen for the next PS2 code
                            END IF;
                        ELSE                            -- code is the last PS2 code in the make/break code
                            ascii(7) <= '1';            -- set internal ascii value to unsupported code (for verification)
                            state <= translate;         -- proceed to translate state
                    END IF;

                    -- translate state: translate PS2 code to ASCII value
                    WHEN translate =>
                        additionals <= (others => '0');         -- reset additional keystrokes by default
                        
                        -- handle codes for control, shift, and caps lock
                        CASE ps2_code IS
                            WHEN x"58" =>                       -- caps lock code
                                IF (break = '0') THEN           -- if make command
                                    caps_lock <= NOT caps_lock; -- toggle caps lock
                                END IF;
                            WHEN x"77" =>                       -- num lock code
                                IF (break = '0') THEN           -- if make command
                                    num_lock <= NOT num_lock;   -- toggle num lock
                                END IF;
                            WHEN x"14" =>                       -- code for the control keys
                                IF (e0_code = '1') THEN         -- code for right control
                                    control_r <= NOT break;     -- update right control flag
                                ELSE                            -- code for left control
                                    control_l <= NOT break;     -- update left control flag
                                END IF;
                            WHEN x"12" =>                       -- left shift code
                                shift_l <= NOT break;           -- update left shift flag
                            WHEN x"59" =>                       -- right shift code
                                shift_r <= NOT break;           -- update right shift flag
                            WHEN OTHERS => NULL;
                        END CASE;

                        -- translate letters (these depend on both shift and caps lock)
                        IF ((shift_r = '0' AND shift_l = '0' AND caps_lock = '0') OR
                            ((shift_r = '1' OR shift_l = '1') AND caps_lock = '1')) THEN  -- letter is lowercase
                            CASE ps2_code IS              
                                WHEN x"1C" => ascii <= x"61"; -- a
                                WHEN x"32" => ascii <= x"62"; -- b
                                WHEN x"21" => ascii <= x"63"; -- c
                                WHEN x"23" => ascii <= x"64"; -- d
                                WHEN x"24" => ascii <= x"65"; -- e
                                WHEN x"2B" => ascii <= x"66"; -- f
                                WHEN x"34" => ascii <= x"67"; -- g
                                WHEN x"33" => ascii <= x"68"; -- h
                                WHEN x"43" => ascii <= x"69"; -- i
                                WHEN x"3B" => ascii <= x"6A"; -- j
                                WHEN x"42" => ascii <= x"6B"; -- k
                                WHEN x"4B" => ascii <= x"6C"; -- l
                                WHEN x"3A" => ascii <= x"6D"; -- m
                                WHEN x"31" => ascii <= x"6E"; -- n
                                WHEN x"44" => ascii <= x"6F"; -- o
                                WHEN x"4D" => ascii <= x"70"; -- p
                                WHEN x"15" => ascii <= x"71"; -- q
                                WHEN x"2D" => ascii <= x"72"; -- r
                                WHEN x"1B" => ascii <= x"73"; -- s
                                WHEN x"2C" => ascii <= x"74"; -- t
                                WHEN x"3C" => ascii <= x"75"; -- u
                                WHEN x"2A" => ascii <= x"76"; -- v
                                WHEN x"1D" => ascii <= x"77"; -- w
                                WHEN x"22" => ascii <= x"78"; -- x
                                WHEN x"35" => ascii <= x"79"; -- y
                                WHEN x"1A" => ascii <= x"7A"; -- z
                                WHEN OTHERS => NULL;
                            END CASE;
                        ELSE                                     --letter is uppercase
                            CASE ps2_code IS            
                                WHEN x"1C" => ascii <= x"41"; -- A
                                WHEN x"32" => ascii <= x"42"; -- B
                                WHEN x"21" => ascii <= x"43"; -- C
                                WHEN x"23" => ascii <= x"44"; -- D
                                WHEN x"24" => ascii <= x"45"; -- E
                                WHEN x"2B" => ascii <= x"46"; -- F
                                WHEN x"34" => ascii <= x"47"; -- G
                                WHEN x"33" => ascii <= x"48"; -- H
                                WHEN x"43" => ascii <= x"49"; -- I
                                WHEN x"3B" => ascii <= x"4A"; -- J
                                WHEN x"42" => ascii <= x"4B"; -- K
                                WHEN x"4B" => ascii <= x"4C"; -- L
                                WHEN x"3A" => ascii <= x"4D"; -- M
                                WHEN x"31" => ascii <= x"4E"; -- N
                                WHEN x"44" => ascii <= x"4F"; -- O
                                WHEN x"4D" => ascii <= x"50"; -- P
                                WHEN x"15" => ascii <= x"51"; -- Q
                                WHEN x"2D" => ascii <= x"52"; -- R
                                WHEN x"1B" => ascii <= x"53"; -- S
                                WHEN x"2C" => ascii <= x"54"; -- T
                                WHEN x"3C" => ascii <= x"55"; -- U
                                WHEN x"2A" => ascii <= x"56"; -- V
                                WHEN x"1D" => ascii <= x"57"; -- W
                                WHEN x"22" => ascii <= x"58"; -- X
                                WHEN x"35" => ascii <= x"59"; -- Y
                                WHEN x"1A" => ascii <= x"5A"; -- Z
                                WHEN OTHERS => NULL;
                            END CASE;
                        END IF;
                        
                        -- translate numbers and symbols (these depend on shift but not caps lock)
                        IF (shift_l = '1' OR shift_r = '1') THEN  -- key's secondary character is desired
                            CASE ps2_code IS              
                                WHEN x"16" => ascii <= x"21"; -- !
                                WHEN x"52" => ascii <= x"22"; -- "
                                WHEN x"26" => ascii <= x"23"; -- #
                                WHEN x"25" => ascii <= x"24"; -- $
                                WHEN x"2E" => ascii <= x"25"; -- %
                                WHEN x"3D" => ascii <= x"26"; -- &
                                WHEN x"46" => ascii <= x"28"; -- (
                                WHEN x"45" => ascii <= x"29"; -- )
                                WHEN x"3E" => ascii <= x"2A"; -- *
                                WHEN x"55" => ascii <= x"2B"; -- +
                                WHEN x"4C" => ascii <= x"3A"; -- :
                                WHEN x"41" => ascii <= x"3C"; -- <
                                WHEN x"49" => ascii <= x"3E"; -- >
                                WHEN x"4A" => ascii <= x"3F"; -- ?
                                WHEN x"1E" => ascii <= x"40"; -- @
                                WHEN x"36" => ascii <= x"5E"; -- ^
                                WHEN x"4E" => ascii <= x"5F"; -- _
                                WHEN x"54" => ascii <= x"7B"; -- {
                                WHEN x"5D" => ascii <= x"7C"; -- |
                                WHEN x"5B" => ascii <= x"7D"; -- }
                                WHEN x"0E" => ascii <= x"7E"; -- ~
                                WHEN OTHERS => NULL;
                            END CASE;
                        ELSE                                     -- key's primary character is desired
                            CASE ps2_code IS  
                                WHEN x"45" => ascii <= x"30"; -- 0
                                WHEN x"16" => ascii <= x"31"; -- 1
                                WHEN x"1E" => ascii <= x"32"; -- 2
                                WHEN x"26" => ascii <= x"33"; -- 3
                                WHEN x"25" => ascii <= x"34"; -- 4
                                WHEN x"2E" => ascii <= x"35"; -- 5
                                WHEN x"36" => ascii <= x"36"; -- 6
                                WHEN x"3D" => ascii <= x"37"; -- 7
                                WHEN x"3E" => ascii <= x"38"; -- 8
                                WHEN x"46" => ascii <= x"39"; -- 9
                                WHEN x"52" => ascii <= x"27"; -- '
                                WHEN x"41" => ascii <= x"2C"; -- ,
                                WHEN x"4E" => ascii <= x"2D"; -- -
                                WHEN x"49" => ascii <= x"2E"; -- .
                                WHEN x"4A" => ascii <= x"2F"; -- /
                                WHEN x"4C" => ascii <= x"3B"; -- ;
                                WHEN x"55" => ascii <= x"3D"; -- =
                                WHEN x"54" => ascii <= x"5B"; -- [
                                WHEN x"5D" => ascii <= x"5C"; -- \
                                WHEN x"5B" => ascii <= x"5D"; -- ]
                                WHEN x"0E" => ascii <= x"60"; -- `
                                WHEN OTHERS => NULL;
                            END CASE;
                        END IF;

                        IF num_lock = '1' AND e0_code = '0' THEN  -- If num lock is on, translate these keys to numerics unless it's an e0 prefixed code
                            CASE ps2_code is
                                WHEN x"70" => ascii <= x"30"; -- KP 0
                                WHEN x"69" => ascii <= x"31"; -- KP 1
                                WHEN x"72" => ascii <= x"32"; -- KP 2
                                WHEN x"7A" => ascii <= x"33"; -- KP 3
                                WHEN x"6B" => ascii <= x"34"; -- KP 4
                                WHEN x"73" => ascii <= x"35"; -- KP 5
                                WHEN x"74" => ascii <= x"36"; -- KP 6
                                WHEN x"6C" => ascii <= x"37"; -- KP 7
                                WHEN x"75" => ascii <= x"38"; -- KP 8
                                WHEN x"7D" => ascii <= x"39"; -- KP 9
                                WHEN x"71" => ascii <= x"2E"; -- KP .  ('.')
                                WHEN x"79" => ascii <= x"2B"; -- KP +
                                WHEN x"7B" => ascii <= x"2D"; -- KP -
                                WHEN x"7C" => ascii <= x"2A"; -- KP *
                                WHEN OTHERS => NULL;
                            END CASE;
                        ELSE                    -- If num lock is off, or it's on, but there was an e0 prefix, transate these keys to control stuff
                            CASE ps2_code is
                                WHEN x"70" =>
                                    ascii       <= x"1B";             -- INS <esc>[2~
                                    additionals <= x"5B327E";
                                WHEN x"69" =>
                                    ascii       <= x"1B";             -- END <esc>[4~
                                    additionals <= x"5B347E";
                                WHEN x"72" =>
                                    ascii       <= x"1B";             -- DOWN <esc>[B
                                    additionals <= x"5B4200";
                                WHEN x"7A" =>
                                    ascii       <= x"1B";             -- PG DN <esc>[6~
                                    additionals <= x"5B367E";
                                WHEN x"6B" =>
                                    ascii       <= x"1B";             -- LEFT <esc>[D
                                    additionals <= x"5B4400";
                                WHEN x"74" =>
                                    ascii       <= x"1B";             -- RIGHT <esc> [C
                                    additionals <= x"5B4300";
                                WHEN x"6C" =>
                                    ascii       <= x"1B";             -- HOME <esc> [1~
                                    additionals <= x"5B317E";
                                WHEN x"75" =>
                                    ascii       <= x"1B";             -- UP <esc>[A
                                    additionals <= x"5B4100";
                                WHEN x"7D" =>
                                    ascii       <= x"1B";             -- PG UP <esc>[5~
                                    additionals <= x"5B357E";
                                WHEN x"79" => ascii <= x"2B"; -- KP +
                                WHEN x"7B" => ascii <= x"2D"; -- KP -
                                WHEN x"7C" => ascii <= x"2A"; -- KP *
                                WHEN OTHERS => NULL;
                            END CASE;
                        END IF;
                        -- translate control codes (these do not depend on shift or caps lock)
                        IF (control_l = '1' OR control_r = '1') THEN
                            CASE ps2_code IS
                                WHEN x"1E" => ascii <= x"00"; -- ^@  NUL
                                WHEN x"1C" => ascii <= x"01"; -- ^A  SOH
                                WHEN x"32" => ascii <= x"02"; -- ^B  STX
                                WHEN x"21" => ascii <= x"03"; -- ^C  ETX
                                WHEN x"23" => ascii <= x"04"; -- ^D  EOT
                                WHEN x"24" => ascii <= x"05"; -- ^E  ENQ
                                WHEN x"2B" => ascii <= x"06"; -- ^F  ACK
                                WHEN x"34" => ascii <= x"07"; -- ^G  BEL
                                WHEN x"33" => ascii <= x"08"; -- ^H  BS
                                WHEN x"43" => ascii <= x"09"; -- ^I  HT
                                WHEN x"3B" => ascii <= x"0A"; -- ^J  LF
                                WHEN x"42" => ascii <= x"0B"; -- ^K  VT
                                WHEN x"4B" => ascii <= x"0C"; -- ^L  FF
                                WHEN x"3A" => ascii <= x"0D"; -- ^M  CR
                                WHEN x"31" => ascii <= x"0E"; -- ^N  SO
                                WHEN x"44" => ascii <= x"0F"; -- ^O  SI
                                WHEN x"4D" => ascii <= x"10"; -- ^P  DLE
                                WHEN x"15" => ascii <= x"11"; -- ^Q  DC1
                                WHEN x"2D" => ascii <= x"12"; -- ^R  DC2
                                WHEN x"1B" => ascii <= x"13"; -- ^S  DC3
                                WHEN x"2C" => ascii <= x"14"; -- ^T  DC4
                                WHEN x"3C" => ascii <= x"15"; -- ^U  NAK
                                WHEN x"2A" => ascii <= x"16"; -- ^V  SYN
                                WHEN x"1D" => ascii <= x"17"; -- ^W  ETB
                                WHEN x"22" => ascii <= x"18"; -- ^X  CAN
                                WHEN x"35" => ascii <= x"19"; -- ^Y  EM
                                WHEN x"1A" => ascii <= x"1A"; -- ^Z  SUB
                                WHEN x"54" => ascii <= x"1B"; -- ^[  ESC
                                WHEN x"5D" => ascii <= x"1C"; -- ^\  FS
                                WHEN x"5B" => ascii <= x"1D"; -- ^]  GS
                                WHEN x"36" => ascii <= x"1E"; -- ^^  RS
                                WHEN x"4E" => ascii <= x"1F"; -- ^_  US
                                WHEN x"4A" => ascii <= x"7F"; -- ^?  DEL
                                WHEN OTHERS => NULL;
                            END CASE;
                        ELSE -- if control keys are not pressed  
                            -- translate other characters that do not depend on shift, or caps lock
                            CASE ps2_code IS
                                WHEN x"29" => ascii <= x"20"; -- space
                                WHEN x"66" => ascii <= x"08"; -- backspace (BS control code)
                                WHEN x"0D" => ascii <= x"09"; -- tab (HT control code)
                                WHEN x"5A" => ascii <= x"0D"; -- enter (CR control code)
                                WHEN x"76" => ascii <= x"1B"; -- escape (ESC control code)
                                WHEN x"71" => 
                                    IF (e0_code = '1') THEN   -- ps2 code for delete is a multi-key code
                                        ascii <= x"7F";       -- delete
                                    END IF;
                                WHEN OTHERS => NULL;
                            END CASE;
                        END IF;

                        IF (break = '0') THEN       -- the code is a make
                            state <= addbuf;        -- proceed to add buffer state
                        ELSE                        -- code is a break
                            state <= ready;         -- return to ready state to await next PS2 code
                        END IF;

                        break <= '0';               -- reset break flag
                        e0_code <= '0';             -- reset multi-code command flag

                    -- buffer state: verify the code is valid and buffer the ASCII value
                    WHEN addbuf =>
                        IF (ascii(7) = '0') THEN                -- if it's '0', the keycode is valid, so add to the buffer
                            buffer_empty <= '0';                            -- buffer no longer empty
                            IF additionals = x"000000" THEN                 -- standard keypress (one ascii code)
                                key_buffer(buffer_head) <= ascii(6 DOWNTO 0);   -- store new ASCII code in buffer
                                buffer_head <= (buffer_head + 1) MOD 8;         -- advance head pointer
                                IF buffer_head = buffer_tail AND buffer_empty = '0' THEN        -- buffer is full
                                    buffer_tail <= (buffer_tail + 1) MOD 8;     -- so advance tail pointer to overwrite oldest value
                                END IF;
                            ELSE                                                    -- four ascii code keypress
                                key_buffer(buffer_head) <= ascii(6 DOWNTO 0);       -- put each of the four keypresses into the buffer
                                key_buffer(buffer_head + 1) <= additionals(22 DOWNTO 16);
                                key_buffer((buffer_head + 2) MOD 8) <= additionals(14 DOWNTO 8);
                                key_buffer((buffer_head + 3) MOD 8) <= additionals(6 DOWNTO 0);
                                buffer_tail <= buffer_head;                 -- purge buffer for these keystrokes, otherwise we might overwrite a portion of a previous set
                                buffer_head <= (buffer_head + 4) MOD 8;     -- advance buffer head by the 4 total ascii codes
                            END IF;
                        END IF;

                        IF ps2_code = x"58" OR ps2_code = x"77" THEN        -- if the code is the caps lock or num lock keys, send command to toggle appropriate lights on keyboard
                            state <= updatekb;
                        ELSE
                            state <= ready;                                 -- otherwise, return to ready state to await next PS2 code
                        END IF;

                    -- handle mode indicator change
                    WHEN updatekb =>
                        IF tx_busy_sig = '0' THEN                   -- wait until ok to transmit
                            tx_cmd_sig <= "111101101";              -- 0xED with msb as parity bit = set/reset mode indicators
                            tx_ena_sig <= '1';                      -- set transmit signal
                            state <= ready;                         -- wait for acknowledgement
                        ELSE
                            state <= updatekb;
                        END IF;

                    WHEN updatekb2 =>
                        IF tx_busy_sig = '0' THEN                   -- wait until ok to transmit
                            tx_cmd_sig <= NOT(caps_lock XOR num_lock) & "00000" & caps_lock & num_lock & "0";   -- set current caps lock (bit 2) and num_lock (bit 1) states with parity bit
                            tx_ena_sig <= '1';                      -- set transmit signal
                            state <= ready;                         -- wait for acknowledgement
                        ELSE
                            state <= updatekb2;
                        END IF;
                END CASE;
            END IF;
        END IF;
    END PROCESS;
END behavior;



