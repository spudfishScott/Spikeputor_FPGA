-- a loader that writes to the DE0 Flash Chip from a serial connection - for Spikeputor /// ROM
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_UART_Test is
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
        UART_RXD    : in  std_logic;
        UART_TXD    : out std_logic
    );
end DE0_UART_Test;

architecture rtl of DE0_FLASHProg is
    signal received : std_logic_vector(7 downto 0);     -- byte received from the UART
    signal byte_ready : std_logic;
    signal reg_value : std_logic_vector(7 downto 0);    -- register to hold last sent byte

begin
    uart_controller: entity work.UART
        generic map (
            CLK_SPEED => 50000000,        -- 50 MHz clock speed
            BAUD_RATE => 115200           -- Baud rate for UART communication
        )
        port map (
            CLK        => CLOCK_50,
            RST        => NOT BUTTON(0),    -- Reset on button press
            RX_SERIAL  => UART_RXD,         -- Serial data input
            RX_DATA    => received,         -- Received byte output
            RX_READY   => byte_ready,       -- Strobed when a byte has been received
            TX_SERIAL  => UART_TXD,         -- Serial data output
            TX_DATA    => SW(7 downto 0),   -- Data to send through UART (set through switches)
            TX_LOAD    => NOT BUTTON(2),    -- Press button to send a byte
            TX_BUSY    => LED(0)            -- Indicates if the transmitter is busy
        );

    reg: entity work.REG_LE
        port map (
            RESET       => NOT BUTTON(0),
            EN          => '1',             -- enabled on every clock pulse
            LE          => byte_ready,      -- when a byte has been received, enable the register latch
            D           => received,        -- the received byte
            Q           => reg_value        -- the stored value in the register
        );

    -- Word to 7 Segment Output
    SEGSOUT : entity work.WORDTO7SEGS port map (
         WORD => reg_value & "00000000",    -- display the current byte in the register, padded with zeros
        SEGS3 => HEX3_D,    -- display byte in HEX3 and HEX2
        SEGS2 => HEX2_D,
        SEGS1 => null,      -- unused
        SEGS0 => null       -- unused
    );

    -- assign output states for unused 7 segment displays and unused LEDs
    HEX0_DP <= '1';      -- clear all DP's
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    HEX0_D <= "1111111"; -- clear all segments of HEX0
    HEX1_D <= "1111111"; -- clear all segments of HEX1
    LEDG(9 downto 1) <= (others => '0');

end rtl;