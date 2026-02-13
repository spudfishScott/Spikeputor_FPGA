library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_arith.all;
  use ieee.std_logic_unsigned.all;

entity DE0_DMATest is
    port (
        -- Clock Input
        CLOCK_50 : in std_logic;
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
        -- UART
        UART_RXD : in std_logic;
        UART_TXD : out std_logic
    );
end DE0_DMATest;

architecture Structural of DE0_DMATest is
    -- Signal Declarations
    signal cyc : std_logic;
    signal stb : std_logic;
    signal ack : std_logic;

    signal addr : std_logic_vector(23 downto 0);
    signal data_o : std_logic_vector(15 downto 0);
    signal data_i : std_logic_vector(15 downto 0);
    signal we : std_logic;

    signal rst : std_logic;

    begin
    -- display PC or PC_INC on 7-seg based on Button(2)
    disp_out <= addr;

    -- Control Logic Instance
    CTRL : entity work.DMA_WSH_M
        generic map (
            BAUD_RATE => 38400
        )
        port map (
            -- SYSCON inputs
            CLK         => CLOCK_50,
            RST_I       => NOT Button(0) OR rst,

            -- Wishbone signals for memory interface
            -- handshaking signals
            WBS_CYC_O   => cyc,
            WBS_STB_O   => stb,
            WBS_ACK_I   => ack,

            -- memory read/write signals
            WBS_ADDR_O  => addr,
            WBS_DATA_O  => data_o,
            WBS_DATA_I  => data_i,
            WBS_WE_O    => we,

            -- external signals
            RX_SERIAL   => UART_RXD,
            TX_SERIAL   => UART_TXD,
            RST_O       => rst
        );

    -- RAM Instance
    RAM : entity work.RAM_WSH_P port map (
        -- SYSCON inputs
        CLK         => system_clk,
        RST_I       => NOT Button(0) OR rst,

        -- Wishbone signals
        -- handshaking signals
        WBS_CYC_I   => cyc,
        WBS_STB_I   => stb,
        WBS_ACK_O   => ack,

        -- memory read/write signals
        WBS_ADDR_I  => addr,
        WBS_DATA_O  => data_i,
        WBS_DATA_I  => data_o,
        WBS_WE_I    => we
    );

      -- 7 Segment display decoder instance
    DISPLAY : entity work.WORDTO7SEGS port map (
        WORD  => disp_out,
        SEGS0 => HEX0_D,
        SEGS1 => HEX1_D,
        SEGS2 => HEX2_D,
        SEGS3 => HEX3_D
    );

    -- Set default output states

    -- 7-SEG Display
    HEX0_DP <= '1';
    HEX1_DP <= '1';
    HEX2_DP <= '1';
    HEX3_DP <= '1';

    -- LED
    LEDG(9) <= NOT Button(0) OR rst;
    LEDG(8 downto 0) <= (others => '0');

end Structural;
