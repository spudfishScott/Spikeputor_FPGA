library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dotstar_driver_tb is
end entity;

architecture sim of dotstar_driver_tb is
    ------------------------------------------------------------------------
    -- Testbench configuration
    ------------------------------------------------------------------------
    constant TB_NUM_LEDS    : integer := 17;  -- use 10 to match your defaults
    constant TB_XMIT_QUANTA : integer := 5;   -- halves per SPI edge, matches DUT

    constant SYS_CLK_PERIOD : time := 20 ns;  -- 50 MHz

    -- Mirror DUT constants (must match DUT math)
    constant START_BITS   : integer := 32;
    constant BITS_PER_LED : integer := 32;
    constant END_BITS     : integer := ((TB_NUM_LEDS + 15) / 16) * 8;
    constant TOTAL_BITS   : integer := START_BITS + TB_NUM_LEDS * BITS_PER_LED + END_BITS;

    ------------------------------------------------------------------------
    -- DUT I/O
    ------------------------------------------------------------------------
    signal CLK        : std_logic := '0';
    signal RESET      : std_logic := '0';
    signal START      : std_logic := '0';
    signal COLOR      : std_logic_vector(3 * TB_NUM_LEDS - 1 downto 0) := (others => '0');

    signal DATA_OUT   : std_logic;
    signal CLK_OUT    : std_logic;
    signal BUSY       : std_logic;

    ------------------------------------------------------------------------
    -- Capture / golden compare
    ------------------------------------------------------------------------
    signal captured_bits : std_logic_vector(TOTAL_BITS-1 downto 0) := (others => '0');
    signal captured_cnt  : integer range 0 to TOTAL_BITS := 0;
    signal done_capture  : std_logic := '0';

begin
    ------------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------------
    dut: entity work.dotstar_driver
        generic map (
            NUM_LEDS    => TB_NUM_LEDS,
            XMIT_QUANTA => TB_XMIT_QUANTA
        )
        port map (
            CLK      => CLK,
            RESET    => RESET,
            START    => START,
            COLOR    => COLOR,
            DATA_OUT => DATA_OUT,
            CLK_OUT  => CLK_OUT,
            BUSY     => BUSY
        );

    ------------------------------------------------------------------------
    -- 50 MHz system clock
    ------------------------------------------------------------------------
    CLK <= not CLK after SYS_CLK_PERIOD/2;

    ------------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------------
    stim: process
        -- Build a fun 1-bit-per-color pattern across LEDs:
        -- LED i uses bits: COLOR(3*i+2 downto 3*i) = {R,G,B}
        -- Here we cycle: 100, 010, 001, 111, 000, 101, 011, 110, 001, 100 ...
        variable pat : std_logic_vector(COLOR'range);
    begin
        -- Reset
        RESET <= '1';
        wait for 200 ns;
        RESET <= '0';
        wait for 200 ns;

        -- Build COLOR pattern
        for i in 0 to TB_NUM_LEDS-1 loop
            case i mod 8 is
                when 0 => pat(3*i+2 downto 3*i) := "100"; -- R
                when 1 => pat(3*i+2 downto 3*i) := "010"; -- G
                when 2 => pat(3*i+2 downto 3*i) := "001"; -- B
                when 3 => pat(3*i+2 downto 3*i) := "111"; -- white
                when 4 => pat(3*i+2 downto 3*i) := "000"; -- off
                when 5 => pat(3*i+2 downto 3*i) := "101"; -- magenta
                when 6 => pat(3*i+2 downto 3*i) := "011"; -- cyan
                when others => pat(3*i+2 downto 3*i) := "110"; -- yellow
            end case;
        end loop;
        COLOR <= pat;

        -- Kick a transfer
        START <= '1';
        wait for SYS_CLK_PERIOD;
        START <= '0';

        -- Wait for completion and comparison
        wait until done_capture = '1';
        report "Test completed." severity note;
        wait;
    end process;

    ------------------------------------------------------------------------
    -- Capture DATA_OUT at rising edge of CLK_OUT while BUSY
    -- The DUT sets DATA before the rising edge and shifts on falling edge.
    ------------------------------------------------------------------------
    capture: process
        variable idx : integer := TOTAL_BITS-1;
    begin
        -- Wait for BUSY rising edge
        wait until rising_edge(BUSY);
        captured_cnt <= 0;
        captured_bits <= (others => '0');
        idx := TOTAL_BITS-1;

        -- Collect TOTAL_BITS samples on rising edges of CLK_OUT
        while idx >= 0 loop
            wait until rising_edge(CLK_OUT);
            captured_bits(idx) <= DATA_OUT;
            captured_cnt <= captured_cnt + 1;
            idx := idx - 1;
        end loop;

        -- Wait for BUSY to drop
        wait until falling_edge(BUSY);

        done_capture <= '1';
        wait;
    end process;

    ------------------------------------------------------------------------
    -- Golden model built exactly like the DUT (same slice math),
    -- then compare captured_bits against expected_bits.
    ------------------------------------------------------------------------
    checker: process(done_capture)
        variable temp_shift : std_logic_vector(TOTAL_BITS-1 downto 0);
        variable color_bits : std_logic_vector(2 downto 0);
        variable r, g, b    : std_logic_vector(7 downto 0);
        variable led_frame  : std_logic_vector(31 downto 0);
        variable expected   : std_logic_vector(TOTAL_BITS-1 downto 0);
    begin
        if done_capture = '1' then
            -- START frame: 32 zeros already defaulted below
            temp_shift := (others => '0');

            -- LED frames (your RTL: 0xFF then B, G, R — brightness fixed at all 1s)
            for i in 0 to TB_NUM_LEDS - 1 loop
                color_bits := COLOR(3*i + 2 downto 3*i);
                r := (others => color_bits(2));
                g := (others => color_bits(1));
                b := (others => color_bits(0));
                led_frame := "11111111" & b & g & r;  -- FF + B G R

                -- Place after START frame moving downward (exactly like DUT)
                temp_shift(TOTAL_BITS - 1 - BITS_PER_LED*i - START_BITS 
                                        downto TOTAL_BITS - BITS_PER_LED*(i+1) - START_BITS) := led_frame;
            end loop;

            -- END frame padding: 0xFF per byte (use the exact indices from your RTL)
            for j in 0 to END_BITS/8 - 1 loop
                -- NOTE: we reproduce your indexing as written
                temp_shift(END_BITS - 8*j - 1 downto END_BITS - 8*(j+1)) := x"FF";
            end loop;

            expected := temp_shift;

            -- Checks
            assert captured_cnt = TOTAL_BITS
                report "Captured bit count mismatch: got " &
                       integer'image(captured_cnt) & " expected " &
                       integer'image(TOTAL_BITS)
                severity error;

            assert captured_bits = expected
                report "Bitstream mismatch between DUT and expected golden."
                severity error;

            report "Bitstream OK. TOTAL_BITS=" & integer'image(TOTAL_BITS) severity note;
        end if;
    end process;

end architecture;
