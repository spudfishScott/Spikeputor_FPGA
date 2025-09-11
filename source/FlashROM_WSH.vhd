-- Flash ROM Wishbone Interface Provider
-- 64 K of ROM, 16 bit wide data bus, 16 bit wide address bus, customize to point to a different sector of 64K ROM if needed
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity FlashROM_WSH is
    generic (
        SECTOR_ADDR  : std_logic_vector(5 downto 0) := "000010" -- the 64KB sector is defined in ADDR[20:15] - default is sector 8 (1st 64KB sector)
    );

    port (
        -- SYSCON inputs
        CLK         : in std_logic;
        RST_I       : in std_logic;

        -- Wishbone inputs
        WBS_CYC_I   : in std_logic;
        WBS_STB_I   : in std_logic;
        WBS_ADDR_I  : in std_logic_vector(15 downto 0); -- lsb is ignored, but it is still part of the address bus
        WBS_DATA_O  : out std_logic_vector(15 downto 0);
        WBS_ACK_O   : out std_logic;

         -- Flash chip signals, passed through to Flash ROM controller
        WP_n        : out std_logic; -- write protection
        BYTE_n      : out std_logic; -- byte mode/~word mode
        RST_n       : out std_logic; -- chip reset
        CE_n        : out std_logic; -- chip enable
        OE_n        : out std_logic; -- output enable
        WE_n        : out std_logic; -- write enable
        BY_n        :  in std_logic; -- chip ready/~busy
        A           : out std_logic_vector(21 downto 0); -- chip Address - msb is ignored in word mode
        Q           :  in std_logic_vector(15 downto 0)  -- chip data output (output only for ROM)
    );
end FlashROM_WSH;

architecture rtl of FlashROM_WSH is

    -- internal signals
    signal flash_addr   : std_logic_vector(21 downto 0) := (others => '0');
    signal flash_data   : std_logic_vector(15 downto 0) := (others => '0');
    signal flash_read   : std_logic := '0';
    signal flash_ready  : std_logic := '1';

    signal wbs_ack      : std_logic := '0';
    signal wbs_data     : std_logic_vector(15 downto 0) := (others => '0');

        -- state machine
    type fsm_main is (ST_IDLE, ST_READ, ST_CLEAR);
    signal st_main : fsm_main := ST_IDLE;

begin
    -- FlashROM controller instance
    flash_ctrl : entity work.FLASH_ROM
        generic map (
            MAIN_CLK_NS => 20          -- main clock period in ns - 20 ns for 50 MHz
        )
        
        port map (
            -- SYSCON
            CLK_IN      => CLK,
            RST_IN      => RST_I,
            -- Flash Controller Interface
            ADDR_IN     => flash_addr,
            RD_IN       => flash_read,
            DATA_OUT    => flash_data,
            READY_OUT   => flash_ready,

            -- Flash chip interface
            WP_n        => WP_n,
            BYTE_n      => BYTE_n,
            RST_n       => RST_n,
            CE_n        => CE_n,
            OE_n        => OE_n,
            WE_n        => WE_n,
            BY_n        => BY_n,
            A           => A,
            Q           => Q
        );

    -- output to wishbone interface
    WBS_ACK_O   <= wbs_ack AND WBS_STB_I AND WBS_CYC_I;
    WBS_DATA_O  <= wbs_data;

    -- Wishbone interface process
    process(CLK)
    begin
        if (rising_edge(CLK)) then
            if (RST_I = '1') then   -- synchronous RESET - clear state machine and ACK and Data
                wbs_ack  <= '0';
                wbs_data <= (others => '0');
                flash_read <= '0';
                flash_addr <= (others => '0');
                st_main  <= ST_IDLE;
            else
                case (st_main) is
                    when ST_IDLE =>
                        if (WBS_CYC_I = '1' and WBS_STB_I = '1') then   -- a valid Wishbone cycle and strobe
                            flash_addr <= "0" & SECTOR_ADDR & WBS_ADDR_I(15 downto 1);     -- form full 22 bit word address from sector and requested address (msb is ignored)
                            flash_read <= '1';                          -- pulse read after one clock
                            st_main    <= ST_READ;                      -- go to read state
                        else
                            st_main <= ST_IDLE; -- remain in IDLE - keep idling until WBS_CYC_I and WBS_STB_I are asserted
                        end if;

                    when ST_READ =>
                        flash_read <= '0';          -- pulse read after one clock, wait until word is ready
                        if (flash_ready = '1' and flash_read = '0') then -- after pulsing read, wait until flash indicates data is ready (will be multiple clocks)
                            wbs_data <= flash_data;     -- store word in output register
                            wbs_ack  <= '1';            -- signal that data is ready
                            st_main  <= ST_CLEAR;       -- done, clear internal ACK flag
                        else
                            if (WBS_CYC_I = '0' or WBS_STB_I = '0') then -- if master deasserts CYC or STB, abort read
                                wbs_ack <= '0';         -- clear internal ACK flag
                                st_main <= ST_IDLE;     -- go back to IDLE
                            else
                                st_main <= ST_READ;     -- stay here until flash data is ready or early termination
                            end if;
                        end if;

                    when ST_CLEAR =>
                        if (WBS_CYC_I = '0' or WBS_STB_I = '0') then -- wait until master deasserts CYC or STB
                            wbs_ack <= '0';             -- clear internal ACK flag
                            st_main <= ST_IDLE;         -- go back to IDLE
                        else
                            st_main <= ST_CLEAR; -- stay here until master deasserts CYC or STB
                        end if;

                    when others =>
                        wbs_ack <= '0';
                        st_main <= ST_IDLE; -- should never happen, go to IDLE
                end case;

                if (WBS_CYC_I = '0') then   -- Break cycle if master deasserts CYC
                    wbs_ack <= '0';
                    st_main <= ST_IDLE;
                end if;

            end if;
        end if;
    end process;
end rtl;