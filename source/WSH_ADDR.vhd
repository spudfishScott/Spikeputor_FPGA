-- This is a Wishbone address comparitor to route bus inputs to a variety of provider models
-- Inputs are:
--  TGA_I  - from the master arbiter (either extended address via SEGMENT register or 0)
--  ADDR_I - from the master arbiter
--  WE_I   - from the master arbiter
--  STB_I  - from the master arbiter
--  TGD_I  - route the data bus to update the SEGMENT register
        -- This is no longer used
        --  BANK_SEL register: - works with both ADDR_I and possible TGA_I to select RAM/ROM or SDRAM/ROM providers
        --      Bank Select = "X00": All access to RAM, ROM not available, 0xE000-0xFFFF not available
        --                  = "X01": (Default) 0x0000-0x7FFF - RAM read, 0x8000-0xFFFF ROM read, always write to RAM (except 0xE000-0xFFFF, for which there is no RAM)
        --                  = "X10": 0x0000-0x7FFF - ROM read, 0x8000-0xFBFF RAM read, 0xE000-0xFFFF reads as 0, always write to RAM (except for 0xE000-0xFFFF)
        --                  = "X11": 0x0000-0xFFFF - ROM read, always write to RAM (except for 0xE000-0xFFFF)
        --      If TGA_I is not 0, RAM?ROM is determined by msb of TGA_I (1 = ROM, 0 = RAM)
--  Px_DATA_O - data output from each provider
--
-- In addition to standard RAM (P0), SDRAM (P10), and ROM (P1), the following providers are accessed through specific addresses, which override the above:
--  GPO (P2)        read/write location 0x7FFC
--  GPI (P3)        read only location 0x7FFE - writing goes nowhere
--  SOUND (P4)      read/write location 0x7FAC
--  VIDEO (P5)      read/write to video coprocessor - locations TBD
--  SERIAL (P6)     serial in/serial out - locations TBD
--  STORAGE (P7)    read/write to SD card filesystem - locations TBD (might be coupled to DMA)
--  KEYBOARD (P8)   read keyboard input buffer (maybe mouse one day as well)
--  SEGMENT (P9)    read/write to segment register, which might be used to expand the total amount of RAM available - locations TBD

-- Outputs are:
--  Individual provider select signals, which go to provider STB_I inputs
--  DATA_O - wired to all of the master DATA_I inputs

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Types.all;

entity WSH_ADDR is
    port (
        -- Wishbone Control Signals
        ADDR_I      : in std_logic_vector(23 downto 0);     -- standard address bus - bottom 16 bits is on Segment 0, msb = ROM/RAM for extended memory, bits 22->16 = segment number
        WE_I        : in std_logic;                         -- write enable flag
        STB_I       : in std_logic;                         -- wishbone strobe signal
        TGD_I       : in std_logic;                         -- TGD_I and WE_I are high, route to P9, SEGMENT write

        -- Data out from providers
        P0_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from RAM (P0)
        P1_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from ROM (P1)
        P2_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from GPO (P2)
        P3_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from GPI (P3)
        P4_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from SOUND (P4)
        P5_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from VIDEO (P5)
        P6_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from SERIAL (P6)
        P7_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from STORAGE (P7)
        P8_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from KEYBOARD (P8)
        P9_DATA_O   : in std_logic_vector(15 downto 0);     -- Data Output from SEGMENT (P9)
        P10_DATA_O  : in std_logic_vector(15 downto 0);     -- Data Output from SDRAM (P10)

        -- Output signals
        DATA_O      : out std_logic_vector(15 downto 0);    -- Wishbone data bus output
        STB_SEL     : out std_logic_vector(10 downto 0)     -- One hot strobe selector for provider STB_I signals
    );
end WSH_ADDR;

architecture RTL of WSH_ADDR is

    constant KEYBOARD_ADDR  : std_logic_vector(15 downto 0) := x"FF00"; -- keyboard address
    constant GPO_ADDR       : std_logic_vector(15 downto 0) := x"FF01"; -- GPO address
    constant GPI_ADDR       : std_logic_vector(15 downto 0) := x"FF02"; -- GPI address

    signal p_sel   : integer range 0 to 10 := 0;                        -- provider selector index
    signal ram_e   : std_logic := '0';                                  -- RAM selected
    signal spec    : std_logic := '0';                                  -- special location (p2-p9)
    signal seg     : std_logic_vector(6 downto 0) := (others => '0');   -- segment portion of the full address
    signal p_addr  : std_logic_vector(15 downto 0) := (others => '0');  -- primary address portion of the full address
    signal p_oh    : std_logic_vector(10 downto 0) := (others => '0');  -- provider one-hot vector

begin
    seg    <= ADDR_I(22 downto 16);   -- extract segment identifier from full address
    p_addr <= ADDR_I(15 downto 0);    -- extract primary address from full address

    spec <= '1' when seg = "0000000" AND                                                  -- check for a special address (more to follow)
                            (p_addr = KEYBOARD_ADDR OR p_addr = GPO_ADDR OR p_addr = GPI_ADDR)
                else '0';
    ram_e <= '1' when (seg  = "0000000" AND ADDR_I(15 downto 13) /= "111") OR             -- no segment and in range 0x0000-0xDFFF
                      (seg /= "0000000" AND ADDR_I(23) = '0')                             -- segment and not a ROM address
                 else '0';

    -- assign p_sel based on addressing logic described above
    p_sel <=    9 when TGD_I = '1' AND WE_I = '1'                                         -- write to SEGMENT when TDG and WE are set, pre-empts all other
        else    0 when seg  = "0000000" AND spec = '0' AND (ram_e = '1' OR WE_I = '1')    -- standard RAM when segment is 0 and not a special location and either a RAM location or writing
        else    1 when spec = '0' AND ram_e = '0'                                         -- ROM if not a special location and not a RAM location (including 0xE000-0xFFFF)
        else    2 when seg  = "0000000" AND p_addr = GPO_ADDR                             -- read/write GPO
        else    3 when seg  = "0000000" AND p_addr = GPI_ADDR                             -- read only GPI
        -- to do the rest 5 through 7
        else    8 when seg  = "0000000" AND p_addr = KEYBOARD_ADDR                            -- read only KEYBOARD
        else   10 when ram_e = '1'                                                        -- SDRAM when ram_e is '1' and we get here (segment /= 0 and not ROM or special)
        else    8;                                                                        -- default to read KEYBOARD

    -- output the correct data based on p_sel
    with (p_sel) select
        DATA_O <=
            P0_DATA_O  when 0,      -- RAM
            P1_DATA_O  when 1,      -- ROM
            P2_DATA_O  when 2,      -- GPO (including VFD text output?)
            P3_DATA_O  when 3,      -- GPI
            P4_DATA_O  when 4,      -- SOUND
            P5_DATA_O  when 5,      -- VIDEO
            P6_DATA_O  when 6,      -- SERIAL
            P7_DATA_O  when 7,      -- DISK STORAGE
            P8_DATA_O  when 8,      -- KEYBOARD
            P9_DATA_O  when 9,      -- SEGMENT
            P10_DATA_O when 10,     -- SDRAM
            (others => '0') when others;

    -- Generate one-hot strobe signals for each provider based on p_sel
    with (p_sel) select
        p_oh <=
            "00000000001" when 0,
            "00000000010" when 1,
            "00000000100" when 2,
            "00000001000" when 3,
            "00000010000" when 4,
            "00000100000" when 5,
            "00001000000" when 6,
            "00010000000" when 7,
            "00100000000" when 8,
            "01000000000" when 9,
            "10000000000" when 10,
            "00000000000" when others;

    -- ouput STB_SEL based on the one-hot result and STB_I
    STB_SEL <= p_oh when STB_I = '1' else "00000000000";

end RTL;
