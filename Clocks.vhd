library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This module synthesizes a clock of desired frequency from an input clock of defined frequency and duty cycle
entity FREQ_CLOCK is
	generic ( -- Desired Frequency in Hz
		FREQUENCY : Integer := 1000;
		 SRC_FREQ : Integer := 50000000;
		 DUTY_CYC : Integer := 50;
	);
	
	port(
		 CLK_IN : in std_logic;
		CLK_OUT : out std_logic
	);
end FREQ_CLOCK;

architecture Behavior of FREQ_CLOCK is
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

-- Clock Enable entity
-- Produces an enable signal every QUANTA_ENABLE ticks of QUANTA_MAX ticks
-- Everyone gets the system clock signal and their own clock enable signal as required
-- This gives a more FPGA-friendly "clock divider" with one monolithic clock signal and tailored enable signals
-- Includes asynchronous reset 
entity CLK_ENABLE is
	generic (
		QUANTA_MAX : Integer := 100;
		QUANTA_ENABLE : Integer := 0;
	);

	port (
		CLK_IN, RESET : in std_logic;
		CLK_EN : out std_logic;
	);
end CLK_ENABLE;

architecture Behavior of CLK_ENABLE is
	signal QUANTA : Integer := 0;
begin
	CLK_TICK : process(CLK_IN, RESET)
	begin
		if RESET = '1' then
			QUANTA <= 0;
		else
			if rising_edge(CLK_IN) then
				if (QUANTA = QUANTA_MAX) then
					QUANTA <= 0;
				else
					QUANTA <= QUANTA + 1;
				end if;
			end if;
		end if;
	end process CLK_TICK;

	CLK_EN <= '1' when QUANTA = QUANTA_ENABLE - 1 else '0';
end Behavior;
