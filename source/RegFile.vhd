-- Spikeputor Register File
-- Inputs:
--     Asynchronous RESET to clear all registers
--     Three Data Inputs 
--     Three Register Controls (OPA, OPB, OPC) from the opcode 
--     Clock Enable, CLK, Input Select
--     WERF (Write enable register flag) and RBSEL (Register Channel B Selector)
-- Outputs:
--     Two Data Outputs (Channel A and Channel B)
--     Zero detect for Register Channel A 

-- All data is BIT_DEPTH bits wide. (use 16 for Spikeputor)
-- Register controls are 3 bits wide (for 8 registers). Input select is 2 bits wide for 3 inputs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package Types is
    constant BIT_DEPTH : Integer := 16;
    type RARRAY is array(1 to 7) of std_logic_vector(BIT_DEPTH-1 downto 0);
end package Types;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Types.all;

entity REG_FILE is

    port (

        -- register file inputs
        RESET         : in std_logic;
        CLK, CLK_EN   : in std_logic;
        IN0, IN1, IN2 : in std_logic_vector(BIT_DEPTH-1 downto 0);
        INSEL         : in std_logic_vector(1 downto 0);
        OPA, OPB, OPC : in std_logic_vector(2 downto 0);
        WERF, RBSEL   : in std_logic;

        -- register file outputs for CPU (also will drive LEDs)
        AOUT  : out std_logic_vector(BIT_DEPTH-1 downto 0);
        BOUT  : out std_logic_vector(BIT_DEPTH-1 downto 0);
        AZERO : out std_logic;

        -- outputs to drive LEDs only
        SEL_INPUT : out std_logic_vector(BIT_DEPTH-1 downto 0);
        SEL_A     : out std_logic_vector(7 downto 0);
        SEL_B     : out std_logic_vector(7 downto 0);
        SEL_W     : out std_logic_vector(7 downto 0);
        REG_DATA  : out RARRAY
    );
	 
end REG_FILE;

architecture RTL of REG_FILE is
    constant ZEROS : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    -- internal signals
    signal REG_IN   : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    signal AOUT_SEL : std_logic_vector(2 downto 0) := (others => '0');
    signal BOUT_SEL : std_logic_vector(2 downto 0) := (others => '0');
    signal   WR_SEL : std_logic_vector(2 downto 0) := (others => '0');
    signal AOUT_INT : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');
    signal BOUT_INT : std_logic_vector(BIT_DEPTH-1 downto 0) := (others => '0');

    -- internal signals only for LEDs
    signal AREG_SEL : std_logic_vector(7 downto 0) := (others => '0');
    signal BREG_SEL : std_logic_vector(7 downto 0) := (others => '0');
    signal WREG_SEL : std_logic_vector(7 downto 0) := (others => '0');
    signal REGS_OUT : RARRAY := (others => (others => '0'));

    -- required to insure that the inputs would not be optimized away (causing fitter to hang)
    -- NOT NEEDED if Multi-corner hold-timer optimization is off in Quartus!
--    attribute keep : boolean;
--    attribute keep of IN0 : signal is true;
--    attribute keep of IN1 : signal is true;
--    attribute keep of IN2 : signal is true;

begin   -- architecture begin

    -- Handle Register Inputs
    REG_INS : entity work.MUX3 generic map(BIT_DEPTH) port map (
           IN2 => IN2,
           IN1 => IN1,
           IN0 => IN0,
           SEL => INSEL,
        MUXOUT => REG_IN
    );

    -------------------------------
    -- Internal Wiring, Addressing and Zero Detection logic

    -- Register Address Controls
    -- Channel A selection is simply OPA
    AOUT_SEL <= OPA;

    -- Channel B selection depends on the RBSEL signal and is either OPB or OPC
    BOUT_SEL <= OPB when RBSEL = '0' else OPC;

    -- Register Write selection depends on WERF, OPC is WERF is selected, Register 0 if not
    WR_SEL <= OPC when WERF = '1' else "000"; -- if WERF is not set, "write" to Register 0

    -- Register File Outputs (for CPU)
    AOUT <= AOUT_INT;
    BOUT <= BOUT_INT;
    AZERO <= '1' when AOUT_INT = ZEROS else '0';   -- zero detect output

    -- Other Outputs (for LEDs)
    SEL_INPUT <= REG_IN;
    SEL_A     <= AREG_SEL;
    SEL_B     <= BREG_SEL;
    SEL_W     <= WREG_SEL;
    REG_DATA  <= REGS_OUT;
    
    -------------------------------
    -- Entity Instantiation
    -- Decoders
    WREG_CTRL: entity work.DECODE3_8 port map ( -- Register Write Select
        DECIN => WR_SEL,
        OUTS  => WREG_SEL
    );

    AREG_CTRL: entity work.DECODE3_8 port map ( -- Register A Select
        DECIN => AOUT_SEL,
        OUTS  => AREG_SEL
    );

    BREG_CTRL: entity work.DECODE3_8 port map ( -- Register B Select
        DECIN => BOUT_SEL,
        OUTS  => BREG_SEL
    );

    -- Registers
    REGISTERS: for r in 1 to 7 generate   -- generate the 7 registers
    begin
        RX : entity work.REG_LE generic map(BIT_DEPTH) port map (  -- Registers
            RESET => RESET,
               EN => CLK_EN,
              CLK => CLK,
               LE => WREG_SEL(r),
                D => REG_IN,
                Q => REGS_OUT(r)
        );
    end generate REGISTERS;

    -- Register Output B
    REGOUT_B: entity work.MUX8 generic map(BIT_DEPTH) port map (   -- Register Channel B Output
        IN7 => REGS_OUT(7),
        IN6 => REGS_OUT(6),
        IN5 => REGS_OUT(5),
        IN4 => REGS_OUT(4),
        IN3 => REGS_OUT(3),
        IN2 => REGS_OUT(2),
        IN1 => REGS_OUT(1),
        IN0 => (others => '0'),     -- Register 0 is always 0
        SEL => BOUT_SEL,
        MUXOUT => BOUT_INT
    );

        -- Register Output A
    REGOUT_A: entity work.MUX8 generic map(BIT_DEPTH) port map (   -- Register Channel A Output
        IN7 => REGS_OUT(7),
        IN6 => REGS_OUT(6),
        IN5 => REGS_OUT(5),
        IN4 => REGS_OUT(4),
        IN3 => REGS_OUT(3),
        IN2 => REGS_OUT(2),
        IN1 => REGS_OUT(1),
        IN0 => (others => '0'),     -- Register 0 is always 0
        SEL => AOUT_SEL,
        MUXOUT => AOUT_INT
    );

end RTL;
