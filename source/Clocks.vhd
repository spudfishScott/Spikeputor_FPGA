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
    signal COUNTER : Integer := 0;

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
    signal QUANTA : Integer := 0;

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
    signal COUNTER : Integer := 0;
    signal PULSE_ACTIVE : std_logic := '0';

begin
    PULSE_GEN_PROCESS : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
				PULSE_ACTIVE <= START_PULSE;    -- PULSE_ACTIVE changes based on the START_PULSE input
                if (PULSE_ACTIVE = '1' AND COUNTER < PULSE_WIDTH) then
                        COUNTER <= COUNTER + 1;    -- increment the counter if pulse active and counter not done
                 end if;
					if START_PULSE = '0' then
                  COUNTER <= 0;           -- Reset counter when pulse_start goes low
					end if;
        end if;
    end process PULSE_GEN_PROCESS;

    -- PULSE_OUT is 1 when the counter is less than the pulse width and START_PULSE is high
    PULSE_OUT <= '1' when ((COUNTER < PULSE_WIDTH) and START_PULSE = '1') else '0';

end Behavior;

------------------------------------------------------------------------------------------------------------------
-- This is an auto/manual clock generator 
-- In manual mode, a clock pulse is generated on each rising edge of the CLK_IN input, syncronized with system_clk
-- in automatic mode, a clock pulse of specified frequency is generated from the system clock
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AUTO_MANUAL_CLOCK is
    generic (
        AUTO_FREQ : Integer := 1            -- Frequency in Hz for automatic clock mode
        SYS_FREQ  : Integer := 50000000     -- System clock frequency in Hz
    );
    port (
        SYS_CLK     : in std_logic;  -- 50 MHz system clock input
        MAN_SEL     : in std_logic;  -- signal to select between auto or manual clock
        MAN_START   : in std_logic;  -- manual clock start signal (from button)
        CLK_EN      : out std_logic  -- output clock enable signal
    );
end AUTO_MANUAL_CLOCK;

architecture RTL of AUTO_MANUAL_CLOCK is
 --signals for clock logic
    signal previous_man : std_logic := '1';
    signal clock_counter : integer := 0;

    constant MAX_COUNT : integer := SYS_FREQ/AUTO_FREQ;

    begin
        -- Select between automatic and manual clock based on SW(0) - manual clock is KEY(1)
        clock : process(SYS_CLK) is
        begin
            if rising_edge(SYS_CLK) then
                if MAN_SEL = '0' then
                    if clock_counter = MAX_COUNT then  -- AUTO_FREQ Hz clock from SYS_FREQ Hz input
                        clock_counter <= 0;
                        CLK_EN <= '1';  -- generate clock enable pulse when counter reaches max
                    else
                        clock_counter <= clock_counter + 1;
                        CLK_EN <= '0';
                    end if;
                else
                    if previous_man = '0' and MAN_START = '1' then -- rising edge of manual start signal
                        CLK_EN <= '1';
                    else
                        CLK_EN <= '0';
                    end if;
                        previous_man <= MAN_START;
                end if;
            end if;
        end process clock;
end RTL;
