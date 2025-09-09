library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

-- Test state values in waveform (current_test_num):
-- 0: TEST_INIT            - Initialization
-- 1: TEST_SINGLE_READ     - Single read test
-- 2: TEST_SEQUENTIAL_READ - Sequential reads test
-- 3: TEST_FLASH_BUSY      - Flash busy test
-- 4: TEST_EARLY_TERM      - Early termination test
-- 5: TEST_RESET_DURING_OP - Reset during operation test
-- 6: TEST_COMPLETE        - Tests complete

entity FlashROM_WSH_tb is
end FlashROM_WSH_tb;

architecture behavior of FlashROM_WSH_tb is
    -- Clock period definition
    constant CLK_PERIOD : time := 20 ns;  -- 50MHz clock
    
    -- Component declaration
    component FlashROM_WSH is
        generic (
            SECTOR_ADDR : std_logic_vector(5 downto 0)
        );
        port (
            -- SYSCON
            CLK         : in  std_logic;
            RST_I       : in  std_logic;
            -- Wishbone
            WBS_CYC_I   : in  std_logic;
            WBS_STB_I   : in  std_logic;
            WBS_ADDR_I  : in  std_logic_vector(15 downto 0);
            WBS_DATA_O  : out std_logic_vector(15 downto 0);
            WBS_ACK_O   : out std_logic;
            -- Flash signals
            WP_n        : out std_logic;
            BYTE_n      : out std_logic;
            RST_n       : out std_logic;
            CE_n        : out std_logic;
            OE_n        : out std_logic;
            WE_n        : out std_logic;
            BY_n        : in  std_logic;
            A           : out std_logic_vector(21 downto 0);
            Q           : in  std_logic_vector(15 downto 0)
        );
    end component;
    
    -- Signal declarations
    -- Control signals
    signal clk         : std_logic := '0';
    signal rst_i       : std_logic := '0';
    signal test_done   : boolean := false;
    
    -- Wishbone signals
    signal wbs_cyc_i   : std_logic := '0';
    signal wbs_stb_i   : std_logic := '0';
    signal wbs_addr_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal wbs_data_o  : std_logic_vector(15 downto 0);
    signal wbs_ack_o   : std_logic;
    
    -- Flash signals
    signal wp_n        : std_logic;
    signal byte_n      : std_logic;
    signal rst_n       : std_logic;
    signal ce_n        : std_logic;
    signal oe_n        : std_logic;
    signal we_n        : std_logic;
    signal by_n        : std_logic := '1';  -- Flash ready by default
    signal flash_a     : std_logic_vector(21 downto 0);
    signal flash_q     : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Test control
    type test_state_t is (
        TEST_INIT,
        TEST_SINGLE_READ,
        TEST_SEQUENTIAL_READS,
        TEST_FLASH_BUSY,
        TEST_EARLY_TERM,
        TEST_RESET_DURING_OP,
        TEST_COMPLETE
    );
    signal current_test: test_state_t := TEST_INIT;
    signal current_test_num: integer range 0 to 7 := 0;
    
begin
    -- Convert test state to number for waveform viewing
    process(current_test)
    begin
        case current_test is
            when TEST_INIT =>            current_test_num <= 0;
            when TEST_SINGLE_READ =>     current_test_num <= 1;
            when TEST_SEQUENTIAL_READS => current_test_num <= 2;
            when TEST_FLASH_BUSY =>      current_test_num <= 3;
            when TEST_EARLY_TERM =>      current_test_num <= 4;
            when TEST_RESET_DURING_OP => current_test_num <= 5;
            when TEST_COMPLETE =>        current_test_num <= 6;
        end case;
    end process;
    -- Instantiate DUT
    DUT: FlashROM_WSH
        generic map (
            SECTOR_ADDR => "000001"  -- Use default sector
        )
        port map (
            CLK         => clk,
            RST_I       => rst_i,
            WBS_CYC_I   => wbs_cyc_i,
            WBS_STB_I   => wbs_stb_i,
            WBS_ADDR_I  => wbs_addr_i,
            WBS_DATA_O  => wbs_data_o,
            WBS_ACK_O   => wbs_ack_o,
            WP_n        => wp_n,
            BYTE_n      => byte_n,
            RST_n       => rst_n,
            CE_n        => ce_n,
            OE_n        => oe_n,
            WE_n        => we_n,
            BY_n        => by_n,
            A           => flash_a,
            Q           => flash_q
        );
    
    -- Clock generation
    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    -- Simulate Flash memory behavior
    flash_sim: process(flash_a)
    begin
        -- Simulate some simple flash content
        case flash_a is
            when "000001" & x"0000" =>
                flash_q <= x"DEAD";
            when "000001" & x"0001" =>
                flash_q <= x"BEEF";
            when "000001" & x"0002" =>
                flash_q <= x"CAFE";
            when others =>
                flash_q <= x"0000";
        end case;
    end process;
    
    -- Stimulus process
    stim_proc: process
        -- Wishbone read procedure
        procedure wb_read(addr: in std_logic_vector(15 downto 0)) is
        begin
            wbs_addr_i <= addr;
            wbs_cyc_i <= '1';
            wbs_stb_i <= '1';
            wait until rising_edge(clk);
            wait until wbs_ack_o = '1';
            wait until rising_edge(clk);
            wbs_cyc_i <= '0';
            wbs_stb_i <= '0';
            wait for CLK_PERIOD*2;
        end procedure;
    begin
        -- Initialize
        current_test <= TEST_INIT;
        rst_i <= '1';
        wait for CLK_PERIOD * 2;
        rst_i <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 1: Single read
        current_test <= TEST_SINGLE_READ;
        wb_read(x"0000");  -- Should return DEAD
        assert wbs_data_o = x"DEAD"
            report "Test 1 failed: Expected DEAD, got " & integer'image(to_integer(unsigned(wbs_data_o)))
            severity error;
        wait for CLK_PERIOD * 2;
        
        -- Test 2: Sequential reads
        current_test <= TEST_SEQUENTIAL_READS;
        wb_read(x"0001");  -- BEEF
        wb_read(x"0002");  -- CAFE
        wb_read(x"0000");  -- DEAD
        wait for CLK_PERIOD * 2;
        
        -- Test 4: Early cycle termination
        current_test <= TEST_EARLY_TERM;
        wbs_addr_i <= x"0001";
        wbs_cyc_i <= '1';
        wbs_stb_i <= '1';
        wait for CLK_PERIOD;
        wbs_cyc_i <= '0';  -- Early termination
        wait for CLK_PERIOD * 2;
        
        -- Test 5: Reset during operation
        current_test <= TEST_RESET_DURING_OP;
        wbs_addr_i <= x"0001";
        wbs_cyc_i <= '1';
        wbs_stb_i <= '1';
        wait for CLK_PERIOD * 2;
        rst_i <= '1';
        wait for CLK_PERIOD * 2;
        wbs_cyc_i <= '0';
        wbs_stb_i <= '0';
        rst_i <= '0';
        wait for CLK_PERIOD * 2;
        
        -- End simulation
        current_test <= TEST_COMPLETE;
        wait for CLK_PERIOD * 10;
        test_done <= true;
        wait;
    end process;
    
    -- Monitor process
    monitor_proc: process
        variable last_cyc_time : time := 0 ns;
    begin
        wait until rising_edge(clk);
        
        -- Check Wishbone timing
        if wbs_cyc_i = '1' and wbs_stb_i = '1' then
            last_cyc_time := now;
        end if;
        
        -- Verify acknowledgment timing
        if wbs_ack_o = '1' then
            assert (now - last_cyc_time) <= (CLK_PERIOD * 10)
                report "Wishbone cycle took too long to complete"
                severity warning;
        end if;
        
        -- Verify protocol rules
        if wbs_ack_o = '1' then
            assert wbs_cyc_i = '1' and wbs_stb_i = '1'
                report "ACK asserted without valid cycle"
                severity error;
        end if;
        
        wait;
    end process;
    
end behavior;