library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_AUDIOTest is -- the interface to the DE0 board
    port (
        -- INPUTS
        CLOCK_50 : in std_logic;
        -- DPDT Switch
        SW       : in std_logic_vector(9 downto 0);
        
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
        VGA_R    : out std_logic_vector(3 downto 0)
);
end DE0_AUDIOTest;

architecture Structural of DE0_AUDIOTest is

    signal sig_out_o : std_logic_vector(13 downto 0) := (others => '0');  -- internal signal to connect AUDIO_SIG output to DE0 audio output

begin

    VGA_R <= sig_out_o(13 downto 10);  -- connect the 4 most significant bits of the signal output to the 4-bit audio output (VGA_R)

    AUDIO_SIG_inst : entity work.AUDIO_SIG
        generic map(
            CLK_FREQ => 50_000_000
        )
        port map(
            CLK      => CLOCK_50,
            RESET    => NOT (Button(0)),  -- active high reset using first push button
            NOTE_IDX => SW(3 downto 0),
            OCTAVE   => SW(7 downto 4),
            WAVEFORM => SW(9 downto 8),
            SET      => NOT (Button(1)),  -- use second push button as strobe to set note parameters
            SIG_OUT  => sig_out_o
        );

    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => "000" & sig_out_o,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );
    
    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG <= (others => '0');


end Structural;