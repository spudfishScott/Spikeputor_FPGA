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

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

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
    signal cal_timer    : integer range 0 to 4 := 0;                            -- timer for calculating note frequency using integer division
    signal set_latch    : std_logic := '0';                                     -- latched version of set signal to synchronize with cal_timer

    signal div_en      : std_logic := '0';                                      -- enable signal for integer division module
    signal numerator   : std_logic_vector(31 downto 0) := (others => '0');      -- numerator for integer division (clock frequency * 10)
    signal denominator : std_logic_vector(31 downto 0) := (others => '0');      -- denominator for integer division (note frequency)
    signal quotient    : std_logic_vector(31 downto 0) := (others => '0');      -- quotient output

    signal waveform_sel : std_logic_vector(1 downto 0) := "00";                 -- latched in waveform selection
    signal signal_int   : std_logic_vector(13 downto 0) := (others => '0');     -- internal signal value before output and offset adjustment

begin

    intdiv: lpm_divide
    GENERIC MAP (
        lpm_pipeline                    => 3, -- needs to be pipelined or timing failures exist
        lpm_widthn                      => 32,
        lpm_widthd                      => 32,
        lpm_nrepresentation             => "UNSIGNED",
        lpm_drepresentation             => "UNSIGNED"
    )
    PORT MAP (
        clock       => CLK,
        clken       => div_en,
        numer       => numerator,
        denom       => denominator,
        quotient    => quotient,
        remain      => open
    );

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

    -- TODO: create a pipelined integer division module to replace the division operations below. Multiplications are all simple bit shifts.
    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RESET = '1' then         -- reset values to 0
                note_cycle   <= 0;
                waveform_sel <= "00";
                cycle_cnt    <= 0;
                cyc_subcnt   <= 0;
                cal_timer    <= 0;
                div_en      <= '0';
                set_latch    <= '0';
                numerator   <= (others => '0');
                denominator <= (others => '0');
                signal_int   <= (others => '0');

            elsif SET = '1' OR set_latch = '1' then        -- latch in new note selection
                case cal_timer is
                    when 0 =>
                        set_latch <= '1';
                        waveform_sel <= WAVEFORM;
                        cycle_cnt    <= 0;
                        if note_freq /= "00000000000000000" then   -- only calculate if note frequency is not 0 (rest)
                            numerator <= std_logic_vector(to_unsigned(CLK_FREQ * 10, 32));   -- set numerator for integer division to clock frequency * 10
                            denominator <= std_logic_vector(resize(note_freq, 32));          -- set denominator to note frequency
                            div_en <= '1';      -- start division
                            cal_timer <= 1;
                        else 
                            set_latch <= '0';
                            cal_timer <= 0;
                            note_cycle <= 0;    -- set note cycle to 0 for rest
                        end if;
                    when 3 =>
                        signal_int <= (others => '0');
                        div_en <= '0';          -- stop division
                        set_latch <= '0';
                        cal_timer <= 0;
                        note_cycle <= to_integer(unsigned(quotient(16 downto 0)));          -- set note cycle to quotient of division
                    when others =>
                        cal_timer <= cal_timer + 1;    -- wait for division to end (3 cycles with pipeline of 3)
                end case;

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
