library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package Types is
    -- for register memory arrays
    constant BIT_DEPTH : Integer := 16;
    type RARRAY is array(1 to 7) of std_logic_vector(BIT_DEPTH-1 downto 0);

    -- for DotStar LED driver
    constant MAX_LEDS_PER_SET : Integer := 32;  -- max number of LEDs in a set
    constant MAX_LEDS_BITS :  Integer := Integer(ceil(log2(real(MAX_LEDS_PER_SET))));      -- number of bits to describe max number of LEDs in a set (2^5 = 32)
    type LEDARRAY is array(1 to 20) of std_logic_vector(MAX_LEDS_PER_SET-1 downto 0);
    type LEDCOUNTARRAY is array(1 to 20) of std_logic_vector(MAX_LEDS_BITS-1 downto 0);     -- number of LEDs in each set
end package Types;
