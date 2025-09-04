library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package Types is
    constant BIT_DEPTH : Integer := 16;
    type RARRAY is array(1 to 7) of std_logic_vector(BIT_DEPTH-1 downto 0);
    type BIGRARRAY is array(1 to 20) of std_logic_vector(BIT_DEPTH-1 downto 0);
end package Types;
