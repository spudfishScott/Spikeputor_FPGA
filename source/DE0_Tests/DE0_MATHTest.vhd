library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_MATHTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        CLOCK_50 : in std_logic;
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        
        --OUTPUTS
        -- GPIO
        GPIO0_D  : out std_logic_vector(31 downto 0);
        GPIO1_D  : out std_logic_vector(31 downto 0);
        -- 7-SEG Display
        HEX0_D   : out std_logic_vector(6 downto 0);
        HEX0_DP  : out std_logic;
        HEX1_D   : out std_logic_vector(6 downto 0);
        HEX1_DP  : out std_logic;
        HEX2_D   : out std_logic_vector(6 downto 0);
        HEX2_DP  : out std_logic;
        HEX3_D   : out std_logic_vector(6 downto 0);
        HEX3_DP  : out std_logic;
        -- LED
        LEDG     : out std_logic_vector(9 downto 0)
);
end DE0_MATHTest;

architecture Structural of DE0_MATHTest is
    signal addsub_result : std_logic_vector(63 downto 0) := (others => '0');
    signal mult_result   : std_logic_vector(63 downto 0) := (others => '0');
    signal div_result    : std_logic_vector(63 downto 0) := (others => '0');
    signal atan_result    : std_logic_vector(31 downto 0) := (others => '0');

    signal output_result  : std_logic_vector(63 downto 0) := (others => '0');
    signal enabled : std_logic_vector(15 downto 0) := (others => '0');  -- one hot enable of each math function
begin
    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(9 downto 0) <= output_result(47 downto 38);   -- 10 more bits of mantissa

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => output_result(63 downto 48),  -- upper bits of result = sign + 11 bits of exponent + 20 bits of mantissa
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    with (SW(9 downto 6)) select                -- switches 9 through 6 select the math function
        enabled <=
            "0000000000000001" when "0000",          -- ADD
            "0000000000000010" when "0001",          -- SUB
            "0000000000000100" when "0010",          -- MULT
            "0000000000001000" when "0011",          -- DIV
            "0000000010000000" when "0111",          -- ATAN
            "0000000000000000" when others;

    with (SW(9 downto 6)) select                -- same selects the output
        output_result <=
            addsub_result   when "0000"|"0001",
            mult_result     when "0010",
            div_result      when "0011",
            atan_result & "00000000000000000000000000000000"      when "0111", -- temporary
            (others => '0') when others;

    -- FP ADD_SUB instance - answer available in 7 cycles
    ADDSUB : work.FPADD_SUB port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(0) OR enabled(1),
        A       => SW(5 downto 3) & "0000000000000000000000000000000000000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "1111111111000000000000000000000000000000000000000000000000000", -- switch in "001" = +1.5, "101" = -1.5
        ADD     => enabled(0),
        RES     => addsub_result
    );

    -- FP MULT instance -- answer available in 5 cycles
    MULT: work.FPMULT port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(2),
        A       => SW(5 downto 3) & "0000000000000000000000000000000000000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "1111111111000000000000000000000000000000000000000000000000000", -- switch in "001" = +1.5, "101" = -1.5
        RES     => mult_result
    );

    -- FP DIV instance -- answer available in 10 cycles
    DIV: work.FPDIV port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(3),
        A       => SW(5 downto 3) & "0000000000000000000000000000000000000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "1111111111000000000000000000000000000000000000000000000000000", -- switch in "001" = +1.5, "101" = -1.5
        RES     => div_result
    );

    -- FP SATANIN instance -- answer available in 36 cycles
    ATAN: work.FPATAN port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(7),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => atan_result
    );
end Structural;