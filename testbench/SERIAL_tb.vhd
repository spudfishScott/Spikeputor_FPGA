-- Testbench for SERIAL UART module
-- Tests receiving functionality at 230400 baud
-- Includes buffer overflow scenario and overflow flag clearing

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity SERIAL_tb is
end SERIAL_tb;

architecture testbench of SERIAL_tb is

    constant CLK_SPEED : integer := 50_000_000;
    constant BAUD_RATE : integer := 230400;
    constant BIT_PERIOD_NS : integer := (1_000_000_000 / BAUD_RATE);  -- bit period in nanoseconds
    constant CLK_PERIOD_NS : integer := 20;  -- 50 MHz clock
    constant BIT_PERIOD_CYCLES : integer := (CLK_SPEED / BAUD_RATE);  -- ~217 cycles
    
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal baud : std_logic_vector(3 downto 0) := (others => '0');
    signal flush : std_logic := '0';
    signal cmd : std_logic := '0';
    signal rx_serial : std_logic := '1';
    signal rx_data : std_logic_vector(7 downto 0);
    signal rx_ready : std_logic_vector(3 downto 0);
    signal rx_next : std_logic := '0';
    signal rx_overflow : std_logic;
    
    -- TX signals (not used in this test, just tie off)
    signal tx_serial : std_logic;
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_load : std_logic := '0';
    signal tx_busy : std_logic;
    
    -- Test data array - 64 bytes
    type data_array is array(0 to 63) of std_logic_vector(7 downto 0);
    constant test_data : data_array := (
        X"41", X"42", X"43", X"44", X"45", X"46", X"47", X"48",  -- ABCDEFGH
        X"49", X"4A", X"4B", X"4C", X"4D", X"4E", X"4F", X"50",  -- IJKLMNOP
        X"51", X"52", X"53", X"54", X"55", X"56", X"57", X"58",  -- QRSTUVWX
        X"59", X"5A", X"30", X"31", X"32", X"33", X"34", X"35",  -- YZ012345
        X"36", X"37", X"38", X"39", X"AA", X"BB", X"CC", X"DD",  -- 6789AABBCCDD
        X"EE", X"FF", X"11", X"22", X"33", X"44", X"55", X"66",  -- EEFF112233445566
        X"77", X"88", X"99", X"DE", X"AD", X"BE", X"EF", X"CA",  -- 7788 99DEADBEEFCA
        X"FE", X"BA", X"BE", X"D0", X"0D", X"BE", X"EF", X"ED"   -- FEBABEDOODBEEFED
    );

    -- Function to convert std_logic_vector byte to hex string
    function byte_to_hex(byte_val : std_logic_vector(7 downto 0)) return string is
        variable high_nibble, low_nibble : std_logic_vector(3 downto 0);
        variable hex_char : string(1 to 2);
    begin
        high_nibble := byte_val(7 downto 4);
        low_nibble := byte_val(3 downto 0);
        
        case high_nibble is
            when "0000" => hex_char(1) := '0';
            when "0001" => hex_char(1) := '1';
            when "0010" => hex_char(1) := '2';
            when "0011" => hex_char(1) := '3';
            when "0100" => hex_char(1) := '4';
            when "0101" => hex_char(1) := '5';
            when "0110" => hex_char(1) := '6';
            when "0111" => hex_char(1) := '7';
            when "1000" => hex_char(1) := '8';
            when "1001" => hex_char(1) := '9';
            when "1010" => hex_char(1) := 'A';
            when "1011" => hex_char(1) := 'B';
            when "1100" => hex_char(1) := 'C';
            when "1101" => hex_char(1) := 'D';
            when "1110" => hex_char(1) := 'E';
            when "1111" => hex_char(1) := 'F';
            when others => hex_char(1) := '?';
        end case;
        
        case low_nibble is
            when "0000" => hex_char(2) := '0';
            when "0001" => hex_char(2) := '1';
            when "0010" => hex_char(2) := '2';
            when "0011" => hex_char(2) := '3';
            when "0100" => hex_char(2) := '4';
            when "0101" => hex_char(2) := '5';
            when "0110" => hex_char(2) := '6';
            when "0111" => hex_char(2) := '7';
            when "1000" => hex_char(2) := '8';
            when "1001" => hex_char(2) := '9';
            when "1010" => hex_char(2) := 'A';
            when "1011" => hex_char(2) := 'B';
            when "1100" => hex_char(2) := 'C';
            when "1101" => hex_char(2) := 'D';
            when "1110" => hex_char(2) := 'E';
            when "1111" => hex_char(2) := 'F';
            when others => hex_char(2) := '?';
        end case;
        
        return hex_char;
    end function;

begin

    uut : entity work.SERIAL
        generic map (
            CLK_SPEED => CLK_SPEED,
            DEFAULT_BAUD => BAUD_RATE
        )
        port map (
            CLK => clk,
            RST => rst,
            BAUD => baud,
            FLUSH => flush,
            CMD => cmd,
            RX_SERIAL => rx_serial,
            RX_DATA => rx_data,
            RX_READY => rx_ready,
            RX_NEXT => rx_next,
            RX_OVERFLOW => rx_overflow,
            TX_SERIAL => tx_serial,
            TX_DATA => tx_data,
            TX_LOAD => tx_load,
            TX_BUSY => tx_busy
        );

    -- ==========================================
    -- Clock generation: 50 MHz
    -- ==========================================
    clock_process : process
    begin
        loop
            clk <= '0';
            wait for CLK_PERIOD_NS / 2 * 1 ns;
            clk <= '1';
            wait for CLK_PERIOD_NS / 2 * 1 ns;
        end loop;
    end process;

    -- ==========================================
    -- Reset process
    -- ==========================================
    reset_process : process
    begin
        rst <= '1';
        wait for 200 ns;  -- Hold reset for 200 ns
        rst <= '0';
        wait;
    end process;

    -- ==========================================
    -- UART RX Serial Data Transmission Process
    -- Sends 64 bytes of test data at specified baud rate
    -- ==========================================
    transmit_process : process
        variable bit_index : integer;
        variable byte_data : std_logic_vector(7 downto 0);
    begin
        -- Wait for reset to complete
        wait until rst = '0';
        wait for 1.5 us;
        
        report "Starting transmission of 64 test bytes at 230400 baud" severity note;
        
        -- Transmit 64 bytes
        for byte_idx in 0 to 63 loop
            byte_data := test_data(byte_idx);
            
            -- Start bit (0)
            rx_serial <= '0';
            wait for BIT_PERIOD_NS * 1 ns;
            
            -- 8 data bits (LSB first)
            for bit_idx in 0 to 7 loop
                rx_serial <= byte_data(bit_idx);
                wait for BIT_PERIOD_NS * 1 ns;
            end loop;
            
            -- Stop bit (1)
            rx_serial <= '1';
            wait for BIT_PERIOD_NS * 1 ns;
            
            -- Inter-byte gap (small delay between consecutive bytes)
            wait for BIT_PERIOD_NS * 2 * 1 ns;
            
            if (byte_idx + 1) mod 16 = 0 then
                report "Transmitted " & integer'image(byte_idx + 1) & " bytes" severity note;
            end if;
        end loop;
        
        rx_serial <= '1';
        report "Transmission complete" severity note;
        wait;
    end process transmit_process;

    -- ==========================================
    -- Reader Process
    -- Reads bytes with strategic delays to demonstrate:
    -- 1. Normal operation with buffer having available data
    -- 2. Buffer filling up during long read delay
    -- 3. Buffer overflow when no reads occur
    -- 4. Overflow flag assertion
    -- 5. Overflow flag clearing via FLUSH
    -- 6. Recovery and reading remaining data
    -- ==========================================
    read_process : process
        variable bytes_read : integer := 0;
        variable ready_count : integer;
    begin
        -- Wait for reset to complete
        wait until rst = '0';
        
        -- Initialize: Set baud rate to 230400 (code "1000")
        baud <= "1000";
        cmd <= '1';
        wait for 20 ns;
        cmd <= '0';
        wait for 200 us;
        
        report "===== PHASE 1: Initial reads =====" severity note;
        -- Phase 1: Read first 5 bytes immediately as they arrive
        for i in 0 to 5 loop
            if to_integer(unsigned(rx_ready)) > 0 then
                wait for 3 ns;
                report "Read byte #" & integer'image(i+1) & ": 0x" & byte_to_hex(rx_data) & " (buffer had " & integer'image(to_integer(unsigned(rx_ready))) & " bytes)" severity note;
                rx_next <= '1';
                wait for 20 ns;
                rx_next <= '0';
                wait for 500 ns;  -- Small delay between reads
                bytes_read := bytes_read + 1;
            else
                wait until to_integer(unsigned(rx_ready)) > 0;
                -- wait for 3 ns;
                -- report "Read byte #" & integer'image(i+1) & ": 0x" & byte_to_hex(rx_data) & " (buffer had " & integer'image(to_integer(unsigned(rx_ready))) & " bytes)" severity note;
                -- rx_next <= '1';
                -- wait for 20 ns;
                -- rx_next <= '0';
                -- wait for 500 ns;  -- Small delay between reads
                -- bytes_read := bytes_read + 1;
            end if;
        end loop;
        
        report "===== PHASE 2: Long delay to allow buffer overflow =====" severity note;
        -- Phase 2: Long delay - stop reading to allow buffer to fill and overflow
        -- At 230400 baud, each byte takes ~43 us (start + 8 data + stop bits)
        -- With inter-byte gaps, roughly 55-60 us per byte total
        -- 16-byte buffer fills in ~880-960 us
        -- Delaying 2.5 ms ensures many bytes overflow the buffer
        wait for 2.5 ms;
        
        if rx_overflow = '1' then
            report "SUCCESS: RX_OVERFLOW flag is SET (buffer overflowed as expected)" severity note;
        else
            report "ERROR: RX_OVERFLOW flag should be SET but is not!" severity error;
        end if;
        
        report "RX_READY count: " & integer'image(to_integer(unsigned(rx_ready))) severity note;
        
        report "===== PHASE 3: Flush buffer and clear overflow flag =====" severity note;
        -- Phase 3: Issue FLUSH command to clear overflow
        cmd <= '1';
        flush <= '1';
        wait for 20 ns;
        cmd <= '0';
        flush <= '0';
        wait for 20 ns;
        
        if rx_overflow = '0' then
            report "SUCCESS: RX_OVERFLOW flag is CLEARED after FLUSH" severity note;
        else
            report "ERROR: RX_OVERFLOW flag should be cleared but is still set!" severity error;
        end if;
        
        report "RX_READY count after flush: " & integer'image(to_integer(unsigned(rx_ready))) severity note;
        
        report "===== PHASE 4: Read remaining data =====" severity note;
        -- Phase 4: After overflow and reset, the buffer has been cleared
        -- New data will continue to arrive and be buffered
        -- Wait a bit for new data to arrive and then read it
        wait for 50 us;
        
        ready_count := to_integer(unsigned(rx_ready));
        report "Bytes available in buffer: " & integer'image(ready_count) severity note;

        -- Read up to 50 more bytes (or until none available)
        for i in 0 to 100000 loop
            if to_integer(unsigned(rx_ready)) > 0 then
                report "Read byte #" & integer'image(bytes_read + 1) & ": 0x" & byte_to_hex(rx_data) severity note;
                rx_next <= '1';
                wait for 20 ns;
                rx_next <= '0';
                wait for 100 ns;
                bytes_read := bytes_read + 1;
            end if;
            wait for 20 ns;
        end loop;
        
        report "===== TEST COMPLETE =====" severity note;
        report "Total bytes successfully read: " & integer'image(bytes_read) & " (out of 64 transmitted)" severity note;
        report "Note: Some bytes were lost due to buffer overflow in Phase 2" severity note;
        
        wait;
    end process read_process;

end architecture testbench;
