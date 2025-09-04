-- library ieee;
-- use ieee.std_logic_1164.all;
-- use ieee.numeric_std.all;

-- -- Include the REGARRAY type definition
-- type RARRAY is array(1 to 7) of std_logic_vector(15 downto 0);

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;


entity dotstar_driver2_tb is
end dotstar_driver2_tb;

architecture behavior of dotstar_driver2_tb is
    -- Constants
    constant CLK_PERIOD : time := 20 ns;  -- 50MHz clock
    constant NUM_SETS : integer := 20;      -- number of LED sets in the display array (or input arrays)
    constant LEDS_PER_SET : integer := 16;
    
    -- Component declaration
    component dotstar_driver is
        generic (
            XMIT_QUANTA : integer := 2
        );
        port (
            CLK      : in  std_logic;
            START    : in  std_logic;
            DISPLAY  : in  BIGRARRAY;  -- Changed to match RegFile.vhd definition
            COLOR    : in  std_logic_vector(23 downto 0);
            DATA_OUT : out std_logic;
            CLK_OUT  : out std_logic;
            BUSY     : out std_logic
        );
    end component;
    
    -- Signals
    signal clk      : std_logic := '0';
    signal start    : std_logic := '0';
    signal display  : BIGRARRAY;
    signal color    : std_logic_vector(23 downto 0) := x"FF0000";  -- Red
    signal data_out : std_logic;
    signal clk_out  : std_logic;
    signal busy     : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    
begin
    -- Instantiate DUT
    DUT: dotstar_driver
        generic map (
            XMIT_QUANTA => 1
        )
        port map (
            CLK      => clk,
            START    => start,
            DISPLAY  => display,
            COLOR    => color,
            DATA_OUT => data_out,
            CLK_OUT  => clk_out,
            BUSY     => busy
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
    
    -- Stimulus process
    stim_proc: process
    begin
        -- Initialize
        start <= '0';
        -- Set up display data - alternating pattern
        for i in 1 to NUM_SETS loop
            display(i) <= (others => '0');  -- Clear all
            for j in 0 to LEDS_PER_SET-1 loop
                if (i + j) mod 2 = 0 then
                    display(i)(j) <= '1';   -- Turn on every other LED
                end if;
            end loop;
        end loop;
        
        wait for CLK_PERIOD * 10;
        
        -- Test 1: Basic transmission with red LEDs
        report "Starting Test 1: Basic transmission with red LEDs";
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        
        -- Wait for transmission to complete
        wait until busy = '0';
        wait for CLK_PERIOD * 10;
        
        -- Test 2: Change color to green and retransmit
        report "Starting Test 2: Green LED transmission";
        color <= x"00FF00";  -- Green
        wait for CLK_PERIOD * 10;
        
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        
        -- Wait for transmission to complete
        wait until busy = '0';
        wait for CLK_PERIOD * 10;
        
        -- Test 3: All LEDs on with blue color
        report "Starting Test 3: All LEDs on with blue color";
        for i in 1 to NUM_SETS loop
            display(i) <= (others => '1');
        end loop;
        
        color <= x"0000FF";  -- Blue
        wait for CLK_PERIOD * 10;
        
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        
        -- Wait for transmission to complete
        wait until busy = '0';
        wait for CLK_PERIOD * 10;
        
        -- Test 4: Quick Start/Stop test
        report "Starting Test 4: Quick Start/Stop test";
        color <= x"FF00FF";  -- Purple
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';
        wait for CLK_PERIOD * 5;  -- Wait briefly
        start <= '1';  -- Start again while potentially still busy - should do nothing if busy
        wait for CLK_PERIOD;
        start <= '0';
        
        -- Wait for final transmission to complete
        wait until busy = '0';
        wait for CLK_PERIOD * 10;
        
        -- End simulation
        report "All tests completed";
        test_done <= true;
        wait;
    end process;
    
    -- Protocol monitor process
    monitor_proc: process
        variable bit_count : integer := 0;
        variable frame_type : string(1 to 20) := (others => ' ');
    begin
        wait until rising_edge(clk_out);
        
        if busy = '1' then
            if bit_count < 32 then
                frame_type := "Start Frame         ";
                assert data_out = '0'
                    report "Start frame should be all zeros"
                    severity error;
            end if;
            
            -- Could add more protocol verification here
            -- For example, verify LED frame format (0xFF + RGB)
            -- and end frame (all ones)
            
            bit_count := bit_count + 1;
        else
            bit_count := 0;
        end if;
        
        wait;
    end process;
    
end behavior;
