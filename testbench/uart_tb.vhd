library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tb is
end entity;

architecture tb of uart_tb is

    constant CLK_PERIOD : time := 20 ns;

    -- shared signals
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';

    -- Signals for UART0 (transmitter)
    signal tx0_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx0_load   : std_logic := '0';
    signal tx0_busy   : std_logic;
    signal tx0_serial : std_logic;

    -- Signals for UART1 (receiver)
    signal rx1_byte   : std_logic_vector(7 downto 0);
    signal rx1_ready  : std_logic;

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

    -- Instantiate UART0 (Transmitter)
    uart0 : entity work.UART
        generic map (
            CLK_SPEED => 50_000_000,
            BAUD_RATE => 115_200
        )
        port map (
            CLK        => clk,
            RST        => rst,
            RX_SERIAL  => '0',              -- No connection for RX in transmitter
            RX_DATA    => open,
            RX_READY   => open,
            TX_SERIAL  => tx0_serial,
            TX_DATA    => tx0_data,
            TX_LOAD    => tx0_load,
            TX_BUSY    => tx0_busy
        );

    -- Instantiate UART1 (Receiver)
    uart1 : entity work.UART
        generic map (
            CLK_SPEED => 50_000_000,
            BAUD_RATE => 115_200
        )
        port map (
            CLK        => clk,
            RST        => rst,
            RX_SERIAL  => tx0_serial,       -- Connect UART0 TX to UART1 RX
            RX_DATA    => rx1_byte,
            RX_READY   => rx1_ready,
            TX_SERIAL  => open,
            TX_DATA    => (others => '0'),  -- No connection for TX in receiver
            TX_LOAD    => '0',              -- No load signal for receiver
            TX_BUSY    => open
        );

    -- Stimulus process
    stim_proc_tx: process
    begin
        -- Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        tx0_data <= x"5A";
        wait for 10 us;

        -- Send a byte from UART0 to UART1
        tx0_load <= '1';
        wait for CLK_PERIOD*2;
        tx0_load <= '0';

        wait for 10 us;
        tx0_data <= x"08";          -- set up new data to send
        wait until tx0_busy = '0';  -- Wait until UART0 is not busy

        tx0_load <= '1';
        wait for CLK_PERIOD*2;
        tx0_load <= '0';

        wait for 10 us;
        tx0_data <= x"A5";          -- set up new data to send
        
        wait until tx0_busy = '0';  -- Wait until UART0 is not busy

        tx0_load <= '1';
        wait for CLK_PERIOD*2;
        tx0_load <= '0';

        -- End simulation
        wait for 1 us;
        assert false report "Simulation finished." severity note;
        wait;
    end process;

    stim_proc_rx: process
    begin
        -- Wait for transmission to complete
        wait until rx1_ready = '1';
        assert rx1_byte = x"5A"
            report "UART1 did not receive the correct byte!" severity error;

        wait until rx1_ready = '1';
        assert rx1_byte = x"08"
            report "UART1 did not receive the correct byte!" severity error;

        wait until rx1_ready = '1';
        assert rx1_byte = x"A5"
            report "UART1 did not receive the correct byte!" severity error;

        wait;

    end process;

end architecture;