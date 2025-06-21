-- Directly from copilot, will need adjustments
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TopLevel is
    port ( -- remap to DE0 pins
        clk        : in  std_logic;
        rst        : in  std_logic;
        rx_serial  : in  std_logic;
        tx_serial  : out std_logic;
        -- Flash chip pins:
        WP_n       : out std_logic;
        BYTE_n     : out std_logic;
        RST_n      : out std_logic;
        CE_n       : out std_logic;
        OE_n       : out std_logic;
        WE_n       : out std_logic;
        BY_n       : in  std_logic;
        A          : out std_logic_vector(21 downto 0);
        DQ         : inout std_logic_vector(15 downto 0)
    );
end TopLevel;

architecture rtl of TopLevel is

    -- Internal signals for interconnection
    signal ready_out  : std_logic;
    signal addr_out   : std_logic_vector(21 downto 0);
    signal data_out   : std_logic_vector(15 downto 0);
    signal we_out     : std_logic;
    signal valid_out  : std_logic;

begin

    -- UART Flash Loader
    uart_loader: entity work.uart_flash_loader
        port map (
            clk        => clk,
            rst        => rst,
            rx_serial  => rx_serial,
            tx_serial  => tx_serial,
            ready_out  => ready_out,
            addr_out   => addr_out,
            data_out   => data_out,
            we_out     => we_out,
            valid_out  => valid_out
        );

    -- Flash Controller
    flash_ctrl: entity work.FLASH_RAM
        generic map (
            MAIN_CLK_NS => 20  -- 50 MHz
        )
        port map (
            CLK_IN      => clk,
            RST_IN      => rst,
            ERASE_IN    => "00",           -- Not used by loader
            RD_IN       => '0',            -- Not used by loader
            WR_IN       => we_out,
            ADDR_IN     => addr_out,
            DATA_IN     => data_out,
            DATA_OUT    => open,           -- Not used by loader
            READY_OUT   => ready_out,
            VALID_OUT   => open,           -- Optional: can monitor
            ERROR_OUT   => open,           -- Optional: can monitor
            WP_n        => WP_n,
            BYTE_n      => BYTE_n,
            RST_n       => RST_n,
            CE_n        => CE_n,
            OE_n        => OE_n,
            WE_n        => WE_n,
            BY_n        => BY_n,
            A           => A,
            DQ          => DQ
        );

end rtl;

-- directly from chatGPT - will need adjustments
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_flash_loader is
    generic (
        FIXED_ADDR_TOP : std_logic_vector(5 downto 0) := "000000"  -- upper 6 flash-address bits
    );
    port (
        clk        : in  std_logic;  -- 50 MHz
        rst        : in  std_logic;

        ----------------------------------------------------------------
        -- UART lines (115 200 baud, 8-N-1)
        ----------------------------------------------------------------
        rx_serial  : in  std_logic;
        tx_serial  : out std_logic;

        ----------------------------------------------------------------
        --  Flash-controller interface  (write-only path shown)
        ----------------------------------------------------------------
        ready_out  : in  std_logic;                        -- goes low while flash is busy
        addr_out   : out std_logic_vector(21 downto 0);    -- address for next word
        data_out   : out std_logic_vector(15 downto 0);    -- data word
        we_out     : out std_logic;                        -- 1-clk pulse to start write
        valid_out  : out std_logic                         -- mirrors we_out, handy for debug
    );
end uart_flash_loader;

architecture rtl of uart_flash_loader is
    --------------------------------------------------------------------
    --  CONSTANTS
    --------------------------------------------------------------------
    constant BAUD_DIV : integer := 50_000_000 / 115_200;  -- 434

    constant C_STAR : std_logic_vector(7 downto 0) := x"2A";  -- '*'
    constant C_BANG : std_logic_vector(7 downto 0) := x"21";  -- '!'

    --------------------------------------------------------------------
    --  UART-RX  (same as before, outputs 1-clk 'rx_ready')
    --------------------------------------------------------------------
    type rx_fsm is (RX_IDLE, RX_START, RX_BITS, RX_STOP, RX_DONE);
    signal rx_state : rx_fsm := RX_IDLE;
    signal rx_cnt   : integer range 0 to BAUD_DIV := 0;
    signal rx_bit   : integer range 0 to 7 := 0;
    signal rx_shift : std_logic_vector(7 downto 0);
    signal rx_byte  : std_logic_vector(7 downto 0);
    signal rx_ready : std_logic := '0';

    --------------------------------------------------------------------
    --  UART-TX  (simple transmitter, driven by 'tx_load')
    --------------------------------------------------------------------
    type tx_fsm is (TX_IDLE, TX_SHIFT);
    signal tx_state : tx_fsm := TX_IDLE;
    signal tx_cnt   : integer range 0 to BAUD_DIV := 0;
    signal tx_bit   : integer range 0 to 9 := 0;
    signal tx_shift : std_logic_vector(9 downto 0) := (others => '1');
    signal tx_load  : std_logic := '0';                -- strobe to send a byte
    signal tx_data  : std_logic_vector(7 downto 0);    -- byte to send
    signal tx_busy  : std_logic := '0';

    --------------------------------------------------------------------
    --  PROTOCOL state
    --------------------------------------------------------------------
    type proto_fsm is (
        WAIT_STAR, ACK_START,
        HDR_0, HDR_1, HDR_2, HDR_3,
        LOAD_L, LOAD_H,
        WAIT_FLASH_BUSY, WAIT_FLASH_READY,
        ACK_DONE
    );
    signal p_state     : proto_fsm := WAIT_STAR;

    signal addr_low    : std_logic_vector(15 downto 0);
    signal write_len   : unsigned(15 downto 0);  -- byte count
    signal bytes_seen  : unsigned(15 downto 0);

    signal byte_buf    : std_logic_vector(7 downto 0);
    signal word_buf    : std_logic_vector(15 downto 0);
    signal next_addr   : std_logic_vector(21 downto 0);

begin
    --------------------------------------------------------------------
    --  =========  UART  RECEIVER  =========
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            rx_ready <= '0';                           -- default
            if rst = '1' then
                rx_state <= RX_IDLE;
            else
                case rx_state is
                    when RX_IDLE =>
                        if rx_serial = '0' then        -- start bit detected
                            rx_cnt   <= BAUD_DIV/2;
                            rx_state <= RX_START;
                        end if;

                    when RX_START =>
                        if rx_cnt = 0 then
                            rx_cnt   <= BAUD_DIV;
                            rx_bit   <= 0;
                            rx_state <= RX_BITS;
                        else rx_cnt <= rx_cnt - 1;
                        end if;

                    when RX_BITS =>
                        if rx_cnt = 0 then
                            rx_shift(rx_bit) <= rx_serial;
                            if rx_bit = 7 then
                                rx_state <= RX_STOP;
                            else
                                rx_bit <= rx_bit + 1;
                            end if;
                            rx_cnt <= BAUD_DIV;
                        else rx_cnt <= rx_cnt - 1;
                        end if;

                    when RX_STOP =>
                        if rx_cnt = 0 then
                            rx_byte  <= rx_shift;
                            rx_ready <= '1';
                            rx_state <= RX_IDLE;
                        else rx_cnt <= rx_cnt - 1;
                        end if;

                    when RX_DONE =>
                        null;   -- unused
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    --  =========  UART  TRANSMITTER  (tx_busy high while shifting) =====
    --------------------------------------------------------------------
    tx_serial <= tx_shift(0);                          -- LSB first, idles high

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_state <= TX_IDLE;
                tx_shift <= (others => '1');
                tx_busy  <= '0';
            else
                case tx_state is
                    when TX_IDLE =>
                        tx_busy <= '0';
                        if tx_load = '1' then
                            tx_shift <= '0' & tx_data & '1'; -- start, data, stop
                            tx_cnt   <= BAUD_DIV;
                            tx_bit   <= 0;
                            tx_state <= TX_SHIFT;
                            tx_busy  <= '1';
                        end if;

                    when TX_SHIFT =>
                        if tx_cnt = 0 then
                            tx_shift <= '1' & tx_shift(9 downto 1); -- shift right
                            if tx_bit = 9 then
                                tx_state <= TX_IDLE;
                            else
                                tx_bit <= tx_bit + 1;
                            end if;
                            tx_cnt <= BAUD_DIV;
                        else
                            tx_cnt <= tx_cnt - 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    --  =========  PROTOCOL FSM  =========
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- defaults each cycle
            we_out    <= '0';
            valid_out <= '0';
            tx_load   <= '0';

            if rst = '1' then
                p_state <= WAIT_STAR;
                bytes_seen <= (others => '0');
            else
                case p_state is
    --------------------------------------------------------------------
    --  0. WAIT FOR LEADING '*'
    --------------------------------------------------------------------
                    when WAIT_STAR =>
                        if rx_ready = '1' and rx_byte = C_STAR then
                            p_state <= ACK_START;
                        end if;
    --------------------------------------------------------------------
    --  1. SEND  '!'  ACK
    --------------------------------------------------------------------
                    when ACK_START =>
                        if tx_busy = '0' then
                            tx_data <= C_BANG;
                            tx_load <= '1';
                            p_state <= HDR_0;
                        end if;
    --------------------------------------------------------------------
    --  2.  READ 4-BYTE HEADER  (addr_low, len)
    --------------------------------------------------------------------
                    when HDR_0 =>
                        if rx_ready = '1' then
                            addr_low(7 downto 0) <= rx_byte;
                            p_state <= HDR_1;
                        end if;

                    when HDR_1 =>
                        if rx_ready = '1' then
                            addr_low(15 downto 8) <= rx_byte;
                            p_state <= HDR_2;
                        end if;

                    when HDR_2 =>
                        if rx_ready = '1' then
                            write_len(7 downto 0) <= unsigned(rx_byte);
                            p_state <= HDR_3;
                        end if;

                    when HDR_3 =>
                        if rx_ready = '1' then
                            write_len(15 downto 8) <= unsigned(rx_byte);
                            bytes_seen  <= (others => '0');
                            next_addr   <= FIXED_ADDR_TOP & addr_low;
                            p_state     <= LOAD_L;
                        end if;
    --------------------------------------------------------------------
    --  3.  STREAM DATA  (pair two bytes to a word)
    --------------------------------------------------------------------
                    when LOAD_L =>
                        if rx_ready = '1' then
                            byte_buf <= rx_byte;
                            p_state  <= LOAD_H;
                        end if;

                    when LOAD_H =>
                        if rx_ready = '1' then
                            word_buf <= rx_byte & byte_buf;
                            p_state  <= WAIT_FLASH_BUSY;
                        end if;

                    when WAIT_FLASH_BUSY =>
                        if ready_out = '1' then                 -- flash idle → can assert WE
                            addr_out  <= next_addr;
                            data_out  <= word_buf;
                            we_out    <= '1';
                            valid_out <= '1';
                            p_state   <= WAIT_FLASH_READY;      -- wait for busy to drop
                        end if;

                    when WAIT_FLASH_READY =>
                        if ready_out = '0' then                 -- busy...
                            null;
                        elsif ready_out = '1' then              -- finished this word
                            -- update counters
                            next_addr   <= std_logic_vector(unsigned(next_addr) + 1);
                            bytes_seen  <= bytes_seen + 2;

                            if bytes_seen + 2 >= write_len then
                                p_state <= ACK_DONE;            -- all data written
                            else
                                p_state <= LOAD_L;              -- fetch next word
                            end if;
                        end if;
    --------------------------------------------------------------------
    --  4.  FINAL ACK '!'  WHEN DONE
    --------------------------------------------------------------------
                    when ACK_DONE =>
                        if tx_busy = '0' then
                            tx_data <= C_BANG;
                            tx_load <= '1';
                            p_state <= WAIT_STAR;               -- ready for next session
                        end if;
                end case;
            end if;
        end if;
    end process;
end rtl;