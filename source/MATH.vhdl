-- FP Addition/Subtraction
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
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Multiplication
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPMULT IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPMULT;

ARCHITECTURE SYN OF FPMULT IS

BEGIN

    fpmul_component : altfp_mult
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 5,
        width_exp                       => 11,
        width_man                       => 52
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        datab      => B,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Division
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

-------------------------------------------------------------------------------------------------------------------

-- FP Square Root
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPSQRT IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPSQRT;

ARCHITECTURE SYN OF FPSQRT IS

BEGIN

    fpsqrt_component : altfp_sqrt
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 57,
        width_exp                       => 11,
        width_man                       => 52
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Exponential function (x^y = exp(y*ln(x)))
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPEXP IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPEXP;

ARCHITECTURE SYN OF FPEXP IS

BEGIN

    fpexp_component : altfp_exp
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 25,
        width_exp                       => 11,
        width_man                       => 52
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Natural Log function (x^y = exp(y*ln(x)))
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPLN IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (63 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (63 DOWNTO 0)
    );
END FPLN;

ARCHITECTURE SYN OF FPLN IS

BEGIN

    fpln_component : altfp_log
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 34,
        width_exp                       => 11,
        width_man                       => 52
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP ATAN function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPATAN IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
    );
END FPATAN;

ARCHITECTURE SYN OF FPATAN IS

    -- signal short_result : STD_LOGIC_VECTOR(31 DOWNTO 0) := (others => '0');
    -- signal pad          : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";

BEGIN
    -- -- put single precision number into double precision footprint
    -- pad <= "000" when short_result(30) = '1' else "111";
    -- RES <= short_result(31) & short_result(30) & pad & short_result(29 downto 23) & short_result(22 downto 0) & x"0000" when short_result(30);

    fpln_component : altfp_atan
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 34,
        width_exp                       => 8,
        width_man                       => 23
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES --short_result
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------
