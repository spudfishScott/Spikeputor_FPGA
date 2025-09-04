library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

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

    REGARRAY(1) <= GPIO0_D(15 downto 0); -- set up data in
    REGARRAY(2) <= GPIO0_D(31 downto 16);
    REGARRAY(3) <= "1011010101101101";
    REGARRAY(4) <= "0101010101011101";
    REGARRAY(5) <= "1010001001100010";
    REGARRAY(6) <= "0001000100010001";
    REGARRAY(7) <= "1100110101100101";
    REGARRAY(8) <= "1111101111101101";
    REGARRAY(9) <= "1100111000111100";
    REGARRAY(10) <= "0110110011101101";
    REGARRAY(11) <= "0000000001000000";
    REGARRAY(12) <= "1111110111110111";
    REGARRAY(13) <= "0110110110110100";
    REGARRAY(14) <= "1111110000001111";
    REGARRAY(15) <= "0000111111110000";
    REGARRAY(16) <= "1000000001000000";
    REGARRAY(17) <= "0010010010000011";
    REGARRAY(18) <= "1110111011111100";
    REGARRAY(19) <= "0110110110111110";
    REGARRAY(20) <= "1111111111111110";


    -- PS2_ASCII instance
   PS2 : entity work.dotstar_driver 
        generic map (
            XMIT_QUANTA => 1 -- this works well with 30 LEDs, maybe will need to slow it down for hundreds?
        )

        port map (
           CLK         => CLOCK_50,
           START       => NOT BUTTON(0),
           DISPLAY     => REGARRAY,
           DATA_OUT    => GPIO1_D(6),
           CLK_OUT     => GPIO1_D(7),
           BUSY        => LEDG(9)
        );

end Structural;