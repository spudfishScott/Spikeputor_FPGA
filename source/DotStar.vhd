library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dotstar_driver is
    generic (
        NUM_LEDS     : integer := 10;
        XMIT_QUANTA  : integer := 5  -- number of system clock cycles per half SPI clock (50 Mhz clock = 5 MHz SPI)
    );
    port (
        CLK        : in  std_logic;
        RESET      : in  std_logic;
        START      : in  std_logic;
        COLOR      : in  std_logic_vector(3 * NUM_LEDS - 1 downto 0); -- RGB 1-bit each, first LED is LSB

        DATA_OUT   : out std_logic;
        CLK_OUT    : out std_logic;
        BUSY       : out std_logic
    );
end dotstar_driver;

architecture rtl of dotstar_driver is

    constant START_BITS     : integer := 32;
    constant BITS_PER_LED   : integer := 32;
    constant END_BITS       : integer := ((NUM_LEDS + 15) / 16) * 8;
    constant TOTAL_BITS     : integer := START_BITS + NUM_LEDS * BITS_PER_LED + END_BITS;

    signal shift_reg  : std_logic_vector(TOTAL_BITS - 1 downto 0) := (others => '0');
    signal bit_index  : integer range 0 to TOTAL_BITS := 0;
    signal phase      : std_logic := '0';  -- 0 = setup, 1 = toggle clock
    signal clk_div    : integer range 0 to XMIT_QUANTA - 1 := 0;
    signal clk_out_int: std_logic := '0';
    signal data_out_int : std_logic := '0';
    signal active     : std_logic := '0';

    type state_type is (IDLE, LOAD, SEND);
    signal state : state_type := IDLE;

begin

    CLK_OUT  <= clk_out_int;
    DATA_OUT <= data_out_int;
    BUSY     <= active;

    process(CLK, RESET)
        variable temp_shift : std_logic_vector(TOTAL_BITS - 1 downto 0);
        variable color_bits : std_logic_vector(2 downto 0);
        variable r, g, b : std_logic_vector(7 downto 0);
        variable led_frame : std_logic_vector(31 downto 0);

    begin
        if RESET = '1' then
            state <= IDLE;
            bit_index <= 0;
            clk_out_int <= '0';
            data_out_int <= '0';
            clk_div <= 0;
            phase <= '0';
            active <= '0';
        elsif rising_edge(CLK) then
            case state is
                when IDLE =>
                    clk_out_int <= '0';
                    data_out_int <= '0';
                    active <= '0';
                    if START = '1' then
                        -- Load the shift register with full frame
                        temp_shift := (others => '0');

                        -- Start Frame is placed at MSB side moving downward, then LED frames
                        for i in 0 to NUM_LEDS - 1 loop
                            -- Insert LED frames
                            color_bits := COLOR(3*i + 2 downto 3*i);
                            -- one byte for each color, brightness is fixed at 0xFF
                            r := (others => color_bits(2));
                            g := (others => color_bits(1));
                            b := (others => color_bits(0));

                            led_frame := "11111111" & b & g & r; -- Brightness + B/G/R from msb to lsb
                            -- start the data bits after the start frame (START_BITS), head down for each LED
                            temp_shift(TOTAL_BITS - BITS_PER_LED*i - START_BITS - 1 
                                        downto TOTAL_BITS - BITS_PER_LED*(i+1) - START_BITS) := led_frame;
                        end loop;

                        -- Insert END frame padding on lsb side of stream: 0xFF per byte
                        for j in 0 to END_BITS/8 - 1 loop   -- number of bytes for end frame
                            temp_shift(END_BITS - 8*j - 1 downto END_BITS - 8*(j+1)) := x"FF";
                        end loop;

                        shift_reg <= temp_shift;
                        bit_index <= 0;
                        clk_div <= 0;
                        phase <= '0';
                        state <= SEND;
                        active <= '1';
                    end if;

                when SEND =>
                    -- Clock divider
                    if clk_div < XMIT_QUANTA - 1 then
                        clk_div <= clk_div + 1;
                    else
                        clk_div <= 0;
                        phase <= not phase;

                        if phase = '0' then
                            -- Data setup phase - output msb of shift register
                            data_out_int <= shift_reg(TOTAL_BITS - 1);
                        else
                            -- Rising clock edge
                            clk_out_int <= not clk_out_int;

                            if clk_out_int = '1' then
                                -- Falling clock edge: shift out from msb
                                if bit_index < TOTAL_BITS - 1 then
                                    shift_reg <= shift_reg(TOTAL_BITS - 2 downto 0) & '0';
                                    bit_index <= bit_index + 1;
                                else
                                    state <= IDLE;
                                    active <= '0';
                                    clk_out_int <= '0';
                                    data_out_int <= '0';
                                end if;
                            end if;
                        end if;
                    end if;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end rtl;
