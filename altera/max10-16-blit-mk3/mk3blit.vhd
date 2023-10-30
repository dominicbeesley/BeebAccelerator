-- MIT License
-- -----------------------------------------------------------------------------
-- Copyright (c) 2022 Dominic Beesley https://github.com/dominicbeesley
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
-- -----------------------------------------------------------------------------


-- Company:          Dossytronics
-- Engineer:         Dominic Beesley
-- 
-- Create Date:      1/7/2021
-- Design Name: 
-- Module Name:      Mk.3 Blitter top-level design
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description:      
-- Dependencies: 
--
-- Revision: 
-- Additional Comments: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--use work.mk1board_types.all;

library work;

entity mk3blit is
   generic (
      SIM                           : boolean := false;                    -- skip some stuff, i.e. slow sdram start up
      CLOCKSPEED                    : natural := 100;                      -- fast clock speed in mhz          
      G_JIM_DEVNO                   : std_logic_vector(7 downto 0) := x"D1";

      N_PHI_DLY                     : natural := 14;
      N_PHI_TAP                     : natural := 1;
      FORCE_SLOW                    : natural := 18
   );
   port(
      -- crystal osc 48Mhz - on WS board
      CLK_48M_i                     : in     std_logic;

      -- 2M RAM/256K ROM bus (45)
      MEM_A_o                       : out    std_logic_vector(20 downto 0);
      MEM_D_io                      : inout  std_logic_vector(7 downto 0); -- 17 bit RAMs used but D[7..0] is multiplexed with D[15..8]
      MEM_nOE_o                     : out    std_logic;
      MEM_nWE_o                     : out    std_logic;                    -- add external pull-up

      MEM_FL_nCE_o                  : out    std_logic;           
      MEM_RAM_nCE_o                 : out    std_logic_vector(3 downto 0);
      
      -- 1 bit DAC sound out stereo, aux connectors mirror main (2)
      SND_L_o                       : out    std_logic;
      SND_R_o                       : out    std_logic;

      -- hdmi (11)

      HDMI_SCL_io                   : inout  std_logic;
      HDMI_SDA_io                   : inout  std_logic;
      HDMI_HPD_i                    : in     std_logic;
      HDMI_CK_o                     : out    std_logic;
      HDMI_D0_o                     : out    std_logic;
      HDMI_D1_o                     : out    std_logic;
      HDMI_D2_o                     : out    std_logic;
      
      -- sdcard (5)
      SD_CS_o                       : out    std_logic;
      SD_CLK_o                      : out    std_logic;
      SD_MOSI_o                     : out    std_logic;
      SD_MISO_i                     : in     std_logic;
      SD_DET_i                      : in     std_logic;

      -- SYS bus connects to SYStem CPU socket (38)

      SUP_nRESET_i                  : in     std_logic;                       -- SYStem reset after supervisor

      SYS_A_o                       : out    std_logic_vector(15 downto 0);
      SYS_D_io                      : inout  std_logic_vector(7 downto 0);
      SYS_BUF_D_DIR_o               : out    std_logic;
      SYS_BUF_D_nOE_o               : out    std_logic;
      
      SYS_SYNC_o                    : out    std_logic;
      SYS_PHI1_o                    : out    std_logic;
      SYS_PHI2_o                    : out    std_logic;
      SYS_RnW_o                     : out    std_logic;


      -- test these as outputs!!!
      SYS_RDY_i                     : in     std_logic; -- Master only?
      SYS_nNMI_i                    : in     std_logic;
      SYS_nIRQ_i                    : in     std_logic;
      SYS_PHI0_i                    : in     std_logic;
      SYS_nDBE_i                    : in     std_logic;


      -- SYS configuration and auxiliary (18)
      SYS_AUX_io                    : inout  std_logic_vector(6 downto 0);
      SYS_AUX_o                     : out    std_logic_vector(3 downto 0);

      -- rpi interface (26)
      --rpi_gpio                       : inout  std_logic_vector(27 downto 2);


      -- i2c EEPROM (2)
      I2C_SCL_io                    : inout  std_logic;
      I2C_SDA_io                    : inout  std_logic;


      -- cpu / expansion sockets (56)

      exp_PORTA_io                  : inout  std_logic_vector(7 downto 0);
      exp_PORTA_nOE_o               : out    std_logic;
      exp_PORTA_DIR_o               : out    std_logic;

      exp_PORTB_o                   : out    std_logic_vector(7 downto 0);

      exp_PORTC_io                  : inout  std_logic_vector(11 downto 0);
      exp_PORTD_io                  : inout  std_logic_vector(11 downto 0);

      exp_PORTEFG_io                : inout  std_logic_vector(11 downto 0);
      exp_PORTE_nOE                 : out    std_logic;
      exp_PORTF_nOE                 : out    std_logic;
      exp_PORTG_nOE                 : out    std_logic;


      -- LEDs 
      LED_o                         : out    std_logic_vector(3 downto 0);

      BTNUSER_i                     : in     std_logic_vector(1 downto 0)

   );
end mk3blit;

architecture rtl of mk3blit is

component pllmain
   PORT
   (
      areset      : IN STD_LOGIC  := '0';
      inclk0      : IN STD_LOGIC  := '0';
      c0    : OUT STD_LOGIC ;
      locked      : OUT STD_LOGIC 
   );
end component;

component beeb_accelerator_int
   generic (
      MOS_INTERNAL   : boolean   := true;
      IS_INTERNAL_LOOKAHEAD : boolean := true;
      NPHI0_REGS     : natural := 6;
      PHIOUT_TAP     : natural := 1;
      FORCE_SLOW     : natural := 15
   );
   port (

            -- pll clock
      cpu_clk        : in        std_logic;

            -- 6502 Signals
      PhiIn          : in        std_logic;
      Phi1Out        : out       std_logic;
      Phi2Out        : out       std_logic;
      IRQ_n          : in        std_logic;
      NMI_n          : in        std_logic;
      Sync           : out       std_logic;
      Addr           : out       std_logic_vector(15 downto 0);
      R_W_n          : out       std_logic;
      Data_I         : in        std_logic_vector(7 downto 0);
      Data_O         : out       std_logic_vector(7 downto 0);
      SO_n           : in        std_logic;
      Res_n          : in        std_logic;
      Rdy            : in        std_logic;

            -- 65C02 Signals
      BE             : in        std_logic;
      ML_n           : out       std_logic;
      VP_n           : out       std_logic;

            -- fast memory
      ram_scrub_A    : out       std_logic_vector(15 downto 0);
      ram_scrub_D_rd : in        std_logic_vector(7 downto 0);

      ram_cpu_A      : out       std_logic_vector(15 downto 0);
      ram_cpu_we     : out       std_logic;
      ram_cpu_D_wr   : out       std_logic_vector(7 downto 0);
      ram_cpu_D_rd   : in        std_logic_vector(7 downto 0)
   );
end component;

component ram_fast_lo
   PORT
   (
      address_a      : IN STD_LOGIC_VECTOR (14 DOWNTO 0);
      address_b      : IN STD_LOGIC_VECTOR (14 DOWNTO 0);
      clock    : IN STD_LOGIC  := '1';
      data_a      : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
      data_b      : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
      wren_a      : IN STD_LOGIC  := '0';
      wren_b      : IN STD_LOGIC  := '0';
      q_a      : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
      q_b      : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
   );
end component;

component ram_fast_lo_tmp
   PORT
   (
      clock    : IN STD_LOGIC  := '1';
      address      : IN STD_LOGIC_VECTOR (14 DOWNTO 0);
      data      : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
      wren      : IN STD_LOGIC  := '0';
      q      : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
   );
end component;

component ram_fast_hi
   PORT
   (
      address     : IN STD_LOGIC_VECTOR (13 DOWNTO 0);
      clock    : IN STD_LOGIC  := '1';
      data     : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
      wren     : IN STD_LOGIC ;
      q     : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
   );
end component;


   signal i_cpu_clk           : std_logic;
   signal i_pll_locked        : std_logic;
   signal i_cpu_nres          : std_logic;

   signal i_ram_scrub_A       : std_logic_vector(15 downto 0);
   signal i_ram_scrub_D_rd    : std_logic_vector(7 downto 0);

   signal i_ram_cpu_A         : std_logic_vector(15 downto 0);
   signal i_ram_cpu_we        : std_logic;
   signal i_ram_cpu_D_wr      : std_logic_vector(7 downto 0);
   signal i_ram_cpu_D_rd      : std_logic_vector(7 downto 0);

   type t_ram is array (natural range <>) of std_logic_vector(7 downto 0);

   signal r_ram_vid           : t_ram(0 to 32767);
   signal r_ram_swram         : t_ram(0 to 16383);

   signal i_RnW               : std_logic;

   signal i_SYS_PHI2          : std_logic;
   signal i_SYS_PHI2_dly      : std_logic;

   signal i_SYS_D_o           : std_logic_vector(7 downto 0);

   signal r_hilo_sel          : std_logic;
   signal i_ram_D_hi          : std_logic_vector(7 downto 0);
   signal i_ram_D_lo          : std_logic_vector(7 downto 0);
begin

pll:pllmain 
port map (
   areset => not SUP_nRESET_i,
   inclk0 => CLK_48M_i,
   c0     => i_cpu_clk,
   locked => i_pll_locked
);

i_cpu_nres <=  '0' when i_pll_locked = '0' or SUP_nRESET_i = '0' else 
               '1';

accel:beeb_accelerator_int
generic map (
   MOS_INTERNAL   => false,
   NPHI0_REGS     => N_PHI_DLY,
   PHIOUT_TAP     => N_PHI_TAP,
   FORCE_SLOW     => FORCE_SLOW
   )
port map (
   cpu_clk        => i_cpu_clk,
   PhiIn          => SYS_PHI0_i,
   Phi1Out        => SYS_PHI1_o,
   Phi2Out        => i_SYS_PHI2,
   IRQ_n          => SYS_nIRQ_i,
   NMI_n          => SYS_nNMI_i,
   Sync           => SYS_SYNC_o,
   Addr           => SYS_A_o,
   R_W_n          => i_RnW,
   Data_I         => SYS_D_io,
   Data_O         => i_SYS_D_o,
   SO_n           => '1',
   Res_n          => i_cpu_nres,
   Rdy            => SYS_RDY_i,

   BE             => '1',
   ML_n           => open,
   VP_n           => open,

   ram_scrub_A    => i_ram_scrub_A,
   ram_scrub_D_rd => i_ram_scrub_D_rd,

   ram_cpu_A      => i_ram_cpu_A,
   ram_cpu_we     => i_ram_cpu_we,
   ram_cpu_D_wr   => i_ram_cpu_D_wr,
   ram_cpu_D_rd   => i_ram_cpu_D_rd

   );

SYS_D_io <= i_SYS_D_o when i_RnW = '0' and (i_SYS_PHI2_dly = '1' or SYS_PHI0_i = '1')  else
            (others => 'Z');

--ram_lo:ram_fast_lo
--   PORT MAP
--   (
--      clock       => i_cpu_clk,
----      address_a   => i_ram_scrub_A(14 downto 0),
--      address_a   => (others => '0'),
--      q_a         => i_ram_scrub_D_rd,
--      wren_a      => '0',
--      data_a      => (others => '1'),
--
--      address_b   => i_ram_cpu_A(14 downto 0),
--      q_b         => i_ram_D_lo,
--      wren_b      => i_ram_cpu_we and not(i_ram_cpu_A(15)),
--      data_b      => i_ram_cpu_D_wr
--   );

ram_lo:ram_fast_lo_tmp
   PORT MAP
   (
      clock       => i_cpu_clk,
      address   => i_ram_cpu_A(14 downto 0),
      q         => i_ram_D_lo,
      wren      => i_ram_cpu_we and not(i_ram_cpu_A(15)),
      data      => i_ram_cpu_D_wr
   );

ram_hi:ram_fast_hi
   PORT MAP
   (
      clock       => i_cpu_clk,
      address     => i_ram_cpu_A(13 downto 0),
      q           => i_ram_D_hi,
      wren        => i_ram_cpu_we and i_ram_cpu_A(15),
      data        => i_ram_cpu_D_wr
   );

   p_ramlohi:process(i_cpu_clk)
   begin
      if rising_edge(i_cpu_clk) then
         r_hilo_sel <= i_ram_cpu_A(15);
      end if;
   end process;

   i_ram_cpu_D_rd <= i_ram_D_lo when r_hilo_sel = '0' else
                     i_ram_D_hi;

SYS_RnW_o         <= i_RnW;
SYS_BUF_D_DIR_o   <= i_RnW;
SYS_BUF_D_nOE_o   <= not (i_SYS_PHI2_dly or SYS_PHI0_i);
SYS_PHI2_o        <= i_SYS_PHI2;

p_phi2_dly:process(i_cpu_clk)
begin
   if rising_edge(i_cpu_clk) then
      i_SYS_PHI2_dly <= i_SYS_PHI2;
   end if;

end process;


-- unused stuff

      -- 2M RAM/256K ROM bus (45)
      MEM_A_o                       <= (others => '0');
      MEM_D_io                      <= (others => 'Z');
      MEM_nOE_o                     <= '1';
      MEM_nWE_o                     <= '1';
      MEM_FL_nCE_o                  <= '1';
      MEM_RAM_nCE_o                 <= (others => '1');
      
      -- 1 bit DAC sound out stereo, aux connectors mirror main (2)
      SND_L_o                       <= '1';
      SND_R_o                       <= '1';

      -- hdmi (11)

      HDMI_SCL_io                   <= '1';
      HDMI_SDA_io                   <= '1';
--      HDMI_CK_o                     <= '1';
--      HDMI_D0_o                     <= '1';
--      HDMI_D1_o                     <= '1';
--      HDMI_D2_o                     <= '1';
      
      -- sdcard (5)
      SD_CS_o                       <= 'Z';
      SD_CLK_o                      <= 'Z';
      SD_MOSI_o                     <= 'Z';


      -- SYS configuration and auxiliary (18)
      SYS_AUX_io                    <= (others => '1');
      SYS_AUX_o                     <= (others => '1');



      -- i2c EEPROM (2)
      I2C_SCL_io                    <= '1';
      I2C_SDA_io                    <= '1';


      -- cpu / expansion sockets (56)

      exp_PORTA_io                  <= (others => 'Z');
      exp_PORTA_nOE_o               <= '1';
      exp_PORTA_DIR_o               <= '1';

      exp_PORTB_o                   <= (others => '1');

      exp_PORTC_io                  <= (others => '1');
      exp_PORTD_io                  <= (others => '1');

      exp_PORTEFG_io                <= (others => 'Z');
      exp_PORTE_nOE                 <= '1';
      exp_PORTF_nOE                 <= '1';
      exp_PORTG_nOE                 <= '1';


      -- LEDs 
      LED_o                         <= (others => '1');


end rtl;
