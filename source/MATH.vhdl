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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        ADD   : IN STD_LOGIC := '1';
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPADD_SUB;

ARCHITECTURE SYN OF FPADD_SUB IS

BEGIN

    fpadd_component : altfp_add_sub
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 7,
        width_exp                       => 8,
        width_man                       => 23,
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPMULT;

ARCHITECTURE SYN OF FPMULT IS

BEGIN

    fpmul_component : altfp_mult
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 5,
        width_exp                       => 8,
        width_man                       => 23
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPDIV;

ARCHITECTURE SYN OF FPDIV IS

BEGIN

    fpdiv_component : altfp_div
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 6,
        width_exp                       => 8,
        width_man                       => 23,
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPSQRT;

ARCHITECTURE SYN OF FPSQRT IS

BEGIN

    fpsqrt_component : altfp_sqrt
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 16,
        width_exp                       => 8,
        width_man                       => 23
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPEXP;

ARCHITECTURE SYN OF FPEXP IS

BEGIN

    fpexp_component : altfp_exp
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 17,
        width_exp                       => 8,
        width_man                       => 23
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPLN;

ARCHITECTURE SYN OF FPLN IS

BEGIN

    fpln_component : altfp_log
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 21,
        width_exp                       => 8,
        width_man                       => 23
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
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPATAN;

ARCHITECTURE SYN OF FPATAN IS

BEGIN

    fpatan_component : altfp_atan
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
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP SIN function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPSIN IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPSIN;

ARCHITECTURE SYN OF FPSIN IS

BEGIN

    fpsin_component : altfp_sincos
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 36,
        operation                       => "SIN",
        width_exp                       => 8,
        width_man                       => 23
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP COS function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPCOS IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END FPCOS;

ARCHITECTURE SYN OF FPCOS IS

BEGIN

    fpcos_component : altfp_sincos
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 35,
        operation                       => "COS",
        width_exp                       => 8,
        width_man                       => 23
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        data       => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Compare function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPCOMPARE IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        B     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(6 downto 0)        -- aeb, aneb, agb, ageb, alb, aleb, unrodered
    );
END FPCOMPARE;

ARCHITECTURE SYN OF FPCOMPARE IS

BEGIN

    fpcompare_component : altfp_compare
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        pipeline                        => 1,
        width_exp                       => 8,
        width_man                       => 23
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        datab      => B,
        aeb        => RES(6),
        agb        => RES(5),
        ageb       => RES(4),
        alb        => RES(3),
        aleb       => RES(2),
        aneb       => RES(1),
        unordered  => RES(0)
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Convert Int to Float function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPCONVERT_IF IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 downto 0)
    );
END FPCONVERT_IF;

ARCHITECTURE SYN OF FPCONVERT_IF IS

BEGIN

    fp_convert_if : altfp_convert
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        width_int                       => 31,
        width_data                      => 31,
        width_exp_output                => 8,
        width_man_output                => 23,
        width_result                    => 31,
        operation                       => "INT2FLOAT"
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- FP Convert Float to Int function
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY FPCONVERT_FI IS
    PORT (
        CLOCK : IN STD_LOGIC := '1';
        EN    : IN STD_LOGIC := '0';
        A     : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        RES   : OUT STD_LOGIC_VECTOR(31 downto 0)
    );
END FPCONVERT_FI;

ARCHITECTURE SYN OF FPCONVERT_FI IS

BEGIN

    fp_convert_FI : altfp_convert
    GENERIC MAP (
        intended_device_family          => "Cyclone III",
        width_int                       => 32,
        width_data                      => 32,
        width_exp_input                 => 8,
        width_man_input                 => 23,
        width_result                    => 32,
        operation                       => "FLOAT2INT"
    )
    PORT MAP (
        clock      => CLOCK,
        clk_en     => EN,
        dataa      => A,
        result     => RES
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- Integer Divide function (16 bit unsigned)

LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.lpm_components.all;

ENTITY INTDIV is
    PORT (
        A       : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
        B       : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
        QUOT    : OUT STD_LOGIC_VECTOR(16 downto 0);
        REMND   : OUT STD_LOGIC_VECTOR(16 downto 0)
    );
END INTDIV;

ARCHITECTURE SYN of INTDIV is

BEGIN
    intdiv: lpm_divide
    GENERIC MAP (
        lpm_widthn                      => 16,
        lpm_widthd                      => 16,
        lpm_nrepresentation             => "UNSIGNED",
        lpm_drepresentation             => "UNSIGNED"
    )
    PORT MAP (
        numer       => A,
        denom       => B,
        quotient    => QUOT,
        remain      => REMND
    );

END SYN;

-------------------------------------------------------------------------------------------------------------------

-- Integer Multiply function (16x16->32 bit)

LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY lpm;
USE lpm.lpm_components.all;

ENTITY INTMULT is
    PORT (
        A       : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
        B       : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
        RES     : OUT STD_LOGIC_VECTOR(16 downto 0)
    );
END INTMULT;

ARCHITECTURE SYN of INTMULT is

BEGIN
    intmult: lpm_mult
    GENERIC MAP (
        lpm_widtha                      => 16,
        lpm_widthb                      => 16,
        lpm_widthp                      => 32,    
        lpm_representation              => "UNSIGNED"
    )
    PORT MAP (
        dataa       => A,
        datab       => B,
        result      => RES
    );

END SYN;
