library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This module synthesizes a clock of desired frequency from an input clock of defined frequency and duty cycle
entity CLOCK is
	generic ( -- Desired Frequency in Hz
		FREQUENCY : Integer := 1000;
		 SRC_FREQ : Integer := 50000000;
		 DUTY_CYC : Integer := 50;
	);
	
	port(
		 CLK_IN : in std_logic;
		CLK_OUT : out std_logic
	);
end CLOCK;

architecture Behavior of CLOCK is
	signal COUNTER : Integer := 0;
	
begin
	CLK_DIV : process(CLK_IN)
	begin
		if rising_edge(CLK_IN) then
			if (COUNTER >= SRC_FREQ/FREQUENCY) then
				COUNTER <= 0;
			else
				COUNTER <= COUNTER + 1;
			end if;
		end if;
	end process CLK_DIV;
	
	CLK_OUT <= '1' when (COUNTER < ((SRC_FREQ/FREQUENCY) * DUTY_CYC / 100)) else '0';
end Behavior;