--------------------------------------------------------------------------------
--
--   FileName:         i2c_master.vhd
--   Dependencies:     none
--   Design Software:  Quartus II 64-bit Version 13.1 Build 162 SJ Full Version
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 11/01/2012 Scott Larson
--     Initial Public Release
--   Version 2.0 06/20/2014 Scott Larson
--     Added ability to interface with different slaves in the same transaction
--     Corrected ack_error bug where ack_error went 'Z' instead of '1' on error
--     Corrected timing of when ack_error signal clears
--   Version 2.1 10/21/2014 Scott Larson
--     Replaced gated clock with clock enable
--     Adjusted timing of SCL during start and stop conditions
--   Version 2.2 02/05/2015 Scott Larson
--     Corrected small SDA glitch introduced in version 2.1
-- 
-- Small modifications by Scott Berk
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;

ENTITY i2c_master IS
    GENERIC (
        INPUT_CLK : INTEGER := 50_000_000;          -- input clock speed from user logic in Hz
        BUS_CLK   : INTEGER := 400_000              -- speed the i2c bus (scl) will run at in Hz
    );

    PORT (
        CLK       : IN     STD_LOGIC;                       -- system clock
        RESET_N   : IN     STD_LOGIC;                       -- active low reset
        ENA       : IN     STD_LOGIC;                       -- latch in command
        ADDR      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0);    -- address of target slave
        RW        : IN     STD_LOGIC;                       -- '0' is write, '1' is read
        DATA_WR   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0);    -- data to write to slave

        BUSY      : OUT    STD_LOGIC;                       -- indicates transaction in progress
        DATA_RD   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0);    -- data read from slave
        ACK_ERROR : OUT    STD_LOGIC;                       -- flag if improper acknowledge from slave

        SDA       : INOUT  STD_LOGIC;                       -- serial data signal of i2c bus
        SCL       : INOUT  STD_LOGIC                        -- serial clock signal of i2c bus
    );
END i2c_master;

ARCHITECTURE logic OF i2c_master IS
    CONSTANT divider     : INTEGER := (INPUT_CLK/BUS_CLK)/4;    -- number of clocks in 1/4 cycle of scl

    SIGNAL data_clk      : STD_LOGIC;                           -- data clock for sda
    SIGNAL data_clk_prev : STD_LOGIC;                           -- data clock during previous system clock
    SIGNAL scl_clk       : STD_LOGIC;                           -- constantly running internal scl
    SIGNAL scl_ena       : STD_LOGIC := '0';                    -- enables internal scl to output
    SIGNAL sda_int       : STD_LOGIC := '1';                    -- internal sda
    SIGNAL sda_ena_n     : STD_LOGIC;                           -- enables internal sda to output
    SIGNAL addr_rw       : STD_LOGIC_VECTOR(7 DOWNTO 0);        -- latched in address and read/write
    SIGNAL data_tx       : STD_LOGIC_VECTOR(7 DOWNTO 0);        -- latched in data to write to provider
    SIGNAL data_rx       : STD_LOGIC_VECTOR(7 DOWNTO 0);        -- data received from provider

    SIGNAL busy_int      : STD_LOGIC := '0';                    -- internal busy flag
    SIGNAL data_rd_int   : STD_LOGIC_VECTOR(7 DOWNTO 0);        -- internal data read from provider
    SIGNAL ack_bit       : STD_LOGIC := '0';                    -- acknowledge bit from provider
    SIGNAL ack_error_int : STD_LOGIC := '0';                    -- internal acknowledge error flag

    SIGNAL bit_cnt       : INTEGER RANGE 0 TO 7 := 7;           -- tracks bit number in transaction
    SIGNAL stretch       : STD_LOGIC := '0';                    -- identifies if slave is stretching scl

    TYPE MACHINE IS (READY, START, COMMAND, ACK1, WR, RD, ACK2, MSTR_ACK, STOP);     -- needed states
    SIGNAL state         : MACHINE;                             -- state machine

BEGIN

    -- set outputs
    ACK_ERROR <= ack_error_int;                                 -- assign internal acknowledge error to output
    DATA_RD <= data_rd_int;                                     -- assign internal data read to output
    BUSY <= BUSY_int;                                           -- assign internal busy flag to output

    --set sda output
    WITH state SELECT
        sda_ena_n <= data_clk_prev     WHEN START,               -- generate start condition
                     NOT data_clk_prev WHEN STOP,                -- generate stop condition
                     sda_int           WHEN OTHERS;              -- set to internal sda signal
        
    --set scl and sda outputs - Since outputs are pulled up, 'Z' state releases line for input or sets '1' as output
    SCL <= '0' WHEN (scl_ena = '1' AND scl_clk = '0') ELSE 'Z';
    SDA <= '0' WHEN sda_ena_n = '0' ELSE 'Z';

    -- generate the timing for the bus clock (scl_clk) and the data clock (data_clk)
    PROCESS(CLK)

    VARIABLE count  :  INTEGER RANGE 0 TO divider * 4;  -- timing for clock generation
  
    BEGIN
        IF (rising_edge(CLK)) THEN
            IF (RESET_N = '0') THEN                     -- reset asserted
                stretch <= '0';
                count := 0;
            ELSE
                data_clk_prev <= data_clk;              -- store previous value of data clock

                IF (count = divider * 4 - 1) THEN       -- end of timing cycle
                    count := 0;                         -- reset timer
                ELSIF (stretch = '0') THEN              -- clock stretching from provider not detected
                    count := count + 1;                 -- continue clock generation timing
                END IF;

                IF (count < divider) THEN                                       -- first 1/4 cycle of clocking
                    scl_clk <= '0';
                    data_clk <= '0';
                ELSIF (count = divider) AND (count < divider * 2) THEN      -- second 1/4 cycle of clocking
                    scl_clk <= '0';
                    data_clk <= '1';
                ELSIF (count = divider * 2) AND (count < divider * 3) THEN  -- third 1/4 cycle of clocking
                    scl_clk <= '1';                 -- release scl
                    IF (SCL = '0') THEN             -- detect if provider is stretching clock
                        stretch <= '1';
                    ELSE
                        stretch <= '0';
                    END IF;
                    data_clk <= '1';
                ELSE                                                            -- last 1/4 cycle of clocking
                    scl_clk <= '1';
                    data_clk <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    --state machine and writing to sda during scl low (data_clk rising edge)
    PROCESS(CLK)
    BEGIN
        IF (rising_edge(CLK)) THEN
            IF (RESET_N = '0') THEN                         -- reset asserted
                state <= ready;                             -- return to initial state
                scl_ena <= '0';                             -- sets scl high impedance
                sda_int <= '1';                             -- sets sda high impedance
                ack_error_int <= '0';                       -- clear acknowledge error flag
                bit_cnt <= 7;                               -- restarts data bit counter

                data_rd_int <= "00000000";                  -- clear data read port
                busy_int <= '1';                            -- indicate not available
            ELSE
                IF (data_clk = '1' AND data_clk_prev = '0') THEN    -- data clock rising edge
                    CASE state IS
                        WHEN READY =>                   -- idle state
                            IF (ENA = '1') THEN             -- transaction requested
                                busy_int <= '1';                -- flag busy
                                addr_rw <= ADDR & RW;           -- collect requested slave address and command
                                data_tx <= DATA_WR;             -- collect requested data to write
                                state <= START;                 -- go to start bit
                            ELSE                            -- remain idle
                                busy_int <= '0';                -- unflag busy
                                state <= ready;                 -- remain idle
                            END IF;

                        WHEN START =>                   -- start bit of transaction
                            busy_int <= '1';                -- resume busy if continuous mode
                            sda_int <= addr_rw(bit_cnt);    -- set first address bit to bus
                            state <= COMMAND;               -- go to command

                        WHEN COMMAND =>                 -- address and command byte of transaction
                            IF (bit_cnt = 0) THEN           -- command transmit finished
                                sda_int <= '1';                 -- release sda for provider acknowledge
                                bit_cnt <= 7;                   -- reset bit counter for "byte" states
                                state <= ACK1;                  -- go to provider acknowledge (command)
                            ELSE                            -- next clock cycle of command state
                                bit_cnt <= bit_cnt - 1;         -- keep track of transaction bits
                                sda_int <= addr_rw(bit_cnt-1);  -- write address/command bit to bus
                                state <= COMMAND;               -- continue with command
                            END IF;

                        WHEN ACK1 =>                    -- provider acknowledge bit (command)
                            IF (addr_rw(0) = '0') THEN      -- write command
                                sda_int <= data_tx(bit_cnt);    -- write first bit of data
                                state <= WR;                    -- go to write byte
                            ELSE                            -- read command
                                sda_int <= '1';                 -- release sda from incoming data
                                state <= RD;                    -- go to read byte
                            END IF;

                        WHEN WR =>                      -- write byte of transaction
                            busy_int <= '1';                -- resume busy if continuous mode
                            IF (bit_cnt = 0) THEN           -- write byte transmit finished
                                sda_int <= '1';                 -- release sda for slave acknowledge
                                bit_cnt <= 7;                   -- reset bit counter for "byte" states
                                state <= ACK2;                  -- go to slave acknowledge (write)
                            ELSE                            --next clock cycle of write state
                                bit_cnt <= bit_cnt - 1;         -- keep track of transaction bits
                                sda_int <= data_tx(bit_cnt-1);  -- write next bit to bus
                                state <= WR;                    -- continue writing
                            END IF;

                        WHEN RD =>                      -- read byte of transaction
                            busy_int <= '1';                -- resume busy if continuous mode
                            IF (bit_cnt = 0) THEN           -- read byte receive finished
                                IF (ENA = '1' AND addr_rw = ADDR & RW) THEN -- continuing with another read at same address
                                    sda_int <= '0';                 -- acknowledge the byte has been received
                                ELSE                            -- stopping or continuing with a write
                                    sda_int <= '1';                 -- send a no-acknowledge (before stop or repeated start)
                                END IF;
                                bit_cnt <= 7;                   -- reset bit counter for "byte" states
                                data_rd_int <= data_rx;         -- output received data
                                state <= MSTR_ACK;              -- go to master acknowledge
                            ELSE                            -- next clock cycle of read state
                                bit_cnt <= bit_cnt - 1;         -- keep track of transaction bits
                                state <= RD;                    -- continue reading
                            END IF;

                        WHEN ACK2 =>                    -- provider acknowledge bit (write)
                            IF (ENA = '1') THEN             -- continue transaction
                                busy_int <= '0';                -- continue is accepted
                                addr_rw <= ADDR & RW;           -- collect requested provider address and command
                                data_tx <= DATA_WR;             -- collect requested data to write
                                IF (addr_rw = ADDR & RW) THEN   -- continue transaction with another write
                                    sda_int <= DATA_WR(bit_cnt);    -- write first bit of data
                                    state <= WR;                    -- go to write byte
                                ELSE                            -- continue transaction with a read or new slave
                                    state <= START;                 -- go to repeated start
                                END IF;
                            ELSE                            -- complete transaction
                                state <= STOP;                  -- go to stop bit
                            END IF;

                        WHEN MSTR_ACK =>                -- master acknowledge bit after a read
                            IF (ENA = '1') THEN             -- continue transaction
                                busy_int <= '0';                -- continue is accepted and data received is available on bus
                                addr_rw <= ADDR & RW;           -- collect requested slave address and command
                                data_tx <= DATA_WR;             -- collect requested data to write
                                IF (addr_rw = ADDR & RW) THEN   -- continue transaction with another read
                                    sda_int <= '1';                 -- release sda from incoming data
                                    state <= RD;                    -- go to read byte
                                ELSE                            -- continue transaction with a write or new slave
                                    state <= START;                 -- repeated start
                                END IF;    
                            ELSE                            -- complete transaction
                                state <= STOP;                  -- go to stop bit
                            END IF;

                        WHEN STOP =>                    -- stop bit of transaction
                            busy_int <= '0';                -- unflag busy
                            state <= READY;                 -- go to idle state
                    END CASE;

                ELSIF (data_clk = '0' AND data_clk_prev = '1') THEN -- data clock falling edge
                    CASE state IS
                        WHEN START =>                  
                            IF (scl_ena = '0') THEN     -- starting new transaction
                                scl_ena <= '1';             -- enable scl output
                                ack_error_int <= '0';       -- reset acknowledge error output
                            END IF;

                        WHEN ACK1 =>                -- receiving provider acknowledge (command)
                            IF (SDA /= '0' OR ack_error_int = '1') THEN -- no-acknowledge or previous no-acknowledge
                                ack_error_int <= '1';                       -- set error output if no-acknowledge
                            END IF;

                        WHEN RD =>                  -- receiving provider data
                            data_rx(bit_cnt) <= SDA;    -- receive current provider data bit

                        WHEN ACK2 =>                -- receiving provider acknowledge (write)
                            IF (SDA /= '0' OR ack_error_int = '1') THEN -- no-acknowledge or previous no-acknowledge
                                ack_error_int <= '1';                       -- set error output if no-acknowledge
                            END IF;

                        WHEN STOP =>
                            scl_ena <= '0';             -- disable scl

                        WHEN OTHERS =>
                            NULL;

                    END CASE;

                END IF;
            END IF;
        END IF;
    END PROCESS;  
END logic;
