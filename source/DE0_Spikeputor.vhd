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
        LEDG : out std_logic_vector(9 downto 0);
        -- GPIO
        GPIO1_D : out std_logic_vector(31 downto 0)
    );
end DE0_Spikeputor;

architecture Structural of DE0_Spikeputor is
    -- Signal Declarations

    -- Memory interface signals
    signal cyc    : std_logic := '0';
    signal stb    : std_logic := '0';
    signal ack    : std_logic := '0';
    signal addr   : std_logic_vector(15 downto 0) := (others => '0');
    signal data_o : std_logic_vector(15 downto 0) := (others => '0');
    signal data_i : std_logic_vector(15 downto 0) := (others => '0');
    signal we     : std_logic := '0';

    -- Registers and Signals to Display (will be replaced with DotStar output eventually)
    -- Special Registers                                                            -- number of LED group for dotstar module [bits]
    signal inst_out   : std_logic_vector(15 downto 0) := (others => '0');           -- 1 [16]
    signal const_out  : std_logic_vector(15 downto 0) := (others => '0');           -- 2 [16]
    signal mrdata_out : std_logic_vector(15 downto 0) := (others => '0');           -- 3 [16]
    signal pc_out      : std_logic_vector(15 downto 0) := (others => '0');          -- 4 [16]

    -- Regsiter File
    signal reg_stat    : std_logic_vector(15 downto 0) := (others => '0');          -- 5 [15]
    signal wd_input    : std_logic_vector(15 downto 0) := (others => '0');          -- 6 [16]
    signal reg_index  : integer range 1 to 7 := 1;                                  -- to select which register to display
    signal all_regs    : RARRAY := (others => (others => '0'));                     -- 7-13
    signal rega_out  : std_logic_vector(15 downto 0) := (others => '0');            -- 14 [17]
    signal regb_out  : std_logic_vector(15 downto 0) := (others => '0');            -- 15 [16]

    -- ALU
    signal alu_fn_leds : std_logic_vector(15 downto 0) := (others => '0');          -- 16 [17 or 19 depending on ASEL/BSEL 1 bit or 2 bit signals]
    signal alu_a       : std_logic_vector(15 downto 0) := (others => '0');          -- 17 [16]
    signal alu_b       : std_logic_vector(15 downto 0) := (others => '0');          -- 18 [16]
    signal alu_arith   : std_logic_vector(15 downto 0) := (others => '0');          -- 19 [16]
    signal alu_bool    : std_logic_vector(15 downto 0) := (others => '0');          -- 20 [16]
    signal alu_shift   : std_logic_vector(15 downto 0) := (others => '0');          -- 21 [16]
    signal alu_cmpf    : std_logic_vector(15 downto 0) := (others => '0');          -- 22 [4]
    signal s_alu_out   : std_logic_vector(15 downto 0) := (others => '0');          -- 23 [16]

    -- clock logic
    signal system_clk_en : std_logic := '0';
    
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
        generic map ( WIDTH => 3)
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => BUTTON,
            SYNC_OUT => button_sync
        );

    -- Auto/Manual Clock Instance - generates CPU clock enable signal 5 Hz automatically or on button press in manual mode
    -- TODO: convert to a wishbone master and integrate into arbiter
    CLK_EN_GEN_E : entity work.AUTO_MANUAL_CLOCK
        generic map (
            AUTO_FREQ => 10,
            SYS_FREQ  => 50000000
        )
        port map (
            SYS_CLK   => CLOCK_50,
            MAN_SEL   => sw_sync(0),            -- switch 0 selects between auto and manual clock
            MAN_START => NOT button_sync(1),    -- Button 1 is manual clock start (active low)
            CLK_EN    => system_clk_en
        );

    -- Arbiter - TODO: include clock enable as a wishbone master (to stall CPU between instructions for single step/slower clock), as well as a wishbone master DMA module

    -- Spikeputor CPU as Wishbone master
    CPU : entity work.CPU_WSH_M port map (
        -- Timing
        CLK       => CLOCK_50,
        RESET     => NOT button_sync(0),            -- Button 0 is system reset (active low)
        STALL     => NOT system_clk_en, --'0',       -- Debug signal will stall the CPU in between each phase. Will wait until STALL is low to proceed. Set to '0' for no stalling.

        -- Memory interface
        M_DATA_I  => data_i,
        M_ACK_I   => ack,
        M_DATA_O  => data_o,
        M_ADDR_O  => addr,
        M_CYC_O   => cyc,
        M_STB_O   => stb,
        M_WE_O    => we,

        --Display interface - DotStar outputs not used currently
        DISP_DATA => open,
        DISP_CLK  => open,

        -- Direct Display Values (temporary - will eventually all be DotStar ouput)
        INST_DISP       => inst_out,
        CONST_DISP      => const_out,
        MRDATA_DISP     => mrdata_out,
        PC_DISP         => pc_out,
        REGSTAT_DISP    => reg_stat,
        WDINPUT_DISP    => wd_input,
        REGS_DISP       => all_regs,
        REGA_DISP       => rega_out,
        REGB_DISP       => regb_out,
        ALU_FNLEDS_DISP => alu_fn_leds,
        ALUA_DISP       => alu_a,
        ALUB_DISP       => alu_b,
        ALUARITH_DISP   => alu_arith,
        ALUBOOL_DISP    => alu_bool,
        ALUSHIFT_DISP   => alu_shift,
        ALUCMPF_DISP    => alu_cmpf,
        ALUOUT_DISP     => s_alu_out,
        PHASE_DISP      => LEDG(2 downto 0)
    );

    -- RAM Instance as Wishbone provider
    RAM : entity work.RAMTest_WSH_P port map ( -- change to real RAM module when testing is complete, add other provider modules for ROM, peripherals, etc.
        -- SYSCON inputs
        CLK         => CLOCK_50,

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

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => pc_out,    -- display PC on 7-seg
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    -- this isn't working the weay it needs to
    PULSE : entity work.PULSE_GEN
        generic map (
            PULSE_WIDTH => 5000000,     -- 0.1 second pulse at 50 MHz clock
            RESET_LOW => false          -- pulse starts on rising edge of START_PULSE and continues for PULSE_WIDTH ticks
        )
        port map (
            CLK_IN       => CLOCK_50,
            START_PULSE  => system_clk_en,
            PULSE_OUT    => LEDG(9)      -- LEDG9 is pulse indicator
        );

    -- LED output logic
    LEDG(8 downto 3) <= (others => '0');
   -- LEDG(9) <= system_clk_en;  -- LED7 is cpu clock indicator - need to use pulse generator so we can see it since it's only on for 20 ns!

    -- Set default output states

    -- 7-SEG Display
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    reg_index <= to_integer(unsigned(sw_sync(3 downto 1)));  -- select register index from switches 3-1

    -- output various values to GPIO1 based on switches 9-7 and 6-4
    WITH (sw_sync(9 downto 7)) SELECT
        GPIO1_D(31 downto 16) <= inst_out    WHEN "000",        -- INST output
                                 s_alu_out   WHEN "001",        -- CONST output
                                 rega_out    WHEN "010",        -- RegFile Channel A
                                 regb_out    WHEN "011",        -- RegFile Channel B
                                 mrdata_out  WHEN "100",        -- MRDATA output
                                 reg_stat    WHEN "101",        -- RegFile control signals and Zero flag
                                 wd_input    WHEN "110",        -- RegFile selected write data
                                 all_regs(reg_index) WHEN "111",   -- register at current index (1 to 7)
                                 inst_out    WHEN others;       -- INST output (should never happen)

    WITH (sw_sync(6 downto 4)) SELECT
        GPIO1_D(15 downto 0)  <= const_out   WHEN "000",        -- ALU Output
                                 alu_shift   WHEN "001",        -- ALU shift by 8 output
                                 alu_arith   WHEN "010",        -- ALU arithmetic output
                                 alu_bool    WHEN "011",        -- ALU boolean output
                                 alu_cmpf    WHEN "100",        -- ALU compare flags
                                 alu_a       WHEN "101",           -- ALU A input
                                 alu_b       WHEN "110",           -- ALU B input
                                 alu_fn_leds WHEN "111",          -- ALU function control signals
                                 const_out   WHEN others;       -- ALU output (should never happen)

end Structural;
