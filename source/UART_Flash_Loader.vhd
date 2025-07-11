library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_flash_loader is
    generic (
        FIXED_ADDR_TOP : std_logic_vector(5 downto 0) := "000000"  -- upper 6 flash-address bits
    );
    port (
        CLK        : in  std_logic;  -- assumes system clock (50 MHz)
        RST        : in  std_logic;
        -- UART interface
        RX_DATA    : in std_logic_vector(7 downto 0);           -- byte received from UART
        RX_READY   : in std_logic;                              -- strobed when a byte is ready to be read from UART

        TX_DATA    : out std_logic_vector(7 downto 0);          -- data to be sent through UART
        TX_LOAD    : out std_logic;                             -- strobe to load data into UART transmitter  
        TX_BUSY    : in std_logic;                              -- indicates if UART transmitter is busy
        --  Flash-controller interface  (write/erase-only path shown)
        FLASH_RDY  : in  std_logic;                             -- goes low while flash is busy
        ADDR_OUT   : out std_logic_vector(21 downto 0);         -- address for next word
        DATA_OUT   : out std_logic_vector(15 downto 0);         -- data word
        WR_OUT     : out std_logic;                             -- 1-clk pulse to start write
        ERASE_OUT  : out std_logic_vector(1 downto 0);          -- 1-clk pulse to start flash erase
        -- Indicator Flags
        ACTIVITY   : out std_logic;                             -- activity indicator
        COMPLETED  : out std_logic                              -- indicates that the last transfer is complete
    );
end uart_flash_loader;

architecture behavioral of uart_flash_loader is
    --  CONSTANTS
    constant C_STAR : std_logic_vector(7 downto 0) := x"2A";  -- '*'
    constant C_BANG : std_logic_vector(7 downto 0) := x"21";  -- '!'
    constant C_QUES : std_logic_vector(7 downto 0) := x"3F";  -- '?'

    --  PROTOCOL state
    type proto_fsm is (
        WAIT_START, ACK_UPLOAD, ACK_ERASE,
        HDR_0, HDR_1, HDR_2, HDR_3,
        LOAD_L, LOAD_H,
        ERASE_FLASH, WAIT_ERASE,
        WRITE_FLASH, WAIT_FLASH,
        NEXT_ADDRESS,
        ACK_DONE
    );
    signal p_state     : proto_fsm := WAIT_START;                   -- start in WAIT_START state

    signal address     : std_logic_vector(15 downto 0);             -- lower 16 bits of address to write to
    signal write_len   : unsigned(16 downto 0) := (others => '0');                     -- number of bytes to recieve

    signal bytes_seen  : unsigned(16 downto 0) := (others => '0');  -- number of bytes recieved so far
    signal word_buf    : std_logic_vector(15 downto 0);             -- buffer for the word to write to flash

    signal activity_flasher : integer range 0 to (50_000_000) := 0; -- counter to flash activity indicator during flash chip erase
   

begin
    -- flicker activity when the process is running, show completed when process is over and ready for next session
    ACTIVITY <= '0' when (activity_flasher < 25_000_000) else '1';
    COMPLETED <= '1' when (p_state = ACK_DONE or p_state = WAIT_START) else '0';
	 
	 -- wire ADDR_OUT, DATA_OUT, WR_OUT and ERASE_OUT connections
    ADDR_OUT  <= FIXED_ADDR_TOP & address;                      -- set address to write to
    DATA_OUT  <= word_buf;                                      -- set data to write
   
    WR_OUT    <= '1' when p_state = WRITE_FLASH else '0';       -- strobe WR_OUT during the WRITE_FLASH state
    ERASE_OUT <= "01" when p_state = ERASE_FLASH else "00";     -- strobe ERASE_OUT (to chip erase) during the ERASE_FLASH state
	
    --  State machine to implement transfer protocol
    process(CLK)
    begin
        if rising_edge(CLK) then
				TX_LOAD <= '0'; -- default TX_LOAD to '0'
				
            if RST = '1' then
                p_state <= WAIT_START;
            else
                case (p_state) is

    --  WAIT_START: Wait for '*' or '?' to be recieved from UART
                    when WAIT_START =>                                      -- wait for RX_ready and rx_byte is '*'				 
                        if RX_READY = '1' then
                            if RX_DATA = C_STAR then
                                p_state <= ACK_UPLOAD;                      -- received '*', acknowledge by sending '!' and starting upload
                            elsif RX_DATA = C_QUES then
                                p_state <= ACK_ERASE;                       -- received '?', acknowledge by sending '!' and starting erase
                            end if;
                        end if;

    --  ACK_UPLOAD: Acknowledge the start of a new upload session with '!'
                    when ACK_UPLOAD =>
                        if TX_BUSY = '0' then
								    TX_DATA <=  C_BANG;
                            TX_LOAD <= '1';                             -- strobe load signal (TX_DATA set above)
                            p_state <= HDR_0;                               -- start header read
                        end if;

    -- ACK_ERASE: Acknowledge the start of a new erase session with '!'
                    when ACK_ERASE =>
                        if TX_BUSY = '0' then
								    TX_DATA <= C_BANG;
                            TX_LOAD <= '1';                                 -- strobe load signal (TX_DATA set above)
                            p_state <= ERASE_FLASH;                          -- start erase
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

    -- WRITE_FLASH: write the word to flash at the current address
                    when WRITE_FLASH =>
                        if FLASH_RDY = '1' then
                            p_state   <= WAIT_FLASH;                        -- move to next state to wait for flash to finish writing
                        end if;

    -- WAIT_FLASH: wait for flash to be ready after it has written the word
                    when WAIT_FLASH =>
                        if FLASH_RDY = '1' then                             -- wait for flash idle
                            p_state <= NEXT_ADDRESS;    							 -- move to next state to notify that flash has been written                    
                        end if;
								
    -- NEXT_ADDRESS: update address and byte counters, and check for end of data
                    when NEXT_ADDRESS =>
                        address     <= std_logic_vector(unsigned(address) + 1);     -- increment address by 1 (next word)
                        bytes_seen  <= bytes_seen + 2;                              -- increment byte counter by 2 (one word = 2 bytes)

							   if bytes_seen + 2 >= write_len then                 -- check if all data has been written
                            p_state <= ACK_DONE;                            -- if so, move to next state to acknowledge completion
                            bytes_seen <= (others => '0');                  -- and clear byte counter
                        else
                           p_state <= LOAD_H;                              -- otherwise, fetch next word
                    end if;
						  
	-- ERASE_FLASH: send the command to erase the entire flash card
                    when ERASE_FLASH =>
                        if FLASH_RDY = '1' then
                            p_state <= WAIT_ERASE;                          -- move to the next state and wait for flash to finish erasing
                        end if;

	-- WAIT_ERASE: wait for flash to be ready after it erases the chip - increment counter so ACTIVITY light flashes at 1 Hz
                    when WAIT_ERASE =>
                        activity_flasher <= activity_flasher + 1;           -- increment activity counter, > 25_000_000 == ACTIVITY on

                        if activity_flasher = 50_000_000 then
                            activity_flasher <= 0;                          -- reset activity flasher at 50_000_000
                        end if;

                        if FLASH_RDY = '1' then                             -- wait for flash idle
                            activity_flasher <= 0;                          -- reset the activity flasher counter
                            p_state <= ACK_DONE;                            -- move to next state to acknowledge completion
                        end if;

    --  ACK_DONE: send acknowledgement and reset state to wait for next upload
                    when ACK_DONE =>
                        if TX_BUSY = '0' then                               -- wait until UART is not busy to transmit
								    TX_DATA <=  C_STAR;
                            TX_LOAD <= '1';                                 -- strobe tx_load to transmit data
                            p_state <= WAIT_START;                           -- move to next state - ready for next session
                        end if;
                end case;
            end if;
        end if;
    end process;
end behavioral;