library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity CTRL_RAM_tb is
end CTRL_RAM_tb;

architecture testbench of CTRL_RAM_tb is
    -- Clock and reset signals
    signal clk      : std_logic := '0';
    signal rst_i    : std_logic := '0';
    constant CLK_PERIOD : time := 20 ns;  -- 50MHz clock

    -- Wishbone interconnect signals between CTRL and RAM
    signal wb_cyc   : std_logic;
    signal wb_stb   : std_logic;
    signal wb_ack   : std_logic;
    signal wb_addr  : std_logic_vector(15 downto 0);
    signal wb_data_to_ram   : std_logic_vector(15 downto 0);
    signal wb_data_to_ctrl  : std_logic_vector(15 downto 0);
    signal wb_we    : std_logic;

    -- CTRL module interface signals
    signal inst     : std_logic_vector(15 downto 0);
    signal const_v  : std_logic_vector(15 downto 0);
    signal pc       : std_logic_vector(15 downto 0);
    signal pc_inc   : std_logic_vector(15 downto 0);
    signal mrdata   : std_logic_vector(15 downto 0);
    signal werf     : std_logic;
    signal rbsel    : std_logic;
    signal wdsel    : std_logic_vector(1 downto 0);
    signal alu_out  : std_logic_vector(15 downto 0);
    signal mwdata   : std_logic_vector(15 downto 0);
    signal z_flag   : std_logic;

    -- Test state tracking
    type test_state_t is (
        TEST_INIT,
        TEST_RESET,
        TEST_INST_FETCH,
        TEST_CONST_FETCH,
        TEST_EXECUTE,
        TEST_LOAD,
        TEST_STORE,
        TEST_BRANCH,
        TEST_COMPLETE
    );
    signal current_test : test_state_t := TEST_INIT;
    signal current_test_num : integer range 0 to 8 := 0;

    -- Wishbone transaction monitoring
    procedure wb_monitor(
        signal cyc  : in std_logic;
        signal stb  : in std_logic;
        signal we   : in std_logic;
        signal addr : in std_logic_vector;
        signal wdata: in std_logic_vector;
        signal rdata: in std_logic_vector;
        msg         : in string
    ) is
    begin
        if cyc = '1' and stb = '1' then
            if we = '1' then
                report msg & ": Write transaction - Address: 0x" & 
                       to_hstring(unsigned(addr)) & " Data: 0x" & 
                       to_hstring(unsigned(wdata));
            else
                report msg & ": Read transaction - Address: 0x" & 
                       to_hstring(unsigned(addr)) & " Data: 0x" & 
                       to_hstring(unsigned(rdata));
            end if;
        end if;
    end procedure;

    -- Test completion check
    procedure check_test_complete(
        test_name   : in string;
        expected    : in std_logic_vector;
        actual      : in std_logic_vector
    ) is
    begin
        assert expected = actual
            report test_name & " failed! Expected: 0x" & 
                   to_hstring(unsigned(expected)) & 
                   " Got: 0x" & to_hstring(unsigned(actual))
            severity error;
        report test_name & " passed!";
    end procedure;

begin
    -- Clock generation
    process
    begin
        wait for CLK_PERIOD/2;
        clk <= not clk;
    end process;

    -- Convert test state to number for waveform viewing
    process(current_test)
    begin
        case current_test is
            when TEST_INIT =>        current_test_num <= 0;
            when TEST_RESET =>       current_test_num <= 1;
            when TEST_INST_FETCH =>  current_test_num <= 2;
            when TEST_CONST_FETCH => current_test_num <= 3;
            when TEST_EXECUTE =>     current_test_num <= 4;
            when TEST_LOAD =>        current_test_num <= 5;
            when TEST_STORE =>       current_test_num <= 6;
            when TEST_BRANCH =>      current_test_num <= 7;
            when TEST_COMPLETE =>    current_test_num <= 8;
        end case;
    end process;

    -- Instantiate CTRL_WSH_M
    ctrl_inst : entity work.CTRL_WSH_M
    port map (
        CLK         => clk,
        RST_I       => rst_i,
        -- Wishbone signals
        WBS_CYC_O   => wb_cyc,
        WBS_STB_O   => wb_stb,
        WBS_ACK_I   => wb_ack,
        WBS_ADDR_O  => wb_addr,
        WBS_DATA_O  => wb_data_to_ram,
        WBS_DATA_I  => wb_data_to_ctrl,
        WBS_WE_O    => wb_we,
        -- Spikeputor signals
        INST        => inst,
        CONST       => const_v,
        PC          => pc,
        PC_INC      => pc_inc,
        MRDATA      => mrdata,
        WERF        => werf,
        RBSEL       => rbsel,
        WDSEL       => wdsel,
        ALU_OUT     => alu_out,
        MWDATA      => mwdata,
        Z           => z_flag
    );

    -- Instantiate RAM_WSH_P
    ram_inst : entity work.RAM_WSH_P
    port map (
        CLK         => clk,
        RST_I       => rst_i,
        -- Wishbone signals
        WBS_CYC_I   => wb_cyc,
        WBS_STB_I   => wb_stb,
        WBS_ACK_O   => wb_ack,
        WBS_ADDR_I  => wb_addr,
        WBS_DATA_O  => wb_data_to_ctrl,
        WBS_DATA_I  => wb_data_to_ram,
        WBS_WE_I    => wb_we
    );

    -- Wishbone transaction monitor
    monitor: process(clk)
    begin
        if rising_edge(clk) then
            wb_monitor(wb_cyc, wb_stb, wb_we, wb_addr, 
                      wb_data_to_ram, wb_data_to_ctrl,
                      "Wishbone Transaction");
        end if;
    end process;

    -- Test stimulus process
    stimulus: process
    begin
        -- Initialize
        current_test <= TEST_INIT;
        rst_i <= '1';
        alu_out <= (others => '0');
        mwdata <= (others => '0');
        z_flag <= '0';
        wait for CLK_PERIOD * 2;

        -- Release reset
        current_test <= TEST_RESET;
        rst_i <= '0';
        wait for CLK_PERIOD * 2;

        -- Test 1: Basic instruction fetch
        current_test <= TEST_INST_FETCH;
        -- Let the controller fetch from reset vector
        wait for CLK_PERIOD * 4;
        check_test_complete("Instruction Fetch", 
                          x"F000",  -- Reset vector address
                          pc);

        -- Test 2: Load operation
        current_test <= TEST_LOAD;
        -- Set up ALU output for load address
        alu_out <= x"0100";  -- Load from address 0x0100
        wait for CLK_PERIOD * 4;

        -- Test 3: Store operation
        current_test <= TEST_STORE;
        -- Set up data to store
        mwdata <= x"BEEF";
        wait for CLK_PERIOD * 4;

        -- Test 4: Branch operation
        current_test <= TEST_BRANCH;
        -- Set up branch condition
        z_flag <= '1';
        alu_out <= x"1000";  -- Branch target address
        wait for CLK_PERIOD * 4;

        -- End simulation
        current_test <= TEST_COMPLETE;
        wait for CLK_PERIOD * 2;
        report "Test completed";
        wait;
    end process;

end testbench;