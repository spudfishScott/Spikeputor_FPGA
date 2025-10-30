library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity CPU_WSH_M is
    port (
        -- Timing
        CLK       : in  std_logic;      -- System clock
        RESET     : in  std_logic;      -- System reset
        STALL     : in  std_logic;      -- CPU stall signal for debugging

        -- Memory interface
        M_DATA_I  : in  std_logic_vector(15 downto 0);
        M_ACK_I   : in  std_logic;

        M_DATA_O  : out std_logic_vector(15 downto 0);
        M_ADDR_O  : out std_logic_vector(15 downto 0);
        M_CYC_O   : out std_logic;
        M_STB_O   : out std_logic;
        M_WE_O    : out std_logic;

        -- Display interface - maybe this should go in the top level module instead
        DISP_DATA : out std_logic;      -- DotStar data line
        DISP_CLK  : out std_logic;      -- DotStar clock line

        -- Direct Display Values (temporary - will eventually all be DotStar ouput)
        INST_DISP       : out std_logic_vector(15 downto 0); -- 1 [16]
        CONST_DISP      : out std_logic_vector(15 downto 0);
        MDATA_DISP     : out std_logic_vector(15 downto 0); -- memory data read or to write
        PC_DISP         : out std_logic_vector(15 downto 0); -- 4 [16]
        JT              : out std_logic;
        REGSTAT_DISP    : out std_logic_vector(15 downto 0); -- 5 [11 or 13 depending on WDSEL inclusion]
        WDINPUT_DISP    : out std_logic_vector(15 downto 0); -- 6 [16 or 18 depending on WDSEL inclusion]
        REGS_DISP       : out RARRAY;                        -- 7-13 [7x19 including a, b, w signals]
        REGA_DISP       : out std_logic_vector(15 downto 0);
        REGB_DISP       : out std_logic_vector(15 downto 0);
        ALU_FNLEDS_DISP : out std_logic_vector(15 downto 0); -- 16 [15 or 17 depending on ASEL/BSEL 1 bit or 2 bit signals]
        ALUA_DISP       : out std_logic_vector(15 downto 0); -- 17 [16]
        ALUB_DISP       : out std_logic_vector(15 downto 0); -- 18 [16]
        ALUARITH_DISP   : out std_logic_vector(15 downto 0); -- 19 [16]
        ALUBOOL_DISP    : out std_logic_vector(15 downto 0); -- 20 [16]
        ALUSHIFT_DISP   : out std_logic_vector(15 downto 0); -- 21 [16]
        ALUCMPF_DISP    : out std_logic_vector(15 downto 0);
        ALUOUT_DISP     : out std_logic_vector(15 downto 0);
        PHASE_DISP      : out std_logic_vector(2 downto 0)  -- 24 [2] - or maybe this, clock, and bank select are separate LEDs?
    );
end CPU_WSH_M;

architecture Behavioral of CPU_WSH_M is
    -- Register File control signals
    signal werf_out  : std_logic := '0';
    signal rbsel_out : std_logic := '0';
    signal wdsel_out : std_logic_vector(1 downto 0) := (others => '0');
    signal opa_out   : std_logic_vector(2 downto 0) := (others => '0');
    signal opb_out   : std_logic_vector(2 downto 0) := (others => '0');
    signal opc_out   : std_logic_vector(2 downto 0) := (others => '0');

    -- Special Registers                                                            -- number of LED group for dotstar module [bits]
    signal const_out  : std_logic_vector(15 downto 0) := (others => '0');           -- 2 [16]
    signal inst_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal pcinc_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal mrdata_out : std_logic_vector(15 downto 0) := (others => '0');           -- 3 [16]

    -- ALU control signals
    signal alufn_out : std_logic_vector(4 downto 0) := (others => '0');
    signal asel_out  : std_logic := '0';
    signal bsel_out  : std_logic := '0';

    -- ALU output
    signal s_alu_out : std_logic_vector(15 downto 0) := (others => '0');            -- 23 [16]

    -- Regsiter File outputs
    signal rega_out  : std_logic_vector(15 downto 0) := (others => '0');            -- 14 [17]
    signal azero_out : std_logic := '0';                                            -- 14
    signal regb_out  : std_logic_vector(15 downto 0) := (others => '0');            -- 15 [16]

    -- Signals for display only
    signal reg_a_addr  : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register addresses (Chan A) -- 7-13 [19]
    signal reg_b_addr  : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register addresses (Chan B) -- 7-13
    signal reg_w_addr  : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register Channel to write   -- 7-13

    signal mdata_disp_sig : std_logic_vector(16 downto 0) := (others => '0');
    signal pc_disp_sig    : std_logic_vector(16 downto 0) := (others => '0');

    signal alu_fnleds  : std_logic_vector(12 downto 0) := (others => '0');   -- to display ALU function control signals incld. ASEL/BSEL  -- 16 [15 or 17, depending on whether ASEL/BSEL get 2 LEDs each]
    signal alu_cmpf    : std_logic_vector(3 downto 0) := (others => '0');    -- to display ALU compare flags - 4 bits: Z, V, N, CMP result -- 22 [4]

    signal refresh     : std_logic := '0';                                   -- signal to start the DotStar LED refresh process
    signal led_busy    : std_logic := '0';                                   -- the dotstar interface is busy with an update
    signal cyc_sig     : std_logic := '0';                                   -- wishone cycle signal from cpu

begin

    -- wire internal signals to display outputs
    INST_DISP       <= inst_out;
    CONST_DISP      <= const_out;
    MDATA_DISP      <= mdata_disp_sign(16 downto 1);
    PC_DISP         <= pc_disp_sig(16 downto 1);
    pc_disp_sig(0)  <= '1' when ((inst_out(9) = '1') AND                     -- check to see if the branch should be taken
                                 ((inst_out(8 downto 6) = "000") OR                    -- unconditional jump (JMP)
                                  (inst_out(8 downto 6) = "100" AND azero_out = '1') OR         -- branch if equal to zero (BEQ)
                                  (inst_out(8 downto 6) = "101" AND azero_out = '0')))          -- branch if not equal to zero (BNE)
                           else '0';

    mdata_disp_sig  <= (mrdata_out & "0") when rbsel_out = '0' else (regb_out & "1");
    REGSTAT_DISP    <= opa_out & opb_out & opc_out & "0" & werf_out & rbsel_out & wdsel_out & "0" & azero_out;    -- to display regfile controls/Z
    REGA_DISP       <= rega_out;
    REGB_DISP       <= regb_out;
    ALUCMPF_DISP    <= alu_cmpf & "000000000000";  -- pad to 16 bits
    ALUOUT_DISP     <= s_alu_out;
    ALU_FNLEDS_DISP <= asel_out & alu_fnleds & bsel_out & "0";  -- pad to 16 bits
    JT              <= '1' when ((inst_out(9) = '1') AND                     -- check to see if the branch should be taken
                                 ((inst_out(8 downto 6) = "000") OR                    -- unconditional jump (JMP)
                                  (inst_out(8 downto 6) = "100" AND azero_out = '1') OR         -- branch if equal to zero (BEQ)
                                  (inst_out(8 downto 6) = "101" AND azero_out = '0')))          -- branch if not equal to zero (BNE)
                           else '0';

    M_CYC_O         <= cyc_sig;
    
    process(cyc_sig) is
    begin
        if falling_edge(cyc_sig) then   -- only update DotStar LEDs at the end of a CPU cycle and if DotStar is not busy
            refresh <= not led_busy;
        else
            refresh <= '0';
        end if;
    end process;

    DOTSTAR : entity work.dotstar_driver generic map ( XMIT_QUANTA => 1 )
    port map (
        CLK         => CLK,
        START       => refresh,

        INST        => inst_out,
        CONST       => const_out,
        MDATA       => mdata_disp_sig,
        PC          => pc_disp_sig,

        DATA_OUT    => DISP_DATA,
        CLOCK_OUT   => DISP_CLK,
        BUSY        => led_busy
    );

     -- Control Logic Instance
    CTRL : entity work.CTRL_WSH_M port map (
        -- SYSCON inputs
        CLK         => CLK,
        RST_I       => RESET,
        STALL_I     => STALL,

        -- Wishbone signals for memory interface
        -- Handshaking signals
        WBS_CYC_O   => cyc_sig,
        WBS_STB_O   => M_STB_O,
        WBS_ACK_I   => M_ACK_I,

        -- Memory read/write signals
        WBS_ADDR_O  => M_ADDR_O, -- address output from master, input to providers
        WBS_DATA_O  => M_DATA_O, -- data output from master, input to providers
        WBS_DATA_I  => M_DATA_I, -- data input to master, output from providers
        WBS_WE_O    => M_WE_O,   -- write enable output from master, input to providers

        -- Internal Spikeputor signals
        -- Data outputs from Control Logic to other modules
        INST        => inst_out,                -- INST output for display only
        CONST       => const_out,               -- CONST output to ALU
        PC          => pc_disp_sig(16 downto 1),-- PC output for display only
        PC_INC      => pcinc_out,               -- PC+2 output to ALU and REG_FILE
        MRDATA      => mrdata_out,              -- MEM output to REG_FILE
        -- Control signals from Control Logic to other modules
        WERF        => werf_out,                -- WERF output to REG_FILE
        RBSEL       => rbsel_out,               -- RBSEL output to REG_FILE
        WDSEL       => wdsel_out,               -- WDSEL output to REG_FILE
        OPA         => opa_out,                 -- OPA output to REG_FILE
        OPB         => opb_out,                 -- OPB output to REG_FILE
        OPC         => opc_out,                 -- OPC output to REG_FILE
        ALUFN       => alufn_out,               -- ALUFN output to ALU
        ASEL        => asel_out,                -- ASEL output to ALU
        BSEL        => bsel_out,                -- BSEL output to ALU
        -- Inputs to Control Logic from other modules
        ALU_OUT     => s_alu_out,               -- ALU output to Control Logic
        MWDATA      => regb_out,                -- RegFile Channel B input to Control Logic for memory writing
        Z           => azero_out,               -- Zero flag input (from RegFile) to Control Logic

        PHASE       => PHASE_DISP               -- PHASE output for display only
    );

    -- RegFile Instance
    REGFILE : entity work.REG_FILE port map (
        -- register file inputs
        CLK         => CLK,             -- system clock
        IN0         => pcinc_out,       -- Register Input: PC + 2
        IN1         => s_alu_out,       -- Register Input: ALU output
        IN2         => mrdata_out,      -- Register Input: Memory Read Data
        WDSEL       => wdsel_out,       -- WDSEL from Control Logic
        OPA         => opa_out,         -- OPA from INST
        OPB         => opb_out,         -- OPB from INST
        OPC         => opc_out,         -- OPC from INST
        WERF        => werf_out,        -- WERF from Control Logic
        RBSEL       => rbsel_out,       -- RBSEL from Control Logic

        -- register file outputs for CPU (also will drive LEDs)
        AOUT        => rega_out,        -- Channel A output to ALU and Control Logic
        BOUT        => regb_out,        -- Channel B output to ALU
        AZERO       => azero_out,       -- Zero flag output to Control Logic

        -- outputs to drive LEDs only
        SEL_INPUT   => WDINPUT_DISP,             -- selected input
        SEL_A       => reg_a_addr(7 downto 0),   -- selected register to output to Channel A - not used now but will be added for DotStar output of each register
        SEL_B       => reg_b_addr(7 downto 0),   -- selected register to output to Channel B - not used now but will be added for DotStar output of each register
        SEL_W       => reg_w_addr(7 downto 0),   -- selected register Channel to write - not used now but will be added for DotStar output of each register
        REG_DATA    => REGS_DISP                 -- all 7 RegFile registers
    );

    -- ALU Instance
    ALU : entity work.ALU port map (
        -- ALU inputs
        ALUFN       => alufn_out,
        ASEL        => asel_out,
        BSEL        => bsel_out,
        REGA        => rega_out,
        PC_INC      => pcinc_out,
        REGB        => regb_out,
        CONST       => const_out,

        -- ALU output
        ALUOUT      => s_alu_out,

        -- outputs to drive LEDs only
        A           => ALUA_DISP,
        B           => ALUB_DISP,
        SHIFT       => ALUSHIFT_DISP,
        ARITH       => ALUARITH_DISP,
        BOOL        => ALUBOOL_DISP,
        CMP_FLAGS   => alu_cmpf,
        ALU_FN_LEDS => alu_fnleds
    );

end Behavioral;