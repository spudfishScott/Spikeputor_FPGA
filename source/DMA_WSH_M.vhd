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
-- If read, DMA gets first word, sets DATA_OUT, strobes READY_OUT, External Interface behaves as below
-- If write, External Interface gets first word, sets DATA_IN strobes READY_IN, DMA behaves as below
-- Data transfer continues:
    -- For Read: 
        -- External Interface waits for READY_OUT, then latches DATA_OUT, sends out word, strobes READY_IN, then loops until LENGTH bytes have been recieved
        -- DMA reads memory, sets DATA_OUT, waits for READY_IN, strobes READY_OUT, then loops until LENGTH bytes have been sent
    -- For Write:
        -- External Interface gets next word of data, sets DATA_IN, waits for READY_OUT, strobes READY_IN, then loops until LENGTH bytes have been sent
        -- DMA waits for READY_IN, then latches DATA_IN, writes it to Spikeputor, strobes READY_OUT, loops until LENGTH bytes have been received

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity DMA_WSH_M is
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

        -- control signals (from UART interface)
        START       : in std_logic;                         -- begin DMA transaction
        WR_RD       : in std_logic;                         -- Write / nRead (1 = Write to Spikeputor, 0 - Read from Spikeputor)
        ADDRESS     : in std_logic_vector(23 downto 0);     -- Start address (full 24 bit)
        LENGTH      : in std_logic_vector(15 downto 0);     -- Length in bytes to read/write
        DATA_IN     : in std_logic_vector(15 downto 0);     -- Data to send to Spikeputor
        READY_IN    : in std_logic;                         -- Strobed when DATA_IN is valid
        DATA_OUT    : out std_logic_vector(15 downto 0);    -- Data to send from the Spikeputor
        READY_OUT   : out std_logic;                        -- Strobed when DATA_OUT is valid
        RESET_REQ   : in std_logic;                         -- Request from external interface to reset the spikeputor
        
        RST_O       : out std_logic                         -- DMA signal to reset the Spikeputor

    );
end DMA_WSH_M;

architecture Behavioral of DMA_WSH_M is
    type CTRL_STATE is (
        IDLE, SEND_START, SEND_OUT, SEND_WAIT, SENDING, RECV_START, RECEIVING
    );
    signal current_state : CTRL_STATE := IDLE;              -- start in WAIT_START state

    signal rst_sig        : std_logic := '0';               -- signal to reset the spikeputor
    signal stb_sig        : std_logic := '0';               -- WBS_STB_O signal

    signal current_addr   : std_logic_vector(23 downto 0) := (others => '0');   -- current spikeputor address
    signal length_sig     : std_logic_vector(15 downto 0) := (others => '0');   -- length in bytes to transfer
    signal w_sig          : std_logic := '0';                                   -- read/write signal
    signal byte_count     : integer range 0 to 65535 := 0;                      -- current count of bytes sent or received
    signal rdy_in_sig     : std_logic;                                          -- latched ready in signal

    signal data_out_sig   : std_logic_vector(15 downto 0) := (others => '0');   -- latch to hold data out
    signal data_in_sig    : std_logic_vector(15 downto 0) := (others => '0');   -- latch to hold data in

begin
    clock : process(CLK) is
    begin

        WBS_ADDR_O   <= current_addr;       -- set up bus address
        WBS_DATA_O   <= data_in_sig;        -- set up data to write to memory
        WBS_WE_O     <= w_sig;              -- write flag
        WBS_STB_O    <= stb_sig;            -- strobe signal

        DATA_OUT     <= data_out_sig;       -- data out
        RST_O        <= rst_sig;            -- reset signal

        if rising_edge(CLK) then
            if RST_I = '1' then
                current_state <= IDLE;            -- return to IDLE state
                byte_count    <= 0;               -- reset byte conuter
                rst_sig       <= '0';             -- clear reset signal
                w_sig         <= '0';             -- clear write signal

                WBS_CYC_O     <= '0';                -- clear wishbone transactions
                WBS_STB_O     <= '0';

            else
                READY_OUT <= '0';           -- default READY_OUT is '0'

                if RESET_REQ = '1' then
                    rst_sig   <= '1';
                    WBS_CYC_O <= '0';                -- clear wishbone transactions
                    stb_sig   <= '0';
                    w_sig     <= '0';
                    current_state <= IDLE;           -- go back to IDLE state

                else
                    case (current_state) is
                        when IDLE =>                -- wait for a DMA transaction request, request bus and wait for bus to be granted
                            WBS_CYC_O <= '0';           -- shut down wishbone cycle and wait until a new DMA transaction is requested
                            stb_sig   <= '0';

                            if (START = '1') then       -- START DMA transaction
                                current_addr <= ADDRESS;    -- latch in starting address
                                length_sig   <= LENGTH;     -- latch in length
                                w_sig        <= WR_RD;      -- latch in read/write signal
                                byte_count <= 0;            -- reset byte count
                                if (WR_RD = '0') then
                                    current_state <= SEND_START;        -- WR_RD = 0, dispatch to sending first word
                                else
                                    current_state <= RECV_START;        -- WR_RD = 1, dispatch to receiving loop
                                end if;
                            end if;

                        when SEND_START =>          -- wait for ACK to be 0, then start read transactions and wait for ack
                            if (WBS_ACK_I = '0') then
                                WBS_CYC_O <= '1';       -- start wishbone cycle to read Spikeputor addresses
                                stb_sig   <= '1';       -- set wishbone strobe to read the first address
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been read
                                data_out_sig <= WBS_DATA_I;     -- latch in the data that was read
                                stb_sig <= '0';                 -- end this wishbone transaction
                                current_state <= SEND_OUT;
                            end if;

                        when SEND_OUT =>            -- strobe ready out, see if we're done looping
                            rdy_in_sig <= '0';              -- clear READY_IN latch, wait for it next step
                            READY_OUT <= '1';               -- strobe READY_OUT to tell External interface data is ready
                            byte_count <= byte_count + 2;                                   -- increment byte count
                            current_addr <= std_logic_vector(unsigned(current_addr) + 2);   -- increment current address
                            if (byte_count < to_integer(unsigned(length_sig)) - 2) then
                                current_state <= SENDING;   -- set up to send next word
                            else
                                current_state <= IDLE;      -- all done!
                            end if;

                        when SENDING =>             -- read memory, set DATA_OUT
                            if READY_IN = '1' then
                                rdy_in_sig <= '1';      -- capture READY_IN strobe even if we're waiting for wishbone
                            end if;
                            if (WBS_ACK_I = '0') then   -- wait for ACK to be low, then read next word
                                stb_sig <= '1';   -- set wishbone strobe to read the current address
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been read
                                data_out_sig <= WBS_DATA_I;     -- latch in the data that was read
                                stb_sig <= '0';                 -- end this wishbone transaction
                                if (rdy_in_sig = '1' OR READY_IN = '1') then
                                    current_state <= SEND_OUT;  -- external interface is ready to recieve the word, send it out
                                else
                                    current_state <= SEND_WAIT; -- otherwise wait for external interface to be ready
                                end if;
                            end if;

                        when SEND_WAIT =>
                            if (READY_IN = '1') then
                                current_state <= SEND_OUT;  -- external interface is ready to recieve the word, send it out
                            else
                                current_state <= SEND_WAIT; -- otherwise wait for external interface to be ready
                            end if;

                        when RECV_START =>          -- wait for READY_IN to get word to write to Spikeputor, then latches DATA_IN
                            if (READY_IN = '1') then
                                current_state <= RECEIVING;     -- external interface has sent a word, so receive it
                                data_in_sig <= DATA_IN;
                            else
                                current_state <= RECV_START;    -- otherwise wait for external interface to finish sending
                            end if;

                        when RECEIVING =>           -- writes data to Spikeputor, strobes READY_OUT, loops until LENGTH bytes have been received
                            if (WBS_ACK_I = '0') then
                                WBS_CYC_O <= '1';       -- start (or continue) wishbone cycle
                                stb_sig <= '1';         -- set wishbone strobe to write the data to the current address
                            elsif (WBS_ACK_I = '1' AND stb_sig = '1') then    -- memory has been written
                                stb_sig <= '0';         -- end this wishbone transaction
                                READY_OUT <= '1';       -- strobe READY_OUT to tell External interface data has been written
                                byte_count <= byte_count + 2;                                   -- increment byte count
                                current_addr <= std_logic_vector(unsigned(current_addr) + 2);   -- increment current address
                                if (byte_count < to_integer(unsigned(length_sig)) - 2) then
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
