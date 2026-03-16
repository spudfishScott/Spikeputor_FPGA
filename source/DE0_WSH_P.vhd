-- DE0 I/O Wishbone Interface Provider
    -- 0xFFF9 - status of switches and buttons - read only - top two bits always read as 0, then 10 bits for the 10 switches, then 3 bits for the 3 buttons
    -- 0xFFFA - number on 7 segment display - read/write
    -- 0xFFFB - four bits per 7 segment display bit 0: digit on/off, bit 1: replace digit with '-' sign, bit 2: replace digit with º sign, bit 3: decimal point on/off - read/write
    -- 0xFFFC - bottom 10 bits for on-board LEDs - read/write

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity DE0_WSH_P is
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
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- address input from master
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus

        -- DE0 I/O
        BUTTONS     : in std_logic_vector(2 downto 0);
        SWITCHES    : in std_logic_vector(9 downto 0);

        LEDS        : out std_logic_vector(9 downto 0);
        HEX0_D      : out std_logic_vector(6 downto 0);
        HEX1_D      : out std_logic_vector(6 downto 0);
        HEX2_D      : out std_logic_vector(6 downto 0);
        HEX3_D      : out std_logic_vector(6 downto 0);
        HEX0_DP     : out std_logic;
        HEX1_DP     : out std_logic;
        HEX2_DP     : out std_logic;
        HEX3_DP     : out std_logic
    );
end DE0_WSH_P;

architecture rtl of DE0_WSH_P is

    signal addr_l      : std_logic_vector(3 downto 0);     -- the bottom 4 bits of the address input, used for address decoding

    signal hex_le_sig  : std_logic := '0';                                      -- latch enable signal for hex display register
    signal hex_data_in : std_logic_vector(15 downto 0) := (others => '0');      -- data to be latched into hex display register
    signal hex_data    : std_logic_vector(15 downto 0) := (others => '0');      -- register for hex display data - set via 0xFFFA
    signal hex0        : std_logic_vector(6 downto 0) := (others => '1');       -- output for hex display 0
    signal hex1        : std_logic_vector(6 downto 0) := (others => '1');       -- output for hex display 1
    signal hex2        : std_logic_vector(6 downto 0) := (others => '1');       -- output for hex display 2
    signal hex3        : std_logic_vector(6 downto 0) := (others => '1');       -- output for hex display 3

    -- control signals for 7 segment hex display - set via 0xFFFB
    -- seg_ctrl bit 0: digit on/off, bit 1: decimal point on/off, bit 2: replace digit with '-' sign, bit 3: replace digit with º sign
    signal seg_ctrl_le_sig : std_logic := '0';                                  -- latch enable signal for 7 segment control register
    signal seg_ctrl_in     : std_logic_vector(15 downto 0) := (others => '0');  -- data to be latched into 7 segment control register
    signal seg_ctrl    : std_logic_vector(15 downto 0) := (others => '0');      -- all control signals packed in one word
    signal seg_ctrl0   : std_logic_vector(3 downto 0) := (others => '0');
    signal seg_ctrl1   : std_logic_vector(3 downto 0) := (others => '0');
    signal seg_ctrl2   : std_logic_vector(3 downto 0) := (others => '0');
    signal seg_ctrl3   : std_logic_vector(3 downto 0) := (others => '0');

    signal led_le_sig  : std_logic := '0';                                      -- latch enable signal for board-mounted led register
    signal led_data_in : std_logic_vector(9 downto 0) := (others => '0');       -- data to be latched into led register
    signal led_data    : std_logic_vector(9 downto 0) := (others => '0');       -- register for led data - set via 0xFFFC

begin
                -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS 
        port map (
            WORD  => hex_data,    -- hex display register
            SEGS0 => hex0,
            SEGS1 => hex1,
            SEGS2 => hex2,
            SEGS3 => hex3
        );

    SEG7 : entity work.REG_LE
    generic map ( width => 16 )
    port map (
        CLK => CLK,
        LE  => hex_le_sig,
        D   => hex_data_in,     -- latch new hex display data when CYC, STB, WE are high and address is 0xFFFA, otherwise clear to 0 on reset
        Q   => hex_data
    );

    SEG7_CTRL_REG : entity work.REG_LE
    generic map ( width => 16 )
    port map (
        CLK => CLK,
        LE  => seg_ctrl_le_sig,
        D   => seg_ctrl_in,     -- latch new 7 segment control data when CYC, STB, WE are high and address is 0xFFFB, otherwise clear to 0 on reset
        Q   => seg_ctrl
    );

    LED_REG : entity work.REG_LE
    generic map ( width => 10 )
    port map (
        CLK => CLK,
        LE  => led_le_sig,
        D   => led_data_in,     -- latch new led data when CYC, STB, WE are high and address is 0xFFFC, otherwise clear to 0 on reset
        Q   => led_data
    );

    addr_l <= WBS_ADDR_I(3 downto 0);     -- only care about the bottom 4 bits of the address since we're only decoding 4 addresses

    -- erase registers on reset
    hex_data_in <= WBS_DATA_I(15 downto 0) when RST_I = '0' else (others => '0');
    seg_ctrl_in <= WBS_DATA_I(15 downto 0) when RST_I = '0' else (others => '0');
    led_data_in <= WBS_DATA_I(9 downto 0) when RST_I = '0' else (others => '0');

    seg_ctrl0 <= seg_ctrl(3 downto 0);
    seg_ctrl1 <= seg_ctrl(7 downto 4);
    seg_ctrl2 <= seg_ctrl(11 downto 8);
    seg_ctrl3 <= seg_ctrl(15 downto 12);

    WBS_DATA_O <= "000" & SWITCHES & BUTTONS when addr_l = x"9"         -- output data is switch and button states zero padded
            else  hex_data                   when addr_l = x"A"         -- output data is hex display register
            else  seg_ctrl                   when addr_l = x"B"         -- output data is 7 segment control register
            else  "000000" & led_data        when addr_l = x"C"         -- output data is led register zero padded
            else  (others => '0');                                      -- default output data is 0

    -- latch 0 on reset, otherwise latch new data on write to the appropriate address
    hex_le_sig      <= '1' when RST_I = '1' OR ((WBS_CYC_I AND WBS_STB_I AND WBS_WE_I) = '1' AND addr_l = x"A") else '0';     -- latch new hex display data when CYC, STB, WE are high and address is 0xFFFA
    seg_ctrl_le_sig <= '1' when RST_I = '1' OR ((WBS_CYC_I AND WBS_STB_I AND WBS_WE_I) = '1' AND addr_l = x"B") else '0';     -- latch new 7 segment control data when CYC, STB, WE are high and address is 0xFFFB
    led_le_sig      <= '1' when RST_I = '1' OR ((WBS_CYC_I AND WBS_STB_I AND WBS_WE_I) = '1' AND addr_l = x"C") else '0';     -- latch new led data when CYC, STB, WE are high and address is 0xFFFC

    -- set up seven segment display outputs based on control signals and hex data register - control signals have priority over hex data bits
    HEX0_DP <= NOT seg_ctrl0(3);     -- decimal point control for hex display 0
    HEX1_DP <= NOT seg_ctrl1(3);     -- decimal point control for hex display 1
    HEX2_DP <= NOT seg_ctrl2(3);     -- decimal point control for hex display 2
    HEX3_DP <= NOT seg_ctrl3(3);     -- decimal point control for hex display 3

    HEX0_D <= "0111111" when seg_ctrl0(1) = '1' else                    -- if replace with '-' control bit is 1, turn on only the middle segment
              "0011100" when seg_ctrl0(2) = '1' else                    -- if replace with º control bit is 1, create the ° symbol
              (others => '1') when seg_ctrl0(0) = '0' else              -- if digit on/off control bit is 0, turn off all segments to blank the display
              hex0;                                                     -- otherwise, use normal hex display output

    HEX1_D <= "0111111" when seg_ctrl1(1) = '1' else
              "0011100" when seg_ctrl1(2) = '1' else
              (others => '1') when seg_ctrl1(0) = '0' else
              hex1;

    HEX2_D <= "0111111" when seg_ctrl2(1) = '1' else
              "0011100" when seg_ctrl2(2) = '1' else
              (others => '1') when seg_ctrl2(0) = '0' else
              hex2;

    HEX3_D <= "0111111" when seg_ctrl3(1) = '1' else
              "0011100" when seg_ctrl3(2) = '1' else
              (others => '1') when seg_ctrl3(0) = '0' else
              hex3;
    
    -- output for board-mounted LEDs
    LEDS <= led_data;

    process(clk) is
    begin
        if rising_edge(clk) then -- send acknowledge when we have a valid cycle and strobe
            WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
        end if;
    end process;

end rtl;
