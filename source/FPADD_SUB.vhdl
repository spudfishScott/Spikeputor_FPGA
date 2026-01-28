-- FP Add test
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPADD_SUB IS
    GENERIC ( OPTIMIZE : String := "AREA" );

    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        ADD   : IN STD_LOGIC := '1';
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPADD_SUB;

ARCHITECTURE SYN OF FPADD_SUB IS

BEGIN

    fpadd_component : altfp_add_sub
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 7,
        width_exp                       => 11,
        width_man                       => 52,
        optimize                        => OPTIMIZE,
        direction                       => "VARIABLE"
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        datab      => B,
        add_sub    => ADD,
        result     => SUM
    );

END SYN;
