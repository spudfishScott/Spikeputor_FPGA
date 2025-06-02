library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This module synthesizes registers with various functionality

-- This is a D-REG that updates half at a time depending on the value of SEL and if LE is set
entity REG_HILO is
	generic (n : positive); -- width of register in bits
	
	port (
		CLK, EN, SEL, LE : in std_logic; -- clock, clock enable, hi/lo select, latch enable active high
		       REGIN : in std_logic_vector((n/2)-1 downto 0);	-- input for hi/lo register is half the full width
		       REGOUT: out std_logic_vector(n-1 downto 0)     -- output is the full width register
	);
end REG_HILO;

architecture Behavior of REG_HILO is
	signal REG_HIGH : std_logic_vector((n/2)-1 downto 0) := (others => '0');
	signal REG_LOW : std_logic_vector((n/2)-1 downto 0) := (others => '0');
	
begin
	assert (n mod 2 = 0) severity failure;	-- for a hi/lo register, n must be even
	
	-- hi/lo D-REG with latch enable
	P_REG_HILO : process(CLK) is
	begin
		if (EN = '1' and rising_edge(CLK)) then -- rising edge of clock and REG is enabled
			if (LE = '1') then -- if latch enable is high, update the correct half of the register
				if (SEL = '1') then
					REG_HIGH <= REGIN; -- if SEL is high, update the high portion of the register from input
				else
					REG_LOW <= REGIN; -- if SEL is low, update the low portion of the register from input
				end if;
			end if;
		end if;
	end process P_REG_HILO;
  
	REGOUT <= REG_HIGH & REG_LOW;	-- output is concatenation of HIGH and LOW internal register
end Behavior;

entity REG_LE is
	generic (n: positive); -- width of register

	port (
		RESET, EN, CLK, LE : in std_logic; -- clock, reset, latch enable, register enable
		REGIN : in std_logic_vector(n-1 downto 0);	-- input
		DOUT : out std_logic_vector(n-1 downto 0)	-- output channel A
	);
end REG_LE;

architecture Behavior of REG_LE is
	signal DATA : std_logic_vector(n-1 downto 0); -- the internal data memory
begin
	P_REG_LE : process(CLK, RESET) is
	begin
		if (RESET = '1') then
			DATA <= (others => '0');	-- clear out registers on reset
		else
			if (EN = '1' and rising_edge(CLK)) then -- changes on rising edge of clock
				if (LE = '1') then
					DATA <= REGIN;
				end if;
			end if;
		end if;
	end process P_REG_LE;

	-- send internal data to output
	DOUT <= DATA;
end Behavior;


	