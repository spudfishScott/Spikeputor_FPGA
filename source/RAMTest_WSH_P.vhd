-- RAM Wishbone Interface Provider
-- Test RAM module with internal memory array for simulation purposes

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity RAMTest_WSH_P is
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
        WBS_ADDR_I  : in std_logic_vector(15 downto 0);     -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic                          -- write enable input - when high, master is writing, when low, master is reading
    );
end RAMTest_WSH_P;

architecture rtl of RAMTest_WSH_P is
    type MEMARRAY is array(0 to 31) of std_logic_vector(16 downto 0);
    -- internal signals

    signal memory : MEMARRAY :=  (-- initialize memory array with test data
                            x"4408", x"001E", x"46C8", x"0020", -- code to write to memory for testing
                            x"4C09", x"0002", x"4011", x"4741",
                            x"FFF2", x"4690", x"0018", x"4700",
                            x"FFFC", x"0000", x"0000", x"0000",
                            x"0000", x"0000", x"0000", x"0000", -- the memory to write to
                            x"0000", x"0000", x"0000", x"0000",
                            x"0000", x"0000", x"0000", x"0000",
                            x"0000", x"0000", x"0000", x"0000" -- memory locations 0x0000 to 0x001F
                        );
    signal memIndex : integer := 0;

begin
    memIndex <= to_integer(unsigned(WBS_ADDR_I(4 downto 0)));   -- use address bits A4 to A0 to index 32 locations

    -- output to wishbone interface
    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;                     -- always acknowledge when CYC and STB are asserted

    WBS_DATA_O  <= memory(memIndex);                            -- return array location based on address bits A4 to A0

    -- write to array location based on address bits A4 to A0 when WE, CYC, and STB are asserted, otherwise retain previous value
    memory(memIndex) <= WBS_DATA_I when WBS_WE_I = '1' AND WBS_CYC_I = '1' AND WBS_STB_I = '1' 
                                        else memory(memIndex);
end rtl;