-- A wishbone master interface to hold the bus for a specified number of system clock ticks
-- This allows a user settable clock for the CPU, either automatic at a set frequency or manual via button press
-- Provides a CPU clock output signal for display purposes (50% duty cycle)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity CLOCK_WSH_M is
    port (
        -- Timing
        CLK        : in  std_logic;      -- System clock
        RESET      : in  std_logic;      -- System reset
        
        -- Wishbone arbiter signals
        M_CYC_O    : out std_logic;      -- wishbone cycle output - set high to request bus, low to release bus
        M_ACK_I    : in  std_logic;      -- aribiter grant signal - wait until high, then counting begins, then set CYC_O low after specified ticks, then set them high again to request bus again

        AUTO_TICKS : in std_logic_vector(31 downto 0); -- Automatic clock frequency pulse width in system clock ticks
        MAN_SEL    : in std_logic;                     -- Manual/Automatic clock select
        MAN_START  : in std_logic;                      -- Manual clock start signal

        CPU_CLOCK  : out std_logic      -- CPU Clock output for display purposes (should be 50% duty cycle)
    );
end CLOCK_WSH_M;

architecture Behavioral of CLOCK_WSH_M is
    -- Signals for clock logic
    signal counter        : Integer := 0;
    signal previous_man   : std_logic := '1';
    signal holding_bus    : std_logic := '0';
    signal bus_req        : std_logic := '0';

begin
    M_CYC_O <= bus_req;

    clock : process(CLK) is
    begin
        if RESET = '1' then
            bus_req <= '0';         -- release bus on reset and reset counter and internal flags
            holding_bus <= '0';
            CPU_CLOCK <= '0';
            counter <= 1;
        else
            if rising_edge(CLK) then
                previous_man <= MAN_START;  -- store previous state of manual start signal for edge detection

                if holding_bus = '0' then   -- not holding the bus, check for bus request/grant
                    if M_ACK_I = '0' then
                        bus_req <= '1';  -- request bus from arbiter if not granted
                    end if;

                    if bus_req = '1' and M_ACK_I = '1' then -- bus has been requested and it has been granted
                        holding_bus <= '1';  -- set holding flag, start counting
                        CPU_CLOCK <= '0';    -- CPU clock display low at start of cycle
                        counter <= 1;        -- reset counter
                    end if;

                else    -- holding bus, counting ticks or waiting for manual button press
                    if MAN_SEL = '0' then
                        if counter < to_integer(unsigned(AUTO_TICKS)) then
                            counter <= counter + 1;
                            if counter > to_integer(unsigned(AUTO_TICKS))/2 then
                                CPU_CLOCK <= '1';    -- set CPU clock display low at half of the cycle
                            end if;
                        else
                            holding_bus <= '0';     -- done holding bus
                            bus_req <= '0';         -- release bus
                        end if;
                    else
                        counter <= 1; -- reset counter in manual mode
                        if previous_man = '0' and MAN_START = '1' then -- rising edge of manual start signal
                            CPU_CLOCK <= '1';       -- set CPU clock display high, keep holding the bus until button is released
                        elsif previous_man = '1' and MAN_START = '0' then -- falling edge of manual start signal
                            holding_bus <= '0';     -- done holding bus
                            bus_req <= '0';         -- release bus
                            CPU_CLOCK <= '0';       -- set CPU clock display low
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process clock;
end Behavioral;
