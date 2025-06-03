-- This module contains MUXes of various sizes and functionality

-- This is an eight input MUX with a three bit selector.
-- The bit width can be selected through the generic
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MUX8 is
    generic (width: positive := 8); -- width of input signal

    port (
        IN7 : in std_logic_vector(width-1 downto 0); -- input 7
        IN6 : in std_logic_vector(width-1 downto 0); -- input 6
        IN5 : in std_logic_vector(width-1 downto 0); -- input 5
        IN4 : in std_logic_vector(width-1 downto 0); -- input 4
        IN3 : in std_logic_vector(width-1 downto 0); -- input 3
        IN2 : in std_logic_vector(width-1 downto 0); -- input 2
        IN1 : in std_logic_vector(width-1 downto 0); -- input 1
        IN0 : in std_logic_vector(width-1 downto 0); -- input 0
        SEL : in std_logic_vector(2 downto 0);   -- selection
        MUXOUT : out std_logic_vector(width-1 downto 0) -- selected output
    );
end MUX8;

architecture Behavior of MUX8 is
begin
    with (SEL) select
        MUXOUT <=
            IN7 when "111",
            IN6 when "110",
            IN5 when "101",
            IN4 when "100",
            IN3 when "011",
            IN2 when "010",
            IN1 when "001",
            IN0 when "000",
            IN0 when others;
end Behavior;

-------------------------------------------------------------------------------------------------------------
-- This is a three input MUX with a two bit selector.
-- The high bit of the selector selects input 2 regardless of the low bit value
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MUX3 is
    generic (width: positive); -- width of in/out signals

    port (
        IN2 : in std_logic_vector(width-1 downto 0); -- input 2
        IN1 : in std_logic_vector(width-1 downto 0); -- input 1
        IN0 : in std_logic_vector(width-1 downto 0); -- input 0
        SEL : in std_logic_vector(1 downto 0); -- selection
        MUXOUT : out std_logic_vector(width-1 downto 0) -- output
    );
end MUX3;

architecture Behavior of MUX3 is
begin
    with (SEL) select
        MUXOUT <=
            IN2 when "10" | "11", -- if high bit is '1', low bit does not matter
            IN1 when "01",
            IN0 when "00",
            IN0 when others;
end Behavior;
