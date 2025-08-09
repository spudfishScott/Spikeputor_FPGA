library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- 7 Segment LED Display Decoder
entity WORDTO7SEGS is
	port (
		 WORD : in std_logic_vector(15 downto 0);
		SEGS0, SEGS1, SEGS2, SEGS3 : out std_logic_vector(6 downto 0)
	);
end WORDTO7SEGS;

architecture Behavior of WORDTO7SEGS is

	function hexToLEDs(n : std_logic_vector(3 downto 0)) return std_logic_vector is
		begin
			case (n) is
				when "0000" => return "1000000";
				when "0001" => return "1111001";
				when "0010" => return "0100100";
				when "0011" => return "0110000";
				when "0100" => return "0011001";
				when "0101" => return "0010010";
				when "0110" => return "0000010";
				when "0111" => return "1111000";
				when "1000" => return "0000000";
				when "1001" => return "0010000";
				when "1010" => return "0001000";
				when "1011" => return "0000011";
				when "1100" => return "1000110";
				when "1101" => return "0100001";
				when "1110" => return "0000110";
				when "1111" => return "0001110";
				when others => return "1111111";
			end case;
		end function;
		
begin
    SEGS3 <= hexToLEDs(WORD(15 downto 12));
    SEGS2 <= hexToLEDs(WORD(11 downto 8));
    SEGS1 <= hexToLEDs(WORD(7 downto 4));
    SEGS0 <= hexToLEDs(WORD(3 downto 0));
end Behavior;
