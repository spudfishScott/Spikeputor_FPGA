-- FP Add test
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPDIV IS
    GENERIC ( OPTIMIZE : String := "AREA" );
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPDIV;

ARCHITECTURE SYN OF FPDIV IS

BEGIN

    fpdiv_component : altfp_div
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 10,
        width_exp                       => 11,
        width_man                       => 52,
        optimize                        => OPTIMIZE
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        datab      => B,
        result     => RES
    );

END SYN;
