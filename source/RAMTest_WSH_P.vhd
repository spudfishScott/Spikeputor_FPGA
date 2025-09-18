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
    type MEMARRAY is array(0 to 31) of std_logic_vector(15 downto 0);
    -- internal signals
    signal memory : MEMARRAY;
    signal memIndex : integer := 0;

begin
    -- Initialize RAM contents on reset
    process(CLK)
    begin
        if rising_edge(CLK) then
            if RST_I = '1' then
                -- Initialize memory array with test data
                memory(0) <= x"4408";  -- code to write to memory for testing
                memory(1) <= x"001E";
                memory(2) <= x"46C8";
                memory(3) <= x"0020";
                memory(4) <= x"4C09";
                memory(5) <= x"0002";
                memory(6) <= x"4011";
                memory(7) <= x"4741";
                memory(8) <= x"FFF2";
                memory(9) <= x"4690";
                memory(10) <= x"0018";
                memory(11) <= x"4700";
                memory(12) <= x"FFFC";
                -- Initialize remaining memory locations to 0
                for i in 13 to 31 loop
                    memory(i) <= x"0000";
                end loop;
            elsif WBS_WE_I = '1' and WBS_CYC_I = '1' and WBS_STB_I = '1' then
                memory(memIndex) <= WBS_DATA_I;
            end if;
        end if;
    end process;
    memIndex <= to_integer(unsigned(WBS_ADDR_I(4 downto 0)));   -- use address bits A4 to A0 to index 32 locations

    -- output to wishbone interface
    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;                     -- always acknowledge when CYC and STB are asserted

    WBS_DATA_O  <= memory(memIndex);                            -- return array location based on address bits A4 to A0
end rtl;