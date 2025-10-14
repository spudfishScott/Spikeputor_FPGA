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
    -- type MEMARRAY is array(0 to 31) of std_logic_vector(15 downto 0);

    -- internal signals
    -- signal memory : MEMARRAY := (others => (others => '0'));
    signal addr : std_logic_vector(4 downto 0);
    signal q : std_logic_vector(15 downto 0) := (others => '0');
    signal MEM_WE : std_logic := '0';
    -- signal MEM_CE : std_logic := '0';

begin
    -- Initialize RAM contents on reset
    -- process(CLK)
    -- begin
    --     if rising_edge(CLK) then
    --         if RST_I = '1' then
    --             -- Initialize memory array with test data
    --             memory(0) <= x"4408";  -- code to write to memory for testing
    --             memory(1) <= x"001E";
    --             memory(2) <= x"4691";
    --             memory(3) <= x"0020";
    --             memory(4) <= x"4091";
    --             memory(5) <= x"46D1";
    --             memory(6) <= x"0020";
    --             memory(7) <= x"4C09";
    --             memory(8) <= x"0002";
    --             memory(9) <= x"4741";
    --             memory(10) <= x"FFEE";
    --             memory(11) <= x"4700";
    --             memory(12) <= x"FFFC";
    --             -- Initialize remaining memory locations to 0
    --             for i in 13 to 31 loop
    --                 memory(i) <= x"0000";
    --             end loop;
    --             q <= (others => '0');
    --         else
    --             if MEM_CE = '1' then
    --                 if MEM_WE = '1' then
    --                     memory(memIndex) <= WBS_DATA_I;
    --                 end if;
    --                 q <= memory(memIndex);           -- return array location based on address bits A5 to A1
    --             end if;
    --         end if;
    --     end if;
    -- end process;

    -- Altera Memory: 32 words x 16 bits per word, 1 port
    testram_component: altsyncram generic map (
        clock_enable_input_a    => "BYPASS",
        clock_enable_output_a => "BYPASS",
        intended_device_family => "Cyclone III",
        lpm_hint => "ENABLE_RUNTIME_MOD=NO",
        lpm_type => "altsyncram",
        numwords_a => 32,
        operation_mode => "SINGLE_PORT",
        outdata_aclr_a => "NONE",
        outdata_reg_a           => "CLOCK0",
        read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
        width_a                 => 16,
        widthad_a               => 5,         -- 2^5 = 32
        width_byteena_a => 1,
        power_up_uninitialized => "FALSE",  -- maybe don't include??
        init_file               => "RAM32X16_TEST.MIF"
    ) port map (
        address_a => addr,
        clock0    => clk,
        wren_a    => MEM_WE,
        data_a    => WBS_DATA_I,
        q_a       => q
  );

    -- address mapping
    -- memIndex <= to_integer(unsigned(WBS_ADDR_I(5 downto 1)));   -- use address bits A5 to A1 to index 32 locations - ignore A15 to A6 and A0
    addr <= WBS_ADDR_I(5 downto 1);                                -- use address bits A5 to A1 to index 32 locations - ignore A15 to A6 and A0

    -- internal control signals
    -- MEM_CE <= (WBS_CYC_I AND WBS_STB_I);
    MEM_WE <= WBS_WE_I;

    -- output to wishbone interface
    WBS_ACK_O   <= WBS_STB_I AND WBS_CYC_I;                     -- always acknowledge when CYC and STB are asserted
    WBS_DATA_O  <= q;
end rtl;
