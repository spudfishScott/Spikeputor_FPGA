-- Spikeputor Register File
-- Inputs:
--     Three Data Inputs 
--     Three Register Controls (OPA, OPB, OPC) from the opcode 
--     CLK, Input Select
--     WERF (Write enable register flag) and RBSEL (Register Channel B Selector)
-- Outputs:
--     Two Data Outputs (Channel A and Channel B)
--     Zero detect for Register Channel A 

-- All data is BIT_DEPTH bits wide. (use 16 for Spikeputor)
-- Register controls are 3 bits wide (for 8 registers). Input select is 2 bits wide for 3 inputs

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Types.all;

entity REG_FILE is

    port (
        -- register file inputs
        CLK           : in std_logic;   
        IN0, IN1, IN2 : in std_logic_vector(BIT_DEPTH-1 downto 0);
        WDSEL         : in std_logic_vector(1 downto 0);
        OPA, OPB, OPC : in std_logic_vector(2 downto 0);
        WERF, RBSEL   : in std_logic;

        -- register file outputs for CPU (also will drive LEDs)
        AOUT          : out std_logic_vector(BIT_DEPTH-1 downto 0);
        BOUT          : out std_logic_vector(BIT_DEPTH-1 downto 0);
        AZERO         : out std_logic;

        -- outputs to drive LEDs only
        SEL_INPUT     : out std_logic_vector(BIT_DEPTH-1 downto 0);
        SEL_A         : out std_logic_vector(7 downto 0);
        SEL_B         : out std_logic_vector(7 downto 0);
        SEL_W         : out std_logic_vector(7 downto 0);
        REG_DATA      : out RARRAY
    );
	 
end REG_FILE;

architecture RTL of REG_FILE is
    constant ZEROS  : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    -- internal signals
    signal reg_in   : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    signal aout_sel : std_logic_vector(2 downto 0) := (others => '0');
    signal bout_sel : std_logic_vector(2 downto 0) := (others => '0');
    signal   wr_sel : std_logic_vector(2 downto 0) := (others => '0');
    signal aout_int : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    signal wreg_sel : std_logic_vector(7 downto 0) := (others => '0');
    signal REGS_OUT : RARRAY := (others => (others => '0'));

begin   -- architecture begin

    -- Handle Register Inputs
    REG_INS : entity work.MUX3 generic map(BIT_DEPTH) port map (
        IN2 => IN2,
        IN1 => IN1,
        IN0 => IN0,
        SEL => WDSEL,
        MUXOUT => reg_in
    );

    -------------------------------
    -- Internal Wiring, Addressing and Zero Detection logic

    -- Register Address Controls
    -- Channel A selection is simply OPA
    aout_sel <= OPA;

    -- Channel B selection depends on the RBSEL signal and is either OPB or OPC
    bout_sel <= OPB when RBSEL = '0' else OPC;

    -- Register Write selection depends on WERF, OPC is WERF is selected, Register 0 if not
    wr_sel   <= OPC when WERF = '1' else "000"; -- if WERF is not set, "write" to Register 0

    -- Register File Outputs (for CPU)
    AOUT  <= aout_int;
    AZERO <= '1' when aout_int = ZEROS else '0';   -- zero detect output

    -- Other Outputs (for LEDs)
    SEL_INPUT <= REG_IN;
    SEL_W     <= wreg_sel;
    REG_DATA  <= regs_out;
    
    -------------------------------
    -- Entity Instantiation
    -- Decoders
    WREG_CTRL: entity work.DECODE3_8 port map ( -- Register Write Select
        DECIN => wr_sel,
        OUTS  => wreg_sel
    );

    AREG_CTRL: entity work.DECODE3_8 port map ( -- Register A Select
        DECIN => aout_sel,
        OUTS  => SEL_A
    );

    BREG_CTRL: entity work.DECODE3_8 port map ( -- Register B Select
        DECIN => bout_sel,
        OUTS  => SEL_B
    );

    -- Registers
    REGISTERS: for r in 1 to 7 generate   -- generate the 7 registers
    begin
        RX : entity work.REG_LE generic map(BIT_DEPTH) port map (  -- Registers
            CLK => CLK,
            LE  => wreg_sel(r),
            D   => reg_in,
            Q   => regs_out(r)
        );
    end generate REGISTERS;

    -- Register Output B
    REGOUT_B: entity work.MUX8 generic map(BIT_DEPTH) port map (   -- Register Channel B Output
        IN7 => regs_out(7),
        IN6 => regs_out(6),
        IN5 => regs_out(5),
        IN4 => regs_out(4),
        IN3 => regs_out(3),
        IN2 => regs_out(2),
        IN1 => regs_out(1),
        IN0 => (others => '0'),     -- Register 0 is always 0
        SEL => bout_sel,
        MUXOUT => BOUT
    );

        -- Register Output A
    REGOUT_A: entity work.MUX8 generic map(BIT_DEPTH) port map (   -- Register Channel A Output
        IN7 => regs_out(7),
        IN6 => regs_out(6),
        IN5 => regs_out(5),
        IN4 => regs_out(4),
        IN3 => regs_out(3),
        IN2 => regs_out(2),
        IN1 => regs_out(1),
        IN0 => (others => '0'),     -- Register 0 is always 0
        SEL => aout_sel,
        MUXOUT => aout_int
    );

end RTL;
