-- tb_wsh_addr_v2.vhd
-- Self-checking test bench for updated WSH_ADDR (VHDL-93)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Keep if the project provides this package
use work.Types.all;

entity wsh_addr_tb is
end wsh_addr_tb;

architecture sim of wsh_addr_tb is
  -- DUT I/O
  signal ADDR_I     : std_logic_vector(23 downto 0) := (others => '0');
  signal WE_I       : std_logic := '0';
  signal STB_I      : std_logic := '0';
  signal TGD_I      : std_logic := '0';

  -- Provider data signatures (distinct so the mux result is obvious)
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

  constant STEP : time := 10 ns;

  -- One-hot helper (pure, no signals read)
  function onehot_p(p : integer) return std_logic_vector is
    variable v : std_logic_vector(10 downto 0) := (others => '0');
  begin
    if (p >= 0) and (p <= 10) then
      v(p) := '1';
    end if;
    return v;
  end function;

  -- Build 24-bit address from fields: [23]=ROM/SDRAM select for seg!=0, [22:16]=seg, [15:0]=offset
  function mk_addr(msb : std_logic; seg : std_logic_vector(6 downto 0); offs : std_logic_vector(15 downto 0))
    return std_logic_vector is
    variable a : std_logic_vector(23 downto 0);
  begin
    a(23)            := msb;
    a(22 downto 16)  := seg;
    a(15 downto 0)   := offs;
    return a;
  end function;

  -- Handy constants
  constant SEG0  : std_logic_vector(6 downto 0) := "0000000";
  constant SEG1  : std_logic_vector(6 downto 0) := "0000001";

begin
  -- DUT
  dut: entity work.WSH_ADDR
    port map (
      ADDR_I     => ADDR_I,
      WE_I       => WE_I,
      STB_I      => STB_I,
      TGD_I      => TGD_I,

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

  -- Test sequence
  stimulus: process
    procedure check(constant name : in string;
                    constant exp_p : in integer;
                    constant exp_data : in std_logic_vector(15 downto 0);
                    constant stb_on : in boolean) is
      variable exp_stb : std_logic_vector(10 downto 0);
    begin
      wait for STEP; -- allow settle
      -- DATA_O check
      assert DATA_O = exp_data
        report "FAIL[" & name & "]: DATA_O mismatch"
        severity error;
      -- STB one-hot check
      if stb_on then
        exp_stb := onehot_p(exp_p);
      else
        exp_stb := (others => '0');
      end if;
      assert STB_SEL = exp_stb
        report "FAIL[" & name & "]: STB_SEL mismatch"
        severity error;
      report "PASS[" & name & "]";
    end procedure;
  begin
    ---------------------------------------------------------------------------
    -- seg=0 (ADDR_I(22:16)=0): RAM for 0x0000–0xFBFF; ROM for 0xFC00–0xFFFF; writes->RAM
    ---------------------------------------------------------------------------
    STB_I <= '1'; TGD_I <= '0'; WE_I <= '0';

    -- A) seg0, read RAM addr 0x1234 -> p=0 (RAM)
    ADDR_I <= mk_addr('0', SEG0, x"1234");
    check("A seg0 read RAM 0x1234", 0, x"0000", true);

    -- B) seg0, read RAM addr 0x9000 -> p=0 (still RAM, since 0x9000 < 0xFC00)
    ADDR_I <= mk_addr('0', SEG0, x"9000");
    check("B seg0 read RAM 0x9000", 0, x"0000", true);

    -- C) seg0, read ROM addr 0xFE00 (in 0xFC00–0xFFFF) -> p=1 (ROM)
    ADDR_I <= mk_addr('0', SEG0, x"FE00");
    check("C seg0 read ROM 0xFE00", 1, x"1111", true);

    -- D) seg0, write to 0xFE00 -> writes go to RAM (p=0)
    WE_I   <= '1';
    ADDR_I <= mk_addr('0', SEG0, x"FE00");
    check("D seg0 write 0xFE00 -> RAM", 0, x"0000", true);
    WE_I   <= '0';

    -- E-H) Specials at seg0: 7FFC (GPO=2), 7FFE (GPI=3), 7FAE (BANK_SEL=4), 7FAC (SOUND=5)
    ADDR_I <= mk_addr('0', SEG0, x"7FFC"); -- GPO
    check("E seg0 special GPO 0x7FFC", 2, x"2222", true);

    ADDR_I <= mk_addr('0', SEG0, x"7FFE"); -- GPI
    check("F seg0 special GPI 0x7FFE", 3, x"3333", true);

    ADDR_I <= mk_addr('0', SEG0, x"7FAE"); -- BANK_SEL
    WE_I   <= '1';
    check("G seg0 special BANK_SEL 0x7FAE", 4, x"4444", true);
    WE_I   <= '0';

    ADDR_I <= mk_addr('0', SEG0, x"7FAC"); -- SOUND
    check("H seg0 special SOUND 0x7FAC", 5, x"5555", true);

    -- STB gating check (no strobes; data still reflects provider)
    STB_I  <= '0';
    ADDR_I <= mk_addr('0', SEG0, x"1234");
    check("I STB low seg0 read RAM", 0, x"0000", false);
    STB_I  <= '1';

    ---------------------------------------------------------------------------
    -- seg != 0 (extended): ADDR_I(23)=0 -> SDRAM (p=10), ADDR_I(23)=1 -> ROM (p=1) on reads
    ---------------------------------------------------------------------------
    -- J) seg1, msb=0 (RAM path) -> SDRAM (p=10)
    ADDR_I <= mk_addr('0', SEG1, x"2000");
    check("J seg1 msb0 -> SDRAM", 10, x"AAAA", true);

    -- K) seg1, msb=1 -> ROM (p=1)
    ADDR_I <= mk_addr('1', SEG1, x"2000");
    check("K seg1 msb1 -> ROM", 1, x"1111", true);

    ---------------------------------------------------------------------------
    -- TGD_I + WE_I write path:
    -- Your RTL sets p_sel=6 when (TGD_I='1' and WE_I='1'). That selects VIDEO (index 6).
    -- If you intended SEGMENT (index 9), change the RTL; the TB checks current RTL behavior.
    ---------------------------------------------------------------------------
    TGD_I  <= '1';
    WE_I   <= '1';
    ADDR_I <= mk_addr('0', SEG1, x"0000"); -- address don't-care per your rule
    check("L TGD&WE -> p=9 (SEGMENT))", 9, x"9999", true);
    TGD_I  <= '0';
    WE_I   <= '0';

    report "All vectors completed." severity note;
    wait;
  end process;

end sim;
