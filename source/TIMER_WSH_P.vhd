-- TIMER Wishbone Interface Provider
-- memory registers as follows:
    -- 0xFFEA - Time since startup in microseconds [15:0]
    -- 0xFFF9 - Time since startup in microseconds [31:16]
    -- 0xFFF8 - Time since startup in microseconds [47:32]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity TIMER_WSH_P is
     generic ( CLK_FREQ : integer := 50_000_000 );            -- system clock frequency in Hz (must be at least 1 MHz)
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals (read-opnly for now)
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);       -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0)--;    -- data output to master
        --WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        --WBS_WE_I    : in std_logic                          -- write enable input - when high, master is writing, when low, master is reading
    );
end TIMER_WSH_P;

architecture rtl of TIMER_WSH_P is

    signal timer         : unsigned(47 downto 0) := (others => '0'); -- timer since startup in microseconds
    signal counter       : natural range 0 to 1_000_000 := 0;          -- counts one microsecond period
    signal ack           : std_logic := '0';                           -- wishbone ack signal
begin

    process(CLK)
    begin
        if rising_edge(CLK) then
            if counter = (CLK_FREQ / 1_000_000) - 1 then
                counter <= 0;            -- reset counter
                timer <= timer + 1;     -- increment timer by 1 us
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;

    WBS_ACK_O <= ack AND WBS_CYC_I AND WBS_STB_I; -- ack out is internal ack if CYC and STB are asserted, else 0

    with WBS_ADDR_I(3 downto 0) select
        WBS_DATA_O <=
            std_logic_vector(timer(15 downto 0))  when "1010", -- 0xFFEA read is [15:0]
            std_logic_vector(timer(31 downto 16)) when "1001", -- 0xFFE9 read is [31:16]
            std_logic_vector(timer(47 downto 32)) when "1000", -- 0xFFE8 read is [47:32]
            (others => '0')                      when others; -- otherwise 0

    process(CLK) is -- wishbone transaction process
    begin
        if rising_edge(CLK) then
            if WBS_CYC_I = '1' AND WBS_STB_I = '1' AND ack = '0' then -- wait for wishbone transaction to start
                ack <= '1'; -- acknowledge on next cycle
                -- if WBS_WE_I = '1' then                                        -- write: take action based on which register being written
                --     case WBS_ADDR_I(3 downto 0) is                              -- get bottom nybble of address
                --         when "1011" =>      -- 0xFFEB = function control - TODO
                --         when others =>                                          -- everything else is read-only
                --             null;
                --     end case;
                -- end if;

            elsif WBS_CYC_I = '0' OR WBS_STB_I = '0' then -- wait for wishbone transaction to end
                ack <= '0'; -- reset internal ack signal when that happens
            end if;
        end if;
    end process;

end rtl;