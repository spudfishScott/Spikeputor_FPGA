-- SEGMENT Register Wishbone Interface Provider

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity SEGMENT_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;
        WBS_TGD_I   : in std_logic_vector(1 downto 0);     -- 0b01 for DATA_SEGMENT (just SEGMENT for now, other tbd), 0b10 for PC_SEGMENT

        -- memory read/write signals
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus. We're including it but it never gets used because reads are handled in the CTRL_WSH_M module

        -- system outputs
        DATA_SEGMENT     : out std_logic_vector(7 downto 0);      -- the output of the DATA_SEGMENT register
        PC_SEGMENT       : out std_logic_vector(7 downto 0)       -- the output of the PC_SEGMENT register
    );
end SEGMENT_WSH_P;

architecture rtl of SEGMENT_WSH_P is
    signal le_data_sig : std_logic := '0';
    signal le_pc_sig   : std_logic := '0';

    signal data_segment_sig : std_logic_vector(7 downto 0) := (others => '0');
    signal pc_segment_sig   : std_logic_vector(7 downto 0) := (others => '0');

    signal data_in          : std_logic_vector(7 downto 0) := (others => '0');

begin
    -- instantiate the two segment registers
    DATA_SEG_REG : entity work.REG_LE
    generic map ( width => 8 )
    port map (
        CLK => CLK,
        LE  => le_data_sig,       -- only write when we and cyc and stb are all asserted and tgd is for DATA
        D   => data_in,
        Q   => data_segment_sig
    );

    PC_SEG_REG : entity work.REG_LE
    generic map ( width => 8 )
    port map (
        CLK => CLK,
        LE  => le_pc_sig,         -- only write when we and cyc and stb are all asserted and tgd is for DATA
        D   => data_in,
        Q   => pc_segment_sig
    );

    -- if RST = '1', clear the registers
    data_in     <= WBS_DATA_I(7 downto 0) when RST_I = '0' else (7 downto 0 => '0');

    le_data_sig <= (WBS_CYC_I AND WBS_STB_I AND WBS_WE_I AND WBS_TGD_I(0)) OR RST_I = '1';   -- bit 0 of TGD is for DATA SEGMENT
    le_pc_sig   <= (WBS_CYC_I AND WBS_STB_I AND WBS_WE_I AND WBS_TGD_I(1)) OR RST_I = '1';   -- bit 1 of TGD is for PC SEGMENT

    DATA_SEGMENT <= data_segment_sig;
    PC_SEGMENT   <= pc_segment_sig;

    WBS_DATA_O <= (15 downto 8 => '0') & pc_segment_sig when WBS_TGD_I(1) = '1'
            else  (15 downto 8 => '0') & data_segment_sig when WBS_TGD_I(0) = '1';

    process(clk) is
    begin
        if rising_edge(clk) then
            WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
        end if;
    end process;

end rtl;
