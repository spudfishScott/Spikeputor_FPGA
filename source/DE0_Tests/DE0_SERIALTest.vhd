-- a loader that writes to the DE0 Flash Chip from a serial connection - for Spikeputor /// ROM
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_SERIALTest is
    -- DE0 Pins
    port (
        -- CLOCK
        CLOCK_50    : in std_logic; -- 20 ns clock
        -- Push Button
        BUTTON      : in std_logic_vector(2 downto 0);
        -- LEDs
        LEDG        : out std_logic_vector(9 downto 0);
        -- DPDT Switch
        SW          : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D      : out std_logic_vector(6 downto 0);
        HEX0_DP     : out std_logic;
        HEX1_D      : out std_logic_vector(6 downto 0);
        HEX1_DP     : out std_logic;
        HEX2_D      : out std_logic_vector(6 downto 0);
        HEX2_DP     : out std_logic;
        HEX3_D      : out std_logic_vector(6 downto 0);
        HEX3_DP     : out std_logic;
        -- RS-232
        GPIO0_D     : inout std_logic_vector(29 downto 28) -- GPIO0[28] = SER_TX, GPIO0[29] = SER_RX
    );
end DE0_SERIALTest;

architecture rtl of DE0_SERIALTest is

    signal rx_data_s     : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready_s    : std_logic_vector(3 downto 0) := (others => '0');
    signal rx_next_s     : std_logic := '0';
    signal tx_data_s     : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_load_s     : std_logic := '0';
    signal tx_busy_s     : std_logic := '0';

    signal step_index    : integer := 0;
    signal delaying      : std_logic := '0';
    signal delay_cnt     : Integer := 50_000_000;

begin
    serial_controller: entity work.SERIAL
    port map (
        CLK         => CLOCK_50,                         -- System clock
        RST         => NOT BUTTON(0),                    -- Reset signal (active high)

        BAUD        => "0101",                           -- Baud Rate index 5 = 38400
        FLUSH       => '0',                              -- set high to flush buffer
        CMD         => NOT BUTTON(1),                    -- strobe to set new baud rate and/or flush buffer

        RX_SERIAL   => GPIO0_D(29),                      -- Serial data input
        RX_DATA     => rx_data_s,                        -- Received byte output
        RX_READY    => rx_ready_s,                       -- Number of bytes available on the buffer
        RX_NEXT     => rx_next_s,                        -- strobe to recieve a byte if available
        RX_OVERFLOW => LEDG(9),                          -- set if the ring buffer overflows

        TX_SERIAL   => GPIO0_D(28),                      -- Serial data output
        TX_DATA     => tx_data_s,                        -- Input byte to send
        TX_LOAD     => tx_load_s,                        -- Strobe to send a byte
        TX_BUSY     => tx_busy_s                         -- Indicates if the transmitter is busy
    );

    process(CLOCK_50) is
    begin
        if BUTTON(0) = '0' then -- reset
            step_index <= 0;
            delaying   <= '0';
            delay_cnt  <= 50_000_000;
            tx_load_s <= '0';
            rx_next_s <= '0';

        elsif rising_edge(CLOCK_50) then
            tx_load_s <= '0';                         -- set these back to zero for strobing
            rx_next_s <= '0';

            if (delaying = '1') then
                if delay_cnt = 0 then
                    delaying <= '0';
                    delay_cnt <= 50_000_000;        -- delay for one second each step
                else
                    delay_cnt <= delay_cnt - 1;     -- countdown delay timer
                end if;
            else
                step_index <= step_index + 1;       -- default is go to next step

                case (step_index) is
                    when 0 =>
                        if (tx_busy_s = '0') then   -- wait until we can send
                            tx_data_s <= x"2A";         -- transmit '*'
                            tx_load_s <= '1';           -- strobe to send
                            delaying <= '1';            -- delay for 1 second
                        else
                            step_index <= 0;    -- stay here until we can send
                        end if;
                    when 1 =>
                        if (rx_ready_s > x"0" and rx_next_s = '0') then    -- wait until we recieve something and next was strobed
                            rx_next_s <= '1';       -- request next byte
                            delaying <= '1';        -- delay for 1 second
                            if rx_data_s /= x"2A" then  -- stay here until we read a '*'
                                step_index <= 1;
                            end if;
                        else 
                            step_index <= 1;  -- stay here until we receive the byte
                        end if;
                    when 2 =>
                        if (tx_busy_s = '0') then   -- wait until we can send
                            tx_data_s <= x"2A";         -- transmit '*'
                            tx_load_s <= '1';           -- strobe to send
                            delaying <= '1';            -- delay for 1 second
                        else
                            step_index <= 2;    -- stay here until we can send
                        end if;
                    when others =>
                        step_index <= step_index;    -- just stay here forever when done
                end case;
            end if;
        end if;
    end process;

    -- Word to 7 Segment Output
    SEGSOUT : entity work.WORDTO7SEGS port map (
         WORD => rx_data_s & tx_data_s,    -- display the current bytes recieving/sending
        SEGS3 => HEX3_D,    -- display receiving byte in HEX3 and HEX2
        SEGS2 => HEX2_D,
        SEGS1 => HEX1_D,    -- display sending byte in HEX1 and HEX0
        SEGS0 => HEX0_D
    );

    -- assign output states for unused 7 segment displays and unused LEDs
    HEX0_DP <= '1';      -- clear all DP's
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    LEDG(3 downto 0) <= std_logic_vector(to_unsigned(step_index), 4);  -- show step number in binary
    LEDG(8 downto 5) <= rx_ready_s;                                 -- show number of bytes available in binary
    LEDG(4) <= '0';

end rtl;