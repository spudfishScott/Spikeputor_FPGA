-- ALU Modules
-- ARITH - Addition and Subtraction
-- BOOL  - Boolean Math
-- SHIFT - Variable Bitwise Shifting
-- CMP   - Comparison

-----------------------------------------------------------------------------------------
-- ARITH  - add or subtract the two inputs, given a SUB flag for subtraction
--          Outputs are the Sum (M_OUT), the final carry bit (COUT), and the inverted B input (for LEDs)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ARITH is
    port (
             A  : in std_logic_vector(15 downto 0);
             B  : in std_logic_vector(15 downto 0);
           SUB  : in std_logic;

         M_OUT  : out std_logic_vector(15 downto 0);
          COUT  : out std_logic;
         INV_B  : out std_logic_vector(15 downto 0)
    );
end ARITH;

architecture Behavior of ARITH is

    signal SUM : std_logic_vector(16 downto 0) := (others => '0'); -- extra bit for the carry
    signal BX  : std_logic_vector(15 downto 0) := (others => '0'); -- B transformed for the addition operation

begin

    M_OUT   <= SUM(15 downto 0);
    COUT    <= SUM(16);
    INV_B   <= B when SUB = '0'
                 else B XOR X"FFFF";

    BX      <= B when SUB = '0' 
                 else std_logic_vector(unsigned(NOT B) + 1);
                 
    SUM     <= std_logic_vector(resize(unsigned(A), 17) + resize(unsigned(BX), 17));

end Behavior;

-----------------------------------------------------------------------------------------
-- BOOL  - bitwise boolean math, given A, B, and the truth table for all four values of A op B
--       Output is the result of the bitwise operation (M_OUT)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BOOL is 
    port (
             A  : in std_logic_vector(15 downto 0);
             B  : in std_logic_vector(15 downto 0);
           BFN  : in std_logic_vector(3 downto 0);

         M_OUT  : out std_logic_vector(15 downto 0)
    );
end BOOL;

architecture Behavior of BOOL is
    type BOOLARRAY is array(15 downto 0) of std_logic_vector(1 downto 0);
    signal BA : BOOLARRAY := (others => (others => '0'));

begin
    MUXES: for m in 15 downto 0 generate   -- generate the 16 MUXes to do the bitwise boolean math
    begin
        BA(m) <= B(m) & A(M);
        with (BA(m)) select
            M_OUT(m) <=
                BFN(3) when "11",
                BFN(2) when "10",
                BFN(1) when "01",
                BFN(0) when "00",
                '0' when others;
    end generate MUXES;

end Behavior;

-----------------------------------------------------------------------------------------
-- SHIFT - variable bit shifting, given A, the value to shift, B, the number of bits to shift (in the lowest nybble of B)
--         EXT, the sign extrension bit, and DIR, the direction to shift
--       Output is the result of the shift operation (M_OUT), all of the intermediate shifts (8, 4, 2 and 1 bit shifts of A)
--         and the value of A used (reversed if DIR is true)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SHIFT is 
    port (
             A  : in std_logic_vector(15 downto 0);
             B  : in std_logic_vector(3 downto 0);
           EXT  : in std_logic;
           DIR  : in std_logic;

         M_OUT  : out std_logic_vector(15 downto 0);
           S_8  : out std_logic_vector(15 downto 0);
           S_4  : out std_logic_vector(15 downto 0);
           S_2  : out std_logic_vector(15 downto 0);
           S_1  : out std_logic_vector(15 downto 0);
         REV_A  : out std_logic_vector(15 downto 0)
    );
end SHIFT;

architecture Behavior of SHIFT is

    signal S8 : std_logic_vector(15 downto 0) := (others => '0');       -- 8 bit shift
    signal S4 : std_logic_vector(15 downto 0) := (others => '0');       -- 4 bit shift
    signal S2 : std_logic_vector(15 downto 0) := (others => '0');       -- 2 bit shift
    signal S1 : std_logic_vector(15 downto 0) := (others => '0');       -- 1 bit shift
    signal S1_REV : std_logic_vector(15 downto 0) := (others => '0');   -- (re)reversed final result
    signal AX : std_logic_vector(15 downto 0) := (others => '0');       -- A, possibly reversed for the shift operation
    signal A_REV : std_logic_vector(15 downto 0) := (others => '0');    -- reversed A for the shift operation
    signal S_EXT : std_logic_vector(7 downto 0) := (others => '0');     -- sign extension vector

begin
    REVERSE_A: entity work.REVERSE generic map(16) port map (
        D => A,
        Q => A_REV
    );

    AX <= A when DIR = '0' 
            else A_REV;

    S_EXT <= (others => '1') when EXT = '1' 
                             else (others => '0');

    S8 <= AX when B(3) = '0'
             else S_EXT(7 downto 0) & AX(15 downto 8);

    S4 <= S8 when B(2) = '0'
             else S_EXT(3 downto 0) & S8(15 downto 4);

    S2 <= S4 when B(1) = '0'
             else S_EXT(1 downto 0) & S4(15 downto 2);

    S1 <= S2 when B(0) = '0'
             else S_EXT(0) & S2(15 downto 1);

    REVERSE_S1: entity work.REVERSE generic map(16) port map (
        D => S1,
        Q => S1_REV
    );

    S_8 <= S8;
    S_4 <= S4;
    S_2 <= S2;
    S_1 <= S1;
    REV_A <= AX;

    M_OUT <= S1 when DIR = '0'
                else S1_REV;

end Behavior;

-----------------------------------------------------------------------------------------
-- CMP   - Comparison functions, given the msb's of the two numbers to compare (A15 and B15), and a function (FN) (LT ,LE, UL, EQ)
--         Also need the difference of the two numbers (SUM) and the final carry out (CARRY)
--       Outputs are the N(egative), Z(ero), and (o)V(erflow) flags, plus a single bit result (M_OUT)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CMP is
    port (
           A15 : in std_logic;
           B15 : in std_logic;
            FN : in std_logic_vector(1 downto 0);
         CARRY : in std_logic;
           SUM : in std_logic_vector(15 downto 0);

             Z : out std_logic;
             V : out std_logic;
             N : out std_logic;
         M_OUT : out std_logic
    );
end CMP;

architecture Behavior of CMP is
    constant ZEROS : std_logic_vector := "0000000000000000";

    signal z_flag : std_logic := '0';   -- zero flag
    signal v_flag : std_logic := '0';   -- overflow flag
    signal n_flag : std_logic := '0';   -- negative flag
    signal     lt : std_logic := '0';   -- less than signal

begin
    z_flag <= '1' when (SUM = ZEROS) else '0';
    n_flag <= SUM(15);
	 -- B15 is inverted version of what it should be for comparison
    v_flag <= (A15 AND (NOT B15) AND (NOT SUM(15))) OR ((NOT A15) AND B15 AND (SUM(15)));
    lt <= n_flag XOR v_flag;

    Z <= z_flag;
    V <= v_flag;
	 N <= n_flag;

    with (FN) select
        M_OUT <=
               z_flag when "00",
            NOT CARRY when "01",
                   lt when "10",
         lt OR z_flag when "11",
                  '0' when others;

end Behavior;