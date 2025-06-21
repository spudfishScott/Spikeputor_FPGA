-- Read and Write the on-board FLASH memory

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_FlashTest is -- the interface to the DE0 board
    port (
        -- CLOCK
        CLOCK_50 : in std_logic; -- 20 ns clock
        -- Push Button
        BUTTON : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D : out std_logic_vector(6 downto 0);
        HEX0_DP : out std_logic;
        HEX1_D : out std_logic_vector(6 downto 0);
        HEX1_DP : out std_logic;
        HEX2_D : out std_logic_vector(6 downto 0);
        HEX2_DP : out std_logic;
        HEX3_D : out std_logic_vector(6 downto 0);
        HEX3_DP : out std_logic;
        -- LED
        LEDG : out std_logic_vector(9 downto 0);
        -- FLASH
        FL_BYTE_N : out std_logic;
        FL_CE_N : out std_logic;
        FL_OE_N : out std_logic;
        FL_RST_N : out std_logic;
        FL_WE_N : out std_logic;
        FL_WP_N : out std_logic;
        FL_ADDR : out std_logic_vector(21 downto 0);
        FL_DQ : inout std_logic_vector(15 downto 0);
        FL_RY : in std_logic
);
end DE0_FlashTest;

architecture Structural of DE0_FlashTest is
	-- -- Components
	-- -- CLOCK_ENABLE
	-- component CLK_ENABLE is
	-- 	generic (
	-- 		QUANTA_MAX : Integer := 4;
	-- 		QUANTA_ENABLE : Integer := 1
	-- 	);

	-- 	port (
	-- 		CLK_IN : in std_logic;
	-- 		CLK_EN : out std_logic
	-- 	);
	-- end component CLK_ENABLE;

    -- component PULSE_GEN is
    --     generic (
    --         PULSE_WIDTH : Integer := 10 -- pulse width in clock ticks
    --     );
    --     port (
    --         START_PULSE : in std_logic; -- start the pulse generation
    --         CLK_IN : in std_logic; -- clock input
    --         PULSE_OUT : out std_logic -- output pulse signal
    --     );
    -- end component;
	
	-- -- D_REG with LE
	-- component REG_LE is
    --     generic (width : positive := 8); -- width of register

    --     port (
    --         RESET, EN, CLK, LE : in std_logic; -- reset, clock enable, clock, latch enable
    --         D : in std_logic_vector(width-1 downto 0);	-- input
    --         Q : out std_logic_vector(width-1 downto 0)	-- output
    --     );
    -- end component;
	
    -- -- convert a word to 7 segment display output
	-- component WORDTO7SEGS is
	-- port (
	-- 	WORD : std_logic_vector(15 downto 0);
	-- 	SEGS0, SEGS1, SEGS2, SEGS3 : out std_logic_vector(6 downto 0)
	-- );
	-- end component;

    -- component FLASH_RAM is
    --     generic (MAIN_CLK_NS : integer := 20 ); -- 50 MHz = 20 ns
    --     port (
    --         -- controller signals
    --         CLK_IN      : in  std_logic;
    --         RST_IN      : in  std_logic;
    --         ERASE_IN    : in  std_logic_vector(1 downto 0);
    --         RD_IN       : in  std_logic;
    --         WR_IN       : in  std_logic; 
    --         ADDR_IN     : in  std_logic_vector(21 downto 0);
    --         DATA_IN     : in  std_logic_vector(15 downto 0);
    --         DATA_OUT    : out std_logic_vector(15 downto 0);
    --         READY_OUT   : out std_logic; -- High when controller ready for a new operation
    --         VALID_OUT	: out std_logic; -- High when controller wrote bytes / erased without errors
    --         ERROR_OUT	: out std_logic; -- High when error, system need to reset chip and repeat operation

    --         -- flash chip signals
    --         WP_n        : out std_logic; -- write protection
    --         BYTE_n      : out std_logic; -- byte mode/~word mode
    --         RST_n       : out std_logic; -- chip reset
    --         CE_n        : out std_logic; -- chip enable
    --         OE_n        : out std_logic; -- output enable
    --         WE_n        : out std_logic; -- write enable
    --         BY_n        :  in std_logic; -- chip ready/~busy
    --         A	        : out std_logic_vector(21 downto 0); -- chip Address
    --         DQ          : inout std_logic_vector(15 downto 0) -- chip DQ
    --     );
    -- end component;

    -- Signal Declarations
    signal STARTUP : std_logic := '0';                                  -- start up signal
    signal ADDR : std_logic_vector(9 downto 0);
    signal DATA : std_logic_vector(9 downto 0);
    signal DATA_OUT : std_logic_vector(15 downto 0);                    -- data output from flash chip
    signal DISPLAY : std_logic_vector(15 downto 0) := (others => '0');  -- display output
    signal CLK_EN : std_logic;                                          -- clock enable signal

begin
    -- Structure
    -- CPU Clock Enable
    CLOCK_EN : entity work.CLK_ENABLE generic map(5, 1) port map ( -- 100 ns clock enable for "cpu"
        CLK_IN => CLOCK_50,
        CLK_EN => CLK_EN
    );

    -- Startup pulse
    START : entity work.PULSE_GEN generic map (PULSE_WIDTH => 50000000) port map ( -- 1 sec startup pulse
        START_PULSE => '1', -- start the pulse immediately
        CLK_IN => CLOCK_50,
        PULSE_OUT => STARTUP
    );

    -- D REG with enable
    ADDR_REG : entity work.REG_LE generic map(10) port map (	-- address register is 10 bits wide - that's how many switches we have
      RESET => STARTUP,
        CLK => CLOCK_50,
         EN => CLK_EN,
         LE => NOT BUTTON(0), 	-- address set is button 0, invert it because the reg is active high and the button is active low
          D => SW(9 downto 0), 	-- input is switches 9 to 0
          Q => ADDR
    );

    DATA_REG : entity work.REG_LE generic map(10) port map (	-- data register is 10 bits wide - that's how many switches we have
    RESET => STARTUP,
        CLK => CLOCK_50,
         EN => CLK_EN,
         LE => NOT BUTTON(1), 	-- data set is button 1, invert it because the reg is active high and the button is active low
          D => SW(9 downto 0), 	-- input is switches 9 to 0
          Q => DATA
);

    -- Word to 7 Segment Output
    SEGSOUT : entity work.WORDTO7SEGS port map (
         WORD => DISPLAY,
        SEGS3 => HEX3_D,
        SEGS2 => HEX2_D,
        SEGS1 => HEX1_D,
        SEGS0 => HEX0_D
    );

    -- FLASH RAM Controller
   FLASH_CTRL : entity work.FLASH_RAM port map (
       CLK_IN   => CLOCK_50,
       RST_IN   => STARTUP,                 -- reset the controller upon startup
     ERASE_IN   => "00",                    -- no erase operation
        RD_IN   => NOT BUTTON(2),           -- read operation is triggered by button 2
        WR_IN   => NOT BUTTON(1),           -- write operation is triggered by button 1
      ADDR_IN   => "000000111111" & ADDR,   -- address input is the address register for low 10 bits with high bits prepended
      DATA_IN   => "000000" & DATA,         -- data input is the data register for low 10 bits with high bits prepended
     DATA_OUT   => DATA_OUT,                -- controller output
     READY_OUT  => LEDG(0),                 -- busy signal is output to LED 0
    VALID_OUT   => LEDG(1),                 -- valid operation signal is output to LED 1
    ERROR_OUT   => LEDG(2),                 -- error signal is output to LED 2
        -- flash chip signals
         WP_n   => FL_WP_N,                 -- write protection signal
       BYTE_n   => FL_BYTE_N,               -- byte mode signal
        RST_n   => FL_RST_N,                -- chip reset signal
         CE_n   => FL_CE_N,                 -- chip enable signal
         OE_n   => FL_OE_N,                 -- output enable signal
         WE_n   => FL_WE_N,                 -- write enable signal
         BY_n   => FL_RY,                   -- chip ready/~busy signal
            A   => FL_ADDR,                 -- chip address output
           DQ   => FL_DQ                    -- chip data input/output
   );

    -- display is either the address register or the data register
    DISPLAY <= DATA_OUT when BUTTON(2) = '0' else   -- if button 2 is pressed, display data from flash chip
               "000000" & ADDR;                      -- else display address register

    LEDG(9) <= STARTUP;         -- LED 9 is the startup signal
    LEDG(8) <= NOT Button(1);   -- LED 8 is the write signal

    -- assign output states for unused 7 segment display decimal point and unused LEDs
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';
    LEDG(7 downto 3) <= (others => '0');

end Structural;
