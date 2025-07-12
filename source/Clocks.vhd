-- This module synthesizes a few kinds of clocks

-- Clock Frequency Divider
-- This entity synthesizes a clock of desired frequency from an input clock of defined frequency and duty cycle
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FREQ_CLOCK is
    generic ( -- Desired Frequency in Hz
        FREQUENCY : Integer := 1000;
        SRC_FREQ : Integer := 50000000;
        DUTY_CYC : Integer := 50
    );

    port(
        CLK_IN : in std_logic;
        CLK_OUT : out std_logic
    );
end FREQ_CLOCK;

architecture Behavior of FREQ_CLOCK is
    signal COUNTER : unsigned(31 downto 0) := 0;

begin
    CLK_DIV : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if (COUNTER >= SRC_FREQ/FREQUENCY) then
                COUNTER <= 0;
            else
                COUNTER <= COUNTER + 1;
            end if;
        end if;
    end process CLK_DIV;

    CLK_OUT <= '1' when (COUNTER < ((SRC_FREQ/FREQUENCY) * DUTY_CYC / 100)) else '0';
end Behavior;

------------------------------------------------------------------------------------------------------------------
-- Clock Enable entity
-- Produces an enable signal every QUANTA_ENABLE ticks of QUANTA_MAX ticks
-- Everyone gets the system clock signal and their own clock enable signal as required
-- This gives a more FPGA-friendly "clock divider" with one monolithic clock signal and tailored enable signals
-- Includes asynchronous reset 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CLK_ENABLE is
    generic (
        QUANTA_MAX : Integer := 4;
        QUANTA_ENABLE : Integer := 1
    );

    port (
        CLK_IN : in std_logic;
        CLK_EN : out std_logic
    );
end CLK_ENABLE;

architecture Behavior of CLK_ENABLE is
    signal QUANTA : Integer range 0 to 32767 := 0;

begin
    CLK_TICK : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if (QUANTA < QUANTA_MAX - 1) then
                QUANTA <= QUANTA + 1;
            else
                QUANTA <= 0;
            end if;
        end if;
    end process CLK_TICK;

    CLK_EN <= '1' when QUANTA = QUANTA_ENABLE - 1 else '0';
end Behavior;

------------------------------------------------------------------------------------------------------------------
-- Timed Pulse Generator
-- Generates a pulse of specified width in clock ticks
-- pulse starts immediately and ends after the specified number of clock ticks
-- If START_PULSE is low before pulse is finished, the pulse is deactivated and the counter resets
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PULSE_GEN is
    generic (
        PULSE_WIDTH : Integer := 10 -- Pulse width in clock ticks
    );

    port (
        START_PULSE : in std_logic; -- Signal to start the pulse
        CLK_IN : in std_logic;
        PULSE_OUT : out std_logic
    );
end PULSE_GEN;

architecture Behavior of PULSE_GEN is
    signal COUNTER : unsigned(31 downto 1) := 0;
    signal PULSE_ACTIVE : std_logic := '0';

begin
    PULSE_GEN_PROCESS : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
		      if START_PULSE = '1' then
                if PULSE_ACTIVE = '1' then
                    if (COUNTER < PULSE_WIDTH) then -- freezes the counter after reaching the desired pulse width
                        COUNTER <= COUNTER + 1;
                    end if;
                else    -- get ready for a new pulse
                    PULSE_ACTIVE <= '1';        -- Activate pulse counting
                end if;
            else							    -- if START_PULSE goes low, deactivate pulse
                PULSE_ACTIVE <= '0';    -- deactivate pulse when START_PULSE goes low
                COUNTER <= 0;           -- Reset counter
				end if;
        end if;
    end process PULSE_GEN_PROCESS;

    -- PULSE_OUT is 1 when the counter is less than the pulse width and START_PULSE is high
    PULSE_OUT <= '1' when ((COUNTER < PULSE_WIDTH) and START_PULSE = '1') else '0';

end Behavior;
