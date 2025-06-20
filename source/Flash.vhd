----------------------------------------------------------------------------------
-- Description      : Spansion S29AL032D-04 32Mbit NOR Flash Memory Controller
--                  : Keep chip set in WORD mode (keep #BYTE high)
----------------------------------------------------------------------------------
--| WR | RD | ERASE | OPERATION    |
--|----|----|-------|--------------|
--| X  | X  |  XX   | IDLE         |
--| 1  | 0  |  00   | WRITE        |
--| 0  | 1  |  00   | READ         |
--| 0  | 0  |  01   | CHIP ERASE   |
--| 0  | 0  |  10   | SECTOR ERASE |
----------------------------------------------------------------------------------

library IEEE;
    use IEEE.std_logic_1164.all;

entity FLASH_RAM is
    generic (MAIN_CLK_NS : integer := 20 ); -- 50 MHz = 20 ns
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
        READY_OUT   : out std_logic; -- High when controller ready for a new operation
        VALID_OUT	: out std_logic; -- High when controller wrote bytes / erased without errors
        ERROR_OUT	: out std_logic; -- High when error, system need to reset chip and repeat operation

        -- flash chip signals
        WP_n        : out std_logic; -- write protection
        BYTE_n      : out std_logic; -- byte mode/~word mode
        RST_n       : out std_logic; -- chip reset
        CE_n        : out std_logic; -- chip enable
        OE_n        : out std_logic; -- output enable
        WE_n        : out std_logic; -- write enable
        BY_n        :  in std_logic; -- chip ready/~busy
        A	        : out std_logic_vector(21 downto 0); -- chip Address
        DQ          : inout std_logic_vector(15 downto 0) -- chip DQ
	);
end entity;

architecture rtl of FLASH_RAM is

    -- Main state machine
    type fsm_main is (ST_IDLE, ST_READ, ST_WRITE, ST_CHIP_ERASE, ST_SECTOR_ERASE);
    signal st_main : fsm_main;

    -- Write Mode
    type fsm_write is (W_SEQ0, W_SEQ1, W_SEQ2, W_SEQ3, W_WAIT);
    signal st_writing : fsm_write;

    -- Chip Erase
    type fsm_erase is (E0_SEQ0, E0_SEQ1, E0_SEQ2, E0_SEQ3, E0_SEQ4, E0_SEQ5, E0_WAIT);
    signal st_chip_erasing : fsm_erase;

    -- Sector Erase
    type fsm_s_erase is (E1_SEQ0, E1_SEQ1, E1_SEQ2, E1_SEQ3, E1_SEQ4, E1_SEQ5, E1_WAIT);
    signal st_sector_erasing : fsm_s_erase;

    -- command timers - total number of ticks of master clock for each command
    -- Only really need one counter, since none of these are ewver ussed at the same time!
    signal t_RD     : integer range 0 to (100/MAIN_CLK_NS) := 0; -- Read counter - tACC is 70 ns max
    signal t_WR     : integer range 0 to (100/MAIN_CLK_NS) := 0; -- Write counter - tWC is 70 ns max
    signal t_CE     : integer range 0 to (100/MAIN_CLK_NS) := 0; -- Chip Erase counter - tWC is 70 ns max
    signal t_SE     : integer range 0 to (100/MAIN_CLK_NS) := 0; -- Sector Erase counter - tWC is 70 ns max

    -- wait timers - used while waiting for n_busy to go low as a timeout watchdog in case of error.
    -- Max sector erase time is 10 s, typical chip erase time is 45 s, max word programming time is 360 us.
    signal t_WHWH1  : integer range 0 to (360100/MAIN_CLK_NS) := 0; -- Write wait counter - 360us max until an error
    signal t_WHWH2  : integer range 0 to (120/MAIN_CLK_NS) := 0; -- Chip Erase counter - wait 90 ns max before n_busy goes low
    signal t_WHWH3  : integer range 0 to (120/MAIN_CLK_NS) := 0; -- Sector erase counter - wait 90 ns max before n_busy goes low

    -- Flash commands (Word mode) - The command *might* need to be repeated in the high byte (0xF0F0), but probably not
    constant write_data_reset   : std_logic_vector(15 downto 0) := x"00F0";

    constant write_data_first   : std_logic_vector(15 downto 0) := x"00AA";
    constant write_data_second  : std_logic_vector(15 downto 0) := x"0055";
    constant write_data_third   : std_logic_vector(15 downto 0) := x"00A0";

    constant write_addr_first   : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555
    constant write_addr_second  : std_logic_vector(21 downto 0) := "0000000000001010101010"; -- 2AA
    constant write_addr_third   : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555

    constant erase_data_first   : std_logic_vector(15 downto 0) := x"00AA";
    constant erase_data_second  : std_logic_vector(15 downto 0) := x"0055";
    constant erase_data_third   : std_logic_vector(15 downto 0) := x"0080";
    constant erase_data_fourth  : std_logic_vector(15 downto 0) := x"00AA";
    constant erase_data_fifth   : std_logic_vector(15 downto 0) := x"0055";
    constant erase_data_sixth   : std_logic_vector(15 downto 0) := x"0010";
    constant erase_data_sector  : std_logic_vector(15 downto 0) := x"0030";

    constant erase_addr_first   : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555
    constant erase_addr_second  : std_logic_vector(21 downto 0) := "0000000000001010101010"; -- 2AA
    constant erase_addr_third   : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555
    constant erase_addr_fourth  : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555
    constant erase_addr_fifth   : std_logic_vector(21 downto 0) := "0000000000001010101010"; -- 2AA
    constant erase_addr_sixth   : std_logic_vector(21 downto 0) := "0000000000010101010101"; -- 555

    -- internal signals
     -- reset and command bits
    signal reset                : std_logic;
    signal chip_enable          : std_logic;
    signal write_enable         : std_logic;
    signal output_enable        : std_logic;
    -- data I/O and address signals 
    signal dq_data_out_r        : std_logic_vector(15 downto 0);
    signal dq_data_in_r         : std_logic_vector(15 downto 0);
    signal address_wr_r         : std_logic_vector(21 downto 0);
    -- internal busy signal
    signal busy_i               : std_logic;
    -- data polling signals
    signal programming_complete : std_logic; 
    signal programming_error    : std_logic;

begin
    -- reset and control signals to chip input pins
    RST_n       <= not(reset);

    WP_n        <= '1'; -- not write protected
    BYTE_n      <= '1'; -- word mode, not byte mode

    CE_n        <= not(chip_enable);
    OE_n        <= not(output_enable);
    WE_n        <= not(write_enable);

    -- controller output signals
    ERROR_OUT   <= programming_error;
    VALID_OUT   <= programming_complete;
    READY_OUT   <= (not busy_i) and BY_n; -- not ready if either state machines or chip is busy
    DATA_OUT    <= dq_data_in_r;

    -- controller to flash chip in signal ('Z' when chip output is not enabled or in reading phase of state machines)
    DQ          <= dq_data_out_r when (output_enable = '0' and st_main /= ST_READ) else (others => 'Z');
    
    process(CLK_IN, RST_IN)
    begin
        if (RST_IN = '1') then  -- RESET
            reset                   <= '1'; -- reset chip settings
            chip_enable	            <= '0';
            output_enable           <= '0';
            write_enable            <= '0';
            A                       <= (others => '0'); -- reset chip address
            st_main                 <= ST_IDLE; -- reset state machines
            st_writing              <= W_SEQ0;
            st_chip_erasing         <= E0_SEQ0;
            st_sector_erasing       <= E1_SEQ0;
            address_wr_r            <= (others => '0'); -- reset internal address and data signals
            dq_data_in_r            <= (others => '0');
            dq_data_out_r           <= (others => '0');
            busy_i                  <= '0';             -- reset busy flag
            t_WHWH1                 <= 0;               -- reset internal wait counters
            t_WHWH2                 <= 0;
            t_WHWH3                 <= 0;
            t_RD                    <= 0;
            t_WR                    <= 0;
            t_CE                    <= 0;
            t_SE                    <= 0;
            programming_complete    <= '0';
            programming_error       <= '0';

        elsif (rising_edge(CLK_IN)) then -- handle state machines on rising clock edge
            reset <= '0';

            case (st_main) is   -- main state machine

                when ST_IDLE => -- IDLE handler
                    -- reset all chip controls, timing counters, and sub state machines
                    chip_enable         <= '0';
                    output_enable       <= '0';
                    write_enable        <= '0';
                    busy_i              <= '0';
                    t_WHWH1	            <= 0;
                    t_WHWH2	            <= 0;
                    t_WHWH3	            <= 0;
                    t_WR                <= 0;
                    t_RD                <= 0;
                    t_CE                <= 0;
                    t_SE                <= 0;
                    st_writing          <= W_SEQ0;
                    st_chip_erasing     <= E0_SEQ0;
                    st_sector_erasing   <= E1_SEQ0;

                    if (BY_n = '1' and programming_error = '0') then -- don't enter new state until chip is not busy and no error
                        if (RD_IN = '1' and WR_IN = '0' and ERASE_IN = "00") then -- enter Read Mode
                            st_main         <= ST_READ;         -- new state is ST_READ
                            address_wr_r    <= ADDR_IN;         -- get address to read
                            busy_i          <= '1';             -- mark controller as busy
                            programming_complete <= '0';        -- clear programming complete flag
                        elsif (RD_IN = '0' and WR_IN = '1' and ERASE_IN = "00") then -- enter Write Command
                            st_main         <= ST_WRITE;        -- new state is ST_WRITE
                            address_wr_r    <= ADDR_IN;         -- get address to write
                            busy_i          <= '1';             -- mark controller as busy
                            programming_complete <= '0';        -- clear programming complete flag
                        elsif (RD_IN = '0' and WR_IN = '0' and ERASE_IN = "01") then -- enter Chip Erase
                            st_main         <= ST_CHIP_ERASE;   -- new state is ST_CHIP_ERASE
                            busy_i          <= '1';
                            programming_complete <= '0';        -- clear programming complete flag
                        elsif (RD_IN = '0' and WR_IN = '0' and ERASE_IN = "10") then -- enter Sector Erase
                            st_main         <= ST_SECTOR_ERASE; -- new state is ST_SECTOR_ERASE
                            address_wr_r    <= ADDR_IN;         -- get sector number to erase
                            busy_i          <= '1';             -- mark controller as busy
                            programming_complete <= '0';        -- clear programming complete flag
                        else
                            st_main         <= ST_IDLE;         -- stay idle if the new command doesn't make sense
                        end if; 
                    else
                        st_main <= ST_IDLE;     -- stay idle if state machines or chip is busy or error
                    end if;

                when ST_READ =>
					     A               <= address_wr_r;    -- set chip address 
                    dq_data_in_r    <= DQ;              -- set data in register to input from chip DQ

                    -- Timer for read cycle time
                    if (t_RD < 70/MAIN_CLK_NS) then   -- Read cycle time counter - count up to 70 ns
                        t_RD <= t_RD + 1;
                    else                                    -- after 70 ns, data is ready to read
                        if (RD_IN = '0') then
                            st_main         <= ST_IDLE;     -- but don't go back to idle until the CPU clears RD_IN
                        else 
                            busy_i      <= '0';             -- set busy signal low so CPU knows it can use the data
                        end if;
                    end if;
						  
						  if (t_RD = 0) then								-- set up chip controls at time 0
						      write_enable    <= '0';             -- set WE to 0, so chip is in read mode
                        output_enable   <= '1';             -- set OE to 1, so chip outputs data on DQ
                        chip_enable     <= '1';             -- set CE to 1, so chip is enabled
						  end if;

                when ST_WRITE =>
                    -- write state machine - write three commands, then write the actual data
                    -- Update the write cycle time counter
                    if (t_WR > (70/MAIN_CLK_NS)) then
                        t_WR <= 0;
                    elsif (st_writing = W_WAIT) then    -- reset counter during wait phase
                        t_WR <= 0;
                    else
                        t_WR <= t_WR + 1;
                    end if;

                    -- Execute each of four writes for the "program" sequence, then wait
                    if (st_writing /= W_WAIT) then  -- if state is not waiting, do standard write timing sequence
                        if (t_WR = 0) then                      -- immediately put command address and data on, and set CE
                            write_enable            <= '0';
                            output_enable           <= '0';
                            chip_enable             <= '1';
                            programming_complete    <= '0';
                            case (st_writing) is    -- set address and data according to current sequence state
                                when W_SEQ0 =>
                                    A               <= write_addr_first;
                                    dq_data_out_r   <= write_data_first;
                                when W_SEQ1 =>
                                    A               <= write_addr_second;
                                    dq_data_out_r   <= write_data_second;
                                when W_SEQ2 =>
                                    A               <= write_addr_third;
                                    dq_data_out_r   <= write_data_third;
                                when W_SEQ3 =>
                                    A               <= address_wr_r;
                                    dq_data_out_r   <= DATA_IN;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        elsif (t_WR = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                            write_enable    <= '1';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                        elsif (t_WR = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '0';
                            case (st_writing) is    -- set new sequence state
                                when W_SEQ0 =>
                                    st_writing  <= W_SEQ1;
                                when W_SEQ1 =>
                                    st_writing  <= W_SEQ2;
                                when W_SEQ2 =>
                                    st_writing  <= W_SEQ3;
                                when W_SEQ3 =>
                                    st_writing  <= W_WAIT;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        end if;
                    else    -- state is waiting, so wait for the "program" cycle to complete
                        if (t_WHWH1 > (360100/MAIN_CLK_NS)) then    -- timeout, there was an error writing the data, stop counting
                                programming_complete    <= '0';
                                programming_error       <= '1';
                                st_main                 <= ST_IDLE;
                        elsif (t_WHWH1 > (90/MAIN_CLK_NS)) then     -- after 90 ns, poll the BY_n signal
                            if (BY_n = '1') then                    -- when RY/BY# = 1, write is complete
                                programming_complete    <= '1';
                                programming_error       <= '0';
                                st_main                 <= ST_IDLE;
                            end if;
                            t_WHWH1 <= t_WHWH1 + 1;                 -- still count to see if timeout is surpassed 
                        else
                            t_WHWH1	<= t_WHWH1 + 1;
                        end if;
                    end if;

                when ST_CHIP_ERASE => 
                -- Chip Erase state machine - write six commands similar to write state
                    if (t_CE > (70/MAIN_CLK_NS)) then       -- Erase cycle time counter
                        t_CE <= 0;
                    elsif (st_chip_erasing = E0_WAIT) then  -- Reset counter during wait phase
                        t_CE <= 0;
                    else
                        t_CE <= t_CE + 1;
                    end if;

                    -- Execute each of six writes for the "chip erase" sequence, then wait
                    if (st_chip_erasing /= E0_WAIT) then  -- if state is not waiting, do standard write timing sequence
                        if (t_CE = 0) then                      -- immediately put command address and data on, and set CE
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                            case (st_chip_erasing) is   -- set address and data according to current sequence state
                                when E0_SEQ0 =>
                                    A               <= erase_addr_first;
                                    dq_data_out_r   <= erase_data_first;
                                when E0_SEQ1 =>
                                    A               <= erase_addr_second;
                                    dq_data_out_r   <= erase_data_second;
                                when E0_SEQ2 =>
                                    A               <= erase_addr_third;
                                    dq_data_out_r   <= erase_data_third;
                                when E0_SEQ3 =>
                                    A               <= erase_addr_fourth;
                                    dq_data_out_r   <= erase_data_fourth;
                                when E0_SEQ4 =>
                                    A               <= erase_addr_fifth;
                                    dq_data_out_r   <= erase_data_fifth;
                                when E0_SEQ5 =>
                                    A               <= erase_addr_sixth;
                                    dq_data_out_r   <= erase_data_sixth;    -- chip erase command
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        elsif (t_CE = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                            write_enable    <= '1';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                        elsif (t_CE = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '0';
                            case (st_chip_erasing) is    -- set new sequence state
                                when E0_SEQ0 =>
                                    st_chip_erasing  <= E0_SEQ1;
                                when E0_SEQ1 =>
                                    st_chip_erasing  <= E0_SEQ2;
                                when E0_SEQ2 =>
                                    st_chip_erasing  <= E0_SEQ3;
                                when E0_SEQ3 =>
                                    st_chip_erasing  <= E0_SEQ4;
                                when E0_SEQ4 =>
                                    st_chip_erasing  <= E0_SEQ5;
                                when E0_SEQ5 =>
                                    st_chip_erasing  <= E0_WAIT;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        end if;
                    else    -- state is waiting, so wait for the "chip erase" cycle to complete - typical timing is 45 seconds!
                        if (t_WHWH2 > (90/MAIN_CLK_NS)) then        -- after 90 ns, poll the BY_n signal forever until it goes low
                            if (BY_n = '1') then                    -- when RY/BY# = 1, write is complete
                                programming_complete    <= '1';
                                programming_error       <= '0';
                                st_main                 <= ST_IDLE;
                            end if; 
                        else
                            t_WHWH2	<= t_WHWH2 + 1;                 -- only increment the timer until RY/BY# is ready
                        end if;
                    end if;

                when ST_SECTOR_ERASE => 
                -- Sector Erase state machine - write six commands similar to write state, address of sixth command is sector to erase
                    if (t_SE > (70/MAIN_CLK_NS)) then       -- Erase cycle time counter
                        t_SE <= 0;
                    elsif (st_sector_erasing = E1_WAIT) then  -- Reset counter during wait phase
                        t_SE <= 0;
                    else
                        t_SE <= t_SE + 1;
                    end if;

                    -- Execute each of six writes for the "sector erase" sequence, then wait
                    if (st_sector_erasing /= E1_WAIT) then    -- if state is not waiting, do standard write timing sequence
                        if (t_SE = 0) then                      -- immediately put command address and data on, and set CE
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                            case (st_sector_erasing) is     -- set address and data according to current sequence state
                                when E1_SEQ0 =>
                                    A               <= erase_addr_first;
                                    dq_data_out_r   <= erase_data_first;
                                when E1_SEQ1 =>
                                    A               <= erase_addr_second;
                                    dq_data_out_r   <= erase_data_second;
                                when E1_SEQ2 =>
                                    A               <= erase_addr_third;
                                    dq_data_out_r   <= erase_data_third;
                                when E1_SEQ3 =>
                                    A               <= erase_addr_fourth;
                                    dq_data_out_r   <= erase_data_fourth;
                                when E1_SEQ4 =>
                                    A               <= erase_addr_fifth;
                                    dq_data_out_r   <= erase_data_fifth;
                                when E1_SEQ5 =>
                                    A               <= address_wr_r;
                                    dq_data_out_r   <= erase_data_sector; -- sector erase command
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        elsif (t_SE = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                            write_enable    <= '1';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                        elsif (t_SE = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '0';
                            case (st_sector_erasing) is    -- set new sequence state
                                when E1_SEQ0 =>
                                    st_sector_erasing  <= E1_SEQ1;
                                when E1_SEQ1 =>
                                    st_sector_erasing  <= E1_SEQ2;
                                when E1_SEQ2 =>
                                    st_sector_erasing  <= E1_SEQ3;
                                when E1_SEQ3 =>
                                    st_sector_erasing  <= E1_SEQ4;
                                when E1_SEQ4 =>
                                    st_sector_erasing  <= E1_SEQ5;
                                when E1_SEQ5 =>
                                    st_sector_erasing  <= E1_WAIT;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        end if;
                    else    -- state is waiting, so wait for the "sector erase" cycle to complete - typical timing is ~1 second
                        if (t_WHWH3 > (90/MAIN_CLK_NS)) then        -- after 90 ns, poll the BY_n signal forever until it goes low
                            if (BY_n = '1') then                    -- when RY/BY# = 1, write is complete
                                programming_complete    <= '1';
                                programming_error       <= '0';
                                st_main                 <= ST_IDLE;
                            end if; 
                        else
                            t_WHWH3	<= t_WHWH3 + 1;                 -- only increment the timer until RY/BY# is ready
                        end if;
                    end if;
            end case;

        end if;

    end process;

end architecture;
