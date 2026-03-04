-- Signal generator for Spikeputor AUDIO module. Generates a digital waveform given a note index, octave, and waveform
-- To enable fast efficient pipelined division, will be called once every LATENCY cycles. This will enable polyphony.
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

entity AUDIO_SIG is
    generic ( 
        CLK_FREQ        : integer := 50_000_000;                                -- clock speed in Hertz
        LATENCY         : integer := 4;                                         -- latency of integer division module in cycles
        LATENCY_OFFSET  : integer := 0                                          -- index of quotient output in latency pipeline (0 to LATENCY-1)
    );
    port (
        CLK             : in std_logic;                                         -- clock input
        RESET           : in std_logic;                                         -- active high reset

        NUMERATOR       : out std_logic_vector(31 downto 0);                    -- numerator for integer division
        DENOMINATOR     : out std_logic_vector(31 downto 0);                    -- denominator for integer division
        QUOTIENT        : in std_logic_vector(31 downto 0);                     -- quotient output from integer division

        NOTE_IDX        : in std_logic_vector(3 downto 0);                      -- note number (1-12, others = off)
        OCTAVE          : in std_logic_vector(3 downto 0);                      -- octave number (0 to 8)
        WAVEFORM        : in std_logic_vector(1 downto 0);                      -- square/sawtooth/triangle/sine
        SET             : in std_logic;

        SIG_OUT         : out std_logic_vector(13 downto 0)                     -- signal out (14 bits)
    );
end AUDIO_SIG;

architecture Behavioral of AUDIO_SIG is

    -- signals for audio signal generation
    signal oct_shift    : integer range 0 to 8 := 0;                            -- octave value clamped to 8
    signal note_base    : std_logic_vector(28 downto 0) := (others => '0');     -- base frequency of the note in octave 8 * 10
    signal note_cycle   : integer range 0 to 2097151 := 0;                      -- number of cycles in one full waveform

    signal cycle_cnt    : integer range 0 to 2097151 := 0;                      -- cycle counter - (0 to 2^21 - 1)
    signal sin2_cnt     : integer range 0 to 3 := 0;                            -- subcycle counter for sine function (half cycle)
    signal sin_index    : integer range 0 to 32 := 0;                           -- index into sine lookup table
    signal sin_result   : std_logic_vector(14 downto 0) := (others => '0');     -- result from sine lookup table

    signal set_latch    : std_logic := '0';                                     -- latched version of set signal to synchronize with cal_timer
    signal new_note     : integer range 0 to 3 := 0;                            -- counter for new note latching
    signal latency_cnt  : integer range 0 to LATENCY := 0;                      -- counter to track latency of division
    signal delay_start  : std_logic;

    signal num_out      : std_logic_vector(31 downto 0) := (others => '0');     -- internal signal for numerator output to integer division
    signal den_out      : std_logic_vector(31 downto 0) := (others => '0');     -- internal signal for denominator output to integer division

    signal waveform_sel : std_logic_vector(1 downto 0) := "00";                 -- latched in waveform selection
    signal signal_int   : std_logic_vector(14 downto 0) := (others => '0');     -- internal output signal (with extra bit for overflow to make multiplication simple bit-shifting)

begin

    SIG_OUT     <= signal_int(13 downto 0) when signal_int(14) = '0' else "11" & x"FFF";    -- if signal is 16384, make it 16383

    NUMERATOR   <= num_out;
    DENOMINATOR <= den_out;

    -- calcaulate base note frequency and amount to shift down by based on OCTAVE and NOTE_IDX
    oct_shift <= 8 - to_integer(unsigned(OCTAVE)) when to_integer(unsigned(OCTAVE)) <= 8 else 0;   -- number of right bits to shift from octave 8, clamp octave to 8
    with (NOTE_IDX) select  -- note base frequency is real frquency * 10 to avoid using real numbers - TODO: see if 100 works again
        note_base <=
            (others => '0') when "0000",        -- rest
            std_logic_vector(to_unsigned(41860, 29)) when "0001",     -- C8
            std_logic_vector(to_unsigned(44349, 29)) when "0010",     -- C#8/Db8
            std_logic_vector(to_unsigned(46986, 29)) when "0011",     -- D8
            std_logic_vector(to_unsigned(49780, 29)) when "0100",     -- D#8/Eb8
            std_logic_vector(to_unsigned(52470, 29)) when "0101",     -- E8
            std_logic_vector(to_unsigned(55877, 29)) when "0110",     -- F8
            std_logic_vector(to_unsigned(59199, 29)) when "0111",     -- F#8/Gb8
            std_logic_vector(to_unsigned(62719, 29)) when "1000",     -- G8
            std_logic_vector(to_unsigned(66449, 29)) when "1001",     -- G#8/Ab8
            std_logic_vector(to_unsigned(70400, 29)) when "1010",     -- A8
            std_logic_vector(to_unsigned(74586, 29)) when "1011",     -- A#8/Bb8
            std_logic_vector(to_unsigned(79021, 29)) when "1100",     -- B8
            (others => '0') when others;

    with (sin_index) select -- sin lookup scaled to max 8192
        sin_result <=
            std_logic_vector(to_unsigned(0, 15)) when 0,
            std_logic_vector(to_unsigned(803, 15)) when 1,
            std_logic_vector(to_unsigned(1598, 15)) when 2,
            std_logic_vector(to_unsigned(2378, 15)) when 3,
            std_logic_vector(to_unsigned(3135, 15)) when 4,
            std_logic_vector(to_unsigned(3861, 15)) when 5,
            std_logic_vector(to_unsigned(4551, 15)) when 6,
            std_logic_vector(to_unsigned(5197, 15)) when 7,
            std_logic_vector(to_unsigned(5793, 15)) when 8,
            std_logic_vector(to_unsigned(6333, 15)) when 9,
            std_logic_vector(to_unsigned(6811, 15)) when 10,
            std_logic_vector(to_unsigned(7225, 15)) when 11,
            std_logic_vector(to_unsigned(7568, 15)) when 12,
            std_logic_vector(to_unsigned(7839, 15)) when 13,
            std_logic_vector(to_unsigned(8035, 15)) when 14,
            std_logic_vector(to_unsigned(8153, 15)) when 15,
            std_logic_vector(to_unsigned(8192, 15)) when 16,
            std_logic_vector(to_unsigned(8153, 15)) when 17,
            std_logic_vector(to_unsigned(8035, 15)) when 18,
            std_logic_vector(to_unsigned(7839, 15)) when 19,
            std_logic_vector(to_unsigned(7568, 15)) when 20,
            std_logic_vector(to_unsigned(7225, 15)) when 21,
            std_logic_vector(to_unsigned(6811, 15)) when 22,
            std_logic_vector(to_unsigned(6333, 15)) when 23,
            std_logic_vector(to_unsigned(5793, 15)) when 24,
            std_logic_vector(to_unsigned(5197, 15)) when 25,
            std_logic_vector(to_unsigned(4551, 15)) when 26,
            std_logic_vector(to_unsigned(3861, 15)) when 27,
            std_logic_vector(to_unsigned(3135, 15)) when 28,
            std_logic_vector(to_unsigned(2378, 15)) when 29,
            std_logic_vector(to_unsigned(1598, 15)) when 30,
            std_logic_vector(to_unsigned(803, 15)) when 31,
            (others => '0') when others;

    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RESET = '1' then         -- reset all values to 0
                latency_cnt  <= 0;
                note_cycle   <= 0;
                waveform_sel <= "00";
                cycle_cnt    <= 0;
                sin_index    <= 0;
                sin2_cnt     <= 0;
                set_latch    <= '0';
                new_note     <= 0;
                delay_start  <= '0';
                num_out      <= (others => '0');
                den_out      <= (others => '0');
                signal_int   <= (others => '0');

            else
                if latency_cnt = LATENCY - 1 then       -- increment latency counter until it reaches LATENCY-1, then start over
                    latency_cnt <= 0;
                else
                    latency_cnt <= latency_cnt + 1;
                end if;

                if SET = '1' then       -- latch in signals on SET strobe, reset cycle count, and start calculation of note cycle based on note frequency
                    set_latch <= '1';
                    waveform_sel <= WAVEFORM;                                                   -- calculate note cycle:
                    num_out  <= std_logic_vector(to_unsigned(CLK_FREQ * 10 / LATENCY, 32));     -- set numerator for integer division to clock frequency * 10 / LATENCY
                    den_out  <= "00000000000" & note_base(20+oct_shift downto oct_shift);       -- set denominator to note frequency
                    signal_int <= (others => '0');
                    if latency_cnt = LATENCY_OFFSET then        -- if the SET comes in at this stage of the cycle, the latching of note_cycle needs to be delayed one more cycle
                        delay_start <= '1';
                    end if;
                end if;

                if latency_cnt = (LATENCY_OFFSET) MOD LATENCY then    -- when latency counter matches offset + 1, division is valid so we can start a new division and continue signal calculation
                    if (set_latch = '1' AND new_note /= 2) then          -- if we just latched in a new note, calculate the note cycle based on the note frequency
                        if delay_start = '1' then
                            delay_start <= '0';                           -- delay one more cycle because SET came in at the start of our pipeline and we need to wait a cycle before the calculation can start
                        else 
                            new_note <=  new_note + 1;                    -- set new note flag to wait until next cycle for division result
                            num_out  <= (others => '0');                  -- first signal is zero (except for sine - handle that later), start the division pipeline
                        end if;
                    elsif (new_note = 2) then             -- division is done now, so latch in the note_cycle number
                        set_latch <= '0';                                 -- clear set_latch to proceed to signal generation
                        new_note     <= 0;
                        note_cycle   <= to_integer(unsigned(QUOTIENT));   -- set note cycle to quotient of division - number of cycles in this note's waveform

                        cycle_cnt    <= 0;                                -- reset all counters
                        sin2_cnt     <= 0;
                        sin_index    <= 0;

                        den_out      <= QUOTIENT;                         -- denominator stays the same for all waveform calculations
                    
                    elsif note_cycle /= 0 and SET = '0' then   -- if a note is playing (and we're not setting a new note), update signal based on waveform and cycle count
                        if cycle_cnt /= note_cycle AND sin2_cnt /= 2 then -- reset cycle count at end of note cycle for all waveforms except sine, which ends after 2nd half of the sine wave

                            cycle_cnt <= cycle_cnt + 1;     -- increment the cycle counter
                            case waveform_sel is
                                when "00" =>  -- square wave - low for first half of the note cycle, high for the second half
                                    if cycle_cnt < (note_cycle / 2) then    -- confirm division is done with bit shifting and not actual division for performance
                                        signal_int <= (others => '0');
                                    else
                                        signal_int <= "011" & x"FFF";
                                    end if;

                                -- for sawtooth and triangle , start next cycle of division and use the result from last cycle
                                when "01" =>  -- sawtooth wave - 0 to 100% across the entire cycle, then immediately back to 0
                                    -- scale cycle count to range of signal using integer division
                                    signal_int <= QUOTIENT(14 downto 0);    --  previous division result
                                    num_out <= std_logic_vector(to_unsigned(cycle_cnt * 16384, 32));                            -- confirm multiplication is done with bit shifting

                                when "10" =>  -- triangle wave - 0 to 100% through half the cycle, then back down again for the second half
                                    signal_int <= QUOTIENT(14 downto 0);    -- previous division result
                                    if cycle_cnt < (note_cycle / 2) then                                                        -- confirm division is done with bit shifting
                                        -- scale to full 14-bit range (0..16383) for first half of cycle 
                                        -- we should divide by note_cycle/2, but instead just keep denominator the same and multiply numerator by 2
                                        num_out <= std_logic_vector(to_unsigned(cycle_cnt * 32768, 32));                        -- confirm multiplication is done with bit shifting
                                    else
                                        -- reverse and scale for second half of cycle
                                        num_out <= std_logic_vector(to_unsigned((note_cycle - cycle_cnt) * 32768, 32));         -- confirm multiplication is done with bit shifting
                                    end if;

                                when "11" =>  -- sine wave - starts at 5)%, goes up to 100%, then down to 0%, then back up to 50% on a curve
                                    if cycle_cnt >= (note_cycle/64) then    -- change the value every 64th of the note cycle
                                        sin_index <= sin_index + 1;         -- increment lookup table index after using the current lookup value
                                        cycle_cnt <= 0;                     -- reset cycle count to count to 1/64th of note cycle again
                                        if sin_index = 31 then              -- after first half of the sine wave, set a flag to reverse the index in the lookup table
                                            sin_index <= 0;                 -- reset the lookup table index
                                            sin2_cnt <= sin2_cnt + 1;       -- 0 and 1 to update each half of the wave, 2 to end
                                        end if;
                                    end if;
                                    if sin2_cnt = 0 then
                                        signal_int <= std_logic_vector(unsigned(sin_result) + to_unsigned(8192, 15));   -- use current sine result which is updated every note_cycle/16 cycles
                                    else
                                        signal_int <= std_logic_vector(to_unsigned(8192, 15) - unsigned(sin_result));   -- invert sine result for second half of wave
                                    end if;
                                when others =>
                                    null;
                            end case;
                        else
                            cycle_cnt    <= 0;         -- reset cycle counts at end of cycle so we can start again
                            sin2_cnt     <= 0;
                            sin_index    <= 0;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
