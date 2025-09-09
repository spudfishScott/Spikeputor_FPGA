library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity dotstar_driver is
    generic (
        XMIT_QUANTA  : integer := 5  -- number of system clock cycles per half SPI clock (50 Mhz clock = 5 MHz SPI)
    );
    port (
        -- INPUTS
        CLK        : in  std_logic;
        START      : in  std_logic;
        DISPLAY    : in LEDARRAY;       -- array of 20 register values (up to 32 bits each)
        LED_COUNTS : in LEDCOUNTARRAY;  -- array of 20 values indicating number of LEDs in each set (5 bits each)

         -- OUTPUTS
        DATA_OUT   : out std_logic;
        CLK_OUT    : out std_logic;
        BUSY       : out std_logic
    );
end dotstar_driver;

architecture rtl of dotstar_driver is

    constant NUM_SETS       : integer := 20;                            -- number of LED sets in the display array (or input arrays)
    constant MAX_LEDS_PER_SET : integer := 32;                          -- max number of LEDs in each set
    constant MAX_LED_SET_BITS : integer := 5;                           -- number of bits to describe max number of LEDs in a set (2^5 = 32)
    constant NUM_LEDS       : integer := NUM_SETS * MAX_LEDS_PER_SET;   -- number of LEDs in the display data

    constant START_BITS     : integer := 32;                            -- number of bits in start frame (all '0's)
    constant BITS_PER_LED   : integer := 32;                            -- number of bits per LED (1 brightness + 3 colors x 8 bits each)
    constant END_BITS       : integer := ((NUM_LEDS + 15) / 16) * 8;    -- number of bits in end frame (at least (n/2) bits, rounded up to next byte, all '1's)
    
    constant NO_COLOR       : std_logic_vector(23 downto 0) := (others => '0'); -- color data for LED off

    signal int_start : std_logic := '0';                                                    -- internal start signal, latched when not busy
    signal start_bit_index : integer range 0 to START_BITS := 0;                            -- bit index within start frame
    signal end_bit_index   : integer range 0 to END_BITS := 0;                              -- bit index within end frame

    signal set_index  : integer range 1 to NUM_SETS+1 := 1;                                 -- index of current LED set being transmitted
    signal set_reg    : std_logic_vector(MAX_LEDS_PER_SET-1 downto 0) := (others => '0');   -- stores the on/off values for the current LED set
    signal num_leds   : std_logic_vector(MAX_LED_SET_BITS-1 downto 0) := (others => '0');   -- number of LEDs per set

    signal led_index  : integer range 0 to MAX_LEDS_PER_SET+1 := 0;                         -- LED index within current LED set
    signal color_data_index : integer range 0 to BITS_PER_LED := 0;                         -- index of current color data bit being transmitted
    signal led_reg : std_logic_vector(BITS_PER_LED - 1 downto 0) := (others => '0');        -- register for current LED color
    
    signal phase      : std_logic := '0';                                                   -- 0 = setup, 1 = toggle clock
    signal clk_div    : integer range 0 to XMIT_QUANTA - 1 := 0;                            -- clock divider counter

    signal clk_out_int: std_logic := '0';                                                   -- internal SPI clock signal
    signal data_out_int : std_logic := '0';                                                 -- internal SPI data signal

    signal active     : std_logic := '0';                                                   -- indicates transmission in progress

    type state_type is (IDLE, SEND_START, LOAD_SET, LOAD_LED, SEND_DATA, SEND_END);
    signal state : state_type := IDLE;

begin

    CLK_OUT  <= clk_out_int;
    DATA_OUT <= data_out_int;
    BUSY     <= active;

    process(CLK) is
    begin
        if rising_edge(CLK) then

            if active = '0' then            -- start a new transaction only if not already active
                int_start <= START;         -- latch in start signal
                if START = '1' then         -- if starting, initialize clockdivider and set active
                    active <= '1';
                    clk_div <= 0;
                    phase <= '0';
                end if;
            end if;

            -- clock divider for SPI clock
            if clk_div < XMIT_QUANTA - 1 then
                clk_div <= clk_div + 1;
            else
                clk_div <= 0;   -- new SPI clock phase - reset clock divider counter
                phase <= not phase; -- toggle SPI clock phase for next time through

                case state is   -- take action based on current state and SPI clock phase
                    when IDLE =>
                        clk_out_int <= '0';
                        data_out_int <= '0';

                        if int_start = '1' then                     -- on start, send the start frame, otherwise, state remains idle
                            start_bit_index <= START_BITS-1;      -- set up to send bits of start frame (all '0')
                            state <= SEND_START;                -- go to send_start state
                        else 
                            state <= IDLE;
                        end if;

                    when SEND_START =>
                        if phase = '0' then
                            -- Data setup phase - output data
                            data_out_int <= '0';  -- start frame is all zeros
                        else
                            -- Rising clock edge - toggle clock out
                            clk_out_int <= not clk_out_int;

                            if clk_out_int = '1' then 
                                if start_bit_index /= 0 then        -- Falling spi clock edge: check bit index and send or change state if complete
                                    start_bit_index <= start_bit_index - 1; -- decrement bit index
                                    state <= SEND_START;                    -- remain in send_start state
                                else                                        -- finished sending start frame
                                    set_index <= 1;                         -- set up counter for LED data sets (will likely end up 0 but right now DISPLAY starts at 1)
                                    state <= LOAD_SET;                      -- go to load_LED state to get next LED to send
                                end if;
                            end if;
                        end if;

                    when LOAD_SET =>                                -- get next set of LEDs to send
                        if set_index /= NUM_SETS+1 then             -- if not finished all LED sets (change to NUM_SETS for zero-indexed set)
                            set_reg <= DISPLAY(set_index);          -- load the LED on/off data for the current set
                            num_leds <= LED_COUNTS(set_index);      -- load the number of LEDs in this set
                            led_index <= 0;                         -- start with first LED in the set
                            state <= LOAD_LED;                      -- go to load_led state
                        else                                        -- finished all LED sets, go to end frame
                            end_bit_index <= END_BITS;              -- set up counter to send end frame (all '1's)
                            state <= SEND_END;                      -- go to send_end state
                        end if;

                    when LOAD_LED =>                                -- get next LED in the current set
                        if led_index /= Integer(num_leds) then      -- now we handle variable number of LEDs per set, so check against num_leds
                            if set_reg(led_index) = '1' then        -- if this LED is on, load its color data based on set_index and led_index
                                                                    -- this will eventually be a big nested case . . . when statement based on set_index and led_index
                                if set_index mod 2 = 1 then
                                    led_reg <= "11111111" & x"001133";      -- color BGR data for current LED, prepended with brightness byte (0xff)
                                else
                                    led_reg <= "11111111" & x"440000";      -- color BGR data for current LED, prepended with brightness byte (0xff)
                                end if;
                            else
                                led_reg <= "11111111" & NO_COLOR;   -- if this LED is off, load all zeros, prepended with brightness byte (0xff)
                            end if;
                            color_data_index <= BITS_PER_LED-1;     -- set up to send bits of current LED color data
                            clk_div <= 0;                           -- reset clock divider
                            phase <= '0';
                            state <= SEND_DATA;                     -- go to send_data state
                        else                                        -- finished all LEDs in this set, go to next set
                            set_index <= set_index + 1;             -- increment to next LED set
                            state <= LOAD_SET;                      -- go to load_set state
                        end if;

                    when SEND_DATA =>
                        if phase = '0' then                          -- Data setup phase - output data
                            data_out_int <= led_reg(BITS_PER_LED - 1);      -- output msb of led color data shift register
                        else
                            clk_out_int <= not clk_out_int;                 -- Rising clock divider edge - toggle SPI clock

                            if clk_out_int = '1' then                       -- Falling spi clock edge: check bit index and send or change state if complete
                                if color_data_index /= 0 then                               -- not finished sending all bits of this LED
                                    led_reg <= led_reg(BITS_PER_LED - 2 downto 0) & '0';    -- shift left the led color data register
                                    color_data_index <= color_data_index - 1;               -- decrement color data bit counter
                                    state <= SEND_DATA;
                                else                                                        -- finished sending all bits of this LED
                                    led_index <= led_index + 1;                             -- increment to next LED in set
                                    state <= LOAD_LED;                                      -- go to load_led state
                                end if;
                            end if;
                        end if;

                    when SEND_END =>
                        if phase = '0' then                         -- Data setup phase - output data
                            data_out_int <= '1';                        -- end frame is all ones
                        else
                            clk_out_int <= not clk_out_int;             -- Rising clock divider edge - toggle clock

                            if clk_out_int = '1' then                   -- Falling spi clock edge: check bit index and send or change state if complete
                                if end_bit_index /= 0 then                  -- not finished sending all bits of end frame
                                    end_bit_index <= end_bit_index - 1;     -- decrement bit index
                                    state <= SEND_END;
                                else                                        -- finished sending end frame
                                    state <= IDLE;                          -- go to idle state
                                    active <= '0';                          -- clear active flag
                                    int_start <= '0';                       -- clear latched start signal
                                    clk_div <= 0;                           -- reset clock divider and phase
                                    phase <= '0';
                                end if;
                            end if;
                        end if;

                    when others =>                                          -- should never happen
                        state <= IDLE;
                end case;

            end if;
        end if;
    end process;

end rtl;