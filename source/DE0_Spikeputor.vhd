library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.Types.all;

entity DE0_Spikeputor is
    port (
        -- Clock Input
        CLOCK_50 : in std_logic;
        -- Push Button
        BUTTON   : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D   : out std_logic_vector(6 downto 0);
        HEX0_DP  : out std_logic;
        HEX1_D   : out std_logic_vector(6 downto 0);
        HEX1_DP  : out std_logic;
        HEX2_D   : out std_logic_vector(6 downto 0);
        HEX2_DP  : out std_logic;
        HEX3_D   : out std_logic_vector(6 downto 0);
        HEX3_DP  : out std_logic;
        -- LED
        LEDG     : out std_logic_vector(9 downto 0);
        -- GPIO
        GPIO1_D  : out std_logic_vector(31 downto 0);   -- LED displays for direct display of registers, etc.
        GPIO0_D  : out std_logic_vector(1 downto 0)     -- dotstar out
    );
end DE0_Spikeputor;

architecture Structural of DE0_Spikeputor is
    -- Signal Declarations

    -- CPU Memory interface signals
    signal cpu_cyc     : std_logic := '0';
    signal cpu_stb     : std_logic := '0';
    signal cpu_ack     : std_logic := '0';
    signal cpu_addr    : std_logic_vector(15 downto 0) := (others => '0');
    signal cpu_data_o  : std_logic_vector(15 downto 0) := (others => '0');
    signal cpu_we      : std_logic := '0';
    signal cpu_gnt_sig : std_logic := '0';
    
    -- Memory output signals - will eventually be multiplexed when multiple Wishbone providers are implemented
    signal data_i      : std_logic_vector(15 downto 0) := (others => '0');
    signal ack         : std_logic := '0';

    -- CPU clock control related signals
    signal clk_gnt_req : std_logic := '0';
    signal clk_gnt_sig : std_logic := '0';

    -- Arbiter-related signals
    signal arb_cyc     : std_logic := '0';
    signal arb_stb     : std_logic := '0';
    signal arb_we      : std_logic := '0';
    signal arb_addr    : std_logic_vector(15 downto 0) := (others => '0');
    signal arb_data_o  : std_logic_vector(15 downto 0) := (others => '0');

    -- Registers and Signals to Display (will be replaced with DotStar output eventually)
    -- Special Registers                                                            -- number of LED group for dotstar module [bits]
    signal inst_out    : std_logic_vector(15 downto 0) := (others => '0');           -- 1 [16]
    signal const_out   : std_logic_vector(15 downto 0) := (others => '0');           -- 2 [16]
    signal mdata_out   : std_logic_vector(15 downto 0) := (others => '0');           -- 3 [16]
    signal pc_out      : std_logic_vector(15 downto 0) := (others => '0');           -- 4 [16]

    -- Regsiter File
    -- signal reg_stat    : std_logic_vector(15 downto 0) := (others => '0');           -- 5 [15]
    -- signal wd_input    : std_logic_vector(15 downto 0) := (others => '0');           -- 6 [16]
    -- signal reg_index   : integer range 1 to 7 := 1;                                  -- to select which register to display
    -- signal all_regs    : RARRAY := (others => (others => '0'));                      -- 7-13
    -- signal rega_out    : std_logic_vector(15 downto 0) := (others => '0');           -- 14 [17]
    -- signal regb_out    : std_logic_vector(15 downto 0) := (others => '0');           -- 15 [16]

    -- ALU
    -- signal alu_fn_leds : std_logic_vector(15 downto 0) := (others => '0');           -- 16 [17 or 19 depending on ASEL/BSEL 1 bit or 2 bit signals]
    -- signal alu_a       : std_logic_vector(15 downto 0) := (others => '0');           -- 17 [16]
    -- signal alu_b       : std_logic_vector(15 downto 0) := (others => '0');           -- 18 [16]
    -- signal alu_arith   : std_logic_vector(15 downto 0) := (others => '0');           -- 19 [16]
    -- signal alu_bool    : std_logic_vector(15 downto 0) := (others => '0');           -- 20 [16]
    -- signal alu_shift   : std_logic_vector(15 downto 0) := (others => '0');           -- 21 [16]
    -- signal alu_cmpf    : std_logic_vector(15 downto 0) := (others => '0');           -- 22 [4]
    -- signal s_alu_out   : std_logic_vector(15 downto 0) := (others => '0');           -- 23 [16]

    -- clock logic
    signal clk_speed   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(50000000, 32)); -- default clock speed = 1 Hz
    
    -- Input synchronized signals
    signal sw_sync     : std_logic_vector(9 downto 0) := (others => '0');
    signal button_sync : std_logic_vector(2 downto 0) := (others => '0');

begin
    -- Input Synchronizers
    DIP_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 10 )
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => SW,
            SYNC_OUT => sw_sync
        );

    BUTTON_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 3 )
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => BUTTON,
            SYNC_OUT => button_sync
        );

    -- Round Robin Wishbone Bus Arbiter
    ARBITER : entity work.WSH_ARBITER 
        port map (
            CLK         => CLOCK_50,
            RESET       => NOT button_sync(0),      --  Button 0 is system reset (active low)

            -- Master 0 (CPU) signals
            M0_CYC_O    => cpu_cyc,
            M0_STB_O    => cpu_stb,
            M0_WE_O     => cpu_we,
            M0_DATA_O   => cpu_data_o,
            M0_ADDR_O   => cpu_addr,

            -- Master 1 (DMA) signals - not yet implemented
            M1_CYC_O    => '0',
            M1_STB_O    => '0',
            M1_WE_O     => '0',
            M1_DATA_O   => X"0000",
            M1_ADDR_O   => X"0000",

            -- Master 2 (Clock Generator) signals
            M2_CYC_O    => clk_gnt_req,             -- clock grant request

            -- Wishbone Grant Signals
            M0_GNT      => cpu_gnt_sig,             -- CPU grant given
            M1_GNT      => open,                    -- DMA grant given
            M2_GNT      => clk_gnt_sig,             -- Clock Generator grant given

            -- Wishbone bus granted signals passed out through the arbiter
            CYC_O       => arb_cyc,
            STB_O       => arb_stb,
            WE_O        => arb_we,
            ADDR_O      => arb_addr,
            DATA_O      => arb_data_o
        );

        cpu_ack <= cpu_gnt_sig AND ack;             -- ack signal for an arbited master is wishbone bus ack signal AND master grant signal (apply this to DMA when implemented)

    -- Spikeputor CPU as Wishbone master (M0)
    CPU : entity work.CPU_WSH_M port map (
        -- Timing
        CLK       => CLOCK_50,
        RESET     => NOT button_sync(0),            -- Button 0 is system reset (active low)
        STALL     => '0',                           -- Debug signal will stall the CPU in between each phase. Will wait until STALL is low to proceed. Set to '0' for no stalling.

        -- Memory standard Wishbone interface signals
        M_DATA_I  => data_i,                        -- Wishbone Data from providers
        M_ACK_I   => cpu_ack,                       -- Wishbone ACK from providers
        M_DATA_O  => cpu_data_o,                    -- Wishbone Data to providers
        M_ADDR_O  => cpu_addr,                      -- Wishbone Address to providers
        M_CYC_O   => cpu_cyc,                       -- Wishbone CYC to providers
        M_STB_O   => cpu_stb,                       -- Wishbone STB to providers
        M_WE_O    => cpu_we,                        -- Wishbone WE to providers

        --Display interface
        DISP_DATA => GPIO0_D(0),                    -- DotStar Data
        DISP_CLK  => GPIO0_D(1),                    -- DotStar Clock

        -- Direct Display Values
        INST_DISP       => inst_out,
        CONST_DISP      => const_out,
        MDATA_DISP      => mdata_out,
        PC_DISP         => pc_out

        -- -- Direct Display Values (temporary - will eventually all be DotStar ouput)
        -- JT              => LEDG(8),
        -- REGSTAT_DISP    => reg_stat,
        -- WDINPUT_DISP    => wd_input,
        -- REGS_DISP       => all_regs,
        -- REGA_DISP       => rega_out,
        -- REGB_DISP       => regb_out,
        -- ALU_FNLEDS_DISP => alu_fn_leds,
        -- ALUA_DISP       => alu_a,
        -- ALUB_DISP       => alu_b,
        -- ALUARITH_DISP   => alu_arith,
        -- ALUBOOL_DISP    => alu_bool,
        -- ALUSHIFT_DISP   => alu_shift,
        -- ALUCMPF_DISP    => alu_cmpf,
        -- ALUOUT_DISP     => s_alu_out,
        -- PHASE_DISP      => LEDG(2 downto 0)
    );

    -- Spikeputor CPU Clock Control as Wishbone Master (M2)
    CLK_GEN : entity work.CLOCK_WSH_M
    port map (
        CLK        => CLOCK_50,
        RESET      => NOT button_sync(0),   -- Button 0 is system reset (active low)

        M_CYC_O    => clk_gnt_req,          -- set high when clock wants to hold the bus
        M_ACK_I    => clk_gnt_sig,          -- set high when clock bus request is granted

        AUTO_TICKS => clk_speed, --std_logic_vector(to_unsigned(50000000, 32)), -- 50 million ticks at 50 MHz = 1 second period = 1 Hz clock
        MAN_SEL    => sw_sync(0),           -- Switch 0 selects between auto and manual clock
        MAN_START  => NOT button_sync(1),   -- Button 1 is manual clock (active low)
        CPU_CLOCK  => LEDG(9)
    );

    -- TODO: this can be replaced with a wishbone provider so it can be set from software
    WITH (sw_sync(6 downto 4)) SELECT   -- select CPU speed via switches 6 through 4
        clk_speed <=                                                        -- clock values assuming a 50MHz system clock
            std_logic_vector(to_unsigned(100_000_000, 32)) when "000",      -- 0.5 Hz
            std_logic_vector(to_unsigned(10_000_000, 32)) when "001",       -- 5 Hz
            std_logic_vector(to_unsigned(1_000_000, 32)) when "010",        -- 50 Hz
            std_logic_vector(to_unsigned(100_000, 32)) when "011",          -- 500 Hz
            std_logic_vector(to_unsigned(10_000, 32)) when "100",           -- 5 KHz
            std_logic_vector(to_unsigned(1_000, 32)) when "101",            -- 50 KHz
            std_logic_vector(to_unsigned(100, 32)) when "110",              -- 500 KHz
            std_logic_vector(to_unsigned(10, 32)) when "111",               -- 5 MHz
            std_logic_vector(to_unsigned(10_000_000, 32)) when others;

    -- TODO: Address comparator to select the proper Wishbone provider based on WBS_ADDR_I, WBS_WE_I and bank select register


    -- RAM Instance as Wishbone provider (P0)
    RAM : entity work.RAMTest_WSH_P port map ( -- change to real RAM module when testing is complete, add other provider modules for ROM, peripherals, etc.
        -- SYSCON inputs
        CLK         => CLOCK_50,

        -- Wishbone signals - inputs from the arbiter, outputs as described
        -- handshaking signals
        WBS_CYC_I   => arb_cyc,
        WBS_STB_I   => arb_stb,     -- Later, this is derived from arb_stb AND address comparator (to select a specific type of memory to interface with based on address and bank select register)
        WBS_ACK_O   => ack,         -- Later, just OR all the memory ack signals together

        -- memory read/write signals
        WBS_ADDR_I  => arb_addr,
        WBS_DATA_O  => data_i,      -- Later, this will be sent to a multiplexer input. MUX selection based on address and bank select register
        WBS_DATA_I  => arb_data_o,
        WBS_WE_I    => arb_we
    );

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => pc_out,    -- display PC on 7-seg
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    -- LED output logic
    LEDG(7 downto 3) <= (others => '0');

    -- Set default output states

    -- 7-SEG Display
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    -- reg_index <= to_integer(unsigned(sw_sync(3 downto 1)));  -- select register index from switches 3-1

    -- WITH (sw_sync(9 downto 7)) SELECT                               -- output various values to upper 16 bits of GPIO1 based on switches 9-7
    --     GPIO1_D(31 downto 16) <= inst_out    WHEN "000",            -- INST output
    --                              s_alu_out   WHEN "001",            -- CONST output
    --                              rega_out    WHEN "010",            -- RegFile Channel A
    --                              regb_out    WHEN "011",            -- RegFile Channel B
    --                              mdata_out   WHEN "100",            -- MRDATA output or MWDATA input (when a ST command)
    --                              reg_stat    WHEN "101",            -- RegFile control signals and Zero flag
    --                              wd_input    WHEN "110",            -- RegFile selected write data
    --                              all_regs(reg_index) WHEN "111",    -- register at current index (1 to 7)
    --                              inst_out    WHEN others;           -- INST output (should never happen)
    
    -- TODO: send these to the LED driver, along with PC and MDATA
    GPIO1_D(31 downto 16) <= inst_out;                              -- output inst_out to upper 16 bits of GPIO1
    GPIO1_D(15 downto 0) <= const_out;                              -- output const_out to lower 16 bits of GPIO1

    -- WITH (sw_sync(6 downto 4)) SELECT
    --     GPIO1_D(15 downto 0)  <= const_out   WHEN "000",            -- ALU Output
    --                              alu_shift   WHEN "001",            -- ALU shift output
    --                              alu_arith   WHEN "010",            -- ALU arithmetic output
    --                              alu_bool    WHEN "011",            -- ALU boolean output
    --                              alu_cmpf    WHEN "100",            -- ALU compare flags
    --                              alu_a       WHEN "101",            -- ALU A input
    --                              alu_b       WHEN "110",            -- ALU B input
    --                              alu_fn_leds WHEN "111",            -- ALU function control signals
    --                              const_out   WHEN others;           -- ALU output (should never happen)

end Structural;
