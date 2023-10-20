// -----------------------------------------------------------------------------
// Copyright (c) 2020 David Banks
// -----------------------------------------------------------------------------
//   ____  ____
//  /   /\/   /
// /___/  \  /
// \   \   \/
//  \   \
//  /   /         Filename  : beeb_accelerator.v
// /___/   /\     Timestamp : 02/07/2020
// \   \  /  \
//  \___\/\___\
//
// Design Name: beeb_accelerator
// Device: XC6SLX9

// `define ELK
// `define MASTER

// For the master, uncomment this to enable an aggressive caching
// strategy of the main screen memory bank in shadow mode.

// `define AGGRESSIVE

`define IS_INTERNAL_LOOKAHEAD

module beeb_accelerator
(
 input         clock,

 // 6502 Signals
 input         PhiIn,
 output        Phi1Out,
 output        Phi2Out,
 input         IRQ_n,
 input         NMI_n,
 output        Sync,
 output [15:0] Addr,
 output [1:0]  R_W_n,
 inout [7:0]   Data,
 input         SO_n,
 input         Res_n,
 input         Rdy,

 // 65C02 Signals
 input         BE,
 output        ML_n,
 output        VP_n,

 // Level Shifter Controls
 output        OERW_n,
 output        OEAH_n,
 output        OEAL_n,
 output        OED_n,
 output        DIRD,

 // External trigger inputs
 input [1:0]   trig,

 // ID/mode inputs
 input         mode,
 input [3:0]   id,

 // Serial Console
 input         avr_RxD,
 output        avr_TxD,

 // Switches
 input         sw1,
 input         sw2,

 // LEDs
 output        led1,
 output        led2,
 output        led3

 );

   parameter ROOT = "../src/";

   parameter SIM = 0;

   // 50 MHz
   //localparam  NPHI0_REGS = 3;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 2;
   //localparam  DCM_DIV    = 2;

   // 64 MHz - meets timing
   //localparam  NPHI0_REGS = 4;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 32;
   //localparam  DCM_DIV    = 25;

   // 80MHz - meets timing
   //localparam  NPHI0_REGS = 5;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 8;
   //localparam  DCM_DIV    = 5;

   // 90MHz - meets timing
   //localparam  NPHI0_REGS = 6;
   //localparam  PHIOUT_TAP = 1;
   //localparam  DCM_MULT   = 9;
   //localparam  DCM_DIV    = 5;

   // 100 MHz (doesn't meet timing, but seems stable in practice)
   localparam  NPHI0_REGS = 6;
   localparam  PHIOUT_TAP = 1;
   localparam  DCM_MULT   = 4;
   localparam  DCM_DIV    = 2;

   wire        cpu_clk;
   wire        clk0;

   wire [0:15]          ram_cpu_A;
   wire [0:7]           ram_cpu_D_wr;
   reg [0:7]            ram_cpu_D_rd;
   wire [0:15]          ram_scrub_A;
   reg [0:7]            ram_scrub_D_rd;

   // PLL to generate CPU clock of 50 * DCM_MULT / DCM_DIV MHz
   DCM
     #(
       .CLKFX_MULTIPLY   (DCM_MULT),
       .CLKFX_DIVIDE     (DCM_DIV),
       .CLKIN_PERIOD     (20.000),
       .CLK_FEEDBACK     ("1X")
       )
   DCM1
     (
      .CLKIN            (clock),
      .CLKFB            (clk0),
      .RST              (1'b0),
      .DSSEN            (1'b0),
      .PSINCDEC         (1'b0),
      .PSEN             (1'b0),
      .PSCLK            (1'b0),
      .CLKFX            (cpu_clk),
      .CLKFX180         (),
      .CLKDV            (),
      .CLK2X            (),
      .CLK2X180         (),
      .CLK0             (clk0),
      .CLK90            (),
      .CLK180           (),
      .CLK270           (),
      .LOCKED           (),
      .PSDONE           (),
      .STATUS           ()
      );

beeb_accelerator_int
#(
   .NPHI0_REGS(NPHI0_REGS),
   .PHIOUT_TAP(PHIOUT_TAP),

`ifdef ELK
      .MODEL(1),
`elifdef `MASTER
      .MODEL(2),
`else
      .MODEL(0),
`endif
`ifdef IS_INTERNAL_LOOKAHEAD
      .IS_INTERNAL_LOOKAHEAD(1),
`else
      .IS_INTERNAL_LOOKAHEAD(0),
`endif
`ifdef AGGRESSIVE
      .AGGRESSIVE(1)
`else
      .AGGRESSIVE(0)
`endif
)
int
(

   .clock(clock),
   .cpu_clk(cpu_clk),        

 // 6502 Signals
   .PhiIn(PhiIn),
   .Phi1Out(Phi1Out),
   .Phi2Out(Phi2Out),
   .IRQ_n(IRQ_n),
   .NMI_n(NMI_n),
   .Sync(Sync),
   .Addr(Addr),
   .R_W_n(R_W_n),
   .Data(Data),
   .SO_n(SO_n),
   .Res_n(Res_n),
   .Rdy(Rdy),

 // 65C02 Signals
   .BE(BE),
   .ML_n(ML_n),
   .VP_n(VP_n),

 // fast memory
   .ram_scrub_A(ram_scrub_A),
   .ram_scrub_D_rd(ram_scrub_D_rd),

   .ram_cpu_A(ram_cpu_A),
   .ram_cpu_we(ram_cpu_we),
   .ram_cpu_D_wr(ram_cpu_D_wr),
   .ram_cpu_D_rd(ram_cpu_D_rd)

 );

   reg   [0:7] ram[0:65535];


   // Internal 64KB Block RAM - initialization data
   initial
`ifdef ELK
     $readmemh({ROOT , "ram_elk.mem"}, ram);
`elsif MASTER
     $readmemh({ROOT , "ram_master.mem"}, ram);
`else
     $readmemh({ROOT , "ram_os12.mem"}, ram);
`endif

   // Internal 64KB Block RAM
   always @(posedge cpu_clk) begin
        if (ram_cpu_we)
          ram[ram_cpu_A] <= ram_cpu_D_wr;
        ram_cpu_D_rd <= ram[ram_cpu_A];
   end

   always @(posedge cpu_clk) begin
      ram_scrub_D_rd <= ram[ram_scrub_A];
   end

   // Level Shifter Controls
   assign OERW_n  = 'b0;
   assign OEAH_n  = 'b0;
   assign OEAL_n  = 'b0;
   assign OED_n   = !(BE & PhiIn);
   assign DIRD    = R_W_n;

   // Misc
   assign led1    = !sw1;
   assign led2    = !sw2;
   assign led3    = &{mode, id, trig, SO_n, Rdy};
   assign avr_TxD = avr_RxD;

endmodule
