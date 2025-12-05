-- KEYBOARD Wishbone interface

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity KEYBOARD_WSH_P is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read signals - keyboard (for now) is read only - might add ability to set autokey repeat rate
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus

        -- keyboard communication
        PS2_CLK     : inout std_logic;
        PS2_DATA    : inout std_logic
    );
end KEYBOARD_WSH_P;

architecture rtl of KEYBOARD_WSH_P is
    signal key_req_s    : std_logic := '0';                                     -- request new keypress
    signal ascii_new_s  : std_logic := '0';                                     -- keypress is available to read
    signal ascii_data   : std_logic_vector(6 downto 0) := (others => '0');      -- keyboard data output
    signal ack          : std_logic := '0';                                     -- wishbone acknowledge

    type st_t is (IDLE, ISSUE, WAIT_VALID, CLEAR);                              -- State machine for multi-step wishbone read
    signal st           : st_t := IDLE;

begin
    -- instantiate the keyboard controller
    kbd : entity work.PS2_ASCII
    PORT MAP (
        clk         => CLK,                    -- system clock input
        n_rst       => NOT(RST_I),             -- reset signal (active low)
        ps2_clk     => PS2_CLK,                -- clock signal from PS2 keyboard
        ps2_data    => PS2_DATA,               -- data signal from PS2 keyboard
        key_req     => key_req_s,              -- strobe this input to request next key in buffer
        ascii_new   => ascii_new_s,            -- output flag to indicate key request has been fulfilled, 0x0000 = buffer empty
        ascii_code  => ascii_data              -- ASCII value
    );

    WBS_DATA_O <= (15 downto 7 => '0') & ascii_data;        -- output data is ascii_data zero padded
    WBS_ACK_O  <= WBS_CYC_I AND WBS_STB_I AND ack;          -- acknowledge signal based on ack, CYC and STB

    process(clk) is
	 begin
        if rising_edge(CLK) then
            if RST_I = '1' then -- return to IDLE state and clear control signals on reset
                key_req_s <= '0';
                ack       <= '0';
                st        <= IDLE; 
            else
                case st is
                    when IDLE =>
                        if (WBS_CYC_I ='1' AND WBS_STB_I = '1') then    -- new transaction requested
                            key_req_s   <= '1';                         -- assert key request
                            st          <= WAIT_VALID;                  -- go to WAIT state, wait for valid result from KEYBOARD controller
                        else
                            st          <= IDLE;                        -- stay in IDLE state
                        end if;

                    when WAIT_VALID =>          -- wait for READ to complete (keyboard data is valid)
                        if (ascii_new_s = '1') then -- keyboard reports a new ascii character
                            key_req_s <= '0';       -- clear request signal
                            ack <= '1';             -- assert wishbone ack signal
                            st  <= CLEAR;           -- done, clear ack signal when wishbone transaction ends, then go back to IDLE state
                        else
                            if (WBS_CYC_I = '0' OR WBS_STB_I = '0') then -- if master deasserts CYC or STB, abort read
                                key_req_s <= '0';   -- clear request signal
                                ack <= '0';         -- clear ack signal
                                st  <= IDLE;        -- go back to IDLE state
                            else
                                st <= WAIT_VALID;   -- stay in wait state until data is valid
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
                        key_req_s <= '0';
                        st  <= IDLE;         -- should never happen, go to IDLE
                end case;

                if (WBS_CYC_I = '0') then   -- Break cycle if master deasserts CYC
                    key_req_s <= '0';
                    ack <= '0';
                    st <= IDLE;
                end if;
            end if;
        end if;
  end process;

end rtl;
