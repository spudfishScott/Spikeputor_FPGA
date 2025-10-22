library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.Types.all;

entity DE0Nano_Spikeputor is
    port (
        -- Clock Input
        CLOCK_50 : in std_logic;
        -- Push Button
        KEY : in std_logic_vector(1 downto 0);  -- KEY(0) is reset, KEY(1) is manual clock
        -- DIP Switch Switch
        DIP : in std_logic_vector(3 downto 0);  -- DIP(0) switches between auto and manual clock
        -- LED
        LED : out std_logic_vector(7 downto 0);
        -- GPIO
        GPIO0 :in std_logic_vector(7 downto 0); -- switches to control output data
        GPIO1 : out std_logic_vector(31 downto 0)
    );
end DE0Nano_Spikeputor;

architecture Structural of DE0Nano_Spikeputor is
    -- Signal Declarations

    -- Memory interface signals
    signal cyc    : std_logic := '0';
    signal stb    : std_logic := '0';
    signal ack    : std_logic := '0';
    signal arb_ack : std_logic := '0';
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
    signal alu_a       : std_logic_vector(15 downto 0) := (others => '0');          -- 17 [16]
    signal alu_b       : std_logic_vector(15 downto 0) := (others => '0');          -- 18 [16]
    signal alu_arith   : std_logic_vector(15 downto 0) := (others => '0');          -- 19 [16]
    signal alu_bool    : std_logic_vector(15 downto 0) := (others => '0');          -- 20 [16]
    signal alu_shift   : std_logic_vector(15 downto 0) := (others => '0');          -- 21 [16]
    signal alu_cmpf    : std_logic_vector(15 downto 0) := (others => '0');          -- 22 [4]
    signal s_alu_out : std_logic_vector(15 downto 0) := (others => '0');            -- 23 [16]

    -- clock logic
    signal system_clk_en : std_logic := '0';
    
    -- Input synchronized signals
    signal dip_sync    : std_logic_vector(3 downto 0) := (others => '0');
    signal key_sync    : std_logic_vector(1 downto 0) := (others => '0');
    signal gpi_sync    : std_logic_vector(7 downto 0) := (others => '0');

begin
    -- Input Synchronizers
    DIP_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 4 )
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => DIP,
            SYNC_OUT => dip_sync
        );

    KEY_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 2 )
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => KEY,
            SYNC_OUT => key_sync
        );

    GPI_SYNC : entity work.SYNC_REG
        generic map ( WIDTH => 8 )
        port map (
            CLK_IN   => CLOCK_50,
            ASYNC_IN => GPIO0,
            SYNC_OUT => gpi_sync
        );

    -- Auto/Manual Clock Instance - generates CPU clock enable signal 5 Hz automatically or on button press in manual mode
    -- TODO: convert to a wishbone master and integrate into arbiter
    CLK_EN_GEN_E : entity work.AUTO_MANUAL_CLOCK
        generic map (
            AUTO_FREQ => 5,
            SYS_FREQ  => 50000000
        )
        port map (
            SYS_CLK   => CLOCK_50,
            MAN_SEL   => dip_sync(0),
            MAN_START => NOT key_sync(1),
            CLK_EN    => system_clk_en
        );

    -- Arbiter - simple right now: just stall the CPU module to wait for clock enable, eventually will include clock enable as a wishbone master, as well as a wishbone master DMA module
    arb_ack <= ack AND system_clk_en;             -- pass ack through to CPU only when clock enable is high (cpu will stall until then)

    -- Spikeputor CPU as Wishbone master
    CPU : entity work.CPU_WSH_M port map (
        -- Timing
        CLK       => CLOCK_50,
        RESET     => NOT key_sync(0),      -- System reset

        -- Memory interface
        M_DATA_I  => data_i,
        M_ACK_I   => arb_ack,
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
        ALUA_DISP       => alu_a,
        ALUB_DISP       => alu_b,
        ALUARITH_DISP   => alu_arith,
        ALUBOOL_DISP    => alu_bool,
        ALUSHIFT_DISP   => alu_shift,
        ALUCMPF_DISP    => alu_cmpf,
        ALUOUT_DISP     => s_alu_out,
        PHASE_DISP      => LED(1 downto 0)
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

    -- LED output logic
    LED(6 downto 2) <= (others => '0');
    LED(7) <= system_clk_en;  -- LED7 is cpu clock indicator

    reg_index <= to_integer(unsigned(dip_sync(3 downto 1)));  -- select register index from DIP switches 3-1

    -- output various values to GPIO1 based on GPIO0 input values 7-5 and 2-0
    WITH (gpi_sync(7 downto 5)) SELECT
        GPIO1(31 downto 16) <= inst_out   WHEN "000",        -- INST output
                               s_alu_out  WHEN "001",        -- CONST output
                               rega_out   WHEN "010",        -- RegFile Channel A
                               regb_out   WHEN "011",        -- RegFile Channel B
                               mrdata_out WHEN "100",        -- MRDATA output
                               reg_stat   WHEN "101",        -- RegFile control signals and Zero flag
                               wd_input   WHEN "110",        -- RegFile selected write data
                               all_regs(reg_index) WHEN "111",   -- register at current index (1 to 7)
                               inst_out   WHEN others;       -- INST output (should never happen)

    WITH (gpi_sync(2 downto 0)) SELECT
        GPIO1(15 downto 0)  <= const_out  WHEN "000",        -- ALU Output
                               alu_shift  WHEN "001",        -- ALU shift output
                               alu_arith  WHEN "010",        -- ALU arithmetic output
                               alu_bool   WHEN "011",        -- ALU boolean output
                               alu_cmpf   WHEN "100",        -- ALU compare flags
                               alu_a      WHEN "101",        -- ALU A input
                               alu_b      WHEN "110",        -- ALU B input
                               pc_out     WHEN "111",        -- ALU function control signals
                               const_out  WHEN others;       -- ALU output (should never happen)

end Structural;
