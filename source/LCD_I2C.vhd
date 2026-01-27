library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LCD_I2C is
    generic ( CLK_FREQ : integer := 50_000_000 );                                           -- system clock frequency in Hz
    port (
        CLK     : in std_logic;                                                             -- system clock
        RST     : in std_logic;                                                             -- reset
        START   : in std_logic;                                                             -- set high to begin an update of the LCD panel

        INST    : in std_logic_vector(15 downto 0);                                         -- current instruction
        CONST   : in std_logic_vector(15 downto 0);                                         -- current constant
        ADDR    : in std_logic_vector(15 downto 0);                                         -- current address being read or written
        SEGMENT : in std_logic_vector(7 downto 0);                                          -- current segment
        PC      : in std_logic_vector(15 downto 0);                                         -- current program counter value
        MDATA   : in std_logic_vector(16 downto 0);                                         -- current data for memory read/write (includes write flag)

        SCL     : inout std_logic;                                                          -- LCD SCL signal - eventually change to LCD_SCL
        SDA     : inout std_logic;                                                          -- LCD SDA signal - eventually change to LCD_SDA

        BUSY    : out std_logic                                                             -- set high when LCD panel is setting the display
    );
end LCD_I2C;

architecture RTL of LCD_I2C is

    CONSTANT LCD_ADDRESS : std_logic_vector(6 downto 0) := "0100111";       -- LCD Display address 0x27

    -- i2c master signals
    signal i2c_ena      : std_logic := '0';                                      -- signal to enable i2c transaction
    signal i2c_data_wr  : std_logic_vector(7 downto 0) := (others => '0');       -- data to write to i2c provider
    signal i2c_busy     : std_logic := '0';                                      -- indicates i2c transaction in progress
    
    -- LCD SEND signals
    signal busy_prev    : std_logic := '0';                                      -- busy edge detection
    signal cmd_latched  : std_logic := '0';                                      -- en was asserted, and then busy transitioned to high

    -- LCD SENDBYTE signals
    signal data_wr      : std_logic_vector(7 downto 0) := (others => '0');       -- byte to be sent
    signal data_cmd     : std_logic := '0';                                      -- command/data bit 0 = command, 1 = data

    -- Indeces and counters
    signal delay_cntr   : integer range 0 to 50000000 := 0;                      -- counter for delay timing
    signal cmd_index    : integer range 0 to 500 := 0;                           -- index for commands
    signal subcmd_idx   : integer range 0 to 100 := 0;                           -- index for subcommands
    signal loop_index   : integer range 0 to 100 := 0;                           -- index for looping

    -- Latched values for all inputs
    signal s_inst       : std_logic_vector(15 downto 0) := (others => '0');      -- local copy of INST
    signal s_const      : std_logic_vector(15 downto 0) := (others => '0');      -- local copy of CONST
    signal s_addr       : std_logic_vector(15 downto 0) := (others => '0');      -- local copy of ADDR
    signal s_pc         : std_logic_vector(15 downto 0) := (others => '0');      -- local copy of PC
    signal s_mdata      : std_logic_vector(15 downto 0) := (others => '0');      -- local copy of memory data
    signal s_seg        : std_logic_vector(7 downto 0) := (others => '0');       -- local copy of SEGMENT
    signal s_wr         : std_logic := '0';                                      -- local copy of write flag

    -- strings to print and translation logic
    signal string_reg   : std_logic_vector(47 downto 0) := (others => '0');      -- up to six byte string to print
    signal rc_first     : boolean := false;                                      -- true if Ra and Rc are swapped in command string
    signal rc_only      : boolean := false;                                      -- true if Rc is the only register to show for the command (LDS/STS)
    signal no_rb        : boolean := false;                                      -- true if Rb should not be printed at all (LD/ST)

    -- State machines
    type machine is (STARTUP, READY, FORMAT, DELAY, SEND, SENDBYTE);             -- needed states
    signal state        : machine := STARTUP;                                    -- state machine initial state
    signal send_return1 : machine := STARTUP;                                    -- state to return to after sending byte
    signal send_return2 : machine := STARTUP;

    -- Function to convert 4-bit hex digit to ASCII
    function to_hex_ascii(digit : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        if to_integer(unsigned(digit)) > 9 then     -- digit is A-F
            return std_logic_vector(to_unsigned(to_integer(unsigned(digit)) + 55, 8)); -- covert digit value (10-15) to ascii character ('A'-'F')
        else                                        -- digit is 0-9
            return std_logic_vector(to_unsigned(to_integer(unsigned(digit)) + 48, 8)); -- convert digit value (0-9) to ascii character ('0'-'9')
        end if;
    end function;

begin

    BUSY <= '0' when state = READY else '1';        -- module is BUSY except when in READY state

    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RST = '1') then                     -- synchronous reset
                state <= STARTUP;
                send_return1 <= STARTUP;
                send_return2 <= STARTUP;

                cmd_index  <= 0;
                subcmd_idx <= 0;
                delay_cntr <= 0;

                busy_prev <= '0';
                cmd_latched <= '0';
            else
                case state is
                    when STARTUP =>                 -- send initialization commands to LCD
                        cmd_index <= cmd_index + 1;         -- increment command index
                        send_return1 <= STARTUP;            -- set return state to come back here
                        send_return2 <= STARTUP;            -- set delay return to come back here
                        data_cmd <= '0';                    -- always send commands from here
                        case cmd_index is
                            when 0 =>               -- delay for startup 50 ms
                                delay_cntr <= CLK_FREQ/20;
                                state <= DELAY;

                            when 1 =>               -- function set command
                                i2c_data_wr <= x"00";       -- turn off backlight, begin communication
                                state <= SEND;
                            
                            when 2 =>               -- delay for 1 s
                                delay_cntr <= CLK_FREQ;
                                state <= DELAY;

                            -- try to set four bit mode by first insuring eight bit mode, then setting four bit mode
                            -- send first command - if it was in four bit mode, but only halfway transmitted, this could execute anything, so long pause afterwards
                            when 3 =>               -- "expander write" is OR backlight on
                                i2c_data_wr <= x"38";       -- function set: 8-bit
                                state <= SEND;

                            when 4 =>               -- "pulse enable"
                                i2c_data_wr <= x"3C";       -- pulse enable high
                                state <= SEND;

                            when 5 =>               -- delay after pulse 1 us
                                delay_cntr <= 50;           -- 1us delay at 50MHz
                                state <= DELAY;

                            when 6 =>               -- "pulse enable" step 2
                                i2c_data_wr <= x"38";       -- pulse enable low
                                state <= SEND;

                            when 7 =>               -- delay after pulse 5 ms
                                delay_cntr <= CLK_FREQ/200;
                                state <= DELAY;

                            -- send two more nybbles to assure the LCD controller is in 8 bit mode - normal pauses here
                            when 8 =>
                                data_wr <= x"33";           -- send byte 0x33 as a command
                                state <= SENDBYTE;

                            -- Now set to 4-bit mode via a single nybble command
                            when 9 =>
                                i2c_data_wr <= x"28";       -- function set: 4-bit
                                state <= SEND;

                            when 10 =>              -- "pulse enable"
                                i2c_data_wr <= x"2C";       -- pulse enable high
                                state <= SEND;

                            when 11 =>              -- delay after pulse 1 us
                                delay_cntr <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 12 =>              -- "pulse enable" step 2
                                i2c_data_wr <= x"28";       -- pulse enable low
                                state <= SEND;

                            when 13 =>              -- delay after pulse 50 us
                                delay_cntr <= CLK_FREQ/20_000;
                                state <= DELAY;

                            -- command: function set: 4-bit, 2 line, 5x8 dots : 0x28
                            when 14 =>
                                data_wr <= x"28";
                                state <= SENDBYTE;

                            -- command: display on, cursor off, blink off : 0x0C
                            when 15 =>
                                data_wr <= x"0C";
                                state <= SENDBYTE;
                            
                            -- command: clear screen : 0x01
                            when 16 =>
                                data_wr <= x"01";
                                state <= SENDBYTE;

                            -- long delay for clear screen! 2ms delay
                            when 17 =>
                                delay_cntr <= CLK_FREQ/500;
                                state <= DELAY;

                            -- command: set default text direction left to right, entry shift decrement : 0x06
                            when 18 =>
                                data_wr <= x"06";
                                state <= SENDBYTE;

                            -- command: set cursor position to home position : 0x02
                            when 19 =>
                                data_wr <= x"02";
                                state <= SENDBYTE;

                            -- long delay for home cursor! 2ms delay
                            when 20 =>
                                delay_cntr <= CLK_FREQ/500;
                                state <= DELAY;

                            when others =>
                                cmd_index <= 0;             -- reset command index
                                state <= READY;             -- go to ready state
                        end case;

                    when READY =>                   -- waiting to start updating the panel info
                        if (START = '1') then               -- got a start signal when not busy
                            s_inst <= INST;                     -- latch in all values
                            s_const <= CONST;
                            s_PC <= PC;
                            s_addr <= ADDR;
                            s_mdata <= MDATA(15 downto 0);
                            s_wr <= MDATA(16);
                            s_seg <= SEGMENT;

                            cmd_index <= 0;                     -- reset cmd_index
                            loop_index <= 8;                    -- set loop index for next step (print 9 spaces)
                            state <= FORMAT;                    -- move to FORMAT state (sets BUSY)
                        end if;

                    when FORMAT =>
                        send_return1 <= FORMAT;                 -- come back here to FORMAT
                        send_return2 <= FORMAT;
                        data_cmd <= '1';                        -- only sending data

                        case cmd_index is
                            when 0 =>                           -- print 9 spaces
                                data_wr <= x"20";                                       -- ascii for space
                                state <= SENDBYTE;                                      -- next state -> send the byte
                                loop_index <= loop_index - 1;                           -- decrement loop index
                                if (loop_index = 0) then                                -- come back here to this step unless we're finished
                                    cmd_index <= 1;                                     -- come back here after last space, but to next step
                                end if;

                            when 1 =>                           -- convert INST to human-readable string
                                cmd_index <= 2;                                         -- Go to next step after assigning string_reg
                                loop_index <= 47;                                       -- set loop index for next step (not used here)
                                rc_first <= false;                                      -- display register flags at default
                                rc_only <= false;
                                no_rb <= false;

                                if (s_inst(9) = '0') then           -- Not a LD/ST/BR opcode, so ALU
                                    case s_inst(15 downto 14) is        -- switch on ALU Function
                                        when "00" =>   -- ALU Compare
                                            case s_inst(13 downto 11) is    -- switching on ALU Function Operation
                                                when 1 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"434D50455120";   -- "CMPEQ "
                                                    else
                                                        string_reg <= x"434D50455143";   -- "CMPEQC"
                                                    end if;
                                                when 3 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"434D50554C20";   -- "CMPUL "
                                                    else
                                                        string_reg <= x"434D50554C43";   -- "CMPULC"
                                                    end if;
                                                when 5 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"434D504C5420";   -- "CMPLT "
                                                    else
                                                        string_reg <= x"434D504C5443";   -- "CMPLTC"
                                                    end if;
                                                when 7 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"434D5054C450";   -- "CMPLE "
                                                    else
                                                        string_reg <= x"434D5054C453";   -- "CMPLEC"
                                                    end if;
                                                when others =>
                                                    string_reg <= x"3F3F3F3F3F3F";       -- "??????"
                                            end case;

                                        when "01" =>   -- ALU Arithmetic
                                            if (s_inst(13 downto 11) = "000") then
                                                if (s_inst(10) = '0') then
                                                    string_reg <= x"204144442020";      -- " ADD  "
                                                else
                                                    string_reg <= x"204144444320";      -- " ADDC "
                                                end if;
                                            elsif (s_inst(13 downto 11) = "001") then
                                                if (s_inst(10) = '0') then
                                                    string_reg <= x"205355422020";      -- " SUB  "
                                                else
                                                    string_reg <= x"205355424320";      -- " SUBC "
                                                end if;
                                            else
                                                string_reg <= x"3F3F3F3F3F3F";          -- "??????"
                                            end if;
                                            
                                        when "10" =>   -- ALU Bitwise Math
                                            case s_inst(13 downto 11) is    -- switching on ALU Function Operation
                                                when 0 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"204E4F522020";   -- " NOR  "
                                                    else
                                                        string_reg <= x"204E4F524320";   -- " NORC "
                                                    end if;
                                                when 1 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"204E414E4420";   -- " NAND "
                                                    else
                                                        string_reg <= x"204E414E4443";   -- " NANDC"
                                                    end if;
                                                when 2 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"20426E412020";   -- " BnA  "
                                                    else
                                                        string_reg <= x"20426E414320";   -- " BnAC "
                                                    end if;
                                                when 3 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"20584F522020";   -- " XOR  "
                                                    else
                                                        string_reg <= x"20584F524320";   -- " XORC "
                                                    end if;
                                                when 4 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"20414E442020";   -- " AND  "
                                                    else
                                                        string_reg <= x"20414E444320";   -- " ANDC "
                                                    end if;
                                                when 5 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"202041202020";   -- "  A   "
                                                    else
                                                        string_reg <= x"202041432020";   -- "  AC  "
                                                    end if;
                                                when 6 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"202042202020";   -- "  B   "
                                                    else
                                                        string_reg <= x"202042432020";   -- "  BC  "
                                                    end if;
                                                when 7 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"20204F522020";   -- "  OR  "
                                                    else
                                                        string_reg <= x"20204F524320";   -- "  ORC "
                                                    end if;
                                                when others =>
                                                    string_reg <= x"3F3F3F3F3F3F";       -- "??????"
                                            end case;

                                        when "11" =>   -- ALU Shift
                                            case s_inst(13 downto 11) is    -- switching on ALU function
                                                when 0 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"205348522020";   -- " SHR  "
                                                    else
                                                        string_reg <= x"205348524320";   -- " SHRC "
                                                    end if;
                                                when 1 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"2053484C2020";   -- " SHL  "
                                                    else
                                                        string_reg <= x"2053484C4320";   -- " SHLC "
                                                    end if;
                                                when 2 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"205352412020";   -- " SRA  "
                                                    else
                                                        string_reg <= x"205352414320";   -- " SRAC "
                                                    end if;
                                                when 3 =>
                                                    if (s_inst(10) = '0') then
                                                        string_reg <= x"20524C432020";   -- " SLC  "
                                                    else
                                                        string_reg <= x"20524C434320";   -- " SLCC "
                                                    end if;
                                                when others =>
                                                    string_reg <= x"3F3F3F3F3F3F";       -- "??????"
                                            end case;
                                    end case;
                                else                                -- LD/ST/BR opcode
                                    if (s_inst(15 downto 10) = "101010") then   -- JMP/LD/ST
                                        case s_inst(9 downto 7) is      -- switching on Rb
                                            when 0 =>
                                                string_reg <= x"204A4D502020";          -- " JMP  "
                                            when 2 =>
                                                string_reg <= x"20204C442020";          -- "  LD  "
                                                no_rb <= true;
                                            when 3 =>
                                                string_reg <= x"202053542020";          -- "  ST  "
                                                no_rb <= true;
                                                rc_first <= true;
                                            when others =>
                                                string_reg <= x"3F3F3F3F3F3F";          -- "??????"
                                        end case;
                                    elsif (s_inst(15 downto 11) = "01000") then -- JMPC/LDC/STC/BEQ/BNE/LDS/STS
                                        case s_inst(9 downto 7) is
                                            when 0 =>
                                                string_reg <= x"204A4D504320";          -- " JMPC "
                                            when 2 =>
                                                string_reg <= x"204C44432020";          -- " LDC  "
                                            when 3 =>
                                                string_reg <= x"205354432020";          -- " STC  "
                                                rc_first <= true;
                                            when 4 =>
                                                string_req <= x"204245512020";          -- " BEQ  "
                                            when 5 =>
                                                string_req <= x"20424E452020";          -- " BNE  "
                                            when 6 =>
                                                string_req <= x"204C44532020";          -- " LDS  "
                                                rc_only <= true;
                                            when 7 =>
                                                string_req <= x"205354532020";          -- " STS  "
                                                rc_only <= true;
                                            when others =>
                                                string_req <= x"3F3F3F3F3F3F";          -- "??????"
                                        end case;
                                    else
                                        string_reg <= x"3F3F3F3F3F3F";                  -- "??????"
                                    end if;
                                end if;
                            
                            when 2 =>                           -- print six characters of the string to the LCD, byte by byte
                                data_wr <= string_reg(loop_index downto loop_index - 7);    -- get next byte to print
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 8;                               -- decrement the loop index to next byte
                                if (loop_index = 7) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 3;                                         -- come back here after last character, but to next step
                                    loop_index <= 4;                                        -- next step, print 5 spaces
                                end if;

                            when 3 =>                           -- print 5 spaces
                                data_wr <= x"20";                                           -- ascii for space
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 4;                                         -- come back here after last space, but to next step
                                    loop_index <= 15;                                       -- next step, convert NEXT_PC to hex string
                                end if;

                            when 4 =>                           -- convert NEXT_PC to 4 hexadecimal digit string
                                string_reg(loop_index * 2 + 1 downto loop_index * 2 - 6)    -- get next digit into string as ascii character
                                    <= to_hex_ascii(s_pc(loop_index downto loop_index - 3));
                                loop_index <= loop_index - 4;                               -- decrement loop index to next digit
                                if (loop_index = 3) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 5;                                         -- come back here after converting last digit, but to next step
                                    loop_index <= 31;                                       -- next step, print four characters of the hex string
                                end if;

                            when 5 =>                           -- print hex string to the LCD, character by character
                                data_wr <= string_reg(loop_index downto loop_index - 7);    -- get next byte to print
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 8;                               -- decrement loop index to next byte
                                if (loop_index = 7) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 6;                                         -- come back here after last character, but to next step
                                    loop_index <= 22;                                       -- next up, print 23 spaces
                                end if;

                            when 6 =>                           -- print 23 spaces
                                data_wr <= x"20";                                           -- ascii for space
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 7;                                         -- come back here after last space, but to next step
                                    loop_index <= 2;                                        -- next step, print first argument (three characters)
                                end if;
                            
                            when 7 =>                           -- print first instruction argument
                                case loop_index is                  -- switch on loop index to select character to print
                                    when 2 =>                           -- print 'R' or space
                                        if (rc_only) then
                                            data_wr <= x"20";                               -- ascii for space
                                        else
                                            data_wr <= x"52";                               -- ascii for 'R'
                                        end if;
                                    when 1 =>                           -- print register number or space
                                        if (rc_only) then
                                            data_wr <= x"20";                               -- ascii for space
                                        elsif (rc_first) then
                                            data_wr <= to_hex_ascii(s_inst(5 downto 3));    -- convert Rc to ascii digit
                                        else
                                            data_wr <= to_hex_ascii(s_inst(2 downto 0));    -- convert Ra to ascii digit
                                        end if;
                                    when others =>                      -- print space
                                        data_wr <= x"20";                                   -- ascii for space
                                end case;
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index to next character
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 8;                                         -- come back here after last character, but to next step
                                    loop_index <= 15;                                       -- next step, convert constant to hex string if needed
                                end if;

                            when 8 =>                       -- convert CONST to 4 hexadecimal digit string if needed
                                if (s_inst(10) = '0' OR rc_only) then           -- this step not needed, go to next step
                                    cmd_index <= 9;                                         -- go to next step, print spaces or second argument (register)
                                    loop_index <= 4;                                        -- print 5 characters
                                else                                            -- convert CONST and add to the string register
                                    string_reg(loop_index * 2 + 1 downto loop_index * 2 - 6)    -- get next digit into string as ascii character
                                        <= to_hex_ascii(s_const(loop_index downto loop_index - 3));
                                    loop_index <= loop_index - 4;                           -- decrement loop index to next digit
                                    if (loop_index = 3) then                                -- come back here to this step unless we're finished
                                        cmd_index <= 9;                                     -- come back here after converting last digit, but to next step
                                        loop_index <= 4;                                    -- next step, print second argument (5 characters)
                                    end if;
                                end if;

                            when 9 =>                       -- print second instruction argument
                                if no_rb then
                                    data_wr <= x"20";                                       -- print only spaces if no_rb is true
                                elsif s_inst(10) = '0' then                     -- print either space or Rb if no constant
                                    case loop_index is
                                        when 3 =>
                                            data_wr <= x"52";                               -- ascii for 'R'
                                        when 2 =>                                          -- convert Rb to ascii digit
                                            data_wr <= to_hex_ascii(s_inst(8 downto 6));
                                        when others =>
                                            data_wr <= x"20";                               -- otherwise get ascii for leading and trailing space    
                                    end case;
                                else                                            -- constant exists, print digits of CONST or trailing space
                                    if (loop_index = 0) then
                                        data_wr <= x"20";                                   -- ascii for trailing space
                                    else                                                    -- get character in string register
                                        data_wr <= string_reg(loop_index * 8 - 1 downto loop_index * 8 - 8);
                                    end if;
                                end if;
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index to next character
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 10;                                        -- come back here after last character, but to next step
                                    loop_index <= 1;                                        -- next step, print third argument (two characters)
                                end if;

                            when 10 =>                      -- print third instruction argument
                                if rc_only then                                 -- print space if rc only
                                    data_wr <= x"20";                                       -- ascii for space
                                else                                            -- print "Rx" for third argument
                                    if (loop_index = 0) then
                                        data_wr <= x"52";                                   -- ascii for 'R'
                                    else
                                        if (rc_first) then
                                            data_wr <= to_hex_ascii(s_inst(2 downto 0));    -- Rc was first, so now convert Ra to ascii digit
                                        else
                                            data_wr <= to_hex_ascii(s_inst(5 downto 3));    -- convert Rc to ascii digit
                                        end if;
                                    end if;
                                end if;
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index to next character
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 11;                                        -- come back here after last character, but to next step
                                    loop_index <= 8;                                        -- next step, print 9 spaces
                                end if;

                            when 11 =>                      -- print 9 spaces
                                data_wr <= x"20";                                           -- ascii for space
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 12;                                        -- come back here after last space, but to next step
                                    loop_index <= 47;                                       -- next step, convert SEGMENT and ADDRESS to ascii string
                                end if;

                            when 12 =>                      -- convert SEGMENT and ADDRESS to 6 hexidecimal digit string
                                if loop_index > 31 then
                                    string_reg(loop_index downto loop_index - 7)            -- get next digit of SEGMENT into string as ascii character
                                        <= to_hex_ascii(s_seg((loop_index - 31)/2 - 1 downto (loop_index - 31)/2 - 4));
                                else
                                    string_reg(loop_index downto loop_index - 7)            -- get next digit of ADDR into string as ascii character
                                        <= to_hex_ascii(s_addr((loop_index + 1)/2 - 1 downto (loop_index + 1)/2 - 4));
                                end if;
                                loop_index <= loop_index - 8;                               -- decrement loop index to next byte
                                if (loop_index = 7) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 13;                                        -- come back here after converting last digit, but to next step
                                    loop_index <= 6;                                        -- next step, print SEG:ADDR (7 characters)
                                end if;

                            when 13 =>                      -- print SEG:ADDR
                                if loop_index > 4 then
                                    data_wr <= string_reg(loop_index * 8 - 1 downto loop_index * 8 - 7);    -- get next byte of SEGMENT to print
                                elsif loop_index = 4 then
                                    data_wr <= x"3A";                                       -- ascii for ":"
                                else
                                    data_wr <= string_reg(loop_index * 8 + 7 downto loop_index * 8);        -- get next byte of ADDR to print
                                end if;
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index to next byte
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 14;                                        -- come back here after last character, but to next step (print arrow for write or read)
                                end if;

                            when 14 =>                      -- print arrow corresponding to read or write
                                if s_wr = '0' then
                                    data_wr <= x"7E";                                       -- read: right arrow from address to data
                                else
                                    data_wr <= x"7F";                                       -- write: left arrow from data to address
                                end if;
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                cmd_index <= 15;                                            -- come back here, but to next step
                                loop_index <= 15;                                           -- next step, convert MDATA to ascii string

                            when 15 =>                      -- convert MDATA to a hex string
                                string_reg(loop_index * 2 + 1 downto loop_index * 2 - 6)    -- get next digit into string as ascii character
                                    <= to_hex_ascii(s_mdata(loop_index downto loop_index - 3));
                                loop_index <= loop_index - 4;                               -- decrement loop index to next digit
                                if (loop_index = 3) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 16;                                        -- come back here after converting last digit, but to next step
                                    loop_index <= 31;                                       -- next step, print four characters of the hex string
                                end if;

                            when 16 =>                      -- print MDATA
                                data_wr <= string_reg(loop_index downto loop_index - 7);    -- get next byte to print
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 8;                               -- decrement loop index to next byte
                                if (loop_index = 7) then                                    -- come back here to this step unless we're finished
                                    cmd_index <= 17;                                        -- come back here after last character, but to next step
                                    loop_index <= 1;                                        -- next up, print 2 spaces
                                end if;

                            when 17 =>                      -- print 2 spaces
                                data_wr <= x"20";                                           -- ascii for space
                                state <= SENDBYTE;                                          -- next state -> send the byte
                                loop_index <= loop_index - 1;                               -- decrement loop index
                                if (loop_index = 0) then                                    -- come back here to this step unless we're finished
                                    state <= READY;                                         -- all done with update! go back to ready
                                end if;
                        end case;
                    
                    when SENDBYTE =>                -- send byte to I2C based on data_wr and data_cmd
                        subcmd_idx <= subcmd_idx + 1;       -- increment command index
                        send_return1 <= SENDBYTE;           -- set return state to come back here - send_return2 is state of the SENDBYTE caller

                        case subcmd_idx is
                                -- send the byte as two nybbles in bits 7-4, bit 3 is always on (backlight), bit 2 is enable, bit 1 is always off (write), bit 0 is data_cmd
                            when 0 =>               -- send high nybble
                                i2c_data_wr <= data_wr(7 downto 4) & "100" & data_cmd;      -- write nybble with enable low
                                state <= SEND;
                            
                            when 1 =>
                                i2c_data_wr <= data_wr(7 downto 4) & "110" & data_cmd;      -- pulse enable high
                                state <= SEND;

                            when 2 =>               -- delay after pulse 1 us (1/1us = 1_000_000)
                                delay_counter <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 3 =>               -- "pulse enable" step 2
                                i2c_data_wr <= data_wr(7 downto 4) & "100" & data_cmd;      -- return to enable low
                                state <= SEND;

                            when 4 =>               -- delay after pulse 50 us (1/50us = 20_000)
                                delay_counter <= CLK_FREQ/20_000;
                                state <= DELAY;

                            when 5 =>               -- send low nybble
                                i2c_data_wr <= data_wr(3 downto 0) & "100" & data_cmd;      -- write nybble with enable low
                                state <= SEND;

                            when 6 =>
                                i2c_data_wr <= data_wr(3 downto 0) & "110" & data_cmd;      -- pulse enable high
                                state <= SEND;

                            when 7 =>               -- delay after pulse 1 us
                                delay_counter <= CLK_FREQ/1_000_000;
                                state <= DELAY;

                            when 8 =>               -- "pulse enable" step 2
                                i2c_data_wr <= data_wr(3 downto 0) & "100" & data_cmd;      -- return to enable low
                                state <= SEND;

                            when 9 =>               -- delay after pulse 50 us
                                delay_counter <= CLK_FREQ/20_000;
                                state <= DELAY;

                            when others =>          -- done
                                subcmd_idx <= 0;        -- reset subcmd_idx
                                state <= send_return2;  -- return to caller (using return2 because send_return1 was used here to return from SEND and DELAY)
                        end case;

                    when DELAY =>                   -- delay for delay_cntr counts
                        if delay_cntr = 0 then
                            state <= send_return1;          -- countdown over, return to caller
                        else
                            delay_cntr <= delay_cntr - 1;   -- decrement delay counter
                        end if;

                    when SEND =>                    -- send command/data to LCD
                        busy_prev <= i2c_busy;                              -- track pevious and current busy signal
                        if (busy_prev = '0' AND i2c_busy = '1') then        -- wasn't busy, now is
                            cmd_latched <= '1';
                        end if;

                        if cmd_latched = '0' AND i2c_ena = '0' then         -- ready to initiate the transaction and wait for busy?
                            i2c_ena <= '1';
                        elsif cmd_latched = '1' AND i2c_ena = '1' then      -- busy transitioned?
                            i2c_ena <= '0';                                 -- command has been latched, deassert enable to stop transaction, wait for busy to be cleared
                        elsif cmd_latched = '1' AND i2c_busy = '0' then     -- busy cleared?
                            cmd_latched <= '0';                             -- clear latch flag
                            state <= send_return1;                           -- return to appropriate state
                        end if;
                end case;
            end if;
        end if;
    end process;

    I2C: entity work.i2c_master port map (
        CLK       => CLK,                               -- system clock
        RESET_N   => NOT(RST),                          -- active low reset
        ENA       => i2c_ena,                           -- enable signal for starting transaction
        ADDR      => LCD_ADDRESS,                       -- 7-bit provider address 0x27 for LCD
        RW        => '0',                               -- read/write signal - already set to write
        DATA_WR   => i2c_data_wr,                       -- data to write to provider
        BUSY      => i2c_busy,                          -- indicates transaction in progress
        DATA_RD   => OPEN,                              -- never reading
        ACK_ERROR => OPEN,                              -- indicate acknowledge error on LEDG(9)

        SDA       => SDA,                               -- serial data signal of i2c bus
        SCL       => SCL                                -- serial clock signal of i2c bus
    );

end RTL;