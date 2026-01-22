library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_LCD4X20 is
    port (
        -- Clock Input
        CLOCK_50   : in std_logic;
        -- Push Button
        BUTTON     : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW         : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D     : out std_logic_vector(6 downto 0);
        HEX0_DP    : out std_logic;
        HEX1_D     : out std_logic_vector(6 downto 0);
        HEX1_DP    : out std_logic;
        HEX2_D     : out std_logic_vector(6 downto 0);
        HEX2_DP    : out std_logic;
        HEX3_D     : out std_logic_vector(6 downto 0);
        HEX3_DP    : out std_logic;
        -- LED
        LEDG       : out std_logic_vector(9 downto 0);
        -- LCD I2C Interface
        GPIO0_D : inout std_logic_vector(31 downto 30)
    );
end DE0_LCD4X20;

architecture RTL of DE0_LCD4X20 is

    -- i2c master signals
    signal i2c_ena : std_logic := '0';                                      -- signal to enable i2c transaction
    signal i2c_data_wr : std_logic_vector(7 downto 0) := (others => '0');   -- data to write to i2c provider
    signal i2c_busy : std_logic := '0';                                     -- indicates i2c transaction in progress
    signal i2c_error : std_logic := '0';                                    -- indicates i2c acknowledge error

	 signal busy_prev : std_logic := '0';												 -- busy edge detection
	 signal cmd_latched : std_logic := '0';											 -- en was asserted, and then busy transitioned to high
    signal delay_counter : integer range 0 to 50000000 := 0;                -- counter for delay timing
    signal cmd_index : integer range 0 to 500 := 0;                         -- index for commands to send to LCD on startup
    signal loop_counter : integer range 0 to 100 := 0;                      -- general purpose loop counter
    signal initialized : std_logic := '0';                                  -- indicates LCD initialization complete

    TYPE machine IS (STARTUP, DELAY, READY, SEND, IDLE);                          -- needed states
    SIGNAL state : machine := STARTUP;                                      -- state machine initial state
    SIGNAL return_state : machine := STARTUP;                               -- state to return to after delay
begin

    I2C: entity work.i2c_master port map (
        CLK       => CLOCK_50,                          -- system clock
        RESET_N   => Button(0),                         -- active low reset
        ENA       => i2c_ena,                           -- enable signal for starting transaction
        ADDR      => "0100111",                         -- 7-bit provider address 0x27 for LCD
        RW        => '0',                               -- read/write signal - already set to write
        DATA_WR   => i2c_data_wr,                       -- data to write to provider
        BUSY      => i2c_busy,                          -- indicates transaction in progress
        DATA_RD   => OPEN,
        ACK_ERROR => i2c_error,                           -- indicate acknowledge error on LEDG(9)

        SDA       => GPIO0_D(31),                       -- serial data signal of i2c bus
        SCL       => GPIO0_D(30)                        -- serial clock signal of i2c bus
    );

    LEDG(7 downto 0) <= std_logic_vector(to_unsigned(cmd_index, 8));   -- show cmd_index on the on-board LEDs
    LEDG(8) <= '0';                                                    -- unused LEDG(8)
    LEDG(9) <= i2c_error;                                              -- show i2c acknowledge error on LEDG(9)

    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => x"00" & i2c_data_wr,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if (Button(0) = '0') then                 -- synchronous reset
                state <= STARTUP;
                cmd_index <= 0;
                delay_counter <= 0;
                initialized <= '0';
                loop_counter <= 0;
                return_state <= STARTUP;
					 busy_prev <= '0';
					 cmd_latched <= '0';
            else
                if i2c_error = '1' then
                    state <= IDLE;                     -- on i2c error go to idle state
                else
                    case state is
                        when STARTUP =>                 -- send initialization commands to LCD
                            cmd_index <= cmd_index + 1;         -- increment command index
                            return_state <= STARTUP;            -- set return state to come back here
                            case cmd_index is
                                when 0 =>               -- delay for startup 50 ms
                                    delay_counter <= 2500000;   -- 50ms delay at 50MHz
                                    state <= DELAY;

                                when 1 =>               -- function set command
                                    i2c_data_wr <= x"00";       -- turn off backlight, begin communication
                                    state <= SEND;
                                
                                when 2 =>               -- delay for 1000 ms
                                    delay_counter <= 50000000;  -- 1000ms delay at 50MHz
                                    state <= DELAY;

                                -- typical sequence to write 4 bits is: data in high nybble, command flags in low nybble. Write three bytes:
                                    -- 1. low nybble is just BACKLIGHT ON
                                    -- 2. low nybble is BACKLIGHT ON + ENABLE HIGH
                                    -- 3. low nybble is just BACKLIGHT ON + ENABLE LOW

                                -- try to set four bit mode by first insuring eight bit mode, then setting four bit mode
                                when 3 =>               -- "expander write" is OR backlight on
                                    i2c_data_wr <= x"38";       -- function set: 8-bit
                                    state <= SEND;

                                when 4 =>               -- "pulse enable"
                                    i2c_data_wr <= x"3C";       -- pulse enable high
                                    state <= SEND;

                                when 5 =>               -- delay after pulse 1 us
                                    delay_counter <= 50;        -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 6 =>               -- "pulse enable" step 2
                                    i2c_data_wr <= x"38";       -- pulse enable low
                                    state <= SEND;

                                when 7 =>               -- delay after pulse 50 us
                                    delay_counter <= 2500;      -- 50us delay at 50MHz
                                    state <= DELAY;
                                
                                when 8 =>               -- delay for 5 ms
                                    delay_counter <= 250000;
                                    state <= DELAY;
                                    loop_counter <= loop_counter + 1;
                                    if loop_counter < 2 then
                                        cmd_index <= 3;         -- repeat for a total of three times - LCD is now in 8 bit mode!
                                    end if;

                                when 9 =>               -- Now set to 4-bit mode
                                    i2c_data_wr <= x"28";       -- function set: 4-bit
                                    state <= SEND;

                                when 10 =>              -- "pulse enable"
                                    i2c_data_wr <= x"2C";       -- pulse enable high
                                    state <= SEND;

                                when 11 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 12 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"28";       -- pulse enable low
                                    state <= SEND;

                                when 13 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                -- to send a byte in 4 bit mode, send two, 4-bit nybbles as above. Each nybble has bit 0 set for data and cleared for commands
                                -- command: function set: 4-bit, 2 line, 5x8 dots : 0x28 = two nybbles: 0x2 and 0x8
                                when 14 =>        -- high nybble (0x2)
                                    i2c_data_wr <= x"28";
                                    state <= SEND;
                                
                                when 15 =>              -- "pulse enable"
                                    i2c_data_wr <= x"2C";       -- pulse enable high
                                    state <= SEND;

                                when 16 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 17 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"28";       -- pulse enable low
                                    state <= SEND;

                                when 18 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 19 =>        -- low nybble (0x8)
                                    i2c_data_wr <= x"88";
                                    state <= SEND;

                                when 20 =>              -- "pulse enable"
                                    i2c_data_wr <= x"8C";       -- pulse enable high
                                    state <= SEND;

                                when 21 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 22 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"88";       -- pulse enable low
                                    state <= SEND;

                                when 23 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                -- command: display on, cursor off, blink off : 0x0C  = two nybbles: 0x0 and 0x8
                                when 24 =>        -- high nybble (0x0)
                                    i2c_data_wr <= x"08";
                                    state <= SEND;
                                
                                when 25 =>              -- "pulse enable"
                                    i2c_data_wr <= x"0C";       -- pulse enable high
                                    state <= SEND;

                                when 26 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 27 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"08";       -- pulse enable low
                                    state <= SEND;

                                when 28 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 29 =>        -- low nybble (0xC)
                                    i2c_data_wr <= x"C8";
                                    state <= SEND;

                                when 30 =>              -- "pulse enable"
                                    i2c_data_wr <= x"CC";       -- pulse enable high
                                    state <= SEND;

                                when 31 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 32 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"C8";       -- pulse enable low
                                    state <= SEND;

                                when 33 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;
                                
                                -- command: clear screen : 0x01 = two nybbles: 0x0 and 0x1
                                when 34 =>        -- high nybble (0x0)
                                    i2c_data_wr <= x"08";
                                    state <= SEND;
                                
                                when 35 =>              -- "pulse enable"
                                    i2c_data_wr <= x"0C";       -- pulse enable high
                                    state <= SEND;

                                when 36 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 37 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"08";       -- pulse enable low
                                    state <= SEND;

                                when 38 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 39 =>        -- low nybble (0x1)
                                    i2c_data_wr <= x"18";
                                    state <= SEND;

                                when 40 =>              -- "pulse enable"
                                    i2c_data_wr <= x"1C";       -- pulse enable high
                                    state <= SEND;

                                when 41 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 42 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"18";       -- pulse enable low
                                    state <= SEND;

                                when 43 =>              -- delay after pulse 2 ms
                                    delay_counter <= 100000;     -- long delay! 2ms delay at 50MHz
                                    state <= DELAY;

                                -- command: set default text direction left to right, entry shift decrement : 0x06 = two nybbles: 0x0 and 0x6
                                when 44 =>        -- high nybble (0x0)
                                    i2c_data_wr <= x"08";
                                    state <= SEND;
                                
                                when 45 =>              -- "pulse enable"
                                    i2c_data_wr <= x"0C";       -- pulse enable high
                                    state <= SEND;

                                when 46 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 47 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"08";       -- pulse enable low
                                    state <= SEND;

                                when 48 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 49 =>        -- low nybble (0x7)
                                    i2c_data_wr <= x"68";
                                    state <= SEND;

                                when 50 =>              -- "pulse enable"
                                    i2c_data_wr <= x"6C";       -- pulse enable high
                                    state <= SEND;

                                when 51 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 52 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"68";       -- pulse enable low
                                    state <= SEND;

                                when 53 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                -- command: set cursor position to home position : 0x02 = two nybbles: 0x0 and 0x2
                                when 54 =>        -- high nybble (0x0)
                                    i2c_data_wr <= x"08";
                                    state <= SEND;
                                
                                when 55 =>              -- "pulse enable"
                                    i2c_data_wr <= x"0C";       -- pulse enable high
                                    state <= SEND;

                                when 56 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 57 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"08";       -- pulse enable low
                                    state <= SEND;

                                when 58 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 59 =>        -- low nybble (0x2)
                                    i2c_data_wr <= x"28";
                                    state <= SEND;

                                when 60 =>              -- "pulse enable"
                                    i2c_data_wr <= x"2C";       -- pulse enable high
                                    state <= SEND;

                                when 61 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 62 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"28";       -- pulse enable low
                                    state <= SEND;

                                when 63 =>              -- delay after pulse 50 us
                                    delay_counter <= 100000;     -- long delay! 2ms delay at 50MHz
                                    state <= DELAY;

                                when others =>
                                    cmd_index <= 200;           -- reset command index
                                    state <= READY;             -- go to ready state
                                    return_state <= READY;
                                    initialized <= '1';         -- indicate initialization complete
                            end case;

                        when DELAY =>                   -- delay for delay_count counts
                            if delay_counter = 0 then
                                state <= return_state;
                            else
                                delay_counter <= delay_counter - 1;
                            end if;
                        
                        when READY =>                   -- ready for test commands/data
                            cmd_index <= cmd_index + 1;     -- increment command index
                            return_state <= READY;          -- stay in ready state
                            case cmd_index is
                                -- send the letter "H" - ascii 0x48 = two nybbles: 0x4 and 0x8, bit 0 of lower nybble set for DATA
                                when 200 =>       -- high nybble (0x4)
                                    i2c_data_wr <= x"49";
                                    state <= SEND;
                                
                                when 201 =>              -- "pulse enable"
                                    i2c_data_wr <= x"4D";       -- pulse enable high
                                    state <= SEND;

                                when 202 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 203 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"49";       -- pulse enable low
                                    state <= SEND;

                                when 204 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 205 =>        -- low nybble (0x8)
                                    i2c_data_wr <= x"89";
                                    state <= SEND;

                                when 206 =>              -- "pulse enable"
                                    i2c_data_wr <= x"8D";       -- pulse enable high
                                    state <= SEND;

                                when 207 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 208 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"89";       -- pulse enable low
                                    state <= SEND;
												
										  when 209 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;
												
                                -- send letter "I" - ascii 0x49 = two nybbles: 0x4 and 0x9, bit 0 of lower nybble set for DATA
                                when 210 =>       -- high nybble (0x4)
                                    i2c_data_wr <= x"49";
                                    state <= SEND;
                                
                                when 211 =>              -- "pulse enable"
                                    i2c_data_wr <= x"4D";       -- pulse enable high
                                    state <= SEND;

                                when 212 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 213 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"49";       -- pulse enable low
                                    state <= SEND;

                                when 214 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 215 =>        -- low nybble (0x9)
                                    i2c_data_wr <= x"99";
                                    state <= SEND;

                                when 216 =>              -- "pulse enable"
                                    i2c_data_wr <= x"9D";       -- pulse enable high
                                    state <= SEND;

                                when 217 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 218 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"99";       -- pulse enable low
                                    state <= SEND;
												
										  when 219 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;
												
                                -- send the character "!" - ascii 0x21 = two nybbles: 0x2 and 0x1, bit 0 of lower nybble set for DATA
                                when 220 =>       -- high nybble (0x2)
                                    i2c_data_wr <= x"29";
                                    state <= SEND;
                                
                                when 221 =>              -- "pulse enable"
                                    i2c_data_wr <= x"2D";       -- pulse enable high
                                    state <= SEND;

                                when 222 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 223 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"29";       -- pulse enable low
                                    state <= SEND;

                                when 224 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when 225 =>        -- low nybble (0x1)
                                    i2c_data_wr <= x"19";
                                    state <= SEND;

                                when 226 =>              -- "pulse enable"
                                    i2c_data_wr <= x"1D";       -- pulse enable high
                                    state <= SEND;

                                when 227 =>              -- delay after pulse 1 us
                                    delay_counter <= 50;         -- 1us delay at 50MHz
                                    state <= DELAY;

                                when 228 =>              -- "pulse enable" step 2
                                    i2c_data_wr <= x"19";       -- pulse enable low
                                    state <= SEND;
												
										  when 229 =>              -- delay after pulse 50 us
                                    delay_counter <= 2500;       -- 50us delay at 50MHz
                                    state <= DELAY;

                                when others =>
                                    state <= IDLE;              -- wait
                            end case;

                        when IDLE =>
                            -- stay in idle state
                            state <= IDLE;
                        
                        when SEND =>                    -- send command/data to LCD
                            busy_prev <= i2c_busy; -- track pevious and current busy signal
									 if (busy_prev = '0' AND i2c_busy = '1') then -- wasn't busy, now is
										cmd_latched <= '1';
									 end if;
									 
									 if cmd_latched = '0' AND i2c_ena = '0' then
										i2c_ena <= '1';	-- initiate the transaction, wait for busy
									 elsif cmd_latched = '1' AND i2c_ena = '1' then -- command has been latched
										i2c_ena <= '0';   -- deassert enable to stop transaction, wait for busy to be cleared
									 elsif cmd_latched = '1' AND i2c_busy = '0' then
									   cmd_latched <= '0';	-- clear latch flag
										state <= return_state; -- return to appropriate state
									 end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

end RTL;