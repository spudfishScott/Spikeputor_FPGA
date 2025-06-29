-- "Hello World" Register test synthesized on the DE0

library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity RegTest is
	port (
		-- CLOCK
		CLOCK_50 : in std_logic;
		-- Push Button
		BUTTON : in std_logic_vector(2 downto 0);
		-- DPDT Switch
		SW : in std_logic_vector(9 downto 0);
		-- 7-SEG Display
		HEX0_D : out std_logic_vector(6 downto 0);
		HEX0_DP : out std_logic;
		HEX1_D : out std_logic_vector(6 downto 0);
		HEX1_DP : out std_logic;
		HEX2_D : out std_logic_vector(6 downto 0);
		HEX2_DP : out std_logic;
		HEX3_D : out std_logic_vector(6 downto 0);
		HEX3_DP : out std_logic;
		-- LED
		LEDG : out std_logic_vector(9 downto 0)
	);
end RegTest;

architecture Structural of RegTest is
	-- Signal Declarations
	signal REG : std_logic_vector(15 downto 0);
	signal REG_EN : std_logic;

begin
	-- Structure
	CLOCK : entity work.CLK_ENABLE generic map(2, 1) port map (
		RESET => '0',
		CLK_IN => CLOCK_50,
		CLK_EN => REG_EN
	);

	-- D REG with enable
	HILO_16 : entity work.REG_HILO generic map(16) port map (	-- register is 16 bits wide
		CLK => CLOCK_50,
		 EN => REG_EN,
		SEL => SW(9),		-- switch 9 up = update high byte, down = update low byte
		 LE => NOT BUTTON(0), 	-- enable is button 0, invert it because the reg is active high and the button is active low
		  D => SW(7 downto 0), 	-- input is switches 7 to 0
		 Q => REG
	);
	
	-- Word to 7 Segment Output
	SEGSOUT : entity work.WORDTO7SEGS port map (
		 WORD => REG,
		SEGS3 => HEX3_D,
		SEGS2 => HEX2_D,
		SEGS1 => HEX1_D,
		SEGS0 => HEX0_D
	);

	-- assign output states for unused 7 segment display decimal point and unused LEDs
	HEX0_DP <= '1';
	HEX1_DP <= '1';
	HEX2_DP <= '1';
	HEX3_DP <= '1';
	LEDG(8 downto 1) <= (others => '0');
  
	-- assign output signals from variable signals
	LEDG(0) <= REG_EN;
	LEDG(9) <= NOT BUTTON(0);

end Structural;
