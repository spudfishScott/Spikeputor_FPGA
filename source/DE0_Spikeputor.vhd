library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.Types.all;

entity DE0_Spikeputor is
    port (
        -- Clock Input
        CLOCK_50     : in std_logic;
        -- Push Button
        BUTTON       : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW           : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D       : out std_logic_vector(6 downto 0);
        HEX0_DP      : out std_logic;
        HEX1_D       : out std_logic_vector(6 downto 0);
        HEX1_DP      : out std_logic;
        HEX2_D       : out std_logic_vector(6 downto 0);
        HEX2_DP      : out std_logic;
        HEX3_D       : out std_logic_vector(6 downto 0);
        HEX3_DP      : out std_logic;
        -- LED
        LEDG         : out std_logic_vector(9 downto 0);
        -- FLASH
        FL_BYTE_N    : out std_logic;
        FL_CE_N      : out std_logic;
        FL_OE_N      : out std_logic;
        FL_RST_N     : out std_logic;
        FL_WE_N      : out std_logic;
        FL_WP_N      : out std_logic;
        FL_ADDR      : out std_logic_vector(21 downto 0);
        FL_DQ        : in std_logic_vector(15 downto 0);
        FL_RY        : in std_logic;
        --SDRAM
        DRAM_CLK     : out std_logic;
        DRAM_CKE     : out std_logic;
        DRAM_CS_N    : out std_logic;
        DRAM_RAS_N   : out std_logic;
        DRAM_CAS_N   : out std_logic;
        DRAM_WE_N    : out std_logic;
        DRAM_BA_0    : out std_logic;
        DRAM_BA_1    : out std_logic;
        DRAM_ADDR    : out std_logic_vector(11 downto 0);
        DRAM_DQ      : inout std_logic_vector(15 downto 0);
        DRAM_UDQM    : out std_logic;
        DRAM_LDQM    : out std_logic;
        --PS/2 KEYBOARD
        PS2_KBCLK    : inout std_logic;
        PS2_KBDAT    : inout std_logic;
        -- GPIO - use GPIO1_D pins, but relabel
        SPK_GPI      : in std_logic_vector(15 downto 0);   -- 16 bits of GPI (GPIO_1[31 to 16])
        SPK_GPO      : out std_logic_vector(15 downto 0);   -- 16 bits of GPO (GPIO_1[15 to 0])
        -- Video Interface
        VIDEO_BL     : out std_logic;
        VIDEO_RST_N  : out std_logic;
        VIDEO_CS_N   : out std_logic;
        VIDEO_WR_N   : out std_logic;
        VIDEO_RD_N   : out std_logic;
        VIDEO_RS     : out std_logic;
        VIDEO_WAIT_N : in std_logic;
        VIDEO_DATA   : inout std_logic_vector(15 downto 0);
        -- DotStar LED Strip Interface
        DOTSTAR_DATA : out std_logic;
        DOTSTAR_CLK  : out std_logic;
        -- LCD I2C Interface -- relabel to SDA and SCL
        LCD_SCL      : inout std_logic;
        LCD_SDA      : inout std_logic
    );
end DE0_Spikeputor;

architecture Structural of DE0_Spikeputor is
    -- Spikeputor Constants
    constant CLK_FREQ     : Integer := 50_000_000;                           -- System clock frequency in Hz - feeds all other modules
    constant RESET_VECTOR : std_logic_vector(15 downto 0) := x"F000";        -- Address PC is set to on RESET

    -- Signal Declarations
    signal SEGMENT     : std_logic_vector(7 downto 0) := (others => '0');
    signal GPO_REG     : std_logic_vector(15 downto 0) := (others => '0');

    -- CPU Memory interface signals
    signal cpu_cyc     : std_logic := '0';
    signal cpu_stb     : std_logic := '0';
    signal cpu_ack     : std_logic := '0';
    signal cpu_addr    : std_logic_vector(15 downto 0) := (others => '0');
    signal cpu_ext     : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_data_o  : std_logic_vector(15 downto 0) := (others => '0');
    signal cpu_we      : std_logic := '0';
    signal cpu_tga     : std_logic := '0';
    signal cpu_tgd     : std_logic := '0';
    signal cpu_gnt_sig : std_logic := '0';

    -- CPU display signals
    signal wseg_out    : std_logic;
    signal inst_out    : std_logic_vector(15 downto 0) := (others => '0');
    signal const_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal mdata_out   : std_logic_vector(16 downto 0) := (others => '0');
    signal rwaddr_out  : std_logic_vector(15 downto 0) := (others => '0');
    signal pc_out      : std_logic_vector(16 downto 0) := (others => '0');
    signal alu_out     : std_logic_vector(15 downto 0) := (others => '0');
    signal alu_cmp_out : std_logic_vector(6 downto 0) := (others => '0');
    signal alu_sh_out  : std_logic_vector(18 downto 0) := (others => '0');
    signal alu_boo_out : std_logic_vector(20 downto 0) := (others => '0');
    signal alu_ar_out  : std_logic_vector(17 downto 0) := (others => '0');
    signal alu_a_out   : std_logic_vector(16 downto 0) := (others => '0');
    signal alu_b_out   : std_logic_vector(16 downto 0) := (others => '0');
    signal regb_out    : std_logic_vector(15 downto 0) := (others => '0');
    signal rega_out    : std_logic_vector(16 downto 0) := (others => '0');
    signal reg1_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg2_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg3_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg4_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg5_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg6_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal reg7_out    : std_logic_vector(18 downto 0) := (others => '0');
    signal regin_out   : std_logic_vector(17 downto 0) := (others => '0');

    -- TODO: DMA interface signals
    signal dma_ack     : std_logic := '0';
    signal dma_gnt_sig : std_logic := '0';

    -- Memory output signals
    signal data_i      : std_logic_vector(15 downto 0) := (others => '0');
    signal ack         : std_logic_vector(11 downto 0) := (others => '0');  -- all of the ack signals from the providers
    signal all_acks    : std_logic := '0';                                  -- OR all of the ack signals together for input into masters

    -- CPU clock control related signals
    signal clk_gnt_req : std_logic := '0';
    signal clk_gnt_sig : std_logic := '0';

    -- Arbiter-related signals
    signal arb_cyc     : std_logic := '0';
    signal arb_stb     : std_logic := '0';
    signal arb_we      : std_logic := '0';
    signal arb_addr    : std_logic_vector(23 downto 0) := (others => '0');
    signal arb_data_o  : std_logic_vector(15 downto 0) := (others => '0');

    -- Adress comparitor-related signals
    signal data0       : std_logic_vector(15 downto 0) := (others => '0');
    signal data1       : std_logic_vector(15 downto 0) := (others => '0');
    signal data2       : std_logic_vector(15 downto 0) := (others => '0');
    signal data3       : std_logic_vector(15 downto 0) := (others => '0');
    signal data4       : std_logic_vector(15 downto 0) := (others => '0');
    signal data5       : std_logic_vector(15 downto 0) := (others => '0');
    signal data6       : std_logic_vector(15 downto 0) := (others => '0');
    signal data7       : std_logic_vector(15 downto 0) := (others => '0');
    signal data8       : std_logic_vector(15 downto 0) := (others => '0');
    signal data9       : std_logic_vector(15 downto 0) := (others => '0');
    signal data10      : std_logic_vector(15 downto 0) := (others => '0');
    signal data11      : std_logic_vector(15 downto 0) := (others => '0');

    signal stb_sel_sig : std_logic_vector(11 downto 0) := (others => '0');

    -- clock logic
    signal clk_speed   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(50000000, 32)); -- default clock speed = 1 Hz
    signal startup_res : std_logic := '1';                                  -- startup reset signal
    signal SYS_CLK     : std_logic;                                         -- system clock signal
    signal RESET       : std_logic;                                         -- system reset signal
    signal MAN_CLK     : std_logic;                                         -- system manual clock

    -- Input synchronized signals
    signal sw_sync     : std_logic_vector(9 downto 0) := (others => '0');
    signal button_sync : std_logic_vector(2 downto 0) := (others => '0');

    -- DotStar and LCD Control
    signal led_refresh     : std_logic := '0';                                   -- signal to start the DotStar LED refresh process
    signal lcd_refresh : std_logic := '0';                                   -- signal to start the LCD refresh process
    signal led_busy    : std_logic := '0';                                   -- the dotstar interface is busy with an update
    signal lcd_busy    : std_logic := '0';                                   -- the LCD interface is busy with an update
    signal last_cyc_sig : std_logic := '0';                                  -- to detect edge of wishbone cycle for wishbone update request

begin
    -- Clock and Reset Signals
    SYS_CLK <= CLOCK_50;                                                     -- This may be a different value in the future (through PLL)
    RESET   <= startup_res OR (NOT button_sync(0));                          -- Reset is startup reset or Button 0 (active low) now, but might not always be
    MAN_CLK <= NOT button_sync(1);                                           -- Button 1 is manual clock (active low) now, but might not always be

    -- startup reset pulse generator
    PG1: entity work.PULSE_GEN
        generic map ( 
           PULSE_WIDTH => 10_000_000,   -- 10 million clock ticks = 0.2 seconds at 50 MHz
           RESET_LOW => false
        )
        port map (
            START_PULSE => '1',
            CLK_IN      => SYS_CLK,
            PULSE_OUT   => startup_res
        );

    -- Input Synchronizers
    DIP_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 10 )
        port map (
            CLK_IN   => SYS_CLK,
            ASYNC_IN => SW, -- switches
            SYNC_OUT => sw_sync
        );

    BUTTON_SYNC_E : entity work.SYNC_REG
        generic map ( WIDTH => 3 )
        port map (
            CLK_IN   => SYS_CLK,
            ASYNC_IN => BUTTON, -- buttons
            SYNC_OUT => button_sync
        );

    -- WISHBONE ROUTING ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Round Robin Wishbone Bus Arbiter
    ARBITER : entity work.WSH_ARBITER 
        port map (
            CLK         => SYS_CLK,
            RESET       => RESET,

            -- Master 0 (CPU) signals
            M0_CYC_O    => cpu_cyc,
            M0_STB_O    => cpu_stb,
            M0_WE_O     => cpu_we,
            M0_DATA_O   => cpu_data_o,
            M0_ADDR_O   => cpu_ext & cpu_addr,

            -- Master 1 (DMA) signals - not yet implemented
            M1_CYC_O    => '0',
            M1_STB_O    => '0',
            M1_WE_O     => '0',
            M1_DATA_O   => X"0000",
            M1_ADDR_O   => X"000000",

            -- Master 2 (Clock Generator) signals
            M2_CYC_O    => clk_gnt_req,             -- clock grant request

            -- Wishbone Grant Signals
            M0_GNT      => cpu_gnt_sig,             -- CPU grant given
            M1_GNT      => dma_gnt_sig,             -- DMA grant given
            M2_GNT      => clk_gnt_sig,             -- Clock Generator grant given

            -- Wishbone bus granted signals passed out through the arbiter
            CYC_O       => arb_cyc,
            STB_O       => arb_stb,
            WE_O        => arb_we,
            ADDR_O      => arb_addr,
            DATA_O      => arb_data_o
        );

        cpu_ext <= SEGMENT when cpu_tga = '1' else x"00";   -- cpu_tga determines if the SEGMENT register should be used to extend the address coming out of the CPU

    -- Address comparator to select the proper Wishbone provider based on arbited 24 bit ADDR, WE, STB, and bank select register signals
    ADDR_CMP : entity work.WSH_ADDR
        port map (
            ADDR_I      => arb_addr,        -- full 24 bit address
            WE_I        => arb_we,
            STB_I       => arb_stb,
            TGD_I       => cpu_tgd,         -- flag to write data bus to SEGMENT register

            P0_DATA_O   => data0,           -- map each provider data output into the address comparator
            P1_DATA_O   => data1,
            P2_DATA_O   => data2,
            P3_DATA_O   => data3,
            P4_DATA_O   => data4,
            P5_DATA_O   => data5,
            P6_DATA_O   => data6,
            P7_DATA_O   => data7,
            P8_DATA_O   => data8,
            P9_DATA_O   => data9,
            P10_DATA_O  => data10,
            P11_DATA_O  => data11,

            DATA_O      => data_i,          -- selected provider data output goes to masters' data_i
            STB_SEL     => stb_sel_sig      -- one hot signal, one bit for each provider STB_I
        );

        -- Wishbone ACK signal logic
        all_acks <= ack(11) OR ack(10) OR ack(9) OR ack(8) OR ack(7) OR ack(6) OR ack(5) OR ack(4) OR ack(3) OR ack(2) OR ack(1) OR ack(0); -- or all provider ACK_Os together to send to granted master ACK_I
        cpu_ack  <= cpu_gnt_sig AND all_acks;               -- ack signal for an arbited master is wishbone bus ack signal AND master grant signal (apply this to DMA when implemented)
        dma_ack  <= dma_gnt_sig AND all_acks;

    -- WISHBONE MASTERS ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    -- CPU (M0), DMA (M1), Clock Throttle (M2)

    -- Spikeputor CPU as Wishbone master (M0)
    CPU : entity work.CPU_WSH_M
        generic map ( RESET_VECTOR => RESET_VECTOR )
        port map (
            -- Timing
            CLK             => SYS_CLK,
            RESET           => RESET,
            STALL           => '0',                           -- Temp Debug signal will stall the CPU in between each phase. Will wait until STALL is low to proceed. Set to '0' for no stalling.
            SEGMENT         => SEGMENT,                       -- Segment Register input to CPU (so it can store in a register)

            -- Memory standard Wishbone interface signals
            M_DATA_I        => data_i,                        -- Wishbone Data from providers (from address comparitor)
            M_ACK_I         => cpu_ack,                       -- Wishbone ACK from providers
            M_DATA_O        => cpu_data_o,                    -- Wishbone Data to providers
            M_ADDR_O        => cpu_addr,                      -- Wishbone Address to providers (16 bit)
            M_CYC_O         => cpu_cyc,                       -- Wishbone CYC to providers
            M_STB_O         => cpu_stb,                       -- Wishbone STB to providers
            M_WE_O          => cpu_we,                        -- Wishbone WE to providers
            M_TGA_O         => cpu_tga,                       -- Wishbone user address tag to use extended address (1 = use segment register)
            M_TGD_O         => cpu_tgd,                       -- Wishbone user data tag to write to SEGMENT register or to a normal memory address

            -- Direct Display Values
            WSEG_DISP       => wseg_out,
            INST_DISP       => inst_out,
            CONST_DISP      => const_out,
            MDATA_DISP      => mdata_out,
            RWADDR_DISP     => rwaddr_out,
            PC_DISP         => pc_out,
            ALU_DISP        => alu_out,
            ALU_CMP_DISP    => alu_cmp_out,
            ALU_SHIFT_DISP  => alu_sh_out,
            ALU_BOOL_DISP   => alu_boo_out,
            ALU_ARITH_DISP  => alu_ar_out,
            ALU_A_DISP      => alu_a_out,
            ALU_B_DISP      => alu_b_out,
            REGB_OUT_DISP   => regb_out,
            REGA_OUT_DISP   => rega_out,
            REG1_DISP       => reg1_out,
            REG2_DISP       => reg2_out,
            REG3_DISP       => reg3_out,
            REG4_DISP       => reg4_out,
            REG5_DISP       => reg5_out,
            REG6_DISP       => reg6_out,
            REG7_DISP       => reg7_out,
            REGIN_DISP      => regin_out
        );

    -- Spikeputor DMA as Wishbone master (M1)
    -- TODO

    -- Spikeputor CPU Clock Throttle Control as Wishbone Master (M2)
    CLK_GEN : entity work.CLOCK_WSH_M
        port map (
            CLK        => SYS_CLK,
            RESET      => RESET,

            M_CYC_O    => clk_gnt_req,          -- set high when clock wants to hold the bus
            M_ACK_I    => clk_gnt_sig,          -- set high when clock bus request is granted

            SPD_IN     => sw_sync(6 downto 4),  -- input for clock speed for auto mode
            MAN_SEL    => sw_sync(0),           -- Switch 0 selects between auto and manual clock
            MAN_START  => MAN_CLK,
            CPU_CLOCK  => LEDG(9)
        );

    -- WISHBONE PROVIDERS --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    -- RAM (P0), ROM (P1), GPO (P2), GPI (P3), SOUND (P4), VIDEO (P5), SERIAL (P6), STORAGE (P7), KEYBOARD (P8), SEGMENT (P9), SDRAM (P10), MATH (P11)

    -- RAM Instance as Wishbone provider (P0)
    RAM : entity work.RAM_WSH_P
        port map (
            -- SYSCON inputs
            CLK         => SYS_CLK,

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(0),     -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(0),             -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read/write signals
            WBS_ADDR_I  => arb_addr,
            WBS_DATA_O  => data0,              -- data out from P0 to Address Comparitor, which provides the wishbone data_o via a mux
            WBS_DATA_I  => arb_data_o,
            WBS_WE_I    => arb_we
        );

    -- ROM Instance as Wishbone provider (P1)
    ROM: entity work.FlashROM_WSH_P
        generic map ( CLK_FREQ => CLK_FREQ )    -- send system frequency into interface
        port map (
            -- SYSCON inputs
            CLK         => SYS_CLK,
            RST_I       => RESET,  -- Button 0 is system reset (active low)

            -- Wishbone signals
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(1),
            WBS_ACK_O   => ack(1),

            -- memory read signals (ROM is read-only)
            WBS_ADDR_I  => arb_addr,
            WBS_DATA_O  => data1,

            -- Flash chip signals
            WP_n        => FL_WP_N,
            BYTE_n      => FL_BYTE_N,
            RST_n       => FL_RST_N,
            CE_n        => FL_CE_N,
            OE_n        => FL_OE_N,
            WE_n        => FL_WE_N,
            BY_n        => FL_RY,
            A           => FL_ADDR,
            Q           => FL_DQ
        );

    -- GPO Instance as Wishbone Provider (P2)
    GPO1 : entity work.GPO_WSH_P
        port map (
            CLK         => SYS_CLK,

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(2),     -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(2),             -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read/write signals
            WBS_DATA_I  => arb_data_o,
            WBS_DATA_O  => data2,
            WBS_WE_I    => arb_we,

            -- GPO register output
            GPO         => GPO_REG             -- 16 bits to go to GPO port
        );

    -- GPI Instance as Wishbone Provider (P3)
    GPI1 : entity work.GPI_WSH_P
        port map (
            CLK         => SYS_CLK,

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(3),     -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(3),             -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read signals (GPI is read-only)
            WBS_DATA_O  => data3,

            -- GPI register input
            GPI         => SPK_GPI             -- 16 bits from GPI port
        );

    -- VIDEO Instance as Wishbone provider (P5)
    VID1 : entity work.VIDEO_WSH_P
        generic map ( CLK_FREQ => CLK_FREQ )
        port map (
            -- SYSCON inputs
            CLK         => SYS_CLK,
            RST_I       => RESET,  -- Button 0 is system reset (active low)

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(5),     -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(5),             -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read/write signals
            WBS_ADDR_I  => arb_addr,
            WBS_DATA_O  => data5,              -- data out from P5 to Address Comparitor, which provides the wishbone data_o via a mux
            WBS_DATA_I  => arb_data_o,
            WBS_WE_I    => arb_we,

            -- video chip control signals
            SCRN_BL     => VIDEO_BL,
            SCRN_RST_N  => VIDEO_RST_N,
            SCRN_CS_N   => VIDEO_CS_N,
            SCRN_WR_N   => VIDEO_WR_N,
            SCRN_RD_N   => VIDEO_RD_N,
            SCRN_RS     => VIDEO_RS,
            SCRN_WAIT_N => VIDEO_WAIT_N,
            SCRN_DATA   => VIDEO_DATA
        );

    -- KEYBOARD Instance as Wishbone provider (P8)
    KBD : entity work.KEYBOARD_WSH_P
        generic map ( CLK_FREQ => CLK_FREQ )
        port map (
            CLK         => SYS_CLK,
            RST_I       => RESET,  -- Button 0 is system reset (active low)

            -- Wishbone signals
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(8),
            WBS_ACK_O   => ack(8),

            -- memory read signals (KEYBOARD is single address read-only for now - maybe include a way to change keybaord repeat rate)
            WBS_DATA_O  => data8,

            -- keyboard communication
            PS2_CLK     => PS2_KBCLK,
            PS2_DATA    => PS2_KBDAT
        );

    -- SEGMENT Instance as Wishbone provider (P9)
    SEG : entity work.SEGMENT_WSH_P
        port map (
            CLK         => SYS_CLK,

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(9),     -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(9),             -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read/write signals
            WBS_DATA_I  => arb_data_o,
            WBS_WE_I    => arb_we,
            WBS_DATA_O  => data9,

            -- SEGMENT register
            SEGMENT     => SEGMENT             -- output of SEGMENT provider is a direct connection to the rest of the computer (not on the data bus)
        );

    -- SDRAM Instance as Wishbone provider (P10)
    SDRAM : entity work.SDRAM_WSH_P
        generic map (CLK_FREQ => CLK_FREQ )
        port map (
            -- SYSCON inputs
            CLK         => SYS_CLK,
            RST_I       => RESET,  -- Button 0 is system reset (active low)

            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
            -- handshaking signals
            WBS_CYC_I   => arb_cyc,
            WBS_STB_I   => stb_sel_sig(10),    -- strobe signal from Address Comparitor (use other bits for other providers)
            WBS_ACK_O   => ack(10),            -- ack bit for the full set of provider acks (use other bits for other providers)

            -- memory read/write signals
            WBS_ADDR_I  => arb_addr,
            WBS_DATA_O  => data10,             -- data out from P0 to Address Comparitor, which provides the wishbone data_o via a mux
            WBS_DATA_I  => arb_data_o,
            WBS_WE_I    => arb_we,

            -- DRAM pins
            DRAM_CLK     => DRAM_CLK,
            DRAM_CKE     => DRAM_CKE,
            DRAM_CS_N    => DRAM_CS_N,
            DRAM_RAS_N   => DRAM_RAS_N,
            DRAM_CAS_N   => DRAM_CAS_N,
            DRAM_WE_N    => DRAM_WE_N,
            DRAM_BA_0    => DRAM_BA_0,
            DRAM_BA_1    => DRAM_BA_1,
            DRAM_ADDR    => DRAM_ADDR,
            DRAM_DQ      => DRAM_DQ,
            DRAM_UDQM    => DRAM_UDQM,
            DRAM_LDQM    => DRAM_LDQM
        );

    -- MATH Instance as Wishbone provider (P11)
--    MATH : entity work.MATH_WSH_P
--        port map (
--            CLK         => SYS_CLK,
--
--            -- Wishbone signals - inputs from the arbiter/comparitor, outputs as described
--            -- handshaking signals
--            WBS_CYC_I   => arb_cyc,
--            WBS_STB_I   => stb_sel_sig(11),     -- strobe signal from Address Comparitor (use other bits for other providers)
--            WBS_ACK_O   => ack(11),             -- ack bit for the full set of provider acks (use other bits for other providers)
--
--            -- memory read/write signals
--            WBS_ADDR_I  => arb_addr,
--            WBS_DATA_O  => data11,
--            WBS_DATA_I  => arb_data_o,
--            WBS_WE_I    => arb_we
--        );

    -- DISPLAY INTERFACES --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    process(SYS_CLK) is
    begin
        if rising_edge(SYS_CLK) then 
            last_cyc_sig <= arb_cyc;    -- to detect falling edge of CYC_O signal for DotStar update requests
        end if;
    end process;

    led_refresh <= '1' when (last_cyc_sig = '1' AND arb_cyc = '0') AND led_busy = '0' else '0';     -- update DotStar at the end of a CPU wishbone cycle (falling edge) and if DotStar is not busy
    lcd_refresh <= '1' when (last_cyc_sig = '1' AND arb_cyc = '0') AND lcd_busy = '0' else '0';     -- update LCD panel at end of a CPU wishbone cycle (falling edge) and if LCD panel is not busy
    
	 SPK_GPO <= GPO_REG;         -- send internal GPO register to external GPO

    DOTSTAR : entity work.dotstar_driver 
        generic map ( XMIT_QUANTA => 1 )   -- change XMIT quanta if there are problems updating the full LED set
        port map (
            CLK         => SYS_CLK,
            START       => led_refresh,

            INST        => inst_out,                                                            -- bits: Instruction (16 bits)
            CONST       => const_out,                                                           -- bits: Constant (16 bits)
            MDATA       => mdata_out,                                                           -- bits: write flag, Memory read/write (16 bits)
            PC          => pc_out,                                                              -- bits: JT flag, Program Counter (16 bits)
            SEGMENT     => wseg_out & SEGMENT,                                                  -- bits: WSEG, SEGMENT register (8 bits)

            ALU_OUT     => alu_out,                                                             -- bits: ALU Output (16 bits)
            ALU_CMP     => alu_cmp_out,                                                         -- bits: compare function (2 bits), Z, V, N, Result, CMP selected
            ALU_SHIFT   => alu_sh_out,                                                          -- bits: shift dir, shift extend, shift result (16 bits), SHIFT selected
            ALU_BOOL    => alu_boo_out,                                                         -- bits: bool truth table (4 bits), bool result (16 bits), BOOL selected
            ALU_ARITH   => alu_ar_out,                                                          -- bits: subtract flag, arith result (16 bits), ARITH selected
            ALU_A       => alu_a_out,                                                           -- bits: ASEL, ALU A Input (16 bits)
            ALU_B       => alu_b_out,                                                           -- bits: BSEL, ALU B Input (16 bits)

            REGB_OUT    => regb_out,                                                            -- bits: Register B out (16 bits)
            REGA_OUT    => rega_out,                                                            -- bits: Zero detect, Register A out (16 bits)
            REG1        => reg1_out,                                                            -- bits: Reg 1 to Channel A Out, Reg 1 to Channel B Out, Write to Register 1, Register 1 (16 bits)
            REG2        => reg2_out,                                                            -- bits: Reg 2 to Channel A Out, Reg 2 to Channel B Out, Write to Register 2, Register 2 (16 bits)
            REG3        => reg3_out,                                                            -- bits: Reg 3 to Channel A Out, Reg 3 to Channel B Out, Write to Register 3, Register 3 (16 bits)
            REG4        => reg4_out,                                                            -- bits: Reg 4 to Channel A Out, Reg 4 to Channel B Out, Write to Register 4, Register 4 (16 bits)
            REG5        => reg5_out,                                                            -- bits: Reg 5 to Channel A Out, Reg 5 to Channel B Out, Write to Register 5, Register 5 (16 bits)
            REG6        => reg6_out,                                                            -- bits: Reg 6 to Channel A Out, Reg 6 to Channel B Out, Write to Register 6, Register 6 (16 bits)
            REG7        => reg7_out,                                                            -- bits: Reg 7 to Channel A Out, Reg 7 to Channel B Out, Write to Register 7, Register 7 (16 bits)
            REGIN       => regin_out,                                                           -- bits: WDSEL (2 bits), Reg Input (16 bits)

            GPO         => GPO_REG,                                                             -- bits: General Purpose Output (16 bits)
            GPI         => SPK_GPI,                                                             -- bits: General Purpose Input (16 bits)

            DATA_OUT    => DOTSTAR_DATA,                                                        -- DotStar data and clock signals
            CLK_OUT     => DOTSTAR_CLK,
            BUSY        => led_busy
        );

    -- the LCD driver shows INST/CONST, instruction interpreted, Next PC, and SEGMENT:RWADDR (-> or <-) MDATA during r/w operations - communicates with actual LCD display via the I2C interface lines
    LCD : entity work.LCD_I2C
        generic map ( CLK_FREQ => CLK_FREQ )
        port map (
            CLK         => SYS_CLK,
            RST         => RESET,
            START       => lcd_refresh,                                                         -- set high to begin an update of the LCD panel

            INST        => inst_out,                                                            -- current instruction
            CONST       => const_out,                                                           -- current constant
            ADDR        => rwaddr_out,                                                          -- current address being read or written
            SEGMENT     => SEGMENT,                                                             -- current segment
            PC          => pc_out,                                                              -- current program counter value (includes JT)
            MDATA       => mdata_out,                                                           -- current data for memory read/write (includes write flag)

            SCL         => LCD_SCL,                                                             -- LCD SCL signal
            SDA         => LCD_SDA,                                                             -- LCD SDA signal
            BUSY        => lcd_busy
        );

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS 
        port map (
            WORD  => pc_out(15 downto 0),    -- display PC on 7-seg
            SEGS0 => HEX0_D,
            SEGS1 => HEX1_D,
            SEGS2 => HEX2_D,
            SEGS3 => HEX3_D
        );

    -- LEDs
    LEDG(8 downto 0) <= (others => '0');

    -- 7-SEG Display
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

end Structural;
