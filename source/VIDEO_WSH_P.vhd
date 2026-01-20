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
        SCRN_BL     : out std_logic;                         -- Backlight control
        SCRN_RST_N  : out std_logic;                         -- /RESET signal
        SCRN_CS_N   : out std_logic;                         -- /CS signal
        SCRN_WR_N   : out std_logic;                         -- /WR signal
        SCRN_RD_N   : out std_logic;                         -- /RD signal
        SCRN_RS     : out std_logic;                         -- RS signal
        SCRN_WAIT_N : in std_logic;                          -- /WAIT signal
        SCRN_DATA   : inout std_logic_vector(15 downto 0)    -- DATAIO signal (GPIO0 24 -> 9)
    );
end VIDEO_WSH_P;

architecture RTL of VIDEO_WSH_P is

    -- constants for timing control
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
    signal ack          : std_logic := '0';                                     -- internal ack signal
    signal reg_r        : std_logic_vector(7 downto 0) := x"FF";                -- current register selected (0xFF = ignored)
    signal word_flg     : std_logic := '0';                                     -- when '1', the register and reg+1 make up a 16-bit value to store/read - little endian

    -- Counters and indeces for initialization sequence
    signal timer        : Integer := 0;                                         -- timer counter
    signal cmd_index    : Integer := 0;                                         -- command index for multi-step commands
    signal status_check : std_logic := '0';                                     -- status register check flag for multi-check commands
    signal powerup_done : std_logic := '0';                                     -- flag to indicate powerup sequence is done

    -- Specialty flags
    signal text_mode : std_logic := '0';                                        -- flag to indicate if text mode is enabled (little-endian pixel writes if not text mode)

    -- write both bytes of word-length registers
    signal lo_byte      : std_logic_vector(7 downto 0) := (others => '0');      -- lower byte for word writes (goes in REG)
    signal hi_byte      : std_logic_vector(7 downto 0) := (others => '0');      -- upper byte for word writes (goes in REG+1)
    signal current_reg  : std_logic_vector(7 downto 0) := (others => '0');      -- storage for current register (to detect changes and handle multi-read/write logic)
    signal current_word_flg : std_logic := '0';                                 -- stores the word_flg value at the start of a wishbone transaction
    signal make_word    : std_logic := '0';                                     -- flag to indicate that a word is being read and the two bytes need to be combined

    -- state machine states and signals
    type state_type is (IDLE, ACK_CLEAR, WSH_READ, WSH_WRITE, STATUS_RD, COMMAND_WR, DATA_RD, DATA_WR, WAIT_ST, INIT, RD4, WR4, WORD_RD, WORD_WR);
    signal state        : state_type := INIT;
    signal return_st    : state_type := INIT;

begin
    -- signals mapped to pin outputs
    SCRN_BL      <= bl;
    SCRN_RST_N   <= n_res;
    SCRN_CS_N    <= n_cs;
    SCRN_WR_N    <= n_wr;
    SCRN_RD_N    <= n_rd;
    SCRN_RS      <= rs;

    -- send d_in into the screen controller when db_oe is 1, otherwise set data_out to screen controller output
    SCRN_DATA(15 downto 0) <= d_in when db_oe = '1' else (others => 'Z');

    -- output to Wishbone interface
    WBS_ACK_O      <= ack AND WBS_CYC_I AND WBS_STB_I;
    WBS_DATA_O     <= d_out;                           -- output read data register to Wishbone data output

    with WBS_ADDR_I(7 downto 0) select
        reg_r <=                        -- register to read/write comes from lsb of Wishbone address unless it's blocked (see "Video Interface Notes" in ProjectNotes folder)
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
                    cmd_index <= 600;    -- if already powered up, skip to warm reset portion
                end if;

                bl        <= '0';               -- turn off backlight
                n_rd      <= '1';               -- reset control signals
                n_wr      <= '1';
                n_cs      <= '1';
                rs        <= '0';
                db_oe     <= '0';
                d_out <= (others => '0');       -- reset data in/out
                d_in  <= (others => '0');
                text_mode <= '0';               -- default to graphics mode

                ack    <= '0';                  -- clear ack signal

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
                            n_wr  <= '1';               -- complete write command
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            n_cs  <= '1';               -- complete command
                            db_oe <= '0';               -- set inout bus to input again
                            timer <= 0;                 -- one tick delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when DATA_RD =>             -- can assert ack early here before the WAIT_ST, since data is already latched
                        timer <= timer + 1;
                        if timer = 0 then
                            n_cs <= '0';                -- start command
                            rs   <= '1';
                            n_rd <= '0';                -- rs = 1, n_rd = 0 -> read data
                        elsif timer = CMD_CS_DIFF then
                            n_rd <= '1';                -- complete read command
                            d_out <= SCRN_DATA(15 downto 0);    -- latch data (all 16 bits) into register
                        elsif timer = CMD_CS_DIFF + CMD_HOLD_TIME then
                            if return_st /= INIT then   -- ignore wishbone-related items during initialization
                                if (current_word_flg = '0') then
                                    if current_reg = x"04" then -- register 4 outputs 16 bits, but pixels are stored little endian - swap the bytes so they come out GGBB RRGG BBRR
                                        d_out <= d_out(7 downto 0) & d_out(15 downto 8);
                                    end if;
                                    ack <= '1';             -- assert ack now that data is read (don't do that yet for first byte of word reads)
                                end if;
                                if (make_word = '1') then   -- second byte of word read
                                    d_out <= d_out(7 downto 0) & lo_byte;   -- combine upper and lower bytes into data out for other word registers
                                    make_word <= '0';                       -- clear flag
                                    ack <= '1';             -- assert ack now that full word data is read and latched to d_out
                                end if;
                            end if;
                            n_cs <= '1';                -- complete command
                            timer <= 0;                 -- one tick delay before next command
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when DATA_WR =>             -- no need to assert ack early here because it will be asserted after register is selected (might be able to do it AS register is being selected - if we save DATA_I early enough)
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
                            n_cs  <= '1';               -- complete command
                            db_oe <= '0';               -- set inout bus to input again
                                timer <= 0;                 -- one tick delay before next command for non-initialization - why is this ok but not during init?
                            state <= WAIT_ST;           -- wait, then go back to the state this was "called" from
                        end if;

                    when IDLE => 
                        if (WBS_CYC_I ='1' AND WBS_STB_I = '1') then    -- new transaction requested
                            lo_byte <= WBS_DATA_I(7 downto 0);    -- on next clock, store lower byte of data input
                            hi_byte <= WBS_DATA_I(15 downto 8);   -- on next clock, store upper byte of data input
                            current_word_flg <= word_flg;         -- on next clock, store current word flag
                            current_reg <= reg_r;                 -- on next clock, store current register for detecting changes

                            if WBS_WE_I = '0' then          -- read operation
                                if reg_r = x"00" then
                                    state <= STATUS_RD;          -- read status register
                                    return_st <= ACK_CLEAR;      -- after reading status, finish wishbone transaction
                                elsif reg_r /= x"FF" then        -- register to read is exposed
                                    if current_reg = reg_r AND reg_r = x"04" then  -- handle register 4 multi-read logic (need to wait until STATUS bit 4 is cleared before next read (Memory Read FIFO not empty))
                                        status_check <= '0';     -- reset status check flag for multi command RD4 state
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
                                if reg_r /= x"00" AND reg_r /= x"FF" then  -- register to write is exposed
                                    ack <= '1';                                     -- assert ack as register is being selected and before actually writing any data - we've saved everything we need
                                    if current_reg = reg_r AND reg_r = x"04" then   -- handle register 4 multi-write logic (need to wait until STATUS bit 7 is cleared before next write (Memory Write FIFO not full))
                                        status_check <= '0';                -- reset status check flag for multi command WR4 state
                                        state <= WR4;                       -- if writing register 4 repeatedly, poll status until FIFO not full and write next data
                                    else
                                        d_in <= "00000000" & reg_r;  -- load register address to write
                                        if reg_r = x"03" then
                                            text_mode <= WBS_DATA_I(2); -- update text mode flag when writing REG 3
                                        end if;
                                        if word_flg = '0' then          -- single byte register
                                            state <= COMMAND_WR;            -- write command to select register
                                            return_st <= WSH_WRITE;         -- after selecting register, go to write state
                                        else                            -- word-length register
                                            cmd_index <= 0;                 -- reset command index for word write sequence
                                            state <= WORD_WR;               -- go to word write state
                                        end if;
                                    end if;
                                else
                                    state <= ACK_CLEAR;          -- register is blocked, finish wishbone transaction doing nothing
                                end if;
                            end if;
                        else
                            state <= IDLE;                       -- stay in IDLE state
                        end if;

                    when WSH_READ =>
                        state <= DATA_RD;               -- read data from selected register (setting ack)
                        return_st <= IDLE;              -- after reading data, finish wishbone transaction

                    when WSH_WRITE =>
                        d_in <= hi_byte & lo_byte;      -- load data to write to register
                        state <= DATA_WR;               -- write data to selected register
                        return_st <= IDLE;              -- after writing data, go to idle to await next wishbone transaction

                    when RD4 =>                     -- multi-read state for register 0x04 (Memory Read FIFO)
                        return_st <= RD4;               -- return state is set back here by default
                        if status_check = '0' then
                            state <= STATUS_RD;          -- read status register
                            status_check <= '1';         -- set flag to indicate status has been checked
                        else
                            if d_out(4) = '1' then       -- check if FIFO not empty
                                status_check <= '0';        -- if empty, check status again
                            else
                                state <= DATA_RD;           -- not empty, so read data from register 0x04 (setting ack)
                                return_st <= IDLE;          -- after reading data, return to idle state to wait for next wishbone transaction
                            end if;
                        end if;

                    when WR4 =>                     -- multi-write state for register 0x04 (Memory Write FIFO)
                        return_st <= WR4;               -- return state is always set here for WAIT and read/write calls
                        if status_check = '0' then
                            state <= STATUS_RD;             -- read status register
                            status_check <= '1';            -- set flag to indicate status has been checked
                        else
                            if d_out(7) = '1' then          -- check if FIFO not full
                                status_check <= '0';        -- if full, check status again
                            else
                                if text_mode = '0' then
                                    d_in <= lo_byte & hi_byte;  -- for graphics writing, flip bytes for little-endian write
                                else
                                    d_in <= hi_byte & lo_byte;  -- for text writing
                                end if;
                                state <= DATA_WR;           -- write data to register 0x04
                                return_st <= IDLE;          -- after writing data, return to idle state to wait for next wishbone transaction
                            end if;
                        end if;

                    when WORD_RD =>                 -- read word-length register
                        return_st <= WORD_RD;           -- return state is always set here
                        cmd_index <= cmd_index + 1;     -- complete each step in turn, so index is incremented by default each time through this state

                        case cmd_index is
                            when 0 =>               -- step 0: select register for lower byte read
                                d_in <= "00000000" & current_reg;   -- select register address to read (lower byte)
                                state <= COMMAND_WR;
                            when 1 =>               -- step 1: read lower byte (will not set ack)
                                state <= DATA_RD;
                            when 2 =>               -- step 2: store lower byte and select register for upper byte
                                lo_byte <= d_out(7 downto 0);       -- store lower byte temporarily
                                d_in <= "00000000" & std_logic_vector(unsigned(current_reg) + 1);  -- select register address to read (upper byte)
                                state <= COMMAND_WR;
                            when 3 =>               -- step 3: read upper byte (will set ack)
                                make_word <= '1';                   -- set flag to indicate that a word is being read and the two bytes need to be combined
                                state <= DATA_RD;
                                return_st <= IDLE;                  -- after reading data, return to idle state to wait for next wishbone transaction
                            when others =>          -- should not occur, but just in case, finish transaction via ACK_CLEAR
                                state <= ACK_CLEAR;
                        end case;

                    when WORD_WR =>                 -- write word-length register
                        return_st <= WORD_WR;           -- return state is always set here
                        cmd_index <= cmd_index + 1;     -- complete each step in turn, so index is incremented by default each time through this state

                        case cmd_index is
                            when 0 =>               -- step 0: select register for lower byte write
                                d_in <= "00000000" & current_reg;   -- select register address to write (lower byte)
                                state <= COMMAND_WR;
                            when 1 =>               -- step 1: write lower byte
                                d_in <= "00000000" & lo_byte;       -- load lower byte to write
                                state <= DATA_WR;
                            when 2 =>               -- step 2: select register for upper byte write
                                d_in <= "00000000" & std_logic_vector(unsigned(current_reg) + 1);  -- select register address to write (upper byte)
                                state <= COMMAND_WR;
                            when 3 =>               -- step 3: write upper byte
                                d_in <= "00000000" & hi_byte;       -- load upper byte to write
                                state <= DATA_WR;
                                return_st <= IDLE;                  -- after writeing data, return to idle state to wait for next wishbone transaction
                            when others =>          -- should not occur, but just in case, finish transaction via ACK_CLEAR
                                state <= ACK_CLEAR;
                        end case;

                    when ACK_CLEAR =>               -- finish wishbone transaction - set ack and wait for master to deassert CYC or STB
                        if (WBS_CYC_I = '1' AND WBS_STB_I = '1') then
                            ack <= '1';                     -- assert ack
                            state <= ACK_CLEAR;             -- and stay here until master deasserts CYC or STB
                        else                                -- otherwise, return to idle state to wait for next wishbone cycle
                            state <= IDLE;                  -- return to IDLE state
                            return_st <= IDLE;
                            timer <= 0;
                        end if;

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
                                else
                                    cmd_index <= 100; -- software reset seemed to be causing trouble at every turn, so see if we can do without it
                                end if;

                            -- SET PLLs
                            when 100 =>      -- step 100: Select Register 0x05
                                d_in <= x"0005";
                                state <= COMMAND_WR;
                            when 101 =>      -- step 101: Write 0x06 to Register 0x05 (PLL1 Divided by 8)
                                d_in <= x"0006";
                                state <= DATA_WR;
                            when 102 =>      -- step 102: Select Register 0x06
                                d_in <= x"0006";
                                state <= COMMAND_WR;
                            when 103 =>      -- step 103: Write 0x27 to Register 0x06 (Pixel Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 104 =>      -- step 104: Select Register 0x07
                                d_in <= x"0007";
                                state <= COMMAND_WR;
                            when 105 =>      -- step 105: Write 0x04 to Register 0x07 (PLL 2 Divided by 4)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 106 =>      -- step 106: Select Register 0x08
                                d_in <= x"0008";
                                state <= COMMAND_WR;
                            when 107 =>      -- step 107: Write 0x27 to Register 0x08 (SDRAM Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 108 =>      -- step 108: Select Register 0x09
                                d_in <= x"0009";
                                state <= COMMAND_WR;
                            when 109 =>      -- step 109: Write 0x04 to Register 0x09 (PLL 3 Divided by 4)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 110 =>      -- step 110: Select Register 0x0A
                                d_in <= x"000A";
                                state <= COMMAND_WR;
                            when 111 =>      -- step 111: Write 0x27 to Register 0x0A (System Clock frequency)
                                d_in <= x"0027";
                                state <= DATA_WR;
                            when 112 =>      -- step 112: Select Register 0x01
                                d_in <= x"0001";
                                state <= COMMAND_WR;
                            when 113 =>      -- step 113: Write 0x00 to Register 0x01 (Reconfigure PLLs)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 114 =>      -- step 114: Delay 10 uS
                                timer <= CLK_FREQ / 100_000;
                                state <= WAIT_ST;
                            when 115 =>      -- step 115: Write 0x80 to Regsiter 0x01 (Set up PLLs, TFT Output is 24 bpp)
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 116 =>      -- step 116: Delay 1 ms
                                timer <= CLK_FREQ / 1000;
                                state <= WAIT_ST;
                                cmd_index <= 200;

                            -- SET UP SDRAM
                            when 200 =>      -- step 200: Select Register 0xE0
                                d_in <= x"00E0";
                                state <= COMMAND_WR;
                            when 201 =>      -- step 201: Write 0x29 to Register 0xE0 (128 Mbit)
                                d_in <= x"0029";
                                state <= DATA_WR;
                            when 202 =>      -- step 202: Select Register 0xE1
                                d_in <= x"00E1";
                                state <= COMMAND_WR;
                            when 203 =>      -- step 203: Write 0x03 to Register 0xE1 (CAS = 2, ACAS = 3)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 204 =>      -- step 204: Select Register 0xE2
                                d_in <= x"00E2";
                                state <= COMMAND_WR;
                            when 205 =>      -- step 205: Write 0x0B to Register 0xE2 (Auto refresh interval is 779 (0x30B))
                                d_in <= x"000B";
                                state <= DATA_WR;
                            when 206 =>      -- step 206: Select Register 0xE3
                                d_in <= x"00E3";
                                state <= COMMAND_WR;
                            when 207 =>      -- step 207: Write 0x03 to Register 0xE3
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 208 =>      -- step 208: Select Register 0xE4
                                d_in <= x"00E4";
                                state <= COMMAND_WR;
                            when 209 =>      -- step 209: Write 0x01 to Register 0xE4 (Begin SDRAM initialization)
                                d_in <= x"0001";
                                state <= DATA_WR;
                            when 210 =>       -- step 210: read Register 0xE4
                                state <= DATA_RD;
                            when 211 =>       -- step 211: if bit 0 is 0, go back to step 211
                                if d_out(0) = '0' then
                                    cmd_index <= 210;
                                end if;
                            when 212 =>       -- step 212: read Status register bit 2 and wait until set - SDRAM ready
                                state <= STATUS_RD;
                            when 213 =>       -- step 213: if status bit 2 is 0, go back to step 212
                                if d_out(2) = '0' then
                                    cmd_index <= 212;
                                else
                                    cmd_index <= 300;
                                end if;

                            -- ADDITIONAL CHIP CONFIG
                            when 300 =>      -- step 300: Select Register 0x01
                                d_in <= x"0001";
                                state <= COMMAND_WR;
                            when 301 =>      -- step 301: Write 0x01 to Register 0x01 (24-bit TFT output, 16-bit Host Data Bus)
                                d_in <= x"0001";
                                state <= DATA_WR;
                                cmd_index <= 400;
                            -- REGISTERS 0x02 and 0x03 STAY AT THEIR DEFAULT VALUES FOR NOW

                            -- SET SCREEN PARAMETERS AND TIMING
                            when 400 =>      -- step 400: Select Register 0x12
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 401 =>      -- step 401: Write 0x80 to Register 0x12 (Set screen data for fetching on falling clock)
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 402 =>      -- step 402: Select Register 0x13
                                d_in <= x"0013";
                                state <= COMMAND_WR;
                            when 403 =>      -- step 403: Write 0xC3 to Register 0x13 (DE active high, HSYNC and VSYNC active high)
                                d_in <= x"00C3";
                                state <= DATA_WR;
                            when 404 =>      -- step 404: Select Register 0x14
                                d_in <= x"0014";
                                state <= COMMAND_WR;
                            when 405 =>      -- step 405: Write 0x7F to Register 0x14 (bits 11:4 of display width - 1 for 1024 pixels)
                                d_in <= x"007F";
                                state <= DATA_WR;
                            when 406 =>      -- step 406: Select Register 0x15
                                d_in <= x"0015";
                                state <= COMMAND_WR;
                            when 407 =>      -- step 407: Write 0x00 to Register 0x15 (bits 3:0 of display width)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 408 =>      -- step 408: Select Register 0x1A
                                d_in <= x"001A";
                                state <= COMMAND_WR;
                            when 409 =>      -- step 409: Write 0x57 to Register 0x1A (bits 7:0 of display height - 1 for 600 pixels)
                                d_in <= x"0057";
                                state <= DATA_WR;
                            when 410 =>      -- step 410: Select Register 0x1B
                                d_in <= x"001B";
                                state <= COMMAND_WR;
                            when 411 =>      -- step 411: Write 0x02 to Register 0x1B (bits 10:8 of display height - 1 for 600 pixels)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 412 =>      -- step 412: Select Register 0x16
                                d_in <= x"0016";
                                state <= COMMAND_WR;
                            when 413 =>      -- step 413: Write 0x13 to Register 0x16 (bits 8:4 of back porch - 1)
                                d_in <= x"0013";
                                state <= DATA_WR;
                            when 414 =>      -- step 414: Select Register 0x17
                                d_in <= x"0017";
                                state <= COMMAND_WR;
                            when 415 =>      -- step 415: Write 0x00 to Register 0x17 (bits 3:0 of back porch)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 416 =>      -- step 416: Select Register 0x18
                                d_in <= x"0018";
                                state <= COMMAND_WR;
                            when 417 =>      -- step 417: Write 0x14 to Register 0x18 (front porch / 8 for back porch 160)
                                d_in <= x"0014";
                                state <= DATA_WR;
                            when 418 =>      -- step 418: Select Register 0x19
                                d_in <= x"0019";
                                state <= COMMAND_WR;
                            when 419 =>      -- step 419: Write 0x07 to Register 0x19 (pulse width / 8 - 1 for HSYNC pulse width 70)
                                d_in <= x"0007";
                                state <= DATA_WR;
                            when 420 =>      -- step 420: Select Register 0x1C
                                d_in <= x"001C";
                                state <= COMMAND_WR;
                            when 421 =>      -- step 421: Write 0x16 to Register 0x1C (bits 7:0 of vertical non-display - 1)
                                d_in <= x"0016";
                                state <= DATA_WR;
                            when 422 =>      -- step 422: Select Register 0x1D
                                d_in <= x"001D";
                                state <= COMMAND_WR;
                            when 423 =>      -- step 423: Write 0x00 to Register 0x1D (bits 9:8 of vertical non-display - 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 424 =>      -- step 424: Select Register 0x1E
                                d_in <= x"001E";
                                state <= COMMAND_WR;
                            when 425 =>      -- step 425: Write 0x0B to Register 0x1E (VSYNC Start Position - 1)
                                d_in <= x"000B";
                                state <= DATA_WR;
                            when 426 =>      -- step 426: Select Register 0x1F
                                d_in <= x"001F";
                                state <= COMMAND_WR;
                            when 427 =>      -- step 427: Write 0x09 to Register 0x1F (VSYNC Pulse width - 1)
                                d_in <= x"0009";
                                state <= DATA_WR;
                            when 428 =>      -- step 428: Delay 1
                                timer <= CLK_FREQ / 1000;         -- 1 ms delay
                                state <= WAIT_ST;
                                cmd_index <= 600;

                            -- SET RA8876 MAIN AND ACTIVE WINDOW - WARM RESET ENTRY POINT
                            when 600 =>      -- step 600: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 601 =>      -- step 601: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            when 602 =>      -- step 602: read Status register bit 3 and wait until clear - core task done/idle
                                state <= STATUS_RD;
                            when 603 =>      -- step 603: if status bit 3 is 1, go back to step 602
                                if d_out(3) = '1' then
                                    cmd_index <= 602;
                                end if;
                            when 604 =>      -- step 604: Select Register 0x20
                                d_in <= x"0020";
                                state <= COMMAND_WR;
                            when 605 =>      -- step 605: Write 0x00 to Register 0x20 (Main Image Start Address byte 0 - least significant byte)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 606 =>      -- step 606: Select Register 0x21
                                d_in <= x"0021";
                                state <= COMMAND_WR;
                            when 607 =>      -- step 607: Write 0x00 to Register 0x21 (Main Image Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 608 =>      -- step 608: Select Register 0x22
                                d_in <= x"0022";
                                state <= COMMAND_WR;
                            when 609 =>      -- step 609: Write 0x00 to Register 0x22 (Main Image Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 610 =>      -- step 610: Select Register 0x23
                                d_in <= x"0023";
                                state <= COMMAND_WR;
                            when 611 =>      -- step 611: Write 0x00 to Register 0x23 (Main Image Start Address byte 3 - most significant byte)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 612 =>      -- step 612: Select Register 0x24
                                d_in <= x"0024";
                                state <= COMMAND_WR;
                            when 613 =>      -- step 613: Write 0x00 to Register 0x24 (bits 7:0 of main image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 614 =>      -- step 614: Select Register 0x25
                                d_in <= x"0025";
                                state <= COMMAND_WR;
                            when 615 =>      -- step 615: Write 0x04 to Register 0x25 (bits 12:8 of main image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 616 =>      -- step 616: Select Register 0x26
                                d_in <= x"0026";
                                state <= COMMAND_WR;
                            when 617 =>      -- step 617: Write 0x00 to Register 0x26 (Main Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 618 =>      -- step 618: Select Register 0x27
                                d_in <= x"0027";
                                state <= COMMAND_WR;
                            when 619 =>      -- step 619: Write 0x00 to Register 0x27 (Main Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 620 =>      -- step 620: Select Register 0x28
                                d_in <= x"0028";
                                state <= COMMAND_WR;
                            when 621 =>      -- step 621: Write 0x00 to Register 0x28 (Main Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 622 =>      -- step 622: Select Register 0x29
                                d_in <= x"0029";
                                state <= COMMAND_WR;
                            when 623 =>      -- step 623: Write 0x00 to Register 0x29 (Main Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 624 =>      -- step 624: Select Register 0x50
                                d_in <= x"0050";
                                state <= COMMAND_WR;
                            when 625 =>      -- step 625: Write 0x00 to Register 0x50 (Canvas Start Address byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 626 =>      -- step 626: Select Register 0x51
                                d_in <= x"0051";
                                state <= COMMAND_WR;
                            when 627 =>      -- step 627: Write 0x00 to Register 0x51 (Canvas Start Address byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 628 =>      -- step 628: Select Register 0x52
                                d_in <= x"0052";
                                state <= COMMAND_WR;
                            when 629 =>      -- step 629: Write 0x00 to Register 0x52 (Canvas Start Address byte 2)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 630 =>      -- step 630: Select Register 0x53
                                d_in <= x"0053";
                                state <= COMMAND_WR;
                            when 631 =>      -- step 631: Write 0x00 to Register 0x53 (Canvas Start Address byte 3)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 632 =>      -- step 632: Select Register 0x54
                                d_in <= x"0054";
                                state <= COMMAND_WR;
                            when 633 =>     -- step 633: Write 0x00 to Register 0x54 (bits 7:2 of canvas image width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 634 =>     -- step 634: Select Register 0x55
                                d_in <= x"0055";
                                state <= COMMAND_WR;
                            when 635 =>     -- step 635: Write 0x04 to Register 0x55 (bits 12:8 of canvas image width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 636 =>     -- step 636: Select Register 0x56
                                d_in <= x"0056";
                                state <= COMMAND_WR;
                            when 637 =>     -- step 637: Write 0x00 to Register 0x56 (Canvas Window Upper-Left X byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 638 =>     -- step 638: Select Register 0x57
                                d_in <= x"0057";
                                state <= COMMAND_WR;
                            when 639 =>     -- step 639: Write 0x00 to Register 0x57 (Canvas Window Upper-Left X byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 640 =>     -- step 640: Select Register 0x58
                                d_in <= x"0058";
                                state <= COMMAND_WR;
                            when 641 =>     -- step 641: Write 0x00 to Register 0x58 (Canvas Window Upper-Left Y byte 0)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 642 =>     -- step 642: Select Register 0x59
                                d_in <= x"0059";
                                state <= COMMAND_WR;
                            when 643 =>     -- step 643: Write 0x00 to Register 0x59 (Canvas Window Upper-Left Y byte 1)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 644 =>     -- step 644: Select Register 0x5A
                                d_in <= x"005A";
                                state <= COMMAND_WR;
                            when 645 =>     -- step 645: Write 0x00 to Register 0x5A (bits 7:0 of Active Window width = 0x00 for 1024)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 646 =>     -- step 646: Select Register 0x5B
                                d_in <= x"005B";
                                state <= COMMAND_WR;
                            when 647 =>     -- step 647: Write 0x04 to Register 0x5B (bits 12:8 of Active Window width = 0x04 for 1024)
                                d_in <= x"0004";
                                state <= DATA_WR;
                            when 648 =>     -- step 648: Select Register 0x5C
                                d_in <= x"005C";
                                state <= COMMAND_WR;
                            when 649 =>     -- step 649: Write 0x58 to Register 0x5C (bits 7:0 of Active Window height = 0x58 for 600)
                                d_in <= x"0058";
                                state <= DATA_WR;
                            when 650 =>     -- step 650: Select Register 0x5D
                                d_in <= x"005D";
                                state <= COMMAND_WR;
                            when 651 =>     -- step 651: Write 0x02 to Register 0x5D (bits 12:8 of Active Window height = 0x02 for 600)
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 652 =>     -- step 652: Select Register 0x5E
                                d_in <= x"005E";
                                state <= COMMAND_WR;
                            when 653 =>     -- step 653: Write 0x03 to Register 0x5E (X-Y coordinate mode, 24 bpp active canvas/window)
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 654 =>     -- step 654: Select Register 0x10
                                d_in <= x"0010";
                                state <= COMMAND_WR;
                            when 655 =>     -- step 655: Write 0x08 to Register 0x10 (Disable PIPs, 24 bpp main window - final)
                                d_in <= x"0008";
                                state <= DATA_WR;
                            when 656 =>       -- step 656: Select Register 0xD2 - CLEAR SCREEN FROM HERE ON DOWN
                                if powerup_done = '1' then
                                    cmd_index  <= 700;  -- skip clear screen if already powered up
                                else
                                    d_in <= x"00D2";    -- otherwise, continue power-up sequence
                                    state <= COMMAND_WR;
                                end if;
                            when 657 =>       -- step 657: Write 0x00 to Register 0xD2 (Foreground Red)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 658 =>       -- step 658: Select Register 0xD3
                                d_in <= x"00D3";
                                state <= COMMAND_WR;
                            when 659 =>       -- step 659 Write 0x00 to Register 0xD3 (Foreground Green)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 660 =>       -- step 660: Select Register 0xD4
                                d_in <= x"00D4";
                                state <= COMMAND_WR;
                            when 661 =>       -- step 661: Write 0x80 to Register 0xD4 (Foreground Blue) - set color to dark blue
                                d_in <= x"0080";
                                state <= DATA_WR;
                            when 662 =>       -- step 662: Select Register 0x68
                                d_in <= x"0068";
                                state <= COMMAND_WR;
                            when 663 =>       -- step 663: Write 0x00 to Register 0x68 (Line Start X low byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 664 =>       -- step 664: Select Register 0x69
                                d_in <= x"0069";
                                state <= COMMAND_WR;
                            when 665 =>       -- step 665: Write 0x00 to Register 0x69 (Line Start X high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 666 =>      -- step 666: Select Register 0x6A
                                d_in <= x"0000";
                                state <= COMMAND_WR;
                            when 667 =>      -- step 667: Write 0x00 to Register 0x6A (Line Start Y low byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 668 =>      -- step 668: Select Register 0x6B
                                d_in <= x"006B";
                                state <= COMMAND_WR;
                            when 669 =>      -- step 669: Write 0x00 to Register 0x6B (Line Start Y high byte = 0x00)
                                d_in <= x"0000";
                                state <= DATA_WR;
                            when 670 =>      -- step 670: Select Register 0x6C
                                d_in <= x"006C";
                                state <= COMMAND_WR;
                            when 671 =>      -- step 671: Write 0xFF to Register 0x6C (Line End X low byte = 0xFF)
                                d_in <= x"00FF";
                                state <= DATA_WR;
                            when 672 =>      -- step 672: Select Register 0x6D
                                d_in <= x"006D";
                                state <= COMMAND_WR;
                            when 673 =>      -- step 673: Write 0x03 to Register 0x6D (Line End X high byte = 0x03) X end = 1023 = 0x3FF
                                d_in <= x"0003";
                                state <= DATA_WR;
                            when 674 =>      -- step 674: Select Register 0x6E
                                d_in <= x"006E";
                                state <= COMMAND_WR;
                            when 675 =>      -- step 675: Write 0x57 to Register 0x6E (Line End Y low byte = 0x57)
                                d_in <= x"0057";
                                state <= DATA_WR;
                            when 676 =>      -- step 676: Select Register 0x6F
                                d_in <= x"006F";
                                state <= COMMAND_WR;
                            when 677 =>      -- step 677: Write 0x02 to Register 0x6F (Line End Y high byte = 0x02) Y end = 599 = 0x257
                                d_in <= x"0002";
                                state <= DATA_WR;
                            when 678 =>      -- step 678: read Status register
                                state <= STATUS_RD;
                            when 679 =>      -- step 679: if status bit 3 is 1, go back to step 678 (Core Task is Busy)
                                if d_out(3) = '1' then
                                    cmd_index <= 678;    -- still busy, check again
                                end if;
                            when 680 =>      -- step 680: Select register 0x76
                                d_in <= x"0076";
                                state <= COMMAND_WR;
                            when 681 =>      -- step 681: Write 0xE0 to register 0x76 (Draw the filled square to clear the screen)
                                d_in <= x"00E0";
                                state <= DATA_WR;
                            when 682 =>     -- step 682: Select register 0x67
                                d_in <= x"0067";
                                state <= COMMAND_WR;
                            when 683 =>      -- step 683: Read Register 0x67
                                state <= DATA_RD;
                            when 684 =>      -- step 684: Check to see if bit 7 is set (line/triangle drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 683;    -- still busy, check again
                                end if;
                            when 685 =>      -- step 685: Select Register 0x76
                                d_in <= x"0076";
                                state <= COMMAND_WR;
                            when 686 =>      -- step 686: Read Register 0x76
                                state <= DATA_RD;
                            when 687 =>      -- step 687: Check to see if bit 7 is set (ellipse/curve/square) drawing function is processing)
                                if d_out(7) = '1' then
                                    cmd_index <= 868;    -- still busy, check again
                                else
                                    cmd_index <= 700;    -- proceed to next step
                                end if;

                            when 700 =>     -- step 700: Drawing completed, turn on backlight and Select Register 0x12
                                bl   <= '1';
                                d_in <= x"0012";
                                state <= COMMAND_WR;
                            when 701 =>     -- step 701: Read Register 0x12
                                state <= DATA_RD;
                            when 702 =>     -- step 702: Assert bit 6 (Turn on Screen) and write register 0x12
                                d_in <= d_out OR "0000000001000000";    -- assert bit 6
                                state <= DATA_WR;
                            when 703 =>
                                state <= IDLE;
                                powerup_done <= '1';

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