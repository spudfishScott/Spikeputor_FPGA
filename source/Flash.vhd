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

    -- -- Write Mode
    -- type fsm_write is (W_SEQ0, W_SEQ1, W_SEQ2, W_SEQ3, W_WAIT);
    -- signal st_writing : fsm_write;

    -- -- Chip Erase
    -- type fsm_erase is (E0_SEQ0, E0_SEQ1, E0_SEQ2, E0_SEQ3, E0_SEQ4, E0_SEQ5, E0_WAIT);
    -- signal st_chip_erasing : fsm_erase;

    -- -- Sector Erase
    -- type fsm_s_erase is (E1_SEQ0, E1_SEQ1, E1_SEQ2, E1_SEQ3, E1_SEQ4, E1_SEQ5, E1_WAIT);
    -- signal st_sector_erasing : fsm_s_erase;

    -- Program Erase
    type fsm_pr_erase is (PR_SEQ0, PR_SEQ1, PR_SEQ2, PR_SEQ3, PR_SEQ4, PR_SEQ5, PR_WAIT);
    signal st_programming : fsm_pr_erase;

    -- command timer - total number of ticks of master clock for each command
    signal t_EX     : integer range 0 to (100/MAIN_CLK_NS) := 0; -- Execution counter - tACC is 70 ns max, tWC is 70 ns max

    -- wait timer - used while waiting for n_busy to go low as a timeout watchdog in case of error.
    -- Max sector erase time is 10 s, typical chip erase time is 45 s, max word programming time is 360 us.
    signal t_WPR    : integer range 0 to (360100/MAIN_CLK_NS) := 0; -- Program wait counter - 360 us max until an error
 
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
     -- flash chip reset and command bits
    signal reset                : std_logic;
    signal chip_enable          : std_logic;
    signal write_enable         : std_logic;
    signal output_enable        : std_logic;
    -- data I/O and address signals 
    signal dq_data_out_r        : std_logic_vector(15 downto 0);
    signal dq_data_in_r         : std_logic_vector(15 downto 0);
    signal address_wr_r         : std_logic_vector(21 downto 0);
    signal address_out_r        : std_logic_vector(21 downto 0);
    -- internal busy signal
    signal busy_i               : std_logic;
    -- internal command signal
    signal command              : std_logic_vector(3 downto 0);
    -- error signal
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
    VALID_OUT   <= '0' when (busy_i = '1' or programming_error = '1') else '1'; -- programming_complete;
    READY_OUT   <= (not busy_i) and BY_n; -- not ready if either state machines or chip is busy
    DATA_OUT    <= dq_data_in_r;

    -- controller to flash chip in signal ('Z' when chip output is not enabled or in reading phase of state machines)
    DQ          <= dq_data_out_r when (output_enable = '0' and st_main /= ST_READ) else (others => 'Z');
    
    -- controller to flash chip address
    A           <= address_out_r;

    process(CLK_IN, RST_IN)
    begin
        if (RST_IN = '1') then  -- RESET
            reset                   <= '1'; -- reset chip settings
            chip_enable	            <= '0';
            output_enable           <= '0';
            write_enable            <= '0';
            st_main                 <= ST_IDLE; -- reset state machines
            st_programming          <= PR_SEQ0;
          --  st_writing              <= W_SEQ0;
          --  st_chip_erasing         <= E0_SEQ0;
          --  st_sector_erasing       <= E1_SEQ0;
            address_out_r           <= (others => '0'); -- reset chip address
            address_wr_r            <= (others => '0'); -- reset internal address and data signals
            dq_data_in_r            <= (others => '0');
            dq_data_out_r           <= (others => '0');
            busy_i                  <= '0';             -- reset busy flag
            t_WPR                   <= 0;
            t_EX                    <= 0;
            programming_error       <= '0';
            command                 <= "0000";
            -- TODO: perhaps make sure all of these signals are set in every data path (necessary?)

        elsif (rising_edge(CLK_IN)) then -- handle state machines on rising clock edge
            reset <= '0';

            case (st_main) is   -- main state machine
                when ST_IDLE => -- IDLE handler
                    -- reset all chip controls, timing counters, and sub state machines
                    chip_enable         <= '0';
                    output_enable       <= '0';
                    write_enable        <= '0';
                    t_WPR               <= 0;
                    t_EX                <= 0;
                    st_programming      <= P_SEQ0;
                  --  st_writing          <= W_SEQ0;
                  --  st_chip_erasing     <= E0_SEQ0;
                  --  st_sector_erasing   <= E1_SEQ0;
                    busy_i              <= '1';                         -- set busy as default in all scenarios where there's a new command
                    address_wr_r        <= ADDR_IN;                     -- latch in address write register from ADDR_IN when idle
                    address_out_r       <= (others => '0');             -- on idle, clear address and data (in/out) registers
                    dq_data_in_r        <= (others => '0');
                    dq_data_out_r       <= (others => '0');
                    command             <= RD_IN & WR_IN & ERASE_IN;    -- concatenate the command bits for easier mapping

                    if (BY_n = '1' and programming_error = '0') then -- don't enter new state until chip is not busy and no error
                        case(command) is    -- command interpreter - set state to new command
                            when "1000" =>  -- READ command
                                st_main <= ST_READ;
                            when "0100" =>  -- WRITE command
                                st_main <= ST_WRITE;
                            when "0010" =>  -- SECTOR ERASE command
                                st_main <= ST_SECTOR_ERASE;
                            when "0001" =>  -- CHIP ERASE command
                                st_main <= ST_CHIP_ERASE;
                            when others =>  -- invalid command
                                st_main <= ST_IDLE;         -- stay idle if the new command doesn't make sense
                                busy_i  <= '0';             -- stay not busy when idle
                        end case;

                    else
                        st_main <= ST_IDLE;         -- stay idle if state machines or chip is busy or error
                        busy_i  <= '0';             -- stay not busy when idle
                    end if;

                when ST_READ =>
                    address_out_r   <= address_wr_r;    -- set chip address 
                    dq_data_in_r    <= DQ;              -- set data in register to input from chip DQ

                    -- Timer for read cycle time
                    if (t_EX < 70/MAIN_CLK_NS) then   -- Read cycle time counter - count up to 70 ns
                        t_EX <= t_EX + 1;
                    else                                    -- after 70 ns, data is ready to read
                        if (RD_IN = '0') then
                            st_main     <= ST_IDLE;         -- but don't go back to idle until the CPU clears RD_IN
                        else 
                            busy_i      <= '0';             -- set busy signal low so CPU knows it can use the data
                        end if;
                    end if;

                    if (t_EX = 0) then                      -- set up chip controls at time 0
                        write_enable    <= '0';             -- set WE to 0, so chip is in read mode
                        output_enable   <= '1';             -- set OE to 1, so chip outputs data on DQ
                        chip_enable     <= '1';             -- set CE to 1, so chip is enabled
                    end if;

                when ST_WRITE | ST_ERASE | ST_CHIP_ERASE =>
                    -- write state machine - write three commands, then write the actual data
                    -- Update the write cycle time counter
                    if (t_EX > (70/MAIN_CLK_NS)) then
                        t_EX <= 0;
                    elsif (st_programming = PR_WAIT) then
                        t_EX <= 0;
                    else
                        t_EX <= t_EX + 1;
                    end if;

                    -- Execute each of four writes for the "program" sequence, then wait
                    if (st_programming /= PR_WAIT) then  -- if state is not waiting, do standard write timing sequence
                        if (t_EX = 0) then                      -- immediately put command address and data on, and set CE
                            write_enable            <= '0';
                            output_enable           <= '0';
                            chip_enable             <= '1';
                            case (st_programming) is    -- set address and data according to current sequence state
                                when PR_SEQ0 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_WRITE =>
                                            address_out_r   <= write_addr_first;
                                            dq_data_out_r   <= write_data_first;
                                        when ST_ERASE | ST_CHIP_ERASE =>
                                            address_out_r   <= erase_addr_first;
                                            dq_data_out_r   <= erase_data_first;
                                        when others =>
                                            null;
                                    end case;
                                when PR_SEQ1 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_WRITE =>
                                            address_out_r   <= write_addr_second;
                                            dq_data_out_r   <= write_data_second;
                                        when ST_ERASE | ST_CHIP_ERASE =>
                                            address_out_r   <= erase_addr_second;
                                            dq_data_out_r   <= erase_data_second;
                                        when others =>
                                            null;
                                    end case;
                                when PR_SEQ2 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_WRITE =>
                                            address_out_r   <= write_addr_third;
                                            dq_data_out_r   <= write_data_third;
                                        when ST_ERASE | ST_CHIP_ERASE =>
                                            address_out_r   <= erase_addr_third;
                                            dq_data_out_r   <= erase_data_third;
                                        when others =>
                                            null;
                                    end case;
                                when PR_SEQ3 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_WRITE =>
                                            address_out_r   <= address_wr_r;
                                            dq_data_out_r   <= DATA_IN;
                                        when ST_ERASE | ST_CHIP_ERASE =>
                                            address_out_r   <= erase_addr_fourth;
                                            dq_data_out_r   <= erase_data_fourth;
                                        when others =>
                                            null;
                                    end case;
                                when PR_SEQ4 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_ERASE | ST_CHIP_ERASE =>
                                            address_out_r   <= erase_addr_fifth;
                                            dq_data_out_r   <= erase_data_fifth;
                                        when others =>
                                            null;
                                    end case;
                                when PR_SEQ5 =>
                                    case (st_main) is -- set address and data according to current function
                                        when ST_ERASE =>
                                            address_out_r   <= address_wr_r;
                                            dq_data_out_r   <= erase_data_sector; -- sector erase command
                                        when CHIP_ERASE =>
                                            address_out_r   <= erase_addr_sixth;
                                            dq_data_out_r   <= erase_data_sixth;  -- chip erase command
                                        when others =>
                                            null;
                                    end case;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        elsif (t_EX = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                            write_enable    <= '1';
                            output_enable   <= '0';
                            chip_enable     <= '1';
                        elsif (t_EX = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                            write_enable    <= '0';
                            output_enable   <= '0';
                            chip_enable     <= '0';
                            case (st_programming) is    -- set new sequence state
                                when PR_SEQ0 =>
                                    st_programming  <= PR_SEQ1;
                                when PR_SEQ1 =>
                                    st_programming  <= PR_SEQ2;
                                when PR_SEQ2 =>
                                    st_programming  <= PR_SEQ3;
                                when PR_SEQ3 =>
                                    if st_main = ST_WRITE then
                                        st_programming  <= PR_WAIT; -- end the sequence on WRITE
                                    else
                                        st_programming  <= PR_SEQ4;
                                    end if;
                                when PR_SEQ4 =>
                                    st_programming  <= PR_SEQ5;
                                when PR_SEQ5 =>
                                    st_programming  <= PR_WAIT;
                                when others =>
                                    null; -- shouldn't happen, but just in case
                            end case;
                        end if;
                    else    -- state is waiting, so wait for the "program" cycle to complete
                        if (t_WPR > (360100/MAIN_CLK_NS)) then    -- timeout, there was an error writing the data, stop counting
                                programming_error       <= '1';
                                st_main                 <= ST_IDLE;
                        elsif (t_WPR > (90/MAIN_CLK_NS)) then     -- after 90 ns, poll the BY_n signal
                            if (BY_n = '1') then                  -- when RY/BY# = 1, write is complete
                                programming_error       <= '0';
                                st_main                 <= ST_IDLE;
                            end if;

                            if (s_main = ST_WRITE) then           -- only check for timeout on WRITE, not ERASE operations
                                t_WPR <= t_WPR + 1;               -- still count to see if timeout is surpassed
                            end if;
                        else
                            t_WPR <= t_WPR + 1;
                        end if;
                    end if;

                when others =>
                    null;

                -- when ST_CHIP_ERASE => 
                -- -- Chip Erase state machine - write six commands similar to write state
                --     if (t_EX > (70/MAIN_CLK_NS)) then       -- Erase cycle time counter
                --         t_EX <= 0;
                --     elsif (st_chip_erasing = E0_WAIT) then  -- Reset counter during wait phase
                --         t_EX <= 0;
                --     else
                --         t_EX <= t_EX + 1;
                --     end if;

                --     -- Execute each of six writes for the "chip erase" sequence, then wait
                --     if (st_chip_erasing /= E0_WAIT) then  -- if state is not waiting, do standard write timing sequence
                --         if (t_EX = 0) then                      -- immediately put command address and data on, and set CE
                --             write_enable    <= '0';
                --             output_enable   <= '0';
                --             chip_enable     <= '1';
                --             case (st_chip_erasing) is   -- set address and data according to current sequence state
                --                 when E0_SEQ0 =>
                --                     address_out_r   <= erase_addr_first;
                --                     dq_data_out_r   <= erase_data_first;
                --                 when E0_SEQ1 =>
                --                     address_out_r  <= erase_addr_second;
                --                     dq_data_out_r   <= erase_data_second;
                --                 when E0_SEQ2 =>
                --                     address_out_r   <= erase_addr_third;
                --                     dq_data_out_r   <= erase_data_third;
                --                 when E0_SEQ3 =>
                --                     address_out_r   <= erase_addr_fourth;
                --                     dq_data_out_r   <= erase_data_fourth;
                --                 when E0_SEQ4 =>
                --                     address_out_r   <= erase_addr_fifth;
                --                     dq_data_out_r   <= erase_data_fifth;
                --                 when E0_SEQ5 =>
                --                     address_out_r   <= erase_addr_sixth;
                --                     dq_data_out_r   <= erase_data_sixth;    -- chip erase command
                --                 when others =>
                --                     null; -- shouldn't happen, but just in case
                --             end case;
                --         elsif (t_EX = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                --             write_enable    <= '1';
                --             output_enable   <= '0';
                --             chip_enable     <= '1';
                --         elsif (t_EX = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                --             write_enable    <= '0';
                --             output_enable   <= '0';
                --             chip_enable     <= '0';
                --             case (st_chip_erasing) is    -- set new sequence state
                --                 when E0_SEQ0 =>
                --                     st_chip_erasing  <= E0_SEQ1;
                --                 when E0_SEQ1 =>
                --                     st_chip_erasing  <= E0_SEQ2;
                --                 when E0_SEQ2 =>
                --                     st_chip_erasing  <= E0_SEQ3;
                --                 when E0_SEQ3 =>
                --                     st_chip_erasing  <= E0_SEQ4;
                --                 when E0_SEQ4 =>
                --                     st_chip_erasing  <= E0_SEQ5;
                --                 when E0_SEQ5 =>
                --                     st_chip_erasing  <= E0_WAIT;
                --                 when others =>
                --                     null; -- shouldn't happen, but just in case
                --             end case;
                --         end if;
                --     else    -- state is waiting, so wait for the "chip erase" cycle to complete - typical timing is 45 seconds!
                --         if (t_WPR > (90/MAIN_CLK_NS)) then        -- after 90 ns, poll the BY_n signal forever until it goes low
                --             if (BY_n = '1') then                  -- when RY/BY# = 1, write is complete
                --                 programming_error       <= '0';
                --                 st_main                 <= ST_IDLE;
                --             end if; 
                --         else
                --             t_WPR	<= t_WPR + 1;                 -- only increment the timer until RY/BY# is ready
                --         end if;
                --     end if;

                -- when ST_SECTOR_ERASE => 
                -- -- Sector Erase state machine - write six commands similar to write state, address of sixth command is sector to erase
                --     if (t_EX > (70/MAIN_CLK_NS)) then       -- Erase cycle time counter
                --         t_EX <= 0;
                --     elsif (st_sector_erasing = E1_WAIT) then  -- Reset counter during wait phase
                --         t_EX <= 0;
                --     else
                --         t_EX <= t_EX + 1;
                --     end if;

                --     -- Execute each of six writes for the "sector erase" sequence, then wait
                --     if (st_sector_erasing /= E1_WAIT) then    -- if state is not waiting, do standard write timing sequence
                --         if (t_EX = 0) then                      -- immediately put command address and data on, and set CE
                --             write_enable    <= '0';
                --             output_enable   <= '0';
                --             chip_enable     <= '1';
                --             case (st_sector_erasing) is     -- set address and data according to current sequence state
                --                 when E1_SEQ0 =>
                --                     address_out_r   <= erase_addr_first;
                --                     dq_data_out_r   <= erase_data_first;
                --                 when E1_SEQ1 =>
                --                     address_out_r   <= erase_addr_second;
                --                     dq_data_out_r   <= erase_data_second;
                --                 when E1_SEQ2 =>
                --                     address_out_r   <= erase_addr_third;
                --                     dq_data_out_r   <= erase_data_third;
                --                 when E1_SEQ3 =>
                --                     address_out_r   <= erase_addr_fourth;
                --                     dq_data_out_r   <= erase_data_fourth;
                --                 when E1_SEQ4 =>
                --                     address_out_r   <= erase_addr_fifth;
                --                     dq_data_out_r   <= erase_data_fifth;
                --                 when E1_SEQ5 =>
                --                     address_out_r   <= address_wr_r;
                --                     dq_data_out_r   <= erase_data_sector; -- sector erase command
                --                 when others =>
                --                     null; -- shouldn't happen, but just in case
                --             end case;
                --         elsif (t_EX = 35/MAIN_CLK_NS + 1) then  -- after 35 ns of setup time, set WE
                --             write_enable    <= '1';
                --             output_enable   <= '0';
                --             chip_enable     <= '1';
                --         elsif (t_EX = 70/MAIN_CLK_NS + 1) then  -- after 70 ns of WE time, clear WE and CE, set state for next command
                --             write_enable    <= '0';
                --             output_enable   <= '0';
                --             chip_enable     <= '0';
                --             case (st_sector_erasing) is    -- set new sequence state
                --                 when E1_SEQ0 =>
                --                     st_sector_erasing  <= E1_SEQ1;
                --                 when E1_SEQ1 =>
                --                     st_sector_erasing  <= E1_SEQ2;
                --                 when E1_SEQ2 =>
                --                     st_sector_erasing  <= E1_SEQ3;
                --                 when E1_SEQ3 =>
                --                     st_sector_erasing  <= E1_SEQ4;
                --                 when E1_SEQ4 =>
                --                     st_sector_erasing  <= E1_SEQ5;
                --                 when E1_SEQ5 =>
                --                     st_sector_erasing  <= E1_WAIT;
                --                 when others =>
                --                     null; -- shouldn't happen, but just in case
                --             end case;
                --         end if;
                --     else    -- state is waiting, so wait for the "sector erase" cycle to complete - typical timing is ~1 second
                --         if (t_WPR > (90/MAIN_CLK_NS)) then        -- after 90 ns, poll the BY_n signal forever until it goes low
                --             if (BY_n = '1') then                  -- when RY/BY# = 1, write is complete
                --                 programming_error       <= '0';
                --                 st_main                 <= ST_IDLE;
                --             end if; 
                --         else
                --             t_WPR	<= t_WPR + 1;                 -- only increment the timer until RY/BY# is ready
                --         end if;
                --     end if;
            end case;

        end if;

    end process;

end architecture;
