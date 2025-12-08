-- GPO Register Wishbone Interface Provider
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity GPO_WSH_P is
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
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus

        -- system outputs
        GPO         : out std_logic_vector(15 downto 0)     -- the output of the GPO register
    );
end GPO_WSH_P;

architecture rtl of GPO_WSH_P is
    signal le_sig : std_logic;
    signal gpo_sig : std_logic_vector(15 downto 0);

begin
    GPO_REG : entity work.REG_LE
    generic map ( width => 16 )
    port map (
        CLK => CLK,
        LE  => le_sig,       -- only write when we and cyc and stb are all asserted
        D   => WBS_DATA_I(15 downto 0),
        Q   => gpo_sig
    );

    GPO        <= gpo_sig;
    WBS_DATA_O <= gpo_sig;
    
    le_sig     <= WBS_CYC_I AND WBS_STB_I AND WBS_WE_I;

    process(clk) is
    begin
        if rising_edge(clk) then
            WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
        end if;
    end process;

end rtl;


-- GPI Register Wishbone Interface Provider
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity GPI_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read signals - GPI is read only
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus

        -- system outputs
        GPI         : out std_logic_vector(15 downto 0)     -- the GPI input port
    );
end GPI_WSH_P;

architecture rtl of GPI_WSH_P is

begin
    WBS_DATA_O <= GPI;
    WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
end rtl;