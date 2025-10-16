-- This module synthesizes registers with various functionality

-- This is a D-REG that updates half at a time depending on the value of SEL and if LE and EN is set
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity REG_HILO is
    generic (width : positive := 8); -- width of register in bits

    port (
        RESET, CLK, EN, SEL, LE : in std_logic; -- reset, clock, clock enable, hi/lo select, latch enable active high
               D : in std_logic_vector((width/2)-1 downto 0);	-- input for hi/lo register is half the full width
               Q: out std_logic_vector(width-1 downto 0)     -- output is the full width register
    );
end REG_HILO;

architecture Behavior of REG_HILO is
    signal REG_HIGH : std_logic_vector((width/2)-1 downto 0) := (others => '0');
    signal REG_LOW : std_logic_vector((width/2)-1 downto 0) := (others => '0');

begin
    assert (width mod 2 = 0) severity failure;	-- for a hi/lo register, n must be even

    -- hi/lo D-REG with latch enable and asynchronous reset
    P_REG_HILO : process(CLK, RESET) is
    begin
        if (RESET = '1') then
            REG_HIGH <= (others => '0');
            REG_LOW <= (others => '0');
        elsif (rising_edge(CLK)) then -- rising edge of clock and REG is enabled
            if (EN = '1' and LE = '1') then -- if latch enable is high, update the correct half of the register
                if (SEL = '1') then
                    REG_HIGH <= D; -- if SEL is high, update the high portion of the register from input
                else
                    REG_LOW <= D; -- if SEL is low, update the low portion of the register from input
                end if;
            end if;
        end if;
    end process P_REG_HILO;

    Q <= REG_HIGH & REG_LOW;	-- output is concatenation of HIGH and LOW internal register
end Behavior;

--------------------------------------------------------------------------------------------------------------
-- This is an edge-triggered D-REG that requires a Latch Enable Signal to write data to the register
-- signal to change its contents.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity REG_LE is
    generic (width : positive := 8); -- width of register

    port (
        CLK, LE : in std_logic; -- clock, latch enable
        D : in std_logic_vector(width-1 downto 0);	-- input
        Q : out std_logic_vector(width-1 downto 0)	-- output
    );
end REG_LE;

architecture Behavior of REG_LE is
    signal DATA : std_logic_vector(width-1 downto 0) := (others => '0'); -- the internal data memory
begin

    P_REG_LE : process(CLK) is
    begin
        if (rising_edge(CLK)) then -- changes on rising edge of clock
            DATA <= DATA;
            if (LE = '1') then
                DATA <= D;
            end if;
        end if;
    end process P_REG_LE;

    -- send internal data to output
    Q <= DATA;
end Behavior;