library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_flash_loader_tb is
end entity;

architecture tb of uart_flash_loader_tb is
    constant CLK_PERIOD : time := 20 ns;

    -- Testbench signals
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal rx_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready   : std_logic := '0';
    signal tx_data    : std_logic_vector(7 downto 0);
    signal tx_load    : std_logic;
    signal tx_busy    : std_logic := '0';
    signal flash_rdy  : std_logic := '1';
    signal addr_out   : std_logic_vector(21 downto 0);
    signal data_out   : std_logic_vector(15 downto 0);
    signal wr_out     : std_logic;
    signal activity   : std_logic;
    signal completed  : std_logic;

    -- Protocol constants
    constant C_STAR   : std_logic_vector(7 downto 0) := x"2A";
    constant C_BANG   : std_logic_vector(7 downto 0) := x"21";
    constant TEST_ADDR_H : std_logic_vector(7 downto 0) := x"12";
    constant TEST_ADDR_L : std_logic_vector(7 downto 0) := x"34";
    constant TEST_ADDR_L2 : std_logic_vector(7 downto 0) := x"35"; -- Incremented for second write
    constant TEST_LEN_H  : std_logic_vector(7 downto 0) := x"00";
    constant TEST_LEN_L  : std_logic_vector(7 downto 0) := x"04"; -- 2 bytes = 2 words
    constant TEST_DATA_H : std_logic_vector(7 downto 0) := x"AB";
    constant TEST_DATA_L : std_logic_vector(7 downto 0) := x"CD";

    -- Helper procedure to strobe rx_ready and present a byte
    procedure send_byte(signal p_rx_data : out std_logic_vector(7 downto 0);
                        signal p_rx_ready : out std_logic;
                        data : std_logic_vector(7 downto 0)) is
    begin
        wait for 100 ns; -- simulate low baud rate
        p_rx_data  <= data;
        p_rx_ready <= '1';
        wait for CLK_PERIOD;
        p_rx_ready <= '0';
    end procedure;

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

    -- Instantiate the loader
    DUT: entity work.uart_flash_loader
        generic map (
            FIXED_ADDR_TOP => "000000"
        )
        port map (
            CLK        => clk,
            RST        => rst,
            RX_DATA    => rx_data,
            RX_READY   => rx_ready,
            TX_DATA    => tx_data,
            TX_LOAD    => tx_load,
            TX_BUSY    => tx_busy,
            FLASH_RDY  => flash_rdy,
            ADDR_OUT   => addr_out,
            DATA_OUT   => data_out,
            WR_OUT     => wr_out,
            ACTIVITY   => activity,
            COMPLETED  => completed
        );

    -- Stimulus process
    stim_proc_tx: process
    begin
        -- Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 100 ns;

        -- Send '*' (start)
        send_byte(rx_data, rx_ready, C_STAR);

        tx_busy <= '1';  -- Simulate UART transmitter busy
        wait for CLK_PERIOD*5;
        tx_busy <= '0';  -- Simulate UART transmitter ready

        -- Wait for ACK ('!')
        wait until tx_load = '1';
        assert tx_data = C_BANG report "Did not receive ACK after '*'!" severity error;

        -- Send address high
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_ADDR_H);

        -- Send address low
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_ADDR_L);
        -- Send length high
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_LEN_H);
        -- Send length low
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_LEN_L);
        -- Send data high
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_DATA_H);
        -- Send data low
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_DATA_L);

        -- Wait for flash write
        wait until wr_out = '1';
        assert addr_out(15 downto 8) = TEST_ADDR_H and addr_out(7 downto 0) = TEST_ADDR_L
            report "Address 1 mismatch" severity error;
        assert data_out(15 downto 8) = TEST_DATA_H and data_out(7 downto 0) = TEST_DATA_L
            report "Data 1 mismatch" severity error;
        wait until wr_out = '0';

        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_DATA_L);
        -- Send data low
        wait for CLK_PERIOD;
        send_byte(rx_data, rx_ready, TEST_DATA_H);

        wait until wr_out = '1';
        assert addr_out(15 downto 8) = TEST_ADDR_H and addr_out(7 downto 0) = TEST_ADDR_L2
            report "Address 2 mismatch" severity error;
        assert data_out(15 downto 8) = TEST_DATA_L and data_out(7 downto 0) = TEST_DATA_H
            report "Data 2 mismatch" severity error;

        tx_busy <= '1';  -- Simulate UART transmitter busy
        wait for CLK_PERIOD*5;
        tx_busy <= '0';  -- Simulate UART transmitter ready

        -- Wait for final ACK ('!')
        wait until tx_load = '1';
        assert tx_data = C_STAR report "Did not receive final ACK!" severity error;
        wait for CLK_PERIOD;

        -- End simulation
        wait for 200 ns; -- Wait for a bit to ensure all signals settle
        assert false report "Simulation finished." severity note;
        wait;
    end process;

end architecture;
