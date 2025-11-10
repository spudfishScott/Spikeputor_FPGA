-- SEGMENT Register Wishbone Interface Provider

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity SEGMENT_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus. We're including it but it never gets used.

        -- system outputs
        SEGMENT     : out std_logic_vector(7 downto 0)      -- the output of the SEGMENT register
    );
end SEGMENT_WSH_P;

architecture rtl of SEGMENT_WSH_P is
    signal le_sig : std_logic;
    signal segment_sig : std_logic_vector(7 downto 0);

begin
    SEG_REG : entity work.REG_LE
    generic map ( width => 8 )
    port map (
        CLK => CLK,
        LE  => le_sig,       -- only write when we and cyc and stb are all asserted
        D   => WBS_DATA_I(7 downto 0),
        Q   => segment_sig
    );

    SEGMENT    <= segment_sig;
    WBS_DATA_O <= (15 downto 8 => '0') & segment_sig;
    
    le_sig     <= WBS_CYC_I AND WBS_STB_I AND WBS_WE_I;

    process(clk) is
    begin
        if rising_edge(clk) then
            WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
        end if;
    end process;

end rtl;
