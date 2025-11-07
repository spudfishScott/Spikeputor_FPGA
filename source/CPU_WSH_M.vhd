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
        SEGMENT   : in  std_logic_vector(7 downto 0);   -- SEGMENT register to supply M_TGA_O
        BANK_SEL  : in  std_logic_vector(1 downto 0);   -- BANK_SEL vector for DotStar output

        -- Memory interface
        M_DATA_I  : in  std_logic_vector(15 downto 0);
        M_ACK_I   : in  std_logic;

        M_DATA_O  : out std_logic_vector(15 downto 0);
        M_ADDR_O  : out std_logic_vector(15 downto 0);
        M_CYC_O   : out std_logic;
        M_STB_O   : out std_logic;
        M_WE_O    : out std_logic;
        M_TGA_O   : out std_logic;

        -- Direct Display Values
        INST_DISP       : out std_logic_vector(15 downto 0);
        CONST_DISP      : out std_logic_vector(15 downto 0);
        MDATA_DISP      : out std_logic_vector(16 downto 0);
        PC_DISP         : out std_logic_vector(16 downto 0);
        ALU_DISP        : out std_logic_vector(15 downto 0);
        ALU_CMP_DISP    : out std_logic_vector(6 downto 0);
        ALU_SHIFT_DISP  : out std_logic_vector(18 downto 0);
        ALU_BOOL_DISP   : out std_logic_vector(20 downto 0);
        ALU_ARITH_DISP  : out std_logic_vector(17 downto 0);
        ALU_A_DISP      : out std_logic_vector(16 downto 0);
        ALU_B_DISP      : out std_logic_vector(16 downto 0);
        REGB_OUT_DISP   : out std_logic_vector(15 downto 0);
        REGA_OUT_DISP   : out std_logic_vector(16 downto 0);
        REG1_DISP       : out std_logic_vector(18 downto 0);
        REG2_DISP       : out std_logic_vector(18 downto 0);
        REG3_DISP       : out std_logic_vector(18 downto 0);
        REG4_DISP       : out std_logic_vector(18 downto 0);
        REG5_DISP       : out std_logic_vector(18 downto 0);
        REG6_DISP       : out std_logic_vector(18 downto 0);
        REG7_DISP       : out std_logic_vector(18 downto 0);
        REGIN_DISP      : out std_logic_vector(17 downto 0)
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

    -- Special Registers
    signal const_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal inst_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal pcinc_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal mrdata_out : std_logic_vector(15 downto 0) := (others => '0');

    -- ALU control signals
    signal alufn_out : std_logic_vector(4 downto 0) := (others => '0');
    signal asel_out  : std_logic := '0';
    signal bsel_out  : std_logic := '0';

    -- ALU output
    signal s_alu_out : std_logic_vector(15 downto 0) := (others => '0');

    -- Regsiter File outputs
    signal rega_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal azero_out : std_logic := '0';
    signal regb_out  : std_logic_vector(15 downto 0) := (others => '0');

    -- Signals for display only
    signal mdata_sig      : std_logic_vector(15 downto 0) := (others => '0');   -- to display the read or write memory data
    signal pc_disp_sig    : std_logic_vector(15 downto 0) := (others => '0');   -- to display the program counter
    signal jt_sig         : std_logic := '0';

    signal alu_fnleds     : std_logic_vector(12 downto 0) := (others => '0');   -- to display ALU function control signals incld. ASEL/BSEL
    signal alu_cmpf       : std_logic_vector(3 downto 0) := (others => '0');    -- to display ALU compare flags - 4 bits: Z, V, N, CMP result
    signal alu_shift_sig  : std_logic_vector(15 downto 0) := (others => '0');   -- to display shift result
    signal alu_bool_sig   : std_logic_vector(15 downto 0) := (others => '0');   -- to display the bool result
    signal alu_arith_sig  : std_logic_vector(15 downto 0) := (others => '0');   -- to display the arith result
    signal alua_sig       : std_logic_vector(15 downto 0) := (others => '0');   -- to display the alu a input
    signal alub_sig       : std_logic_vector(15 downto 0) := (others => '0');   -- to display the alu b input

    signal allregs_sig    : RARRAY := (others => (others => '0'));              -- to display the registers
    signal regin_sig      : std_logic_vector(15 downto 0) := (others => '0');   -- to display the register input
    signal reg_a_addr     : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register addresses (Chan A)
    signal reg_b_addr     : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register addresses (Chan B)
    signal reg_w_addr     : std_logic_vector(15 downto 0) := (others => '0');   -- received register Channel to write
    signal reg_w_disp     : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register Channel to write
	 
begin

    -- wire internal signals to display outputs
    INST_DISP       <= inst_out;
    CONST_DISP      <= const_out;
    MDATA_DISP      <= rbsel_out & mdata_sig;
    PC_DISP         <= jt_sig & pc_disp_sig;
    RBSEL_DISP      <= rbsel_out;

    ALU_DISP        <= s_alu_out;
    ALU_CMP_DISP    <= alu_fnleds(6 downto 5) & alu_cmpf & alu_fnleds(7);
    ALU_SHIFT_DISP  <= alu_fnleds(8) & alu_fnleds(9) & alu_shift_sig & alu_fnleds(10);
    ALU_BOOL_DISP   <= alu_fnleds(3 downto 0) & alu_bool_sig & alu_fnleds(4);
    ALU_ARITH_DISP  <= alu_fnleds(11) & alu_arith_sig & alu_fnleds(12);
    ALU_A_DISP      <= asel_out & alua_sig;
    ALU_B_DISP      <= bsel_out & alub_sig;

    REGB_OUT_DISP   <= regb_out;
    REGA_OUT_DISP   <= azero_out & rega_out;
    REG1_DISP       <= reg_a_addr(1) & reg_b_addr(1) & reg_w_disp(1) & allregs_sig(1);
    REG2_DISP       <= reg_a_addr(2) & reg_b_addr(2) & reg_w_disp(2) & allregs_sig(2);
    REG3_DISP       <= reg_a_addr(3) & reg_b_addr(3) & reg_w_disp(3) & allregs_sig(3);
    REG4_DISP       <= reg_a_addr(4) & reg_b_addr(4) & reg_w_disp(4) & allregs_sig(4);
    REG5_DISP       <= reg_a_addr(5) & reg_b_addr(5) & reg_w_disp(5) & allregs_sig(5);
    REG6_DISP       <= reg_a_addr(6) & reg_b_addr(6) & reg_w_disp(6) & allregs_sig(6);
    REG7_DISP       <= reg_a_addr(7) & reg_b_addr(7) & reg_w_disp(7) & allregs_sig(7);
    REGIN_DISP      <= wdsel_out & regin_sig;

    mdata_sig       <= mrdata_out when rbsel_out = '0' else regb_out;       -- get mdata from memory read or write (rbsel = 1 on ST commands only)

    jt_sig          <= '1' when ((inst_out(9) = '1') AND                    -- Calculate value of JT flag (1 = jump, 0 = use pc_inc)
                                 ((inst_out(8 downto 6) = "000") OR                             -- unconditional jump (JMP)
                                  (inst_out(8 downto 6) = "100" AND azero_out = '1') OR         -- branch if equal to zero (BEQ)
                                  (inst_out(8 downto 6) = "101" AND azero_out = '0')))          -- branch if not equal to zero (BNE)
                           else '0';

    reg_w_disp <= reg_w_addr when rbsel_out = '0' else (others => '0'); -- display register write unless rbsel is 1

     -- Control Logic Instance
    CTRL : entity work.CTRL_WSH_M port map (
        -- SYSCON inputs
        CLK         => CLK,
        RST_I       => RESET,
        STALL_I     => STALL,

        -- Wishbone signals for memory interface
        -- Handshaking signals
        WBS_CYC_O   => M_CYC_O,
        WBS_STB_O   => M_STB_O,
        WBS_ACK_I   => M_ACK_I,

        -- Memory read/write signals
        WBS_ADDR_O  => M_ADDR_O, -- address output from master, input to providers
        WBS_DATA_O  => M_DATA_O, -- data output from master, input to providers
        WBS_DATA_I  => M_DATA_I, -- data input to master, output from providers
        WBS_WE_O    => M_WE_O,   -- write enable output from master, input to providers
        WBS_TGA_O   => M_TGA_O,  -- tag for whether to use extended address bus from segment register

        -- Internal Spikeputor signals
        -- Data outputs from Control Logic to other modules
        INST        => inst_out,                -- INST output for display only
        CONST       => const_out,               -- CONST output to ALU
        PC          => pc_disp_sig,             -- PC output for display only
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
        Z           => azero_out               -- Zero flag input (from RegFile) to Control Logic
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
        SEL_INPUT   => regin_sig,                -- selected input
        SEL_A       => reg_a_addr(7 downto 0),   -- selected register to output to Channel A
        SEL_B       => reg_b_addr(7 downto 0),   -- selected register to output to Channel B
        SEL_W       => reg_w_addr(7 downto 0),   -- selected register Channel to write
        REG_DATA    => allregs_sig               -- all 7 RegFile registers
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
        A           => alua_sig,
        B           => alub_sig,
        SHIFT       => alu_shift_sig,
        ARITH       => alu_arith_sig,
        BOOL        => alu_bool_sig,
        CMP_FLAGS   => alu_cmpf,
        ALU_FN_LEDS => alu_fnleds
    );

end Behavioral;