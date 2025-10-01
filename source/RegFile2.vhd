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
-- Register controls are 3 bits wide (for 8 registers). Input select is 2 bits wide for 3 inputs => 

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
        WDSEL         : in std_logic_vector(1 downto 0);
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
    signal AZERO_INT : std_logic := '0';

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

     -- Register File Outputs (for CPU)
    AOUT <= AOUT_INT;
    BOUT <= BOUT_INT;
    AZERO <= AZERO_INT;

    process(CLK)
    begin
        -- everything happens on rising edge of clock now - see how much of this can be moved back to combinational logic
        if rising_edge(CLK) then
            if RESET = '1' then
                REG_IN <= (others => '0');  -- reset input register, but keep register values and zero flag
            else
                -- Handle Zero Detection
                if AOUT_INT = ZEROS 
                    then AZERO <= '1';
                else
                    AZERO <= '0';
                end if;

                -- Handle Register Inputs
                case WDSEL is
                    when "00" => REG_IN <= IN0;     -- select IN0
                    when "01" => REG_IN <= IN1;     -- select IN1
                    when others => REG_IN <= IN2;   -- select IN2
                end case;

                -- Handle Register Writes
                if CLK_EN = '1' AND WERF = '1' then
                    case OPC is
                        when "111" => REGS_OUT(7) <= REG_IN;  -- write to R7
                        when "110" => REGS_OUT(6) <= REG_IN;  -- write to R6
                        when "101" => REGS_OUT(5) <= REG_IN;  -- write to R5
                        when "100" => REGS_OUT(4) <= REG_IN;  -- write to R4
                        when "011" => REGS_OUT(3) <= REG_IN;  -- write to R3
                        when "010" => REGS_OUT(2) <= REG_IN;  -- write to R2
                        when "001" => REGS_OUT(1) <= REG_IN;  -- write to R1
                        when others => null;                  -- do not write to R0 (always zero)
                    end case;
                end if;

                -- Handle Register Outputs
                -- Register Output A
                case OPA is
                    when "111" => AOUT_INT <= REGS_OUT(7);  -- select R7
                    when "110" => AOUT_INT <= REGS_OUT(6);  -- select R6
                    when "101" => AOUT_INT <= REGS_OUT(5);  -- select R5
                    when "100" => AOUT_INT <= REGS_OUT(4);  -- select R4
                    when "011" => AOUT_INT <= REGS_OUT(3);  -- select R3
                    when "010" => AOUT_INT <= REGS_OUT(2);  -- select R2
                    when "001" => AOUT_INT <= REGS_OUT(1);  -- select R1
                    when others => AOUT_INT <= (others => '0');     -- R0 is always zero
                end case;
                -- Register Output B
                if RBSEL = '0' then
                    case OPB is
                        when "111" => BOUT_INT <= REGS_OUT(7);  -- select R7
                        when "110" => BOUT_INT <= REGS_OUT(6);  -- select R6
                        when "101" => BOUT_INT <= REGS_OUT(5);  -- select R5
                        when "100" => BOUT_INT <= REGS_OUT(4);  -- select R4
                        when "011" => BOUT_INT <= REGS_OUT(3);  -- select R3
                        when "010" => BOUT_INT <= REGS_OUT(2);  -- select R2
                        when "001" => BOUT_INT <= REGS_OUT(1);  -- select R1
                        when others => BOUT_INT <= (others => '0');     -- R0 is always zero
                    end case;
                else
                    case OPC is
                        when "111" => BOUT_INT <= REGS_OUT(7);  -- select R7
                        when "110" => BOUT_INT <= REGS_OUT(6);  -- select R6
                        when "101" => BOUT_INT <= REGS_OUT(5);  -- select R5
                        when "100" => BOUT_INT <= REGS_OUT(4);  -- select R4
                        when "011" => BOUT_INT <= REGS_OUT(3);  -- select R3
                        when "010" => BOUT_INT <= REGS_OUT(2);  -- select R2
                        when "001" => BOUT_INT <= REGS_OUT(1);  -- select R1
                        when others => BOUT_INT <= (others => '0');     -- R0 is always zero
                    end case;
                end if;
            end if;
        end if;
    end process;

    -------------------------------
    -- Signals to produce LED outputs
    BOUT_SEL <= OPB when RBSEL = '0' else OPC;  -- Register B output selection depends on RBSEL
    WR_SEL <= OPC when WERF = '1' else "000";   -- if WERF is not set, "write" to Register 0

    -- Other Outputs (for LEDs)
    SEL_INPUT <= REG_IN;
    SEL_A     <= AREG_SEL;
    SEL_B     <= BREG_SEL;
    SEL_W     <= WREG_SEL;
    REG_DATA  <= REGS_OUT;
    
    -------------------------------
    -- Decoders for display outputs
    WREG_CTRL: entity work.DECODE3_8 port map ( -- Register Write Select
        DECIN => WR_SEL,
        OUTS  => WREG_SEL
    );

    AREG_CTRL: entity work.DECODE3_8 port map ( -- Register A Select
        DECIN => OPA,--AOUT_SEL,
        OUTS  => AREG_SEL
    );

    BREG_CTRL: entity work.DECODE3_8 port map ( -- Register B Select
        DECIN => BOUT_SEL,
        OUTS  => BREG_SEL
    );

end RTL;
