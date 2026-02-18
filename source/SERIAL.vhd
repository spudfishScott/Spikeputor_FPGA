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
        DEFAULT_BAUD  : Integer := 38400                            -- Default Baud rate = 38400
    );

    port (
        CLK         : in  std_logic;                     -- System clock
        RST         : in  std_logic;                     -- Reset signal (active high)

        BAUD        : in std_logic_vector(3 downto 0);   -- Baud Rate index (number from 0-15 for baud rates from 1200 to 2000000)
        FLUSH       : in std_logic;                      -- set high to flush buffer
        CMD         : in std_logic;                      -- strobe to set new baud rate and/or flush buffer

        RX_SERIAL   : in  std_logic;                     -- Serial data input
        RX_DATA     : out std_logic_vector(7 downto 0);  -- Received byte output
        RX_READY    : out std_logic_vector(3 downto 0);  -- Number of bytes available on the buffer
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
    signal tx_cnt     : integer range 0 to 65535 := 0;                      -- counter for bit timing
    signal tx_bit     : integer range 0 to 9 := 0;                          -- bit counter for transmitted data (10 bits: 1 start, 8 data, 1 stop)
    signal tx_shift   : std_logic_vector(9 downto 0) := (others => '1');    -- shift register to store data to be transmitted

    TYPE SERBUF IS ARRAY(0 to 15) OF STD_LOGIC_VECTOR(7 DOWNTO 0);          -- sixteen byte buffer
    SIGNAL ser_buffer        : SERBUF := (others => (others => '0'));       -- ring buffer for recieved bytes
    SIGNAL buffer_head       : unsigned(3 downto 0) := (others => '0');     -- points to next position to write new key
    SIGNAL buffer_tail       : unsigned(3 downto 0) := (others => '0');     -- points to next position to read key
    SIGNAL buffer_full       : std_logic := '0';                            -- flag if buffer is full
    SIGNAL overflow_s        : std_logic := '0';                            -- buffer overflow flag

begin

    RX_READY <= x"0" when rx_state /= RX_IDLE  else
                std_logic_vector(buffer_head - buffer_tail) when buffer_full = '0'
                else X"F";                                                  -- current number of bytes on the buffer
    RX_DATA <= ser_buffer(to_integer(buffer_tail));                         -- current RX data is pointed to by buffer_tail index
    RX_OVERFLOW <= overflow_s;

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
                bit_period  <= CLK_SPEED / DEFAULT_BAUD;    -- reset bit_period to default baud rate
                buffer_head <= (others => '0');             -- flush input buffer
                buffer_tail <= (others => '0');
                buffer_full <= '0';
                overflow_s  <= '0';

            else
                if CMD = '1' then                           -- if CMD is high, latch in new baud rate and flush buffer
                    case BAUD is
                        when "0000" =>
                            bit_period <= CLK_SPEED / 1200;
                        when "0001" =>
                            bit_period <= CLK_SPEED / 2400;
                        when "0010" =>
                            bit_period <= CLK_SPEED / 4800;
                        when "0011" =>
                            bit_period <= CLK_SPEED / 9600;
                        when "0100" =>
                            bit_period <= CLK_SPEED / 19200;
                        when "0101" =>
                            bit_period <= CLK_SPEED / 38400;
                        when "0110" =>
                            bit_period <= CLK_SPEED / 57600;
                        when "0111" =>
                            bit_period <= CLK_SPEED / 115200;
                        when "1000" =>
                            bit_period <= CLK_SPEED / 230400;
                        when "1001" =>
                            bit_period <= CLK_SPEED / 460800;
                        when "1010" =>
                            bit_period <= CLK_SPEED / 921600;
                        when "1011" =>
                            bit_period <= CLK_SPEED / 1382400;
                        when "1100" =>
                            bit_period <= CLK_SPEED / 1728000;
                        when "1101" =>
                            bit_period <= CLK_SPEED / 2073600;
                        when "1110" =>
                            bit_period <= CLK_SPEED / 2500000;
                        when "1111" =>
                            bit_period <= CLK_SPEED / 3000000;
                        when others =>
                            null; -- should never happen
                    end case;

                    if FLUSH = '1' then         -- flush input buffer and clear overflow error
                        buffer_head <= (others => '0');
                        buffer_tail <= (others => '0');
                        ser_buffer  <= (others => (others => '0'));
                        buffer_full <= '0';
                        overflow_s  <= '0';
                    end if;
                else
                    if RX_NEXT = '1' then   -- if RX_NEXT was high and we're not messing with the buffer
                        buffer_tail <= buffer_tail + 1;     -- increment buffer_tail with automatic wrap-around
                        buffer_full <= '0';                 -- buffer can no longer be full
                        if rx_cnt /= 0 then
                            rx_cnt <= rx_cnt - 1;           -- count down continues if it's happening
                        end if;
                    else
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
                                if rx_cnt = 0 then                  -- wait for counter to expire
                                    rx_state <= RX_IDLE;            -- go back to idle state when it does - even if no stop bit detected
                                    if rx_ser_s = '1' then          -- check for stop bit (should be high)
                                        ser_buffer(to_integer(buffer_head)) <= rx_shift;
                                        buffer_head <= buffer_head + 1;
                                        if buffer_full = '1' then   -- latch overflow signal if adding to a full buffer
                                            overflow_s <= '1';
                                        end if;
                                        if (buffer_head + 1 = buffer_tail) then
                                            buffer_tail <= buffer_tail +1;
                                            buffer_full <= '1';
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
