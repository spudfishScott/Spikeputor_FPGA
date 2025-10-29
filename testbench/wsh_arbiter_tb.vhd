library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity wsh_arbiter_tb is
end wsh_arbiter_tb;

architecture tb of wsh_arbiter_tb is
    -- Clock period definition
    constant CLK_PERIOD : time := 20 ns;
    
    -- Test signals
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '0';
    
    -- Master 0 (CPU) signals
    signal m0_cyc_o    : std_logic := '0';
    signal m0_stb_o    : std_logic := '0';
    signal m0_we_o     : std_logic := '0';
    signal m0_data_o   : std_logic_vector(15 downto 0) := x"AA00";
    signal m0_addr_o   : std_logic_vector(15 downto 0) := x"0000";
    signal m0_gnt      : std_logic;
    
    -- Master 1 (DMA) signals
    signal m1_cyc_o    : std_logic := '0';
    signal m1_stb_o    : std_logic := '0';
    signal m1_we_o     : std_logic := '0';
    signal m1_data_o   : std_logic_vector(15 downto 0) := x"BB00";
    signal m1_addr_o   : std_logic_vector(15 downto 0) := x"1000";
    signal m1_gnt      : std_logic;
    
    -- Master 2 (Clock) signals
    signal m2_cyc_o    : std_logic := '0';
    signal m2_gnt      : std_logic;
    
    -- Arbiter outputs
    signal cyc_o       : std_logic;
    signal stb_o       : std_logic;
    signal we_o        : std_logic;
    signal addr_o      : std_logic_vector(15 downto 0);
    signal data_o      : std_logic_vector(15 downto 0);
    
    -- Test control
    signal sim_done    : boolean := false;
    
begin
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';
    
    -- DUT instantiation
    DUT: entity work.WSH_ARBITER
        port map (
            CLK       => clk,
            RESET     => reset,
            
            M0_CYC_O  => m0_cyc_o,
            M0_STB_O  => m0_stb_o,
            M0_WE_O   => m0_we_o,
            M0_DATA_O => m0_data_o,
            M0_ADDR_O => m0_addr_o,
            M0_GNT    => m0_gnt,
            
            M1_CYC_O  => m1_cyc_o,
            M1_STB_O  => m1_stb_o,
            M1_WE_O   => m1_we_o,
            M1_DATA_O => m1_data_o,
            M1_ADDR_O => m1_addr_o,
            M1_GNT    => m1_gnt,
            
            M2_CYC_O  => m2_cyc_o,
            M2_GNT    => m2_gnt,
            
            CYC_O     => cyc_o,
            STB_O     => stb_o,
            WE_O      => we_o,
            ADDR_O    => addr_o,
            DATA_O    => data_o
        );
        
    -- Stimulus process
    stim_proc: process
        -- Helper procedure to request bus access
        procedure request_bus(
            signal cyc : out std_logic;
            signal stb : out std_logic;
            constant cycles : in integer) is
        begin
            cyc <= '1';
            stb <= '1';
            wait for CLK_PERIOD * cycles;
            cyc <= '0';
            stb <= '0';
            wait for CLK_PERIOD * 2;  -- Wait between requests
        end procedure;
        
        -- Helper procedure to verify grant signals
        procedure check_grant(
            signal gnt : in std_logic;
            constant expected : in std_logic;
            constant msg : in string) is
        begin
            assert gnt = expected
                report msg & ": expected " & std_logic'image(expected) & 
                      " but got " & std_logic'image(gnt)
                severity error;
        end procedure;
        
    begin
        -- Reset sequence
        reset <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 1: Single master access (M0)
        report "Test 1: Single master access (M0)";
        request_bus(m0_cyc_o, m0_stb_o, 5);
        check_grant(m0_gnt, '1', "M0 should be granted");
        
        -- Test 2: Two masters competing (M0 and M1)
        report "Test 2: Two masters competing";
        m0_cyc_o <= '1';
        m0_stb_o <= '1';
        wait for CLK_PERIOD * 2;
        m1_cyc_o <= '1';
        m1_stb_o <= '1';
        wait for CLK_PERIOD * 5;
        check_grant(m0_gnt, '1', "M0 should be granted first");
        m0_cyc_o <= '0';
        m0_stb_o <= '0';
        wait for CLK_PERIOD * 2;
        check_grant(m1_gnt, '1', "M1 should be granted after M0");
        m1_cyc_o <= '0';
        m1_stb_o <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 3: All masters competing
        report "Test 3: All masters competing";
        m1_cyc_o <= '1';
        m2_cyc_o <= '1';
        wait for CLK_PERIOD * 2;
        m0_cyc_o <= '1';
        
        check_grant(m1_gnt, '1', "M1 should be granted first");
        m1_cyc_o <= '0';
        wait for CLK_PERIOD * 2;
        
        check_grant(m2_gnt, '1', "M2 should be granted second");
        m2_cyc_o <= '0';
        wait for CLK_PERIOD * 2;

        check_grant(m0_gnt, '1', "M0 should be granted third");
        m0_cyc_o <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 4: Verify multiplexed outputs
        report "Test 4: Verify multiplexed outputs";
        -- Test M0's signals
        m0_we_o <= '1';
        m0_cyc_o <= '1';
        m0_stb_o <= '1';
        wait for CLK_PERIOD * 2;
        assert addr_o = x"0000" and data_o = x"AA00" and we_o = '1'
            report "M0's signals not properly multiplexed"
            severity error;
        m0_cyc_o <= '0';
        m0_stb_o <= '0';
        m0_we_o <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test M1's signals
        m1_we_o <= '1';
        m1_cyc_o <= '1';
        m1_stb_o <= '1';
        wait for CLK_PERIOD * 2;
        assert addr_o = x"1000" and data_o = x"BB00" and we_o = '1'
            report "M1's signals not properly multiplexed"
            severity error;
        m1_cyc_o <= '0';
        m1_stb_o <= '0';
        m1_we_o <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 5: Reset behavior
        report "Test 5: Reset behavior";
        m0_cyc_o <= '1';
        m1_cyc_o <= '1';
        m2_cyc_o <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '1';
        wait for CLK_PERIOD;
        check_grant(m0_gnt, '0', "M0 grant should be cleared on reset");
        check_grant(m1_gnt, '0', "M1 grant should be cleared on reset");
        check_grant(m2_gnt, '0', "M2 grant should be cleared on reset");
        reset <= '0';
        wait for CLK_PERIOD * 2;
        
        -- End simulation
        report "Testbench completed successfully";
        sim_done <= true;
        wait;
    end process;
    
    -- Monitor process
    monitor_proc: process
    begin
        wait until rising_edge(clk);
        -- Verify that only one master is granted at a time
        assert (to_integer(unsigned'('0' & m0_gnt) + 
                         unsigned'('0' & m1_gnt) + 
                         unsigned'('0' & m2_gnt)) <= 1)
            report "Multiple masters granted simultaneously"
            severity error;
            
        -- Verify CYC_O behavior
        if m0_gnt = '1' or m1_gnt = '1' or m2_gnt = '1' then
            assert cyc_o = '1'
                report "CYC_O should be asserted when a master is granted"
                severity error;
        end if;
    end process;

end tb;