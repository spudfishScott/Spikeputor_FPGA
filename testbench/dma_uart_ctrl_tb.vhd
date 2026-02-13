library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_uart_ctrl_tb is
end entity dma_uart_ctrl_tb;

architecture testbench of dma_uart_ctrl_tb is

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

    -- Constants
    constant CLK_PERIOD : time := 20 ns;        -- 50 MHz clock
    constant BAUD_RATE : integer := 38400;
    constant BAUD_PERIOD : time := 26041 ns;    -- 1/38400 sec ≈ 26 us per bit
    constant HALF_BAUD : time := 13020 ns;      -- Half baud period

    -- Signals
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    
    -- UART signals
    signal rx_serial  : std_logic := '1';
    signal tx_serial  : std_logic := '1';
    
    -- DMA control signals
    signal start      : std_logic;
    signal wr_rd      : std_logic;
    signal address    : std_logic_vector(23 downto 0);
    signal length     : std_logic_vector(15 downto 0);
    signal wr_data    : std_logic_vector(15 downto 0);
    signal wr_ready   : std_logic;
    signal rd_data    : std_logic_vector(15 downto 0) := (others => '0');
    signal rd_ready   : std_logic := '0';
    signal reset_req  : std_logic;

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

    -- UART receive procedure: receive a byte serially
    procedure uart_receive_byte(
        signal rx_line : in std_logic;
        byte_val : out std_logic_vector(7 downto 0)
    ) is
    begin
        -- wait for start bit (line goes low)
        wait until rx_line = '0';
        -- wait for HALF_BAUD;

        -- sample 8 data bits, each 1 bit period apart
        for i in 0 to 7 loop
            byte_val(i) := rx_line;
            wait for BAUD_PERIOD;  -- Move to center of next bit
        end loop;
    end procedure;

begin

    -- Instantiate the DMA UART Controller
    dut: entity work.dma_uart_ctrl
        generic map (
            CLK_FREQ => 50_000_000
        )
        port map (
            CLK       => clk,
            RST       => rst,
            RX_SERIAL => rx_serial,
            TX_SERIAL => tx_serial,
            START     => start,
            WR_RD     => wr_rd,
            ADDRESS   => address,
            LENGTH    => length,
            WR_DATA   => wr_data,
            WR_READY  => wr_ready,
            RD_DATA   => rd_data,
            RD_READY  => rd_ready,
            RESET_REQ => reset_req
        );

    -- Clock generation
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Test process
    test_process: process
        variable rx_byte : std_logic_vector(7 downto 0);
        variable i : integer;
    begin
        -- Reset
        rst <= '1';
        rx_serial <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        report "=== TEST 1: ACK Command ('*') ===" severity note;
        uart_send_byte(x"2A", rx_serial);  -- send '*'
        -- uart_receive_byte(tx_serial, rx_byte);  -- receive '*'
        -- report "Received: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        wait for 1 us;

        report "=== TEST 2: RESET Command ('!') ===" severity note;
        uart_send_byte(x"21", rx_serial);  -- send '!'
        -- uart_receive_byte(tx_serial, rx_byte);  -- receive '*'
        -- report "Received ACK: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        -- wait for 10 us;
        report "RESET_REQ triggered: " & to_string(reset_req) severity note;
        wait for 2 ms;

        report "=== TEST 3: READ Command ('>') ===" severity note;
        -- Send read command
        uart_send_byte(x"3E", rx_serial);  -- send '>'
        -- uart_receive_byte(tx_serial, rx_byte);  -- receive '*'
        -- report "Received ACK: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        
        -- Send 5-byte header: address 0x123456, length 0x0010 (16 bytes)
        wait for 100 ns;
        uart_send_byte(x"12", rx_serial);  -- address high byte
        uart_send_byte(x"34", rx_serial);  -- address mid byte
        uart_send_byte(x"56", rx_serial);  -- address low byte
        uart_send_byte(x"00", rx_serial);  -- length high byte
        uart_send_byte(x"10", rx_serial);  -- length low byte (16 bytes)
        
        -- Wait for START strobe
        -- wait until start = '1';
        report "DMA START strobed. Address: " & to_hex_string(address) & 
                ", Length: " & to_hex_string(length) severity note;
        
        -- Simulate DMA read response: provide data for 8 words (16 bytes)
        for word_idx in 0 to 7 loop
            rd_data <= std_logic_vector(to_unsigned(word_idx * 256 + word_idx+1, 16));
            rd_ready <= '1';
            wait for CLK_PERIOD;
            rd_ready <= '0';
            wait until wr_ready = '1';
            report "Word " & integer'image(word_idx) & " sent: " & 
                    to_hex_string(rd_data) severity note;
            wait for 100 ns;
            
            -- Receive the two bytes from UART
            -- uart_receive_byte(tx_serial, rx_byte);
            -- report "  RX byte (high): " & to_hex_string(rx_byte) severity note;
            -- uart_receive_byte(tx_serial, rx_byte);
            -- report "  RX byte (low): " & to_hex_string(rx_byte) severity note;
        end loop;
        
        -- Receive final ACK
        -- uart_receive_byte(tx_serial, rx_byte);
        -- report "Final ACK: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        wait for 1 us;

        report "=== TEST 4: WRITE Command ('<') ====" severity note;
        -- Send write command
        uart_send_byte(x"3C", rx_serial);  -- send '<'
        -- uart_receive_byte(tx_serial, rx_byte);  -- receive '*'
        -- report "Received ACK: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        
        -- Send 5-byte header: address 0xABCDEF, length 0x0008 (8 bytes = 4 words)
        wait for 100 ns;
        uart_send_byte(x"AB", rx_serial);  -- address high byte
        uart_send_byte(x"CD", rx_serial);  -- address mid byte
        uart_send_byte(x"EF", rx_serial);  -- address low byte
        uart_send_byte(x"00", rx_serial);  -- length high byte
        uart_send_byte(x"08", rx_serial);  -- length low byte (8 bytes)
        
        -- Wait for START strobe
        -- wait until start = '1';
        report "DMA START strobed (WRITE). Address: " & to_hex_string(address) & 
                ", Length: " & to_hex_string(length) & ", WR_RD: " & to_string(wr_rd) severity note;
        wait for 100 ns;
        
        -- Send 4 words (8 bytes) of data
        for word_idx in 0 to 3 loop
            uart_send_byte(std_logic_vector(to_unsigned(word_idx * 17, 8)), rx_serial);  -- high byte
            uart_send_byte(std_logic_vector(to_unsigned(word_idx * 17 + 1, 8)), rx_serial);  -- low byte
            
            -- Wait for WR_READY strobe and capture written data
            -- wait until wr_ready = '1';
            report "Word " & integer'image(word_idx) & " written: " & 
                    to_hex_string(wr_data) severity note;
            
            -- Set RD_READY to allow next write
            rd_ready <= '1';
            wait for CLK_PERIOD;
            rd_ready <= '0';
        end loop;
        
        -- Receive final ACK
        -- uart_receive_byte(tx_serial, rx_byte);
        -- report "Final ACK: " & to_hex_string(rx_byte) & " (expected 2A)" severity note;
        wait for 1 us;

        report "=== All Tests Complete ===" severity note;
        wait;
    end process;

end architecture testbench;
