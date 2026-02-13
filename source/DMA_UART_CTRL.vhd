-- External interface to the Spiekputor DMA - mediated through a serial connection to the outside world
-- Serial connection can send one of the following commands:
    -- "*" - send back acknowledgement and wait
    -- ">" - send back acknowledgement, then recieve 5 byte header (3 bytes for address, 2 bytes for length (0 = 65536 bytes)), then send bytes, then send acknowledgement
    -- "<" - send back acknowledgement, then receive 5 byte header (3 bytes for address, 2 bytes for length (0 = 65536 bytes)), then receive bytes, then send acknowledgement
    -- "!" - send back acknowledgement, then reset the Spikeputor, then send another acknowledgement
-- Sends external signals:
    -- Start (begin the DMA transaction)
    -- Write/nRead (1 = write, 0 = read)
    -- Start Address (Full 24 Bit: msb = ROM/RAM for extended memory, bits 22->16 = segment number , bits 15->0 = address)
    -- Length - Number of bytes to read - 16 bits
    -- Write Data  - 16 bits sent to Spikeputor memory
    -- Read Data - 16 bits sent from Spikeputor memory
    -- Write Ready - ready to send the next word to the Spikeputor
    -- Read Ready - ready to send the next word from the Spikeputor

-- External Interface sends Start signal when Write/Read, Start Address, and Length are valid
-- If read, DMA gets first word, sets DATA_OUT, strobes READY_OUT, External Interface behaves as below
-- If write, External Interface gets first word, sets WR_DATA and strobes WR_READY, DMA behaves as below
-- Data transfer continues:
    -- For Read: 
        -- External Interface waits for RD_READY, then latches RD_DATA, sends out word through serial port, strobes WR_READY, then loops until LENGTH bytes have been recieved
        -- DMA reads memory, sets RD_DATA, waits for WR_READY, strobes RD_READY, then loops until LENGTH bytes have been sent
    -- For Write:
        -- External Interface gets next word of data, sets WR_DATA, waits for RD_READY, strobes WR_READY, then loops until LENGTH bytes have been sent
        -- DMA waits for WR_READY, then latches WR_DATA, writes it to Spikeputor, strobes RD_READY, loops until LENGTH bytes have been received

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_uart_ctrl is
    generic (
        CLK_FREQ   : Integer := 50_000_000;                      -- clock frequency - default = 50 MHz - read/write = 120 ns so baud rate >= 12 ns/bit = 120 ns/byte 
        BAUD_RATE  : Integer := 38400                            -- baud rate for UART communication - default = 38400 (where two bytes is transferred in the time it takes to read/write a word in Spikeputor memory)
    );
    port (
        CLK        : in  std_logic;
        RST        : in  std_logic;

        -- UART interface
        RX_SERIAL  : in std_logic;                              -- serial data input
        TX_SERIAL  : out std_logic;                             -- serial data output

        -- control signals (from DMA interface)
        START       : out std_logic;                            -- strobe to begin DMA transaction
        WR_RD       : out std_logic;                            -- Write / nRead (1 = Write to Spikeputor, 0 - Read from Spikeputor)
        ADDRESS     : out std_logic_vector(23 downto 0);        -- Start address (full 24 bit)
        LENGTH      : out std_logic_vector(15 downto 0);        -- Length in bytes to read/write
        WR_DATA     : out std_logic_vector(15 downto 0);        -- Data to send to Spikeputor
        WR_READY    : out std_logic;                            -- Strobed when WR_DATA is valid
        RD_DATA     : in std_logic_vector(15 downto 0);         -- Data to send from the Spikeputor
        RD_READY    : in std_logic;                             -- Strobed when RD_DATA is valid
        RESET_REQ   : out std_logic                             -- Request to reset the spikeputor
    );
end entity dma_uart_ctrl;

architecture behavioral of dma_uart_ctrl is

    signal uart_rx_data : std_logic_vector(7 downto 0);         -- Data received from UART
    signal uart_rx_rdy  : std_logic;                            -- Strobed when a byte is ready to be read from UART
    signal uart_tx_data : std_logic_vector(7 downto 0);         -- Data to send through UART
    signal uart_tx_load : std_logic;                            -- Strobe to load data into UART transmitter
    signal uart_tx_busy : std_logic;                            -- Indicates if UART transmitter is busy

    --  CONSTANTS
    constant C_READ  : std_logic_vector(7 downto 0) := x"3E";  -- '>' READ
    constant C_WRITE : std_logic_vector(7 downto 0) := x"3C";  -- '<' WRITE
    constant C_RESET : std_logic_vector(7 downto 0) := x"21";  -- '!' RESET
    constant C_ACK   : std_logic_vector(7 downto 0) := x"2A";  -- '*' ACK

    -- internal signals, including state machine
    -- include preliminary values for all to help with fitter getting stuck
    type proto_fsm is (
        WAIT_START, ACK_START, DMA_START,
        S_READ, S_WRITE, RESET,
        HDR_0, HDR_1, HDR_2, HDR_3, HDR_4,
        LOAD_L, SEND_L, SEND_H, SEND_DONE, WRITE_MEM, NEXT_TRANSFER
    );
    signal p_state     : proto_fsm := WAIT_START;                           -- current state: start in WAIT_START state
    signal cmd_state   : proto_fsm := WAIT_START;                           -- state to branch to from common code

    signal reset_start : std_logic := '0';                                  -- start a reset pulse

    signal addr_sig    : std_logic_vector(23 downto 0) := (others => '0');  -- full 24 bit address
    signal len_sig     : std_logic_vector(15 downto 0) := (others => '0');  -- number of bytes to transfer
    signal wr_rdy_sig  : std_logic := '0';                                  -- WR_READY strobe
    signal rd_rdy_sig  : std_logic := '0';                                  -- RD_READY latch

    signal byte_count  : unsigned(15 downto 0) := (others => '0');          -- number of bytes transferred so far
    signal word_buf    : std_logic_vector(15 downto 0) := (others => '0');  -- buffer for the word to transfer

begin

    uart_controller: entity work.UART
        generic map (
            CLK_SPEED  => CLK_FREQ,           -- Clock speed in Hz
            BAUD_RATE  => BAUD_RATE           -- Baud rate for UART communication   -- (where two bytes is transferred in the time it takes to read/write a word in Spikeputor memory)
        )
        port map (
            CLK        => CLK,
            RST        => RST,
            RX_SERIAL  => RX_SERIAL,      -- Serial data input
            RX_DATA    => uart_rx_data,   -- Received byte output
            RX_READY   => uart_rx_rdy,    -- Strobed when a byte has been received
            TX_SERIAL  => TX_SERIAL,      -- Serial data output
            TX_DATA    => uart_tx_data,   -- Data to send through UART
            TX_LOAD    => uart_tx_load,   -- Strobe to send a byte
            TX_BUSY    => uart_tx_busy    -- Indicates if the transmitter is busy
        );

    reset_pulse: entity work.PULSE_GEN
        generic map ( 
           PULSE_WIDTH => CLK_FREQ * 2 / 1000,   -- 0.002 seconds (ticks = clock freq * 0.002 seconds)
           RESET_LOW => false
        )
        port map (
            START_PULSE => reset_start,
            CLK_IN      => CLK,
            PULSE_OUT   => RESET_REQ
        );

    ADDRESS  <= addr_sig;
    LENGTH   <= len_sig;
    WR_RD    <= '1' when cmd_state = S_WRITE else '0';                       -- Set write flag on WRITE command only
    WR_READY <= wr_rdy_sig;
    WR_DATA  <= word_buf;

    --  State machine to implement transfer protocol
    process(CLK)
    begin
        if rising_edge(CLK) then

            uart_tx_load <= '0';        -- default uart_tx_load to '0' to strobe it
            START        <= '0';        -- default DMA START to '0' to strobe it
            wr_rdy_sig   <= '0';        -- default wr_rdy_sig to '0' to strobe it
            reset_start  <= '0';        -- default reset_start to '0' to strobe it

            if RD_READY = '1' then
                rd_rdy_sig <= '1';      -- latch RD_READY strobe when it comes in
            end if;

            if RST = '1' then
                p_state   <= WAIT_START;
                cmd_state <= WAIT_START;
            else

                case (p_state) is

    --  WAIT_START: Wait for command to be recieved from UART
                    when WAIT_START =>                                      -- wait for RX_ready and rx_byte is a valid command
                        rd_rdy_sig <= '0';
                        addr_sig  <= (others => '0');
                        len_sig   <= (others => '0');

                        if uart_rx_rdy = '1' then
                            p_state <= ACK_START;                           -- default - go to acknowledge
                            case (uart_rx_data) is                          -- see if the receieved byte is a cvalid command and route accordingly
                                when C_ACK =>                               -- received '*', simply acknowledge and come back here
                                    cmd_state <= WAIT_START;
                                when C_READ =>                              -- received '>', acknowledge and start READ
                                    cmd_state <= S_READ;
                                when C_WRITE =>                             -- receieved '<', acknowledge and start WRITE
                                    cmd_state <= S_WRITE;
                                when C_RESET =>                             -- received '!', acknowledge and start RESET
                                    cmd_state <= RESET;
                                when others =>
                                    p_state <= WAIT_START;                  -- ignore all invalid commands
                            end case;
                        end if;

    --  RESET: Hold the RESET_REQ line high for 2 milliseconds
                    when RESET =>
                        reset_start <= '1';                                 -- strobe the reset start to generate the long RESET_REQ pulse
                        p_state <= WAIT_START;

    --  ACK_START: Acknowledge the start and execute the command
                    when ACK_START =>
                        if uart_tx_busy = '0' then                          -- wait here until OK to send
                            uart_tx_data <= C_ACK;
                            uart_tx_load <= '1';                            -- strobe load signal
                            if cmd_state = S_READ OR cmd_state = S_WRITE then
                                p_state <= HDR_0;                           -- read header for READ and WRITE commands
                            else
                                p_state <= cmd_state;                       -- RESET or ACK
                            end if;
                        end if;

    --  HDR_x: Read the 5 byte header (address, length) - address is byte address (23 bits)
                    when HDR_0 =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get high byte of address
                            addr_sig(23 downto 16) <= uart_rx_data;         -- store high byte of address
                            p_state <= HDR_1;                               -- move to next header read state
                        end if;

                    when HDR_1 =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get next byte of address
                            addr_sig(15 downto 8) <= uart_rx_data;          -- store next byte of address
                            p_state <= HDR_2;                               -- move to next header read state
                        end if;

                    when HDR_2 =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get low byte of address
                            addr_sig(7 downto 0) <= uart_rx_data;           -- store low byte address
                            p_state <= HDR_3;                               -- move to next header read state
                        end if;

                    when HDR_3 =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get high byte of length of data
                            len_sig(15 downto 8) <= uart_rx_data;           -- store high byte of length
                            p_state <= HDR_4;                               -- move to next header read state
                        end if;

                    when HDR_4 =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get low byte of length of data
                            len_sig(7 downto 0) <= uart_rx_data;            -- store low byte of length
                            p_state <= DMA_START;                           -- move to next state to start DMA transaction
                        end if;

    -- DMA_START: strobe the START signal of the DMA module to begin DMA transaction
                    when DMA_START =>
                        START <= '1';                                       -- strobe the START signal
                        byte_count <= (others => '0');                      -- reset byte count
                        if cmd_state = S_WRITE then
                            rd_rdy_sig <= '1';                              -- on first word write, set RD_READY latch high already - DMA is ready to receive first word
                        end if;
                        p_state <= cmd_state;                               -- go to S_READ or S_WRITE

    -- S_READ: External Interface waits for RD_READY, then latches RD_DATA from DMA
                    when S_READ =>
                        if rd_rdy_sig = '1' then                            -- wait for RD_READY
                            word_buf <= RD_DATA;                            -- latch in the word
                            rd_rdy_sig <= '0';                              -- clear RD_READY latch
                            p_state <= SEND_H;                              -- move to next state to send the word
                        end if;

    -- SEND_x: send out two bytes of data through serial port
                    when SEND_H =>
                        if uart_tx_busy = '0' AND uart_tx_load = '0' then   -- wait here until OK to send
                            uart_tx_data <= word_buf(15 downto 8);          -- send high byte of word
                            uart_tx_load <= '1';                            -- strobe load signal
                            p_state <= SEND_L;                              -- send the next byte
                        end if;

                    when SEND_L =>
                        if uart_tx_busy = '0' AND uart_tx_load = '0' then   -- wait here until OK to send
                            uart_tx_data <= word_buf(7 downto 0);           -- send low byte of word
                            uart_tx_load <= '1';                            -- strobe load signal
                            p_state <= SEND_DONE;                           -- go to address increment loop
                        end if;

    -- SEND_DONE:  strobes WR_READY, then loops until LENGTH bytes have been recieved
                    when SEND_DONE =>
                        if uart_tx_busy = '0' AND uart_tx_load = '0' then   -- wait here until UART has sent the byte
                            wr_rdy_sig <= '1';                              -- strobe WR_READY
                            p_state <= NEXT_TRANSFER;                        -- go to address increment loop
                        end if;

    -- S_WRITE: External interface gets first word from serial interface, sets WR_DATA and strobes WR_READY to send to DMA, then increments loop
    --          On subsequent iterations, waits for RD_READY before strobing WR_READY
                    when S_WRITE =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get high byte of word
                            word_buf(15 downto 8) <= uart_rx_data;          -- store high byte of word
                            p_state  <= LOAD_L;                             -- move to next state to load low byte
                        end if;

                    when LOAD_L =>
                        if uart_rx_rdy = '1' then                           -- wait for RX_ready to get low byte of word
                            word_buf(7 downto 0) <= uart_rx_data;           -- store full word from byte_buf & low byte
                            p_state  <= WRITE_MEM;                          -- move to next state to wait for flash to be ready to write
                        end if;
                    
                    when WRITE_MEM =>                                       -- WRITE_DATA now good
                        if rd_rdy_sig = '1' then                            -- strobe WR_READY if RD_READY has been strobed since last clear (will be high on first word write)
                            wr_rdy_sig <= '1';                              -- strobe WR_READY - send word to DMA
                            rd_rdy_sig <= '0';                              -- clear RD_READY for next write cycle
                            p_state <= NEXT_TRANSFER;                        -- go to address increment loop
                        end if;

    -- NEXT_TRANSFER: update byte counters, and check for end of data
                    when NEXT_TRANSFER =>
                        byte_count  <= byte_count + 2;                              -- increment byte counter by 2 (one word = 2 bytes)

                        -- check if all data has been written (len_sig = 0 for 65536 byte read, byte_count will roll over to 0 at 65536)
                        if (byte_count < unsigned(length_sig) - 2) OR (length_sig = 0 AND byte_count /= x"FFFE") then
                            p_state <= cmd_state;                                   -- if so, read or write next word
                        else
                            cmd_state <= WAIT_START;
                            p_state <= ACK_START;                                   -- if not, send ACK and go back to wait_start
                    end if;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;
end behavioral;

if (byte_count < unsigned(length_sig) - 2) OR (length_sig = 0 AND byte_count /= x"FFFE") then
                                current_state <= SENDING;   -- set up to send next word
                            else
                                current_state <= IDLE;      -- all done!
                            end if;