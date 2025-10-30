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
        GPIO0_D  : out std_logic_vector(1 downto 0);    -- DotStar Data and Clock
        -- LED
        LEDG     : out std_logic_vector(9 downto 0)      -- general purpose LEDs
    );

end DE0_DotStarTest;

architecture Structural of DE0_DotStarTest is

    signal INST       : in std_logic_vector(15 downto 0);  -- Instruction
    signal CONST      : in std_logic_vector(15 downto 0);  -- Constant
    signal MDATA      : in std_logic_vector(16 downto 0);  -- Memory Data, prepended with R/W signal (0 = read, 1 = write)
    signal PC         : in std_logic_vector(16 downto 0);  -- Program Counter, prepended with JT signal (1 = jump, 0 = continue)

begin
    LEDG(8 downto 0) <= (others => '0'); -- other LEDs off

    INST  <= X"DEAD";
    CONST <= X"F00D";
    MDATA <= "1" & X"BEEF";
    PC    <= "0" & X"CAFE";

    -- REGARRAY(1) <= GPIO0_D(15 downto 0) & "0000000000000000"; -- set up data in, shifted to msb, padded at lsb to equal max number of leds per set
    -- REGARRAY(2) <= GPIO0_D(31 downto 16) & "0000000000000000";
    -- REGARRAY(3) <= "1011010101101101" & "0000000000000000";
    -- REGARRAY(4) <= "0101010101011101" & "0000000000000000";
    -- REGARRAY(5) <= "1010001001100010" & "0000000000000000";
    -- REGARRAY(6) <= "0001000100010001" & "0000000000000000";
    -- REGARRAY(7) <= "1100110101100101" & "0000000000000000";
    -- REGARRAY(8) <= "1111101111101101" & "0000000000000000";
    -- REGARRAY(9) <= "1100111000111100" & "0000000000000000";
    -- REGARRAY(10) <= "0110110011101101" & "0000000000000000";
    -- REGARRAY(11) <= "0000000001000000" & "0000000000000000";
    -- REGARRAY(12) <= "1111110111110111" & "0000000000000000";
    -- REGARRAY(13) <= "0110110110110100" & "0000000000000000";
    -- REGARRAY(14) <= "1111110000001111" & "0000000000000000";
    -- REGARRAY(15) <= "0000111111110000" & "0000000000000000";
    -- REGARRAY(16) <= "1000000001000000" & "0000000000000000";
    -- REGARRAY(17) <= "0010010010000011" & "0000000000000000";
    -- REGARRAY(18) <= "1110111011111100" & "0000000000000000";
    -- REGARRAY(19) <= "0110110110111110" & "0000000000000000";
    -- REGARRAY(20) <= "1111111111111110" & "0000000000000000";

    -- COUNTARRAY <= (others => "01111"); -- set all sets to 16 LEDs each for now


    -- PS2_ASCII instance
   PS2 : entity work.dotstar_driver 
        generic map (
            XMIT_QUANTA => 1 -- this works well with 72 LEDs, maybe will need to slow it down for hundreds?
        )

        port map (
            CLK         => CLOCK_50,
            START       => NOT BUTTON(0),
           
            INST       => INST,     -- Instruction
            CONST      => CONST,    -- Constant
            MDATA      => MDATA,    -- Memory Data, prepended with R/W signal (0 = read, 1 = write)
            PC         => PC        -- Program Counter, prepended with JT signal (1 = jump, 0 = continue)

           DATA_OUT    => GPIO1_D(0),
           CLK_OUT     => GPIO1_D(1),
           BUSY        => LEDG(9)
        );

end Structural;