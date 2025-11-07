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
    signal counter : Integer := 0;

begin
    CLK_DIV : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if (counter >= SRC_FREQ/FREQUENCY) then
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process CLK_DIV;

    CLK_OUT <= '1' when (counter < ((SRC_FREQ/FREQUENCY) * DUTY_CYC / 100)) else '0';
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
        QUANTA_MAX    : Integer := 4;
        QUANTA_ENABLE : Integer := 1
    );

    port (
        CLK_IN : in std_logic;
        CLK_EN : out std_logic
    );
end CLK_ENABLE;

architecture Behavior of CLK_ENABLE is
    signal quanta : Integer := 0;

begin
    CLK_TICK : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if (quanta < QUANTA_MAX - 1) then
                quanta <= quanta + 1;
            else
                quanta <= 0;
            end if;
        end if;
    end process CLK_TICK;

    CLK_EN <= '1' when quanta = QUANTA_ENABLE - 1 else '0';
end Behavior;

------------------------------------------------------------------------------------------------------------------
-- Timed Pulse Generator
-- Generates a pulse of specified width in clock ticks
-- pulse starts immediately and ends after the specified number of clock ticks
-- If RESET_LOW is true, If START_PULSE is low before pulse is finished, the pulse is deactivated and the counter resets
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PULSE_GEN is
    generic (
        PULSE_WIDTH : Integer := 10; -- Pulse width in clock ticks
        RESET_LOW   : Boolean := true   -- If true, pulse can be reset by bringing START_PULSE low before pulse is finished
    );

    port (
        START_PULSE : in std_logic; -- Signal to start the pulse
        CLK_IN      : in std_logic;
        PULSE_OUT   : out std_logic
    );
end PULSE_GEN;

architecture Behavior of PULSE_GEN is
    signal counter      : Integer := 0;
    signal pulse_active : std_logic := '0';
    signal prev_start : std_logic := '0';

begin
    PULSE_GEN_PROCESS : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            if prev_start = '0' and START_PULSE = '1' then
                pulse_active <= '1';    -- start pulse on rising edge of START_PULSE
            end if;

            if prev_start = '1' and START_PULSE = '0' and RESET_LOW = true then
                pulse_active <= '0';    -- reset pulse if RESET_LOW is true and START_PULSE goes low
            end if;

            if pulse_active = '1' then
                if counter < PULSE_WIDTH then
                    counter <= counter + 1;     -- increment the counter if pulse active and counter not done
                else 
                    pulse_active <= '0';        -- end the pulse when counter reaches pulse width
                    counter <= 0;               -- reset counter
                end if;
            else
                if pulse_active = '0' then
                    counter <= 0;               -- Reset counter when pulse_active goes low
                end if;
            end if;

            prev_start <= START_PULSE;      -- store previous state of START_PULSE for edge detection
        end if;
    end process PULSE_GEN_PROCESS;

    -- PULSE_OUT is 1 when the counter is less than the pulse width and START_PULSE is high
    PULSE_OUT <= '1' when (counter < PULSE_WIDTH AND pulse_active = '1') else '0';

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
        AUTO_FREQ : Integer := 1;           -- Frequency in Hz for automatic clock mode
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
    constant MAX_COUNT   : integer := SYS_FREQ/AUTO_FREQ;

    signal previous_man  : std_logic := '1';
    signal clock_counter : integer := 0;

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

------------------------------------------------------------------------------------------------------------------
-- This is an external signal synchronizer
-- It synchronizes an external asynchronous signal of arbitrary bit depth to the system clock domain
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SYNC_REG is
    generic (
        WIDTH : Integer := 1                                    -- Width of the signal to be synchronized
    );

    port (
        CLK_IN   : in std_logic;                                 -- System clock input
        ASYNC_IN : in std_logic_vector(WIDTH-1 downto 0);        -- Asynchronous input signal
        SYNC_OUT : out std_logic_vector(WIDTH-1 downto 0)        -- Synchronized output signal
    );
end SYNC_REG;

architecture RTL of SYNC_REG is
    signal reg_meta : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal reg_sync : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

     -- Quartus Prime specific synchronizer attributes to identify synchronized signals for analysis
    attribute altera_attribute : string;
    attribute altera_attribute of reg_meta, reg_sync : signal is "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";

begin
    SYNC_PROCESS : process(CLK_IN)
    begin
        if rising_edge(CLK_IN) then
            reg_meta <= ASYNC_IN;        -- First stage of synchronization
            reg_sync <= reg_meta;        -- Second stage of synchronization
        end if;
    end process SYNC_PROCESS;
    SYNC_OUT <= reg_sync;                -- Output the synchronized signal
end RTL;

------------------------------------------------------------------------------------------------------------------
-- This is a simple module to convert a one hot signal into a 32 bit number used as a delay for clock management

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CLK_SEL is
    port (
        SW_INPUTS : in std_logic_vector(2 downto 0);    -- one-hot speed setting (slow, med, fast for now)
        SPEED_OUT : out std_logic_vector(31 downto 0)   -- 32 bit number to delay the clock
    );
end CLK_SEL;

architecture Behavior of CLK_SEL is
begin

    WITH (SW_INPUTS) SELECT   -- select CPU speed via switches 6 through 4
        SPEED_OUT <=                                                        -- clock values assuming a 50MHz system clock
            std_logic_vector(to_unsigned(10_000_000, 32)) when "001",       -- 5 Hz
            std_logic_vector(to_unsigned(50_000, 32)) when "010",           -- 1 KHz
            std_logic_vector(to_unsigned(1, 32)) when "100",                -- 50 MHz
            std_logic_vector(to_unsigned(100_000_000, 32)) when others;     -- 0.5 Hz

end Behavior;
