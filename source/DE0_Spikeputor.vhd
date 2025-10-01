library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.Types.all;

entity DE0_Spikeputor is
    port (
        -- Clock Input
        CLOCK_50 : in std_logic;
        -- Push Button
        BUTTON : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D : out std_logic_vector(6 downto 0);
        HEX0_DP : out std_logic;
        HEX1_D : out std_logic_vector(6 downto 0);
        HEX1_DP : out std_logic;
        HEX2_D : out std_logic_vector(6 downto 0);
        HEX2_DP : out std_logic;
        HEX3_D : out std_logic_vector(6 downto 0);
        HEX3_DP : out std_logic;
        -- LED
        LEDG : out std_logic_vector(9 downto 0)
        -- GPIO
   --     GPIO1_D : out std_logic_vector(31 downto 0)
    );
end DE0_Spikeputor;

architecture Structural of DE0_Spikeputor is
    -- Signal Declarations
    -- Clock selection signal
    signal system_clk : std_logic;

    -- Clock selection attribute - to aid in synthesis
    attribute keep : string;
    attribute keep of system_clk : signal is "true";
    attribute preserve : string;
    attribute preserve of system_clk : signal is "true";

    -- Memory interface signals
    signal cyc    : std_logic := '0';
    signal stb    : std_logic := '0';
    signal ack    : std_logic := '0';
    signal addr   : std_logic_vector(15 downto 0) := (others => '0');
    signal data_o : std_logic_vector(15 downto 0) := (others => '0');
    signal data_i : std_logic_vector(15 downto 0) := (others => '0');
    signal we     : std_logic := '0';

    -- Special Registers
    signal pcinc_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal inst_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal const_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal mrdata_out : std_logic_vector(15 downto 0) := (others => '0');

    -- Register File control signals
    signal werf_out  : std_logic := '0';
    signal rbsel_out : std_logic := '0';
    signal wdsel_out : std_logic_vector(1 downto 0) := (others => '0');
    signal opa_out   : std_logic_vector(2 downto 0) := (others => '0');
    signal opb_out   : std_logic_vector(2 downto 0) := (others => '0');
    signal opc_out   : std_logic_vector(2 downto 0) := (others => '0');

    -- Regsiter File outputs
    signal rega_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal regb_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal azero_out : std_logic := '0';

    -- ALU control signals
    signal alufn_out : std_logic_vector(4 downto 0) := (others => '0');
    signal asel_out  : std_logic := '0';
    signal bsel_out  : std_logic := '0';

    -- ALU output
    signal s_alu_out : std_logic_vector(15 downto 0) := (others => '0');

    -- Signals for display only
    signal pc_out     : std_logic_vector(15 downto 0) := (others => '0');   -- to display current PC value
    signal reg_stat   : std_logic_vector(15 downto 0) := (others => '0');   -- to display regfile controls/Zero flag
    signal alu_ctrl   : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU controls
    signal wd_input   : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected write data input
    signal reg_addr   : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register addresses (Chan A and Chan B)
    signal reg_waddr  : std_logic_vector(15 downto 0) := (others => '0');   -- to display selected register Channel to write
 --   signal reg_index  : integer range 1 to 7 := 1;                          -- to select which register to display
    signal all_regs   : RARRAY := (others => (others => '0'));              -- to display all register contents
    signal alu_a      : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU A input
    signal alu_b      : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU B input
    signal alu_reva   : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU A input reversed
    signal alu_invb   : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU B input inverted
    signal alu_shift  : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU shift output
    signal alu_arith  : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU arithmetic output
    signal alu_bool   : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU boolean output
    signal alu_cmpf   : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU compare flags - 4 bits: Z, V, N, CMP result
    signal alu_shift8 : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU shift by 8 output
    signal alu_shift4 : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU shift by 4 output
    signal alu_shift2 : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU shift by 2 output
    signal alu_shift1 : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU shift by 1 output
    signal alu_fnleds : std_logic_vector(15 downto 0) := (others => '0');   -- to display ALU function control signals - 13 bits

    -- signal to display on 7-seg display
    signal disp_out  : std_logic_vector(15 downto 0) := (others => '0');
    
    begin
    -- Select between automatic and manual clock based on SW(0) - manual clock is Button(1)
    system_clk <= CLOCK_50 when SW(0) = '1' else NOT Button(1);

    -- display PC or PC_INC on 7-seg based on Button(2) - this will change to select other signals later
    disp_out <= pc_out when Button(2) = '1' else pcinc_out;

--    process(Button(2), reg_index) -- increment register index on each press of Button(2)
--    begin
--        if Button(2) = '0' then
--            if reg_index = 7 then
--                reg_index <= 1;
--            else
--                reg_index <= reg_index + 1;
--            end if;
--        end if;
--    end process;

--    LEDG(9 downto 7) <= std_logic_vector(to_unsigned(reg_index, 3));  -- display current register index on LEDG(9:7)

--
--    WITH (SW(9 downto 7)) SELECT
--        GPIO1_D(31 downto 16) <= inst_out   WHEN "000",        -- INST output
--                                 const_out  WHEN "001",        -- CONST output
--                                 rega_out   WHEN "010",        -- RegFile Channel A
--                                 regb_out   WHEN "011",        -- RegFile Channel B
--                                 mrdata_out WHEN "100",        -- MRDATA output
--                                 reg_stat   WHEN "101",        -- RegFile control signals and Zero flag
--                                 wd_input   WHEN "110",        -- RegFile selected write data
--                                 all_regs(1) WHEN "111",   -- register at current index (1 to 7)
--                                 inst_out   WHEN others;       -- INST output (should never happen)
--
--    WITH (SW(4 downto 2)) SELECT
--        GPIO1_D(15 downto 0)  <= s_alu_out  WHEN "000",        -- ALU Output
--                                 alu_shift  WHEN "001",        -- ALU shift by 8 output
--                                 alu_arith  WHEN "010",        -- ALU arithmetic output
--                                 alu_bool   WHEN "011",        -- ALU boolean output
--                                 alu_cmpf   WHEN "100",        -- ALU compare flags
--                                 alu_a   WHEN "101",           -- ALU A input
--                                 alu_b   WHEN "110",           -- ALU B input
--                                 alu_ctrl WHEN "111",          -- ALU function control signals
--                                 s_alu_out  WHEN others;       -- ALU output (should never happen)

    -- set up internal display signals
    reg_stat <= opa_out & opb_out & opc_out & "0" & werf_out & rbsel_out & wdsel_out & "0" & azero_out;   -- to display regfile controls/Z
    alu_ctrl <= asel_out & "00000" & alufn_out & "0000" & bsel_out;                                       -- to display ALU controls

    -- Control Logic Instance
    CTRL : entity work.CTRL_WSH_M port map (
        -- SYSCON inputs
        CLK         => system_clk,
        RST_I       => NOT Button(0), -- Button 0 is reset button

        -- Wishbone signals for memory interface
        -- handshaking signals
        WBS_CYC_O   => cyc,
        WBS_STB_O   => stb,
        WBS_ACK_I   => ack,

        -- memory read/write signals
        WBS_ADDR_O  => addr,
        WBS_DATA_O  => data_o, -- output from master, input to provider
        WBS_DATA_I  => data_i, -- input to master, output from provider
        WBS_WE_O    => we,

        -- Spikeputor Signals
        -- Data outputs from Control Logic to other modules
        INST        => inst_out,                -- INST output for display only
        CONST       => const_out,               -- CONST output to ALU
        PC          => pc_out,                  -- PC output for display only
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
        MWDATA      => rega_out,                -- RegFile Channel A input to Control Logic for memory writing
        Z           => azero_out,               -- Zero flag input (from RegFile) to Control Logic

        PHASE       => LEDG(1 downto 0)         -- PHASE output to LEDG(1:0) for display only
    );

    -- RAM Instance
    RAM : entity work.RAMTest_WSH_P port map (  -- use test RAM to execute a simple program
        -- SYSCON inputs
        CLK         => system_clk,
        RST_I       => NOT Button(0), -- Button 0 is reset button

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   => cyc,
        WBS_STB_I   => stb,
        WBS_ACK_O   => ack,

        -- memory read/write signals
        WBS_ADDR_I  => addr,
        WBS_DATA_O  => data_i,
        WBS_DATA_I  => data_o,
        WBS_WE_I    => we       
    );

    -- RegFile Instance
    REGFILE : entity work.REG_FILE port map (
        -- register file inputs
        RESET       => NOT Button(0),   -- Button 0 is reset button
        CLK         => system_clk,      -- system clock
        CLK_EN      => '1',             -- always enabled for now
        IN0         => X"F00D", --pcinc_out,       -- PC + 2
        IN1         => X"DEAD",--s_alu_out,       -- ALU output
        IN2         => X"B0D1", --mrdata_out,      -- Memory Read Data
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
        SEL_INPUT   => wd_input,                -- selected input
        SEL_A       => reg_addr(15 downto 8),   -- selected register to output to Channel A
        SEL_B       => reg_addr(7 downto 0),    -- selected register to output to Channel B
        SEL_W       => reg_waddr(7 downto 0),   -- selected register Channel to write
        REG_DATA    => all_regs                 -- all 7 RegFile registers
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
        A           => alu_a,
        B           => alu_b,
        REV_A       => alu_reva,
        INV_B       => alu_invb,
        SHIFT       => alu_shift,
        ARITH       => alu_arith,
        BOOL        => alu_bool,
        SHIFT8      => alu_shift8,
        SHIFT4      => alu_shift4,
        SHIFT2      => alu_shift2,
        SHIFT1      => alu_shift1,
        CMP_FLAGS   => alu_cmpf(3 downto 0),
        ALU_FN_LEDS => alu_fnleds(12 downto 0)
    );

      -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => disp_out,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

-- Set default output states

-- 7-SEG Display
HEX0_DP <= '1';
HEX1_DP <= '1';
HEX2_DP <= '1';
HEX3_DP <= '1';

-- LED
LEDG(9 downto 2) <= (others => '0');

end Structural;
