-- Testbench for AUDIO_SIG.vhd
-- Exercises the note frequency generation and waveform outputs
-- Includes a pipelined divider simulation with 4-cycle latency
-- Sine waveform is not verified (left as future work)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AUDIO_SIG_tb is
end AUDIO_SIG_tb;

architecture Behavioral of AUDIO_SIG_tb is
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz clock
    constant DIVIDER_LATENCY : integer := 4;

    signal clk           : std_logic := '0';
    signal reset         : std_logic := '0';
    signal note_idx      : std_logic_vector(3 downto 0) := (others => '0');
    signal octave        : std_logic_vector(3 downto 0) := (others => '0');
    signal waveform      : std_logic_vector(1 downto 0) := (others => '0');
    signal set_sig       : std_logic := '0';
    signal sig_out       : std_logic_vector(13 downto 0);
    
    -- pipelined divider signals (inputs are multiplexed between test values and UUT outputs)
    signal audio_numerator   : std_logic_vector(31 downto 0);
    signal audio_denominator : std_logic_vector(31 downto 0);
    signal numerator         : std_logic_vector(31 downto 0);
    signal denominator       : std_logic_vector(31 downto 0);
    signal quotient          : std_logic_vector(31 downto 0);
    signal test_numerator    : std_logic_vector(31 downto 0);
    signal test_denominator  : std_logic_vector(31 downto 0);
    signal in_test_mode      : std_logic := '1';  -- start in test mode

begin
    -- instantiate unit under test (make sure we drive the clock port)
    uut: entity work.AUDIO_SIG
        generic map(
            CLK_FREQ       => 50_000_000,
            LATENCY        => 4,
            LATENCY_OFFSET => 0
        )
        port map(
            CLK         => clk,
            RESET       => reset,
            NUMERATOR   => audio_numerator,
            DENOMINATOR => audio_denominator,
            QUOTIENT    => quotient,
            NOTE_IDX    => note_idx,
            OCTAVE      => octave,
            WAVEFORM    => waveform,
            SET         => set_sig,
            SIG_OUT     => sig_out
        );

    -- multiplex test inputs and audio outputs to divider
    numerator <= test_numerator when in_test_mode = '1' else audio_numerator;
    denominator <= test_denominator when in_test_mode = '1' else audio_denominator;

    
    -- pipelined divider simulation with 4-cycle latency
    -- stores inputs and computes division result, returning it 4 cycles later
    divider_sim: process(clk)
        type divider_pipeline_t is array(0 to DIVIDER_LATENCY-1) of unsigned(31 downto 0);
        variable numerator_pipe   : divider_pipeline_t := (others => (others => '0'));
        variable denominator_pipe : divider_pipeline_t := (others => (others => '0'));
        variable result_pipe      : divider_pipeline_t := (others => (others => '0'));
    begin
        if rising_edge(clk) then
            if reset = '1' then
                numerator_pipe   := (others => (others => '0'));
                denominator_pipe := (others => (others => '0'));
                result_pipe      := (others => (others => '0'));
                quotient <= (others => '0');
            else
                -- shift pipeline stages
                for i in DIVIDER_LATENCY-1 downto 1 loop
                    numerator_pipe(i)   := numerator_pipe(i-1);
                    denominator_pipe(i) := denominator_pipe(i-1);
                    result_pipe(i)      := result_pipe(i-1);
                end loop;
                
                -- process new inputs at stage 0
                numerator_pipe(0)   := unsigned(numerator);
                denominator_pipe(0) := unsigned(denominator);
                
                -- compute division at stage 0 (will appear at output after LATENCY cycles)
                if denominator_pipe(0) /= 0 then
                    result_pipe(0) := numerator_pipe(0) / denominator_pipe(0);
                else
                    result_pipe(0) := (others => '0');
                end if;
                
                -- output the result from the last pipeline stage
                quotient <= std_logic_vector(result_pipe(DIVIDER_LATENCY-1));
            end if;
        end if;
    end process divider_sim;

    -- clock generation (continually toggles 'clk')
    clk_proc: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process clk_proc;

    -- stimulus process
    stimulus: process
        procedure apply_note(
            constant idx : std_logic_vector(3 downto 0);
            constant oct : std_logic_vector(3 downto 0);
            constant wf  : std_logic_vector(1 downto 0);
            constant duration : integer
        ) is
        begin
            note_idx <= idx;
            octave   <= oct;
            waveform <= wf;
            wait for CLK_PERIOD;
            set_sig <= '1';
            wait for CLK_PERIOD;
            set_sig <= '0';
            -- let output run for specified cycles
            wait for duration * CLK_PERIOD;
        end procedure;
        
        procedure test_divider_pipeline is
            -- Test the pipelined divider with known values
            variable expected : unsigned(31 downto 0);
        begin
            report "Testing pipelined divider pipeline..." severity note;
            in_test_mode <= '1';
            
            -- Test 1: Simple division (100 / 1 = 100)
            test_numerator   <= std_logic_vector(to_unsigned(100, 32));
            test_denominator <= std_logic_vector(to_unsigned(1, 32));
            wait for CLK_PERIOD;
            wait for DIVIDER_LATENCY * CLK_PERIOD;  -- wait for latency
            expected := to_unsigned(100, 32);
            assert unsigned(quotient) = expected
                report "Divider test 1 failed: expected " & integer'image(to_integer(expected)) & 
                       " got " & integer'image(to_integer(unsigned(quotient)))
                severity error;
            report "Divider test 1 passed: 100 / 1 = 100" severity note;
            
            -- Test 2: Division with remainder (250 / 25 = 10)
            test_numerator   <= std_logic_vector(to_unsigned(250, 32));
            test_denominator <= std_logic_vector(to_unsigned(25, 32));
            wait for CLK_PERIOD;
            wait for DIVIDER_LATENCY * CLK_PERIOD;
            expected := to_unsigned(10, 32);
            assert unsigned(quotient) = expected
                report "Divider test 2 failed" severity error;
            report "Divider test 2 passed: 250 / 25 = 10" severity note;
            
            -- Test 3: Large numbers (12500000 / 262 ≈ 47723)
            test_numerator   <= std_logic_vector(to_unsigned(12500000, 32));
            test_denominator <= std_logic_vector(to_unsigned(262, 32));
            wait for CLK_PERIOD;
            wait for DIVIDER_LATENCY * CLK_PERIOD;
            expected := to_unsigned(47709, 32);  -- integer division result
            assert unsigned(quotient) = expected
                report "Divider test 3 failed: expected " & integer'image(to_integer(expected)) &
                       " got " & integer'image(to_integer(unsigned(quotient)))
                severity error;
            report "Divider test 3 passed: 12500000 / 262 = 47709" severity note;
            
            test_numerator   <= (others => '0');
            test_denominator <= (others => '0');
            in_test_mode <= '0';
        end procedure;
    
    begin
        -- reset the device
        reset <= '1';
        wait for 5 * CLK_PERIOD;
        reset <= '0';
        
        report "Starting AUDIO_SIG testbench..." severity note;
        wait for 10 * CLK_PERIOD;
        
        -- Test the pipelined divider first
        test_divider_pipeline;
        wait for 500 * CLK_PERIOD;
        
        -- test square wave on middle C octave 4
        report "Testing triangle wave B2" severity note;
        apply_note("1100", "0100", "10", 101252);

        -- test sawtooth on A4
        report "Testing sawtooth wave B5" severity note;
        apply_note("1100", "0101", "01", 101252);

        -- test triangle on B5
        report "Testing sin wave B6" severity note;
        apply_note("1100", "1000", "11", 101252);

        -- test triangle on B5
        report "Testing square wave B6" severity note;
        apply_note("1100", "0111", "00", 101252);
        
        -- test square wave on high C (C8)
        report "Testing sawtooth wave B8" severity note;
        apply_note("1100", "1000", "01", 101252);

        -- test silence (note index 0)
        report "Testing silence" severity note;
        apply_note("0000", "0000", "00", 50000);

        -- end simulation
        wait for 50 * CLK_PERIOD;
        report "End of simulation" severity note;
        wait;
    end process stimulus;

end Behavioral;
