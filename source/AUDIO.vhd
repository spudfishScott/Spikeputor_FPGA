-- Integer Divide function - SIMULATION ONLY (for testing divider latency and pipelining in AUDIO_SIG)

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY INTDIV_SIM is
    GENERIC (
        LATENCY : integer := 8
    );
    PORT (
        CLOCK   : IN std_logic;
        RESET   : In std_logic;
        
        A       : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        B       : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        QUOT    : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END INTDIV_SIM;

ARCHITECTURE SIM of INTDIV_SIM is
    signal result_pipe11 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe10 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe9 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe8 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe7 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe6 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe5 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe4 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe3 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe2 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe1 : unsigned(31 downto 0) := (others => '0');
    signal result_pipe0 : unsigned(31 downto 0) := (others => '0');

begin

    -- output the result from the last pipeline stage
    QUOT <= std_logic_vector(result_pipe0) when LATENCY = 1 else
            std_logic_vector(result_pipe1) when LATENCY = 2 else
            std_logic_vector(result_pipe2) when LATENCY = 3 else
            std_logic_vector(result_pipe3) when LATENCY = 4 else
            std_logic_vector(result_pipe4) when LATENCY = 5 else
            std_logic_vector(result_pipe5) when LATENCY = 6 else
            std_logic_vector(result_pipe6) when LATENCY = 7 else
            std_logic_vector(result_pipe7) when LATENCY = 8 else
            std_logic_vector(result_pipe8) when LATENCY = 9 else
            std_logic_vector(result_pipe9) when LATENCY = 10 else
            std_logic_vector(result_pipe10) when LATENCY = 11 else
            std_logic_vector(result_pipe11) when LATENCY = 12 else
            (others => '0');  -- default to zero if LATENCY is out of range

    process(CLOCK)
    begin
        if rising_edge(CLOCK) then
            if RESET = '1' then
                result_pipe11  <= (others => '0');
                result_pipe10  <= (others => '0');
                result_pipe9   <= (others => '0');
                result_pipe8   <= (others => '0');
                result_pipe7   <= (others => '0');
                result_pipe6   <= (others => '0');
                result_pipe5   <= (others => '0');
                result_pipe4   <= (others => '0');
                result_pipe3  <= (others => '0');
                result_pipe2  <= (others => '0');
                result_pipe1  <= (others => '0');
                result_pipe0  <= (others => '0');
            else
                -- shift pipeline stages
                result_pipe11 <= result_pipe10;
                result_pipe10 <= result_pipe9;
                result_pipe9  <= result_pipe8;
                result_pipe8  <= result_pipe7;
                result_pipe7  <= result_pipe6;
                result_pipe6  <= result_pipe5;
                result_pipe5  <= result_pipe4;
                result_pipe4  <= result_pipe3;
                result_pipe3 <= result_pipe2;
                result_pipe2 <= result_pipe1;
                result_pipe1 <= result_pipe0;
                
                -- compute division at stage 0 (will appear at output after LATENCY cycles)
                if unsigned(B) /= 0 then
                    result_pipe0 <= unsigned(A) / unsigned(B);
                else
                    result_pipe0 <= (others => '0');
                end if;
            end if;
        end if;
    end process;
end SIM;

-------------------------------------------------------------------------------------------------------------------

-- An AUDIO module to implement polyphony with AUDIO_SIG signal generators. Uses division latency to pipeline the signals, 
-- then recombine them as a weighted average of active signals and channel selections before sending the final signal out to the two channel, 4-bit audio DAC.
-- Inputs for each voice (16 bits total):
    -- NOTE INDEX - 4 bits from 1-12 for each note of the scale starting with C and rising to B. 0 = no sound, anything above 12 is no sound.
    -- OCTAVE     - 4 bits from 0-8, anyting higher than 8 is clamped to 8. Octave 0 doesn't work well below Note Index 8 for triangle or sawtooth waveforms.
    -- WAVEFORM   - 2 bits: 0b00 - square, 0b01 - sawtooth, 0b10 - triangle, 0b11 - sine
    -- [REMOVED] CHANNEL    - 2 bits: 0b00 - neither, 0b01 - right only, 0b10 - left only, 0b11 - right and left

    -- SET        - signal to strobe to set the current values into the audio generator

-- Outputs:
    -- 4 bits each (to match the 4 bit DAC on the DE0 board)
        -- AUDIO Right
        -- AUDIO Left

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity AUDIO is
    generic ( CLK_FREQ : Integer :=  50_000_000 );   -- default to 50 MHz clock
    port (
        CLK         : in std_logic;
        RESET       : in std_logic;

        VOICE0      : in std_logic_vector(15 downto 0);
        VOICE1      : in std_logic_vector(15 downto 0);
        VOICE2      : in std_logic_vector(15 downto 0);
        VOICE3      : in std_logic_vector(15 downto 0);

        SET0        : in std_logic;
        SET1        : in std_logic;
        SET2        : in std_logic;
        SET3        : in std_logic;

        -- audio signals out
        AUDIO_H     : out std_logic_vector(3 downto 0);
        AUDIO_M     : out std_logic_vector(3 downto 0);
        AUDIO_L     : out std_logic_vector(3 downto 0)
        -- AUDIO_R     : out std_logic_vector(3 downto 0);
        -- AUDIO_L     : out std_logic_vector(3 downto 0)
);
end AUDIO;

architecture Structural of AUDIO is

    -- final output signals
    signal sig_12bit : std_logic_vector(11 downto 0) := (others => '0');    -- combined 12 bit output signal
    -- signal out_r     : std_logic_vector(3 downto 0) := (others => '0');
    -- signal out_l     : std_logic_vector(3 downto 0) := (others => '0');

    -- signal accumulators
    signal out_acc   : std_logic_vector(16 downto 0);
    -- signal out_r_acc : std_logic_vector(16 downto 0) := (others => '0');    -- signals are added and normalized here
    -- signal out_l_acc : std_logic_vector(16 downto 0) := (others => '0');    -- signals are added and normalized here

    -- each voice has a numerator, denominator, and quotient used with the shared division module, a signal output, an active flag, and a set strobe
    type div_t is array(0 to 3) of std_logic_vector(31 downto 0);
    signal num       : div_t := (others => (others => '0'));
    signal den       : div_t := (others => (others => '0'));
    signal quot      : div_t := (others => (others => '0'));

    -- current signal for mixing into accumulators
    type sig_t is array(0 to 3) of std_logic_vector(13 downto 0);
    signal sig_out   : sig_t := (others => (others => '0'));
    signal cur_sig   : std_logic_vector(13 downto 0) := (others => '0');
    -- signal cur_sig_l : std_logic_vector(13 downto 0) := (others => '0');
    -- signal cur_sig_r : std_logic_vector(13 downto 0) := (others => '0');

    -- active voices and number of voices per channel for mixing and normalization calculation
    signal active   : std_logic_vector(0 to 3) := (others => '0');
    -- signal active_l  : std_logic_vector(0 to 3) := (others => '0');
    -- signal active_r  : std_logic_vector(0 to 3) := (others => '0');

    -- signal num_voices_l : integer range 0 to 4 := 0;
    -- signal num_voices_r : integer range 0 to 4 := 0;
    signal num_voices : integer range 0 to 4 := 0;

-- the inputs and output of the divider
    signal arb_num   : std_logic_vector(31 downto 0) := (others => '0');
    signal arb_den   : std_logic_vector(31 downto 0) := (others => '0');
    signal arb_quot  : std_logic_vector(31 downto 0) := (others => '0');
    signal arb_rem   : std_logic_vector(31 downto 0) := (others => '0');

    constant DIV_LATENCY : integer := 8;    -- should be a multiple of 4 (number of voices)
    signal voice_cnt : integer range 0 to DIV_LATENCY-1 := 0;   -- round robin counter for sharing division resource with 4 voices

begin

    -- instantiate four signal generators for each of the four voices
    AUDIO_SIG0 : entity work.AUDIO_SIG
        generic map (
            CLK_FREQ => CLK_FREQ,
            LATENCY  => DIV_LATENCY,
            LATENCY_OFFSET => 0
        )
        port map (
            CLK         => CLK,
            RESET       => RESET,

            NUMERATOR   => num(0),
            DENOMINATOR => den(0),
            QUOTIENT    => quot(0),

            NOTE_IDX    => VOICE0(3 downto 0),
            OCTAVE      => VOICE0(7 downto 4),
            WAVEFORM    => VOICE0(9 downto 8),
            SET         => SET0,

            SIG_OUT     => sig_out(0)
        );

    AUDIO_SIG1 : entity work.AUDIO_SIG
        generic map (
            CLK_FREQ => 50_000_000,
            LATENCY  => DIV_LATENCY,
            LATENCY_OFFSET => 2
        )
        port map (
            CLK         => CLK,
            RESET       => RESET,

            NUMERATOR   => num(1),
            DENOMINATOR => den(1),
            QUOTIENT    => quot(1),

            NOTE_IDX    => VOICE1(3 downto 0),
            OCTAVE      => VOICE1(7 downto 4),
            WAVEFORM    => VOICE1(9 downto 8),
            SET         => SET1,

            SIG_OUT     => sig_out(1)
        );

    AUDIO_SIG2 : entity work.AUDIO_SIG
        generic map (
            CLK_FREQ => 50_000_000,
            LATENCY  => DIV_LATENCY,
            LATENCY_OFFSET => 4
        )
        port map (
            CLK         => CLK,
            RESET       => RESET,

            NUMERATOR   => num(2),
            DENOMINATOR => den(2),
            QUOTIENT    => quot(2),

            NOTE_IDX    => VOICE2(3 downto 0),
            OCTAVE      => VOICE2(7 downto 4),
            WAVEFORM    => VOICE2(9 downto 8),
            SET         => SET2,

            SIG_OUT     => sig_out(2)
        );

    AUDIO_SIG3 : entity work.AUDIO_SIG
        generic map (
            CLK_FREQ => 50_000_000,
            LATENCY  => DIV_LATENCY,
            LATENCY_OFFSET => 6
        )
        port map (
            CLK         => CLK,
            RESET       => RESET,

            NUMERATOR   => num(3),
            DENOMINATOR => den(3),
            QUOTIENT    => quot(3),

            NOTE_IDX    => VOICE3(3 downto 0),
            OCTAVE      => VOICE3(7 downto 4),
            WAVEFORM    => VOICE3(9 downto 8),
            SET         => SET3,

            SIG_OUT     => sig_out(3)
        );

    -- Temporary simulation divide function - comment out to synthesize on DE0
    IDIV0: entity work.INTDIV_SIM
        GENERIC MAP (
            LATENCY => DIV_LATENCY
        )   
        PORT MAP (
            CLOCK   => CLK,
            RESET   => RESET,
            
            A       => arb_num,
            B       => arb_den,
            QUOT    => arb_quot
        );

    -- INTDIV: entity work.INTDIV
    -- GENERIC MAP (
    --     WIDTH => 32,
    --     LATENCY => 8
    -- )
    -- PORT MAP (
    --     CLOCK       => CLK,
    --        EN       => '1',
    --         A       => arb_num,
    --         B       => arb_den,
    --      QUOT       => arb_quot,
    --     REMND       => open
    -- );

    -- audio outputs
    AUDIO_H <= sig_12bit(11 downto 8);
    AUDIO_M <= sig_12bit(7 downto 4);
    AUDIO_L <= sig_12bit(3 downto 0);
    -- AUDIO_R <= out_r;
    -- AUDIO_L <= out_l;

    -- current signal to add to accumulators if active on a channel and even voice count
    cur_sig <= sig_out(voice_cnt/2) when (active(voice_cnt/2) = '1' AND voice_cnt MOD 2 = 0) else (others => '0');
    -- cur_sig_r <= sig_out(voice_cnt) when voice_cnt < 4 AND active_r(voice_cnt) = '1' else (others => '0');
    -- cur_sig_l <= sig_out(voice_cnt) when voice_cnt < 4 AND active_l(voice_cnt) = '1' else (others => '0');

    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                voice_cnt    <= 0;                    -- reset the counter
                -- out_r_acc    <= (others => '0');      -- clear the accumulators
                -- out_l_acc    <= (others => '0');
                out_acc      <= (others => '0');
                -- out_r        <= (others => '0');      -- clear the outputs
                -- out_l        <= (others => '0');
                sig_12bit    <= (others => '0');
                arb_num      <= (others => '0');      -- clear division inputs
                arb_den      <= (others => '0');
                -- active_l     <= (others => '0');      -- clear active flags
                -- active_r     <= (others => '0');
                active       <= (others => '0');
                -- num_voices_l <= 0;                    -- clear num voices
                -- num_voices_r <= 0;
                num_voices   <= 0;
            else
                -- increment voice counter for round robin processing
                if voice_cnt = DIV_LATENCY-1 then
                    voice_cnt <= 0;
                else
                    voice_cnt <= voice_cnt + 1;
                end if;

                -- after a full cycle of round robin, calculate outputs and reset the counter for next cycle
                if voice_cnt = 7 then
                    -- calculate left and right outputs given accumulator totals and number of active voices at the end of each cycle
                    -- now just one channel
                    case (num_voices) is
                        when 1 =>               -- simply use accumulator
                            sig_12bit <= out_acc(13 downto 2);
                        when 2 =>               -- accumulator / 2
                            sig_12bit <= out_acc(14 downto 3);
                        when 4 =>               -- accumulator / 4
                            sig_12bit <= out_acc(15 downto 4);
                        when 3 =>               -- accumulator / 3 (max value is 16383 * 3, to do: x/3 ≈ x/4+x/16+x/64+x/256
                            sig_12bit <= std_logic_vector(unsigned(out_acc(15 downto 4)) + unsigned(out_acc(15 downto 6)) + unsigned(out_acc(15 downto 8)));
                            -- sig_12bit <= out_acc(15 downto 4); -- use x/4 right now
                            -- case(out_r_acc(15 downto 11)) is
                            --     when "11000"|"10111"                    =>  out_r <= x"F";
                            --     when "10110"|"10101"                    =>  out_r <= x"E";
                            --     when "10100"                            =>  out_r <= x"D";
                            --     when "10011"|"10010"                    =>  out_r <= x"C";
                            --     when "10001"|"10000"                    =>  out_r <= x"B";
                            --     when "01111"                            =>  out_r <= x"A";
                            --     when "01110"|"01101"                    =>  out_r <= x"9";
                            --     when "01100"                            =>  out_r <= x"8";
                            --     when "01011"|"01010"                    =>  out_r <= x"7";
                            --     when "01001"|"01000"                    =>  out_r <= x"6";
                            --     when "00111"                            =>  out_r <= x"5";
                            --     when "00110"|"00101"                    =>  out_r <= x"4";
                            --     when "00100"                            =>  out_r <= x"3";
                            --     when "00011"|"00010"                    =>  out_r <= x"2";
                            --     when "00001"                            =>  out_r <= x"1";
                            --     when others                             =>  out_r <= x"0";
                            -- end case;
                        when others =>
                            sig_12bit <= (others => '0');
                    end case;

                    -- case (num_voices_l) is
                    --     when 1 =>               -- simply use accumulator
                    --         out_l <= out_l_acc(13 downto 10);
                    --     when 2 =>               -- accumulator / 2
                    --         out_l <= out_l_acc(14 downto 11);
                    --     when 4 =>               -- accumulator / 4
                    --         out_l <= out_l_acc(15 downto 12);
                    --     when 3 =>               -- accumulator / 3 (max value is 16383 * 3, upper four bits = 11)
                    --         case(out_l_acc(15 downto 11)) is
                    --             when "11000"|"10111"                    =>  out_l <= x"F";
                    --             when "10110"|"10101"                    =>  out_l <= x"E";
                    --             when "10100"                            =>  out_l <= x"D";
                    --             when "10011"|"10010"                    =>  out_l <= x"C";
                    --             when "10001"|"10000"                    =>  out_l <= x"B";
                    --             when "01111"                            =>  out_l <= x"A";
                    --             when "01110"|"01101"                    =>  out_l <= x"9";
                    --             when "01100"                            =>  out_l <= x"8";
                    --             when "01011"|"01010"                    =>  out_l <= x"7";
                    --             when "01001"|"01000"                    =>  out_l <= x"6";
                    --             when "00111"                            =>  out_l <= x"5";
                    --             when "00110"|"00101"                    =>  out_l <= x"4";
                    --             when "00100"                            =>  out_l <= x"3";
                    --             when "00011"|"00010"                    =>  out_l <= x"2";
                    --             when "00001"                            =>  out_l <= x"1";
                    --             when others                             =>  out_l <= x"0";
                    --         end case;
                    --     when others =>
                    --         out_l <= (others => '0');
                    -- end case;
                end if;

                if voice_cnt MOD 2 = 0 then -- on 0, 2, 4, and 6 (for latency = 8 and total voices = 4)
                    -- route numerator, denominator, and quotient from correct voice generator to division module
                    arb_num  <= num(voice_cnt/2);
                    arb_den  <= den(voice_cnt/2);
                    -- put the quotient in the right input as soon as it's available
                    quot((voice_cnt/2 - 1) MOD 4) <= arb_quot;
                end if;

                -- if we're starting a new cycle of voices, set the accumulators directly, otherwise, add to it
                if voice_cnt = 0 then
                    out_acc <= "000" & cur_sig;
                    -- out_r_acc <= "000" & cur_sig_r;    -- start accumulator over on cnt = 0
                    -- out_l_acc <= "000" & cur_sig_l;
                else
                    out_acc <= std_logic_vector(unsigned(out_acc) + unsigned(cur_sig));
                    -- out_r_acc <= std_logic_vector(unsigned(out_r_acc) + unsigned(cur_sig_r));
                    -- out_l_acc <= std_logic_vector(unsigned(out_l_acc) + unsigned(cur_sig_l));
                end if;

                -- if SET is latched for a particular voice, update its current channel active status and latch in channel setting
                if SET0 = '1' then       -- VOICE [3:0] = 0 means not active (no note), else active if the correct channel bit is set
                    active(0) <= (VOICE0(3) OR VOICE0(2) OR VOICE0(1) OR VOICE0(0));
                    -- active_r(0) <= (VOICE0(3) OR VOICE0(2) OR VOICE0(1) OR VOICE0(0)) AND VOICE0(10);   -- active in right channel
                    -- active_l(0) <= (VOICE0(3) OR VOICE0(2) OR VOICE0(1) OR VOICE0(0)) AND VOICE0(11);   -- active in left channel
                end if;
                if SET1 = '1' then
                    active(1) <= (VOICE1(3) OR VOICE1(2) OR VOICE1(1) OR VOICE1(0));
                    -- active_r(1) <= (VOICE1(3) OR VOICE1(2) OR VOICE1(1) OR VOICE1(0)) AND VOICE1(10);
                    -- active_l(1) <= (VOICE1(3) OR VOICE1(2) OR VOICE1(1) OR VOICE1(0)) AND VOICE1(11);
                end if;
                if SET2 = '1' then
                    active(2) <= (VOICE2(3) OR VOICE2(2) OR VOICE2(1) OR VOICE2(0));
                    -- active_r(2) <= (VOICE2(3) OR VOICE2(2) OR VOICE2(1) OR VOICE2(0)) AND VOICE2(10);
                    -- active_l(2) <= (VOICE2(3) OR VOICE2(2) OR VOICE2(1) OR VOICE2(0)) AND VOICE2(11); 
                end if;
                if SET3 = '1' then
                    active(3) <= (VOICE3(3) OR VOICE3(2) OR VOICE3(1) OR VOICE3(0));
                    -- active_r(3) <= (VOICE3(3) OR VOICE3(2) OR VOICE3(1) OR VOICE3(0)) AND VOICE3(10);
                    -- active_l(3) <= (VOICE3(3) OR VOICE3(2) OR VOICE3(1) OR VOICE3(0)) AND VOICE3(11);
                end if;

                -- recalculate number of active voices for each channel by treating each bit as a 1‑bit vector
                num_voices <= to_integer(unsigned(active(0 to 0)))
                            + to_integer(unsigned(active(1 to 1)))
                            + to_integer(unsigned(active(2 to 2)))
                            + to_integer(unsigned(active(3 to 3)));

                -- num_voices_r <= to_integer(unsigned(active_r(0 to 0)))
                --               + to_integer(unsigned(active_r(1 to 1)))
                --               + to_integer(unsigned(active_r(2 to 2)))
                --               + to_integer(unsigned(active_r(3 to 3)));

                -- num_voices_l <= to_integer(unsigned(active_l(0 to 0)))
                --               + to_integer(unsigned(active_l(1 to 1)))
                --               + to_integer(unsigned(active_l(2 to 2)))
                --               + to_integer(unsigned(active_l(3 to 3)));

            end if;
        end if;
    end process;
end Structural;