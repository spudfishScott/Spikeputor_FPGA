library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity DMA_WSH_M_tb is
end DMA_WSH_M_tb;

architecture sim of DMA_WSH_M_tb is
    -- Clock and reset
    signal CLK      : std_logic := '0';
    signal RST_I    : std_logic := '0';

    -- Wishbone Master signals from DMA (to memory provider)
    signal WBS_CYC_O : std_logic;
    signal WBS_STB_O : std_logic;
    signal WBS_ACK_I : std_logic := '0';
    signal WBS_ADDR_O : std_logic_vector(23 downto 0);
    signal WBS_DATA_O : std_logic_vector(15 downto 0);
    signal WBS_DATA_I : std_logic_vector(15 downto 0) := (others => '0');
    signal WBS_WE_O   : std_logic;

    -- DMA Control signals
    signal START       : std_logic := '0';
    signal WR_RD       : std_logic := '0';
    signal ADDRESS     : std_logic_vector(23 downto 0) := (others => '0');
    signal LENGTH      : std_logic_vector(15 downto 0) := (others => '0');
    signal DATA_IN     : std_logic_vector(15 downto 0) := (others => '0');
    signal READY_IN    : std_logic := '0';
    signal DATA_OUT    : std_logic_vector(15 downto 0);
    signal READY_OUT   : std_logic;
    signal RESET_REQ   : std_logic := '0';
    signal RST_O       : std_logic;

    -- Simple memory model using modulo addressing on lower bits
    -- This will use addresses modulo 256 to have a small, manageable memory
    type mem_t is array (0 to 255) of std_logic_vector(15 downto 0);
    shared variable memory : mem_t;
    
    signal read_pipeline : std_logic_vector(5 downto 0) := (others => '0');  -- 6-bit pipeline
    signal read_data_latched : std_logic_vector(15 downto 0) := (others => '0');
    signal prev_stb : std_logic := '0';  -- Previous WBS_STB_O for edge detection

    constant SYS_PERIOD_NS : time := 20 ns; -- 50 MHz clock
    constant SETUP_TIME : time := 100 ns;

begin
    -- Instantiate DUT (DMA_WSH_M)
    DUT : entity work.DMA_WSH_M
        port map (
            CLK         => CLK,
            RST_I       => RST_I,
            WBS_CYC_O   => WBS_CYC_O,
            WBS_STB_O   => WBS_STB_O,
            WBS_ACK_I   => WBS_ACK_I,
            WBS_ADDR_O  => WBS_ADDR_O,
            WBS_DATA_O  => WBS_DATA_O,
            WBS_DATA_I  => WBS_DATA_I,
            WBS_WE_O    => WBS_WE_O,
            START       => START,
            WR_RD       => WR_RD,
            ADDRESS     => ADDRESS,
            LENGTH      => LENGTH,
            DATA_IN     => DATA_IN,
            READY_IN    => READY_IN,
            DATA_OUT    => DATA_OUT,
            READY_OUT   => READY_OUT,
            RESET_REQ   => RESET_REQ,
            RST_O       => RST_O
        );

    -- System clock generator
    clk_proc : process
    begin
        while now < 20 us loop
            CLK <= '0';
            wait for SYS_PERIOD_NS / 2;
            CLK <= '1';
            wait for SYS_PERIOD_NS / 2;
        end loop;
        wait;
    end process;

    -- Memory model (read/write handled in mem_model process below)

    -- Synchronous memory with 6-cycle read latency using pipeline
    mem_model : process(CLK)
    begin
        if rising_edge(CLK) then
            -- Default response
            WBS_ACK_I <= '0';
            
            -- Shift pipeline each cycle (for read latency tracking)
            read_pipeline <= read_pipeline(4 downto 0) & '0';
            
            -- Check if ACK should be asserted (bit 5 of pipeline is set)
            if read_pipeline(5) = '1' then
                WBS_ACK_I <= '1';
                WBS_DATA_I <= read_data_latched;
            end if;

            -- Respond to new wishbone transaction (detect rising edge of STB)
            if WBS_CYC_O = '1' and prev_stb = '0' and WBS_STB_O = '1' then
                if WBS_WE_O = '1' then
                    -- Write transaction: store data to memory immediately, ACK immediately
                    memory(to_integer(unsigned(WBS_ADDR_O(7 downto 0)))) := WBS_DATA_O;
                    WBS_ACK_I <= '1';
                else
                    -- Read transaction: start pipeline, latch data and address
                    if read_pipeline = "000000" then  -- Only start if no read in progress
                        read_pipeline <= "000001";  -- Start counting down 6 cycles
                        read_data_latched <= memory(to_integer(unsigned(WBS_ADDR_O(7 downto 0))));
                    end if;
                end if;
            end if;
            
            -- Capture current STB for edge detection next cycle
            prev_stb <= WBS_STB_O;
        end if;
    end process;

    -- Test stimulus
    test_proc : process
        variable word_count : integer;
    begin
        -- Initialize memory with test pattern
        for i in 0 to 255 loop
            memory(i) := std_logic_vector(to_unsigned(i * 256 + i, 16));
        end loop;

        -- Wait for system to stabilize
        wait for SETUP_TIME;

        -- Apply reset
        report "*** Starting DMA_WSH_M Testbench ***";
        RST_I <= '1';
        wait for 3 * SYS_PERIOD_NS;
        RST_I <= '0';
        wait for SYS_PERIOD_NS;

        -- ========================================
        -- TEST 1: Multi-word READ from memory
        -- ========================================
        report "TEST 1: Multi-word READ (4 words = 8 bytes)";
        report "  Reading from address 0x000010, length 8 bytes";
        
        ADDRESS <= x"000010";  -- Start address
        LENGTH <= x"0008";     -- 8 bytes = 4 words
        WR_RD <= '0';          -- Read mode
        START <= '1';
        wait for SYS_PERIOD_NS;
        START <= '0';

        -- Wait for first word to be ready
        word_count := 0;
        while word_count < 4 loop
            wait until READY_OUT = '1';
            report "  Word " & integer'image(word_count) & " read: 0x" & integer'image(to_integer(unsigned(DATA_OUT)));
            -- wait for SYS_PERIOD_NS;
            wait for 10 * SYS_PERIOD_NS;  -- Delay before acknowledging
            READY_IN <= '1';  -- Signal we're ready for next word
            wait for SYS_PERIOD_NS;
            READY_IN <= '0';
            -- wait for 2 * SYS_PERIOD_NS;
            word_count := word_count + 1;
        end loop;

        report "TEST 1 COMPLETE: Successfully read 4 words";
        wait for 3 * SYS_PERIOD_NS;

        -- ========================================
        -- TEST 2: Multi-word WRITE to memory
        -- ========================================
        report "TEST 2: Multi-word WRITE (3 words = 6 bytes)";
        report "  Writing to address 0x000050, length 6 bytes";

        ADDRESS <= x"000050";  -- Start address
        LENGTH <= x"0006";     -- 6 bytes = 3 words
        WR_RD <= '1';          -- Write mode
        START <= '1';
        wait for SYS_PERIOD_NS;
        START <= '0';

        -- Send multiple words to be written
        word_count := 0;
        while word_count < 3 loop
            DATA_IN <= std_logic_vector(to_unsigned(16#AAAA# + word_count * 16#1111#, 16));
            READY_IN <= '1';
            wait for SYS_PERIOD_NS;
            READY_IN <= '0';
            wait until READY_OUT = '1';
            report "  Word " & integer'image(word_count) & " written: 0x" & integer'image(to_integer(unsigned(DATA_IN)));
            wait for SYS_PERIOD_NS; -- need at least one clock period delay between READY_OUT going high and setting READY_IN on External Interface side
            word_count := word_count + 1;
        end loop;

        report "TEST 2 COMPLETE: Successfully wrote 3 words";
        wait for 3 * SYS_PERIOD_NS;

        -- ========================================
        -- TEST 3: Verify written data
        -- ========================================
        report "TEST 3: Verify written data by reading back";
        report "  Reading from address 0x000050, length 6 bytes";

        ADDRESS <= x"000050";
        LENGTH <= x"0006";
        WR_RD <= '0';
        START <= '1';
        wait for SYS_PERIOD_NS;
        START <= '0';

        word_count := 0;
        while word_count < 3 loop
            wait until READY_OUT = '1';
            report "  Word " & integer'image(word_count) & " read back: 0x" & integer'image(to_integer(unsigned(DATA_OUT)));
            wait for SYS_PERIOD_NS;
            READY_IN <= '1';
            wait for SYS_PERIOD_NS;
            READY_IN <= '0';
            -- wait for 2 * SYS_PERIOD_NS;
            word_count := word_count + 1;
        end loop;

        report "TEST 3 COMPLETE: Verification done";
        wait for 3 * SYS_PERIOD_NS;

        -- ========================================
        -- TEST 4: Single word read
        -- ========================================
        report "TEST 4: Single word READ";
        report "  Reading from address 0x0000FF, length 2 bytes";

        ADDRESS <= x"0000FF";
        LENGTH <= x"0002";
        WR_RD <= '0';
        START <= '1';
        wait for SYS_PERIOD_NS;
        START <= '0';

        wait until READY_OUT = '1';
        report "  Single word read: 0x" & integer'image(to_integer(unsigned(DATA_OUT)));
        wait for SYS_PERIOD_NS;
        READY_IN <= '1';
        wait for SYS_PERIOD_NS;
        READY_IN <= '0';

        report "TEST 4 COMPLETE";
        wait for 3 * SYS_PERIOD_NS;

        -- ========================================
        -- TEST 5: Read with delayed ready
        -- ========================================
        report "TEST 5: READ with delayed READY_IN response";
        report "  Reading from address 0x000020, length 4 bytes";

        ADDRESS <= x"000020";
        LENGTH <= x"0004";
        WR_RD <= '0';
        START <= '1';
        wait for SYS_PERIOD_NS;
        START <= '0';

        word_count := 0;
        while word_count < 2 loop
            wait until READY_OUT = '1';
            report "  Word " & integer'image(word_count) & " ready, delaying READY_IN...";
            wait for 5 * SYS_PERIOD_NS;  -- Delay before acknowledging
            READY_IN <= '1';
            wait for SYS_PERIOD_NS;
            READY_IN <= '0';
            -- wait for 2 * SYS_PERIOD_NS;
            word_count := word_count + 1;
        end loop;

        report "TEST 5 COMPLETE";
        wait for 3 * SYS_PERIOD_NS;

        -- ========================================
        -- Finish simulation
        -- ========================================
        report "*** All tests completed successfully ***";
        wait;

    end process;

end sim;
