library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_ascii_tb is
end entity;

architecture sim of ps2_ascii_tb is
    -- UUT ports
    signal clk        : std_logic := '0';
    signal ps2_clk    : std_logic := '1';
    signal ps2_data   : std_logic := '1';
    signal ascii_new  : std_logic;
    signal ascii_code : std_logic_vector(6 downto 0);

    -- timing
    constant SYS_CLK_PERIOD : time := 20 ns;      -- 50 MHz
    constant PS2_HALF_BIT   : time := 30 us;      -- ~16.7 kHz bit clock (60 us period)

    -- helpful scan codes (Set 2)
    constant SC_O      : std_logic_vector(7 downto 0) := x"44";
    constant SC_K      : std_logic_vector(7 downto 0) := x"42";
    constant SC_C      : std_logic_vector(7 downto 0) := x"21";
    constant SC_9      : std_logic_vector(7 downto 0) := x"46";
    constant SC_5      : std_logic_vector(7 downto 0) := x"2E";
    constant SC_CAPS   : std_logic_vector(7 downto 0) := x"58"; -- Caps Lock
    constant SC_LSHIFT : std_logic_vector(7 downto 0) := x"12";
    constant SC_RSHIFT : std_logic_vector(7 downto 0) := x"59";
    constant SC_CTRL   : std_logic_vector(7 downto 0) := x"14";
    constant SC_BREAK  : std_logic_vector(7 downto 0) := x"F0";
    constant SC_EXT    : std_logic_vector(7 downto 0) := x"E0"; -- extended code prefix

    ------------------------------------------------------------------------
    -- PS/2 helper functions/procedures (DECLARATIVE REGION)
    ------------------------------------------------------------------------
    -- compute odd parity for an 8-bit vector
    function odd_parity(v: std_logic_vector(7 downto 0)) return std_logic is
        variable ones : integer := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then ones := ones + 1; end if;
        end loop;
        if (ones mod 2) = 0 then return '1'; else return '0'; end if;
    end function;

    -- drive one PS/2 bit (toggle sclk low/high with data stable)
    procedure ps2_drive_bit(signal sclk: out std_logic;
                            signal sdat: out std_logic;
                            b: in std_logic) is
    begin
        sdat <= b;
        sclk <= '0';  wait for PS2_HALF_BIT;
        sclk <= '1';  wait for PS2_HALF_BIT;
    end procedure;

    -- send one PS/2 byte (start, 8 data LSB-first, parity (odd), stop)
    procedure ps2_send_byte(signal sclk: out std_logic;
                            signal sdat: out std_logic;
                            code: in std_logic_vector(7 downto 0)) is
        variable p : std_logic;
    begin
        wait for 100 us; -- inter-byte idle
        p := odd_parity(code);

        -- start bit (0)
        ps2_drive_bit(sclk => sclk, sdat => sdat, b => '0');

        -- data bits LSB-first
        for i in 0 to 7 loop
            ps2_drive_bit(sclk => sclk, sdat => sdat, b => code(i));
        end loop;

        -- parity (odd)
        ps2_drive_bit(sclk => sclk, sdat => sdat, b => p);

        -- stop bit (1)
        ps2_drive_bit(sclk => sclk, sdat => sdat, b => '1');

        -- release bus back to idle
        sdat <= '1';
        sclk <= '1';
    end procedure;

    -- key make (press)
    procedure key_make(signal sclk: out std_logic;
                       signal sdat: out std_logic;
                       sc: in std_logic_vector(7 downto 0)) is
    begin
        ps2_send_byte(sclk => sclk, sdat => sdat, code => sc);
    end procedure;

    -- key break (release) => F0, then sc
    procedure key_break(signal sclk: out std_logic;
                        signal sdat: out std_logic;
                        sc: in std_logic_vector(7 downto 0)) is
    begin
        ps2_send_byte(sclk => sclk, sdat => sdat, code => SC_BREAK);
        ps2_send_byte(sclk => sclk, sdat => sdat, code => sc);
    end procedure;

    -- type (press then release)
    procedure key_type(signal sclk: out std_logic;
                       signal sdat: out std_logic;
                       sc: in std_logic_vector(7 downto 0)) is
    begin
        key_make(sclk => sclk, sdat => sdat, sc => sc);
        wait for 1 ms;
        key_break(sclk => sclk, sdat => sdat, sc => sc);
    end procedure;

begin
    -- UUT
    uut: entity work.PS2_ASCII
        generic map (
            clk_freq => 50_000_000,
            ps2_debounce_counter_size => 8
        )
        port map (
            clk        => clk,
            ps2_clk    => ps2_clk,
            ps2_data   => ps2_data,
            ascii_new  => ascii_new,
            ascii_code => ascii_code
        );

    -- 50 MHz clock
    clk <= not clk after SYS_CLK_PERIOD/2;

    -- Monitor: print ASCII when produced (decimal code for portability)
    monitor: process(ascii_new)
    begin
        if rising_edge(ascii_new) then
            -- if ascii_new = '1' then
                report "ASCII new (dec): " &
                       integer'image(to_integer(unsigned(ascii_code)));
            -- end if;
        end if;
    end process;

    -- Stimulus
    stim: process
    begin
        -- settle
        ps2_clk  <= '1';
        ps2_data <= '1';
        wait for 1 ms;

        -- 1) 'o'
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_O);
        wait for 2 ms;

        -- 2) Shift + k
        key_make(sclk => ps2_clk, sdat => ps2_data, sc => SC_LSHIFT);
        wait for 1 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_K);
        wait for 1 ms;
        key_break(sclk => ps2_clk, sdat => ps2_data, sc => SC_LSHIFT);
        wait for 2 ms;

        -- 3) Control + c
        key_make(sclk => ps2_clk, sdat => ps2_data, sc => SC_CTRL);
        wait for 1 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_C);
        wait for 1 ms;
        key_break(sclk => ps2_clk, sdat => ps2_data, sc => SC_CTRL);
        wait for 2 ms;

        -- 4) '9'
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_9);
        wait for 2 ms;

        -- 5) Shift + '5'  -> '%'
        key_make(sclk => ps2_clk, sdat => ps2_data, sc => SC_RSHIFT);
        wait for 1 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_5);
        wait for 1 ms;
        key_break(sclk => ps2_clk, sdat => ps2_data, sc => SC_RSHIFT);
        wait for 2 ms;

        -- 6) Control + c with right control key
        key_make(sclk => ps2_clk, sdat => ps2_data, sc => SC_EXT);
        ps2_send_byte(sclk => ps2_clk, sdat => ps2_data, code => SC_CTRL);
        wait for 1 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_C);
        wait for 1 ms;
        key_break(sclk => ps2_clk, sdat => ps2_data, sc => SC_EXT);
        ps2_send_byte(sclk => ps2_clk, sdat => ps2_data, code => SC_CTRL);
        wait for 2 ms;

        -- 7) Caps Lock + k
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_CAPS);
        wait for 1 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_K);
        wait for 2 ms;

        -- 8) 'o' (caps lock still on)
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_O);
        wait for 2 ms;
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_CAPS);
        wait for 2 ms;

        -- 9) 'c' with caps lock off
        key_type(sclk => ps2_clk, sdat => ps2_data, sc => SC_C);

        wait for 10 ms;
        report "Simulation done." severity note;
        wait;
    end process;

end architecture;
