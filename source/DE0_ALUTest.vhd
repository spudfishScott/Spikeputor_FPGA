library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_ALUTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        -- GPIO
        GPIO0_D  : in std_logic_vector(31 downto 0);
        GPIO1_D  : in std_logic_vector(31 downto 16);

        --OUTPUTS
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
end DE0_ALUTest;

architecture Structural of DE0_ALUTest is
    signal disp_out : std_logic_vector(15 downto 0) := (others => '0');
    signal alu_led  : std_logic_vector(12 downto 0) := (others => '0');
begin
    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(9 downto 4) <= (others => '0'); -- other LEDs off

    LEDG(3 downto 0) <= alu_led(3 downto 0); -- display BRFN on LEDs 3-0

    -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => disp_out,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    -- ALU instance
   ALU0 : work.ALU port map (
        ALUFN   => SW(4 downto 0),
        ASEL    => SW(6),
        BSEL    => SW(5),
        REGA    => GPIO0_D(31 downto 16),
        PC_INC  => GPIO0_D(15 downto 0),
        REGB    => GPIO1_D(31 downto 16),
        CONST   => x"5A5A",

        ALUOUT  => disp_out,

        -- LED outputs
        A       => open,
        B       => open,
        REV_A   => open,
        INV_B   => open,
        SHIFT   => open,
        ARITH   => open,
        BOOL    => open,
        SHIFT8  => open,
        SHIFT4  => open,
        SHIFT2  => open,
        SHIFT1  => open,
        CMP_FLAGS   => open,
        ALU_FN_LEDS => alu_led
    );

end Structural;