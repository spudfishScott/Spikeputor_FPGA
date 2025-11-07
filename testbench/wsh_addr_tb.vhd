-- tb_wsh_addr.vhd
-- Self-checking test bench for WSH_ADDR (VHDL-93)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Keep if your project has this package (DUT references work.Types)
use work.Types.all;

entity wsh_addr_tb is
end wsh_addr_tb;

architecture sim of wsh_addr_tb is
  -- DUT-facing signals
  signal ADDR_I     : std_logic_vector(23 downto 0) := (others => '0');
  signal WE_I       : std_logic := '0';
  signal STB_I      : std_logic := '0';
  signal BANK_SEL   : std_logic_vector(1 downto 0) := "01";  -- default 01

  -- Provider data signatures (distinct so mux selection is obvious)
  signal P0_DATA_O  : std_logic_vector(15 downto 0) := x"0000"; -- RAM
  signal P1_DATA_O  : std_logic_vector(15 downto 0) := x"1111"; -- ROM
  signal P2_DATA_O  : std_logic_vector(15 downto 0) := x"2222"; -- GPO
  signal P3_DATA_O  : std_logic_vector(15 downto 0) := x"3333"; -- GPI
  signal P4_DATA_O  : std_logic_vector(15 downto 0) := x"4444"; -- BANK_SEL
  signal P5_DATA_O  : std_logic_vector(15 downto 0) := x"5555"; -- SOUND
  signal P6_DATA_O  : std_logic_vector(15 downto 0) := x"6666"; -- VIDEO
  signal P7_DATA_O  : std_logic_vector(15 downto 0) := x"7777"; -- SERIAL
  signal P8_DATA_O  : std_logic_vector(15 downto 0) := x"8888"; -- STORAGE
  signal P9_DATA_O  : std_logic_vector(15 downto 0) := x"9999"; -- SEGMENT
  signal P10_DATA_O : std_logic_vector(15 downto 0) := x"AAAA"; -- SDRAM

  signal DATA_O     : std_logic_vector(15 downto 0);
  signal STB_SEL    : std_logic_vector(10 downto 0);

  subtype slv16 is std_logic_vector(15 downto 0);

  constant STEP : time := 10 ns;

  -- Build the expected one-hot strobe vector by provider index (pure: no signals read)
  function strobe_by_p(p : integer) return std_logic_vector is
    variable s : std_logic_vector(10 downto 0) := (others => '0');
  begin
    if p >= 0 and p <= 10 then
      s(p) := '1';
    end if;
    return s;
  end function;

  -- Read current DUT strobes (impure: reads signals)
--   impure function current_strobes return std_logic_vector is
--     variable s : std_logic_vector(10 downto 0);
--   begin
--     s(0)  := P0_STB_I;
--     s(1)  := P1_STB_I;
--     s(2)  := P2_STB_I;
--     s(3)  := P3_STB_I;
--     s(4)  := P4_STB_I;
--     s(5)  := P5_STB_I;
--     s(6)  := P6_STB_I;
--     s(7)  := P7_STB_I;
--     s(8)  := P8_STB_I;
--     s(9)  := P9_STB_I;
--     s(10) := P10_STB_I;
--     return s;
--   end function;

  -- Single vector driver + checker
  procedure drive_and_check(
    -- >>> Signals to drive must be formal signal parameters <<<
    signal ADDR_s     : out std_logic_vector(23 downto 0);
    signal WE_s       : out std_logic;
    signal STB_s      : out std_logic;
    signal BANK_s     : out std_logic_vector(1 downto 0);
    -- Vector contents + expectations
    constant name_in     : in string;
    constant addr_in     : in std_logic_vector(23 downto 0);
    constant we_in       : in std_logic;
    constant stb_in      : in std_logic;
    constant bank_in     : in std_logic_vector(1 downto 0);
    constant exp_p       : in integer;               -- expected provider index (0..10)
    constant exp_data    : in slv16;                 -- expected DATA_O value
    constant exp_stb_on  : in boolean                -- whether any strobe should assert
  ) is
    variable exp_strobes : std_logic_vector(10 downto 0);
    variable got_strobes : std_logic_vector(10 downto 0);
  begin
    -- drive via formal signal parameters
    ADDR_s <= addr_in;
    WE_s   <= we_in;
    STB_s  <= stb_in;
    BANK_s <= bank_in;

    wait for STEP; -- allow combinational settle

    -- data check
    assert DATA_O = exp_data
      report "FAIL[" & name_in & "]: DATA_O mismatch."
      severity error;

    -- strobe check
    if exp_stb_on then
      exp_strobes := strobe_by_p(exp_p);
    else
      exp_strobes := (others => '0');
    end if;

    assert STB_SEL = exp_strobes
      report "FAIL[" & name_in & "]: strobe vector mismatch."
      severity error;

    report "PASS[" & name_in & "]";
  end procedure;

begin
  -- DUT instantiation
  dut: entity work.WSH_ADDR
    port map (
      ADDR_I     => ADDR_I,
      WE_I       => WE_I,
      STB_I      => STB_I,
      BANK_SEL   => BANK_SEL,

      P0_DATA_O  => P0_DATA_O,
      P1_DATA_O  => P1_DATA_O,
      P2_DATA_O  => P2_DATA_O,
      P3_DATA_O  => P3_DATA_O,
      P4_DATA_O  => P4_DATA_O,
      P5_DATA_O  => P5_DATA_O,
      P6_DATA_O  => P6_DATA_O,
      P7_DATA_O  => P7_DATA_O,
      P8_DATA_O  => P8_DATA_O,
      P9_DATA_O  => P9_DATA_O,
      P10_DATA_O => P10_DATA_O,

      DATA_O     => DATA_O,
      STB_SEL    => STB_SEL
    );

  -- Test sequence (same vectors)
  stimulus: process
  begin
    BANK_SEL <= "01";  -- X01
    wait for STEP;

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "A:read RAM, X01",
      x"001234", '0', '1', "01",
      0, x"0000", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "B:read ROM, X01",
      x"009000", '0', '1', "01",
      1, x"1111", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "C:write in ROM addr -> RAM, X01",
      x"009000", '1', '1', "01",
      0, x"0000", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "D:STB low, read ROM, X01",
      x"008000", '0', '0', "01",
      1, x"1111", false);

    -- Specials (override)
    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "E:GPO @7FFC",
      x"007FFC", '0', '1', "01",
      2, x"2222", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "F:GPI @7FFE",
      x"007FFE", '0', '1', "01",
      3, x"3333", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "G:BANK_SEL @7FAE",
      x"007FAE", '1', '1', "01",
      4, x"4444", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "H:SOUND @7FAC",
      x"007FAC", '0', '1', "01",
      5, x"5555", true);

    -- X10
    BANK_SEL <= "10";
    wait for STEP;

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "I:X10 read low -> ROM",
      x"001234", '0', '1', "10",
      1, x"1111", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "J:X10 read mid -> RAM",
      x"009000", '0', '1', "10",
      0, x"0000", true);

    -- X11
    BANK_SEL <= "11";
    wait for STEP;

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "K:X11 read anywhere -> ROM",
      x"000002", '0', '1', "11",
      1, x"1111", true);

    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "L:X11 write anywhere -> RAM",
      x"008000", '1', '1', "11",
      0, x"0000", true);

    -- Segment/TGA with SDRAM
    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "M:Segment+SDRAM",
      x"011234", '0', '1', "01",
      10, x"AAAA", true);

    -- Segment but no SDRAM -> ROM
    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "N:Segment no SDRAM -> ROM",
      x"811234", '0', '1', "01",
      1, x"1111", true);

    -- Segment + special
    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "O:Segment+Special GPO",
      x"207FFC", '1', '1', "01",
      10, x"AAAA", true);

    -- STB gating on SDRAM path
    drive_and_check(ADDR_I, WE_I, STB_I, BANK_SEL,
      "P:SDRAM STB low -> no strobes",
      x"012000", '0', '0', "00",
      10, x"AAAA", false);

    report "All test vectors completed." severity note;
    wait;
  end process;
end sim;
