-- Signal generator for Spikeputor AUDIO module. Generates a digital waveform given a note index, octave, and waveform
-- Inputs:
    -- RESET      -- resets signal generator to 0
    -- NOTE_IDX   - index into note frequency table starting with C, going through to B, including halftone values are 1 to 12, others mean silence
    -- OCTAVE     - Octave number from 0 to 8, others treated as 8
    -- WAVEFORM   - index for waveform: 0 = square, 1 = sawtooth, 2 = triangle, 3 = sine
    -- SET        - strobe to latch in selection
-- Output:
    -- SIG_OUT    - digital signal output - 14 bits

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity AUDIO_SIG is
    generic ( 
        CLK_FREQ : integer := 50_000_000                                       -- clock speed in Hertz
    );
    port (
        CLK      : in std_logic;                                                -- clock input
        RESET    : in std_logic;                                                -- active high reset

        NOTE_IDX : in std_logic_vector(3 downto 0);                             -- note number (1-12, others = off)
        OCTAVE   : in std_logic_vector(3 downto 0);                             -- octave number (0 to 8)
        WAVEFORM : in std_logic_vector(1 downto 0);                             -- square/sawtooth/triangle/sine
        SET      : in std_logic;

        SIG_OUT  : out std_logic_vector(13 downto 0)                           -- signal out (14 bits)
    );
end AUDIO_SIG;

architecture Behavioral of AUDIO_SIG is
    constant CYCLE_MIN    : integer := (CLK_FREQ / (3087 * 256)) * 100 + 1;     -- number of cycles for highest note (B8 - 6327 for 50 MHz)
    constant SIG_OFFSET   : integer := 16384 - CYCLE_MIN;                       -- offset so all signals peak at 0x3fff

    -- signals for audio signal generation
    signal note_cycle   : integer := 0;                                         -- number of cycles in one full waveform
    signal clamped_oct  : integer := 0;                                         -- octave value clamped to 8
    signal note_freq    : integer := 0;                                         -- note frequency in hertz * 100 (to avoid using real numbers)
    signal cycle_cnt    : integer := 0;                                         -- cycle counter
    signal cyc_subcnt   : integer := 0;                                         -- subcounter for changes within the cycle
    signal waveform_sel : std_logic_vector(1 downto 0) := "00";                 -- latched in waveform selection
    signal signal_int   : std_logic_vector(13 downto 0) := (others => '0');     -- internal signal value before output and offset adjustment

begin

    SIG_OUT <= signal_int;   -- add offset to signal and convert to std_logic_vector for output
    clamped_oct <= to_integer(unsigned(OCTAVE)) when to_integer(unsigned(OCTAVE)) <= 8 else 8;   -- clamp octave to 8
    
    with (NOTE_IDX) select  -- note frequency is real frquency * 100 to avoid using real numbers
        note_freq <=
            0 when "0000",        -- rest
            1635 * (2 ** clamped_oct) when "0001",     -- C0 * octave multiplier
            1732 * (2 ** clamped_oct) when "0010",     -- C#0 * octave multiplier
            1835 * (2 ** clamped_oct) when "0011",     -- D0 * octave multiplier
            1945 * (2 ** clamped_oct) when "0100",     -- D#0 * octave multiplier
            2062 * (2 ** clamped_oct) when "0101",     -- E0 * octave multiplier
            2183 * (2 ** clamped_oct) when "0110",     -- F0 * octave multiplier
            2312 * (2 ** clamped_oct) when "0111",     -- F#0 * octave multiplier
            2450 * (2 ** clamped_oct) when "1000",     -- G0 * octave multiplier
            2596 * (2 ** clamped_oct) when "1001",     -- G#0 * octave multiplier
            2750 * (2 ** clamped_oct) when "1010",     -- A0 * octave multiplier
            2914 * (2 ** clamped_oct) when "1011",     -- A#0 * octave multiplier
            3087 * (2 ** clamped_oct) when "1100",     -- B0 * octave multiplier
            0 when others;

    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RESET = '1' then         -- reset values to 0
                note_cycle   <= 0;
                waveform_sel <= "00";
                cycle_cnt    <= 0;
                cyc_subcnt   <= 0;
                signal_int   <= (others => '0');

            elsif SET = '1' then        -- latch in new note selection
                waveform_sel <= WAVEFORM;
                cycle_cnt    <= 0;
                cyc_subcnt   <= 0;
                signal_int   <= (others => '0');

                if note_freq /= 0 then
                    note_cycle <= (CLK_FREQ * 100) / note_freq;   -- calculate number of cycles in one waveform period
                else
                    note_cycle <= 0;
                end if;

            elsif note_cycle /= 0 then   -- if a note is playing, update signal based on waveform and cycle count
                if cycle_cnt < note_cycle then
                    cycle_cnt <= cycle_cnt + 1;
                    case waveform_sel is
                        when "00" =>  -- square wave
                            if cycle_cnt < (note_cycle / 2) then
                                signal_int <= (others => '1');
                            else
                                signal_int <= (others => '0');
                            end if;
                        when "01" =>  -- sawtooth wave
                            signal_int <= std_logic_vector(to_unsigned((cycle_cnt * 16383) / note_cycle, 14));   -- scale cycle count to range of signal
                        when "10" =>  -- triangle wave
                            if cycle_cnt < (note_cycle / 2) then
                                -- scale to full 14-bit range (0..16383) for first half of cycle
                                signal_int <= std_logic_vector(to_unsigned((cycle_cnt * 16382) / note_cycle * 2, 14));
                            else
                                -- reverse and scale for second half of cycle
                                signal_int <= std_logic_vector(to_unsigned(((note_cycle - cycle_cnt) * 16382) / note_cycle * 2, 14));
                            end if;
                        when "11" =>  -- sine wave
                            -- todo: implement sine wave using a lookup table or approximation method
                            signal_int <= (others => '0');  -- placeholder for now
                        when others =>
                            null;
                    end case;
                else
                    cycle_cnt <= 0;   -- reset cycle count at end of cycle
                end if;
            end if;
        end if;
    end process;

end Behavioral;
