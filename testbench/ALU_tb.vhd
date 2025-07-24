library ieee;
use ieee.std_logic_1164.all;

entity alu_tb is
end entity;

architecture tb of alu_tb is

    -- Component declaration
    component ALU
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
    end component;

    -- Signals for DUT
            signal S_ALUFN   : std_logic_vector(4 downto 0);
            signal S_ASEL    : std_logic;
            signal S_BSEL    : std_logic;
            signal S_REGA    : std_logic_vector(15 downto 0);
            signal S_PC_INC  : std_logic_vector(15 downto 0);
            signal S_REGB    : std_logic_vector(15 downto 0);
            signal S_CONST   : std_logic_vector(15 downto 0);

            signal R_ALUOUT  : std_logic_vector(15 downto 0);

            -- LED ouputs
            signal R_A       : std_logic_vector(15 downto 0);
            signal R_B       : std_logic_vector(15 downto 0);
            signal R_REV_A   : std_logic_vector(15 downto 0);
            signal R_INV_B   : std_logic_vector(15 downto 0);
            signal R_SHIFT   : std_logic_vector(15 downto 0);
            signal R_ARITH   : std_logic_vector(15 downto 0);
            signal R_BOOL    : std_logic_vector(15 downto 0);
            signal R_SHIFT8  : std_logic_vector(15 downto 0);
            signal R_SHIFT4  : std_logic_vector(15 downto 0);
            signal R_SHIFT2  : std_logic_vector(15 downto 0);
            signal R_SHIFT1  : std_logic_vector(15 downto 0);
            signal R_CMP_FLAGS   : std_logic_vector(3 downto 0);
            signal R_ALU_FN_LEDS : std_logic_vector(12 downto 0);

begin

    -- Instantiate DUT
    DUT: ALU
        port map (
            ALUFN   => S_ALUFN,
            ASEL    => S_ASEL,
            BSEL    => S_BSEL,
            REGA    => S_REGA,
            PC_INC  => S_PC_INC,
            REGB    => S_REGB,
            CONST   => S_CONST,

            ALUOUT  => R_ALUOUT,

            -- LED ouputs
            A       => R_A,
            B       => R_B,
            REV_A   => R_REV_A,
            INV_B   => R_INV_B,
            SHIFT   => R_SHIFT,
            ARITH   => R_ARITH,
            BOOL    => R_BOOL,
            SHIFT8  => R_SHIFT8,
            SHIFT4  => R_SHIFT4,
            SHIFT2  => R_SHIFT2,
            SHIFT1  => R_SHIFT1,
            CMP_FLAGS   => R_CMP_FLAGS,
            ALU_FN_LEDS => R_ALU_FN_LEDS
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- Initial state
          S_REGA <= X"DEAD";
          S_REGB <= X"F00D";
        S_PC_INC <= X"BADD";
         S_CONST <= X"FACE";
         S_ALUFN <= "00000";
          S_ASEL <= '0';
          S_BSEL <= '0';
        wait for 25 ns;

        -- test ARITH
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "01000"; -- ADD DEAD + F00D
        wait for 25 ns;
        assert R_ALUOUT = X"CEBA" report "Wrong result for DEAD + F00D" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "01001"; -- SUBTRACT DEAD - FACE
        wait for 25 ns;
        assert R_ALUOUT = X"E3DF" report "Wrong result for DEAD - FACE" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00001"; -- CMPEQ BADD == F00D
        wait for 25 ns;
        assert R_ALUOUT = X"0000" report "Wrong result for BADD == F00D" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "00011"; -- CMPUL BADD < FACE (unsigned)
        wait for 25 ns;
        assert R_ALUOUT = X"0001" report "Wrong result for BADD < FACE (unsigned)" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00101"; -- CMPLT DEAD < F00D (signed)
        wait for 25 ns;
        assert R_ALUOUT = X"0001" report "Wrong result for DEAD < F00D (signed)" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "00111"; -- CMPLE DEAD <= FACE
        wait for 25 ns;
        assert R_ALUOUT = X"0001" report "Wrong result for DEAD <= FACE" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "10000"; -- BADD NOR F00D
        wait for 25 ns;
        assert R_ALUOUT = X"0522" report "Wrong result for BADD NOR F00D" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "10001"; -- BADD NAND FACE
        wait for 25 ns;
        assert R_ALUOUT = X"4533" report "Wrong result for BADD NAND FACE" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "10010"; -- NOT(DEAD) AND F00D
        wait for 25 ns;
        assert R_ALUOUT = X"2000" report "Wrong result for NOT(DEAD) AND F00D" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "10011"; --  DEAD XOR FACE
        wait for 25 ns;
        assert R_ALUOUT = X"2463" report "Wrong result for DEAD XOR FACE" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "10100"; -- BADD AND F00D
        wait for 25 ns;
        assert R_ALUOUT = X"B00D" report "Wrong result for BADD AND F00D" severity error;

        S_ASEL <= '1';      -- PC_INC
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "10101"; -- BADD A FACE
        wait for 25 ns;
        assert R_ALUOUT = X"BADD" report "Wrong result for BADD A FACE" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "10110"; -- DEAD B F00D
        wait for 25 ns;
        assert R_ALUOUT = X"F00D" report "Wrong result for DEAD B F00D" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '1';      -- CONST
        S_ALUFN <= "10111"; --  DEAD OR FACE
        wait for 25 ns;
        assert R_ALUOUT = X"FEEF" report "Wrong result for DEAD OR FACE" severity error;

        S_REGB <= X"DEAD";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00001"; -- CMPEQ DEAD == DEAD
        wait for 25 ns;
        assert R_ALUOUT = X"0001" report "Wrong result for DEAD == DEAD" severity error;

        S_REGB <= X"B0D1";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00011"; -- CMPUL DEAD < B0D1 (unsigned)
        wait for 25 ns;
        assert R_ALUOUT = X"0000" report "Wrong result for DEAD < B0D1 (unsigned)" severity error;

        S_REGA <= X"01CE";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00101"; -- CMPLT 01CE < DEAD (signed)
        wait for 25 ns;
        assert R_ALUOUT = X"0000" report "Wrong result for 01CE < DEAD (signed)" severity error;

        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00111"; -- CMPLE 01CE <= DEAD
        wait for 25 ns;
        assert R_ALUOUT = X"0000" report "Wrong result for 01CE <= DEAD" severity error;

        S_REGB <= X"01CE";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "00111"; -- CMPLE 01CE <= DEAD
        wait for 25 ns;
        assert R_ALUOUT = X"0001" report "Wrong result for 01CE <= 01CE" severity error;

        S_REGA <= X"B0D1";
        S_REGB <= X"0007";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "11011"; -- B0D1 SLC 7
        wait for 25 ns;
        assert R_ALUOUT = X"68FF" report "Wrong result for B0D1 SLC 7" severity error;

        S_REGB <= X"000A";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "11000"; -- B0D1 SHR A
        wait for 25 ns;
        assert R_ALUOUT = X"002C" report "Wrong result for B0D1 SLC A" severity error;

        S_REGB <= X"0003";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "11001"; -- B0D1 SHL A
        wait for 25 ns;
        assert R_ALUOUT = X"8688" report "Wrong result for B0D1 SHL 3" severity error;

        S_REGB <= X"0009";
        S_ASEL <= '0';      -- REGA
        S_BSEL <= '0';      -- REGB
        S_ALUFN <= "11010"; -- B0D1 SRA 9
        wait for 25 ns;
        assert R_ALUOUT = X"FFD8" report "Wrong result for B0D1 SRA 9" severity error;
        -- End simulation
        wait;
    end process;

end architecture;