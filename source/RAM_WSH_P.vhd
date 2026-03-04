-- RAM Wishbone Interface Provider
-- 32/16/2 K of RAM (in three separate blocks due to Cyclone III constraints of 56 blocks total less 3 blocks for math)
-- thus 0xC800-0xFFFF is not accessable and always returns 0
-- 16 bit wide data bus, 16 bit wide address bus
-- RAM address is always even (bit 0 is ignored), and a full word is returned on an even address boundary

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity RAM_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic                          -- write enable input - when high, master is writing, when low, master is reading
    );
end RAM_WSH_P;

architecture rtl of RAM_WSH_P is

    -- internal signals
    constant zero16     : std_logic_vector(15 downto 0) := (others => '0');

    signal wbs_data32K  : std_logic_vector(15 downto 0) := (others => '0');
    signal wbs_data16K  : std_logic_vector(15 downto 0) := (others => '0');
    signal wbs_data2K   : std_logic_vector(15 downto 0) := (others => '0');

    signal we_32K       : std_logic := '0';
    signal we_16K       : std_logic := '0';
    signal we_2K        : std_logic := '0';

begin
    RAM32K_inst : entity work.RAM   
        generic map (
            NUM_WORDS  => 16384,    -- 32K bytes = 16K words of 16 bits each
            ADDR_WIDTH => 14        -- 14 bits to address 16K words
        )
        port map (                  -- 32K bytes from 0x0000 to 0x7FFF - ADDR[15] = "0", ADDR[0] = don't care
            clock     => CLK,

            address   => WBS_ADDR_I(14 downto 1),
            data      => WBS_DATA_I,
            wren      => we_32K AND WBS_CYC_I AND WBS_STB_I,    -- only write when we_32K and CYC and STB are asserted

            q         => wbs_data32K
        );

    RAM16K_inst : entity work.RAM
        generic map (
            NUM_WORDS  => 8192,     -- 16K bytes = 8K words of 16 bits each
            ADDR_WIDTH => 13        -- 13 bits to address 8K words
        )
        port map (                  -- 16K bytes from 0x8000 to 0xBFFF - ADDR[15:14]="10", ADDR[0] = don't care
            clock     => CLK,
            address   => WBS_ADDR_I(13 downto 1),
            data      => WBS_DATA_I,
            wren      => we_16K AND WBS_CYC_I AND WBS_STB_I,    -- only write when we_16K and CYC and STB are asserted

            q         => wbs_data16K
        );
    
    RAM2K_inst : entity work.RAM
        generic map (
            NUM_WORDS  => 1024,     -- 2K bytes = 1K words of 16 bits each
            ADDR_WIDTH => 10        -- 10 bits to address 1K words
        )
        port map (                  -- 2K bytes from 0xC000 to 0xC7FF - ADDR[15:11]="11000", ADDR[0] = don't care
            clock     => CLK,
            address   => WBS_ADDR_I(11 downto 1),
            data      => WBS_DATA_I,
            wren      => we_2K AND WBS_CYC_I AND WBS_STB_I,     -- only write when we_2K and CYC and STB are asserted

            q         => wbs_data2K
        );

    -- output to wishbone interface
    WBS_DATA_O  <= wbs_data32K when WBS_ADDR_I(15) = '0' else               -- 32K block for addresses 0x0000-0x7FFF
                   wbs_data16K when WBS_ADDR_I(15 downto 14) = "10" else    -- 16K block for addresses 0x8000-0xBFFF
                   wbs_data2K  when WBS_ADDR_I(15 downto 11) = "11000" else -- 2K block  for addresses 0xC000-0xC7FF
                   zero16;                                                  -- return zero for addresses 0xC800-0xFFFF (will not get here - comparitor routes to ROM for 0xD000-0xFFFF)

    -- internal address select and write enable logic
    we_32K <= WBS_WE_I when WBS_ADDR_I(15) = '0' else '0';                  -- only write to 32K block when address is in range 0x0000-0x7FFF
    we_16K <= WBS_WE_I when WBS_ADDR_I(15 downto 14) = "10" else '0';       -- only write to 16K block when address is in range 0x8000-0xBFFF
    we_2K  <= WBS_WE_I when WBS_ADDR_I(15 downto 11) = "11000" else '0';     -- only write to 2K block when address is in range 0xC000-0xC7FF

    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;         -- always acknowledge when CYC and STB are asserted

end rtl;