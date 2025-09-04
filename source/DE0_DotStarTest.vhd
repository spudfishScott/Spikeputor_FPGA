library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_DotStarTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        -- CLOCK
        CLOCK_50 : in std_logic; -- 20 ns clock
        -- GPIO
        GPIO0_D  : in std_logic_vector(31 downto 0);    -- data inputs, 3 bits each (RGB) for 10 LEDs
        -- Push Button
        BUTTON   : in std_logic_vector(2 downto 0);     -- BUTTON(0) = send data

        --OUTPUTS
        -- GPIO
        GPIO1_D  : out std_logic_vector(7 downto 6);    -- DotStar Data and Clock
        -- LED
        LEDG     : out std_logic_vector(9 downto 0)      -- general purpose LEDs
    );

end DE0_DotStarTest;

architecture Structural of DE0_DotStarTest is

    signal REGARRAY : BIGRARRAY;

begin
    LEDG(8 downto 0) <= (others => '0'); -- other LEDs off

    REGARRAY(1) <= GPIO_D(15 downto 0); -- set up data in
    REGARRAY(2) <= GPIO_D(31 downto 16);
    REGARRAY(3) <= GPIO_D(15 downto 0);
    REGARRAY(4) <= GPIO_D(31 downto 16);
    REGARRAY(5) <= GPIO_D(15 downto 0);
    REGARRAY(6) <= GPIO_D(31 downto 16);
    REGARRAY(7) <= GPIO_D(15 downto 0);
    REGARRAY(8) <= GPIO_D(31 downto 16);
    REGARRAY(7) <= GPIO_D(15 downto 0);
    REGARRAY(8) <= GPIO_D(31 downto 16);
    REGARRAY(9) <= GPIO_D(15 downto 0);
    REGARRAY(10) <= GPIO_D(31 downto 16);
    REGARRAY(11) <= GPIO_D(15 downto 0);
    REGARRAY(12) <= GPIO_D(31 downto 16);
    REGARRAY(13) <= GPIO_D(15 downto 0);
    REGARRAY(14) <= GPIO_D(31 downto 16);
    REGARRAY(15) <= GPIO_D(15 downto 0);
    REGARRAY(16) <= GPIO_D(31 downto 16);
    REGARRAY(17) <= GPIO_D(15 downto 0);
    REGARRAY(18) <= GPIO_D(31 downto 16);
    REGARRAY(19) <= GPIO_D(15 downto 0);
    REGARRAY(20) <= GPIO_D(31 downto 16);


    -- PS2_ASCII instance
   PS2 : entity work.dotstar_driver 
        generic map (
            XMIT_QUANTA => 1 -- this works well with 30 LEDs, maybe will need to slow it down for hundreds?
        )

        port map (
           CLK         => CLOCK_50,
           START       => NOT BUTTON(0),
           DISPLAY     => REGARRAY,
           COLOR       => x"00FF00", -- green
           DATA_OUT    => GPIO1_D(6),
           CLK_OUT     => GPIO1_D(7),
           BUSY        => LEDG(9)
        );

end Structural;