-- RAM Wishbone Interface Provider
-- Test RAM module with internal memory array for simulation purposes

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity RAMTest_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

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

    -- internal signals
    signal addr : std_logic_vector(4 downto 0) := (others => '0');

begin
    -- Altera Memory: 32 words x 16 bits per word, 1 port, unregistered output, registered inputs
    testram_component: altsyncram generic map (
        clock_enable_input_a            => "BYPASS",
        clock_enable_output_a           => "BYPASS",
        intended_device_family          => "Cyclone III",
        lpm_hint                        => "ENABLE_RUNTIME_MOD=NO",
        lpm_type                        => "altsyncram",
        numwords_a                      => 32,
        operation_mode                  => "SINGLE_PORT",
        outdata_aclr_a                  => "NONE",
        outdata_reg_a                   => "UNREGISTERED",
        read_during_write_mode_port_a   => "NEW_DATA_NO_NBE_READ",
        width_a                         => 16,
        widthad_a                       => 5,         -- 2^5 = 32
        width_byteena_a                 => 1,
        init_file                       => "RAM32X16_TEST.MIF"
    ) port map (
        address_a => addr,
        clock0    => CLK,
        wren_a    => WBS_WE_I AND WBS_CYC_I AND WBS_STB_I,  -- only write when we and cyc and stb are asserted
        data_a    => WBS_DATA_I,
        q_a       => WBS_DATA_O
  );
    
    -- internal control signals
    addr        <= WBS_ADDR_I(5 downto 1);                  -- use address bits A5 to A1 to index 32 locations - ignore A15 to A6 and A0

    -- output to wishbone interface
    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;                 -- always acknowledge when CYC and STB are asserted

end rtl;
