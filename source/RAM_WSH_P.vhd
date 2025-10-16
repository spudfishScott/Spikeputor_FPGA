-- RAM Wishbone Interface Provider
-- 32/16/8 K of RAM (in three separate blocks due to Cyclone III constraints of 56 blocks total), thus 0xE000-0xFFFF is not accessable and always returns 0
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
        -- RST_I       : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_ADDR_I  : in std_logic_vector(15 downto 0);     -- lsb is ignored, but it is still part of the address bus
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
    signal wbs_data8K   : std_logic_vector(15 downto 0) := (others => '0');
    signal wbs_data     : std_logic_vector(15 downto 0) := (others => '0');
    signal we_32K       : std_logic := '0';
    signal we_16K       : std_logic := '0';
    signal we_8K        : std_logic := '0';

begin
    RAM32K_inst : entity work.RAM   
        generic map (
            NUM_WORDS  => 16384,    -- 32K bytes = 16K words of 16 bits each
            ADDR_WIDTH => 14        -- 14 bits to address 16K words
        )
        port map (                  -- 32K bytes from 0x0000 to 0x7FFF - ADDR[15] = "0", ADDR[0] = don't care
            clock     => CLK,

            address => WBS_ADDR_I(14 downto 1),
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
            address => WBS_ADDR_I(13 downto 1),
            data      => WBS_DATA_I,
            wren      => we_16K AND WBS_CYC_I AND WBS_STB_I,    -- only write when we_16K and CYC and STB are asserted

            q         => wbs_data16K
        );
    
    RAM8K_inst : entity work.RAM
        generic map (
            NUM_WORDS  => 4096,     -- 8K bytes = 4K words of 16 bits each
            ADDR_WIDTH => 12        -- 12 bits to address 4K words
        )
        port map (                  -- 8K bytes from 0xC000 to 0xDFFF - ADDR[15:13]="110", ADDR[0] = don't care
            clock     => CLK,
            address => WBS_ADDR_I(12 downto 1),
            data      => WBS_DATA_I,
            wren      => we_8K AND WBS_CYC_I AND WBS_STB_I,     -- only write when we_8K and CYC and STB are asserted

            q         => wbs_data8K
        );

    -- output to wishbone interface

    WBS_DATA_O  <= wbs_data32K when WBS_ADDR_I(15) = '0' else               -- 32K block for addresses 0x0000-0x7FFF
                   wbs_data16K when WBS_ADDR_I(15 downto 14) = "10" else    -- 16K block for addresses 0x8000-0xBFFF
                   wbs_data8K  when WBS_ADDR_I(15 downto 13) = "110" else   -- 8K block  for addresses 0xC000-0xDFFF
                   zero16;                                                  -- return zero for addresses 0xE000-0xFFFF

    we_32K <= WBS_WE_I when WBS_ADDR_I(15) = '0' else '0';                  -- only write to 32K block when address is in range 0x0000-0x7FFF
    we_16K <= WBS_WE_I when WBS_ADDR_I(15 downto 14) = "10" else '0';       -- only write to 16K block when address is in range 0x8000-0xBFFF
    we_8K  <= WBS_WE_I when WBS_ADDR_I(15 downto 13) = "110" else '0';      -- only write to 8K block when address is in range 0xC000-0xDFFF

    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;         -- always acknowledge when CYC and STB are asserted

end rtl;