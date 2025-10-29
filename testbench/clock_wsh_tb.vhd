library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity clock_wsh_tb is
end clock_wsh_tb;

architecture tb of clock_wsh_tb is
    -- Clock period
    constant CLK_PERIOD : time := 20 ns;  -- 50MHz system clock
    
    -- Component signals
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '0';
    signal m_cyc_o     : std_logic;
    signal m_ack_i     : std_logic := '0';
    signal auto_ticks  : std_logic_vector(31 downto 0) := (others => '0');
    signal man_sel     : std_logic := '0';
    signal man_start   : std_logic := '0';
    signal cpu_clock   : std_logic;
    
    -- Test control signals
    signal sim_done    : boolean := false;
    
begin
    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not sim_done else '0';
    
    -- DUT instantiation
    DUT: entity work.CLOCK_WSH_M
        port map (
            CLK        => clk,
            RESET      => reset,
            M_CYC_O    => m_cyc_o,
            M_ACK_I    => m_ack_i,
            AUTO_TICKS => auto_ticks,
            MAN_SEL    => man_sel,
            MAN_START  => man_start,
            CPU_CLOCK  => cpu_clock
        );
        
    -- Stimulus process
    stim_proc: process
        -- Helper procedure to check automatic mode
        procedure check_auto_mode(constant ticks : in integer) is
        begin
            report "Testing automatic mode with " & integer'image(ticks) & " ticks";
            man_sel <= '0';
            auto_ticks <= std_logic_vector(to_unsigned(ticks, 32));
            
            -- Wait for bus request
            wait until rising_edge(clk) and m_cyc_o = '1';
            wait for CLK_PERIOD * 2;  -- Simulate arbiter delay
            m_ack_i <= '1';  -- Grant bus
            
            -- Wait until bus is released
            wait until rising_edge(clk) and m_cyc_o = '0';
                
            m_ack_i <= '0'; -- simulate arbiter removal of grant
            wait for CLK_PERIOD * 2;
        end procedure;
        
        -- Helper procedure to check manual mode
        procedure check_manual_mode(constant hold_cycles : in integer) is
        begin
            report "Testing manual mode with " & integer'image(hold_cycles) & " cycles hold time";
            man_sel <= '1';
            
            -- Wait for bus request
            wait until rising_edge(clk) and m_cyc_o = '1';
            wait for CLK_PERIOD * 2;  -- Simulate arbiter delay
            m_ack_i <= '1';  -- Grant bus
            
            -- Assert manual start
            wait for CLK_PERIOD * 2;
            man_start <= '1';
            
            -- Hold for specified cycles
            wait for CLK_PERIOD * hold_cycles;
            
            -- Release manual start
            man_start <= '0';
            
            -- Verify bus is released
            wait for CLK_PERIOD * 2;
            assert m_cyc_o = '0'
                report "Bus not released after manual signal deasserted"
                severity error;
                
            m_ack_i <= '0'; -- simulate arbiter removal of grant
            wait for CLK_PERIOD * 2;
        end procedure;
        
    begin
        -- Reset sequence
        reset <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test automatic mode with different tick counts
        check_auto_mode(40);
        check_auto_mode(40);
        check_auto_mode(40);

        man_sel <= '0';
        auto_ticks <= std_logic_vector(to_unsigned(40, 32)); 
        -- Wait for bus request
        wait until rising_edge(clk) and m_cyc_o = '1';
        wait for CLK_PERIOD * 2;  -- Simulate arbiter delay
        m_ack_i <= '1';  -- Grant bus

        -- reset during operation
        wait for CLK_PERIOD * 10;
        reset <= '1';
        wait for CLK_PERIOD * 2;
        m_ack_i <= '0';
        reset <= '0';

        check_manual_mode(10);

        -- End simulation
        report "Simulation complete";
        sim_done <= true;
        wait;
    end process;
end tb;