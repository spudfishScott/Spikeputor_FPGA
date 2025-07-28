-- Spikeputor ALU
-- Inputs:
--     ALU Function
--     ASEL, BSEL
--     REGA/PC_INC
--     REGB/CONST
-- Outputs:
--     ALU Output

-- All data is 16 bits wide

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ALU is

    port (
        ALUFN   : in std_logic_vector(4 downto 0);
        ASEL    : in std_logic;
        BSEL    : in std_logic;
        REGA    : in std_logic_vector(15 downto 0);
        PC_INC  : in std_logic_vector(15 downto 0);
        REGB    : in std_logic_vector(15 downto 0);
        CONST   : in std_logic_vector(15 downto 0);

        ALUOUT  : out std_logic_vector(15 downto 0);

        -- LED ouputs
        A       : out std_logic_vector(15 downto 0);
        B       : out std_logic_vector(15 downto 0);
        REV_A   : out std_logic_vector(15 downto 0);
        INV_B   : out std_logic_vector(15 downto 0);
        SHIFT   : out std_logic_vector(15 downto 0);
        ARITH   : out std_logic_vector(15 downto 0);
        BOOL    : out std_logic_vector(15 downto 0);
        SHIFT8  : out std_logic_vector(15 downto 0);
        SHIFT4  : out std_logic_vector(15 downto 0);
        SHIFT2  : out std_logic_vector(15 downto 0);
        SHIFT1  : out std_logic_vector(15 downto 0);
        CMP_FLAGS   : out std_logic_vector(3 downto 0);
        ALU_FN_LEDS : out std_logic_vector(12 downto 0)
    );

end ALU;

architecture RTL of ALU is
    CONSTANT ZERO : std_logic_vector(15 downto 0) := "0000000000000000";
    CONSTANT ONE  : std_logic_vector(15 downto 0) := "0000000000000001";

    -- input signals for the four ALU math modules
    signal OUTSEL   : std_logic_vector(1 downto 0) := (others => '0');  -- which module is output
    signal BFN      : std_logic_vector(3 downto 0) := (others => '0');  -- the four bits for binary math
    signal CMP_FN   : std_logic_vector(1 downto 0) := (others => '0');  -- compare function
    signal SHFT_EXT : std_logic := '0';                                 -- sign extension for shifting
    signal SHFT_DIR : std_logic := '0';                                 -- shift direction
    signal SUB      : std_logic := '0';                                 -- subtraction flag (for adder)
    signal A_IN     : std_logic_vector(15 downto 0) := (others => '0'); -- ALU Input A
    signal B_IN     : std_logic_vector(15 downto 0) := (others => '0'); -- ALU Input B

    -- output signals for the four ALU math modules
    signal S_ARITH    : std_logic_vector(15 downto 0) := (others => '0'); -- arithmetic output
    signal S_SHIFT    : std_logic_vector(15 downto 0) := (others => '0'); -- shift output
    signal S_BOOL     : std_logic_vector(15 downto 0) := (others => '0'); -- bool output
    signal CMP_BIT    : std_logic := '0';                                 -- compare output
    signal ADD_COUT   : std_logic := '0';                                 -- final carry out of arithmetic (for compare)
    signal S_CMP      : std_logic_vector(15 downto 0) := (others => '0'); -- cmp output extended to 16 bits

begin

    -- Module Inputs
    A_IN <= PC_INC when ASEL = '1' else REGA;
    B_IN <= CONST when BSEL = '1' else REGB;

    -- Generate Module Input Signals
    OUTSEL   <= ALUFN(4 downto 3);
    SHFT_EXT <= A_IN(15) AND ALUFN(1);  -- shift extension is msb of A if ALUFN[1] is set
    SHFT_DIR <= ALUFN(0);               -- shift direction is ALUFN[0]
    SUB      <= ALUFN(0);               -- subtraction flag is also ALUFN[0] (must be set for compare functions as well)
    CMP_FN   <= ALUFN(2 downto 1);      -- compare function is ALUFN[2:1]

    with (ALUFN(2 downto 0)) select     -- logic to convert three bit ALUFN to four bit BOOL math template
        BFN <=
            "0001" when "000",      -- NOR
            "0111" when "001",      -- NAND
            "0100" when "010",      -- BnotA
            "0110" when "011",      -- XOR
            "1000" when "100",      -- AND
            "1010" when "101",      -- A
            "1100" when "110",      -- B
            "1110" when "111",      -- OR
            "0000" when others;

    -- LED signals
    ARITH <= S_ARITH;
    BOOL  <= S_BOOL;
    SHIFT <= S_SHIFT;           -- other shift LED signals (SHIFT8, SHIFT4, SHIFT2, SHIFT1, REV_A) produced directly from SHIFT module
    CMP_FLAGS(0) <= CMP_BIT;    -- other CMP_FLAGS produced directly from CMP module
    A     <= A_IN;
    B     <= B_IN;

    -- Generate additional LED outputs
    ALU_FN_LEDS(12) <= '1' when OUTSEL = "01" else '0';
    ALU_FN_LEDS(11) <= SUB;
    ALU_FN_LEDS(10) <= '1' when OUTSEL = "11" else '0';
    ALU_FN_LEDS(9)  <= SHFT_EXT;
    ALU_FN_LEDS(8)  <= SHFT_DIR;
    ALU_FN_LEDS(7)  <= '1' when OUTSEL = "00" else '0';
    ALU_FN_LEDS(6 downto 5) <= CMP_FN;
    ALU_FN_LEDS(4)  <= '1' when OUTSEL = "10" else '0';
    ALU_FN_LEDS(3 downto 0) <= BFN;

    -- ALU Modules
    -- Arithmetic (addition and subtraction)
    M_ARITH: entity work.ARITH port map (
             A => A_IN,
             B => B_IN,
           SUB => SUB,
         M_OUT => S_ARITH,
          COUT => ADD_COUT,
         INV_B => INV_B
    );

    -- Boolean Math
    M_BOOL: entity work.BOOL port map (
             A => A_IN,
             B => B_IN,
           BFN => BFN,
         M_OUT => S_BOOL
    );

    -- Bit Shifts
    M_SHIFT: entity work.SHIFT port map (
             A => A_IN,
             B => B_IN(3 downto 0),
           EXT => SHFT_EXT,
           DIR => SHFT_DIR,
         M_OUT => S_SHIFT,
           S_8 => SHIFT8,
           S_4 => SHIFT4,
           S_2 => SHIFT2,
           S_1 => SHIFT1,
         REV_A => REV_A
    );

    -- Compares
    M_CMP: entity work.CMP port map (
           A15 => A_IN(15),
           B15 => B_IN(15),
            FN => CMP_FN,
         CARRY => ADD_COUT,
           SUM => S_ARITH,
             Z => CMP_FLAGS(3),
             V => CMP_FLAGS(2),
             N => CMP_FLAGS(1),
         M_OUT => CMP_BIT
    );
    S_CMP <= ZERO when CMP_BIT = '0' else ONE;

     -- Send correct module output to ALU output
    OUTMUX : entity work.MUX4 generic map(16) port map (
           IN3 => S_SHIFT,
           IN2 => S_BOOL,
           IN1 => S_ARITH,
           IN0 => S_CMP,
           SEL => OUTSEL,
        MUXOUT => ALUOUT
    );

end RTL;
