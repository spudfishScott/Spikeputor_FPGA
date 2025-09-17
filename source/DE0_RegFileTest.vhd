library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_RegFileTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        -- CLOCK
        CLOCK_50 : in std_logic; -- 20 ns clock
        -- Push Button
        BUTTON   : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        -- GPIO
        GPIO0_D  : in std_logic_vector(31 downto 0);
        GPIO1_D  : in std_logic_vector(31 downto 14);

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
        -- LED
        LEDG     : out std_logic_vector(9 downto 0)
);
end DE0_RegFileTest;

architecture Structural of DE0_RegFileTest is
    -- wiring signals
    signal  cpu_clk : std_logic := '0';
    signal disp_out : std_logic_vector(15 downto 0) := (others => '0');
    signal    a_out : std_logic_vector(15 downto 0) := (others => '0');
    signal    b_out : std_logic_vector(15 downto 0) := (others => '0');

begin
    -- Defaults and display logic
    -- display is either the REGA or REGB (MUX2)
    disp_out <= a_out when BUTTON(2) = '1' else b_out;  -- if button 2 is pressed, display REG B, else display REG A

    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(1) <= '0';

    -- Structure
    -- CPU Clock Enable
    CLOCK_EN : entity work.CLK_ENABLE generic map(5, 1) port map ( -- 100 ns clock enable for "cpu"
        CLK_IN => CLOCK_50,
        CLK_EN => cpu_clk
    );

    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD   => disp_out,
        SEGS0  => HEX0_D,
        SEGS1  => HEX1_D,
        SEGS2  => HEX2_D,
        SEGS3  => HEX3_D
    );

    REGFILE: entity work.REG_FILE port map (
        RESET   => NOT BUTTON(0),
        IN0     => GPIO0_D(31 downto 16),
        IN1     => GPIO0_D(15 downto 0),
        IN2     => GPIO1_D(31 downto 16),
        WDSEL   => GPIO1_D(15 downto 14),
        CLK     => CLOCK_50,
        CLK_EN  => cpu_clk,
        OPA     => SW(9 downto 7),
        OPB     => SW(6 downto 4),
        OPC     => SW(3 downto 1),
        RBSEL   => SW(0),
        WERF    => NOT BUTTON(1),
        AOUT    => a_out,
        BOUT    => b_out,
        AZERO   => LEDG(0),
     SEL_INPUT  => open, -- these are LED-only outputs
        SEL_A   => LEDG(9 downto 2),
        SEL_B   => open,
        SEL_W   => open,
     REG_DATA   => open
    );

end Structural;