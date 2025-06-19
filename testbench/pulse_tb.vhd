library ieee;
use ieee.std_logic_1164.all;

entity pulse_tb is
end entity;

architecture tb of pulse_tb is

    -- Component declaration
    component PULSE_GEN
        generic (
            PULSE_WIDTH : Integer := 10
        );
        port (
            START_PULSE : in std_logic;
            CLK_IN      : in std_logic;
            PULSE_OUT   : out std_logic
        );
    end component;

    -- Signals for DUT
    signal clk         : std_logic := '0';
    signal start_pulse : std_logic := '0';
    signal pulse_out   : std_logic;

    constant clk_period : time := 20 ns;

begin

    -- Instantiate DUT
    DUT: PULSE_GEN
        generic map (
            PULSE_WIDTH => 5  -- Set pulse width for test = 5 ticks (100 ns at 20 ns clock period)
        )
        port map (
            START_PULSE => start_pulse,
            CLK_IN      => clk,
            PULSE_OUT   => pulse_out
        );

    -- Clock generation
    clk_process : process
    begin
        while now < 500 ns loop
            clk <= '0';
            wait for clk_period/2;
            clk <= '1';
            wait for clk_period/2;
        end loop;
        wait;
    end process;

    -- Stimulus process
    stim_proc: process
    begin
        -- Initial state
        start_pulse <= '0';
        wait for 45 ns;

        -- Start a pulse
        start_pulse <= '1';
        wait for 200 ns;

        -- End the pulse
        start_pulse <= '0';
        wait for 40 ns;

        -- Start another pulse
        start_pulse <= '1';
        wait for 40 ns;

        -- End prematurely
        start_pulse <= '0';
        wait for 100 ns;

        -- End simulation
        wait;
    end process;

end architecture;