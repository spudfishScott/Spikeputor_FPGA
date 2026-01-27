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

    CONSTANT CLK_FREQ : Integer := 50_000_000;                              -- Clock frequency in Hertz - make this a generic parameter
    CONSTANT LCD_ADDRESS : std_logic_vector(6 downto 0) := "0100111";       -- LCD Display address 0x27

    -- i2c master signals
    signal i2c_ena : std_logic := '0';                                      -- signal to enable i2c transaction
    signal i2c_data_wr : std_logic_vector(7 downto 0) := (others => '0');   -- data to write to i2c provider
    signal i2c_busy : std_logic := '0';                                     -- indicates i2c transaction in progress
    
    signal data_wr : std_logic_vector(7 downto 0) := (others => '0');       -- byte to be sent
    signal data_cmd : std_logic := '0';                                     -- command/data bit 0 = command, 1 = data

    signal busy_prev : std_logic := '0';                                    -- busy edge detection
    signal cmd_latched : std_logic := '0';                                  -- en was asserted, and then busy transitioned to high

    signal delay_counter : integer range 0 to 50000000 := 0;                -- counter for delay timing

    signal cmd_index  : integer range 0 to 500 := 0;                        -- index for commands
    signal subcmd_idx : integer range 0 to 100 := 0;                        -- index for subcommands

    TYPE machine IS (STARTUP, DELAY, READY, SEND, SENDBYTE, IDLE);          -- needed states
    SIGNAL state        : machine := STARTUP;                               -- state machine initial state
    SIGNAL send_return1 : machine := STARTUP;                               -- state to return to after sending byte
    SIGNAL send_return2 : machine := STARTUP;                               -- state to return to after delay

    begin

    I2C: entity work.i2c_master port map (
        CLK       => CLOCK_50,                          -- system clock
        RESET_N   => Button(0),                         -- active low reset
        ENA       => i2c_ena,                           -- enable signal for starting transaction
        ADDR      => LCD_ADDRESS,                       -- 7-bit provider address 0x27 for LCD
        RW        => '0',                               -- read/write signal - already set to write
        DATA_WR   => i2c_data_wr,                       -- data to write to provider
        BUSY      => i2c_busy,                          -- indicates transaction in progress
        DATA_RD   => OPEN,                              -- never reading
        ACK_ERROR => OPEN,                              -- indicate acknowledge error on LEDG(9)

        SDA       => GPIO0_D(31),                       -- serial data signal of i2c bus
        SCL       => GPIO0_D(30)                        -- serial clock signal of i2c bus
    );

    LEDG(7 downto 0) <= std_logic_vector(to_unsigned(cmd_index, 8));   -- show cmd_index on the on-board LEDs
    LEDG(8) <= '0';                                                    -- unused LEDG(8)
    LEDG(9) <= '0';

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
                send_return1 <= STARTUP;
                send_return2 <= STARTUP;

                cmd_index <= 0;
                subcmd_idx <= 0;
                delay_counter <= 0;

                busy_prev <= '0';
                cmd_latched <= '0';
            else
                case state is
                    when STARTUP =>                 -- send initialization commands to LCD
                        cmd_index <= cmd_index + 1;         -- increment command index
                        send_return1 <= STARTUP;            -- set return state to come back here
                        send_return2 <= STARTUP;            -- set delay return to come back here
                        data_cmd <= '0';                    -- always send commands from here
                        case cmd_index is
                            when 0 =>               -- delay for startup 50 ms
                                delay_counter <= CLK_FREQ/20;
                                state <= DELAY;

                            when 1 =>               -- function set command
                                i2c_data_wr <= x"00";       -- turn off backlight, begin communication
                                state <= SEND;
                            
                            when 2 =>               -- delay for 1 s
                                delay_counter <= CLK_FREQ;
                                state <= DELAY;

                            -- try to set four bit mode by first insuring eight bit mode, then setting four bit mode
                            -- send first command - if it was in four bit mode, but only halfway transmitted, this could execute anything, so long pause afterwards
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

                            when 7 =>               -- delay after pulse 5 ms
                                delay_counter <= CLK_FREQ/200;
                                state <= DELAY;

                            -- send two more nybbles to assure the LCD controller is in 8 bit mode - normal pauses here
                            when 8 =>
                                data_wr <= x"33";           -- send byte 0x33 as a command
                                state <= SENDBYTE;

                            -- Now set to 4-bit mode via a single nybble command
                            when 9 =>
                                i2c_data_wr <= x"28";       -- function set: 4-bit
                                state <= SEND;

                            when 10 =>              -- "pulse enable"
                                i2c_data_wr <= x"2C";       -- pulse enable high
                                state <= SEND;

                            when 11 =>              -- delay after pulse 1 us
                                delay_counter <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 12 =>              -- "pulse enable" step 2
                                i2c_data_wr <= x"28";       -- pulse enable low
                                state <= SEND;

                            when 13 =>              -- delay after pulse 50 us
                                delay_counter <= CLK_FREQ/20_000;
                                state <= DELAY;

                            -- command: function set: 4-bit, 2 line, 5x8 dots : 0x28
                            when 14 =>
                                data_wr <= x"28";
                                state <= SENDBYTE;

                            -- command: display on, cursor off, blink off : 0x0C
                            when 15 =>
                                data_wr <= x"0C";
                                state <= SENDBYTE;
                            
                            -- command: clear screen : 0x01
                            when 16 =>
                                data_wr <= x"01";
                                state <= SENDBYTE;

                            -- long delay for clear screen! 2ms delay
                            when 17 =>
                                delay_counter <= CLK_FREQ/500;
                                state <= DELAY;

                            -- command: set default text direction left to right, entry shift decrement : 0x06
                            when 18 =>
                                data_wr <= x"06";
                                state <= SENDBYTE;

                            -- command: set cursor position to home position : 0x02
                            when 19 =>
                                data_wr <= x"02";
                                state <= SENDBYTE;

                            -- long delay for home cursor! 2ms delay
                            when 20 =>
                                delay_counter <= CLK_FREQ/500;
                                state <= DELAY;

                            when others =>
                                cmd_index <= 0;             -- reset command index
                                state <= READY;             -- go to ready state
                        end case;

                    when DELAY =>                   -- delay for delay_count counts
                        if delay_counter = 0 then
                            state <= send_return1;                  -- countdown over, return to caller
                        else
                            delay_counter <= delay_counter - 1;     -- decrement delay counter
                        end if;
                    
                    when READY =>                   -- ready for test commands/data
                        cmd_index <= cmd_index + 1;     -- increment command index
                        send_return1 <= READY;          -- return to ready state
                        send_return2 <= READY;
                        data_cmd <= '1';                -- all these are data, not command
                        state <= SENDBYTE;              -- always goign to the SENDBYTE state after this

                        case cmd_index is
                            when 0 =>
                                data_wr <= x"48";       -- "H"

                            when 1 =>
                                data_wr <= x"65";       -- "e"

                            when 2 =>
                                data_wr <= x"6C";       -- "l"

                            when 3 =>
                                data_wr <= x"6C";       -- "l"

                            when 4 =>
                                data_wr <= x"6F";       -- "o"

                            when 5 =>
                                data_wr <= x"2C";       -- ","

                            when 6 =>
                                data_wr <= x"20";       -- " "

                            when 7 =>
                                data_wr <= x"4C";       -- "L"

                            when 8 =>
                                data_wr <= x"61";       -- "a"

                            when 9 =>
                                data_wr <= x"75";       -- "u"

                            when 10 =>
                                data_wr <= x"72";       -- "r"

                            when 11 =>
                                data_wr <= x"65";       -- "e"

                            when 12 =>
                                data_wr <= x"6C";       -- "l"

                            when 13 =>
                                data_wr <= x"21";       -- "!"

                            when others =>
                                state <= IDLE;              -- wait when done
                        end case;

                    when IDLE =>        -- stay in idle state
                        state <= IDLE;

                    when SENDBYTE =>                -- send byte to I2C based on data_wr and data_cmd
                        subcmd_idx <= subcmd_idx + 1;       -- increment command index
                        send_return1 <= SENDBYTE;           -- set return state to come back here - send_return2 is state of the caller

                        case subcmd_idx is
                                -- send the byte as two nybbles in bits 7-4, bit 3 is always on (backlight), bit 2 is enable, bit 1 is always off (write), bit 0 is data_cmd
                            when 0 =>               -- send high nybble
                                i2c_data_wr <= data_wr(7 downto 4) & "100" & data_cmd;      -- write nybble with enable low
                                state <= SEND;
                            
                            when 1 =>
                                i2c_data_wr <= data_wr(7 downto 4) & "110" & data_cmd;      -- pulse enable high
                                state <= SEND;

                            when 2 =>               -- delay after pulse 1 us (1/1us = 1_000_000)
                                delay_counter <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 3 =>               -- "pulse enable" step 2
                                i2c_data_wr <= data_wr(7 downto 4) & "100" & data_cmd;      -- return to enable low
                                state <= SEND;

                            when 4 =>               -- delay after pulse 50 us (1/50us = 20_000)
                                delay_counter <= CLK_FREQ/20_000;
                                state <= DELAY;

                            when 5 =>               -- send low nybble
                                i2c_data_wr <= data_wr(3 downto 0) & "100" & data_cmd;      -- write nybble with enable low
                                state <= SEND;

                            when 6 =>
                                i2c_data_wr <= data_wr(3 downto 0) & "110" & data_cmd;      -- pulse enable high
                                state <= SEND;

                            when 7 =>               -- delay after pulse 1 us
                                delay_counter <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 8 =>               -- "pulse enable" step 2
                                i2c_data_wr <= data_wr(3 downto 0) & "100" & data_cmd;      -- return to enable low
                                state <= SEND;

                            when 9 =>               -- delay after pulse 50 us
                                delay_counter <= CLK_FREQ/20_000;
                                state <= DELAY;

                            when others =>          -- done
                                subcmd_idx <= 0;        -- reset subcmd_idx
                                state <= send_return2;  -- return to caller (using return2 because send_return1 was used here to return from SEND and DELAY)
                        end case;

                    when SEND =>                    -- send command/data to LCD
                        busy_prev <= i2c_busy;                              -- track pevious and current busy signal
                        if (busy_prev = '0' AND i2c_busy = '1') then        -- wasn't busy, now is
                            cmd_latched <= '1';
                        end if;

                        if cmd_latched = '0' AND i2c_ena = '0' then         -- ready to initiate the transaction and wait for busy?
                            i2c_ena <= '1';
                        elsif cmd_latched = '1' AND i2c_ena = '1' then      -- busy transitioned?
                            i2c_ena <= '0';                                 -- command has been latched, deassert enable to stop transaction, wait for busy to be cleared
                        elsif cmd_latched = '1' AND i2c_busy = '0' then     -- busy cleared?
                            cmd_latched <= '0';                             -- clear latch flag
                            state <= send_return1;                           -- return to appropriate state
                        end if;
                end case;
            end if;
        end if;
    end process;

end RTL;