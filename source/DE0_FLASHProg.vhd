-- a loader that writes to the DE0 Flash Chip from a serial connection - for Spikeputor /// ROM
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_FLASHProg is
    -- DE0 Pins
    port (
        -- CLOCK
        CLOCK_50      : in std_logic; -- 20 ns clock
        -- Push Button
        BUTTON        : in std_logic_vector(2 downto 0);
        -- LEDs
        LEDG          : out std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D        : out std_logic_vector(6 downto 0);
        HEX0_DP       : out std_logic;
        HEX1_D        : out std_logic_vector(6 downto 0);
        HEX1_DP       : out std_logic;
        HEX2_D        : out std_logic_vector(6 downto 0);
        HEX2_DP       : out std_logic;
        HEX3_D        : out std_logic_vector(6 downto 0);
        HEX3_DP       : out std_logic;
        -- RS-232
        UART_RXD      : in  std_logic;
        UART_TXD      : out std_logic;
        -- Flash chip pins
        FL_WP_N       : out std_logic;
        FL_BYTE_N     : out std_logic;
        FL_RST_N      : out std_logic;
        FL_CE_N       : out std_logic;
        FL_OE_N       : out std_logic;
        FL_WE_N       : out std_logic;
        FL_RY         : in  std_logic;
        FL_ADDR       : out std_logic_vector(21 downto 0);
        FL_DQ         : inout std_logic_vector(15 downto 0)
    );
end DE0_FLASHProg;

architecture rtl of DE0_FLASHProg is

    -- Internal signals for interconnection
    signal flash_ready  : std_logic;
    signal flash_address: std_logic_vector(21 downto 0);
    signal flash_data   : std_logic_vector(15 downto 0);
    signal flash_write  : std_logic;
    signal flash_erase  : std_logic_vector(1 downto 0);

    signal uart_rx_data : std_logic_vector(7 downto 0);
    signal uart_rx_rdy  : std_logic;
    signal uart_tx_data : std_logic_vector(7 downto 0);
    signal uart_tx_load : std_logic;
    signal uart_tx_busy : std_logic;

begin
    -- UART Flash Loader
    uart_loader: entity work.uart_flash_loader
        generic map (
            SECTOR_ADDR => "000001"     -- 000001 is the first 64 KB sector
        )
        port map (
            CLK        => CLOCK_50,       -- System clock (50 MHz)
            RST        => NOT BUTTON(0),  -- Reset on button press
            RX_DATA    => uart_rx_data,   -- Data received from UART
            RX_READY   => uart_rx_rdy,    -- Strobed when a byte is ready to be read from UART
            TX_DATA    => uart_tx_data,   -- Data to send through UART
            TX_LOAD    => uart_tx_load,   -- Strobe to load data into UART transmitter
            TX_BUSY    => uart_tx_busy,   -- Indicates if UART transmitter is busy
            FLASH_RDY  => flash_ready,    -- Flash controller ready signal
            ADDR_OUT   => flash_address,  -- Address for next word
            DATA_OUT   => flash_data,     -- Data word to write to flash
            WR_OUT     => flash_write,    -- Write signal to flash controller
            ERASE_OUT  => flash_erase,    -- Chip erase signal to flash controller
            ACTIVITY   => LEDG(0),        -- Activity indicator (LED)
            COMPLETED  => LEDG(1)         -- Transfer completed indicator (LED)
        );

    uart_controller: entity work.UART
        generic map (
            CLK_SPEED  => 50_000_000,     -- 50 MHz clock speed
            BAUD_RATE  => 38400           -- Baud rate for UART communication
                                          -- (where two bytes is sent in the time it takes to write a word to FLASH memory)
        )
        port map (
            CLK        => CLOCK_50,
            RST        => NOT BUTTON(0),  -- Reset on button press
            RX_SERIAL  => UART_RXD,       -- Serial data input
            RX_DATA    => uart_rx_data,   -- Received byte output
            RX_READY   => uart_rx_rdy,    -- Strobed when a byte has been received
            TX_SERIAL  => UART_TXD,       -- Serial data output
            TX_DATA    => uart_tx_data,   -- Data to send through UART
            TX_LOAD    => uart_tx_load,   -- Strobe to send a byte
            TX_BUSY    => uart_tx_busy    -- Indicates if the transmitter is busy
        );

    -- Word to 7 Segment Output
    SEGSOUT : entity work.WORDTO7SEGS port map (
        WORD  => flash_address(15 downto 0),   -- display the current address
        SEGS3 => HEX3_D,
        SEGS2 => HEX2_D,
        SEGS1 => HEX1_D,
        SEGS0 => HEX0_D
    );

    -- Flash Controller
    flash_ctrl: entity work.FLASH_RAM
        generic map (
            MAIN_CLK_NS => 20  -- 50 MHz
        )
        port map (
            CLK_IN      => CLOCK_50,
            RST_IN      => NOT BUTTON(0),           -- Reset on button press
            ERASE_IN    => flash_erase,             -- Controller chip erase signal
            RD_IN       => '0',                     -- Not used by loader
            WR_IN       => flash_write,             -- Controller write signal
            ADDR_IN     => flash_address,           -- Current flash controller address
            DATA_IN     => flash_data,              -- Data to write to flash
            DATA_OUT    => open,                    -- Not used by loader
            READY_OUT   => flash_ready,             -- Controller ready signal
            VALID_OUT   => LEDG(9),                 -- valid write indicator
            ERROR_OUT   => LEDG(8),                 -- error indicator
            WP_n        => FL_WP_N,                 -- write protection signal (active low)
            BYTE_n      => FL_BYTE_N,               -- byte mode signal (word mode high)
            RST_n       => FL_RST_N,                -- chip reset signal
            CE_n        => FL_CE_N,                 -- chip enable signal
            OE_n        => FL_OE_N,                 -- chip output enable signal
            WE_n        => FL_WE_N,                 -- chip write enable signal
            BY_n        => FL_RY,                   -- chip ready/~busy signal
            A           => FL_ADDR,                 -- chip address output
            DQ          => FL_DQ                    -- chip data input/output
        );

     -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(2) <= not BUTTON(0); -- show reset button being pushed
    LEDG(7 downto 3) <= (others => '0');
end rtl;