-- Spikeputor Register File
-- Inputs:
--     Asynchronous RESET to clear all registers
--     Three Data Inputs 
--     Three Register Controls (Rega, RegB, RegC) from the opcode 
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
    port (
        RESET : in std_logic;
        IN0, IN1, IN2 : in std_logic_vector(15 downto 0);
        CLK, CLK_EN : in std_logic;
        INSEL : in std_logic_vector(1 downto 0);
        REGA, REGB, REGC : in std_logic_vector(2 downto 0);
        WERF, RBSEL : in std_logic;

        AOUT : out std_logic_vector(15 downto 0);
        BOUT : out std_logic_vector(15 downto 0);
        AZERO : out std_logic
    );
end REG_FILE;

architecture RTL of REG_FILE is
    type RARRAY is array(1 to 7) of std_logic_vector(15 downto 0); -- define a an array type of 7 registers
--    constant BIT_DEPTH : Integer := 16;

    -- component definitions
    -- MUX3 - need one to select REG_IN
    component MUX3 is
        generic (n: positive); -- width of in/out signals

        port (
            IN2 : in std_logic_vector(n-1 downto 0); -- input 2
            IN1 : in std_logic_vector(n-1 downto 0); -- input 1
            IN0 : in std_logic_vector(n-1 downto 0); -- input 0
            SEL : in std_logic_vector(1 downto 0); -- selection
            MUXOUT : out std_logic_vector(n-1 downto 0) -- output
        );
    end component;

    -- Decoder3_8 - need three to select AOUT, BOUT and WREG
    component DECODE3_8 is
        port (
            DECIN : in std_logic_vector(2 downto 0); -- decoder input
            OUTS : out std_logic_vector(7 downto 0) -- decoded output signal
        );
    end component;

    -- REG_LE - need 7 of these plus logic for one "always zero" register
    component REG_LE is
        generic (n: positive); -- width of register

        port (
            RESET, EN, CLK, LE : in std_logic; -- reset, clock enable, clock, latch enable 
            D : in std_logic_vector(n-1 downto 0);	-- input
            Q : out std_logic_vector(n-1 downto 0)	-- output channel A
        );
    end component;

    -- end components

    -- internal signals
    signal REG_IN : std_logic_vector(15 downto 0);
    signal B_DECIN, W_DECIN : std_logic_vector(2 downto 0);
    signal AOUT_SEL, BOUT_SEL, WREG_SEL : std_logic_vector(7 downto 0);
    signal REGS_OUT : RARRAY;

    -- MUX8 - need one for the 8 register outputs
    component MUX8 is
        generic (n: positive); -- width of in/out signals

        port (
            IN7 : in std_logic_vector(n-1 downto 0); -- input 7
            IN6 : in std_logic_vector(n-1 downto 0); -- input 6
            IN5 : in std_logic_vector(n-1 downto 0); -- input 5
            IN4 : in std_logic_vector(n-1 downto 0); -- input 4
            IN3 : in std_logic_vector(n-1 downto 0); -- input 3
            IN2 : in std_logic_vector(n-1 downto 0); -- input 2
            IN1 : in std_logic_vector(n-1 downto 0); -- input 1
            IN0 : in std_logic_vector(n-1 downto 0); -- input 0
            SEL : in std_logic_vector(2 downto 0);   -- selection
            MUXOUT : out std_logic_vector(n-1 downto 0) -- selected output
        );
    end component;

begin   -- architecture begin

    -- Handle Register Inputs
    REG_INS : MUX3 generic map(16) port map (
           IN2 => IN2,
           IN1 => IN1,
           IN0 => IN0,
           SEL => INSEL,
        MUXOUT => REG_IN
    );

    -- Handle Register Address Controls
    -- Channel A selection is simply REGA
    AOUT_CTRL: DECODE3_8 port map (  -- Channel A Register Select
        DECIN => REGA,
        OUTS  => AOUT_SEL
    );

    -- Channel B selection depends on the RBSEL signal and is either REGB or REGC
    B_DECIN <= REGB when RBSEL = '0' else REGC;
    BOUT_CTRL: DECODE3_8 port map (  -- Channel B Register Select
        DECIN => B_DECIN,
        OUTS  => BOUT_SEL
    );

    -- Register Write selection depends on WERF, REGC is WERF is selected, Register 0 if not
    W_DECIN <= REGC when WERF = '1' else "000"; -- if WERF is not set, "write" to Register 0
    WREG_CTRL: DECODE3_8 port map ( -- Register Write Select
        DECIN => W_DECIN,
        OUTS  => WREG_SEL
    );

    -- Registers
    REGISTERS: for r in (1 to 7) generate   -- generate the 7 registers
    begin
        RX : REG_LE generic map(16) port map (  -- Registers
            RESET => RESET,
               EN => CLK_EN,
              CLK => CLK,
               LE => WREG_SEL(r),
                D => REG_IN,
                Q => REGS_OUT(r)
        );
    end generate REGISTERS;

    -- Register Output A
    REGOUT_A: MUX8 generic map(16) port map (   -- Register Channel A Output
        IN7 => REGS_OUT(7),
        IN6 => REGS_OUT(6),
        IN5 => REGS_OUT(5),
        IN4 => REGS_OUT(4),
        IN3 => REGS_OUT(3),
        IN2 => REGS_OUT(2),
        IN1 => REGS_OUT(1),
        IN0 => (others => '0'),     -- Register 0 is always 0
        SEL => AOUT_SEL,
        MUXOUT => AOUT
    );

    AZERO <= '1' when AOUT = (others => '0') else '0';   -- zero detect output

    -- Register Output B
    REGOUT_B: MUX8 generic map(16) port map (   -- Register Channel B Output
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

end RTL;
