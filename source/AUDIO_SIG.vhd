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
    signal oct_shift    : integer range 0 to 8 := 0;                            -- octave value clamped to 8
    signal note_base    : std_logic_vector(24 downto 0) := (others => '0');     -- base frequency of the note in octave 8 * 10
    signal note_freq    : std_logic_vector(16 downto 0) := (others => '0');     -- note frequency in hertz * 10
    signal cycle_cnt    : integer := 0;                                         -- cycle counter
    signal cyc_subcnt   : integer := 0;                                         -- subcounter for changes within the cycle
    signal waveform_sel : std_logic_vector(1 downto 0) := "00";                 -- latched in waveform selection
    signal signal_int   : std_logic_vector(13 downto 0) := (others => '0');     -- internal signal value before output and offset adjustment

begin

    SIG_OUT <= signal_int;   -- add offset to signal and convert to std_logic_vector for output
    oct_shift <= 8 - to_integer(unsigned(OCTAVE)) when to_integer(unsigned(OCTAVE)) <= 8 else 0;   -- number of right bits to shift from octave 8, clamp octave to 8
    
    with (NOTE_IDX) select  -- note frequency is real frquency * 100 to avoid using real numbers
        note_base <=
            (others => '0') when "0000",        -- rest
            std_logic_vector(to_unsigned(41860, 25)) when "0001",     -- C8
            std_logic_vector(to_unsigned(44350, 25)) when "0010",     -- C#8/Db8
            std_logic_vector(to_unsigned(46986, 25)) when "0011",     -- D8
            std_logic_vector(to_unsigned(49960, 25)) when "0100",     -- D#8/Eb8
            std_logic_vector(to_unsigned(52470, 25)) when "0101",     -- E8
            std_logic_vector(to_unsigned(55860, 25)) when "0110",     -- F8
            std_logic_vector(to_unsigned(59200, 25)) when "0111",     -- F#8/Gb8
            std_logic_vector(to_unsigned(62720, 25)) when "1000",     -- G8
            std_logic_vector(to_unsigned(66448, 25)) when "1001",     -- G#8/Ab8
            std_logic_vector(to_unsigned(70400, 25)) when "1010",     -- A8
            std_logic_vector(to_unsigned(74586, 25)) when "1011",     -- A#8/Bb8
            std_logic_vector(to_unsigned(79022, 25)) when "1100",     -- B8
            (others => '0') when others;

    note_freq <= note_base(16+oct_shift downto oct_shift);   -- shift base frequency down by octave and convert to integer

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
                signal_int   <= (others => '0');

                if note_freq /= "00000000000000000" then
                    note_cycle <= (CLK_FREQ * 10) / to_integer(unsigned(note_freq));   -- calculate number of cycles in one waveform period
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
                            signal_int <= std_logic_vector(to_unsigned((cycle_cnt * 16384) / note_cycle, 14));   -- scale cycle count to range of signal
                        when "10" =>  -- triangle wave
                            if cycle_cnt < (note_cycle / 2) then
                                -- scale to full 14-bit range (0..16383) for first half of cycle
                                signal_int <= std_logic_vector(to_unsigned((cycle_cnt * 16384) / note_cycle * 2, 14));
                            else
                                -- reverse and scale for second half of cycle
                                signal_int <= std_logic_vector(to_unsigned(((note_cycle - cycle_cnt) * 16384) / note_cycle * 2, 14));
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
