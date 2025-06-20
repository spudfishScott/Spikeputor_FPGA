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

-- All data is 16 bits wide (Defined in BIT_DEPTH). 
-- Register controls are 3 bits wide. Input select is 2 bits wide.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity REG_FILE is
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
end REG_FILE;

architecture RTL of REG_FILE is
    type RARRAY is array(1 to 7) of std_logic_vector(15 downto 0); -- define an array type of 7 registers

    -- internal signals
    signal REG_IN : std_logic_vector(15 downto 0);
    signal B_DECIN, W_DECIN : std_logic_vector(2 downto 0);
    signal AOUT_SEL, BOUT_SEL : std_logic_vector(2 downto 0); 
    signal WREG_SEL : std_logic_vector(7 downto 0);
    signal AOUT_INT : std_logic_vector(15 downto 0);
    signal REGS_OUT : RARRAY;

begin   -- architecture begin

    -- Handle Register Inputs
    REG_INS : entity work.MUX3 generic map(BIT_DEPTH) port map (
           IN2 => IN2,
           IN1 => IN1,
           IN0 => IN0,
           SEL => INSEL,
        MUXOUT => REG_IN
    );

    -- Handle Register Address Controls
    -- Channel A selection is simply OPA
    AOUT_SEL <= OPA;

    -- Channel B selection depends on the RBSEL signal and is either OPB or OPC
    BOUT_SEL <= OPB when RBSEL = '0' else OPC;

    -- Register Write selection depends on WERF, OPC is WERF is selected, Register 0 if not
    W_DECIN <= OPC when WERF = '1' else "000"; -- if WERF is not set, "write" to Register 0

    WREG_CTRL: entity work.DECODE3_8 port map ( -- Register Write Select
        DECIN => W_DECIN,
        OUTS  => WREG_SEL
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
        MUXOUT => BOUT
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

    AOUT <= AOUT_INT;
    AZERO <= '1' when AOUT_INT = "0000000000000000" else '0';   -- zero detect output

end RTL;
