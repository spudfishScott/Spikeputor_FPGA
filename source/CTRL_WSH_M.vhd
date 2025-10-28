-- Spikeputor Control Logic and Memory Wishbone Interface Master
-- Data and ADDRESS buses are 16 bits wide
-- Each CPU instruction cycle can be up to three read/writes, so execute them in a single wishbone BLOCK READ/WRITE cycle
-- ACK_I is the only termination signal currently supported. RTY_I and ERR_I are not supported.

-- Contains the INST, CONST, and PC registers
-- Also contains the state machine for fetching instructions and constants from memory
-- and executing instructions, including memory read and write operations.
-- Uses a FSM to manage instruction fetch, constant fetch, and execution phases (with out without memory r/w command) with stalling as needed for memory acknowledgements.
-- Includes a PHASE output to indicate current phase of instruction cycle for display purposes
-- Memory interface is a Wishbone Provider interface
-- Inputs from ALU and Register File, outputs to Register File and ALU control signals
-- Memory write data is directly from Register File Channel B output (MWDATA)
-- Memory Read Data is output to MRDATA signal
-- Program Counter (PC) is incremented by 2 for each instruction, unless a branch or jump occurs
-- On reset, PC is set to the RESET_VECTOR address (xF000)
-- Instruction format:
--     Bits 15-11: ALU Opcode
--     Bit 10:    '1' if instruction has a constant (CONST), '0' if no constant
--     Bit 9:     '1' if instruction is a memory (LD, LDR, ST) or branch (JMP, BEQ, BNE) operation, '0' for other instructions
--     Bits 8-6:  Register Operand B or Memory/Branch opcode
--                For memory operations:
--                  "010" for LD and LDC instructions
--                  "110" for LDR instruction
--                  "011" for ST and STC instructions
--                For branch instructions:
--                  "000" = JMP (unconditional)
--                  "100" = BEQ (branch if zero)
--                  "101" = BNE (branch if not zero)
--     Bits 5-3:  Register Operand C
--     Bits 2-0:  Register Operand A - directly to Channel A of Register File
-- ALU Control signals:
    -- ALUFN: INST(15 downto 11)
    -- ASEL:  INST(8) AND INST(9)
    -- BSEL:  INST(10)
-- Register File Control signals:
    -- WERF:  '1' to write to register file, '0' otherwise
    -- RBSEL: '0' to select OPB, '1' to select OPC for Channel B output
    -- WDSEL: "01" to select ALU output, "00" to select PC+2, "10" to select Memory Read Data
    -- OPA:   INST(2 downto 0)
    -- OPB:   INST(8 downto 6)
    -- OPC:   INST(5 downto 3)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity CTRL_WSH_M is
    generic (
        RESET_VECTOR : std_logic_vector(15 downto 0) := x"F000"  -- reset vector address
    );
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;
        STALL_I     : in std_logic;                         -- stall input from CPU to pause operation for debugging

        -- Wishbone signals for memory interface
        -- handshaking signals
        WBS_CYC_O   : out std_logic;
        WBS_STB_O   : out std_logic;
        WBS_ACK_I   : in std_logic;

        -- memory read/write signals
        WBS_ADDR_O  : out std_logic_vector(15 downto 0);    -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);    -- data output to provider
        WBS_DATA_I  : in std_logic_vector(15 downto 0);     -- data input from provider
        WBS_WE_O    : out std_logic;                        -- write enable output - write when high, read when low

        -- Spikeputor Signals
            -- Data outputs from Control Logic to other modules
        INST    : out std_logic_vector(15 downto 0);                      -- instruction fetched from memory - for display only
        CONST   : out std_logic_vector(15 downto 0);                      -- constant fetched from memory
        PC      : out std_logic_vector(15 downto 0);                      -- program counter
        PC_INC  : out std_logic_vector(15 downto 0);                      -- incremented program counter
        MRDATA  : out std_logic_vector(15 downto 0);                      -- memory read data

            -- Control signals from Control Logic to RegFile
        WERF    : out std_logic;                                          -- Write Enable Register File - '1' to write to register file
        RBSEL   : out std_logic;                                          -- Register Channel B Select - '0' for OPB, '1' for OPC
        WDSEL   : out std_logic_vector(1 downto 0);                       -- Write Data Select - "01" for ALU, "00" for PC+2, "10" for Memory Read Data
        OPA     : out std_logic_vector(2 downto 0);                       -- Register Operand A
        OPB     : out std_logic_vector(2 downto 0);                       -- Register Operand B
        OPC     : out std_logic_vector(2 downto 0);                       -- Register Operand C

            -- Control signals from Control Logic to ALU
        ALUFN   : out std_logic_vector(4 downto 0);                       -- ALU Function select - opcode from instruction
        ASEL    : out std_logic;                                          -- ALU A input select - '0' for REGFile Channel A, '1' for PC+2
        BSEL    : out std_logic;                                          -- ALU B input select - '0' for REGFile Channel B, '1' for CONST

            -- Inputs to Control Logic from other modules
        ALU_OUT : in std_logic_vector(15 downto 0);                       -- ALU output
        MWDATA  : in std_logic_vector(15 downto 0);                       -- memory write data - Register Channel B output
        Z       : in std_logic;                                           -- Zero flag from RegFile Channel A

        PHASE   : out std_logic_vector(2 downto 0)                        -- current phase of instruction cycle
    );
end CTRL_WSH_M;

architecture rtl of CTRL_WSH_M is

    -- internal signals
    -- internal registers to hold outputs
    signal INST_reg    : std_logic_vector(15 downto 0) := (others => '0');   -- instruction fetched from memory
    signal CONST_reg   : std_logic_vector(15 downto 0) := (others => '0');   -- constant fetched from memory
    signal PC_reg      : std_logic_vector(15 downto 0) := (others => '0');   -- program counter
    signal PC_INC_calc : std_logic_vector(15 downto 0) := (others => '0');   -- incremented program counter

    signal WERF_sig    : std_logic := '0';                                   -- Write Enable for Register File - on during execute phase if instruction is not a store (ST command)

    -- state machine
    type fsm_main is (ST_FETCH_I, ST_FETCH_I_WAIT, ST_FETCH_C, ST_FETCH_C_WAIT, ST_EXECUTE, ST_EXECUTE_RW, ST_EXECUTE_RW_WAIT);
    signal st_main : fsm_main := ST_FETCH_I;

begin
    -- Spikeputor control outputs, including control signals for ALU and Register File
    PC          <= PC_reg;                                                  -- program counter
    PC_INC      <= PC_INC_calc;                                             -- incremented program counter
    INST        <= INST_reg;                                                -- instruction fetched from memory
    CONST       <= CONST_reg;                                               -- constant fetched from memory

    -- Control Signal Logic
    MRDATA <= WBS_DATA_I;
    RBSEL       <= '1' when INST_reg(8 downto 6) = "011" else '0';          -- RBSEL = '0' for OPB, '1' for OPC RBSEL is '1' for ST and STC instructions, else '0'
    -- issue with non-manual run of fibonacci. Other signals probably need to be synchronous
    WERF        <= WERF_sig;                                                -- WERF = 1 during execute phases if instruction is not a store (ST command)
    WDSEL       <=  "10" when (INST_reg(9) = '1' AND INST_reg(7 downto 6) = "10") else      -- Write Data Select: use Memory Read Data as Register Input for LD and LDR instructions
                    "00" when (INST_reg(9) = '1' AND INST_reg(7) = '0') else                --      use PC+2 as Register Input for Branch Instructions
                    "01";                                                                   --      else use ALU output as Register Input for all other instructions
    OPA         <= INST_reg(2 downto 0);                                    -- OPA is always bits 2-0
    OPB         <= INST_reg(8 downto 6);                                    -- OPB is always bits 8-6
    OPC         <= INST_reg(5 downto 3);                                    -- OPC is always bits 5-3
    ALUFN       <= INST_reg(15 downto 11);                                  -- ALU Function Select - ALUFN is always bits 15-11
    ASEL        <= INST_reg(8) AND INST_reg(9);                             -- ASEL = 1 for PC+2 (for memory and branching instructions), else 0 for RegFile Channel A
    BSEL        <= INST_reg(10);                                            -- BSEL = 1 for CONST (for instructions that get a constant), else 0 for RegFile Channel B

    WBS_DATA_O  <= MWDATA;                                                  -- data output is directly from Register File Channel B output
    WBS_WE_O    <= '1'  when INST_reg(9 downto 6) = "1011" AND
                             (st_main = ST_EXECUTE_RW OR st_main = ST_EXECUTE_RW_WAIT) AND
                             RST_I = '0' else '0';                          -- write enable high for ST and STC instructions during execute with r/w phase


    -- Generate PHASE signal for display purposes
    WITH (st_main) SELECT                       -- current phase of instruction cycle for display purposes
        PHASE <= 
            "000" when ST_FETCH_I,
            "001" when ST_FETCH_I_WAIT,
            "010" when ST_FETCH_C,
            "011" when ST_FETCH_C_WAIT,
            "100" when ST_EXECUTE,
            "101" when ST_EXECUTE_RW,
            "111" when ST_EXECUTE_RW_WAIT,
            "000" when others;  -- should never occur, default to fetch instruction phase

    PC_INC_calc <= std_logic_vector(unsigned(PC_reg) + 2);

    process(clk)
    begin
        if rising_edge(clk) then
            if RST_I = '1' then
                -- reset state
                st_main <= ST_FETCH_I;          -- start by fetching instruction
                PC_reg <= RESET_VECTOR;         -- set PC to reset vector
                WERF_sig <= '0';                -- do not write to registers during reset

                 -- clear wishbone signals
                WBS_CYC_O <= '0';               -- clear wishbone handshake signals
                WBS_STB_O <= '0';
                WBS_ADDR_O <= RESET_VECTOR;     -- set address to reset vector
            else
                -- normal operation
                WERF_sig <= '0';                -- do not write to registers unless specifically set below
                if STALL_I = '0' then              -- only proceed if not stalled for debugging, otherwise hold current state and do nothing
                    case st_main is
                        when ST_FETCH_I =>
                            -- fetch instruction from memory at address PC
                            if WBS_ACK_I = '0' then             -- confirm that acknowledgement is clear and we're not stalled for debugging
                                WBS_CYC_O <= '1';               -- initiate wishbone cycle
                                WBS_STB_O <= '1';               -- strobe to indicate valid address and start memory read
                                st_main <= ST_FETCH_I_WAIT;	    -- go to wait for instruction (may take more than one clock cycle for non-RAM)
                            else
                                st_main <= ST_FETCH_I;          -- keep waiting until ready
                            end if;

                        when ST_FETCH_I_WAIT =>
                            -- wait for memory to return instruction
                            if WBS_ACK_I = '1' then             -- wait for ack indicating memory read is valid
                                WBS_STB_O <= '0';               -- deassert strobe - end read phase
                                INST_reg <= WBS_DATA_I;         -- latch instruction

                                if WBS_DATA_I(10) = '1' then    -- instruction bit 10 indicates if there is a constant to fetch
                                        st_main <= ST_FETCH_C;          -- instruction has constant - go to fetch constant state
                                        PC_reg <= PC_INC_calc;          -- increment PC for constant
                                        WBS_ADDR_O <= PC_INC_calc;      -- set address of constant
                                else
                                    st_main <= ST_EXECUTE;           -- no constant for this opcode, so execute directly (keeping PC unchanged)
                                end if;
                            else                                -- wait until ack received
                                st_main <= ST_FETCH_I_WAIT;
                            end if;

                        when ST_FETCH_C =>
                            -- fetch constant from memory at now incremented PC
                            if WBS_ACK_I = '0' then             -- confirm that acknowledgement is clear
                                WBS_STB_O <= '1';                   -- strobe to indicate valid address and start memory read
                                st_main <= ST_FETCH_C_WAIT;         -- go to wait for constant (may take more than one clock cycle for non-RAM)
                            else
                                st_main <= ST_FETCH_C;              -- keep waiting until ready
                            end if;

                        when ST_FETCH_C_WAIT =>
                            -- wait for memory to return constant
                            if WBS_ACK_I = '1' then             -- wait for ack indicating memory read is valid
                                WBS_STB_O <= '0';                   -- deassert strobe - end read phase
                                CONST_reg <= WBS_DATA_I;            -- latch constant
                                st_main <= ST_EXECUTE;              -- proceed to execute instruction
                            else
                                st_main <= ST_FETCH_C_WAIT;     -- wait until ack received
                            end if;

                        when ST_EXECUTE =>
                            -- execute instruction
                            if (INST_reg(9) AND INST_reg(7)) = '1' then     -- operation requires memory read or write (LD, LDR, or ST commands)
                                WBS_ADDR_O <= ALU_OUT;                          -- address for memory r/w is ALU output
                                st_main <= ST_EXECUTE_RW;                       -- go to execute_rw state
                            else                                            -- other instructions - do not need to read or write to memory
                                if ((INST_reg(9) = '1') AND                     -- check to see if the branch should be taken (formerly JT = 1)
                                        ((INST_reg(8 downto 6) = "000") OR                    -- unconditional jump (JMP)
                                        (INST_reg(8 downto 6) = "100" AND Z = '1') OR         -- branch if equal to zero (BEQ)
                                        (INST_reg(8 downto 6) = "101" AND Z = '0'))) then     -- branch if not equal to zero (BNE)

                                            PC_reg <= ALU_OUT;          -- set PC to address in ALU output to jump
                                            WBS_ADDR_O <= ALU_OUT;      -- set address of next instruction to ALU_OUT
                                else
                                            PC_reg <= PC_INC_calc;      -- increment PC by 2 for next instruction
                                            WBS_ADDR_O <= PC_INC_calc;  -- set address of next instruction to PC+2
                                end if;

                                WERF_sig <= '1';            -- write to register on next clock
                                WBS_CYC_O <= '0';           -- end wishbone cycle
                                st_main <= ST_FETCH_I;      -- go back to fetch next instruction, no wishbone read/write phase needed
                            end if;

                        when ST_EXECUTE_RW =>
                            -- execute instruction with memory read or write phase
                            if WBS_ACK_I = '0' then         -- confirm that acknowledge has been cleared
                                WBS_STB_O <= '1';                   -- strobe to indicate valid address and start memory read/write
                                st_main <= ST_EXECUTE_RW_WAIT;      -- wait for memory operation to complete
                            else
                                st_main <= ST_EXECUTE_RW;           -- keep waiting until ready
                            end if;

                        when ST_EXECUTE_RW_WAIT =>
                            -- wait for memory read or write operation to complete
                            if WBS_ACK_I = '1' then         -- wait for acknowledge from memory and handle read or write completion
                                if (INST_reg(9 downto 6) /= "1011") then
                                    WERF_sig <= '1';                -- write to register on next clock if not a ST command
                                end if;

                                PC_reg <= PC_INC_calc;              -- increment PC by 2 for next instruction
                                WBS_ADDR_O <= PC_INC_calc;          -- set address of next instruction to PC+2
                                WBS_STB_O <= '0';                   -- deassert strobe
                                WBS_CYC_O <= '0';                   -- end wishbone cycle
                                st_main <= ST_FETCH_I;              -- go back to fetch next instruction
                            else
                                st_main <= ST_EXECUTE_RW_WAIT;      -- wait until ack received
                            end if;

                        when others =>                      -- should never occur
                            st_main <= ST_FETCH_I;                  -- default to fetch instruction state
                    end case;
                end if;
            end if;
        end if;
    end process;

end rtl;