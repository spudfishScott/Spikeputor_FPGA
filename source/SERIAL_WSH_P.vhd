-- SERIAL Wishbone Interface Provider
-- single memory register is 0xFFF3
    -- WRITE:
        -- High Byte: COMMAND
            -- 0x00:    READ/WRITE      - send and receive the low byte via the serial interface
            -- 0x01:    FLUSH Buffer    - flush the ring input buffer
            -- 0x80:    SET BAUD        -- set baud
        -- Low Byte: DATA associated with the command in the high byte
            -- WRITE:       Send the byte out through the serial port at the current baud rate
            -- FLUSH:       Ignored - Immediately flush the 16 byte ring input buffer
            -- SET BAUD:    A four bit number associated with the baud rate to set
            --                  0x0     <unused>
            --                  0x1     2400
            --                  0x2     4800
            --                  0x3     9600
            --                  0x4     19200
            --                  0x5     38400 * default baud rate unless the generic paramter of SERIAL is changed
            --                  0x6     57600
            --                  0x7     115200
            --                  0x8     230400
            --                  0x9     460800
            --                  0xA     921600
            --                  0xB     1382400
            --                  0xC     1728000
            --                  0xD     2073600
            --                  0xE     2500000
            --                  0xF     <unused>
    -- READ:
        -- High Byte: STATUS
            -- High Nybble      Number of bytes available to read from the ring buffer
            -- Low Nybble       Current Baud Rate, 0x0 if still transmitting, or 0xF if ring buffer has overflowed (entire byte will be 0xFF)
        -- Low Byte: DATA received from the serial port 
            -- If no data is available, this will read as 0x00, but the high nybble of the status signal should be used to check if data is actually available before reading

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity SERIAL_WSH_P is
    generic ( 
        CLK_SPEED : integer := 50_000_000;                                      -- clock speed in Hertz
        DEFAULT_BAUD : std_logic_vector(3 downto 0) := "0101"                   -- default baud setting: index "0101" = 38400
    );
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing, when low, master is reading

        -- serial controller signals
        RX_SERIAL   : in std_logic;                         -- Serial data input
        TX_SERIAL   : out std_logic                         -- Serial data output

    );
end SERIAL_WSH_P;

architecture rtl of SERIAL_WSH_P is

    signal baud_rate     : std_logic_vector(3 downto 0) := (others => '0');      -- baud rate index (see above)
    signal flush         : std_logic := '0';                                     -- flush buffer signal
    signal command       : std_logic := '0';                                     -- strobe to set baud rate and/or flush buffer

    signal rx_data_s     : std_logic_vector(7 downto 0) := (others => '0');      -- received byte
    signal rx_ready_s    : std_logic_vector(3 downto 0) := (others => '0');      -- number of bytes available in ring buffer
    signal rx_next_s     : std_logic := '0';                                     -- strobe for each byte read from buffer (if bytes in buffer > 0)
    signal rx_overflow_s : std_logic := '0';                                     -- ring buffer overflow flag

    signal tx_data_s     : std_logic_vector(7 downto 0) := (others => '0');      -- data to send out
    signal tx_load_s     : std_logic := '0';                                     -- strobe to send out data
    signal tx_busy_s     : std_logic := '0';                                     -- high if transmit is busy

    signal ack           : std_logic := '0';                                     -- internal wishbone acknowledgement
    signal status        : std_logic_vector(3 downto 0) := (others => '0');      -- Current Baud Rate, 0x0 if still transmitting, or 0xF if ring buffer has overflowed

begin

    SER: entity work.SERIAL
    generic map (
        CLK_SPEED    => CLK_SPEED,
        DEFAULT_BAUD => DEFAULT_BAUD
    )
    port map (
        CLK         => CLK,
        RST         => RST_I,

        BAUD        => baud_rate,
        FLUSH       => flush,
        CMD         => command,

        RX_SERIAL   => RX_SERIAL,
        RX_DATA     => rx_data_s,
        RX_READY    => rx_ready_s,
        RX_NEXT     => rx_next_s,
        RX_OVERFLOW => rx_overflow_s,

        TX_SERIAL   => TX_SERIAL,
        TX_DATA     => tx_data_s,
        TX_LOAD     => tx_load_s,
        TX_BUSY     => tx_busy_s
    );

    status      <= x"0" when tx_busy_s = '1' else
                   x"F" when rx_overflow_s = '1' else
                   baud_rate;

    WBS_ACK_O   <= ack AND WBS_CYC_I AND WBS_STB_I;         -- ack out is internal ack if CYC and STB are asserted, else 0
    WBS_DATA_O  <= rx_ready_s & status & rx_data_s;         -- data out is status byte and data byte

    process(CLK) is     -- wishbone transaction process
    begin
        if RST_I = '1' then                                 -- reset state on reset
            baud_rate   <= DEFAULT_BAUD;
            flush       <= '0';
            command     <= '0';
            rx_next_s   <= '0';
            tx_data_s   <= (others => '0');
            tx_load_s   <= '0';

        elsif rising_edge(CLK) then
            command     <= '0';                             -- set these signal to '0' for strobe
            flush       <= '0';
            rx_next_s   <= '0';
            tx_load_s   <= '0';

            if (WBS_CYC_I = '1' AND WBS_STB_I = '1' AND ack = '0') then     -- wait for wishbone transaction to start
                ack <= '1';                                                 -- acknowledge on next cycle
                if (WBS_WE_I = '1') then                                    -- write: take action
                    case WBS_DATA_I(15 downto 8) is                         -- get top byte of data
                        when x"00" =>       -- 0x00 = write data
                            if tx_busy_s = '0' then -- only start writing if transmission is not currently happening, otherwise do nothing
                                tx_data_s <= WBS_DATA_I(7 downto 0);        -- latch in data to be sent
                                tx_load_s <= '1';                           -- strobe tx load to send that data
                            end if;

                        when x"01" =>       -- 0x01 = Flush Buffer
                            flush   <= '1';         -- strobe FLUSH flag
                            command <= '1';         -- strobe command

                        when x"80" =>       -- 0x80 = Set Baud Rate
                            baud_rate <= WBS_DATA_I(7 downto 0);            -- latch in baud rate to set
                            command   <= '1';                               -- strobe command to set the rate

                        when others =>                                      -- otherwise do nothing
                            null;
                    end case;
                else                                                        -- read: if there is data in the buffer, strobe rx_next_s to get next item from buffer
                    if rx_ready_s /= x"0" then
                        rx_next_s <= '1';
                    end if;
                end if;

            elsif (WBS_CYC_I = '0' OR WBS_STB_I = '0') then     -- wait for wishbone transaction to end
                ack <= '0';                 -- reset internal ack signal when that happens
            end if;
        end if;
    end process;

end rtl;