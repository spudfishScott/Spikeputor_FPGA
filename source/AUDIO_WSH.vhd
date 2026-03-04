-- AUDIO Wishbone Interface Provider
-- Write to addresses 0xFFF5 - 0xFFF* to set voices 0 through 3
-- Inputs for each voice (16 bits total):
    -- [3:0] NOTE INDEX - 4 bits from 1-12 for each note of the scale starting with C and rising to B. 0 = no sound, anything above 12 is no sound.
    -- [7:4] OCTAVE     - 4 bits from 0-8, anyting higher than 8 is clamped to 8. Octave 0 doesn't work well below Note Index 8 for triangle or sawtooth waveforms.
    -- [9:8] WAVEFORM   - 2 bits: 0b00 - square, 0b01 - sawtooth, 0b10 - triangle, 0b11 - sine
    -- Remaining bits are ignored

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity AUDIO_WSH_P is
    generic (
        CLK_FREQ : integer := 50000000  -- default to 50 MHz clock, can be overridden by testbench or top-level module
    );
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
        WBS_ADDR_I  : in std_logic_vector(15 downto 0);     -- address from master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to bus

        -- audio signals out
        AUDIO_H     : out std_logic_vector(3 downto 0);
        AUDIO_M     : out std_logic_vector(3 downto 0);
        AUDIO_L     : out std_logic_vector(3 downto 0)
    );
end AUDIO_WSH_P;

architecture rtl of AUDIO_WSH_P is
    signal set_sig    : std_logic := '0';
    signal set0_sig   : std_logic := '0';
    signal set1_sig   : std_logic := '0';
    signal set2_sig   : std_logic := '0';
    signal set3_sig   : std_logic := '0';

    signal voice0_sig : std_logic_vector(15 downto 0) := (others => '0');
    signal voice1_sig : std_logic_vector(15 downto 0) := (others => '0');
    signal voice2_sig : std_logic_vector(15 downto 0) := (others => '0');
    signal voice3_sig : std_logic_vector(15 downto 0) := (others => '0');

begin

    AUDIO_CTRL : entity work.AUDIO
    generic map (
        CLK_FREQ => CLK_FREQ  -- pass in system clock frequency for accurate timing
    )
    port map (
        CLK        => CLK,
        RESET      => RST_I,

        VOICE0     => voice0_sig,
        VOICE1     => voice1_sig,
        VOICE2     => voice2_sig,
        VOICE3     => voice3_sig,

        SET0       => set0_sig,
        SET1       => set1_sig,
        SET2       => set2_sig,
        SET3       => set3_sig,

        AUDIO_H    => AUDIO_H,
        AUDIO_M    => AUDIO_M,
        AUDIO_L    => AUDIO_L
    );

    -- connections to AUDIO controller
    set0_sig   <= set_sig when WBS_ADDR_I(3 downto 0) = "0101" else '0';
    set1_sig   <= set_sig when WBS_ADDR_I(3 downto 0) = "0110" else '0';
    set2_sig   <= set_sig when WBS_ADDR_I(3 downto 0) = "0111" else '0';
    set3_sig   <= set_sig when WBS_ADDR_I(3 downto 0) = "1000" else '0';

    -- data output is just the appropriate latched voice value based on register
    WBS_DATA_O <= voice0_sig when WBS_ADDR_I(3 downto 0) = "0101" else
                  voice1_sig when WBS_ADDR_I(3 downto 0) = "0110" else
                  voice2_sig when WBS_ADDR_I(3 downto 0) = "0111" else
                  voice3_sig when WBS_ADDR_I(3 downto 0) = "1000" else
                  (others => '0');

    process(clk) is
    begin
        if rising_edge(clk) then
            if (RST_I = '1') then   -- reset all internal values on RST_I
                set_sig    <= '0';
                voice0_sig <= (others => '0');
                voice1_sig <= (others => '0');
                voice2_sig <= (others => '0');
                voice3_sig <= (others => '0');
            else
                WBS_ACK_O <= WBS_CYC_I AND WBS_STB_I;
                set_sig <= '0';

                if WBS_CYC_I = '1' and WBS_STB_I = '1' and WBS_WE_I = '1' then  -- when writing, set the voice data and strobe SET signal on appropriate voice.
                    set_sig <= '1';
                    case WBS_ADDR_I(3 downto 0) is  -- select voice signal based on last nybble of address
                        when "0101" =>
                            voice0_sig <= WBS_DATA_I;
                        when "0110" =>
                            voice1_sig <= WBS_DATA_I;
                        when "0111" =>
                            voice2_sig <= WBS_DATA_I;
                        when "1000" =>
                            voice3_sig <= WBS_DATA_I;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

end rtl;