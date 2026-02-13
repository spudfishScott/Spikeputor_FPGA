library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity DMA_WSH_M2_tb is
end DMA_WSH_M2_tb;

architecture sim of DMA_WSH_M2_tb is
     -- Function to convert std_logic_vector to hex string
    function to_hex_string(value : std_logic_vector) return string is
        variable result : string(1 to (value'length + 3) / 4);
        variable temp : integer;
        variable hex_char : string(1 to 16) := "0123456789ABCDEF";
    begin
        for i in 0 to (value'length - 1) / 4 loop
            if (i * 4 + 3) < value'length then
                temp := to_integer(unsigned(value((i + 1) * 4 - 1 downto i * 4)));
            else
                temp := to_integer(unsigned(value(value'length - 1 downto i * 4)));
            end if;
            result(result'length - i) := hex_char(temp + 1);
        end loop;
        return result;
    end function;

    -- Function to convert std_logic to string
    function to_string(value : std_logic) return string is
    begin
        if value = '1' then
            return "1";
        else
            return "0";
        end if;
    end function;

    -- Clock and reset
    signal CLK      : std_logic := '0';
    signal RST_I    : std_logic := '0';

    -- Wishbone Master signals from DMA (to memory provider)
    signal WBS_CYC_O  : std_logic;
    signal WBS_STB_O  : std_logic;
    signal WBS_ACK_I  : std_logic := '0';
    signal WBS_ADDR_O : std_logic_vector(23 downto 0);
    signal WBS_DATA_O : std_logic_vector(15 downto 0);
    signal WBS_DATA_I : std_logic_vector(15 downto 0) := (others => '0');
    signal WBS_WE_O   : std_logic;

    signal RX_SERIAL  : std_logic;                         -- external UART RX
    signal TX_SERIAL  : std_logic;                         -- external UART TX
    signal RST_O      : std_logic;                         -- DMA signal to reset the Spikeputor

    -- Simple memory model using modulo addressing on lower bits
    -- This will use addresses modulo 256 to have a small, manageable memory
    type mem_t is array (0 to 255) of std_logic_vector(15 downto 0);
    shared variable memory : mem_t;
    
    signal read_pipeline : std_logic_vector(5 downto 0) := (others => '0');  -- 6-bit pipeline
    signal read_data_latched : std_logic_vector(15 downto 0) := (others => '0');
    signal prev_stb : std_logic := '0';  -- Previous WBS_STB_O for edge detection

    constant SYS_PERIOD_NS : time := 20 ns; -- 50 MHz clock
    constant SETUP_TIME : time := 100 ns;

    constant BAUD_PERIOD : time := 1000 ns; --4340 ns;    -- 1/230400 sec

    -- UART transmit procedure: send a byte serially (LSB first)
    procedure uart_send_byte(
        byte_val : in std_logic_vector(7 downto 0);
        signal tx_line : out std_logic
    ) is
    begin
        -- start bit (low)
        tx_line <= '0';
        wait for BAUD_PERIOD;
        
        -- 8 data bits
        for i in 0 to 7 loop
            tx_line <= byte_val(i);
            wait for BAUD_PERIOD;
        end loop;
        
        -- stop bit (high)
        tx_line <= '1';
        wait for BAUD_PERIOD;
    end procedure;


begin
    -- Instantiate DUT (DMA_WSH_M)
    DUT : entity work.DMA_WSH_M
        generic map (
            CLK_FREQ  => 50_000_000,      -- 50 MHz clock frequency
            BAUD_RATE => 1000000--230400           -- Baud rate for UART communication
        )
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
            RX_SERIAL   => RX_SERIAL,
            TX_SERIAL   => TX_SERIAL,
            RST_O       => RST_O
        );

    -- System clock generator
    clk_proc : process
    begin
        CLK <= '0';
        wait for SYS_PERIOD_NS / 2;
        CLK <= '1';
        wait for SYS_PERIOD_NS / 2;
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
            memory(i) := std_logic_vector(to_unsigned(i * 256 + i + 1, 16));
        end loop;

        -- Wait for system to stabilize
        wait for SETUP_TIME;

        -- Apply reset
        report "*** Starting DMA_WSH_M Testbench ***";
        RST_I <= '1';
        wait for 3 * SYS_PERIOD_NS;
        RST_I <= '0';
        wait for SYS_PERIOD_NS;

        report "=== TEST 1: ACK Command ('*') ===" severity note;
        uart_send_byte(x"2A", RX_SERIAL);  -- send '*'
        wait for 100 us;

        report "=== TEST 2: RESET Command ('!') ===" severity note;
        uart_send_byte(x"21", rx_serial);  -- send '!'
        wait for 2100 us;

        report "=== TEST 3: READ Command ('>') ===" severity note;
        -- Send read command
        uart_send_byte(x"3E", rx_serial);  -- send '>'
        wait for 100 us; -- simulate waiting for ACK and processing

        -- Send 5-byte header: address 0x123456, length 0x0010 (16 bytes)
        wait for 100 ns;
        uart_send_byte(x"12", rx_serial);  -- address high byte
        uart_send_byte(x"34", rx_serial);  -- address mid byte
        uart_send_byte(x"56", rx_serial);  -- address low byte
        uart_send_byte(x"00", rx_serial);  -- length high byte
        uart_send_byte(x"10", rx_serial);  -- length low byte (16 bytes)
        
        report "Read Started. Address: 0x123456 " &
                ", Length: 0x0010" severity note;

        wait for 2 ms;

        report "=== TEST 4: WRITE Command ('<') ====" severity note;
        -- Send write command
        uart_send_byte(x"3C", rx_serial);  -- send '<'
        
        -- Send 5-byte header: address 0xABCDEF, length 0x0008 (8 bytes = 4 words)
        wait for 100 ns;
        uart_send_byte(x"AB", rx_serial);  -- address high byte
        uart_send_byte(x"CD", rx_serial);  -- address mid byte
        uart_send_byte(x"EF", rx_serial);  -- address low byte
        uart_send_byte(x"00", rx_serial);  -- length high byte
        uart_send_byte(x"08", rx_serial);  -- length low byte (8 bytes)
        
        report "Write Started. Address: 0xABCDEF" &
                ", Length: 0x0008" severity note;
        wait for 100 ns;
        
        -- Send 4 words (8 bytes) of data
        for word_idx in 0 to 3 loop
            uart_send_byte(std_logic_vector(to_unsigned(word_idx * 17, 8)), rx_serial);      -- high byte
            uart_send_byte(std_logic_vector(to_unsigned(word_idx * 17 + 1, 8)), rx_serial);  -- low byte
            
            report "Word " & integer'image(word_idx) & " written" severity note;
            wait for 100 ns;
        end loop;

        report "*** All tests completed successfully ***";
        wait;

    end process;

end sim;
