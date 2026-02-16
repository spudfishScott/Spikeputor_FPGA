-- This is a simple wishbone round-robin arbiter for multiple masters
-- Masters are: the spikpeutor CPU (M0), the DMA controller (M1) (not implemented yet), and the clock generator (M2) (for CPU clocking)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity WSH_ARBITER is
    port (
        -- Wishbone bus signals
        CLK        : in  std_logic;      -- System clock
        RESET      : in  std_logic;      -- System reset

        -- Master 0 (CPU) signals
        M0_CYC_O   : in  std_logic;                     -- Master 0 cycle output
        M0_STB_O   : in  std_logic;                     -- Master 0 strobe output
        M0_WE_O    : in std_logic;                      -- Master 0 we output
        M0_DATA_O  : in std_logic_vector(15 downto 0);  -- Master 0 Data output
        M0_ADDR_O  : in std_logic_vector(23 downto 0);  -- Master 0 Address output
        M0_GNT     : out std_logic;                     -- Master 0 grant output

        -- Master 1 (DMA) signals
        M1_CYC_O   : in  std_logic;                     -- Master 1 cycle input
        M1_STB_O   : in  std_logic;                     -- Master 1 strobe input
        M1_WE_O    : in std_logic;                      -- Master 1 we output
        M1_DATA_O  : in std_logic_vector(15 downto 0);  -- Master 1 Data output
        M1_ADDR_O  : in std_logic_vector(23 downto 0);  -- Master 1 Address output
        M1_GNT     : out std_logic;                     -- Master 1 grant output

        -- Master 2 (Clock Generator) signals
        M2_CYC_O   : in  std_logic;                     -- Master 2 cycle input
        M2_GNT     : out std_logic;                     -- Master 2 grant output

        -- Wishbone bus signals passed out throught the arbiter
        CYC_O      : out std_logic;                     -- Cycle output to providers
        STB_O      : out std_logic;                     -- Strobe output to providers
        WE_O       : out std_logic;                     -- WE output to providers
        ADDR_O     : out std_logic_vector(23 downto 0); -- Address output to providers
        DATA_O     : out std_logic_vector(15 downto 0)  -- Data output to providers
    );
end WSH_ARBITER;

architecture RTL of WSH_ARBITER is
    type STATE_TYPE is (IDLE, GRANT_M0, GRANT_M1, GRANT_M2);
    signal grant_state, prev_grant : STATE_TYPE := IDLE;
    signal grant_sel   : std_logic_vector(1 downto 0) := "00";  -- Grant select
    signal stb_sel     : std_logic_vector(0 downto 0) := "0";
    signal we_sel      : std_logic_vector(0 downto 0) := "0";

    signal m1_stb_sig  : std_logic_vector(0 downto 0) := "0";
    signal m0_stb_sig  : std_logic_vector(0 downto 0) := "0";
    signal m1_we_sig   : std_logic_vector(0 downto 0) := "0";
    signal m0_we_sig   : std_logic_vector(0 downto 0) := "0";

begin

    -- output signals
    CYC_O <= '0' when grant_state = IDLE else '1';  -- CYC_O needs to be deasserted before next grant can occur

    STB_MUX : entity work.MUX3
        generic map( WIDTH => 1 )
        port map (
            IN2    => "0",  -- no STB signal for M2 (CPU Clock)
            IN1    => m1_stb_sig,
            IN0    => m0_stb_sig,
            SEL    => grant_sel,
            MUXOUT => stb_sel
        );

    -- convert std_logic to std_logic_vectors for the MUX
    m1_stb_sig <= (0 => M1_STB_O);
    m0_stb_sig <= (0 => M0_STB_O);

    -- convert std_logic_vector from the MUX to std_logic
    STB_O <= '1' when stb_sel = "1" else '0';

    WE_MUX : entity work.MUX3
        generic map( WIDTH => 1 )
        port map (
            IN2    => "0",  -- no WE signal for M2 (CPU Clock)
            IN1    => m1_we_sig,
            IN0    => m0_we_sig,
            SEL    => grant_sel,
            MUXOUT => we_sel
        );

    -- convert std_logic to std_logic_vectors for the MUX
    m1_we_sig <= (0 => M1_WE_O);
    m0_we_sig <= (0 => M0_WE_O);

    -- convert std_logic to std_logic_vectors for the MUX
    WE_O <= '1' when we_sel = "1" else '0';

    ADDR_MUX : entity work.MUX3 
        generic map( WIDTH => 24 )
        port map (
            IN2    => "000000000000000000000000",  -- no ADDR signal for M2 (CPU Clock) - maybe just set it to CPU address?
            IN1    => M1_ADDR_O,
            IN0    => M0_ADDR_O,
            SEL    => grant_sel,
            MUXOUT => ADDR_O
        );

    DATA_MUX : entity work.MUX3
        generic map(WIDTH => 16)
        port map (
            IN2    => "0000000000000000",  -- no DATA signal for M2 (CPU Clock)
            IN1    => M1_DATA_O,
            IN0    => M0_DATA_O,
            SEL    => grant_sel,
            MUXOUT => DATA_O
        );

    -- Output logic
    process(grant_state) is
    begin
        -- Default outputs
        M0_GNT <= '0';
        M1_GNT <= '0';
        M2_GNT <= '0';
        grant_sel <= "00";

        case grant_state is
            when GRANT_M0 =>
                M0_GNT <= '1';
                grant_sel <= "00";

            when GRANT_M1 =>
                M1_GNT <= '1';
                grant_sel <= "01";

            when GRANT_M2 =>
                M2_GNT <= '1';
                grant_sel <= "10";

            when others =>
                -- No grants in IDLE state
                null;
        end case;
    end process;

    -- review grant state each clock tick
    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RESET = '1' then     -- handle reset
                grant_state <= IDLE;
                prev_grant <= IDLE;
            else
                case grant_state is
                    when IDLE =>    -- wait for requests from all masters, priority is round-robin based on previous grant
                        case prev_grant is
                            when IDLE => 
                                if M2_CYC_O = '1' then          -- on IDLE (and reset), prioritize CLOCK over CPU
                                    grant_state <= GRANT_M2;
                                elsif M0_CYC_O = '1' then
                                    grant_state <= GRANT_M0;
                                elsif M1_CYC_O = '1' then
                                    grant_state <= GRANT_M1;
                                else
                                    grant_state <= IDLE;
                                end if;

                            when GRANT_M0 =>
                                if M1_CYC_O = '1' then
                                    grant_state <= GRANT_M1;
                                elsif M2_CYC_O = '1' then
                                    grant_state <= GRANT_M2;
                                elsif M0_CYC_O = '1' then
                                    grant_state <= GRANT_M0;
                                else
                                    grant_state <= IDLE;
                                    prev_grant <= IDLE;     -- if no grant request is pending after this one, M0 gets first priority again
                                end if;

                            when GRANT_M1 =>
                                if M2_CYC_O = '1' then
                                    grant_state <= GRANT_M2;
                                elsif M0_CYC_O = '1' then
                                    grant_state <= GRANT_M0;
                                elsif M1_CYC_O = '1' then
                                    grant_state <= GRANT_M1;
                                else
                                    grant_state <= IDLE;
                                    prev_grant <= IDLE;     -- if no grant request is pending after this one, M0 gets first priority again
                                end if;
            
                            when GRANT_M2 => 
                                if M0_CYC_O = '1' then
                                    grant_state <= GRANT_M0;
                                elsif M1_CYC_O = '1' then
                                    grant_state <= GRANT_M1;
                                elsif M2_CYC_O = '1' then
                                    grant_state <= GRANT_M2;
                                else
                                    grant_state <= IDLE;
                                    prev_grant <= IDLE;     -- if no grant request is pending after this one, M0 gets first priority again
                                end if;
                            
                            when others =>      -- should never happen, treat like a reset
                                grant_state <= IDLE;
                                prev_grant <= IDLE;
                        end case;

                    when GRANT_M0 =>    -- stay in grant state as long as master is requesting
                        if M0_CYC_O = '1' then
                            grant_state <= GRANT_M0;
                        else
                            prev_grant <= GRANT_M0;
                            grant_state <= IDLE;    -- deassert CYC_O and select next grant
                        end if;

                    when GRANT_M1 =>    -- stay in grant state as long as master is requesting
                        if M1_CYC_O = '1' then
                            grant_state <= GRANT_M1;
                        else
                            prev_grant <= GRANT_M1;
                            grant_state <= IDLE;    -- deassert CYC_O and select next grant
                        end if;

                    when GRANT_M2 =>    -- stay in grant state as long as master is requesting
                        if M2_CYC_O = '1' then
                            grant_state <= GRANT_M2;
                        else
                            prev_grant <= GRANT_M2;
                            grant_state <= IDLE;    -- deassert CYC_O and select next grant
                        end if;

                    when others =>      -- should not occur, default to IDLE
                        grant_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end RTL;