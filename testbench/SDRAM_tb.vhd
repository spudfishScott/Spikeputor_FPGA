-- ###########################################################################
-- SDRAM Test Bench
-- Simple read/write stimuli to observe BUSY and VALID timing
-- ###########################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_tb is
end entity;

architecture testbench of SDRAM_tb is
    -- Clock and reset signals
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';

    -- User interface signals
    signal req         : std_logic := '0';
    signal we          : std_logic := '0';
    signal addr        : std_logic_vector(21 downto 0) := (others => '0');
    signal wdata       : std_logic_vector(15 downto 0) := (others => '0');
    signal busy        : std_logic;
    signal rdata       : std_logic_vector(15 downto 0);
    signal valid       : std_logic;

    -- SDRAM pins
    signal dram_clk    : std_logic;
    signal dram_cke    : std_logic;
    signal dram_cs_n   : std_logic;
    signal dram_ras_n  : std_logic;
    signal dram_cas_n  : std_logic;
    signal dram_we_n   : std_logic;
    signal dram_ba_0   : std_logic;
    signal dram_ba_1   : std_logic;
    signal dram_addr   : std_logic_vector(11 downto 0);
    signal dram_dq     : std_logic_vector(15 downto 0);
    signal dram_udqm   : std_logic;
    signal dram_ldqm   : std_logic;

    -- Test signals
    signal dram_dq_out : std_logic_vector(15 downto 0) := (others => '0');
    signal dram_dq_oe  : std_logic := '0';
    signal cycle_count : integer := 0;

    component SDRAM
        generic ( CLK_FREQ : Integer := 50_000_000 );
        port (
            CLK          : in  std_logic;
            RST_N        : in  std_logic;
            REQ          : in  std_logic;
            WE           : in  std_logic;
            ADDR         : in  std_logic_vector(21 downto 0);
            WDATA        : in  std_logic_vector(15 downto 0);
            BUSY         : out std_logic;
            RDATA        : out std_logic_vector(15 downto 0);
            VALID        : out std_logic;
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
            DRAM_LDQM    : out std_logic
        );
    end component;

begin
    -- Instantiate SDRAM controller
    uut : SDRAM
        generic map ( CLK_FREQ => 50_000_000 )
        port map (
            CLK       => clk,
            RST_N     => rst_n,
            REQ       => req,
            WE        => we,
            ADDR      => addr,
            WDATA     => wdata,
            BUSY      => busy,
            RDATA     => rdata,
            VALID     => valid,
            DRAM_CLK  => dram_clk,
            DRAM_CKE  => dram_cke,
            DRAM_CS_N => dram_cs_n,
            DRAM_RAS_N => dram_ras_n,
            DRAM_CAS_N => dram_cas_n,
            DRAM_WE_N => dram_we_n,
            DRAM_BA_0 => dram_ba_0,
            DRAM_BA_1 => dram_ba_1,
            DRAM_ADDR => dram_addr,
            DRAM_DQ   => dram_dq,
            DRAM_UDQM => dram_udqm,
            DRAM_LDQM => dram_ldqm
        );

    -- Tri-state simulation for DRAM_DQ: controller drives on writes, test drives on reads
    dram_dq <= dram_dq_out when dram_dq_oe = '1' else (others => 'Z');

    -- Clock generation: 50 MHz (20 ns period)
    clk_proc : process
    begin
        clk <= '0';
        wait for 10 ns;
        clk <= '1';
        wait for 10 ns;
    end process;

    -- Main stimulus process
    stim_proc : process
    begin
        -- Reset for a few cycles
        rst_n <= '0';
        req   <= '0';
        we    <= '0';
        wait for 100 ns;
        rst_n <= '1';

        report "=== SDRAM Test Bench Started ===" severity note;

        -- Wait for SDRAM initialization (BUSY should go low after ~250 us)
        report "Waiting for SDRAM initialization..." severity note;
        wait until busy = '0';
        wait for 100 ns;  -- extra margin
        report "SDRAM initialized, BUSY is now LOW" severity note;

        -- =====================================================================
        -- TEST 1: WRITE operation
        -- =====================================================================
        report "TEST 1: WRITE to address 0x00_0000 with data 0xABCD" severity note;
        addr  <= "00" & x"00000";  -- address 0x00_0000
        wdata <= x"ABCD";
        we    <= '1';              -- write mode
        req   <= '1';              -- request
        wait for 20 ns;            -- one clock cycle
        req   <= '0';              -- deassert request
        
        report "Waiting for write to complete..." severity note;
        wait until busy = '0';     -- wait for SDRAM to finish write
        wait for 100 ns;
        report "Write completed, BUSY is now LOW" severity note;

        -- =====================================================================
        -- TEST 2: READ operation
        -- =====================================================================
        report "TEST 2: READ from address 0x10_0000" severity note;
        addr  <= "00" & x"10000";  -- address 0x10_0000
        we    <= '0';              -- read mode
        req   <= '1';              -- request
        wait for 20 ns;            -- one clock cycle
        req   <= '0';              -- deassert request
        
        report "Waiting for read to latch CAS latency..." severity note;
        -- During read, we need to provide dummy data on DRAM_DQ after CAS latency
        -- The controller will sample DRAM_DQ when VALID goes high
        -- Provide dummy read data: 0x1234
        wait for 80 ns;            -- wait ~4 cycles for activation and CAS latency
        dram_dq_out <= x"1234";
        dram_dq_oe  <= '1';
        
        wait until valid = '1';    -- wait for read data valid
        report "Read completed, VALID is now HIGH, RDATA = 0x" severity note;
        wait for 20 ns;
        dram_dq_oe  <= '0';        -- release DRAM_DQ
        
        wait until busy = '0';     -- wait for SDRAM to return to idle
        wait for 100 ns;
        report "Read cycle finished, BUSY is now LOW" severity note;

        -- =====================================================================
        -- End simulation
        -- =====================================================================
        report "=== All Tests Completed ===" severity note;
        wait;

    end process;

    -- Monitor process to log important signals
    monitor_proc : process(clk)
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;

            -- Log when BUSY or VALID change
            if busy = '0' and req = '1' then
                report "Cycle " & integer'image(cycle_count) & 
                        ": Request accepted (BUSY becoming high on next cycle)" 
                        severity note;
            end if;

            if valid = '1' then
                report "Cycle " & integer'image(cycle_count) & 
                        ": VALID pulse - RDATA = 0x" severity note;
            end if;

            if busy = '0' and req = '0' then
                -- Monitor for state transitions (optional detailed logging)
                -- Can be expanded to show command sequences
            end if;
        end if;
    end process;

end architecture;
