library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_arith.all;
  use ieee.std_logic_unsigned.all;

entity DE0_CTRLTest is
    port (
        -- Clock Input
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
        LEDG : out std_logic_vector(9 downto 0);
        -- GPIO
        GPIO0_D : in std_logic_vector(31 downto 0);
        GPIO1_D : out std_logic_vector(31 downto 0)
    );
end DE0_CTRLTest;

architecture Structural of DE0_CTRLTest is
    -- Signal Declarations
    signal cyc    : std_logic := '0';
    signal stb    : std_logic := '0';
    signal ack    : std_logic := '0';
    signal addr   : std_logic_vector(15 downto 0) := (others => '0');
    signal data_o : std_logic_vector(15 downto 0) := (others => '0');
    signal data_i : std_logic_vector(15 downto 0) := (others => '0');
    signal we     : std_logic := '0';

    signal disp_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal inst_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal const_out : std_logic_vector(15 downto 0) := (others => '0');
	 
    -- Clock selection signal
    signal system_clk : std_logic;
    
    -- Clock selection attribute - to aid in synthesis
    attribute keep : string;
    attribute keep of system_clk : signal is "true";
    attribute preserve : string;
    attribute preserve of system_clk : signal is "true";
    
    begin
	 -- Select between automatic and manual clock based on SW(0)
    system_clk <= CLOCK_50 when SW(0) = '1' else NOT Button(1);

    -- connect INST or CONST output to GPIO1 for testing based on SW(1)
    GPIO1_D(31 downto 16) <= inst_out when SW(1) = '1' else const_out;
	 
    -- Control Logic Instance
    CTRL : entity work.CTRL_WSH_M port map (
        -- SYSCON inputs
        CLK         => system_clk,
        RST_I       => NOT Button(0), -- Button 0 is reset button

        -- Wishbone signals for memory interface
        -- handshaking signals
        WBS_CYC_O   => cyc,
        WBS_STB_O   => stb,
        WBS_ACK_I   => ack,

        -- memory read/write signals
        WBS_ADDR_O  => addr,
        WBS_DATA_O  => data_o, -- output from master, input to provider
        WBS_DATA_I  => data_i, -- input to master, output from provider
        WBS_WE_O    => we,

        -- Spikeputor Signals
        -- Data outputs from Control Logic to other modules
        INST        => inst_out,
        CONST       => const_out,
        PC          => disp_out,                -- output current PC for testing
        PC_INC      => open,
        MRDATA      => GPIO1_D(15 downto 0),    -- output memory read data for testing
        -- Control signals from Control Logic to other modules
        WERF        => LEDG(9),
        RBSEL       => LEDG(8),
        WDSEL       => LEDG(7 downto 6),
        -- Inputs to Control Logic from other modules
        ALU_OUT     => GPIO0_D(31 downto 16),
        MWDATA      => GPIO0_D(15 downto 0),
        Z           => SW(9),

        PHASE       => LEDG(1 downto 0)
    );

    -- RAM Instance
    RAM : entity work.RAMTest_WSH_P port map (  -- use test RAM to execute a simple program
        -- SYSCON inputs
        CLK         => system_clk,
        RST_I       => NOT Button(0), -- Button 0 is reset button

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   => cyc,
        WBS_STB_I   => stb,
        WBS_ACK_O   => ack,

        -- memory read/write signals
        WBS_ADDR_I  => addr,
        WBS_DATA_O  => data_i,
        WBS_DATA_I  => data_o,
        WBS_WE_I    => we       
    );

      -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => disp_out,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

-- Set default output states

-- 7-SEG Display
HEX0_DP <= '1';
HEX1_DP <= '1';
HEX2_DP <= '1';
HEX3_DP <= '1';

-- LED
LEDG(5 downto 2) <= (others => '0');

end Structural;
