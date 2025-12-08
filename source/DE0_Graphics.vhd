library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE0_Graphics is
    port (
        -- Clock Input
        CLOCK_50   : in std_logic;
        -- Push Button
        BUTTON     : in std_logic_vector(2 downto 0);
        -- DPDT Switch
        SW         : in std_logic_vector(9 downto 0);
        -- 7-SEG Display
        HEX0_D     : out std_logic_vector(6 downto 0);
        HEX0_DP    : out std_logic;
        HEX1_D     : out std_logic_vector(6 downto 0);
        HEX1_DP    : out std_logic;
        HEX2_D     : out std_logic_vector(6 downto 0);
        HEX2_DP    : out std_logic;
        HEX3_D     : out std_logic_vector(6 downto 0);
        HEX3_DP    : out std_logic;
        -- LED
        LEDG       : out std_logic_vector(9 downto 0);
        -- GPIO (need to assign pins accordingly)
        SCRN_CTRL   : out   std_logic_vector(5 downto 0);    -- Screen Control output only (BL_CTL, /RESET, /CS, /WR, /RD, RS) GPIO 2 -> 7
        SCRN_WAIT_N : in    std_logic;                       -- /WAIT signal input only (GPIO0 8)
        SCRN_DATA   : inout std_logic_vector(15 downto 0)    -- DATAIO signal (GPIO 9 -> 24)
    );
end DE0_Graphics;

architecture RTL of DE0_Graphics is
    signal bl    : std_logic := '0';                                        -- Backlight control
    signal n_res : std_logic := '1';                                        -- /RESET signal
    signal n_cs  : std_logic := '1';                                        -- /CS signal (see if it can always just be on)
    signal rs    : std_logic := '0';                                        -- RS signal - default to STATUS read/Command Write
    signal n_rd  : std_logic := '1';                                        -- /RD signal
    signal n_wr  : std_logic := '1';                                        -- /WR signal
    signal d_out : std_logic_vector(15 downto 0) := (others => '0');        -- Data Out from screen controller
    signal d_in  : std_logic_vector(15 downto 0) := (others => '0');        -- Data In to screen controller
    signal db_oe : std_logic := '0';                                        -- data bus output enable - set to 1 when sending to screen controller

    signal timer : Integer := 0;            -- timer counter
    signal cmd_index : Integer := 0;        -- command index for multi-step commands

    type state_type is (IDLE, STATUS_RD, COMMAND_WR, DATA_RD, DATA_WR, RW_DONE, WAIT_ST, INIT);
    signal state     : state_type := INIT;
    signal return_st : state_type := INIT;

    signal blue : Integer range 0 to 255 := 0;

begin
    -- signals mapped to pin outputs
    SCRN_CTRL(5) <= bl;
    SCRN_CTRL(4) <= n_res;
    SCRN_CTRL(3) <= n_cs;
    SCRN_CTRL(2) <= n_wr;
    SCRN_CTRL(1) <= n_rd;
    SCRN_CTRL(0) <= rs;


    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    DISPLAY : entity work.WORDTO7SEGS
        port map (
            WORD  => d_in,
            SEGS0 => HEX0_D,
            SEGS1 => HEX1_D,
            SEGS2 => HEX2_D,
            SEGS3 => HEX3_D
        );

    LEDG <= std_logic_vector(to_unsigned(cmd_index, 10));   -- show cmd_index on the on-board LEDs

    -- send d_in into the screen controller when db_oe is 1, otherwise set data_out to screen controller output
    SCRN_DATA(15 downto 0) <= d_in when db_oe = '1' else (others => 'Z');

    process(CLOCK_50) is
    begin
        if rising_edge(CLOCK_50) then
            if Button(0) = '0' then         -- reset button pushed, clear state machine and all counters
                state     <= INIT;  -- set state to initialize the contoller
                return_st <= INIT;  -- reset the return state as well
                timer     <= 0;     -- reset timer and command index
                cmd_index <= 0;
                n_res     <= '1';   -- reset output control signals
                n_rd      <= '1';
                n_wr      <= '1';
                n_cs      <= '1';
                rs        <= '0';
                db_oe     <= '0';
                d_out <= (others => '0');   -- reset data in/out
                d_in  <= (others => '0');
            else
                case state is
                    when WAIT_ST =>
                        if timer = 0 then
                            state <= return_st;
                        else
                            timer <= timer - 1;
                            state <= WAIT_ST;
                        end if;

                    when STATUS_RD =>
                        if n_cs = '1' then  -- issue command, then come back on next clock cycle
                            n_cs <= '0';
                            rs   <= '0';
                            n_rd <= '0';    -- rs = 0, n_rd = 0 -> read status
                            state <= STATUS_RD;
                        else
                            n_cs <= '1';
                            n_rd <= '1';    -- complete command
                            d_out(15 downto 8) <= (others => '0');
                            d_out(7 downto 0) <= SCRN_DATA(7 downto 0);   -- latch data (lower 8 bits only) into data_out
                            state <= RW_DONE;                 -- go back to the state this was "called" from
                        end if;

                    when COMMAND_WR =>
                        if n_cs = '1' then  -- issue command, then come back on next clock cycle
                            db_oe <= '1';   -- puts d_in onto the inout bus
                            n_cs <= '0';
                            rs   <= '0';
                            n_wr <= '0';    -- rs = 0, n_wr = 0 -> write command
                            state <= COMMAND_WR;    -- hold in this state for one clock cycle
                        else
                            n_cs  <= '1';
                            db_oe <= '0';
                            n_wr  <= '1';    -- complete command
                            state <= RW_DONE;                 -- go back to the state this was "called" from
                        end if;

                    when DATA_RD =>
                        if n_cs = '1' then  -- issue command, then come back on next clock cycle
                            n_cs <= '0';
                            rs   <= '1';
                            n_rd <= '0';    -- rs = 1, n_rd = 0 -> read data
                            state <= DATA_RD;
                        else
                            n_cs <= '1';
                            n_rd <= '1';    -- complete command
                            d_out <= SCRN_DATA(15 downto 0);    -- latch data (all 16 bits) into register
                            state <= RW_DONE;                 -- go back to the state this was "called" from
                        end if;

                    when DATA_WR =>
                        if n_cs = '1' then  -- issue command, then come back on next clock cycle
                            db_oe <= '1';   -- puts d_in onto the inout bus
                            n_cs <= '0';
                            rs   <= '1';
                            n_wr <= '0';    -- rs = 1, n_wr = 0 -> write data
                            state <= DATA_WR;    -- hold in this state for one clock cycle
                        else
                            n_cs  <= '1';
                            db_oe <= '0';
                            n_wr  <= '1';    -- complete command
                            state <= RW_DONE;                 -- go back to the state this was "called" from
                        end if;

                    when RW_DONE =>
                        state <= return_st;     -- go back to the state this was "called" from

                    when INIT =>            -- go through the display reset and initialization sequence
                        return_st <= INIT;              -- return state is always set here for WAIT and read/write calls
                        cmd_index <= cmd_index + 1;     -- complete each step in turn, so index is incremented by default each time through this state
                        case cmd_index is
                            -- POWER UP CYCLE - WAIT - HW RESET - WAIT
                            when 0 =>       -- step 0: delay 100 ms (5,000,000 cycles at 20 ns per cycle)
                                timer <= 5_000_000;
                                state <= WAIT_ST;
                            when 1 =>       -- step 1: set /RESET low on the chip and delay for 50 ms
                                n_res <= '0';
                                timer <= 2_500_000;
                                state <= WAIT_ST;
                            when 2 =>       -- step 2: set /RESET high on the chip and delay 150 ms
                                n_res <= '1';
                                timer <= 7_500_000;
                                state <= WAIT_ST;
                            -- WAIT FOR CHIP TO POWER UP/RESET
                            when 3 =>       -- step 3: read Status register
                                state <= STATUS_RD;
                            when 4 =>       -- step 4: if status bit 1 is 1, go back to step 3
                                if d_out(1) = '1' then
                                    cmd_index <= 3;
                                end if;
                            -- SOFTWARE RESET
                            when 5 =>       -- step 5: select register 0
                                d_in <= x"0000";  -- set register 0
                                state <= COMMAND_WR;
                            when 6 =>       -- step 6: read register 0
                                state <= DATA_RD;
                            when 7 =>       -- step 7: assert bit 0 and write to register 0 (Software Reset)
                                d_in <= d_out OR x"0001";
                                state <= DATA_WR;
                            when 8 =>       -- step 8: re-read register 8
                                state <= DATA_RD;
                            when 9 =>       -- step 9: if bit 0 is 1, go back to step 8 (Software Reset not complete)
                                if d_out(0) = '1' then
                                    cmd_index <= 8;
                                end if;
                            -- SET PLLs
                            when 10 =>      -- step 10: Select Register 0x05
                                d_in <= x"0005";
                                state <= COMMAND_WR;
                            when 11 =>      -- step 11: Write 0x06 to Register 0x05 (PLL1 Divided by 8)
                                d_in <= x"0006";
                                state <= DATA_WR;
                            when 12 =>      -- step 12: Select Register 0x06
                                d_in <= x"0006";
                                state <= COMMAND_WR;
                            when 13 =>      -- step 13: Write 0x27 to Register 0x06 (Pixel Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 14 =>      -- step 14: Select Register 0x07
                                d_in <= x"0007";
                                state <= COMMAND_WR;
                            when 15 =>      -- step 15: Write 0x04 to Register 0x07 (PLL 2 Divided by 4)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 16 =>      -- step 16: Select Register 0x08
                                d_in <= x"0008";
                                state <= COMMAND_WR;
                            when 17 =>      -- step 17: Write 0x27 to Register 0x08 (SDRAM Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 18 =>      -- step 18: Select Register 0x09
                                d_in <= x"0009";
                                state <= COMMAND_WR;
                            when 19 =>      -- step 19: Write 0x04 to Register 0x09 (PLL 3 Divided by 4)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 20 =>      -- step 20: Select Register 0x0A
                                d_in <= x"000A";
                                state <= COMMAND_WR;
                            when 21 =>      -- step 21: Write 0x27 to Register 0x0A (System Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 22 =>      -- step 22: Select Register 0x01
                                d_in <= x"0001";
                                state <= COMMAND_WR;
                            when 23 =>      -- step 23: Write 0x00 to Register 0x01 (Reconfigure PLLs)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 24 =>      -- step 24: Delay 10 uS
                                timer <= 500;
                                state <= WAIT_ST;
                            when 25 =>      -- step 25: Write 0x80 to Regsiter 0x01 (Set up PLLs, TFT Output is 24 bpp)
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 26 =>      -- step 26: Delay 1 ms
                                timer <= 50_000;
                                state <= WAIT_ST;
                            -- SET UP SDRAM
                            when 27 =>      -- step 27: Select Register 0xE0
                                d_in <= x"00E0";
                                state <= COMMAND_WR;
                            when 28 =>      -- step 28: Write 0x29 to Register 0xE0 (128 Mbit)
                                d_in <= x"0029";
                                state <= DATA_WR;
                            when 29 =>      -- step 29: Select Register 0xE1
                                d_in <= x"00E1";
                                state <= COMMAND_WR;
                            when 30 =>      -- step 30: Write 0x03 to Register 0xE1 (CAS = 2, ACAS = 3)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 31 =>      -- step 31: Select Register 0xE2
                                d_in <= x"00E2";
                                state <= COMMAND_WR;
                            when 32 =>      -- step 32: Write 0x0B to Register 0xE2 (Auto refresh interval is 779 (0x30B))
                                d_in <= x"000B";
                                state <= DATA_WR;
                            when 33 =>      -- step 33: Select Register 0xE3
                                d_in <= x"00E3";
                                state <= COMMAND_WR;
                            when 34 =>      -- step 34: Write 0x03 to Register 0xE3
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 35 =>      -- step 35: Select Register 0xE4
                                d_in <= x"00E4";
                                state <= COMMAND_WR;
                            when 36 =>      -- step 36: Write 0x01 to Register 0xE4 (Begin SDRAM initialization)
                                d_in <= x"0001";
                                state <= DATA_WR;
                            -- ADDITIONAL CHIP CONFIG
                            when 37 =>      -- step 37: Select Register 0x01
                                d_in <= x"0001";
                                state <= COMMAND_WR;
                            when 38 =>      -- step 38: Write 0x01 to Register 0x01 (24-bit TFT output, 16-bit Host Data Bus)
                                d_in <= x"0001";
                                state <= DATA_WR;
                            -- REGISTERS 0x02 and 0x03 STAY AT THEIR DEFAULT VALUES FOR NOW
                            -- SET SCREEN PARAMETERS AND TIMING
                            when 39 =>      -- step 39: Select Register 0x12
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 40 =>      -- step 40: Write 0x80 to Register 0x12 (Set screen data for fetching on falling clock)
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 41 =>      -- step 41: Select Register 0x13
                                d_in <= x"0013";
                                state <= COMMAND_WR;
                            when 42 =>      -- step 42: Write 0xC3 to Register 0x13 (DE active high, HSYNC and VSYNC active high)
                                d_in <= x"00C3";
                                state <= DATA_WR;
                            when 43 =>      -- step 43: Select Register 0x14
                                d_in <= x"0014";
                                state <= COMMAND_WR;
                            when 44 =>      -- step 44: Write 0x7F to Register 0x14 (bits 11:4 of display width - 1 for 1024 pixels)
                                d_in <= x"007F";
                                state <= DATA_WR;
                            when 45 =>      -- step 45: Select Register 0x15
                                d_in <= x"0015";
                                state <= COMMAND_WR;
                            when 46 =>      -- step 46: Write 0x00 to Register 0x15 (bits 3:0 of display width)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 47 =>      -- step 47: Select Register 0x1A
                                d_in <= x"001A";
                                state <= COMMAND_WR;
                            when 48 =>      -- step 48: Write 0x57 to Register 0x1A (bits 7:0 of display height - 1 for 600 pixels)
                                d_in <= x"0057";
                                state <= DATA_WR;
                            when 49 =>      -- step 49: Select Register 0x1B
                                d_in <= x"001B";
                                state <= COMMAND_WR;
                            when 50 =>      -- step 50: Write 0x02 to Register 0x1B (bits 10:8 of display height - 1 for 600 pixels)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 51 =>      -- step 51: Select Register 0x16
                                d_in <= x"0016";
                                state <= COMMAND_WR;
                            when 52 =>      -- step 52: Write 0x13 to Register 0x16 (bits 8:4 of back porch - 1)
                                d_in <= x"0013";
                                state <= DATA_WR;
                            when 53 =>      -- step 53: Select Register 0x17
                                d_in <= x"0017";
                                state <= COMMAND_WR;
                            when 54 =>      -- step 54: Write 0x00 to Register 0x17 (bits 3:0 of back porch)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 55 =>      -- step 55: Select Register 0x18
                                d_in <= x"0018";
                                state <= COMMAND_WR;
                            when 56 =>      -- step 56: Write 0x14 to Register 0x18 (front porch / 8 for back porch 160)
                                d_in <= x"0014";
                                state <= DATA_WR;
                            when 57 =>      -- step 57: Select Register 0x19
                                d_in <= x"0019";
                                state <= COMMAND_WR;
                            when 58 =>      -- step 58: Write 0x07 to Register 0x19 (pulse width / 8 - 1 for HSYNC pulse width 70)
                                d_in <= x"0007";
                                state <= DATA_WR;
                            when 59 =>      -- step 59: Select Register 0x1C
                                d_in <= x"001C";
                                state <= COMMAND_WR;
                            when 60 =>      -- step 60: Write 0x16 to Register 0x1C (bits 7:0 of vertical non-display - 1)
                                d_in <= x"0016";
                                state <= DATA_WR;
                            when 61 =>      -- step 61: Select Register 0x1D
                                d_in <= x"001D";
                                state <= COMMAND_WR;
                            when 62 =>      -- step 62: Write 0x00 to Register 0x1D (bits 9:8 of vertical non-display - 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 63 =>      -- step 63: Select Register 0x1E
                                d_in <= x"001E";
                                state <= COMMAND_WR;
                            when 64 =>      -- step 64: Write 0x0B to Register 0x1E (VSYNC Start Position - 1)
                                d_in <= x"000B";
                                state <= DATA_WR;
                            when 65 =>      -- step 65: Select Register 0x1F
                                d_in <= x"001F";
                                state <= COMMAND_WR;
                            when 66 =>      -- step 66: Write 0x09 to Register 0x1F (VSYNC Pulse width - 1)
                                d_in <= x"0009";
                                state <= DATA_WR;
                            -- SET RA8876 MAIN AND ACTIVE WINDOW
                            when 67 =>      -- step 67: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 68 =>      -- step 68: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            when 69 =>      -- step 69: Select Register 0x20
                                d_in <= x"0020";
                                state <= COMMAND_WR;
                            when 70 =>      -- step 70: Write 0x00 to Register 0x20 (Main Image Start Address byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 71 =>      -- step 71: Select Register 0x21
                                d_in <= x"0021";
                                state <= COMMAND_WR;
                            when 72 =>      -- step 72: Write 0x00 to Register 0x21 (Main Image Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 73 =>      -- step 73: Select Register 0x22
                                d_in <= x"0022";
                                state <= COMMAND_WR;
                            when 74 =>      -- step 74: Write 0x00 to Register 0x22 (Main Image Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 75 =>      -- step 75: Select Register 0x23
                                d_in <= x"0023";
                                state <= COMMAND_WR;
                            when 76 =>      -- step 76: Write 0x00 to Register 0x23 (Main Image Start Address byte 3)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 77 =>      -- step 77: Select Register 0x24
                                d_in <= x"0024";
                                state <= COMMAND_WR;
                            when 78 =>      -- step 78: Write 0x00 to Register 0x24 (bits 7:0 of main image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 79 =>      -- step 79: Select Register 0x25
                                d_in <= x"0025";
                                state <= COMMAND_WR;
                            when 80 =>      -- step 80: Write 0x04 to Register 0x25 (bits 12:8 of main image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 81 =>      -- step 81: Select Register 0x26
                                d_in <= x"0026";
                                state <= COMMAND_WR;
                            when 82 =>      -- step 82: Write 0x00 to Register 0x26 (Main Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 83 =>      -- step 83: Select Register 0x27
                                d_in <= x"0027";
                                state <= COMMAND_WR;
                            when 84 =>      -- step 84: Write 0x00 to Register 0x27 (Main Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 85 =>      -- step 85: Select Register 0x28
                                d_in <= x"0028";
                                state <= COMMAND_WR;
                            when 86 =>      -- step 86: Write 0x00 to Register 0x28 (Main Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 87 =>      -- step 87: Select Register 0x29
                                d_in <= x"0029";
                                state <= COMMAND_WR;
                            when 88 =>      -- step 88: Write 0x00 to Register 0x29 (Main Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 89 =>      -- step 89: Select Register 0x50
                                d_in <= x"0050";
                                state <= COMMAND_WR;
                            when 90 =>      -- step 90: Write 0x00 to Register 0x50 (Canvas Start Address byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 91 =>      -- step 91: Select Register 0x51
                                d_in <= x"0051";
                                state <= COMMAND_WR;
                            when 92 =>      -- step 92: Write 0x00 to Register 0x51 (Canvas Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 93 =>      -- step 93: Select Register 0x52
                                d_in <= x"0052";
                                state <= COMMAND_WR;
                            when 94 =>      -- step 94: Write 0x00 to Register 0x52 (Canvas Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 95 =>      -- step 95: Select Register 0x53
                                d_in <= x"0053";
                                state <= COMMAND_WR;
                            when 96 =>      -- step 96: Write 0x00 to Register 0x53 (Canvas Start Address byte 3)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 97 =>      -- step 97: Select Register 0x54
                                d_in <= x"0054";
                                state <= COMMAND_WR;
                            when 98 =>      -- step 98: Write 0x00 to Register 0x54 (bits 7:2 of canvas image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 99 =>      -- step 99: Select Register 0x55
                                d_in <= x"0055";
                                state <= COMMAND_WR;
                            when 100 =>     -- step 100: Write 0x04 to Register 0x55 (bits 12:8 of canvas image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 101 =>     -- step 101: Select Register 0x56
                                d_in <= x"0056";
                                state <= COMMAND_WR;
                            when 102 =>     -- step 102: Write 0x00 to Register 0x56 (Canvas Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 103 =>     -- step 103: Select Register 0x57
                                d_in <= x"0057";
                                state <= COMMAND_WR;
                            when 104 =>     -- step 104: Write 0x00 to Register 0x57 (Canvas Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 105 =>     -- step 105: Select Register 0x58
                                d_in <= x"0058";
                                state <= COMMAND_WR;
                            when 106 =>     -- step 106: Write 0x00 to Register 0x58 (Canvas Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 107 =>     -- step 107: Select Register 0x59
                                d_in <= x"0059";
                                state <= COMMAND_WR;
                            when 108 =>     -- step 108: Write 0x00 to Register 0x59 (Canvas Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 109 =>     -- step 109: Select Register 0x5A
                                d_in <= x"005A";
                                state <= COMMAND_WR;
                            when 110 =>     -- step 110: Write 0x00 to Register 0x5A (bits 7:0 of Active Window width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 111 =>     -- step 111: Select Register 0x5B
                                d_in <= x"005B";
                                state <= COMMAND_WR;
                            when 112 =>     -- step 112: Write 0x04 to Register 0x5B (bits 12:8 of Active Window width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 113 =>     -- step 113: Select Register 0x5C
                                d_in <= x"005C";
                                state <= COMMAND_WR;
                            when 114 =>     -- step 114: Write 0x58 to Register 0x5C (bits 7:0 of Active Window height = 0x58 for 600)
                                d_in <= x"0058";
                                state <= DATA_WR;
                            when 115 =>     -- step 115: Select Register 0x5D
                                d_in <= x"005D";
                                state <= COMMAND_WR;
                            when 116 =>     -- step 116: Write 0x02 to Register 0x5D (bits 12:8 of Active Window height = 0x02 for 600)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 117 =>     -- step 117: Select Register 0x5E
                                d_in <= x"005E";
                                state <= COMMAND_WR;
                            when 118 =>     -- step 118: Write 0x03 to Register 0x5E (X-Y coordinate mode, 24 bpp active canvas/window)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 119 =>     -- step 119: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 120 =>     -- step 120: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window - final)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            -- TURN ON DISPLAY WITH TEST PATTERN
                            when 121 =>     -- step 121: Turn on backlight and Select Register 0x12
                                bl   <= '1';
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 122 =>     -- step 122: Read Register 0x12
                                state <= DATA_RD;
                            when 123 =>     -- step 123: Assert bits 5 and 6 (Show Test Pattern and Turn on Screen)
                                d_in <= d_out OR "0000000001100000";    -- assert bits 5 and 6
                                state <= DATA_WR;
                            when 124 =>     -- step 124: Wait for 5 seconds
                                timer <= 250_000_000;
                                state <= WAIT_ST;
                            when 125 =>     -- step 125: Re-read Register 0x12 (required - why? Should stay in d_out, right?)
                                state <= DATA_RD;
                            when 126 =>     -- step 126: Clear bit 5 (still Register 0x12) to remove test pattern and proceed to IDLE state
                                d_in <= d_out AND "1111111111011111";   -- clear bit 5
                                state <= DATA_WR;
                                cmd_index <= 0;     -- reset the command index and go to IDLE
                                return_st <= IDLE;
                            when others =>
                                cmd_index <= 0;     -- failsafe - go back to the start if we get here
                                state <= INIT;
                        end case;

                    when IDLE =>
                        return_st <= IDLE;              -- return from other states to here by default
                        cmd_index <= cmd_index + 1;     -- go to next command index by default
                        case cmd_index is
                            when 0 =>       -- step 0: Select Register 0xD2
                                d_in <= x"00D2";
                                state <= COMMAND_WR;
                            when 1 =>       -- step 1: Write 0x80 to Register 0xD2 (Foreground Red)
                                d_in <= x"00FF";
                                state <= DATA_WR;
                            when 2 =>       -- step 2: Select Register 0xD3
                                d_in <= x"00D3";
                                state <= COMMAND_WR;
                            when 3 =>       -- step 3: Write 0x80 to Register 0xD3 (Foreground Green)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 4 =>       -- step 4: Select Register 0xD4
                                d_in <= x"00D4";
                                state <= COMMAND_WR;
                            when 5 =>       -- step 5: Write 0x80 to Register 0xD4 (Foreground Blue)
                                d_in <= "00000000" & std_logic_vector(to_unsigned(blue, 8));
                                blue <= (blue + 1);
                                state <= DATA_WR;
                            when 6 =>       -- step 6: Select Register 0x68
                                d_in <= x"0068";
                                state <= COMMAND_WR;
                            when 7 =>       -- step 7: Write 0x20 to Register 0x68 (Line Start X low byte = 0x20)
                                d_in <= x"0020";
                                state <= DATA_WR;
                            when 8 =>       -- step 8: Select Register 0x69
                                d_in <= x"0069";
                                state <= COMMAND_WR;
                            when 9 =>       -- step 9: Write 0x00 to Register 0x69 (Line Start X high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 10 =>      -- step 10: Select Register 0x6A
                                d_in <= x"006A";
                                state <= COMMAND_WR;
                            when 11 =>      -- step 11: Write 0x20 to Register 0x6A (Line Start Y low byte = 0x20)
                                d_in <= x"0020";
                                state <= DATA_WR;
                            when 12 =>      -- step 12: Select Register 0x6B
                                d_in <= x"006B";
                                state <= COMMAND_WR;
                            when 13 =>      -- step 13: Write 0x00 to Register 0x6B (Line Start Y high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 14 =>      -- step 14: Select Register 0x6C
                                d_in <= x"006C";
                                state <= COMMAND_WR;
                            when 15 =>      -- step 15: Write 0xE0 to Register 0x6C (Line End X low byte = 0xE0)
                                d_in <= x"00E0";
                                state <= DATA_WR;
                            when 16 =>      -- step 16: Select Register 0x6D
                                d_in <= x"006D";
                                state <= COMMAND_WR;
                            when 17 =>      -- step 17: Write 0x03 to Register 0x6D (Line End X high byte = 0x03)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 18 =>      -- step 18: Select Register 0x6E
                                d_in <= x"006E";
                                state <= COMMAND_WR;
                            when 19 =>      -- step 19: Write 0x38 to Register 0x6E (Line End Y low byte = 0x38)
                                d_in <= x"0038";
                                state <= DATA_WR;
                            when 20 =>      -- step 20: Select Register 0x6F
                                d_in <= x"006F";
                                state <= COMMAND_WR;
                            when 21 =>      -- step 21: Write 0x02 to Register 0x6F (Line End Y high byte = 0x02)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 22 =>      -- step 22: read Status register
                                state <= STATUS_RD;
                            when 23 =>      -- step 23: if status bit 3 is 1, go back to step 3 (Core Task is Busy)
                                if d_out(1) = '1' then
                                    cmd_index <= 22;    -- still busy, check again
                                end if;
                            when 24 =>      -- step 24: Select register 0x67
                                d_in <= x"0067";
                                state <= COMMAND_WR;
                            when 25 =>      -- step 25: Read Register 0x67
                                state <= DATA_RD;
                            when 26 =>      -- step 26: Check to see if bit 7 is set (line/triangle drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 25;    -- still busy, check again
                                end if;
                            when 27 =>      -- step 27: Select Register 0x76
                                d_in <= x"0076";
                                state <= COMMAND_WR;
                            when 28 =>      -- step 28: Read Register 0x76
                                state <= DATA_RD;
                            when 29 =>      -- step 29: Check to see if bit 7 is set (ellipse/curve/square) drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 28;    -- still busy, check again
                                end if;
                            when 30 =>      -- step 30: Write 0xE0 to register 0x76 (Draw the filled square)
                                d_in <= x"00E0";
                                state <= DATA_WR;
                            when others =>
                                cmd_index <= 0;    -- loop forever
                        end case;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end RTL;