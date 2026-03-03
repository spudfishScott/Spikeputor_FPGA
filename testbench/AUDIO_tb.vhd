-- Testbench for AUDIO.vhdl
-- Exercises single-voice operation (all waveforms and channel selections)
-- and a few multi-voice configurations using sine waves.
-- The output values are simply observed in waveform or reported.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AUDIO_tb is
end AUDIO_tb;

architecture Behavioral of AUDIO_tb is
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz clock

    signal clk    : std_logic := '0';
    signal reset  : std_logic := '0';

    signal VOICE0 : std_logic_vector(15 downto 0) := (others => '0');
    signal VOICE1 : std_logic_vector(15 downto 0) := (others => '0');
    signal VOICE2 : std_logic_vector(15 downto 0) := (others => '0');
    signal VOICE3 : std_logic_vector(15 downto 0) := (others => '0');

    signal SET0   : std_logic := '0';
    signal SET1   : std_logic := '0';
    signal SET2   : std_logic := '0';
    signal SET3   : std_logic := '0';

    signal AUDIO_H : std_logic_vector(3 downto 0);
    signal AUDIO_M : std_logic_vector(3 downto 0);
    signal AUDIO_L : std_logic_vector(3 downto 0);

    -- signal AUDIO_R : std_logic_vector(3 downto 0);
    -- signal AUDIO_L : std_logic_vector(3 downto 0);

begin
    -- instantiate the unit under test
    uut: entity work.AUDIO
        port map (
            CLK     => clk,
            RESET   => reset,
            VOICE0  => VOICE0,
            VOICE1  => VOICE1,
            VOICE2  => VOICE2,
            VOICE3  => VOICE3,
            SET0    => SET0,
            SET1    => SET1,
            SET2    => SET2,
            SET3    => SET3,
            AUDIO_H => AUDIO_H,
            AUDIO_M => AUDIO_M,
            AUDIO_L => AUDIO_L
            -- AUDIO_R => AUDIO_R,
            -- AUDIO_L => AUDIO_L
        );

    -- clock generator
    clk_proc: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process clk_proc;

    -- main stimulus process
    stimulus: process
    -- helper procedure to program a voice and strobe its SET line
        procedure program_voice(
            constant voice_num : integer;
            constant note      : std_logic_vector(3 downto 0);
            constant oct       : std_logic_vector(3 downto 0);
            constant wf        : std_logic_vector(1 downto 0);
            constant ch        : std_logic_vector(1 downto 0)
        ) is
        begin
            case voice_num is
                when 0 =>
                    VOICE0(3 downto 0)   <= note;
                    VOICE0(7 downto 4)   <= oct;
                    VOICE0(9 downto 8)   <= wf;
                    VOICE0(11 downto 10) <= ch;
                    SET0 <= '1';
                when 1 =>
                    VOICE1(3 downto 0)   <= note;
                    VOICE1(7 downto 4)   <= oct;
                    VOICE1(9 downto 8)   <= wf;
                    VOICE1(11 downto 10) <= ch;
                    SET1 <= '1';
                when 2 =>
                    VOICE2(3 downto 0)   <= note;
                    VOICE2(7 downto 4)   <= oct;
                    VOICE2(9 downto 8)   <= wf;
                    VOICE2(11 downto 10) <= ch;
                    SET2 <= '1';
                when 3 =>
                    VOICE3(3 downto 0)   <= note;
                    VOICE3(7 downto 4)   <= oct;
                    VOICE3(9 downto 8)   <= wf;
                    VOICE3(11 downto 10) <= ch;
                    SET3 <= '1';
                when others => null;
            end case;
            wait for CLK_PERIOD;
            -- de‑assert all SET lines to avoid latching multiple times
            SET0 <= '0'; SET1 <= '0'; SET2 <= '0'; SET3 <= '0';
        end procedure;

    begin
        -- reset the device
        reset <= '1';
        wait for 5 * CLK_PERIOD;
        reset <= '0';
        wait for 10 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- single-voice tests
        ------------------------------------------------------------------

        -- program_voice(0, "1100", "0011", "01", "01");
        -- -- program_voice(3, "1100", "0100", "01", "10"); 
        -- wait for 100000 * CLK_PERIOD;

        -- program_voice(0, "1100", "0101", "00", "01");
        -- -- program_voice(3, "1100", "0110", "00", "10");
        -- wait for 100000 * CLK_PERIOD;

        -- program_voice(0, "1100", "0111", "10", "01");
        -- -- program_voice(3, "1100", "1000", "10", "10");
        -- wait for 100000 * CLK_PERIOD;

        -- program_voice(0, "1100", "1000", "11", "01");
        -- -- program_voice(3, "0101", "1000", "11", "10");
        -- wait for 100000 * CLK_PERIOD;

        --         -- -- turn off all voices by sending note index 0
        -- report "Clearing all voices" severity note;
        -- program_voice(0, "0000", "0000", "00", "00");
        -- program_voice(1, "0000", "0000", "00", "00");
        -- program_voice(2, "0000", "0000", "00", "00");
        -- program_voice(3, "0000", "0000", "00", "00");
        -- wait for 200 * CLK_PERIOD;


        -- -- ------------------------------------------------------------------
        -- -- -- multi-voice tests (sine waves)
        -- -- ------------------------------------------------------------------
        report "Multi-voice test: two voices, sine, both channels" severity note;

        program_voice(0, "0001", "0110", "11", "10");
        program_voice(1, "0101", "0110", "11", "01");
        wait for 100000 * CLK_PERIOD;

        program_voice(0, "0001", "0110", "11", "10");
        program_voice(1, "0101", "0110", "11", "10");
        wait for 400000 * CLK_PERIOD;

        program_voice(2, "0111", "0111", "11", "11");
        wait for 600000 * CLK_PERIOD;

        program_voice(3, "0111", "1000", "11", "11");
        wait for 400000 * CLK_PERIOD;

        -- -- turn off all voices by sending note index 0
        report "Clearing all voices" severity note;
        program_voice(0, "0000", "0000", "00", "00");
        program_voice(1, "0000", "0000", "00", "00");
        program_voice(2, "0000", "0000", "00", "00");
        program_voice(3, "0000", "0000", "00", "00");
        wait for 200 * CLK_PERIOD;

        report "End of simulation" severity note;
        wait;
    end process stimulus;

end Behavioral;
