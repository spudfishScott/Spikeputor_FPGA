library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_AUDIOTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        CLOCK_50 : in std_logic;
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        -- Button
        BUTTON   : in std_logic_vector(2 downto 0);
        --OUTPUTS
        -- 7-SEG Display
        HEX0_D   : out std_logic_vector(6 downto 0);
        HEX0_DP  : out std_logic;
        HEX1_D   : out std_logic_vector(6 downto 0);
        HEX1_DP  : out std_logic;
        HEX2_D   : out std_logic_vector(6 downto 0);
        HEX2_DP  : out std_logic;
        HEX3_D   : out std_logic_vector(6 downto 0);
        HEX3_DP  : out std_logic;
        -- LED
        LEDG     : out std_logic_vector(9 downto 0);

        -- audio out
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0)
);
end DE0_AUDIOTest;

architecture Structural of DE0_AUDIOTest is
    signal voice0_sig : std_logic_vector(9 downto 0) := (others => '0');
    signal voice1_sig : std_logic_vector(9 downto 0) := (others => '0');
    signal voice2_sig : std_logic_vector(9 downto 0) := (others => '0');
    signal voice3_sig : std_logic_vector(9 downto 0) := (others => '0');

    signal voice_sel  : unsigned(1 downto 0) := (others => '0');

    signal set0_sig   : std_logic := '0';
    signal set1_sig   : std_logic := '0';
    signal set2_sig   : std_logic := '0';
    signal set3_sig   : std_logic := '0';

    signal sig_out_r  : std_logic_vector(3 downto 0);
    signal sig_out_l  : std_logic_vector(3 downto 0);

    signal prev_button_1 : std_logic := '0';
    signal prev_button_2 : std_logic := '0';
    signal set_strobe    : std_logic := '0';

begin

    VGA_R <= sig_out_r;
    VGA_G <= sig_out_l;

    set0_sig <= set_strobe when voice_sel = "00" else '0';
    set1_sig <= set_strobe when voice_sel = "01" else '0';
    set2_sig <= set_strobe when voice_sel = "10" else '0';
    set3_sig <= set_strobe when voice_sel = "11" else '0';


    AUDIO_CTRL : entity work.AUDIO
    generic map (
        CLK_FREQ => 50000000, -- 50 MHz
    )
    port map (
        CLK     => CLOCK_50,
        RESET   => NOT BUTTON(0),

        VOICE0  => "000011" & voice0_sig,   -- 11 is channel
        VOICE1  => "000011" & voice1_sig,
        VOICE2  => "000011" & voice2_sig,
        VOICE3  => "000011" & voice3_sig,

        SET0    => set0_sig,
        SET1    => set1_sig,
        SET2    => set2_sig,
        SET3    => set3_sig,

        AUDIO_R => sig_out_r,
        AUDIO_L => sig_out_l
    );

    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => "000000" & SW(9 downto 0),
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );
    
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            if RESET = '1' then
                voice_sel <= (others => '0');
                prev_button_1 <= '0';
                prev_button_2 <= '0';

                set_strobe <= '1';  -- clear all voices on reset
                voice0_sig <= (others => '0');
                voice1_sig <= (others => '0');
                voice2_sig <= (others => '0');
                voice3_sig <= (others => '0');
            end if;

            set_strobe <= 0; -- default to 0, set to 1 for one cycle when setting a voice signal
            -- voice selection logic
            if BUTTON(1) = '1' and prev_button_1 = '0' then
                voice_sel <= voice_sel + 1;
            end if;
            prev_button_1 <= BUTTON(1);

            -- set signal logic
            if BUTTON(2) = '1' and prev_button_2 = '0' then
                set_strobe <= 1;
                case voice_sel is
                    when "00" =>
                        voice0_sig <= SW(9 downto 0);
                    when "01" =>
                        voice1_sig <= SW(9 downto 0);
                    when "10" =>
                        voice2_sig <= SW(9 downto 0);
                    when "11" =>
                        voice3_sig <= SW(9 downto 0);
                    when others =>
                        null;
                end case;
            end if;
            prev_button_2 <= BUTTON(2);
        end if;
    end process;

    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(9 downto 8) <= voice_sel;  -- currently selected voice
    LEDG(7 downto 0) <= (others => '0');


end Structural;