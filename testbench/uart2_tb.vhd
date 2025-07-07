library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart2_tb is
end entity;

architecture tb of uart2_tb is

    constant CLK_PERIOD : time := 20 ns;
    constant CYCLES_PER_BIT : Integer := (50_000_000/115_200);  -- Calculate cycles per bit for 115200 baud rate

    -- shared signals
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';

    -- Signals for UART1 (receiver)
    signal tx_serial : std_logic;
    signal rx_serial : std_logic;
    
    signal tx_busy   : std_logic;
    signal tx_load   : std_logic := '0';
    signal rx1_byte  : std_logic_vector(7 downto 0);
    signal rx1_ready : std_logic;
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Clock generation
    clk_process : process
    begin
        while now < 2 ms loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Instantiate UART1 (Receiver)
    uart1 : entity work.UART
        generic map (
            CLK_SPEED => 50_000_000,
            BAUD_RATE => 115_200
        )
        port map (
            CLK        => clk,
            RST        => rst,
            RX_SERIAL  => tx_serial,
            RX_DATA    => rx1_byte,
            RX_READY   => rx1_ready,
            TX_SERIAL  => rx_serial,
            TX_DATA    => tx_data,              -- Data to send through UART
            TX_LOAD    => tx_load,
            TX_BUSY    => tx_busy
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- Reset
        rst <= '1';
        tx_serial <= '1';  -- Idle state for TX

        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        -- Send a byte
        tx_serial <= '0';  -- Start bit
        wait for CLK_PERIOD * CYCLES_PER_BIT;  -- Wait for one bit period
        tx_serial <= '0';  -- Data bit 0
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 1
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 2
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 3
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 4
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '0';  -- Data bit 5
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 6
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 7
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Stop bit
        wait for CLK_PERIOD * CYCLES_PER_BIT * 2;  -- wait extra after stop bit

        -- Send another byte
        tx_serial <= '0';  -- Start bit
        wait for CLK_PERIOD * CYCLES_PER_BIT;  -- Wait for one bit period
        tx_serial <= '1';  -- Data bit 0
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '0';  -- Data bit 1
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 2
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 3
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '0';  -- Data bit 4
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 5
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '0';  -- Data bit 6
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Data bit 7
        wait for CLK_PERIOD * CYCLES_PER_BIT;
        tx_serial <= '1';  -- Stop bit

        wait;
    end process;

    recv_process: process
    begin
        -- Wait for reception
        wait until rx1_ready = '1';
        assert rx1_byte = "11011110" report "Received byte does not match expected value" severity error;
        report "Received byte: " & integer'image(to_integer(unsigned(rx1_byte)));

        wait until rx1_ready = '1';
        assert rx1_byte = "10101101" report "Received byte does not match expected value" severity error;
        report "Received byte: " & integer'image(to_integer(unsigned(rx1_byte)));

        -- End simulation
        wait for 100 ns;
        assert false report "End of simulation" severity note;
        wait;

    end process;

    send_process: process
    begin
        tx_load <= '0';
        wait for CLK_PERIOD * CYCLES_PER_BIT * 2;  -- wait extra after stop bit

        TX_DATA <= "10111110";  -- Load data to send
        tx_load <= '1';  -- Trigger load
        wait for CLK_PERIOD*2;  -- Wait for load to complete
        tx_load <= '0';  -- Clear load signal
        wait until tx_busy = '0';  -- Wait until transmitter is not busy

        wait for CLK_PERIOD * CYCLES_PER_BIT;
        TX_DATA <= "11101111";  -- Load another data to send
        tx_load <= '1';  -- Trigger load
        wait for CLK_PERIOD*2;  -- Wait for load to complete
        tx_load <= '0';  -- Clear load signal

        wait;
    end process;

end architecture;