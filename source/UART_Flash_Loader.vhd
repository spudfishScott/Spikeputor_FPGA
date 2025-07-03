library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_flash_loader is
    generic (
        FIXED_ADDR_TOP : std_logic_vector(5 downto 0) := "000000"  -- upper 6 flash-address bits
    );
    port (
        CLK        : in  std_logic;  -- 50 MHz
        RST        : in  std_logic;
        -- UART interface
        RX_DATA    : in std_logic_vector(7 downto 0);           -- byte received from UART
        RX_READY   : in std_logic;                              -- strobed when a byte is ready to be read from UART

        TX_DATA    : out std_logic_vector(7 downto 0);          -- data to be sent through UART
        TX_LOAD    : out std_logic;                             -- strobe to load data into UART transmitter  
        TX_BUSY    : in std_logic;                              -- indicates if UART transmitter is busy
        --  Flash-controller interface  (write-only path shown)
        FLASH_RDY  : in  std_logic;                             -- goes low while flash is busy
        ADDR_OUT   : out std_logic_vector(21 downto 0);         -- address for next word
        DATA_OUT   : out std_logic_vector(15 downto 0);         -- data word
        WR_OUT     : out std_logic;                             -- 1-clk pulse to start write
        -- Indicator Flags
        ACTIVITY   : out std_logic;                             -- activity indicator
        COMPLETED  : out std_logic                              -- indicates that the last transfer is complete
    );
end uart_flash_loader;

architecture behavioral of uart_flash_loader is
    --  CONSTANTS
    constant C_STAR : std_logic_vector(7 downto 0) := x"2A";  -- '*'
    constant C_BANG : std_logic_vector(7 downto 0) := x"21";  -- '!'

    --  PROTOCOL state
    type proto_fsm is (
        WAIT_STAR, ACK_START,
        HDR_0, HDR_1, HDR_2, HDR_3,
        LOAD_L, LOAD_H,
        WRITE_FLASH, NEXT_ADDRESS,
        ACK_DONE
    );
    signal p_state     : proto_fsm := WAIT_STAR;

    signal address     : std_logic_vector(21 downto 0); -- address to write to (upper 6 bits fixed, lower 16 bits from header)
    signal write_len   : unsigned(15 downto 0);         -- number of bytes to recieve

    signal bytes_seen  : unsigned(15 downto 0);         -- number of bytes recieved so far
    signal word_buf    : std_logic_vector(15 downto 0); -- buffer for the word to write to flash
    signal activity_conn: std_logic := '0';             -- activity indicator connection
   

begin
    ACTIVITY <= activity_conn;  -- connect activity indicator to output

    --  State machine to implement transfer protocol
    process(CLK)
    begin
        if rising_edge(CLK) then
            -- defaults each cycle - asserting these signals will last one clock cycle maximum
            WR_OUT    <= '0';
            TX_LOAD   <= '0';

            if RST = '1' then
                activity_conn <= '0';                                       -- reset activity indicator
					 COMPLETED <= '0';
                p_state    <= WAIT_STAR;
                bytes_seen <= (others => '0');
            else
                case (p_state) is

    --  WAIT_STAR: Wait for '*' to be recieved from UART
                    when WAIT_STAR =>                                       -- wait for RX_ready and rx_byte is '*'
                        if RX_READY = '1' and RX_DATA = C_STAR then
								    activity_conn <= '1';
                            COMPLETED <= '0';                               -- reset completed flag
                            p_state   <= ACK_START;                         -- received '*', acknowledge by sending '!'
                        end if;

    --  ACK_START: Acknowledge the start of a new session with '!'
                    when ACK_START =>
                        if TX_BUSY = '0' then
                            TX_DATA <= C_BANG;
                            TX_LOAD <= '1';
                            p_state <= HDR_0;                               -- start header read
                        end if;

    --  HDR_x: Read the 4 byte header (address, length)
                    when HDR_0 =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get high byte of address
                            address(15 downto 8) <= RX_DATA;                -- store high byte of address
                            p_state <= HDR_1;                               -- move to next header read state
                        end if;

                    when HDR_1 =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get low byte of address
                            address(7 downto 0) <= RX_DATA;                 -- store low byte of address
                            p_state <= HDR_2;                               -- move to next header read state
                        end if;

                    when HDR_2 =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get high byte of length of data
                            write_len(15 downto 8) <= unsigned(RX_DATA);    -- store high byte of length
                            p_state <= HDR_3;                               -- move to next header read state
                        end if;

                    when HDR_3 =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get low byte of length of data
                            write_len(7 downto 0) <= unsigned(RX_DATA);     -- store low byte of length
                            bytes_seen  <= (others => '0');                 -- reset byte counter
                            address(21 downto 16) <= FIXED_ADDR_TOP;        -- set next address to write to (upper 6 bits fixed, lower 16 bits from header)
                            p_state <= LOAD_H;                              -- move to next state to load first word
                        end if;

    --  LOAD_x: read in two bytes of data to make the word to write to flash
                    when LOAD_H =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get high byte of word
                            word_buf(15 downto 8) <= RX_DATA;               -- store high byte of word
                            p_state  <= LOAD_L;                             -- move to next state to load low byte
                        end if;

                    when LOAD_L =>
                        if RX_READY = '1' then                              -- wait for RX_ready to get low byte of word
                            word_buf(7 downto 0) <= RX_DATA;                -- store full word from byte_buf & low byte
                            p_state  <= WRITE_FLASH;                        -- move to next state to wait for flash to be ready to write
                        end if;
    -- WRITE_FLASH: wait for flash to be ready and write the word to flash at the current address
                    when WRITE_FLASH =>
                        if FLASH_RDY = '1' then                             -- wait for flash idle → can assert WE
                            ADDR_OUT  <= address;                           -- set address to write to
                            DATA_OUT  <= word_buf;                          -- set data to write
                            WR_OUT    <= '1';                               -- assert write enable signal for one clock cycle
                            p_state   <= NEXT_ADDRESS;                      -- move to next state to update counters and check if all data recieved
                        end if;

    -- NEXT_ADDRESS: update address and byte counters, and check for end of data
                    when NEXT_ADDRESS =>
                        activity_conn <= not activity_conn;                         -- toggle activity indicator to show progress
                        address     <= std_logic_vector(unsigned(address) + 1);     -- increment address by 1 (next word)
                        bytes_seen  <= bytes_seen + 2;                              -- increment byte counter by 2 (one word = 2 bytes)

                        if bytes_seen + 2 >= write_len then                         -- check if all data has been written
                            p_state <= ACK_DONE;                                    -- if so, move to next state to acknowledge completion
                        else
                            p_state <= LOAD_H;                                      -- otherwise, fetch next word
                    end if;

    --  ACK_DONE: send acknowledgement and reset state to wait for next upload
                    when ACK_DONE =>
                        if TX_BUSY = '0' then                                       -- wait until UART is not busy to transmit
                            TX_DATA <= C_STAR;                                      -- send '*' to acknowledge completion
                            TX_LOAD <= '1';                                         -- strobe tx_load to transmit data
                            COMPLETED <= '1';                                       -- set completed flag to indicate transfer is done
                            p_state <= WAIT_STAR;                                   -- move to next state - ready for next session
                        end if;
                end case;
            end if;
        end if;
    end process;
end behavioral;