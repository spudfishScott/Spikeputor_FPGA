-- A wishbone master interface for direct memory access tyo the Spikeputor
-- Recieves external signals:
    -- Start (begin the DMA transaction)
    -- Write/nRead (1 = write, 0 = read)
    -- Start Address (Full 24 Bit: msb = ROM/RAM for extended memory, bits 22->16 = segment number , bits 15->0 = address)
    -- Length - Number of bytes to read - 16 bits
    -- Data In  - 16 bits sent to Spikeputor memory
    -- Data Out - 16 bits sent from Spikeputor memory
    -- Ready In - ready to send the next word to the Spikeputor
    -- Ready Out - ready to send the next word from the Spikeputor
    -- Out Busy - sending data from the Spikeputor

-- External Interface sends Start signal when Write/Read, Start Address, and Length are valid

-- Data transfer continues:
    -- For Read: 
        -- External Interface waits for READY_OUT, then latches DATA_OUT, sends out word, strobes READY_IN, then loops until LENGTH bytes have been recieved
        -- DMA reads memory, sets DATA_OUT, waits for READY_IN (doesn't wait on first word), strobes READY_OUT, then loops until LENGTH bytes have been sent
    -- For Write:
        -- External Interface gets next word of data, sets DATA_IN, waits for READY_OUT, strobes READY_IN, then loops until LENGTH bytes have been sent
        -- DMA waits for READY_IN, then latches DATA_IN, writes it to Spikeputor, strobes READY_OUT, loops until LENGTH bytes have been received

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity DMA_WSH_M is
    generic ( 
        CLK_FREQ  : Integer := 50_000_000;                             -- clock frequency - default = 50 MHz
        BAUD_RATE : Integer := 38400                                  -- baud rate for UART communication - default = 38400
    );
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

        -- Wishbone signals for memory interface
        -- handshaking signals
        WBS_CYC_O   : out std_logic;
        WBS_STB_O   : out std_logic;
        WBS_ACK_I   : in std_logic;

        -- memory read/write signals
        WBS_ADDR_O  : out std_logic_vector(23 downto 0);    -- full 24 bit address
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to provider
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from provider
        WBS_WE_O    : out std_logic;                        -- write enable output - write when high, read when low

        RX_SERIAL   : in std_logic;                         -- external UART RX
        TX_SERIAL   : out std_logic;                        -- external UART TX
        RST_O       : out std_logic;                        -- DMA signal to reset the Spikeputor

        DEBUG_STATE  : out std_logic_vector(4 downto 0)     -- 5 bits to send current state information out for debugging
    );
end DMA_WSH_M;

architecture Behavioral of DMA_WSH_M is
    type CTRL_STATE is (
        IDLE, SEND_OUT, SEND_WAIT, SENDING, RECV_HALT, RECV_START, RECEIVING
    );
    signal current_state : CTRL_STATE := IDLE;              -- start in WAIT_START state

    signal rst_sig        : std_logic := '0';               -- signal to reset the spikeputor
    signal stb_sig        : std_logic := '0';               -- WBS_STB_O signal

    signal current_addr   : std_logic_vector(23 downto 0) := (others => '0');   -- current spikeputor address
    signal start_addr     : std_logic_vector(23 downto 0) := (others => '0');   -- starting address for this DMA transaction
    signal length_sig     : std_logic_vector(15 downto 0) := (others => '0');   -- length in bytes to transfer
    signal w_sig          : std_logic := '0';                                   -- read/write signal
    signal w_latch_sig    : std_logic := '0';                                   -- latched read/write signal for wishbone transaction
    signal byte_count     : unsigned(15 downto 0) := (others => '0');           -- current count of bytes sent or received, rolls to 0 after 65535
    signal rdy_in         : std_logic;                                          -- strobed when data is ready from external source
    signal rdy_in_sig     : std_logic;                                          -- latched ready in signal
    signal data_out_sig   : std_logic_vector(15 downto 0) := (others => '0');   -- latch to hold data out
    signal data_in_sig    : std_logic_vector(15 downto 0) := (others => '0');   -- data in from external source to be written to Spikeputor memory
    signal data_in_latch  : std_logic_vector(15 downto 0) := (others => '0');   -- latch to hold data in for wishbone transaction
    signal rdy_out        : std_logic;                                          -- strobed when data out is valid
    signal dma_start      : std_logic;                                          -- strobed to start DMA transaction
    signal halted_sig     : std_logic;                                          -- set high when SPikeputor is halted

begin

    UART_CTRL : entity work.DMA_UART_CTRL
        generic map ( 
            CLK_FREQ => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            CLK         => CLK,
            RST         => RST_I,

            RX_SERIAL   => RX_SERIAL,
            TX_SERIAL   => TX_SERIAL,

            START       => dma_start,                           -- strobe to begin DMA transaction
            WR_RD       => w_sig,                               -- Write / nRead (1 = Write to Spikeputor, 0 - Read from Spikeputor)
            ADDRESS     => start_addr,                          -- Start address (full 24 bit)
            LENGTH      => length_sig,                          -- Length in bytes to read/write
            WR_DATA     => data_in_sig,                         -- Data to send to Spikeputor
            WR_READY    => rdy_in,                              -- Strobed when WR_DATA is valid
            RD_DATA     => data_out_sig,                        -- Data to send from the Spikeputor
            RD_READY    => rdy_out,                             -- Strobed when RD_DATA is valid
            HALTED      => halted_sig,                          -- set when DMA has control of the bus (CPU is halted)
            RESET_REQ   => rst_sig,                             -- Request to reset the spikeputor
            DEBUG_STATE => DEBUG_STATE                          -- 5 bits to send current state information out
        );

    WBS_ADDR_O   <= current_addr;       -- set up bus address
    WBS_DATA_O   <= data_in_latch;      -- latched data to write to memory
    WBS_WE_O     <= w_latch_sig;        -- write flag
    WBS_STB_O    <= stb_sig;            -- strobe signal

    RST_O        <= rst_sig;            -- reset signal

    clock : process(CLK) is
    begin
        if rising_edge(CLK) then
            rdy_out <= '0';             -- default READY_OUT is '0' for strobing

            if RST_I = '1' then
                current_state <= IDLE;              -- return to IDLE state
                WBS_CYC_O   <= '0';         -- shut down wishbone cycle and wait until a new DMA transaction is requested
                stb_sig     <= '0';
                w_latch_sig <= '0';
                halted_sig  <= '0';
            else
                if rst_sig = '1' then
                    current_state <= IDLE;          -- return to IDLE state
                    WBS_CYC_O   <= '0';         -- shut down wishbone cycle and wait until a new DMA transaction is requested
                    stb_sig     <= '0';
                    w_latch_sig <= '0';
                    halted_sig  <= '0';
                else
                    case (current_state) is

                        when IDLE =>                -- wait for a DMA transaction request, request bus and wait for bus to be granted
                            WBS_CYC_O   <= '0';         -- shut down wishbone cycle and wait until a new DMA transaction is requested
                            stb_sig     <= '0';
                            w_latch_sig <= '0';
                            halted_sig  <= '0';

                            if (dma_start = '1') then   -- start DMA transaction
                                byte_count <= (others => '0');          -- reset byte count
                                current_addr <= start_addr;             -- set current address to start address
                                if (w_sig = '0') then                   -- Read Command
                                    rdy_in_sig <= '1';                      -- set ready in latch for first word to send to controller (Controller is by definition ready to receive because it sent start signal)
                                    current_state <= SENDING;               -- dispatch to reading and sending memory data
                                else
                                    w_latch_sig <= '1';                 -- latch the write signal for wishbone transactions
                                    current_state <= RECV_HALT;         -- Write Command - dispatch to receiving data from external interface and writing to memory
                                end if;
                            end if;

                        when SENDING =>             -- read memory, set DATA_OUT, if READY_IN has come in, go to SEND_OUT, otherwise go to SEND_WAIT
                            if rdy_in = '1' then
                                rdy_in_sig <= '1';      -- capture rdy_in strobe to avoid missing it if it comes while waiting for memory read to complete
                            end if;

                            if (WBS_ACK_I = '0') then   -- wait for ACK to be low, then read next word
                                WBS_CYC_O <= '1';           -- start (or continue) wishbone cycle
                                stb_sig <= '1';   -- set wishbone strobe to read the current address
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been read
                                halted_sig <= '1';              -- confirm Spikeputor is halted - external interface will send header recieved signal
                                data_out_sig <= WBS_DATA_I;     -- latch in the data that was read
                                stb_sig <= '0';                 -- end this wishbone transaction
                                if (halted_sig = '0') then
                                    current_state <= SENDING;               -- after Spikeputor halts, re-read the first address
                                else
                                    if (rdy_in_sig = '1' OR rdy_in = '1') then  -- if external interface is ready to recieve the word, send it out, otherwise wait for it to be ready
                                        current_state <= SEND_OUT;  -- external interface is ready to recieve the word, send it out
                                    else
                                        current_state <= SEND_WAIT; -- otherwise wait for external interface to be ready
                                    end if;
                                end if;
                            end if;

                        when SEND_WAIT =>
                            if (rdy_in = '1') then
                                current_state <= SEND_OUT;  -- external interface is ready to recieve the word, send it out
                            else
                                current_state <= SEND_WAIT; -- otherwise wait for external interface to be ready
                            end if;

                        when SEND_OUT =>                -- strobe ready out, see if we're done looping
                            rdy_in_sig <= '0';                          -- clear READY_IN latch, wait for it next step
                            rdy_out <= '1';                             -- strobe READY_OUT to tell External interface data is ready to be sent
                            byte_count <= byte_count + 2;               -- increment byte count
                            current_addr <= std_logic_vector(unsigned(current_addr) + 2);   -- increment current address
                            if (byte_count < unsigned(length_sig) - 2) OR (unsigned(length_sig) = 0 AND byte_count /= x"FFFE") then
                                current_state <= SENDING;   -- set up to send next word
                            else
                                current_state <= IDLE;      -- all done!
                            end if;

                        when RECV_HALT =>           -- wait until Spikpeutor is halted to begin to accept stream of incoming words to write
                            if (WBS_ACK_I) = '0' then   -- wait until ready to start wishbone cycle
                                WBS_CYC_O <= '1';       -- start wishbone cycle
                                stb_sig <= '1';
                                data_in_latch <= (others => '0');
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been written - this is a dummy write which will be overwritten next wishbone transaction
                                halted_sig <= '1';      -- confirm Spikeputor is halted - will cause header_reciviewd signal to be sent from external interface
                                stb_sig <= '0';         -- end this wishbone transaction
                                rdy_out <= '1';         -- strobe READY_OUT to tell External interface data has been written
                                current_state <= RECV_START;
                            end if;

                        when RECV_START =>          -- wait for READY_IN to get word to write to Spikeputor, data_in_sig is valid
                            if (rdy_in = '1') then
                                data_in_latch <= data_in_sig;   -- latch in the data to be written to memory
                                current_state <= RECEIVING;     -- external interface has sent a word, so receive it
                            else
                                current_state <= RECV_START;    -- otherwise wait for external interface to finish sending
                            end if;

                        when RECEIVING =>           -- writes data to Spikeputor, strobes READY_OUT, loops until LENGTH bytes have been received
                            if (WBS_ACK_I = '0') then
                                stb_sig <= '1';         -- set wishbone strobe to write the data to the current address
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been written
                                halted_sig <= '1';      -- confirm Spikeputor is halted
                                stb_sig <= '0';         -- end this wishbone transaction
                                rdy_out <= '1';         -- strobe READY_OUT to tell External interface data has been written
                                byte_count <= byte_count + 2;                                   -- increment byte count
                                current_addr <= std_logic_vector(unsigned(current_addr) + 2);   -- increment current address
                                if (byte_count < unsigned(length_sig) - 2) OR (unsigned(length_sig) = 0 AND byte_count /= x"FFFE") then
                                    current_state <= RECV_START;   -- set up to receive next word
                                else
                                    current_state <= IDLE;      -- all done!
                                end if;
                            end if;

                        when others =>
                            current_state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
