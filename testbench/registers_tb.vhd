library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity registers_tb is
end entity;

architecture testbench of registers_tb is

  component REG_HILO
    generic (width : positive); -- width of register in bits
    port (
      RESET, CLK, EN, LE, SEL: in std_logic; -- clock, clock enable, hi/lo select, latch enable active high
	    D : in std_logic_vector((width/2)-1 downto 0);	-- input for hi/lo register is half the full width
	    Q: out std_logic_vector(width-1 downto 0)     -- output is the full width register
	  );
  end component;

  component CLK_ENABLE is
	generic (
		QUANTA_MAX : Integer := 4;
		QUANTA_ENABLE : Integer := 1
	);

	port (
		CLK_IN, RESET : in std_logic;
		CLK_EN : out std_logic
	);
end component;

  signal  reset: std_logic := '1';
  signal  clock : std_logic := '0';
  signal  clk_en : std_logic := '0';
  signal  data_stim : std_logic_vector(7 downto 0) := (others => '0');
  signal  sel_stim : std_logic := '0';
  signal  le_stim : std_logic := '0';
  signal  dataq_resp : std_logic_vector(15 downto 0);

begin
  clk: CLK_ENABLE generic map(2, 2) port map (
	  CLK_IN => clock,
	  CLK_EN => clk_en
  );

  dut: REG_HILO generic map(16) port map (
	  RESET => reset, 
	  CLK => clock,
	  EN => clk_en,
	  LE => le_stim, 
	  SEL => sel_stim, 
	  D => data_stim, 
	  Q => dataq_resp
  );

  -- clock for REG_HILO module
  clock <= not clock after 5 ns;
   
  -- exercise the REG_HILO component
  process
  begin
	-- negate reset after 20ns
	wait for 20 ns;
  reset <= '0';
	
	-- latch FE into MSB
	data_stim <= X"FE";
	le_stim <= '1';
	sel_stim <= '1';
	
	wait for 10 ns;
	
	-- idle for 30 ns
	le_stim <= '0';
	sel_stim <= '0';
	
	wait for 30 ns;
	
	-- latch ED into LSB
	data_stim <= X"ED";
	le_stim <= '1';
	sel_stim <= '0';

	wait for 10 ns;
	
	-- idle for remainder of simulation
	le_stim <= '0';
	sel_stim <= '0';
	
	wait for 18 ns;
	reset <= '1';
	
	wait;
  end process;

end;
