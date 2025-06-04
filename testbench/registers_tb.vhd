library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity registers_tb is
end entity;

architecture testbench of registers_tb is

    component REG_FILE is
        generic (BIT_DEPTH : Integer := 16);

        port (
            RESET : in std_logic;
            IN0, IN1, IN2 : in std_logic_vector(15 downto 0);
            CLK, CLK_EN : in std_logic;
            INSEL : in std_logic_vector(1 downto 0);
            OPA, OPB, OPC : in std_logic_vector(2 downto 0);
            WERF, RBSEL : in std_logic;

            AOUT : out std_logic_vector(15 downto 0);
            BOUT : out std_logic_vector(15 downto 0);
            AZERO : out std_logic
        );
    end component;

  component CLK_ENABLE is
	generic (
		QUANTA_MAX : Integer := 4;
		QUANTA_ENABLE : Integer := 1
	);

	port (
		CLK_IN : in std_logic;
		CLK_EN : out std_logic
	);
end component;

  signal  reset: std_logic := '1';
  signal  clock : std_logic := '0';
  signal  clk_en : std_logic := '0';
  signal  in0_stim : std_logic_vector(15 downto 0) := (others => '0');
  signal  in1_stim : std_logic_vector(15 downto 0) := (others => '0');
  signal  in2_stim : std_logic_vector(15 downto 0) := (others => '0');
  signal  insel_stim : std_logic_vector(1 downto 0) := (others => '0');
  signal  operand_stim : std_logic_vector(8 downto 0) := (others => '0'); -- opa[2:0]/opb[2:0]/opc[2:0]
  signal  rbsel_stim : std_logic := '0';
  signal  werf_stim : std_logic := '0';

  signal  aout_resp : std_logic_vector(15 downto 0);
  signal  bout_resp : std_logic_vector(15 downto 0);
  signal  azero_resp : std_logic;

begin
  clk: CLK_ENABLE generic map(10, 1) port map ( -- divide clock by 10 for clock enable signal
	  CLK_IN => clock,
	  CLK_EN => clk_en
  );

  dut: REG_FILE port map (
	  RESET => reset,
      IN0 => in0_stim,
      IN1 => in1_stim,
      IN2 => in2_stim, 
	  CLK => clock,
	  CLK_EN => clk_en,
	  INSEL => insel_stim,
      OPA => operand_stim(8 downto 6),
      OPB => operand_stim(5 downto 3),
      OPC => operand_stim(2 downto 0),
      WERF => werf_stim,
      RBSEL => rbsel_stim,
      AOUT => aout_resp,
      BOUT => bout_resp,
      AZERO => azero_resp
  );

  -- clock for RegFile module
  clock <= not clock after 5 ns; -- chip clock is 10 ns, cpu clock is 100 ns
   
  -- exercise the RegFile component
  process
  begin
    -- set up input signals
    in0_stim <= X"DEAD";
    in1_stim <= X"BEEF";
    in2_stim <= X"B0D1";

	-- negate reset after 75ns
	wait for 75 ns;
    reset <= '0';
	
    wait until rising_edge(CLK_EN);
    
	-- load values into the registers
    for i in 1 to 7 loop
        werf_stim <= '1';
        operand_stim(8 downto 6) <= std_logic_vector(to_unsigned(i, 3) - 2);
        operand_stim(5 downto 3) <= std_logic_vector(to_unsigned(i, 3) - 1);
        operand_stim(2 downto 0) <= std_logic_vector(to_unsigned(i, 3));
        insel_stim <= std_logic_vector(to_unsigned(i mod 3, 2));
        wait for 100 ns;

        werf_stim <= '0';
        wait for 100 ns;
    end loop;
	
    operand_stim(8 downto 6) <= "010"; -- register 2 to Channel A
    operand_stim(5 downto 3) <= "100"; -- register 4 to Channel B
    wait for 100 ns;

    rbsel_stim <= '1';
    operand_stim(8 downto 6) <= "011"; -- register 3 to Channel A
    operand_stim(2 downto 0) <= "110"; -- register 6 to Channel B (via operand C and rbsel)
    wait for 100 ns;

    rbsel_stim <= '0';
    operand_stim(8 downto 6) <= "100"; -- register 3 to Channel A
    operand_stim(5 downto 3) <= "101"; -- register 5 to Channel B (via operand B)
	wait for 100 ns;

	reset <= '1';
	
	wait;
  end process;

end;
