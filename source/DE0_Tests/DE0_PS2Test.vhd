library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_PS2Test is -- the interface to the DE0 board
    port (
        -- INPUTS
        -- CLOCK
        CLOCK_50 : in std_logic; -- 20 ns clock
        -- PS/2 Keyboard
        PS2_KBCLK : inout std_logic; -- PS/2 clock signal
        PS2_KBDAT : inout std_logic; -- PS/2 data signal

        --OUTPUTS
        -- 7-SEG Display
        HEX0_D   : out std_logic_vector(6 downto 0);
        HEX0_DP  : out std_logic;
        HEX1_D   : out std_logic_vector(6 downto 0);
        HEX1_DP  : out std_logic;
        HEX2_D   : out std_logic_vector(6 downto 0);
        HEX2_DP  : out std_logic;
        HEX3_D   : out std_logic_vector(6 downto 0);
        HEX3_DP  : out std_logic;

        LEDG     : out std_logic_vector(9 downto 0);

        BUTTON   : in std_logic_vector(1 downto 0)
    );

end DE0_PS2Test;

architecture Structural of DE0_PS2Test is
    signal disp_out : std_logic_vector(15 downto 0) := (others => '0');
    signal key_req_sig : std_logic := '0';

begin
    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(9 downto 1) <= (others => '0');

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => disp_out,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    -- Generate one cycle pulse signal for key request on button press
    PULSER : entity work.PULSE_GEN
    generic map (
        PULSE_WIDTH => 1
    )

    port map (
        CLK_IN      => CLOCK_50,
        START_PULSE => NOT(Button(1)),  -- button 1 is key request
        PULSE_OUT   => key_req_sig
    );

    -- PS2_ASCII instance
    PS2 : entity work.PS2_ASCII port map (
        clk        => CLOCK_50,
        n_rst      => Button(0),            -- button 0 is reset active low
        ps2_clk    => PS2_KBCLK,
        ps2_data   => PS2_KBDAT,
        key_req    => key_req_sig,          -- key request signal
        ascii_new  => LEDG(0),
        ascii_code => disp_out(6 downto 0)  -- output ASCII code to display
    );



end Structural;
