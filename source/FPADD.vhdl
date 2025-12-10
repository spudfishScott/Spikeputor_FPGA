-- FP Add test
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPADD IS
    PORT (
        CLOCK       : IN STD_LOGIC  := '1';

        A     : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
        SUM   : OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
    );
END FPADD;

ARCHITECTURE SYN OF RAM IS

BEGIN

    altsyncram_component : altfp_add_sub
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 11,
    )
    PORT MAP (
        clock      => CLOCK,
        dataa      => A,
        datab      => B,
        result     => SUM
    );

END SYN;
