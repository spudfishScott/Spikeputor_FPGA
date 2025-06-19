library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity Flash_tb is
end entity;

architecture tb of Flash_tb is

    -- Component declaration
    component FLASH_RAM
        generic (MAIN_CLK_NS : integer := 20);
        port (
            -- controller signals
            CLK_IN      : in  std_logic;
            RST_IN      : in  std_logic;
            ERASE_IN    : in  std_logic_vector(1 downto 0);
            RD_IN       : in  std_logic;
            WR_IN       : in  std_logic; 
            ADDR_IN     : in  std_logic_vector(21 downto 0);
            DATA_IN     : in  std_logic_vector(15 downto 0);
            DATA_OUT    : out std_logic_vector(15 downto 0);
            BUSY_OUT    : out std_logic;
            VALID_OUT   : out std_logic;
            ERROR_OUT   : out std_logic;

            -- flash chip signals
            WP_n        : out std_logic;
            BYTE_n      : out std_logic;
            RST_n       : out std_logic;
            CE_n        : out std_logic;
            OE_n        : out std_logic;
            WE_n        : out std_logic;
            BY_n        : in  std_logic;
            A           : out std_logic_vector(21 downto 0);
            DQ          : inout std_logic_vector(15 downto 0)
        );
    end component;

    -- Signals for DUT
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal erase       : std_logic_vector(1 downto 0) := "00";
    signal rd          : std_logic := '0';
    signal wr          : std_logic := '0';
    signal addr        : std_logic_vector(21 downto 0) := (others => '0');
    signal din         : std_logic_vector(15 downto 0) := (others => '0');
    signal dout        : std_logic_vector(15 downto 0);
    signal busy        : std_logic;
    signal valid       : std_logic;
    signal err         : std_logic;
    signal wp_n        : std_logic;
    signal byte_n      : std_logic;
    signal rst_n       : std_logic;
    signal ce_n        : std_logic;
    signal oe_n        : std_logic;
    signal we_n        : std_logic;
    signal by_n        : std_logic := '0'; -- Simulate chip ready
    signal a           : std_logic_vector(20 downto 0);
    signal dq          : std_logic_vector(15 downto 0);

    -- Clock generation
    constant clk_period : time := 20 ns;
begin

    -- Instantiate DUT
    DUT: FLASH_RAM
        port map (
            CLK_IN      => clk,
            RST_IN      => rst,
            ERASE_IN    => erase,
            RD_IN       => rd,
            WR_IN       => wr,
            ADDR_IN     => addr,
            DATA_IN     => din,
            DATA_OUT    => dout,
            BUSY_OUT    => busy,
            VALID_OUT   => valid,
            ERROR_OUT   => err,
            WP_n        => wp_n,
            BYTE_n      => byte_n,
            RST_n       => rst_n,
            CE_n        => ce_n,
            OE_n        => oe_n,
            WE_n        => we_n,
            BY_n        => by_n,
            A           => a,
            DQ          => dq
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

        -- Write operation - successful
        addr <= "0000000000000000000001";  -- Address 1
        din  <= x"1234";
        wr   <= '1';
        wait for clk_period;
        by_n <= '1';  -- Simulate chip not ready
        wr   <= '0';
        wait for 400 ns;
        by_n <= '0';  -- Simulate chip ready
        wait until valid = '1'; -- wait for write to complete
        wait for 100 ns;

        -- Read operation
        addr <= "0000000000000000000011";  -- Address 1
        rd   <= '1';
        wait for 100 ns;
        rd   <= '0';
        wait for 500 ns;

        -- Chip erase operation
        erase <= "01";
        wait for clk_period;
        erase <= "00";
        wait for 500 ns;
        by_n <= '0';  -- Simulate chip ready
        wait for 500 ns;

        -- Sector erase operation
        erase <= "10";
        addr  <= "0000000000000000010000"; -- Address 16
        wait for clk_period;
        erase <= "00";
        wait for 500 ns;
        by_n <= '0';  -- Simulate chip ready
        wait for 500 ns;

        -- Write operation - unsuccessful
        addr <= "0000000000000000000010";  -- Address 2
        din  <= x"5678";
        wr   <= '1';
        wait for clk_period;
        by_n <= '1';  -- Simulate chip not ready
        wr   <= '0';
        wait for 500 ns; -- entity should still be busy

        -- End simulation
        wait;
    end process;

    -- Simulate DQ as bidirectional (simple model)
    dq <= (others => 'Z') when oe_n = '1' else x"BEEF"; -- Simulate read data

end architecture;