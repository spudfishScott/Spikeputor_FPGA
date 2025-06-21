library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity Flash_tb is
end entity;

architecture tb of Flash_tb is

    -- Signals for DUT
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal erase       : std_logic_vector(1 downto 0) := "00";
    signal rd          : std_logic := '0';
    signal wr          : std_logic := '0';
    signal addr        : std_logic_vector(21 downto 0) := (others => '0');
    signal din         : std_logic_vector(15 downto 0) := (others => '0');
    signal dout        : std_logic_vector(15 downto 0);
    signal ready       : std_logic;
    signal valid       : std_logic;
    signal err         : std_logic;
    signal wp_n        : std_logic;
    signal byte_n      : std_logic;
    signal rst_n       : std_logic;
    signal ce_n        : std_logic;
    signal oe_n        : std_logic;
    signal we_n        : std_logic;
    signal by_n        : std_logic := '0'; -- Simulate chip ready
    signal a_o         : std_logic_vector(21 downto 0);
    signal dq_io       : std_logic_vector(15 downto 0);

    -- signals for DQ simulation
    signal dq_timer      : integer := 0;
    signal last_oe_n        : std_logic := '1';
    signal last_ce_n        : std_logic := '1';
    signal dq_drive_value   : std_logic_vector(15 downto 0) := (others => 'Z');



    -- Clock generation
    constant clk_period : time := 20 ns;
begin

    -- Instantiate DUT
    DUT: entity work.FLASH_RAM
        port map (
            CLK_IN      => clk,
            RST_IN      => rst,
            ERASE_IN    => erase,
            RD_IN       => rd,
            WR_IN       => wr,
            ADDR_IN     => addr,
            DATA_IN     => din,
            DATA_OUT    => dout,
           READY_OUT    => ready,
            VALID_OUT   => valid,
            ERROR_OUT   => err,
            WP_n        => wp_n,
            BYTE_n      => byte_n,
            RST_n       => rst_n,
            CE_n        => ce_n,
            OE_n        => oe_n,
            WE_n        => we_n,
            BY_n        => by_n,
            A           => a_o,
            DQ          => dq_io
        );

    -- Clock process
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus process
    stim_proc: process
    begin
        -- Reset
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for clk_period;
        by_n <= '1';  -- Simulate chip ready
        
        -- Write operation - successful
        addr <= "0000000000000000000001";  -- Address 1
        din  <= x"eaea";
        wr   <= '1';
        wait for clk_period;
        by_n <= '0';  -- Simulate chip not ready
        wr   <= '0';
        wait for 400 ns;
        by_n <= '1';  -- Simulate chip ready
        wait until valid = '1'; -- wait for write to complete
        wait for 100 ns;

        -- Read operation 1
        addr <= "0000000000000000000011";  -- Address 1
        rd   <= '1';
        wait for 200 ns;
        rd   <= '0';
        wait for 500 ns;

        -- Read operation 2
        addr <= "0000000000000000000001";  -- Address 1
        rd   <= '1';
        wait for 200 ns;
        rd   <= '0';
        wait for 500 ns;

        -- Chip erase operation
        erase <= "01";
        wait for clk_period;
        by_n <= '0';  -- Simulate chip not ready
        erase <= "00";
        wait for 500 ns;
        by_n <= '1';  -- Simulate chip ready
        wait for 500 ns;

        -- Sector erase operation
        erase <= "10";
        addr  <= "0000000000000000010000"; -- Address 16
        wait for clk_period;
        by_n <= '0';  -- Simulate chip not ready
        erase <= "00";
        wait for 500 ns;
        by_n <= '1';  -- Simulate chip ready
        wait for 500 ns;

        -- Write operation - unsuccessful
        addr <= "0000000000000000000010";  -- Address 2
        din  <= x"5678";
        wr   <= '1';
        wait for clk_period;
        by_n <= '0';  -- Simulate chip not ready
        wr   <= '0';
        wait for 500 ns; -- entity should still be busy

        -- End simulation
        wait;
    end process;

--    Simulate DQ as bidirectional with 80 ns lag between OE/CE and valid output
dq_drive_proc: process(clk)
    begin
        if rising_edge(clk) then
            -- Detect when output should be enabled
            if ce_n = '0' and oe_n = '0' then
                -- Start delay if OE/CE changed to 0
                if (oe_n /= last_oe_n) or (ce_n /= last_ce_n) then
                    dq_timer   <= 2; -- 4 cycles x 20ns = 80ns (close to 70ns) (one has already happened to get here)
                elsif dq_timer > 1 then -- otherwise if timer started and nOE/nCN still 0, then decrement timer
                    dq_timer <= dq_timer - 1;
                end if;
            else -- if nOE/nCE are no longer 0, then reset timer and set DQ to high impedance
                dq_timer   <= 0;
                dq_drive_value <= (others => 'U'); -- Set DQ to undefined state
            end if;

            -- Drive value after delay
            if dq_timer = 1 then
                if a_o = "0000000000000000000001" then
                    dq_drive_value <= x"1234";
                else
                    dq_drive_value <= x"BEEF";
                end if;
            end if;

            -- Update last values
            last_oe_n <= oe_n;
            last_ce_n <= ce_n;
        end if;
    end process;

    dq_io <= dq_drive_value when oe_n = '0' else (others => 'Z');



end architecture;