library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity I2C_tb is
end entity;

architecture tb of I2C_tb is

    -- Resolution function for pull-up behavior
    function resolve_pullup (drivers : std_logic_vector) return std_logic is
    begin
        for i in drivers'range loop
            if drivers(i) /= 'Z' then
                return drivers(i);
            end if;
        end loop;
        return '1'; -- pulled up to '1'
    end function;

    subtype pullup_logic is resolve_pullup std_logic;

    component i2c_master is
        generic (
            INPUT_CLK : INTEGER := 50_000_000;
            BUS_CLK   : INTEGER := 400_000
        );
        port (
            CLK       : IN     STD_LOGIC;
            RESET_N   : IN     STD_LOGIC;
            ENA       : IN     STD_LOGIC;
            ADDR      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0);
            RW        : IN     STD_LOGIC;
            DATA_WR   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0);
            BUSY      : OUT    STD_LOGIC;
            DATA_RD   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0);
            ACK_ERROR : OUT    STD_LOGIC;
            SDA       : INOUT  STD_LOGIC;
            SCL       : INOUT  STD_LOGIC
        );
    end component;

    signal clk       : std_logic := '0';
    signal reset_n   : std_logic := '0';
    signal ena       : std_logic := '0';
    signal addr      : std_logic_vector(6 downto 0) := (others => '0');
    signal rw        : std_logic := '0';
    signal data_wr   : std_logic_vector(7 downto 0) := (others => '0');
    signal busy      : std_logic;
    signal data_rd   : std_logic_vector(7 downto 0);
    signal ack_error : std_logic;
    signal sda       : pullup_logic := '1';
    signal scl       : pullup_logic := '1';

    constant outdata : std_logic_vector(7 downto 0) := "01010101";

    signal provider_rw  : std_logic;

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- Instantiate the DUT
    dut : i2c_master
        port map (
            CLK       => clk,
            RESET_N   => reset_n,
            ENA       => ena,
            ADDR      => addr,
            RW        => rw,
            DATA_WR   => data_wr,
            BUSY      => busy,
            DATA_RD   => data_rd,
            ACK_ERROR => ack_error,
            SDA       => sda,
            SCL       => scl
        );

    -- Stimulus process
    stimulus : process
    begin
        -- Reset
        reset_n <= '0';
        wait for 100 ns;
        reset_n <= '1';
        wait until busy = '0';

        -- Write transaction
        addr <= "0101010";
        rw <= '0';
        data_wr <= "10111101";
        wait until rising_edge(clk);
        ena <= '1';
        wait until busy = '1';
        ena <= '0';
        wait until busy = '0';
        wait for 1 us;

        -- Read transaction
        -- rw <= '1';
        -- wait until rising_edge(clk);
        -- ena <= '1';
        -- wait until busy = '1';
        -- ena <= '0';
        -- wait until busy = '0';
        -- wait for 1 us;

        -- End simulation
        assert false report "Test completed successfully" severity note;
        wait;
    end process;

    -- Slave simulation process
    slave_sim : process

    begin
        loop
            -- Wait for start condition
            wait until scl = '1' and sda = '0';

            -- Address bits (7 bits)
            for i in 0 to 6 loop
                wait until scl = '0';
                wait until scl = '1';
            end loop;

            -- RW bit
            wait until scl = '0';
            wait until scl = '1';
            provider_rw <= sda;

            -- Acknowledge address
            wait until scl = '0';
            sda <= '0';

            if provider_rw = '0' then
                wait until scl = '1';
                wait until scl = '0';
                sda <= 'Z';
                -- Write operation
                for i in 0 to 7 loop
                    wait until scl = '1';
                    wait until scl = '0';
                end loop;
                -- Acknowledge data

                sda <= '0';
                wait until scl = '1';
                wait until scl = '0';
                sda <= 'Z';
            else
                wait until scl = '1';
                -- Read operation
                for i in 0 to 7 loop
                    wait until scl = '0';
                    sda <= outdata(i);
                    wait until scl = '1';
                end loop;
                -- Wait for master acknowledge
                wait until scl = '0';
                wait until scl = '1';
            end if;

            -- Wait for stop condition
            wait until scl = '1' and sda = '1';
        end loop;
    end process;

end architecture;