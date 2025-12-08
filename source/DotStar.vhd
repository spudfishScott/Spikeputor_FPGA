library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity dotstar_driver is
    generic (
        XMIT_QUANTA  : integer := 5                       -- number of system clock cycles per half SPI clock (50 Mhz clock = 5 MHz SPI)
    );
    port (
        -- INPUTS
        CLK          : in  std_logic;
        START        : in  std_logic;

        -- DotStar Signals in reverse display order
        SEGMENT      : in std_logic_vector(8 downto 0);   -- Segment register (to extend address bus), prepnded  with WSEG            0
        PC           : in std_logic_vector(16 downto 0);  -- Program Counter, prepended with JT signal (1 = jump, 0 = continue)       1
        MDATA        : in std_logic_vector(16 downto 0);  -- Memory Data, prepended with R/W signal (0 = read, 1 = write)             2
        CONST        : in std_logic_vector(15 downto 0);  -- Constant                                                                 3
        INST         : in std_logic_vector(15 downto 0);  -- Instruction                                                              4
        
        ALU_OUT      : in std_logic_vector(15 downto 0);  -- ALU Output                                                               5
        ALU_CMP      : in std_logic_vector(6 downto 0);   -- CMP function (2 bits), Z, V, N, Result, CMP Selected                     6 - needs only 6 LEDs
        ALU_SHIFT    : in std_logic_vector(18 downto 0);  -- SHIFT dir, SHIFT extend, Result (16 bits), SHIFT selected                7
        ALU_BOOL     : in std_logic_vector(20 downto 0);  -- BOOL truth table (4 bits), Result (16 bits), BOOL selected               8
        ALU_ARITH    : in std_logic_vector(17 downto 0);  -- ARITH subtract flag, Result (16 bits), ARITH selected                    9
        ALU_A        : in std_logic_vector(16 downto 0);  -- ASEL, ALU Input A (16 bits)                                              10
        ALU_B        : in std_logic_vector(16 downto 0);  -- BSEL, ALU Input B (16 bits)                                              11

        REGB_OUT     : in std_logic_vector(15 downto 0);  -- Register B output (16 bits)                                              12
        REGA_OUT     : in std_logic_vector(16 downto 0);  -- Zero Detect, Register A output (16 bits)                                 13
        REG1         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  14
        REG2         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  15
        REG3         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  16
        REG4         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  17
        REG5         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  18
        REG6         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  19
        REG7         : in std_logic_vector(18 downto 0);  -- A out, B out, Write, Register (16 bits)                                  20
        REGIN        : in std_logic_vector(17 downto 0);  -- WDSEL (2 bits), Regsiter Input (16 bits)                                 21

        GPO          : in std_logic_vector(15 downto 0);  -- General Purpose Output Register                                          22
        GPI          : in std_logic_vector(15 downto 0);  -- General Purpose Input                                                    23

         -- OUTPUTS
        DATA_OUT     : out std_logic;
        CLK_OUT      : out std_logic;
        BUSY         : out std_logic
    );
end dotstar_driver;

architecture rtl of dotstar_driver is

    constant NUM_SETS         : integer := 23;                                                      -- number of LED sets in the whole display array
    constant MAX_LEDS_PER_SET : integer := 22;                                                      -- max number of LEDs in each set (one more than actual so zero padding always works)
    constant TOTAL_LEDS       : integer := 405;                                                     -- total number of LEDs (added the list above)

    constant START_BITS       : integer := 32;                                                      -- number of bits in start frame (all '0's)
    constant BITS_PER_LED     : integer := 32;                                                      -- number of bits per LED (1 brightness + 3 colors x 8 bits each)
    constant END_BITS         : integer := ((TOTAL_LEDS + 15) / 16) * 8;                            -- number of bits in end frame (at least (n/2) bits, rounded up to next byte, all '1's)

    subtype COLOR_RANGE      is integer range BITS_PER_LED-9 downto 0;                              -- range for color data within LED register
    subtype BRIGHTNESS_RANGE is integer range BITS_PER_LED-1 downto BITS_PER_LED-8;                 -- range for brightness data within LED register

    signal start_bit_index    : integer range 0 to START_BITS := 0;                                 -- bit index within start frame
    signal end_bit_index      : integer range 0 to END_BITS := 0;                                   -- bit index within end frame

    signal set_index          : integer range 0 to NUM_SETS+1 := 1;                                 -- index of current LED set being transmitted
    signal set_reg            : std_logic_vector(MAX_LEDS_PER_SET-1 downto 0) := (others => '0');   -- stores the on/off values for the current LED set
    signal num_leds           : integer range 0 to MAX_LEDS_PER_SET;                                -- number of LEDs in current set

    signal led_index          : integer range 0 to MAX_LEDS_PER_SET+1 := 0;                         -- LED index within current LED set
    signal color_data_index   : integer range 0 to BITS_PER_LED := 0;                               -- index of current color data bit being transmitted
    signal led_reg            : std_logic_vector(BITS_PER_LED-1 downto 0) := (others => '0');       -- register for current LED color

    signal regin_sig          : std_logic_vector(16 downto 0);                                      -- use this for displaying reg in, but use wdsel portion of input for color selection
    signal cmp_sig            : std_logic_vector(5 downto 0);                                       -- use this for displaying cmp, but use cmpfn portion of input for color selection
    
    signal phase              : std_logic := '0';                                                   -- 0 = setup, 1 = toggle clock
    signal clk_div            : integer range 0 to XMIT_QUANTA-1 := 0;                              -- clock divider counter

    signal clk_out_int        : std_logic := '0';                                                   -- internal SPI clock signal
    signal data_out_int       : std_logic := '0';                                                   -- internal SPI data signal

    signal active             : std_logic := '0';                                                   -- indicates transmission in progress

    type state_type is (IDLE, SEND_START, LOAD_SET, LOAD_LED, SEND_DATA, SEND_END);
    signal state : state_type := IDLE;

begin

    CLK_OUT   <= clk_out_int;
    DATA_OUT  <= data_out_int;
    BUSY      <= active;

    regin_sig <= "1" & REGIN(15 downto 0);  -- the wdsel LED will always be lit with something, the rest is a normal 16 bit value
    cmp_sig   <= "1" & ALU_CMP(4 downto 0); -- the CMPFN LED will always be lit with something, the rest are normals signals

    process(CLK) is
    begin
        if rising_edge(CLK) then

            if active = '0' then            -- start a new transaction only if not already active
                if START = '1' then         -- if starting, initialize clock divider and set active
                    active  <= '1';
                    clk_div <= 0;
                    phase   <= '0';
                end if;
            end if;

            -- clock divider for SPI clock
            if clk_div < XMIT_QUANTA - 1 then
                clk_div <= clk_div + 1;
            else
                clk_div <= 0;   -- new SPI clock phase - reset clock divider counter
                phase   <= not phase; -- toggle SPI clock phase for next time through

                case state is   -- take action based on current state and SPI clock phase
                    when IDLE =>
                        clk_out_int  <= '0';
                        data_out_int <= '0';

                        if START = '1' then                   -- on start, send the start frame, otherwise, state remains idle
                            start_bit_index <= START_BITS-1;      -- set up to send bits of start frame (all '0')
                            state <= SEND_START;                  -- go to send_start state
                        else 
                            state <= IDLE;
                        end if;

                    when SEND_START =>
                        if phase = '0' then
                            -- Data setup phase - output data
                            data_out_int <= '0';  -- start frame is all zeros
                        else
                            -- Rising clock edge - toggle clock out
                            clk_out_int  <= not clk_out_int;

                            if clk_out_int = '1' then 
                                if start_bit_index /= 0 then        -- Falling spi clock edge: check bit index and send or change state if complete
                                    start_bit_index <= start_bit_index - 1; -- decrement bit index
                                    state <= SEND_START;                    -- remain in send_start state
                                else                                        -- finished sending start frame
                                    set_index <= 0;                         -- set up counter for LED data sets
                                    state <= LOAD_SET;                      -- go to load_LED state to get next LED to send
                                end if;
                            end if;
                        end if;

                    when LOAD_SET =>                                -- get next set of LEDs to send
                        if set_index /= NUM_SETS+1 then             -- if not finished all LED sets
                            -- for each set, use custom signal names and bit widths, zero pad msb's to MAX_LEDS_PER_SET
                            case set_index is
                                when 23 =>
                                    set_reg <= (MAX_LEDS_PER_SET-1 downto GPI'length => '0') & GPI;
                                    num_leds <= GPI'length;
                                when 22 =>
                                    set_reg <= (MAX_LEDS_PER_SET-1 downto GPO'length => '0') & GPO;
                                    num_leds <= GPO'length;
                                when 21 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto regin_sig'length => '0') & regin_sig;
                                    num_leds <= regin_sig'length;
                                when 20 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG7'length => '0') & REG7;
                                    num_leds <= REG7'length;
                                when 19 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG6'length => '0') & REG6;
                                    num_leds <= REG6'length;
                                when 18 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG5'length => '0') & REG5;
                                    num_leds <= REG5'length;
                                when 17 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG4'length => '0') & REG4;
                                    num_leds <= REG4'length;
                                when 16 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG3'length => '0') & REG3;
                                    num_leds <= REG3'length;
                                when 15 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG2'length => '0') & REG2;
                                    num_leds <= REG2'length;
                                when 14 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REG1'length => '0') & REG1;
                                    num_leds <= REG1'length;
                                when 13 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REGA_OUT'length => '0') & REGA_OUT;
                                    num_leds <= REGA_OUT'length;
                                when 12 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto REGB_OUT'length => '0') & REGB_OUT;
                                    num_leds <= REGB_OUT'length;
                                when 11 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_B'length => '0') & ALU_B;
                                    num_leds <= ALU_B'length;
                                when 10 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_A'length => '0') & ALU_A;
                                    num_leds <= ALU_A'length; 
                                when 9 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_ARITH'length => '0') & ALU_ARITH;
                                    num_leds <= ALU_ARITH'length;
                                when 8 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_BOOL'length => '0') & ALU_BOOL;
                                    num_leds <= ALU_BOOL'length;
                                when 7 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_SHIFT'length => '0') & ALU_SHIFT;
                                    num_leds <= ALU_SHIFT'length;
                                when 6 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto cmp_sig'length => '0') & cmp_sig;
                                    num_leds <= cmp_sig'length;
                                when 5 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto ALU_OUT'length => '0') & ALU_OUT;
                                    num_leds <= ALU_OUT'length;
                                when 4 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto INST'length => '0') & INST;
                                    num_leds <= INST'length;
                                when 3 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto CONST'length => '0') & CONST;
                                    num_leds <= CONST'length;
                                when 2 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto MDATA'length => '0') & MDATA;
                                    num_leds <= MDATA'length;
                                when 1 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto PC'length => '0') & PC;
                                    num_leds <= PC'length;
                                when 0 =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto SEGMENT'length => '0') & SEGMENT;
                                    num_leds <= SEGMENT'length;
                                when others =>
                                    set_reg  <= (MAX_LEDS_PER_SET-1 downto INST'length => '0') & INST;
                                    num_leds <= INST'length;
                            end case;

                            led_index <= 0;                         -- start with first LED in the set
                            state <= LOAD_LED;                      -- go to load_led state
                        else                                        -- finished all LED sets, go to end frame
                            end_bit_index <= END_BITS;              -- set up counter to send end frame (all '1's)
                            state <= SEND_END;                      -- go to send_end state
                        end if;

                    when LOAD_LED =>                                -- get next LED in the current set
                        if led_index /= Integer(num_leds) then      -- now we handle variable number of LEDs per set, so check against num_leds
                            
                            -- Set default LED state - brightness at max, color off
                            led_reg(BRIGHTNESS_RANGE) <= X"FF";     -- set brightness byte to full brightness
                            led_reg(COLOR_RANGE)     <= X"000000";  -- set default color to LED off

                            -- Override color for specific cases
                            case set_index is
                                when 23 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        led_reg(COLOR_RANGE) <= x"000400";          -- color GPI green
                                    end if;
                                when 22 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        led_reg(COLOR_RANGE) <= x"000004";          -- color GPO red
                                    end if;
                                when 21 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        if led_index = 16 then
                                            case REGIN(17 downto 16) is             -- select color for the wdsel LED from the two wdsel bits
                                                when "00" =>
                                                    led_reg(COLOR_RANGE) <= x"040004";  -- magenta LED for WDSEL = 0 (PC_INC)
                                                when "01" =>
                                                    led_reg(COLOR_RANGE) <= x"040400";  -- cyan LED for WDSEL = 1 (ALU)
                                                when others =>
                                                    led_reg(COLOR_RANGE) <= x"000404";  -- yellow LED for WDSEL = 2 (MEM)
                                            end case;
                                        else
                                            led_reg(COLOR_RANGE) <= x"000400";      -- green LEDs for register input value
                                        end if;
                                    end if;
                                when 14 to 20 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        case led_index is
                                            when 18 =>
                                                led_reg(COLOR_RANGE) <= x"000204";  -- orange LED for output to Channel A
                                            when 17 =>
                                                led_reg(COLOR_RANGE) <= x"000400";  -- green LED for output to Channel B
                                            when 16 =>
                                                led_reg(COLOR_RANGE) <= x"040000";  -- blue LED for register write
                                            when others =>
                                                led_reg(COLOR_RANGE) <= x"000004";  -- red LEDs for register data
                                        end case;
                                    end if;
                                when 13 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        if led_index = 16 then
                                            led_reg(COLOR_RANGE) <= x"040000";      -- blue LED for Zero detect
                                        else
                                            led_reg(COLOR_RANGE) <= x"000204";      -- Register A Output is all orange LEDs
                                        end if;
                                    end if;
                                when 12 =>
                                    if set_reg(led_index) = '1' then
                                        led_reg(COLOR_RANGE) <= x"000400";          -- Register B Output is all green LEDs
                                    end if;
                                when 10 | 11 =>
                                    if led_index = 16 then      -- asel or bsel flag
                                        if set_reg(led_index) = '1' then
                                            led_reg(COLOR_RANGE) <= x"000404";      -- yellow LED for ASEL = 1 (CONST or PC+2 input)
                                        else
                                            led_reg(COLOR_RANGE) <= x"040004";      -- magenta LED for ASEL = 0 (Register Channel input)
                                        end if;
                                    else
                                        if set_reg(led_index) = '1' then
                                            led_reg(COLOR_RANGE) <= x"000400";      -- green LEDs for ALU inputs
                                        end if;
                                    end if;
                                when 9 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        case led_index is
                                            when 0 =>
                                                led_reg(COLOR_RANGE) <= x"040404";  -- white LED for ARITH selected
                                            when 17 =>
                                                led_reg(COLOR_RANGE) <= x"040004";  -- magenta for subtraction
                                            when others =>
                                                led_reg(COLOR_RANGE) <= x"040000";  -- red LEDs for ARITH result
                                        end case;
                                    elsif led_index = 17 then   -- addition (flag = '0')
                                        led_reg(COLOR_RANGE) <= x"040000";          -- cyan for addition
                                    end if;
                                when 8 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        case led_index is
                                            when 0 =>
                                                led_reg(COLOR_RANGE) <= x"040404";  -- white LED for BOOL selected
                                            when 17 to 20 =>
                                                led_reg(COLOR_RANGE) <= x"040000";  -- blue LED for BOOL truth table
                                            when others =>
                                                led_reg(COLOR_RANGE) <= x"000004";  -- red LEDs for BOOL result
                                        end case;
                                    end if;
                                when 7 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        case led_index is
                                            when 0 =>
                                                led_reg(COLOR_RANGE) <= x"040404";  -- white LED for SHIFT selected
                                            when 17 =>
                                                led_reg(COLOR_RANGE) <= x"040000";  -- blue LED for SHIFT extend
                                            when 18 =>
                                                led_reg(COLOR_RANGE) <= x"040000";  -- blue LED for shift right 
                                            when others =>
                                                led_reg(COLOR_RANGE) <= x"000004";  -- red LEDs for SHIFT result
                                        end case;
                                    elsif led_index = 18 then   -- shift left (flag = '0')
                                        led_reg(COLOR_RANGE) <= x"000400";          -- green LED for shift left
                                    end if;
                                when 6 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        case led_index is
                                            when 0 =>
                                                led_reg(COLOR_RANGE) <= x"040404";  -- white LED for CMP selected
                                            when 1 =>
                                                led_reg(COLOR_RANGE) <= x"000004";  -- red LED for CMP result
                                            when 2 =>
                                                led_reg(COLOR_RANGE) <= x"040004";  -- magenta LED for N
                                            when 3 =>
                                                led_reg(COLOR_RANGE) <= x"000404";  -- yellow LED for V
                                            when 4 =>
                                                led_reg(COLOR_RANGE) <= x"040400";  -- cyan LED for Z
                                            when others =>
                                                case ALU_CMP(6 downto 5) is -- select color for the cmpfn LED from the two cmpfn bits
                                                    when "00" =>
                                                        led_reg(COLOR_RANGE) <= x"040404";  -- white LED for CMPEQ  (0b00)
                                                    when "01" =>
                                                        led_reg(COLOR_RANGE) <= x"000004";  -- red LED for CMPUL    (0b01)
                                                    when "10" =>
                                                        led_reg(COLOR_RANGE) <= x"000400";  -- green LED for CMPLT  (0b10)
                                                    when others =>
                                                        led_reg(COLOR_RANGE) <= x"040000";  -- blue LED for CMPLE   (0b11)
                                            end case;
                                        end case;
                                    end if;
                                when 3 | 4 | 5 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        led_reg(COLOR_RANGE) <= x"000004";          -- INST and CONST, and ALU Output are all red LEDs
                                    end if;
                                when 2 => -- TODO: Maybe blank these unless reading or writing is happening
                                    if led_index = 16 then      -- msb of MDATA is read/write signal
                                        if set_reg(led_index) = '1' then
                                            led_reg(COLOR_RANGE) <= x"040004";      -- magenta LED for write (1)
                                        else
                                            led_reg(COLOR_RANGE) <= x"000400";      -- green LED for read (0)
                                        end if;
                                    elsif set_reg(led_index) = '1' then
                                        led_reg(COLOR_RANGE) <= x"000004";          -- MDATA is all red LEDs
                                    end if;
                                when 1 =>
                                    if set_reg(led_index) = '1' then                -- only color the LEDs if they are on
                                        if led_index = 16 then  -- msb of PC is JT signal
                                            led_reg(COLOR_RANGE) <= x"040000";      -- blue LED for JT
                                        else
                                            led_reg(COLOR_RANGE) <= x"000004";      -- PC is all red LEDs
                                        end if;
                                    elsif led_index = 16 then
                                            led_reg(COLOR_RANGE) <= x"000400";      -- green LED for PC_INC
                                    end if;
                                when 0 =>
                                    if led_index = 8 then
                                        if set_reg(led_index) = '1' then
                                            led_reg(COLOR_RANGE) <= x"000204";      -- orange LED for WSEG = 1
                                        end if;
                                    elsif led_index = 7 AND set_reg(7 downto 0) /= "00000000" then     -- msb is ROM/RAM signal, but only if segment register isn't 0
                                        if set_reg(led_index) = '1' then
                                            led_reg(COLOR_RANGE) <= x"040000";      -- blue LED for ROM
                                        else
                                            led_reg(COLOR_RANGE) <= x"000400";      -- green LED for RAM
                                        end if;
                                    elsif set_reg(led_index) = '1' then
                                        led_reg(COLOR_RANGE) <= x"000004";      -- SEGMENT is all red LEDs
                                    end if;
                                when others =>
                                    null;  -- keep default NO_COLOR
                            end case;

                            color_data_index <= BITS_PER_LED-1;     -- set up to send bits of current LED color data
                            clk_div <= 0;                           -- reset clock divider signals
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
                                    state   <= IDLE;                          -- go to idle state
                                    active  <= '0';                          -- clear active flag
                                    clk_div <= 0;                           -- reset clock divider and phase
                                    phase   <= '0';
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