-- Spikeputor Control Logic and Memory Wishbone Interface Master
-- Data and ADDRESS buses are 16 bits wide
-- Each CPU instruction cycle can be up to three read/writes, so execute them in a single wishbone BLOCK READ/WRITE cycle
-- ACK_I is the only termination signal currently supported. RTY_I and ERR_I are not supported.

-- Contains the INST, CONST, and PC registers
-- Also contains the state machine for fetching instructions and constants from memory
-- and executing instructions, including memory read and write operations.
-- Uses a simple 3-state FSM to manage instruction fetch, constant fetch, and execution phases
-- Memory interface is a Wishbone Master interface
-- Inputs from ALU and Register File, outputs to Register File and ALU control signals
-- ALU Control signals:
    -- ALUFN: INST(15 downto 11)
    -- ASEL:  INST(8) AND INST(9)
    -- BSEL:  INST(10)
-- Register File Control signals:
    -- WERF:  '1' to write to register file, '0' otherwise
    -- RBSEL: '0' to select Rb, '1' to select Rc
    -- WDSEL: "00" to select ALU output, "01" to select PC+2, "10" to select Memory Read Data
    -- OPA:   INST(2 downto 0)
    -- OPB:   INST(8 downto 6)
    -- OPC:   INST(5 downto 3)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity CTRL_WSH_M is
    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

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
        INST    : out std_logic_vector(15 downto 0) := (others => '0');   -- instruction fetched from memory
        CONST   : out std_logic_vector(15 downto 0) := (others => '0');   -- constant fetched from memory
        PC      : out std_logic_vector(15 downto 0) := (others => '0');   -- program counter
        PC_INC  : out std_logic_vector(15 downto 0) := (others => '0');   -- incremented program counter
        MRDATA  : out std_logic_vector(15 downto 0) := (others => '0');   -- memory read data
            -- Control signals from Control Logic to other modules
        WERF    : out std_logic := '0';                                   -- Write Enable Register File - '1' to write to register file
        RBSEL   : out std_logic := '0';                                   -- Register Channel B Select - '0' for Rb, '1' for Rc
        WDSEL   : out std_logic_vector(1 downto 0) := (others => '0');    -- Write Data Select - "00" for ALU, "01" for PC+2, "10" for Memory Read Data
            -- Inputs to Control Logic from other modules
        ALU_OUT : in std_logic_vector(15 downto 0) := (others => '0');    -- ALU output
        MWDATA  : in std_logic_vector(15 downto 0) := (others => '0');    -- memory write data - Register Channel B output
        Z       : in std_logic := '0';                                     -- Zero flag from RegFile Channel A
		  
		  PHASE   : out std_logic_vector(1 downto 0) := (others => '0')
    );
end CTRL_WSH_M;

architecture rtl of CTRL_WSH_M is

    -- internal signals
    constant RESET_VECTOR : std_logic_vector(15 downto 0) := x"F000";   -- reset vector address

    -- internal registers to hold outputs
    signal INST_reg    : std_logic_vector(15 downto 0) := (others => '0');   -- instruction fetched from memory
    signal CONST_reg   : std_logic_vector(15 downto 0) := (others => '0');   -- constant fetched from memory
    signal PC_reg      : std_logic_vector(15 downto 0) := (others => '0');   -- program counter
    signal PC_INC_calc : std_logic_vector(15 downto 0) := (others => '0');   -- incremented program counter
    signal MRDATA_reg  : std_logic_vector(15 downto 0) := (others => '0');   -- memory read data
	 signal RBSEL_sig   : std_logic := '0';
	 signal MWDATA_sig  : std_logic_vector(15 downto 0) := (others => '0');   -- MWData

    -- internal signals for control logic
    signal MASEL  : std_logic := '0';                                   -- Address select - '0' for PC, '1' for ALU Output
    signal MWR    : std_logic := '0';                                   -- Memory Write - '1' for write, '0' for read
    signal PC_JT  : std_logic := '0';                                   -- Program Counter Jump - '1' to jump to address in ALU output, otherwise increment by 2

    -- state machine
    type fsm_main is (ST_FETCH_I, ST_FETCH_C, ST_EXECUTE);
    signal st_main : fsm_main := ST_FETCH_I;

begin
    -- combinational logic for internal control signals
    MASEL <= (INST_reg(9) AND INST_reg(7)) when st_main = ST_EXECUTE else '0';     -- high if execution requires memory read or write (LD, LDR or ST commands)
    MWR   <= (INST_reg(9) AND RBSEL_sig) when st_main = ST_EXECUTE else '0';       -- Set write signal only during execute phase if instruction is a store (ST command)
    PC_JT <= '1' when (INST_reg(9) = '1') AND                                   -- Program Counter Jump - jump to ALU output address for Branch Instructions
                       ( (INST_reg(8 downto 6) = "000") OR                          -- unconditional JMP
                         (INST_reg(8 downto 6) = "100" AND Z = '1') OR              -- BEQ command and Zero flag = 1
                         (INST_reg(8 downto 6) = "101" AND Z = '0') )               -- BNE command and Zero flag = 0
             else '0';

    MWDATA_sig <= MWDATA;                                                   -- wire memory write data directly from Register File Channel B output

    -- Spikeputor control outputs, including control signals for ALU and Register File
    PC_INC_calc <= std_logic_vector(unsigned(PC_reg) + 2);                  -- PC incremented by 2 for next instruction

    PC          <= PC_reg;                                                  -- program counter
    PC_INC      <= PC_INC_calc;                                             -- incremented program counter
    INST        <= INST_reg;                                                -- instruction fetched from memory
    CONST       <= CONST_reg;                                               -- constant fetched from memory
    MRDATA      <= MRDATA_reg;                                              -- memory read data
	 RBSEL       <= RBSEL_sig;
	 
	 PHASE       <= "00" when st_main = ST_FETCH_I else
	                "01" when st_main = ST_FETCH_C else
						 "10" when st_main = ST_EXECUTE else
						 "11";

    RBSEL_sig <= '1' when INST_reg(8 downto 6) = "011" else '0';                    -- select register Channel B output (Rb or Rc) - (Only Rc for ST instruction)
    WERF  <= NOT RBSEL_sig when st_main = ST_EXECUTE else '0';                 -- Write Enable for Register File - on during execute phase if instruction is not a store (ST command)
    WDSEL <= "10" when (INST_reg(9) = '1' AND INST_reg(7 downto 6) = "10")          -- Register Write Data Select - use Memory Read Data as Register Input for LD and LDR instructions
             else "00" when (INST_reg(9) = '1' AND INST_reg(7) = '0')               -- use PC+2 as Register Input for Branch Instructions
             else "01";                                                     -- use ALU Output as Register Input for all other instructions

    process(clk)
    begin
        if rising_edge(clk) then
            if RST_I = '1' then
                -- reset state
                st_main <= ST_FETCH_I;          -- start by fetching instruction
                PC_reg <= RESET_VECTOR;         -- set PC to reset vector
                WBS_CYC_O <= '0';               -- clear wishbone handshake signals
                WBS_STB_O <= '0';
                WBS_WE_O <= '0';
                WBS_ADDR_O <= RESET_VECTOR;     -- set address to reset vector
                WBS_DATA_O <= (others => '0');  -- clear data output
            else
                case st_main is
                    when ST_FETCH_I =>
                        -- fetch instruction from memory at address PC
                        WBS_ADDR_O <= PC_reg;           -- set address to PC
                        WBS_CYC_O <= '1';               -- initiate wishbone cycle
                        WBS_STB_O <= '1';               -- strobe to indicate valid address
                        WBS_WE_O <= '0';                -- read operation
                        if WBS_ACK_I = '1' then     -- wait for acknowledge from memory
                            INST_reg <= WBS_DATA_I;     -- latch instruction
                            WBS_STB_O <= '0';           -- deassert strobe - end read phase
                            if WBS_DATA_I(10) = '1' then    -- instruction bit 10 indicates if there is a constant to fetch
                                st_main <= ST_FETCH_C;          -- instruction has constant
                                PC_reg <= PC_INC_calc;          -- increment PC for constant
                            else
										  PC_reg <= PC_reg;
                                st_main <= ST_EXECUTE;          -- no constant, execute directly (keeping PC unchanged)
                            end if;
                        else                        -- stall until ack received
                            st_main <= ST_FETCH_I;
                        end if;

                    when ST_FETCH_C =>
                        -- fetch constant from memory at now incremented PC
                        WBS_ADDR_O <= PC_reg;           -- set address to PC
                        WBS_STB_O <= '1';               -- strobe to indicate valid address
                        WBS_WE_O <= '0';                -- read operation
                        if WBS_ACK_I = '1' then
                            CONST_reg <= WBS_DATA_I;    -- latch constant
                            WBS_STB_O <= '0';           -- deassert strobe - end read phase
                            st_main <= ST_EXECUTE;      -- proceed to execute instruction
                        else
                            st_main <= ST_FETCH_C;  -- stall until ack received
                        end if;

                    when ST_EXECUTE =>
                        -- execute instruction
                        if MASEL = '1' then -- get address from ALU output and read or write based on MWR signal
									 if WBS_ACK_I = '0' then
										WBS_ADDR_O <= ALU_OUT;          -- address is ALU output
										WBS_STB_O <= '1';               -- strobe to indicate valid address
										if MWR = '1' then               -- write to memory when MWR is high, otherwise read
											WBS_WE_O <= '1';
											WBS_DATA_O <= MWDATA_sig;
										else
											WBS_WE_O <= '0';
										end if;
										st_main <= ST_EXECUTE;          -- stay in execute state until ack received
									 end if;
									 
									 if WBS_ACK_I = '1' then         -- wait for acknowledge from memory and handle read or write completion
										if MWR = '0' then
											MRDATA_reg <= WBS_DATA_I;   -- latch memory read data for read operation
										else 
											WBS_WE_O <= '0';            -- deassert write enable after write operation
										end if;
										WBS_STB_O <= '0';           -- deassert strobe
										WBS_CYC_O <= '0';           -- end wishbone cycle
										st_main <= ST_FETCH_I;      -- go back to fetch next instruction
									else
										st_main <= ST_EXECUTE;  -- stall until ack received
									end if;
									 
                        else                            -- other instructions - do not need to read or write to memory
                            if PC_JT = '0' then
                                PC_reg <= PC_INC_calc;      -- increment PC by 2 for next instruction
                            else
                                PC_reg <= ALU_OUT;          -- set PC to address in ALU output to jump
                            end if;
                            WBS_CYC_O <= '0';           -- end wishbone cycle
                            st_main <= ST_FETCH_I;      -- go back to fetch next instruction, no wishbone cycle needed
                        end if;
                end case;
            end if;
        end if;
    end process;

end rtl;