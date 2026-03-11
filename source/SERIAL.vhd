-- This module synthesizes a variable buffered UART (Universal Asynchronous Receiver-Transmitter) for serial communication.
-- It supports configurable clock speed and baud rate, and provides basic functionality for receiving and transmitting bytes.
-- Configured for 1 start bit, 8 data bits, and 1 stop bit (8N1).
-- If RX_READY is non-zero, data is available at RX_DATA. Strobe RX_NEXT to get next item from the buffer, if it exists.
-- Strobe CMD with BAUD and FLASH set to desired valuesato set the baud rate and/or flush the rx buffer.
-- If buffer overflows, the RX_OVERFLOW signal will be set until cleared by a FLUSH command.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SERIAL is
    generic (
        CLK_SPEED     : Integer := 50_000_000;                      -- Clock speed in Hz (default: 50 MHz)
        DEFAULT_BAUD  : std_logic_vector(3 downto 0) := "0101"      -- Default Baud rate = 38400 (index "0101")
    );

    port (
        CLK         : in  std_logic;                     -- System clock
        RST         : in  std_logic;                     -- Reset signal (active high)

        BAUD        : in std_logic_vector(3 downto 0);   -- Baud Rate index (number from 0-15 for baud rates from 1200 to 2000000)
        FLUSH       : in std_logic;                      -- set high to flush buffer
        CMD         : in std_logic;                      -- strobe to set new baud rate and/or flush buffer

        RX_SERIAL   : in  std_logic;                     -- Serial data input
        RX_DATA     : out std_logic_vector(7 downto 0);  -- Received byte output
        RX_READY    : out std_logic_vector;              -- Next byte is ready to be read
        RX_SIZE     : out std_logic_vector(8 downto 0);  -- Number of bytes in the buffer
        RX_NEXT     : in std_logic;                      -- strobe to recieve a byte if available
        RX_OVERFLOW : out std_logic;                     -- set if the ring buffer overflows

        TX_SERIAL   : out std_logic;                     -- Serial data output
        TX_DATA     : in std_logic_vector(7 downto 0);   -- Input byte to send
        TX_LOAD     : in std_logic;                      -- Strobe to send a byte
        TX_BUSY     : out std_logic                      -- Indicates if the transmitter is busy
    );
end SERIAL;

architecture Behavioral of SERIAL is

    -- signals - always provide initial values to help fitter not get stuck
    --  UART-RX  (strobes 'rx_ready' when byte is recieved)
    type RX_FSM is (RX_IDLE, RX_START, RX_BITS, RX_STOP);                   -- state definitions for recieving data
    signal rx_state : RX_FSM := RX_IDLE;

    signal rx_cnt   : integer range 0 to 65535 := 0;                        -- counter for bit timing
    signal rx_bit   : integer range 0 to 7 := 0;                            -- bit counter for received data
    signal rx_shift : std_logic_vector(7 downto 0) := (others => '0');      -- shift register to store received data

    signal rx_sync  : std_logic_vector(1 downto 0) := (others => '1');      -- "Double Flop" to prevent metastable states with ansynchronous signals
    signal rx_ser_s : std_logic := '1';                                     -- Debounced version of RX_SERIAL

    --  UART-TX  (driven by 'tx_load')
    type TX_FSM is (TX_IDLE, TX_BITS);                                      -- state definitions for transmitting data
    signal tx_state : TX_FSM := TX_IDLE;

    signal bit_period : integer range 0 to 65536 := 0;                      -- number of clock cycles per bit
    signal baud_period : integer range 0 to 65535 := 0;
    signal baud_s     : std_logic_vector(3 downto 0) := (others => '0');    -- baud index signal
    signal tx_cnt     : integer range 0 to 65535 := 0;                      -- counter for bit timing
    signal tx_bit     : integer range 0 to 9 := 0;                          -- bit counter for transmitted data (10 bits: 1 start, 8 data, 1 stop)
    signal tx_shift   : std_logic_vector(9 downto 0) := (others => '1');    -- shift register to store data to be transmitted

    SIGNAL buffer_full       : std_logic := '0';                            -- flag if buffer is full
    SIGNAL overflow_s        : std_logic := '0';                            -- buffer overflow flag
    SIGNAL rx_ready_s        : std_logic;

    SIGNAL buffer_head       : unsigned(8 downto 0) := (others => '0');
    SIGNAL buffer_tail       : unsigned(8 downto 0) := (others => '0');

    SIGNAL buf_updating      : std_logic := '0';
    SIGNAL buf_addr          : std_logic_vector(8 downto 0) := (others => '0');
    SIGNAL buf_data_in       : std_logic_vector(7 downto 0) := (others => '0');
    SIGNAL buf_wr            : std_logic := '0';
    SIGNAL buf_data_out      : std_logic_vector(7 downto 0) := (others => '0');
    SIGNAL rx_data_out       : std_logic_vector(7 downto 0) := (others => '0');

begin

    SER_BUF : entity work.RAM
    generic map (
        NUM_WORDS  => 512,      -- buffer is 512 bytes
        ADDR_WIDTH => 9,        -- 9 bits to address 512 bytes (0x000-0x1ff)
        DATA_WIDTH => 8         -- data is 8 bits wide
    )
    port map (
        clock     => CLK,
        address   => buf_addr,
        data      => buf_data_in,
        wren      => buf_wr,

        q         => buf_data_out
    );

    RX_READY <= rx_ready_s;
    RX_SIZE  <= std_logic_vector(buffer_tail - buffer_head) when buffer_full = '0' else (others => '1');
    RX_DATA  <= rx_data_out; --ser_buffer(to_integer(buffer_tail));                         -- current RX data is pointed to by buffer_tail index
    RX_OVERFLOW <= overflow_s;
    
    baud_s <= BAUD when RST = '0' else DEFAULT_BAUD;
    with (baud_s) select
        baud_period <=
            CLK_SPEED / 2400 when "0001",
            CLK_SPEED / 4800 when "0010",
            CLK_SPEED / 9600 when "0011",
            CLK_SPEED / 19200 when "0100",
            CLK_SPEED / 38400 when "0101",
            CLK_SPEED / 57600 when "0110",
            CLK_SPEED / 115200 when "0111",
            CLK_SPEED / 230400 when "1000",
            CLK_SPEED / 460800 when "1001",
            CLK_SPEED / 921600 when "1010",
            CLK_SPEED / 1382400 when "1011",
            CLK_SPEED / 1728000 when "1100",
            CLK_SPEED / 2073600 when "1101",
            CLK_SPEED / 2500000 when "1110",
            CLK_SPEED / 1200 when others; -- default case, including "0000" which is the reset value

    -- RX Input Synchronizer
    process(CLK)
    begin
        if rising_edge(CLK) THEN                            -- these are very important for handling outside asynchronous signals
            rx_sync(0) <= RX_SERIAL;
            rx_sync(1) <= rx_sync(0);
            rx_ser_s   <= rx_sync(1);
        end if;
    end process;

    --  UART RECEIVER
    process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                rx_state    <= RX_IDLE;                     -- reset state machine
                rx_shift    <= (others => '1');             -- reset shift register
                bit_period  <= baud_period;                 -- reset bit_period to default baud rate
                buffer_head <= (others => '0');             -- flush input buffer
                buffer_tail <= (others => '0');
                buffer_full <= '0';
                overflow_s  <= '0';
                rx_data_out <= (others => '0');
                rx_ready_s  <= '0';

            else
                buf_wr      <= '0';                             -- reset buffer write each cycle

                -- update buffer output if needed
                if buf_updating = '1' then
                    rx_data_out <= buf_data_out;    -- latch data out if updating
                    buf_updating <= '0';            -- clear updating flag, next cycle will update buffer_ready
                end if;
                
                -- update buffer ready
                if buffer_full = '0' then
                    if buffer_head = buffer_tail then   -- 0 if nothing in the buffer, 1 if something
                        rx_ready_s <= '0';
                    else
                        rx_ready_s <= '1';
                    end if;
                else 
                    rx_ready_s <= '1';                  -- 1 when buffer is full
                end if;

                if CMD = '1' then                           -- if CMD is high, latch in new baud rate and flush buffer
                    bit_period <= baud_period;  -- set baud period based on current baud value

                    if FLUSH = '1' then         -- flush input buffer, clear buffer output, and clear overflow error
                        buffer_head <= (others => '0');
                        buffer_tail <= (others => '0');
                        buffer_full <= '0';
                        rx_data_out <= (others => '0');
                        overflow_s  <= '0';
                    end if;
                else
                    if RX_NEXT = '1' then    -- if RX_NEXT is high and there's data on the buffer, increment buffer_tail to next position and get data fro buffer
                        if (buffer_tail /= buffer_head OR buffer_full = '1') then
                            buf_addr    <= std_logic_vector(buffer_tail + 1);  -- set new buffer address
                            buffer_tail <= buffer_tail + 1;     -- increment buffer_tail with automatic wrap-around
                            buffer_full <= '0';                 -- buffer can no longer be full (unless we're also recieving, see below)
                            buf_updating <= '1';                -- set updating so new data will be latched in next cycle
                            rx_ready_s <= '0';                  -- next buffer item is not ready yet
                        end if;
                    end if;

                    case rx_state is
                        when RX_IDLE =>
                            if rx_ser_s = '0' then              -- start bit detected
                                rx_cnt   <= bit_period/2;       -- wait to sample in the middle
                                rx_state <= RX_START;           -- set next state
                            end if;

                        when RX_START =>
                            if rx_cnt = 0 then                  -- wait for counter to expire
                                rx_cnt   <= bit_period;         -- reset counter for data bits
                                rx_bit   <= 0;                  -- reset bit counter
                                rx_state <= RX_BITS;            -- set next state to read in the bits
                            else rx_cnt <= rx_cnt - 1;          -- decrement counter
                            end if;

                        when RX_BITS =>
                            if rx_cnt = 0 then                  -- wait for counter to expire
                                rx_shift(rx_bit) <= rx_ser_s;   -- sample the serial data input line and store in current bit position of rx register
                                if rx_bit = 7 then              -- if all bits have been received, go to stop state
                                    rx_state <= RX_STOP;
                                    rx_cnt <= bit_period;       -- reset clock counter for stop bit
                                else                            -- otherwise increment bit counter
                                    rx_bit <= rx_bit + 1;
                                    rx_cnt <= bit_period;       -- reset clock counter for next bit
                                end if;
                            else 
                                rx_cnt <= rx_cnt - 1;          -- decrement counter
                            end if;

                        when RX_STOP =>
                            if rx_cnt = 1 then
                                buf_addr    <= std_logic_vector(buffer_head);     -- set up buffer address one cycle before time to write
                            end if;
                            if rx_cnt = 0 then                  -- wait for counter to expire
                                rx_state <= RX_IDLE;            -- go back to idle state when it does - even if no stop bit detected
                                if rx_ser_s = '1' then          -- check for stop bit (should be high)
                                    buf_data_in <= rx_shift;    -- latch new data into data_in
                                    buf_wr      <= '1';         -- strobe wr to write it
                                    buffer_head <= buffer_head + 1; -- always increment buffer_head when adding to buffer

                                     -- logic is different if RX_NEXT is being strobed or not
                                    if RX_NEXT = '0' then       -- logic for RX_NEXT = '0'
                                        if buffer_head = buffer_tail AND buffer_full = '0' AND buf_updating = '0' then  -- if buffer was clear and data is being added and not already being updated, update it on the output
                                            rx_data_out <= rx_shift;
                                        end if;
                                        if (buffer_head + 1 = buffer_tail) then
                                            buffer_full <= '1';         -- buffer will be full after this
                                            if (buffer_full = '1') then
                                                overflow_s <= '1';              -- latch overflow signal if adding to a full buffer
                                                buffer_tail <= buffer_tail + 1; -- buffer overflow, new data coming in erases old data
                                            end if;
                                        end if;
                                    else                        -- logic for RX_NEXT = '1'
                                        if (buffer_tail /= buffer_head) then
                                            buffer_tail <= buffer_tail + 1;     -- increment both tail and head
                                        else
                                            if (buffer_full = '1') then
                                                buffer_tail <= buffer_tail + 1;     -- increment both tail and head
                                                buffer_full <= '1';                 -- buffer is still full
                                            else
                                                buffer_tail <= buffer_tail;         -- do NOT increment buffer tail (overriding the logic above)
                                            end if;
                                        end if;
                                    end if;

                                end if;
                            else 
                                rx_cnt <= rx_cnt - 1;           -- decrement counter
                            end if;

                        when others => 
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    --  UART TRANSMITTER
    TX_SERIAL <= tx_shift(0);                               -- LSB first, idles high

    process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                tx_state <= TX_IDLE;                        -- reset state machine to IDLE
                tx_shift <= (others => '1');                -- clear shift register
                TX_BUSY  <= '0';                            -- clear busy flag
            else
                case tx_state is
                    when TX_IDLE =>
                        TX_BUSY <= '0';                     -- clear busy flag on IDLE
                        if TX_LOAD = '1' then               -- if load signal is high, prepare to send data
                            tx_shift <= '1' & TX_DATA & '0';    -- load start, data, and stop bits into shift register
                            tx_cnt   <= bit_period;         -- reset counter for bit transmission
                            tx_bit   <= 0;                  -- reset bit counter
                            tx_state <= TX_BITS;            -- move to shift state
                            TX_BUSY  <= '1';                -- set busy flag to indicate transmission is in progress
                        end if;

                    when TX_BITS =>
                        TX_BUSY <= '1';                     -- keep busy flag set to indicate transmission is in progress
                        if tx_cnt = 0 then                  -- wait for counter to expire to read the bit
                            tx_shift <= '1' & tx_shift(9 downto 1);     -- shift right, backfill with '1'
                            tx_cnt <= bit_period;           -- reset counter to wait until next bit should be read
                            if tx_bit = 9 then              -- if all bits have been sent, go back to idle state
                                tx_state <= TX_IDLE;
                            else
                                tx_bit <= tx_bit + 1;       -- otherwise increment bit counter 
                            end if;
                        else
                            tx_cnt <= tx_cnt - 1;           -- decrement counter
                        end if;

                    when others => 
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture;
