-- ###########################################################################
-- INITIAL code from ChatGPT, then modified and corrected
-- SDR SDRAM MINIMAL CONTROLLER @ 50 MHz (tCK = 20 ns)
-- Target: Zentel A3V6S40ETP-66 (4M x 16 x 4 banks), closed-page, BL=1, CL=2
-- Board: Terasic DE0 (Cyclone III).
--
-- Design goals:
--  * Single-beat accesses only (burst length 1) using auto-precharge (A10=1).
--  * No row/page tracking; each request is self-contained: ACT → RD/WR(AP) → done.
--  * Simple user-side handshake: req/we/addr/wdata/be  ↔ busy/rvalid/rdata.
--  * 50 MHz timing baked in (constants below). Adjust only if you change clocks.
--  * Clean, future-dev comments (why each step exists, not just how).
--
-- NOTE FOR FUTURE DEVELOPERS:
--  * If you move to a different clock, recompute the *_CYC constants from ns.
--  * If you enable bursts >1 or open-page policy, you'll need tRAS/tRC guards.
-- ###########################################################################


-- ###########################################################################
-- SIMPLIFIED VARIANT: 16-bit bus only, no byte enables (DQM permanently 0)
-- * Always full-word accesses (16 bits). No 8-bit writes/reads.
-- * DQM is tied low (00) so both bytes are always active.
-- ###########################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM is
    port (
        -- INPUTS
        CLK          : in  std_logic;              -- 50 MHz
        RST_N        : in  std_logic;              -- async, active-low
        REQ          : in  std_logic;              -- start transaction when not refreshing or completing previous command
        WE           : in  std_logic;              -- 1=write, 0=read
        ADDR         : in  std_logic_vector(21 downto 0); -- WORD address mapping - 22 bits = 4M word addresses (8 MB)
        WDATA        : in  std_logic_vector(15 downto 0);

        --OUTPUTS
        BUSY         : out std_logic;
        RDATA        : out std_logic_vector(15 downto 0);
        RVALID       : out std_logic;

        -- SDR SDRAM pins
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
end entity;

architecture rtl of SDRAM is
    -- Timing constants based on a 50 MHz system clock. Change if that changes.
    constant CAS_LATENCY  : integer := 2;
    constant tRCD_CYC     : integer := 2;
    constant tRP_CYC      : integer := 2;
    constant tMRD_CYC     : integer := 2;
    constant tWR_CYC      : integer := 2;
    constant tRFC_CYC     : integer := 4;
    constant REF_INTERVAL : integer := 781;

    constant MODE_REG     : std_logic_vector(11 downto 0) := "00000" & "010" & "0" & "001";  -- [11:7] - Burst Read/Write / [6:4] - CAS latency = 2 / [3] - sequential wrap type / [2:0] - Burst Length = 1

    type state_t is ( -- SDRAM state machine states
        ST_BOOT_WAIT, ST_PREALL, ST_AR, ST_tRFC, ST_LMR, ST_IDLE,
        ST_tRCD, ST_CASLAT, ST_WREC, ST_REF_WAIT
    );
    signal st : state_t := ST_BOOT_WAIT;

    -- address signals
    signal bank  : unsigned(1 downto 0);
    signal row   : unsigned(11 downto 0);
    signal col   : unsigned(7 downto 0);

    -- data output signals
    signal dq_out : std_logic_vector(15 downto 0) := (others=>'0');
    signal dq_oe  : std_logic := '0';

    -- timing signals
    signal ref_cnt     : integer := 0;
    signal ref_pending : std_logic := '0';
    signal timer       : integer := 0;
    signal ar_count    : integer := 0; -- counts 0..7 for 8 refresh commands

    begin
    DRAM_CLK <= CLK;  -- wire the system clock right into the DRAM clock

    -- split 22 bit address into components
    bank <= unsigned(ADDR(21 downto 20));
    row  <= unsigned(ADDR(19 downto 8));
    col  <= unsigned(ADDR(7 downto 0));

    -- Always full 16-bit transfers → DQM=00 (both bytes enabled)
    DRAM_UDQM <= '0';
    DRAM_LDQM <= '0';

    -- Handle tri-stated DQ
    DRAM_DQ  <= dq_out when dq_oe='1' else (others=>'Z');

    process(CLK)
    begin
        if rising_edge(clk) then
            if RST_N = '0' then     -- on reset, clear commands and counters, send to BOOT_WAIT state
                st          <= ST_BOOT_WAIT;
                timer       <= 1000;  -- wait 10000 cycles (200 us) after reset
                DRAM_CKE    <= '0';
                DRAM_CS_N   <= '1';
                DRAM_RAS_N  <= '1';
                DRAM_CAS_N  <= '1';
                DRAM_WE_N   <= '1';
                DRAM_BA_0   <= '0';
                DRAM_BA_1   <= '0';
                DRAM_ADDR   <= (others=>'0');
                dq_out      <= (others=>'0');
                dq_oe       <= '0';
                ref_cnt     <= 0;
                ref_pending <= '0';
                rvalid      <= '0';
                busy        <= '1';
            else
                -- Default to NOP each clock cycle
                DRAM_CS_N   <= '0';
                DRAM_RAS_N  <= '1';
                DRAM_CAS_N  <= '1';
                DRAM_WE_N   <= '1';
                DRAM_BA_0   <= bank(0);
                DRAM_BA_1   <= bank(1);
                DRAM_ADDR   <= (others => '0');
                rvalid      <= '0';                                               -- set rvalid flag to false
                busy        <= '1';                                               -- set busy flag true as a default

                -- refresh cadence (only count when idle to avoid drift)
                if st = ST_IDLE then
                    if ref_cnt >= REF_INTERVAL then 
                        ref_cnt     <= 0;
                        ref_pending <= '1';
                    else 
                        ref_cnt     <= ref_cnt + 1; 
                    end if;
                end if;

                case st is
                    when ST_BOOT_WAIT =>    -- count down timer after a reset - 10000 cycles
                        if timer > 0 then 
                            timer   <= timer - 1;
                        else 
                            timer   <= 2;   -- set delay for tRP, then execute precharge all
                            st      <= ST_PREALL; 
                        end if;

                    when ST_PREALL => 
                        if timer > 0 then
                            timer <= timer - 1;                  -- emit NOPs while timer runs
                        else
                            -- PRECHARGE ALL (A10=1) command
                            DRAM_CS_N  <= '0';
                            DRAM_RAS_N <= '0';
                            DRAM_CAS_N <= '1';
                            DRAM_WE_N  <= '0';
                            DRAM_BA_0  <= '0';
                            DRAM_BA_1  <= '0';
                            DRAM_ADDR  <= "100000000000";
                            timer      <= tRP_CYC;              -- auto refresh cycle timer
                            ar_count   <= 0;                    -- auto-refresh cycle counter
                            st         <= ST_tRFC;              -- proceed to wait
                        end if;

                    when ST_AR =>
                        -- AUTO REFRESH command
                        DRAM_CS_N  <= '0';
                        DRAM_RAS_N <= '0';
                        DRAM_CAS_N <= '0';
                        DRAM_WE_N  <= '1';
                        DRAM_BA_0  <= '0';
                        DRAM_BA_1  <= '0';
                        DRAM_ADDR  <= (others => '0');
                        timer      <= tRFC_CYC;
                        st         <= ST_tRFC;

                    when ST_tRFC => 
                        if timer > 0 then                       -- Count down until timer is done
                            timer <= timer - 1;
                        else
                            if ar_count = 0 then                -- We arrived here from PREALL's tRP wait; start AR sequence
                                st       <= ST_AR;                                  -- issue first auto-refresh command
                                ar_count <= ar_count + 1;                           -- increment cycle count
                            elsif ar_count < 7 then                                 -- More refreshes to go
                                ar_count <= ar_count + 1;                           -- increment cycle count
                                st       <= ST_AR;                                  -- do next auto refresh command
                            else
                                st       <= ST_LMR;                                 -- all 8 auto-refresh commands done, proceed to Load Mode Register
                            end if;
                        end if;

                    when ST_LMR =>
                        -- LOAD MODE REGISTER command
                        DRAM_CS_N  <= '0';
                        DRAM_RAS_N <= '0';
                        DRAM_CAS_N <= '0';
                        DRAM_WE_N  <= '0';
                        DRAM_BA_0  <= '0';
                        DRAM_BA_1  <= '0';
                        DRAM_ADDR  <= MODE_REG;
                        st         <= ST_IDLE;                                  -- proceed to IDLE state 

                    when ST_IDLE => 
                        busy <= '0';                                                -- DRAM is ready to accept requests

                        if ref_pending = '1' then     -- if a refresh is due, execute it
                            -- REFRESH command
                            DRAM_CS_N   <= '0';
                            DRAM_RAS_N  <= '0';
                            DRAM_CAS_N  <= '0';
                            DRAM_WE_N   <= '1';
                            DRAM_BA_0   <= '0';
                            DRAM_BA_1   <= '0';
                            DRAM_ADDR   <= (others => '0');
                            timer       <= tRFC_CYC;                                    -- set delay for tRFC
                            ref_pending <= '0';                                         -- clear refresh flag
                            st          <= ST_REF_WAIT;                                 -- go to delay, then idle
                        elsif req = '1' then          -- memory r/w request, execute it by activating row then executing read/write on column
                            -- ACTIVATE (set ROW address)
                            DRAM_CS_N   <= '0';
                            DRAM_RAS_N  <= '0';
                            DRAM_CAS_N  <= '1';
                            DRAM_WE_N   <= '1';
                            DRAM_BA_0   <= bank(0);                                     -- select banks
                            DRAM_BA_1   <= bank(1);
                            DRAM_ADDR   <= std_logic_vector(row);
                            timer       <=  tRCD_CYC;                                   -- set delay for tRCD
                            st          <=  ST_tRCD;                                    -- go to delay before read/write
                        end if; -- otherwise, just stay in IDLE

                    when ST_REF_WAIT =>                                             -- delay for refresh cycle, then back to IDLE
                        if timer > 0 then
                            timer <= timer - 1;
                        else 
                            st <= ST_IDLE;
                        end if;

                    when ST_tRCD =>                                                 -- delay, then send read or write command
                        if timer > 0 then
                            timer <= timer - 1; 
                        else 
                            if we = '0' then 
                                -- READ with precharge
                                DRAM_CS_N  <= '0';
                                DRAM_RAS_N <= '1';
                                DRAM_CAS_N <= '0';
                                DRAM_WE_N  <= '1';
                                DRAM_BA_0  <= bank(0);                             -- select banks
                                DRAM_BA_1  <= bank(1);
                                DRAM_ADDR  <= "0010" & std_logic_vector(col);
                                timer      <= CAS_LATENCY;                          -- set delay to CAS latency
                                st         <= ST_CASLAT;                            -- go to delay and output
                            else 
                                dq_out <= wdata;                                    -- set DQ to write data
                                dq_oe  <= '1';                                      -- set correct direction for data to input into DRAM
                                -- WRITE with precharge
                                DRAM_CS_N  <= '0';
                                DRAM_RAS_N <= '1';
                                DRAM_CAS_N <= '0';
                                DRAM_WE_N  <= '0';
                                DRAM_BA_0  <= bank(0);
                                DRAM_BA_1  <= bank(1);
                                DRAM_ADDR  <= "0010" & std_logic_vector(col);
                                timer      <= tWR_CYC;                              -- set delay to tWR
                                st         <= ST_WREC;                              -- go to delay and finish write
                            end if;
                        end if;

                    when ST_CASLAT =>                                               -- delay, then latch the DRAM output from the read
                        if timer > 0 then 
                            timer  <= timer - 1;
                        else
                            RDATA  <= DRAM_DQ;                                      -- set data from DRAM
                            RVALID <= '1';                                          -- set the rvalid flag for one cycle
                            timer  <= timer - 1;
                            st     <= ST_IDLE;                                      -- return to IDLE
                        end if;

                    when ST_WREC =>                                                 -- delay for writing, then back to IDLE
                        dq_oe <= '0';                                               -- data has been latched to memory, switch dq_oe
                        if timer > 0 then 
                            timer <= timer - 1; 
                        else 
                            st    <= ST_IDLE;                                       -- return to IDLE
                        end if;

                    when others =>
                        st <= ST_IDLE;                                              -- should never happen - return to IDLE on unknown state

                end case;
            end if;
        end if;
    end process;
end architecture;
