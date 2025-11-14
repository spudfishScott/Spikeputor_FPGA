library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_WSH_P_tb is
end SDRAM_WSH_P_tb;

architecture sim of SDRAM_WSH_P_tb is
    -- Clock and reset
    signal CLK    : std_logic := '0';
    signal RST_I  : std_logic := '0';

    -- Wishbone Master signals (from CPU)
    signal WBS_CYC_O : std_logic := '0';
    signal WBS_STB_O : std_logic := '0';
    signal WBS_ACK_I : std_logic;
    signal WBS_ADDR_O : std_logic_vector(23 downto 0) := (others => '0');
    signal WBS_DATA_O : std_logic_vector(15 downto 0) := (others => '0');
    signal WBS_DATA_I : std_logic_vector(15 downto 0);
    signal WBS_WE_O   : std_logic := '0';

    -- SDRAM pins (simulate only DQ, others are observed)
    signal DRAM_CLK   : std_logic;
    signal DRAM_CKE   : std_logic;
    signal DRAM_CS_N  : std_logic;
    signal DRAM_RAS_N : std_logic;
    signal DRAM_CAS_N : std_logic;
    signal DRAM_WE_N  : std_logic;
    signal DRAM_BA_0  : std_logic;
    signal DRAM_BA_1  : std_logic;
    signal DRAM_ADDR  : std_logic_vector(11 downto 0);
    signal DRAM_DQ    : std_logic_vector(15 downto 0) := (others => 'Z');
    signal DRAM_UDQM  : std_logic;
    signal DRAM_LDQM  : std_logic;

    -- Simple memory model (small) using modulo addressing
    type mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- DRAM model internal registers
    signal act_bank   : std_logic_vector(1 downto 0) := (others => '0');
    signal act_row    : std_logic_vector(11 downto 0) := (others => '0');
    signal read_pending : integer := 0;
    signal read_data_out : std_logic_vector(15 downto 0) := (others => '0');

    constant SYS_PERIOD_NS : time := 20 ns; -- 50 MHz
    constant CAS_LATENCY_CYC : integer := 2;

begin
    -- Instantiate DUT (SDRAM_WSH_P wrapper)
    DUT : entity work.SDRAM_WSH_P
        port map (
            CLK      => CLK,
            RST_I    => RST_I,
            WBS_CYC_I => WBS_CYC_O,
            WBS_STB_I => WBS_STB_O,
            WBS_ACK_O => WBS_ACK_I,
            WBS_ADDR_I => WBS_ADDR_O,
            WBS_DATA_O => WBS_DATA_I,
            WBS_DATA_I => WBS_DATA_O,
            WBS_WE_I  => WBS_WE_O,

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
            DRAM_UDQM => DRAM_UDQM,
            DRAM_LDQM => DRAM_LDQM
        );

    -- Drive system clock
    clk_proc : process
    begin
        while now < 500 us loop
            CLK <= '0';
            wait for SYS_PERIOD_NS/2;
            CLK <= '1';
            wait for SYS_PERIOD_NS/2;
        end loop;
        wait;
    end process;

    -- Simple SDRAM device model: react to commands driven on DRAM control pins
    dram_model : process(CLK)
        variable col : std_logic_vector(7 downto 0);
        variable bankrowcol_idx : integer;
        variable addr_vec : std_logic_vector(21 downto 0);
        variable addr_vec2 : std_logic_vector(21 downto 0);
        variable next_read_pending : integer;
    begin
        if rising_edge(CLK) then
            -- Calculate what read_pending will be next cycle
            if read_pending > 0 then
                next_read_pending := read_pending - 1;
            else
                next_read_pending := 0;
            end if;

            -- Tri-state DRAM_DQ: drive when next_read_pending will be 1 (one more cycle before ready)
            if next_read_pending = 1 and read_pending > 0 then
                DRAM_DQ <= read_data_out;
            else
      --          DRAM_DQ <= (others => 'Z');
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
                    col := DRAM_ADDR(7 downto 0);
                    addr_vec := act_bank & act_row(11 downto 0) & col;
                    bankrowcol_idx := to_integer(unsigned(addr_vec)) mod mem'length;
                    read_data_out <= mem(bankrowcol_idx);
                    read_pending <= CAS_LATENCY_CYC;
                end if;

                -- WRITE: RAS=1, CAS=0, WE=0
                if DRAM_RAS_N = '1' and DRAM_CAS_N = '0' and DRAM_WE_N = '0' then
                    col := DRAM_ADDR(7 downto 0);
                    addr_vec2 := act_bank & act_row(11 downto 0) & col;
                    bankrowcol_idx := to_integer(unsigned(addr_vec2)) mod mem'length;
                    mem(bankrowcol_idx) <= DRAM_DQ;
                end if;

            end if;
        end if;
    end process;

    -- Test stimulus - Wishbone Master behavior (CPU)
    stim_proc : process
    begin
        -- Reset
        RST_I <= '1';
        WBS_CYC_O <= '0';
        WBS_STB_O <= '0';
        WBS_WE_O <= '0';
        wait for 200 ns;
        RST_I <= '0';

        -- Wait for SDRAM controller to initialize
        wait for 500 ns; -- in simulation only, so wishbone has to wait for reset to end

        -- ===== TRANSACTION 1: First WRITE to address 0x000100 =====
        report "Starting first WRITE transaction to 0x000100";
        WBS_ADDR_O <= x"000100";  -- word address 0x000100
        WBS_DATA_O <= x"ABCD";
        WBS_WE_O <= '1';
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '1';
        WBS_STB_O <= '1';
        wait for SYS_PERIOD_NS;
        
        -- Wait for ACK
        wait until WBS_ACK_I = '1';
        report "First WRITE ACK received";
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '0';
        WBS_STB_O <= '0';
        WBS_ADDR_O <= x"000200";  -- word address 0x000200
        WBS_DATA_O <= x"1234";
        WBS_WE_O <= '1';
        wait for SYS_PERIOD_NS;
        -- WBS_WE_O <= '0';

        -- wait for SYS_PERIOD_NS; -- try to immediately do another write, but RAM is busy!

        -- ===== TRANSACTION 2: Second WRITE to address 0x000200 =====
        -- report "Starting second WRITE transaction to 0x000200";
        -- WBS_ADDR_O <= x"000200";  -- word address 0x000200
        -- WBS_DATA_O <= x"1234";
        -- WBS_WE_O <= '1';
        -- wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '1';
        WBS_STB_O <= '1';
        wait for SYS_PERIOD_NS;
        
        -- Wait for ACK
        wait until WBS_ACK_I = '1';
        report "Second WRITE ACK received";
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '0';
        WBS_STB_O <= '0';
        wait for SYS_PERIOD_NS;
        WBS_WE_O <= '0';
        wait for 200 ns;

        -- ===== TRANSACTION 3: READ from address 0x000100 =====
        report "Starting READ transaction from 0x000100";
        WBS_ADDR_O <= x"000100";  -- word address 0x000100
        WBS_WE_O <= '0';
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '1';
        WBS_STB_O <= '1';
        wait for SYS_PERIOD_NS;
        
        -- Wait for ACK
        wait until WBS_ACK_I = '1';
        report "READ ACK received, data = 0x" & integer'image(to_integer(unsigned(WBS_DATA_I)));
        if WBS_DATA_I = x"ABCD" then
            report "READ data correct: 0xABCD";
        else
            report "READ data INCORRECT: expected 0xABCD, got 0x" & integer'image(to_integer(unsigned(WBS_DATA_I)));
        end if;
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '0';
        WBS_STB_O <= '0';
        wait for 200 ns;

        -- ===== TRANSACTION 4: READ from address 0x000200 =====
        report "Starting READ transaction from 0x000200";
        WBS_ADDR_O <= x"000200";  -- word address 0x000200
        WBS_WE_O <= '0';
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '1';
        WBS_STB_O <= '1';
        wait for SYS_PERIOD_NS;
        
        -- Wait for ACK
        wait until WBS_ACK_I = '1';
        report "READ ACK received, data = 0x" & integer'image(to_integer(unsigned(WBS_DATA_I)));
        if WBS_DATA_I = x"1234" then
            report "READ data correct: 0x1234";
        else
            report "READ data INCORRECT: expected 0x1234, got 0x" & integer'image(to_integer(unsigned(WBS_DATA_I)));
        end if;
        wait for SYS_PERIOD_NS;
        
        WBS_CYC_O <= '0';
        WBS_STB_O <= '0';
        wait for 500 ns;

        report "End of test.";
        wait;
    end process;

end architecture;
