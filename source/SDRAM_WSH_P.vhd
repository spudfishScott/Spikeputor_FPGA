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
    signal c_busy   : std_logic := '0';
    signal c_valid : std_logic := '0';

    signal c_we     : std_logic := '0';
    signal c_addr   : std_logic_vector(21 downto 0) := (others=>'0');
    signal c_wdata  : std_logic_vector(15 downto 0) := (others=>'0');
    signal c_rdata  : std_logic_vector(15 downto 0) := (others=>'0');

    type st_t is (IDLE, ISSUE, WAIT_VALID, CLEAR);
    signal st    : st_t := IDLE;
    signal ack   : std_logic := '0';
    signal dat_r : std_logic_vector(15 downto 0) := (others=>'0');

    signal reset_n : std_logic;

begin

    SDRAM_core : entity work.SDRAM
    port map (
        -- Control signals
        CLK          => CLK,
        RST_N        => reset_n,
        REQ          => c_req,
        WE           => c_we,
        ADDR         => c_addr,
        WDATA        => c_wdata,
        BUSY         => c_busy,
        RDATA        => c_rdata,
        VALID        => c_valid,

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

    -- output to Wishbone interface
    WBS_ACK_O      <= ack AND WBS_CYC_I AND WBS_STB_I;
    WBS_DATA_O     <= dat_r;
    c_wdata        <= WBS_DATA_I;               -- data to write comes directly from Wishbone input
    c_addr         <= WBS_ADDR_I(22 downto 1);  -- word-addressed, ignore msb (ROM/RAM selector) and lsb (byte offset)
    reset_n        <= not RST_I;

    process(CLK) is 
    begin

        if rising_edge(CLK) then
            if RST_I = '1' then -- return to IDLE state and clear output and control signals on reset
                ack <= '0';
                c_req <= '0';
                dat_r <= (others=>'0');
                st    <= IDLE; 
            else
                case st is
                    when IDLE =>
                        if (WBS_CYC_I ='1' AND WBS_STB_I = '1' AND c_busy = '0') then    -- new transaction requested - begin only if SDRAM controller is ready
                            c_we    <= WBS_WE_I;                    -- set write enable
                            c_req   <= '1';                         -- set request
                            st      <= WAIT_VALID;                  -- go to WAIT state, wait for valid result from RAM controller
                        else
                            st      <= IDLE;                       -- stay in IDLE state
                        end if;

                    when WAIT_VALID =>             -- wait for READ to complete (read data is valid)
                        c_req <= '0';           -- clear request signal
                        if (c_valid = '1' AND c_req = '0') then
                            dat_r <= c_rdata;   -- latch in read data
                            ack   <= '1';       -- assert ack signal
                            st    <= CLEAR;     -- done, clear ack signal when wishbone transaction ends, then go back to IDLE state
                        else
                            if (WBS_CYC_I = '0' OR WBS_STB_I = '0') then -- if master deasserts CYC or STB, abort read
                                ack <= '0';         -- clear ack signal
                                st  <= IDLE;        -- go back to IDLE state
                            else
                                st <= WAIT_VALID;  -- stay in wait state until data is valid
                            end if;
                        end if;

                    when CLEAR =>
                        if (WBS_CYC_I = '0' OR WBS_STB_I = '0') then -- wait until master deasserts CYC or STB
                            ack <= '0';             -- clear ack signal
                            st  <= IDLE;            -- go back to IDLE state
                        else
                            st <= CLEAR;            -- stay here until master deasserts CYC or STB
                        end if;

                    when others =>
                        ack <= '0';
                        st <= IDLE;         -- should never happen, go to IDLE
                end case;

                if (WBS_CYC_I = '0') then   -- Break cycle if master deasserts CYC
                    ack <= '0';
                    st <= IDLE;
                end if;

            end if;
        end if;
  end process;
end rtl;
