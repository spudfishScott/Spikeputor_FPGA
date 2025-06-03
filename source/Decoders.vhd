-- This module has decoders of various sizes and functionality

-- This is a 3 bit to 8 bit output one-hot decoder
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DECODE3_8 is
    port (
        DECIN : in std_logic_vector(2 downto 0); -- decoder input
        OUTS : out std_logic_vector(7 downto 0) -- decoded output signal
    );
end DECODE3_8;

architecture Behavior of DECODE3_8 is
begin
    with (DECIN) select -- decode the 3 bit signal to a signal bit of an 8 bit output
        OUTS <= 
            "10000000" when "111",
            "01000000" when "110",
            "00100000" when "101",
            "00010000" when "100",
            "00001000" when "011",
            "00000100" when "010",
            "00000010" when "001",
            "00000001" when "000",
            "00000000" when others;
end Behavior;