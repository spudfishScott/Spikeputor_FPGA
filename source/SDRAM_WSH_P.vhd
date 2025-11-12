-- From ChatGPT
-- ======================= Wishbone SIMPLE (WORD-addressed) ====================
-- Classic handshake, 16-bit only, no SEL, ADR is WORD-addressed (A0 omitted).
-- If your upstream Wishbone is byte-addressed, adapt by shifting right by 1.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_WSH_P is
  port (
    -- SYSCON inputs
    CLK         : in std_logic;
    RST_I       : in std_logic;

    -- Wishbone signals
    -- handshaking signals
    WBS_CYC_I   : in std_logic;
    WBS_STB_I   : in std_logic;
    WBS_ACK_O   : out std_logic;

    -- memory read/write signals
    WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- lsb is ignored, but it is still part of the address bus
    WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
    WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
    WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing, when low, master is reading

    -- SDRAM pins
    DRAM_CLK     : out std_logic;
    DRAM_CKE     : out std_logic;
    DRAM_CS_N    : out std_logic;
    DRAM_RAS_N   : out std_logic;
    DRAM_CAS_N   : out std_logic;
    DRAM_WE_N    : out std_logic;
    DRAM_BA_0    : out std_logic;
    DRAM_BA_1    : out std_logic;
    DRAM_ADDR    : out std_logic_vector(11 downto 0);
    DRAM_DQ      : inout std_logic_vector(15 downto 0);
    DRAM_UDQM    : out std_logic;
    DRAM_LDQM    : out std_logic
  );
end SDRAM_WSH_P;

architecture rtl of SDRAM_WSH_P is
    signal c_req    : std_logic := '0';
    signal c_we     : std_logic := '0';
    signal c_busy   : std_logic := '0';
    signal c_rvalid : std_logic := '0';
    signal c_addr   : std_logic_vector(21 downto 0) := (others=>'0');
    signal c_wdata  : std_logic_vector(15 downto 0) := (others=>'0');
    signal c_rdata  : std_logic_vector(15 downto 0);

    type st_t is (IDLE, ISSUE, WAIT_RD, WAIT_WR);
    signal st    : st_t := IDLE;
    signal ack   : std_logic := '0';
    signal dat_r : std_logic_vector(15 downto 0) := (others=>'0');

begin
    WBS_ACK_O      <= ack AND WBS_CYC_I AND WBS_STB_I;
    WBS_DATA_O     <= dat_r;

    SDRAM_core : entity work.SDRAM
    port map (
        -- Control signals
        CLK          => CLK,
        RST_N        => not RST_I,
        REQ          => c_req,
        WE           => c_we,
        ADDR         => c_addr,
        WDATA        => c_wdata,
        BUSY         => c_busy,
        RDATA        => c_rdata,
        RVALID       => c_rvalid,

        -- DRAM pins - passthrough
        DRAM_CLK     => DRAM_CLK,
        DRAM_CKE     => DRAM_CKE,
        DRAM_CS_N    => DRAM_CS_N,
        DRAM_RAS_N   => DRAM_RAS_N,
        DRAM_CAS_N   => DRAM_CAS_N,
        DRAM_WE_N    => DRAM_WE_N,
        DRAM_BA_0    => DRAM_BA_0,
        DRAM_BA_1    => DRAM_BA_1,
        DRAM_ADDR    => DRAM_ADDR,
        DRAM_DQ      => DRAM_DQ,
        DRAM_UDQM    => DRAM_UDQM,
        DRAM_LDQM    => DRAM_LDQM
    );

    process(CLK) is 
    begin

        if rising_edge(CLK) then
            c_req <= '0';   -- default req and ack are 0 each clock cycle
            ack   <= '0';

            if RST_I = '1' then -- return to IDLE state and clear output on reset
                st    <= IDLE; 
                dat_r <= (others=>'0');
            else
                case st is
                    when IDLE =>
                        if (WBS_CYC_I ='1' AND WBS_STB_I = '1') then    -- new transaction requested - set address, we, and data (if write)
                            c_addr  <= WBS_ADDR_I(22 downto 1);     -- word-addressed, ignore msb (ROM/RAM selector) and lsb (byte offset)
                            c_we    <= WBS_WE_I;
                            c_wdata <= WBS_DATA_I;
                            st      <= ISSUE;                       -- proceed to ISSUE state, otherwise stay in IDLE state
                        end if;

                    when ISSUE =>
                        if c_busy = '0' then    -- only act if SDRAM controller ready for new request, otherwise stay in ISSUE state
                            c_req <= '1';   -- assert request
                            if WBS_WE_I = '1' then
                                st <= WAIT_WR;  -- wait for write to be finished (c_busy = '0' again)
                            else
                                st <= WAIT_RD;  -- wait for read data to be valid (c_rvalid = '1') 
                            end if;
                        end if;

                    when WAIT_RD =>             -- wait for READ to complete (read data is valid)
                        if c_rvalid = '1' then
                            dat_r <= c_rdata;   -- latch in read data
                            ack   <= '1';       -- assert ack signal
                            st    <= IDLE;      -- go back to IDLE state
                        end if;                 -- stay in WAIT_RD until data is valid

                    when WAIT_WR =>
                        if c_busy = '0' then    -- wait for WRITE to complete
                            ack <= '1';         -- assert ack signal 
                            st  <= IDLE;        -- go back to IDLE state
                        end if;                 -- stay in WAIT_WR until write is done

                    when others =>
                        st <= IDLE;             -- should never happen, go to IDLE
                end case;
            end if;
        end if;
  end process;

end architecture;
