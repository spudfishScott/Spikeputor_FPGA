-- MATH Wishbone Interface Provider
-- memory registers as follows:
    -- 0xFFE0 - Function Control (write)/Status(read)
        -- WRITE:
            -- 0x0000           A+B
            -- 0x0001           A-B
            -- 0x0002           A*B
            -- 0x0003           A/B
            -- 0x0004           SQRT(A)
            -- 0x0005           e^(A) !!REMOVED!!
            -- 0x0006           LN(A) !!REMOVED!!
            -- 0x0008           SIN(A) - A in radians !!REMOVED!!
            -- 0x000A           COMPARE(A,B) (result is seven bits:[6:0] = aeb/aneb/agb/ageb/alb/aleb/unrodered)
            -- 0x000B           CONVERT A INT TO FLOAT
            -- 0x000C           CONVERT FLOAT A to INT
            -- 0x000D           16 BIT INTEGER A/B - result is quotient, 0xFFE7 is remainder
            -- 0x000E           16 BIT INTEGER A*B - result is 32 bits wide
        -- READ:
            -- 0x8000           BUSY (1 = result computing, 0 = result ready)
    -- 0xFFE1 - Input A High Word (ignored for INTMUL and INTDIV)
    -- 0xFFE2 - Input A Low Word  (use for INTMUL and INTDIV)
    -- 0xFFE3 - Input B High Word (when needed - ignored for INTMUL and INTDIV)
    -- 0xFFE4 - Input B Low Word  (when needed - use for INTMUL and INTDIV)
    -- 0xFFE5 - Output High Word (read only)
    -- 0xFFE6 - Output Low Word (read only)
    -- 0xFFE7 - INTDIV Remainder Output (read only)

    -- Usage:
        -- Store A high in 0xFFE1
        -- Store A low in 0xFFE2
        -- Store B high (if used) in 0xFFE3
        -- Store B low (if used) in 0xFFE4
        -- Store Function in 0xFFE0
        -- Poll 0xFFE0 until 0 (up to 30 cycles and as few as 0, depending on the function)
        -- Read result high from 0xFFE5
        -- Read result low from 0xFFE6
        -- Read INTDIV remainder from 0xFFE7

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity MATH_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic                          -- write enable input - when high, master is writing, when low, master is reading
    );
end MATH_WSH_P;

architecture rtl of MATH_WSH_P is

    -- internal signals
    constant z25         : std_logic_vector(24 downto 0) := (others => '0');    -- 25 zero bits
    constant z16         : std_logic_vector(15 downto 0) := (others => '0');    -- 16 zero bits

    -- individual function results
    signal addsub_result : std_logic_vector(31 downto 0) := (others => '0');
    signal mult_result   : std_logic_vector(31 downto 0) := (others => '0');
    signal div_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal sqrt_result   : std_logic_vector(31 downto 0) := (others => '0');
    signal cmp_result    : std_logic_vector(6 downto 0)  := (others => '0');
    signal i2f_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal f2i_result    : std_logic_vector(31 downto 0) := (others => '0');
    signal idiv_quot     : std_logic_vector(15 downto 0) := (others => '0');
    signal idiv_rem      : std_logic_vector(15 downto 0) := (others => '0');
    signal imult_result  : std_logic_vector(31 downto 0) := (others => '0');

    signal fn_select     : std_logic_vector(3 downto 0)  := (others => '0');
    signal enabled       : std_logic_vector(15 downto 0) := (others => '0');    -- one hot enable of each math function

    signal ack           : std_logic := '0';                                    -- wishbone ack signal
    signal busy          : integer range 0 to 31 := 0;                          -- non-zero if calculating, reset for each new command (future - add multiple results for pipelining)
    signal busy_out      : std_logic_vector(15 downto 0) := (others => '0');

    signal input_a       : std_logic_vector(31 downto 0) := (others => '0');    -- input A register
    signal input_b       : std_logic_vector(31 downto 0) := (others => '0');    -- input B register
    signal result        : std_logic_vector(31 downto 0) := (others => '0');    -- result register

begin

    with (fn_select) select                     -- select output to map to result
        result <=
            addsub_result           when "0000"|"0001",
            mult_result             when "0010",
            div_result              when "0011",
            sqrt_result             when "0100",
            z25 & cmp_result        when "1010",        -- CMP result is only 7 bits
            i2f_result              when "1011",
            f2i_result              when "1100",
            z16 & idiv_quot         when "1101",        -- 16 bits output, remainder output is separate
            imult_result            when "1110",        -- imult is 16x16 bit inputs = 32 bit output
            (others => '0')         when others;

    with (fn_select) select                     -- select math function to enable
        enabled <=
            "0000000000000001" when "0000",          -- ADD
            "0000000000000010" when "0001",          -- SUB
            "0000000000000100" when "0010",          -- MULT
            "0000000000001000" when "0011",          -- DIV
            "0000000000010000" when "0100",          -- SQRT
            "0000010000000000" when "1010",          -- CMP
            "0000100000000000" when "1011",          -- INT to FLOAT
            "0001000000000000" when "1100",          -- FLOAT to INT
            "0010000000000000" when "1101",          -- Integer Divide (16 bit / 16 bit = 16 bit quotient, 16 bit remainder)
            "0100000000000000" when "1110",          -- Integer Multiply (16 bit * 16 bit = 32 bit product)
            "0000000000000000" when others;

 with (WBS_ADDR_I(3 downto 0)) select           -- select output based on address of register to read
        WBS_DATA_O <=
            busy_out                when "0000",     -- 0xFFE0 read is current calculation status
            input_a(31 downto 16)   when "0001",     -- 0xFFE1 read is Input A High Word
            input_a(15 downto 0)    when "0010",     -- 0xFFE2 read is Input A Low Word
            input_b(31 downto 16)   when "0011",     -- 0xFFE3 read is Input B High Word
            input_b(15 downto 0)    when "0100",     -- 0xFFE4 read is Input B Low Word
            result(31 downto 16)    when "0101",     -- 0xFFE5 read is Result High Word
            result(15 downto 0)     when "0110",     -- 0xFFE6 read is Result Low Word
            idiv_rem                when "0111",     -- 0xFFE7 read is Integer Division Remainder
            z16                     when others;     -- otherwise 0

    busy_out    <= x"0000" when busy = 0 else std_logic_vector(to_unsigned(busy,16));      -- if busy timer is non-zero, output number of cycles remaining as 16-bit value

    WBS_ACK_O   <= ack AND WBS_CYC_I AND WBS_STB_I;         -- ack out is internal ack if CYC and STB are asserted, else 0

    process(CLK) is     -- wishbone transaction process
    begin
        if rising_edge(CLK) then
            if busy /= 0 then                 -- busy counter countdown
                busy <= busy - 1;
            end if;

            if (WBS_CYC_I = '1' AND WBS_STB_I = '1' AND ack = '0') then         -- wait for wishbone transaction to start
                ack <= '1';                                                     -- acknowledge on next cycle
                if (WBS_WE_I = '1') then                                        -- write: take action based on which register being written
                    case WBS_ADDR_I(3 downto 0) is                              -- get bottom nybble of address
                        when "0000" =>      -- 0xFFE0 = function control
                            fn_select <= WBS_DATA_I(3 downto 0);                -- latch in function select to pipeline new calculation - resets the busy counter
                            case WBS_DATA_I(3 downto 0) is                      -- set up busy counter based on selected command
                                when "0000"|"0001" =>       -- ADD/SUB = 7 cycles
                                    busy <= 7;
                                when "0010" =>              -- MULT = 5 cycles
                                    busy <= 5;
                                when "0011" =>              -- DIV = 10 cycles
                                    busy <= 10;
                                when "0100" =>              -- SQRT = 16 cycles
                                    busy <= 16;
                                when "1010" =>              -- COMPARE = 1 cycle
                                    busy <= 1;
                                when "1011" =>              -- INT to FLOAT = 6 cycles
                                    busy <= 6;
                                when "1100" =>              -- FLOAT to INT = 6 cycles
                                    busy <= 6;
                                when "1101" =>              -- INT DIV = 3 cycles
                                    busy <= 3;
                                when "1110" =>              -- INT MULT = available immediately
                                    busy <= 0;
                                when others =>
                                    busy <= 0;              -- undefined functions produce 0 immediately
                            end case;
                        -- Only allow writes to inputs if not busy or result will not make sense (until/if data pipelining is implemented)
                        when "0001" =>      -- 0xFFE1 = Input A High
                            if busy = 0 then
                                input_a(31 downto 16) <= WBS_DATA_I;            -- latch Input A High word
                            end if;
                        when "0010" =>      -- 0xFFE2 - Input A Low
                            if busy = 0 then
                                input_a(15 downto 0) <= WBS_DATA_I;             -- latch Input A Low word
                            end if;
                        when "0011" =>      -- 0xFFE3 - Input B High
                            if busy = 0 then
                                input_b(31 downto 16) <= WBS_DATA_I;            -- latch Input B High word
                            end if;
                        when "0100" =>      -- 0xFFE4 - Input B Low
                            if busy = 0 then
                                input_b(15 downto 0) <= WBS_DATA_I;             -- latch Input B Low word
                            end if;
                        when others =>                                          -- everything else is read-only
                            null;
                    end case;
                end if;

            elsif (WBS_CYC_I = '0' OR WBS_STB_I = '0') then     -- wait for wishbone transaction to end
                ack <= '0';                 -- reset internal ack signal when that happens
            end if;
        end if;
    end process;

    -- FP ADD_SUB instance - answer available in 7 cycles
    ADDSUB : entity work.FPADD_SUB port map (
        CLOCK   => CLK,
        EN      => enabled(0) OR enabled(1),
        A       => input_a,
        B       => input_b,
        ADD     => enabled(0),
        RES     => addsub_result
    );

    -- FP MULT instance -- answer available in 5 cycles
    MULT: entity work.FPMULT port map (
        CLOCK   => CLK,
        EN      => enabled(2),
        A       => input_a,
        B       => input_b,
        RES     => mult_result
    );

    -- FP DIV instance -- answer available in 10 cycles
    DIV: entity work.FPDIV port map (
        CLOCK   => CLK,
        EN      => enabled(3),
        A       => input_a,
        B       => input_b,
        RES     => div_result
    );

    -- FP SQRT instance -- answer available in 30 cycles
    SQRT: entity work.FPSQRT port map (
        CLOCK   => CLK,
        EN      => enabled(4),
        A       => input_a,
        RES     => sqrt_result
    );

    -- FP Compare instance -- answer available in 1 cycle - 7 bits of output (aeb/aneb/agb/ageb/alb/aleb/unrodered)
    CMP: entity work.FPCOMPARE port map (
        CLOCK   => CLK,
        EN      => enabled(10),
        A       => input_a,
        B       => input_b,
        RES     => cmp_result
    );

    -- Convert INT to FLOAT - answer in 6 cycles
    I2F: entity work.FPCONVERT_IF port map (
        CLOCK   => CLK,
        EN      => enabled(11),
        A       => input_a,
        RES     => i2f_result
    );

     -- Convert FLOAT to INT - answer in 6 cycles
    F2I: entity work.FPCONVERT_FI port map (
        CLOCK   => CLK,
        EN      => enabled(12),
        A       => input_a,
        RES     => f2i_result
    );

    -- Integer division - 16 bit numerator and 16 bit denominator - answer in 3 cycles as 16 bit quotient and 16 bit remainder
    IDIV: entity work.INTDIV port map (
	   CLOCK     => CLK,
		  EN      => enabled(13),
        A       => input_a(15 downto 0),
        B       => input_b(15 downto 0),
        QUOT    => idiv_quot,
        REMND   => idiv_rem
    );

    -- Integer multiplication - answer immediately
    IMULT: entity work.INTMULT port map (
        A       => input_a(15 downto 0),
        B       => input_b(15 downto 0),
        RES     => imult_result
    );

end rtl;