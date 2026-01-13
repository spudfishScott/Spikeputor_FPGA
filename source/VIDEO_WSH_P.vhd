-- Wishbone Provider for Video Coprocessor and Video Memory Mapped I/O
-- For now, this is a simple wishbone provider that maps a fixed address range to read/write the video coprocessor registers and data
-- In the future, may change this to be a higher level graphics engine that handles drawing operations, etc.
-- Simple read or write 0xFFxx addresses to access the video coprocessor registers and data. Registers that shouldn't be exposed will return 0x0000 and will ignore writes.
-- Note that the lsb of the address is NOT ignored here.
-- The STATUS register is read via location 0xFF00. Writes to 0xFF00 are ignored. Actual video register 0 is not exposed.
-- Certain registers accept/produce an entire word (16 bits) at once, others are byte-wide only. See "word_flg" signal assignment for details.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity VIDEO_WSH_P is
    generic ( CLK_FREQ : integer := 50_000_000 );            -- system clock frequency in Hz
    port (
        -- Clock Input
        CLK         : in std_logic;                          -- System Clock
        RST_I       : in std_logic;                          -- System Reset

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ACK_O   : out std_logic;

        -- memory read/write signals
        WBS_ADDR_I  : in std_logic_vector(23 downto 0);     -- lsb is NOT ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to master
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from master
        WBS_WE_I    : in std_logic;                         -- write enable input - when high, master is writing, when low, master is reading

        -- Video Chip control signals
        SCRN_CTRL   : out   std_logic_vector(5 downto 0);    -- Screen Control output only (BL_CTL, /RESET, /CS, /WR, /RD, RS) GPIO0 7 -> 2
        SCRN_WAIT_N : in    std_logic;                       -- /WAIT signal input only (GPIO0 8)
        SCRN_DATA   : inout std_logic_vector(15 downto 0)    -- DATAIO signal (GPIO0 24 -> 9)
    );
end VIDEO_WSH_P;

architecture RTL of VIDEO_WSH_P is

    -- constants for timing control - RA8876 is slower than we are
    constant CMD_REFRESH_TIME  : Integer := 8;  -- 8 ticks between end of last read/write data command and availability to do next command (160 ns)
    constant CMD_CS_DIFF : Integer := 2;        -- 40 ns between /CS low and nRD/nWR high
    constant CMD_HOLD_TIME : Integer := 1;      -- 20 ns between nRD/nWR high and /CS high

    -- Video control signals
    signal bl           : std_logic := '0';                                     -- Backlight control
    signal n_res        : std_logic := '1';                                     -- /RESET signal
    signal n_cs         : std_logic := '1';                                     -- /CS signal (see if it can always just be on)
    signal rs           : std_logic := '0';                                     -- RS signal - default to STATUS read/Command Write
    signal n_rd         : std_logic := '1';                                     -- /RD signal
    signal n_wr         : std_logic := '1';                                     -- /WR signal
    signal d_out        : std_logic_vector(15 downto 0) := (others => '0');     -- Data Out from screen controller
    signal d_in         : std_logic_vector(15 downto 0) := (others => '0');     -- Data In to screen controller
    signal db_oe        : std_logic := '0';                                     -- data bus output enable - set to 1 when sending to screen controller

    -- Wishbone interface signals
    signal ack      : std_logic := '0';                                         -- internal ack signal
    signal reg_r    : std_logic_vector(7 downto 0) := x"FF";                    -- current register selected (0xFF = ignored)
    signal prev_reg     : std_logic_vector(7 downto 0) := x"FF";                -- previous register selected (for detecting changes)

    -- Counters and indeces for initialization sequence
    signal timer        : Integer := 0;                                         -- timer counter
    signal cmd_index    : Integer := 0;                                         -- command index for multi-step commands
    signal status_check : std_logic := '0';                                     -- status register check flag for multi-check commands
    signal reset_done   : std_logic := '0';                                     -- flag to indicate initialization is done
    signal powerup_done : std_logic := '0';                                     -- flag to indicate powerup sequence is done

    -- write both bytes of word-length registers
    signal lo_byte      : std_logic_vector(7 downto 0) := (others => '0');      -- lower byte for word writes (goes in REG)
    signal hi_byte      : std_logic_vector(7 downto 0) := (others => '0');      -- upper byte for word writes (goes in REG+1)
    signal word_flg     : std_logic := '0';                                     -- when '1', the register and reg+1 make up a 16-bit value to store/read - little endian
    signal make_word    : std_logic := '0';                                     -- flag to indicate that a word is being read and the two bytes need to be combined


    type state_type is (IDLE, ACK_CLEAR, WSH_READ, WSH_WRITE, STATUS_RD, COMMAND_WR, DATA_RD, DATA_WR, WAIT_ST, INIT, RD4, WR4, WORD_RD, WORD_WR);
    signal state        : state_type := INIT;
    signal return_st    : state_type := INIT;

begin
    -- signals mapped to pin outputs
    SCRN_CTRL(5) <= bl;
    SCRN_CTRL(4) <= n_res;
    SCRN_CTRL(3) <= n_cs;
    SCRN_CTRL(2) <= n_wr;
    SCRN_CTRL(1) <= n_rd;
    SCRN_CTRL(0) <= rs;

    -- send d_in into the screen controller when db_oe is 1, otherwise set data_out to screen controller output
    SCRN_DATA(15 downto 0) <= d_in when db_oe = '1' else (others => 'Z');

    -- output to Wishbone interface
    WBS_ACK_O      <= ack AND WBS_CYC_I AND WBS_STB_I;
    WBS_DATA_O     <= d_out;                           -- output read data register to Wishbone data output

    with WBS_ADDR_I(7 downto 0) select
        reg_r <=                        -- register to read/write comes from lsb of Wishbone address unless it's blocked (see "Video Interface Notes")
            WBS_ADDR_I(7 downto 0) when x"00" | x"03" | x"04" | x"10" | x"11" | x"20" to x"45" | x"50" to x"73" | 
                                        x"76" to x"7E" | x"90" to x"B5" | x"CC" | x"CD" | x"CF" to X"D7" | x"DB" to x"DE",
                             x"FF" when others;

    with WBS_ADDR_I(7 downto 0) select
        word_flg <=                     -- when '1', the register and reg+1 make up a 16-bit value to store/read - little endian
            '0' when x"00" | x"03" | x"04" | x"10" | x"11" | x"21" | x"23" | x"25" | x"27" | x"29" | x"2B" | x"2D" |
                     x"2F" | x"31" | x"33" | x"35" | x"37" | x"39" | x"3B" to x"3F" | x"41" | x"43" | x"44" | x"45" | 
                     x"51" | x"53" | x"55" | x"57" | x"59" | x"5B" | x"5D" | x"5E" | x"60" | x"62" | x"64" | x"66" | x"67" |
                     x"69" | x"6B" | x"6D" | x"6F" | x"71" | x"73" | x"76" | x"78" | x"7A" | x"7C" | x"7E" | x"90" | x"91" | 
                     x"94" | x"96" | x"98" | x"9A" | x"9C" | x"9E" | x"A0" | x"A2" | x"A4" | x"A6" | x"A8" | x"AA" | x"AC" | 
                     x"AE" | x"B0" | x"B2" | x"B4" | x"B5" | x"CC" | x"CD" | x"CF" to x"D7" | x"DC" | x"DE",
            '1' when others;

    process(CLK) is
    begin
        if rising_edge(CLK) then
            if RST_I = '1' then         -- reset button pushed, clear state machine and all counters
                state     <= INIT;      -- set state to initialize the contoller
                return_st <= INIT;      -- reset the return state as well
                timer     <= 0;         -- reset timer and command index
                status_check <= '0';    -- reset status check flag
                
                if powerup_done = '0' then
                    cmd_index <= 0;
                    n_res     <= '1';   -- set chip reset high to begin power up sequence
                else
                    cmd_index <= 67;    -- if already powered up, skip to warm reset portion
                end if;

                reset_done <= '0';  -- clear reset done flag

                bl        <= '0';   -- turn off backlight
                n_rd      <= '1';   -- reset control signals
                n_wr      <= '1';
                n_cs      <= '1';
                rs        <= '0';
                db_oe     <= '0';
                d_out <= (others => '0');   -- reset data in/out
                d_in  <= (others => '0');

                ack    <= '0';              -- clear ack signal
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
                        timer <= timer + 1;
                        if timer = 0 then
                            n_cs <= '0';                -- start command
                            rs   <= '0';
                            n_rd <= '0';                -- rs = 0, n_rd = 0 -> read status
                        elsif timer = CMD_CS_DIFF then
                            n_rd <= '1';                -- complete read command
                            d_out(15 downto 8) <= (others => '0');
                            d_out(7 downto 0) <= SCRN_DATA(7 downto 0);     -- latch data (lower 8 bits only) into data_out
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            n_cs <= '1';                -- complete command
                            timer <= 0;                 -- one tick delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when COMMAND_WR =>
                        timer <= timer + 1;
                        if timer = 0 then
                            db_oe <= '1';               -- puts d_in onto the inout bus
                            n_cs <= '0';                -- start command
                            rs   <= '0';
                            n_wr <= '0';                -- rs = 0, n_wr = 0 -> write command
                        elsif timer = CMD_CS_DIFF then
                              n_wr  <= '1';             -- complete write command
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            n_cs  <= '1';               -- complete command
                            db_oe <= '0';               -- set inout bus to input again
                            timer <= 0;                 -- one tick delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when DATA_RD =>
                        timer <= timer + 1;
                        if timer = 0 then
                            n_cs <= '0';                -- start command
                            rs   <= '1';
                            n_rd <= '0';                -- rs = 1, n_rd = 0 -> read data
                        elsif timer = CMD_CS_DIFF then
                            n_rd <= '1';                -- complete read command
                            d_out <= SCRN_DATA(15 downto 0);    -- latch data (all 16 bits) into register
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            if (WBS_CYC_I = '1' AND WBS_STB_I = '1' AND reset_done = '1' AND word_flg = '0') then
                                ack <= '1';             -- assert ack now that data is read or written (don't do that yet for first byte of word reads)
                            end if;
                            if (make_word = '1') then
                                d_out <= d_out(7 downto 0) & lo_byte;   -- combine upper and lower bytes into data out
                                make_word <= '0';
                                ack <= '1';             -- assert ack now that full word data is read or written
                            end if;
                            n_cs <= '1';                -- complete command
                            timer <= CMD_REFRESH_TIME;  -- set timer to delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when DATA_WR =>
                        timer <= timer + 1;
                        if timer = 0 then
                            db_oe <= '1';               -- puts d_in onto the inout bus
                            n_cs <= '0';
                            rs   <= '1';
                            n_wr <= '0';                -- rs = 1, n_wr = 0 -> write data
                            state <= DATA_WR;           -- hold in this state for one clock cycle
                        elsif timer = CMD_CS_DIFF then
                            n_wr  <= '1';               -- complete write command
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            if (WBS_CYC_I = '1' AND WBS_STB_I = '1' AND reset_done = '1') then
                                ack <= '1';             -- assert ack now that data is read or written
                            end if;
                            n_cs  <= '1';               -- complete command
                            db_oe <= '0';               -- set inout bus to input again
                            timer <= CMD_REFRESH_TIME;  -- set timer to delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when IDLE =>
                        if (WBS_CYC_I ='1' AND WBS_STB_I = '1') then    -- new transaction requested

                            if WBS_WE_I = '0' then          -- read operation
                                if reg_r = x"00" then
                                    state <= STATUS_RD;          -- read status register
                                    return_st <= ACK_CLEAR;      -- after reading status, finish wishbone transaction
                                elsif reg_r /= x"FF" then        -- register to read is exposed
                                    if prev_reg = reg_r AND reg_r = x"04" then  -- handle register 4 multi-read logic (need to wait until STATUS bit 4 is cleared before next read (Memory Read FIFO not empty))
                                        status_check <= '0';     -- reset command index to for multi command RD4 state
                                        state <= RD4;            -- if reading register 4 repeatedly, poll status until FIFO not empty and read next data
                                    else
                                        d_in <= "00000000" & reg_r;  -- load register address to read
                                        if word_flg = '0' then   -- single byte register
                                            state <= COMMAND_WR;               -- write command to select register
                                            return_st <= WSH_READ;             -- after selecting register, go to read state
                                        else                     -- word-length register
                                            cmd_index <= 0;                    -- reset command index for word read sequence
                                            state <= WORD_RD;                  -- go to word read state
                                        end if;
                                    end if;
                                else
                                    d_out <= (others => '0');    -- register is blocked, return zero data
                                    state <= ACK_CLEAR;          -- finish wishbone transaction
                                end if;
                            else                            -- write operation
                                lo_byte <= WBS_DATA_I(7 downto 0);    -- store lower byte of data input
                                hi_byte <= WBS_DATA_I(15 downto 8);   -- store upper byte of data input

                                if reg_r /= x"00" AND reg_r /= x"FF" then  -- register to write is exposed
                                    if prev_reg = reg_r AND reg_r = x"04" then  -- handle register 4 multi-write logic (need to wait until STATUS bit 7 is cleared before next write (Memory Write FIFO not full))
                                        status_check <= '0';     -- reset command index to for multi command WR4 state
                                        state <= WR4;            -- if writing register 4 repeatedly, poll status until FIFO not full and write next data
                                    else
                                        d_in <= "00000000" & reg_r;  -- load register address to write
                                        state <= COMMAND_WR;         -- write command to select register
                                        return_st <= WSH_WRITE;      -- after selecting register, go to write state
                                    end if;
                                else                             -- register is blocked, do nothing
                                    ack <= '1';                  -- acknowledge wishbone write
                                    state <= ACK_CLEAR;          -- register is blocked, finish wishbone transaction doing nothing
                                end if;
                            end if;
                            prev_reg <= reg_r;    -- store previous register for detecting changes
                        else
                            state <= IDLE;                       -- stay in IDLE state
                        end if;

                    when WSH_READ =>
                        state <= DATA_RD;                  -- read data from selected register
                        return_st <= ACK_CLEAR;            -- after reading data, finish wishbone transaction

                    when WSH_WRITE =>
                        d_in <= WBS_DATA_I(15 downto 0);   -- load data to write to register
                        state <= DATA_WR;                  -- write data to selected register and set ack
                        return_st <= ACK_CLEAR;            -- after writing data, finish wishbone transaction

                    when ACK_CLEAR =>
                        if (WBS_CYC_I = '1' AND WBS_STB_I = '1' AND ack = '0') then
                            ack <= '1';                    -- if ack hasn't already been set and wishbone cycle still active - assert ack
                            state <= ACK_CLEAR;            -- and stay here until master deasserts CYC or STB
                        else                               -- otherwise, return to idle state to wait for next wishbone cycle
                            state <= IDLE;
                            return_st <= IDLE;
                            timer <= 0;
                        end if;

                    when RD4 =>                     -- multi-read state for register 0x04 (Memory Read FIFO)
                        return_st <= RD4;               -- return state is set back here by default
                        if status_check = '0' then
                            state <= STATUS_RD;          -- read status register
                            status_check <= '1';         -- set flag to indicate status has been checked
                        else
                            if d_out(4) = '1' then       -- check if FIFO not empty
                                status_check <= '0';        -- if empty, check status again
                            else
                                state <= DATA_RD;           -- not empty, so read data from register 0x04
                                return_st <= ACK_CLEAR;     -- after reading data, finish wishbone transaction
                            end if;
                        end if;

                    when WR4 =>                     -- multi-write state for register 0x04 (Memory Write FIFO)
                        return_st <= WR4;               -- return state is always set here for WAIT and read/write calls
                        if status_check = '0' then
                            state <= STATUS_RD;          -- read status register
                            status_check <= '1';         -- set flag to indicate status has been checked
                        else
                            if d_out(7) = '1' then       -- check if FIFO not full
                                status_check <= '0';        -- if full, check status again
                            else
                                d_in <= WBS_DATA_I(15 downto 0);    -- not full, so load data to write to register
                                state <= DATA_WR;                   -- write data to register 0x04
                                return_st <= ACK_CLEAR;             -- after writing data, finish wishbone transaction
                            end if;
                        end if;

                    when WORD_RD =>                 -- read word-length register
                        return_st <= WORD_RD;           -- return state is always set here
                        cmd_index <= cmd_index + 1;     -- complete each step in turn, so index is incremented by default each time through this state
                        case cmd_index is
                            when 0 =>               -- step 0: select register for lower byte read
                                d_in <= "00000000" & reg_r;  -- load register address to read (lower byte)
                                state <= COMMAND_WR;
                            when 1 =>               -- step 1: read lower byte
                                state <= DATA_RD;
                            when 2 =>               -- step 2: store lower byte and select register for upper byte
                                lo_byte <= d_out(7 downto 0);     -- store lower byte temporarily
                                d_in <= "00000000" & std_logic_vector(unsigned(reg_r) + 1);  -- load register address to read (upper byte)
                                state <= COMMAND_WR;
                            when 3 =>               -- step 3: read upper byte
                                make_word <= '1';       -- set flag to indicate that a word is being read and the two bytes need to be combined
                                state <= DATA_RD;
                                return_st <= ACK_CLEAR;
                            when others =>          -- should not occur, but just in case
                                state <= ACK_CLEAR;
                        end case;

                    when INIT =>            -- go through the display reset and initialization sequence
                        return_st <= INIT;              -- return state is always set here for WAIT and read/write calls
                        cmd_index <= cmd_index + 1;     -- complete each step in turn, so index is incremented by default each time through this state
                        case cmd_index is
                            -- POWER UP CYCLE - WAIT - HW RESET - WAIT
                            when 0 =>       -- step 0: delay 100 ms (5,000,000 cycles at 20 ns per cycle)
                                timer <= CLK_FREQ / 10;         -- 100 ms delay
                                state <= WAIT_ST;
                            when 1 =>       -- step 1: set /RESET low on the chip and delay for 100 ms
                                n_res <= '0';
                                timer <= CLK_FREQ / 10;         -- 100 ms delay
                                state <= WAIT_ST;
                            when 2 =>       -- step 2: set /RESET high on the chip and delay 150 ms
                                n_res <= '1';
                                timer <= CLK_FREQ * 3 / 20;     -- 150 ms delay
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
                            when 8 =>       -- step 8: re-read register 0
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
                            when 37 =>       -- step 37: read Register 0xE4
                                state <= DATA_RD;
                            when 38 =>       -- step 38: if bit 0 is 0, go back to step 37
                                if d_out(0) = '0' then
                                    cmd_index <= 37;
                                end if;
                            -- ADDITIONAL CHIP CONFIG
                            when 39 =>      -- step 39: Select Register 0x01
                                d_in <= x"0001";
                                state <= COMMAND_WR;
                            when 40 =>      -- step 40: Write 0x01 to Register 0x01 (24-bit TFT output, 16-bit Host Data Bus)
                                d_in <= x"0001";
                                state <= DATA_WR;
                            -- REGISTERS 0x02 and 0x03 STAY AT THEIR DEFAULT VALUES FOR NOW
                            -- SET SCREEN PARAMETERS AND TIMING
                            when 41 =>      -- step 41: Select Register 0x12
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 42 =>      -- step 42: Write 0x80 to Register 0x12 (Set screen data for fetching on falling clock)
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 43 =>      -- step 43: Select Register 0x13
                                d_in <= x"0013";
                                state <= COMMAND_WR;
                            when 44 =>      -- step 44: Write 0xC3 to Register 0x13 (DE active high, HSYNC and VSYNC active high)
                                d_in <= x"00C3";
                                state <= DATA_WR;
                            when 45 =>      -- step 45: Select Register 0x14
                                d_in <= x"0014";
                                state <= COMMAND_WR;
                            when 46 =>      -- step 46: Write 0x7F to Register 0x14 (bits 11:4 of display width - 1 for 1024 pixels)
                                d_in <= x"007F";
                                state <= DATA_WR;
                            when 47 =>      -- step 47: Select Register 0x15
                                d_in <= x"0015";
                                state <= COMMAND_WR;
                            when 48 =>      -- step 48: Write 0x00 to Register 0x15 (bits 3:0 of display width)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 49 =>      -- step 49: Select Register 0x1A
                                d_in <= x"001A";
                                state <= COMMAND_WR;
                            when 50 =>      -- step 50: Write 0x57 to Register 0x1A (bits 7:0 of display height - 1 for 600 pixels)
                                d_in <= x"0057";
                                state <= DATA_WR;
                            when 51 =>      -- step 51: Select Register 0x1B
                                d_in <= x"001B";
                                state <= COMMAND_WR;
                            when 52 =>      -- step 52: Write 0x02 to Register 0x1B (bits 10:8 of display height - 1 for 600 pixels)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 53 =>      -- step 53: Select Register 0x16
                                d_in <= x"0016";
                                state <= COMMAND_WR;
                            when 54 =>      -- step 54: Write 0x13 to Register 0x16 (bits 8:4 of back porch - 1)
                                d_in <= x"0013";
                                state <= DATA_WR;
                            when 55 =>      -- step 55: Select Register 0x17
                                d_in <= x"0017";
                                state <= COMMAND_WR;
                            when 56 =>      -- step 56: Write 0x00 to Register 0x17 (bits 3:0 of back porch)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 57 =>      -- step 57: Select Register 0x18
                                d_in <= x"0018";
                                state <= COMMAND_WR;
                            when 58 =>      -- step 58: Write 0x14 to Register 0x18 (front porch / 8 for back porch 160)
                                d_in <= x"0014";
                                state <= DATA_WR;
                            when 59 =>      -- step 59: Select Register 0x19
                                d_in <= x"0019";
                                state <= COMMAND_WR;
                            when 60 =>      -- step 60: Write 0x07 to Register 0x19 (pulse width / 8 - 1 for HSYNC pulse width 70)
                                d_in <= x"0007";
                                state <= DATA_WR;
                            when 61 =>      -- step 61: Select Register 0x1C
                                d_in <= x"001C";
                                state <= COMMAND_WR;
                            when 62 =>      -- step 62: Write 0x16 to Register 0x1C (bits 7:0 of vertical non-display - 1)
                                d_in <= x"0016";
                                state <= DATA_WR;
                            when 63 =>      -- step 63: Select Register 0x1D
                                d_in <= x"001D";
                                state <= COMMAND_WR;
                            when 64 =>      -- step 64: Write 0x00 to Register 0x1D (bits 9:8 of vertical non-display - 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 65 =>      -- step 65: Select Register 0x1E
                                d_in <= x"001E";
                                state <= COMMAND_WR;
                            when 66 =>      -- step 66: Write 0x0B to Register 0x1E (VSYNC Start Position - 1)
                                d_in <= x"000B";
                                state <= DATA_WR;
                            when 67 =>      -- step 67: Select Register 0x1F
                                d_in <= x"001F";
                                state <= COMMAND_WR;
                            when 68 =>      -- step 68: Write 0x09 to Register 0x1F (VSYNC Pulse width - 1)
                                d_in <= x"0009";
                                state <= DATA_WR;
                            -- SET RA8876 MAIN AND ACTIVE WINDOW - WARM RESET ENTRY POINT
                            when 69 =>      -- step 69: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 70 =>      -- step 70: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            when 71 =>      -- step 71: Select Register 0x20
                                d_in <= x"0020";
                                state <= COMMAND_WR;
                            when 72 =>      -- step 72: Write 0x00 to Register 0x20 (Main Image Start Address byte 0 - least significant byte)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 73 =>      -- step 73: Select Register 0x21
                                d_in <= x"0021";
                                state <= COMMAND_WR;
                            when 74 =>      -- step 74: Write 0x00 to Register 0x21 (Main Image Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 75 =>      -- step 75: Select Register 0x22
                                d_in <= x"0022";
                                state <= COMMAND_WR;
                            when 76 =>      -- step 76: Write 0x00 to Register 0x22 (Main Image Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 77 =>      -- step 77: Select Register 0x23
                                d_in <= x"0023";
                                state <= COMMAND_WR;
                            when 78 =>      -- step 78: Write 0x00 to Register 0x23 (Main Image Start Address byte 3 - most significant byte)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 79 =>      -- step 79: Select Register 0x24
                                d_in <= x"0024";
                                state <= COMMAND_WR;
                            when 80 =>      -- step 80: Write 0x00 to Register 0x24 (bits 7:0 of main image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 81 =>      -- step 81: Select Register 0x25
                                d_in <= x"0025";
                                state <= COMMAND_WR;
                            when 82 =>      -- step 82: Write 0x04 to Register 0x25 (bits 12:8 of main image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 83 =>      -- step 83: Select Register 0x26
                                d_in <= x"0026";
                                state <= COMMAND_WR;
                            when 84 =>      -- step 84: Write 0x00 to Register 0x26 (Main Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 85 =>      -- step 85: Select Register 0x27
                                d_in <= x"0027";
                                state <= COMMAND_WR;
                            when 86 =>      -- step 86: Write 0x00 to Register 0x27 (Main Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 87 =>      -- step 87: Select Register 0x28
                                d_in <= x"0028";
                                state <= COMMAND_WR;
                            when 88 =>      -- step 88: Write 0x00 to Register 0x28 (Main Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 89 =>      -- step 89: Select Register 0x29
                                d_in <= x"0029";
                                state <= COMMAND_WR;
                            when 90 =>      -- step 90: Write 0x00 to Register 0x29 (Main Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 91 =>      -- step 91: Select Register 0x50
                                d_in <= x"0050";
                                state <= COMMAND_WR;
                            when 92 =>      -- step 92: Write 0x00 to Register 0x50 (Canvas Start Address byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 93 =>      -- step 93: Select Register 0x51
                                d_in <= x"0051";
                                state <= COMMAND_WR;
                            when 94 =>      -- step 94: Write 0x00 to Register 0x51 (Canvas Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 95 =>      -- step 95: Select Register 0x52
                                d_in <= x"0052";
                                state <= COMMAND_WR;
                            when 96 =>      -- step 96: Write 0x00 to Register 0x52 (Canvas Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 97 =>      -- step 97: Select Register 0x53
                                d_in <= x"0053";
                                state <= COMMAND_WR;
                            when 98 =>      -- step 98: Write 0x00 to Register 0x53 (Canvas Start Address byte 3)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 99 =>      -- step 99: Select Register 0x54
                                d_in <= x"0054";
                                state <= COMMAND_WR;
                            when 100 =>     -- step 100: Write 0x00 to Register 0x54 (bits 7:2 of canvas image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 101 =>     -- step 101: Select Register 0x55
                                d_in <= x"0055";
                                state <= COMMAND_WR;
                            when 102 =>     -- step 102: Write 0x04 to Register 0x55 (bits 12:8 of canvas image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 103 =>     -- step 103: Select Register 0x56
                                d_in <= x"0056";
                                state <= COMMAND_WR;
                            when 104 =>     -- step 104: Write 0x00 to Register 0x56 (Canvas Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 105 =>     -- step 105: Select Register 0x57
                                d_in <= x"0057";
                                state <= COMMAND_WR;
                            when 106 =>     -- step 106: Write 0x00 to Register 0x57 (Canvas Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 107 =>     -- step 107: Select Register 0x58
                                d_in <= x"0058";
                                state <= COMMAND_WR;
                            when 108 =>     -- step 108: Write 0x00 to Register 0x58 (Canvas Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 109 =>     -- step 109: Select Register 0x59
                                d_in <= x"0059";
                                state <= COMMAND_WR;
                            when 110 =>     -- step 110: Write 0x00 to Register 0x59 (Canvas Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 111 =>     -- step 111: Select Register 0x5A
                                d_in <= x"005A";
                                state <= COMMAND_WR;
                            when 112 =>     -- step 112: Write 0x00 to Register 0x5A (bits 7:0 of Active Window width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 113 =>     -- step 113: Select Register 0x5B
                                d_in <= x"005B";
                                state <= COMMAND_WR;
                            when 114 =>     -- step 114: Write 0x04 to Register 0x5B (bits 12:8 of Active Window width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 115 =>     -- step 115: Select Register 0x5C
                                d_in <= x"005C";
                                state <= COMMAND_WR;
                            when 116 =>     -- step 116: Write 0x58 to Register 0x5C (bits 7:0 of Active Window height = 0x58 for 600)
                                d_in <= x"0058";
                                state <= DATA_WR;
                            when 117 =>     -- step 117: Select Register 0x5D
                                d_in <= x"005D";
                                state <= COMMAND_WR;
                            when 118 =>     -- step 118: Write 0x02 to Register 0x5D (bits 12:8 of Active Window height = 0x02 for 600)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 119 =>     -- step 119: Select Register 0x5E
                                d_in <= x"005E";
                                state <= COMMAND_WR;
                            when 120 =>     -- step 120: Write 0x03 to Register 0x5E (X-Y coordinate mode, 24 bpp active canvas/window)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 121 =>     -- step 121: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 122 =>     -- step 122: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window - final)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            when 123 =>       -- step 123: Select Register 0xD2 - CLEAR SCREEN FROM HERE ON DOWN
                                if powerup_done = '1' then
                                    reset_done <= '1';  -- set reset done flag
                                    cmd_index  <= 155;  -- skip clear screen if already powered up
                                else
                                    d_in <= x"00D2";    -- otherwise, continue power-up sequence
                                    state <= COMMAND_WR;
                                end if;
                            when 124 =>       -- step 124: Write 0x00 to Register 0xD2 (Foreground Red)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 125 =>       -- step 125: Select Register 0xD3
                                d_in <= x"00D3";
                                state <= COMMAND_WR;
                            when 126 =>       -- step 126 Write 0x00 to Register 0xD3 (Foreground Green)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 127 =>       -- step 127: Select Register 0xD4
                                d_in <= x"00D4";
                                state <= COMMAND_WR;
                            when 128 =>       -- step 128: Write 0x80 to Register 0xD4 (Foreground Blue) - set color to dark blue
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 129 =>       -- step 129: Select Register 0x68
                                d_in <= x"0068";
                                state <= COMMAND_WR;
                            when 130 =>       -- step 130: Write 0x00 to Register 0x68 (Line Start X low byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 131 =>       -- step 131: Select Register 0x69
                                d_in <= x"0069";
                                state <= COMMAND_WR;
                            when 132 =>       -- step 132: Write 0x00 to Register 0x69 (Line Start X high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 133 =>      -- step 133: Select Register 0x6A
                                d_in <= x"0000";
                                state <= COMMAND_WR;
                            when 134 =>      -- step 134: Write 0x00 to Register 0x6A (Line Start Y low byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 135 =>      -- step 135: Select Register 0x6B
                                d_in <= x"006B";
                                state <= COMMAND_WR;
                            when 136 =>      -- step 136: Write 0x00 to Register 0x6B (Line Start Y high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 137 =>      -- step 137: Select Register 0x6C
                                d_in <= x"006C";
                                state <= COMMAND_WR;
                            when 138 =>      -- step 138: Write 0xFF to Register 0x6C (Line End X low byte = 0xFF)
                                d_in <= x"00FF";
                                state <= DATA_WR;
                            when 139 =>      -- step 139: Select Register 0x6D
                                d_in <= x"006D";
                                state <= COMMAND_WR;
                            when 140 =>      -- step 140: Write 0x03 to Register 0x6D (Line End X high byte = 0x03) X end = 1023 = 0x3FF
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 141 =>      -- step 141: Select Register 0x6E
                                d_in <= x"006E";
                                state <= COMMAND_WR;
                            when 142 =>      -- step 142: Write 0x57 to Register 0x6E (Line End Y low byte = 0x57)
                                d_in <= x"0057";
                                state <= DATA_WR;
                            when 143 =>      -- step 143: Select Register 0x6F
                                d_in <= x"006F";
                                state <= COMMAND_WR;
                            when 144 =>      -- step 144: Write 0x02 to Register 0x6F (Line End Y high byte = 0x02) Y end = 599 = 0x257
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 145 =>      -- step 145: read Status register
                                state <= STATUS_RD;
                            when 146 =>      -- step 146: if status bit 3 is 1, go back to step 145 (Core Task is Busy)
                                if d_out(3) = '1' then
                                    cmd_index <= 145;    -- still busy, check again
                                end if;
                            when 147 =>      -- step 147: Select register 0x76
                                d_in <= x"0076";
                                state <= COMMAND_WR;
                            when 148 =>      -- step 148: Write 0xE0 to register 0x76 (Draw the filled square to clear the screen)
                                d_in <= x"00E0";
                                state <= DATA_WR;
                            when 149 =>     -- step 149: Select register 0x67
                                d_in <= x"0067";
                                state <= COMMAND_WR;
                            when 150 =>      -- step 150: Read Register 0x67
                                state <= DATA_RD;
                            when 151 =>      -- step 151: Check to see if bit 7 is set (line/triangle drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 150;    -- still busy, check again
                                end if;
                            when 152 =>      -- step 152: Select Register 0x76
                                d_in <= x"0076";
                                state <= COMMAND_WR;
                            when 153 =>      -- step 153: Read Register 0x76
                                state <= DATA_RD;
                            when 154 =>      -- step 154: Check to see if bit 7 is set (ellipse/curve/square) drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 153;    -- still busy, check again
                                end if;
                            when 155 =>     -- step 155: Drawing completed, turn on backlight and Select Register 0x12
                                bl   <= '1';
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 156 =>     -- step 156: Read Register 0x12
                                state <= DATA_RD;
                            when 157 =>     -- step 157: Assert bit 6 (Turn on Screen) and write register 0x12
                                d_in <= d_out OR "0000000001000000";    -- assert bit 6
                                state <= DATA_WR;
                                powerup_done <= '1';     -- indicate power up is done
                                return_st <= IDLE;       -- and go to idle when done
                            when others =>
                                cmd_index <= 0;     -- failsafe - go back to the start if we get here
                                state <= INIT;
                        end case;

                    when others =>                         -- should never happen
                        null;
                end case;

                if (WBS_CYC_I = '0' OR WBS_STB_I = '0') then   -- Break cycle and reset ack when master deasserts CYC at any point
                    ack <= '0';
                end if;

            end if;
        end if;
    end process;

end RTL;