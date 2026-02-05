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

    constant z25         : std_logic_vector(24 downto 0) := (others => '0');    -- 25 zero bits
    constant z16         : std_logic_vector(15 downto 0) := (others => '0');    -- 16 zero bits

    signal addsub_result : std_logic_vector(31 downto 0) := (others => '0');
    signal mult_result   : std_logic_vector(31 downto 0) := (others => '0');
    signal div_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal sqrt_result   : std_logic_vector(31 downto 0) := (others => '0');
    signal exp_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal ln_result     : std_logic_vector(31 downto 0) := (others => '0');
    signal atan_result   : std_logic_vector(31 downto 0) := (others => '0');
    signal sin_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal cos_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal cmp_result    : std_logic_vector(6 downto 0)  := (others => '0');
    signal i2f_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal f2i_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal idiv_quot     : std_logic_vector(15 downto 0) := (others => '0');
    signal idiv_rem      : std_logic_vector(15 downto 0) := (others => '0');
    signal imult_result  : std_logic_vector(31 downto 0) := (others => '0');

    signal fn_select     : std_logic_vector(3 downto 0)  := (others => '0');
    signal output_result : std_logic_vector(31 downto 0) := (others => '0');
    signal enabled       : std_logic_vector(15 downto 0) := (others => '0');  -- one hot enable of each math function
begin
    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    -- asign function select from top four switches
    fn_select <= SW(9 downto 6);

    -- LEDs show 10 more bits of mantissa unless IDIV, then 10 bits of of remainder, or CMP, then zero padded 7 bits of result
    LEDG(9 downto 0) <= 
        idiv_rem(15 downto 6)      when fn_select = "1101" else    -- IDIV
        output_result(9 downto 0)   when fn_select = "1010" else    -- CMP
        output_result(15 downto 6);

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => output_result(31 downto 16),  -- upper bits of result = sign + 8 bits of exponent + 7 bits of mantissa
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    with (fn_select) select                     -- select math function
        enabled <=
            "0000000000000001" when "0000",          -- ADD
            "0000000000000010" when "0001",          -- SUB
            "0000000000000100" when "0010",          -- MULT
            "0000000000001000" when "0011",          -- DIV
            "0000000000010000" when "0100",          -- SQRT
            "0000000000100000" when "0101",          -- EXP
            "0000000001000000" when "0110",          -- LN
 --           "0000000010000000" when "0111",          -- ATAN - removed due to resource requirements
            "0000000100000000" when "1000",          -- SIN
 --           "0000001000000000" when "1001",          -- COS - removed due to resource requirements
            "0000010000000000" when "1010",          -- CMP
            "0000100000000000" when "1011",          -- INT to FLOAT
            "0001000000000000" when "1100",          -- FLOAT to INT
            "0010000000000000" when "1101",          -- Integer Divide (64 bit / 32 bit)
            "0100000000000000" when "1110",          -- Integer Multiply
            "0000000000000000" when others;

    with (fn_select) select                     -- select output
        output_result <=
            addsub_result           when "0000"|"0001",
            mult_result             when "0010",
            div_result              when "0011",
            sqrt_result             when "0100",
            exp_result              when "0101",
            ln_result               when "0110",
--            atan_result             when "0111",      -- removed due to resource requirements
            sin_result              when "1000",
--            cos_result              when "1001",      -- removed due to resource requirements
            z25 & cmp_result        when "1010",        -- CMP result is only 7 bits
            i2f_result              when "1011",
            f2i_result              when "1100",
            z16 & idiv_quot         when "1101",        -- 16 bits output, remainder output is separate
            imult_result            when "1110",        -- imult is 16x16 bit inputs, 32 bit output
            (others => '0')         when others;

    -- FP ADD_SUB instance - answer available in 7 cycles
    ADDSUB : work.FPADD_SUB port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(0) OR enabled(1),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "11111100000000000000000000000", -- switch in "001" = +1, "101" = -1
        ADD     => enabled(0),
        RES     => addsub_result
    );

    -- FP MULT instance -- answer available in 5 cycles
    MULT: work.FPMULT port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(2),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "11111100000000000000000000000", -- switch in "001" = +1, "101" = -1
        RES     => mult_result
    );

    -- FP DIV instance -- answer available in 10 cycles
    DIV: work.FPDIV port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(3),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "11111110000000000000000000000", -- switch in "001" = +1.5, "101" = -1.5
        RES     => div_result
    );

    -- FP SQRT instance -- answer available in 30 cycles
    SQRT: work.FPSQRT port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(4),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => sqrt_result
    );

    -- FP EXP instance -- answer available in 25 cycles
    EXP: work.FPEXP port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(5),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => exp_result
    );

    -- FP LN instance -- answer available in 34 cycles
    LN: work.FPLN port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(6),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => ln_result
    );

    -- Removed due to resource requirements
    -- -- FP ATAN instance -- answer available in 34 cycles - 32 bit float
    -- ATAN: work.FPATAN port map (
    --     CLOCK   => CLOCK_50,
    --     EN      => enabled(7),
    --     A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
    --     RES     => atan_result
    -- );

    -- FP SIN instance -- answer available in 36 cycles - 32 bit float
    SIN: work.FPSIN port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(8),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => sin_result
    );

    -- Removed due to resource requirements
    -- -- FP COS instance -- answer available in 35 cycles - 32 bit float
    -- COS: work.FPCOS port map (
    --     CLOCK   => CLOCK_50,
    --     EN      => enabled(9),
    --     A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
    --     RES     => cos_result
    -- );

    -- FP Compare instance -- answer available in 1 cycles - 7 bits of output (aeb/aneb/agb/ageb/alb/aleb/unrodered)
    CMP: work.FPCOMPARE port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(10),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        B       => SW(2 downto 0) & "00000000000000000000000000000", -- switch in "010" = +2, "101" = -2
        RES     => cmp_result
    );

    -- Convert INT to FLOAT - answer in 6 cycles
    I2F: work.FPCONVERT_IF port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(11),
        A       => SW(5 downto 3) & "00000000000000000000000000010", -- switch in "000" = +2, "111" = -(2^29 - 2)
        RES     => i2f_result
    );

     -- Convert FLOAT to INT - answer in 6 cycles
    F2I: work.FPCONVERT_FI port map (
        CLOCK   => CLOCK_50,
        EN      => enabled(12),
        A       => SW(5 downto 3) & "00000000000000000000000000000", -- switch in "010" = +2, "110" = -2
        RES     => f2i_result
    );

    -- Integer division - 16 bit numerator and 16 bit denominator - answer immediately as 16 bit quotient and 16 bit remainder
    IDIV: work.INTDIV port map (
        A       => SW(5 downto 3) & "0000000000000", -- switch in "010" = +2^14, "110" = -2^14
        B       => SW(2 downto 0) & "0000000000001", -- switch in "010" = +2^14+1, "110" = -(2^14 - 1)
        QUOT    => idiv_quot,
        REMND   => idiv_rem
    );

    -- Integer multiplication - answer immediately
    IMULT: work.INTMULT port map (
        A       => SW(5 downto 3) & "0000000000000", -- switch in "010" = +2^14, "110" = -2^14
        B       => SW(2 downto 0) & "0000000000000", -- switch in "010" = +2^14, "110" = -2^14
        RES   => imult_result
    );

end Structural;