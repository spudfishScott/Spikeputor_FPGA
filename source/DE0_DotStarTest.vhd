library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_DotStarTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        -- CLOCK
        CLOCK_50 : in std_logic; -- 20 ns clock
        -- GPIO
        GPIO0_D  : in std_logic_vector(29 downto 0);    -- data inputs, 3 bits each (RGB) for 10 LEDs
        -- Push Button
        BUTTON   : in std_logic_vector(2 downto 0);     -- BUTTON(0) = send data, BUTTON(2) = reset

        --OUTPUTS
        -- GPIO
        GPIO1_D  : out std_logic_vector(7 downto 6);    -- DotStar Data and Clock
        -- LED
        LEDG     : out std_logic_vector(9 downto 0)      -- general purpose LEDs
    );

end DE0_DotStarTest;

architecture Structural of DE0_DotStarTest is


begin
    LEDG(8 downto 0) <= (others => '0'); -- other LEDs off

    -- PS2_ASCII instance
   PS2 : entity work.DotStar generic map (NUM_LEDs => 10) port map (
        CLK        => CLOCK_50,
        RESET      => BUTTON(2),
        START      => BUTTON(0),
        COLOR      => GPIO_D(29 downto 0),
        DATA_OUT   => GPIO1_D(6),
        CLK_OUT    => GPIO1_D(7),
        BUSY       => LEDG(9)
    );

end Structural;