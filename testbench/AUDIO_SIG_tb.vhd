-- Testbench for AUDIO_SIG.vhd
-- Exercises the note frequency generation and waveform outputs
-- Sine waveform is not verified (left as future work)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AUDIO_SIG_tb is
end AUDIO_SIG_tb;

architecture Behavioral of AUDIO_SIG_tb is
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz clock

    signal clk       : std_logic := '0';
    signal reset     : std_logic := '0';
    signal note_idx  : std_logic_vector(3 downto 0) := (others => '0');
    signal octave    : std_logic_vector(3 downto 0) := (others => '0');
    signal waveform  : std_logic_vector(1 downto 0) := (others => '0');
    signal set_sig   : std_logic := '0';
    signal sig_out   : std_logic_vector(13 downto 0);

begin
    -- instantiate unit under test (make sure we drive the clock port)
    uut: entity work.AUDIO_SIG
        generic map(
            CLK_FREQ => 50_000_000
        )
        port map(
            CLK      => clk,            -- clock must be connected or nothing will toggle
            RESET    => reset,
            NOTE_IDX => note_idx,
            OCTAVE   => octave,
            WAVEFORM => waveform,
            SET      => set_sig,
            SIG_OUT  => sig_out
        );

    -- clock generation (continually toggles 'clk')
    clk_proc: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process clk_proc;

    -- (the empty process below was unnecessary and has been removed)

    -- stimulus process
    stimulus: process
        procedure apply_note(
            constant idx : std_logic_vector(3 downto 0);
            constant oct : std_logic_vector(3 downto 0);
            constant wf  : std_logic_vector(1 downto 0)
        ) is
        begin
            note_idx <= idx;
            octave   <= oct;
            waveform <= wf;
            wait for CLK_PERIOD;
            set_sig <= '1';
            wait for CLK_PERIOD;
            set_sig <= '0';
            -- let output run for some cycles
            wait for 150000 * CLK_PERIOD;
        end procedure;
    begin
        -- reset the device
        reset <= '1';
        wait for 5 * CLK_PERIOD;
        reset <= '0';

        -- test square wave on middle C octave 4
        apply_note("0001", "0101", "00");

        -- test sawtooth on A4
        apply_note("1010", "0101", "01");

        -- test triangle on B5
        apply_note("1100", "0101", "10");

        -- test silence (note index 0)
        apply_note("0000", "0000", "00");

        -- end simulation
        wait for 50 * CLK_PERIOD;
        assert false report "End of simulation" severity note;
    end process stimulus;

end Behavioral;
