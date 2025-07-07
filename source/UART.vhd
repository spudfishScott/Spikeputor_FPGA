library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This module synthesizes a simple UART (Universal Asynchronous Receiver-Transmitter) for serial communication.
-- It supports configurable clock speed and baud rate, and provides basic functionality for receiving and transmitting bytes.
-- Configured for 1 start bit, 8 data bits, and 1 stop bit (8N1).

entity UART is
    generic (
        CLK_SPEED : Integer := 50_000_000;  -- Clock speed in Hz (default: 50 MHz)
        BAUD_RATE : Integer := 115_200       -- Baud rate for UART communication (default: 115200)
    );

    port (
        CLK        : in  std_logic;                     -- System clock
        RST        : in  std_logic;                     -- Reset signal (active high)

        RX_SERIAL  : in  std_logic;                     -- Serial data input
        RX_DATA    : out std_logic_vector(7 downto 0);  -- Received byte output
        RX_READY   : out std_logic;                     -- Strobed when a byte has been received

        TX_SERIAL  : out std_logic;                     -- Serial data output
        TX_DATA    : in std_logic_vector(7 downto 0);   -- Input byte to send
        TX_LOAD    : in std_logic;                      -- Strobe to send a byte
        TX_BUSY    : out std_logic                      -- Indicates if the transmitter is busy
    );
end UART;

architecture Behavioral of UART is
    constant BIT_PERIOD : Integer := CLK_SPEED / BAUD_RATE;         -- number of clock cycles per bit

    --  UART-RX  (strobes 'rx_ready' when byte is recieved)
    type RX_FSM is (RX_IDLE, RX_START, RX_BITS, RX_STOP);           -- state definitions for recieving data
    signal rx_state : RX_FSM := RX_IDLE;
    signal rx_cnt   : integer range 0 to BIT_PERIOD := 0;           -- counter for bit timing
    signal rx_bit   : integer range 0 to 7 := 0;                    -- bit counter for received data
    signal rx_shift : std_logic_vector(7 downto 0);                 -- shift register to store received data

    --  UART-TX  (driven by 'tx_load')
    type TX_FSM is (TX_IDLE, TX_BITS);                              -- state definitions for transmitting data
    signal tx_state : TX_FSM := TX_IDLE; 
    signal tx_cnt   : integer range 0 to BIT_PERIOD := 0;           -- counter for bit timing
    signal tx_bit   : integer range 0 to 9 := 0;                    -- bit counter for transmitted data (10 bits: 1 start, 8 data, 1 stop)
    signal tx_shift : std_logic_vector(9 downto 0) := (others => '1');  -- shift register to store data to be transmitted

begin
    --  UART RECEIVER
    process(CLK)
    begin
        if rising_edge(CLK) then
            RX_READY <= '0';            -- clear ready flag at the start of each clock cycle

            if RST = '1' then
                rx_state <= RX_IDLE;    -- reset state machine
            else
                case rx_state is
                    when RX_IDLE =>
                        if RX_SERIAL = '0' then             -- start bit detected
                            rx_cnt   <= BIT_PERIOD/2;       -- wait for half a bit period to sample in the middle
                            rx_state <= RX_START;           -- set next state
                        end if;

                    when RX_START =>
                        if rx_cnt = 0 then                  -- wait for counter to expire
                            rx_cnt   <= BIT_PERIOD;         -- reset counter for data bits
                            rx_bit   <= 0;                  -- reset bit counter
                            rx_state <= RX_BITS;            -- set next state to read in the bits
                        else rx_cnt <= rx_cnt - 1;          -- decrement counter
                        end if;

                    when RX_BITS =>
                        if rx_cnt = 0 then                  -- wait for counter to expire
                            rx_shift(rx_bit) <= RX_SERIAL;  -- sample the serial data input line and store in current bit position of rx register
                            if rx_bit = 7 then              -- if all bits have been received, go to stop state
                                rx_state <= RX_STOP;
                            else                            -- otherwise increment bit counter
                                rx_bit <= rx_bit + 1;
                            end if;
                            rx_cnt <= BIT_PERIOD;           -- reset clock counter for next bit
                        else rx_cnt <= rx_cnt - 1;          -- decrement counter
                        end if;

                    when RX_STOP =>
                        if RX_SERIAL = '1' then             -- check for stop bit (should be high)
                            if rx_cnt = 0 then              -- wait for counter to expire
                                RX_DATA  <= rx_shift;       -- output the received byte
                                RX_READY <= '1';            -- strobe ready flag to indicate byte is ready
                                rx_state <= RX_IDLE;        -- go back to idle state
                            else rx_cnt <= rx_cnt - 1;      -- decrement counter
                            end if;
                        end if;
                        
                end case;
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
                            tx_cnt   <= BIT_PERIOD;         -- reset counter for bit transmission
                            tx_bit   <= 0;                  -- reset bit counter
                            tx_state <= TX_BITS;            -- move to shift state
                            TX_BUSY  <= '1';                -- set busy flag to indicate transmission is in progress
                        end if;

                    when TX_BITS =>
                        TX_BITS <= '1';                     -- keep busy flag set to indicate transmission is in progress
                        if tx_cnt = 0 then                  -- wait for counter to expire
                            tx_shift <= '1' & tx_shift(9 downto 1);     -- shift right, backfill with '1'
                            if tx_bit = 9 then              -- if all bits have been sent, go back to idle state
                                tx_state <= TX_IDLE;
                            else
                                tx_bit <= tx_bit + 1;       -- otherwise increment bit counter 
                            end if;
                            tx_cnt <= BIT_PERIOD;           -- reset counter for next bit
                        else
                            tx_cnt <= tx_cnt - 1;           -- decrement counter
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;
