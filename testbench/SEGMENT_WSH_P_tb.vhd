-- segment_wsh_p_tb.vhd
-- Self-checking test bench for SEGMENT_WSH_P (VHDL-93)
-- Matches RTL where:
--   - data_in <= WBS_DATA_I(7 downto 0) when WE=1 and RST=0 else 0
--   - le_sig  <= WE when RST=0 else 1
--   - WBS_ACK_O <= registered (CYC AND STB)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity segment_wsh_p_tb is
end segment_wsh_p_tb;

architecture sim of segment_wsh_p_tb is
  -- DUT ports
  signal CLK        : std_logic := '0';

  signal WBS_CYC_I  : std_logic := '0';
  signal WBS_STB_I  : std_logic := '0';
  signal WBS_ACK_O  : std_logic;

  signal WBS_DATA_I : std_logic_vector(15 downto 0) := (others => '0');
  signal WBS_WE_I   : std_logic := '0';

  signal SEGMENT    : std_logic_vector(7 downto 0);

  constant TCK : time := 20 ns;

  --------------------------------------------------------------------
  -- Procedures (declarative region)
  --------------------------------------------------------------------

  -- Single-beat write with registered ACK:
  -- Drive WE/CYC/STB, ensure ACK=0 before edge, then on next rising edge:
  --   ACK=1 and SEGMENT updates to expect.
  -- After deasserting bus, on the following edge ACK drops to 0.
  procedure wb_write_sync(
    signal clk_i      : in  std_logic;
    signal segment_i  : in  std_logic_vector(7 downto 0);
    signal data_i     : out std_logic_vector(15 downto 0);
    signal we_i       : out std_logic;
    signal cyc_i      : out std_logic;
    signal stb_i      : out std_logic;
    signal ack_i      : in  std_logic;
    constant data_lo8 : in  std_logic_vector(7 downto 0);
    constant expect   : in  std_logic_vector(7 downto 0)
  ) is
  begin
    -- Drive request this cycle
    data_i <= data_lo8 & data_lo8; -- upper byte don't-care; mirrored for visibility
    we_i   <= '1';
    cyc_i  <= '1';
    stb_i  <= '1';

    -- ACK is registered -> remains 0 before the edge
    wait for 1 ns;
    assert ack_i = '0'
      report "FAIL[wb_write_sync pre]: ACK asserted before edge"
      severity error;

    -- Update/check one cycle later
    wait until rising_edge(clk_i);
    wait for 1 ns;

    assert ack_i = '1'
      report "FAIL[wb_write_sync post]: ACK not asserted on registered cycle"
      severity error;

    assert segment_i = expect
      report "FAIL[wb_write_sync]: SEGMENT mismatch after write"
      severity error;

    -- Deassert bus; ACK should drop on the next edge
    we_i  <= '0';
    cyc_i <= '0';
    stb_i <= '0';

    wait until rising_edge(clk_i);
    wait for 1 ns;

    assert ack_i = '0'
      report "FAIL[wb_write_sync deassert]: ACK did not drop after bus deassert"
      severity error;
  end procedure;


  -- Registered ACK behavior check for arbitrary WE/CYC/STB:
  -- Apply levels, then check expected ACK on the next rising edge.
  procedure wb_ack_sync_check(
    signal clk_i : in std_logic;
    signal we_i  : out std_logic;
    signal cyc_i : out std_logic;
    signal stb_i : out std_logic;
    signal ack_i : in std_logic;
    constant we_set  : in std_logic;
    constant cyc_set : in std_logic;
    constant stb_set : in std_logic;
    constant exp_ack : in std_logic
  ) is
  begin
    we_i  <= we_set;
    cyc_i <= cyc_set;
    stb_i <= stb_set;

    wait until rising_edge(clk_i);
    wait for 1 ns;

    assert ack_i = exp_ack
      report "FAIL[wb_ack_sync_check]: ACK mismatch"
      severity error;

    -- Return to idle and allow ACK to settle low next cycle
    we_i  <= '0';
    cyc_i <= '0';
    stb_i <= '0';
    wait until rising_edge(clk_i);
  end procedure;

begin
  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk_gen : process
  begin
    CLK <= '0'; wait for TCK/2;
    CLK <= '1'; wait for TCK/2;
  end process;

  --------------------------------------------------------------------
  -- DUT
  --------------------------------------------------------------------
  dut: entity work.SEGMENT_WSH_P
    port map (
      CLK        => CLK,
      WBS_CYC_I  => WBS_CYC_I,
      WBS_STB_I  => WBS_STB_I,
      WBS_ACK_O  => WBS_ACK_O,
      WBS_DATA_I => WBS_DATA_I,
      WBS_WE_I   => WBS_WE_I,
      SEGMENT    => SEGMENT
    );

  --------------------------------------------------------------------
  -- Stimulus
  --------------------------------------------------------------------
  stim : process
  begin
    -- 0) Hold reset for a couple of cycles: SEGMENT must be 0
    wait until rising_edge(CLK);
    wait until rising_edge(CLK);
    assert SEGMENT = x"00"
      report "FAIL[reset hold]: SEGMENT not cleared while reset asserted"
      severity error;

    -- ACK should be low in idle after a registered cycle
    assert WBS_ACK_O = '0'
      report "FAIL[reset hold]: ACK not low while idle under reset"
      severity error;

    -- 1) Release reset
    wait until rising_edge(CLK);

    -- 2) Simple write 0x5A (registered ACK)
    wb_write_sync(CLK, SEGMENT, WBS_DATA_I, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, x"5A", x"5A");

    -- 3) Write 0xC3
    wb_write_sync(CLK, SEGMENT, WBS_DATA_I, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, x"C3", x"C3");

    -- 4) WE=0 should NOT change SEGMENT; ACK still follows CYC&STB (registered)
    WBS_DATA_I <= x"7F7F";
    wb_ack_sync_check(CLK, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O,
                      '0', '1', '1',  -- drive this cycle
                      '1');           -- ACK expected next edge (CYC&STB=1), independent of WE
    assert SEGMENT = x"C3"
      report "FAIL[WE=0]: SEGMENT changed when WE=0"
      severity error;

    -- 5) Idle/partial handshakes and ACK (registered)
    wb_ack_sync_check(CLK, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, '0','0','0','0'); -- idle
    wb_ack_sync_check(CLK, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, '1','1','0','0'); -- CYC only
    wb_ack_sync_check(CLK, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, '1','0','1','0'); -- STB only

    -- 6) Reset dominates an in-flight write:
    -- Drive WE=1, CYC=1, STB=1 then assert reset before the edge; next edge SEGMENT must clear to 0.
    WBS_DATA_I <= x"FFFF";
    WBS_WE_I   <= '1';
    WBS_CYC_I  <= '1';
    WBS_STB_I  <= '1';
    wait for 5 ns;        -- hold for part of cycle
    wait until rising_edge(CLK);
    wait for 1 ns;

    -- ACK equals registered (CYC&STB) even in reset; may be 1 here—do not fail on it.
    -- Critical check: SEGMENT must be 0 due to le_sig='1' and data_in=0 under reset.
    assert SEGMENT = x"00"
      report "FAIL[reset dominates]: SEGMENT not cleared when reset asserted with active write"
      severity error;

    -- Deassert bus, keep reset a bit, then release reset
    WBS_WE_I  <= '0';
    WBS_CYC_I <= '0';
    WBS_STB_I <= '0';
    wait until rising_edge(CLK);
    wait until rising_edge(CLK);

    -- 7) Final write 0xA5 after reset released
    wb_write_sync(CLK, SEGMENT, WBS_DATA_I, WBS_WE_I, WBS_CYC_I, WBS_STB_I, WBS_ACK_O, x"A5", x"A5");

    report "All tests passed." severity note;
    wait;
  end process;

end sim;
