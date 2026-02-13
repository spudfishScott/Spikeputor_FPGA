library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_tb is
end SDRAM_tb;

architecture sim of SDRAM_tb is
    -- Clock and reset
    signal CLK    : std_logic := '0';
    signal RST_N  : std_logic := '0';

    -- Controller interface
    signal REQ    : std_logic := '0';
    signal WE     : std_logic := '0';
    signal ADDR   : std_logic_vector(21 downto 0) := (others => '0');
    signal WDATA  : std_logic_vector(15 downto 0) := (others => '0');

    signal BUSY   : std_logic;
    signal RDATA  : std_logic_vector(15 downto 0);
    signal VALID : std_logic;

    -- SDRAM pins (connect to controller under test)
    signal DRAM_CLK   : std_logic;
    signal DRAM_CKE   : std_logic;
    signal DRAM_CS_N  : std_logic;
    signal DRAM_RAS_N : std_logic;
    signal DRAM_CAS_N : std_logic;
    signal DRAM_WE_N  : std_logic;
    signal DRAM_BA_0  : std_logic;
    signal DRAM_BA_1  : std_logic;
    signal DRAM_ADDR  : std_logic_vector(11 downto 0);

    -- shared tri-state data bus for DRAM
    signal DRAM_DQ    : std_logic_vector(15 downto 0) := (others => 'Z');

    -- simple memory model (small) using modulo addressing
    type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- DRAM model internal registers
    signal act_bank   : std_logic_vector(1 downto 0) := (others => '0');
    signal act_row    : std_logic_vector(11 downto 0) := (others => '0');
    signal read_pending : integer := 0;
    signal read_data_out : std_logic_vector(15 downto 0) := (others => '0');

    constant SYS_PERIOD_NS : time := 20 ns; -- 50 MHz
    constant CAS_LATENCY_CYC : integer := 2; -- should match controller constant

begin
    -- Instantiate DUT
    DUT : entity work.SDRAM
        port map (
            CLK      => CLK,
            RST_N    => RST_N,
            REQ      => REQ,
            WE       => WE,
            ADDR     => ADDR,
            WDATA    => WDATA,

            BUSY     => BUSY,
            RDATA    => RDATA,
            VALID    => VALID,

            DRAM_CLK  => DRAM_CLK,
            DRAM_CKE  => DRAM_CKE,
            DRAM_CS_N => DRAM_CS_N,
            DRAM_RAS_N=> DRAM_RAS_N,
            DRAM_CAS_N=> DRAM_CAS_N,
            DRAM_WE_N => DRAM_WE_N,
            DRAM_BA_0 => DRAM_BA_0,
            DRAM_BA_1 => DRAM_BA_1,
            DRAM_ADDR => DRAM_ADDR,
            DRAM_DQ   => DRAM_DQ,
            DRAM_UDQM => open,
            DRAM_LDQM => open
        );

    -- Drive system clock
    clk_proc : process
    begin
        while now < 200 us loop
            CLK <= '0';
            wait for SYS_PERIOD_NS/2;
            CLK <= '1';
            wait for SYS_PERIOD_NS/2;
        end loop;
        wait;
    end process;

    -- Tie DRAM_CLK to system clock for visibility
    DRAM_CLK <= CLK;

    -- Simple SDRAM device model: react to commands driven on DRAM control pins
    dram_model : process(CLK)
        variable col : std_logic_vector(7 downto 0);
        variable bankrowcol_idx : integer;
        variable addr_vec : std_logic_vector(21 downto 0);
        variable addr_vec2 : std_logic_vector(21 downto 0);
        variable next_read_pending : integer;
    begin
        if rising_edge(CLK) then
            -- Calculate what read_pending will be next cycle (after decrement)
            if read_pending > 0 then
                next_read_pending := read_pending - 1;
            else
                next_read_pending := 0;
            end if;

            -- Tri-state DRAM_DQ: drive when next_read_pending will be 1 (i.e., one more cycle before ready)
            if next_read_pending = 1 and read_pending > 0 then
                DRAM_DQ <= read_data_out;
            else
   --             DRAM_DQ <= (others => 'Z');
            end if;

            -- Decrement pending read timer
            if read_pending > 0 then
                read_pending <= read_pending - 1;
            end if;

            -- Sample commands: active when CS_N = '0'
            if DRAM_CS_N = '0' then
                -- ACTIVATE: RAS=0, CAS=1, WE=1
                if DRAM_RAS_N = '0' and DRAM_CAS_N = '1' and DRAM_WE_N = '1' then
                    act_bank <= DRAM_BA_1 & DRAM_BA_0;
                    act_row  <= DRAM_ADDR(11 downto 0);
                end if;

                -- READ: RAS=1, CAS=0, WE=1
                if DRAM_RAS_N = '1' and DRAM_CAS_N = '0' and DRAM_WE_N = '1' then
                    -- capture column and schedule data drive after CAS latency
                    col := DRAM_ADDR(7 downto 0);
                    -- build an address vector locally to avoid ambiguous concatenation overloads
                    addr_vec := act_bank & act_row(11 downto 0) & col;
                    bankrowcol_idx := to_integer(unsigned(addr_vec)) mod mem'length;
                    read_data_out <= mem(bankrowcol_idx);  -- fetch from memory
                    read_pending <= CAS_LATENCY_CYC;       -- schedule for presentation after CAS cycles
                end if;

                -- WRITE: RAS=1, CAS=0, WE=0 -> data is driven by controller onto DRAM_DQ
                if DRAM_RAS_N = '1' and DRAM_CAS_N = '0' and DRAM_WE_N = '0' then
                    col := DRAM_ADDR(7 downto 0);
                    -- build address vector locally to avoid ambiguous concatenation overloads
                    addr_vec2 := act_bank & act_row(11 downto 0) & col;
                    bankrowcol_idx := to_integer(unsigned(addr_vec2)) mod mem'length;
                    -- read the data driven on DRAM_DQ (controller must drive it)
                    mem(bankrowcol_idx) <= DRAM_DQ;
                end if;

            end if;
        end if;
    end process;

    -- Test stimulus
    stim_proc : process
    begin
        -- -- reset
        -- RST_N <= '0';
        -- REQ <= '0'; WE <= '0';
        -- wait for 200 ns;
        -- RST_N <= '1';

        -- wait until controller indicates ready
        wait until BUSY = '0';
        wait for 100 ns;

        -- First WRITE transaction at address 0x000100
        -- Setup phase: set address/data/control one cycle before REQ (proper Wishbone timing)
        ADDR <= std_logic_vector(to_unsigned(16#000100#, 22));
        WDATA <= x"ABCD";
        WE <= '1';
        wait for SYS_PERIOD_NS;  -- allow setup time
        
        -- Assert REQ to initiate transaction
        REQ <= '1';
        wait for SYS_PERIOD_NS;  -- pulse REQ for one cycle
        REQ <= '0';
        wait until VALID = '1'; -- wait for write operation to complete
        wait for 100 ns;
        
        report "First write complete";

        -- Second WRITE transaction at address 0x000200 (different address)
        -- Setup phase: set address/data/control one cycle before REQ
        ADDR <= std_logic_vector(to_unsigned(16#000200#, 22));
        WDATA <= x"1234";
        WE <= '1';
        wait for SYS_PERIOD_NS;  -- allow setup time
        
        -- Assert REQ to initiate transaction
        REQ <= '1';
        wait for SYS_PERIOD_NS;  -- pulse REQ for one cycle
        REQ <= '0';
        wait until VALID = '1'; -- wait for write operation to complete
        wait for 100 ns;
        
        report "Second write complete";

        -- Read transaction from first address (0x000100)
        -- Setup phase: set address/control one cycle before REQ (proper Wishbone timing)
        ADDR <= std_logic_vector(to_unsigned(16#000100#, 22));
        WE <= '0';
        wait for SYS_PERIOD_NS;  -- allow setup time
        
        -- Assert REQ to initiate transaction
        REQ <= '1';
        wait for SYS_PERIOD_NS;  -- pulse REQ for one cycle
        REQ <= '0';

        -- wait for valid
        wait until VALID = '1';
        report "Read data from 0x000100 (should be 0xABCD, decimal) = " & integer'image(to_integer(unsigned(RDATA)));
        wait for 100 ns;

        -- Read transaction from second address (0x000200)
        -- Setup phase: set address/control one cycle before REQ
        ADDR <= std_logic_vector(to_unsigned(16#000200#, 22));
        WE <= '0';
        wait for SYS_PERIOD_NS;  -- allow setup time
        
        -- Assert REQ to initiate transaction
        REQ <= '1';
        wait for SYS_PERIOD_NS;  -- pulse REQ for one cycle
        REQ <= '0';

        -- wait for valid
        wait until VALID = '1';
        report "Read data from 0x000200 (should be 0x1234, decimal) = " & integer'image(to_integer(unsigned(RDATA)));

        wait for 1 us;
        report "End of test.";
        wait;
    end process;

end architecture;