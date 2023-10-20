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


module beeb_accelerator_int
(

 // board clock
 input         clock,

 // pll clock
 input         cpu_clk,        

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

 // fast memory
 output [15:0] ram_scrub_A,
 input  [7:0]  ram_scrub_D_rd,

 output [15:0] ram_cpu_A,
 output        ram_cpu_we,
 output [7:0]  ram_cpu_D_wr,
 input  [7:0]  ram_cpu_D_rd

 );

   parameter  NPHI0_REGS = 6;
   parameter  PHIOUT_TAP = 1;

   parameter MODEL = 0;    
   localparam MODEL_BBC = 0;
   localparam MODEL_ELK = 1;
   localparam MODEL_MASTER = 2;

   parameter IS_INTERNAL_LOOKAHEAD = 0;
   parameter AGGRESSIVE = 0;

   localparam BASIC_ROM = MODEL == MODEL_ELK ? 11 : MODEL == MODEL_MASTER ? 12 : 15;


   reg         tick;
   reg [5:0]   clk_div = 'b0;
   reg [5:0]   cpu_div = 'b0;

   reg [NPHI0_REGS-1:0] Phi0_r;

   wire        cpu_clken;
   reg         cpu_reset;
   wire [15:0] cpu_AB_next;
   reg [14:0]  scrub_AB;
   reg [15:0]  cpu_AB;
   reg [15:0]  beeb_AB;
   wire [7:0]  cpu_DI;
   reg [7:0]   data_r;
   wire [7:0]  cpu_DO_next;
   reg [7:0]   cpu_DO;
   reg [7:0]   beeb_DO;
   wire        cpu_WE_next;
   reg         cpu_WE;
   reg         beeb_WE;
   reg         cpu_IRQ;
   reg         cpu_NMI;
   reg         cpu_RDY;
   wire        cpu_SYNC;
   reg [3:0]   force_slowdown = 4'b0;

   reg [7:0]   ram[0:65535];
   reg [7:0]   ram_dout;
   reg [7:0]   ram_dout2; // Second port to suport scrubbing RAM back to external RAM

   reg         ext_busy;
   reg         ext_cycle_start;
   wire        ext_cycle_end;

   reg         rom_latch_basic;

//   generate if (MODEL == MODEL_MASTER)
      // From FE30: bit 7
      reg         ram_at_8000;
      // From FE34: IRR TST IFU ITU Y X E D
      reg         acccon_e; // controls whether VDU  code accesses main or shadow RAM
      reg         acccon_x; // controls whether !VDU code accesses main or shadow RAM
      reg         acccon_y; // controls wither file system workspace is active at C000-DFFF
//   else
      // These implement a B+ style shadow mode
      reg         shadow = 1'b0;
//   endgenerate

   // Access to the screen RAM (3000-7FFF, main bank and shadow bank)
   //
   // On the B/B+ the display is always driven from the main bank. The
   // the optimal strategy depends on the shadow bit:
   // - shadow off: Mirror the main bank (slow writes, fast reads)
   // - shadow  on: Provide the shadow bank (fast writes, fast reads)
   //
   // On the Master, it's more complex as the either bank can be
   // displayed.
   //
   // Screen RAM Access on the Master involves three actors:
   // - the display hardware (controlled by acccon_d)
   // - the VDU driver code (controlled by acccon_e)
   // - all other code (controlled by acccon_x)
   //
   // When a non-shadow mode is selected (e.g. MODE 0)
   // - acccon_d = 0
   // - acccon_e = 0
   // - acccon_x = 0
   // i.e. all actors use the main bank, and the shadow bank is unused
   // (unless the user manually maps it in calling OSBYTE 108)
   //
   // When a shadow mode is selected (e.g. MODE 128)
   // - acccon_d = 1
   // - acccon_e = 1
   // - acccon_x = 0
   // i.e. the display and VDU drivers use the shadow bank, leaving
   // the user with the entirety of the main bank.
   //
   // The simplest approach is quite conservative: the fast (internal)
   // RAM is used as a write-through cache of the main bank.
   // - Writes to either bank are external (slow)
   // - Reads from the shadow bank are external (slow)
   // - Reads from the main bank are internal (fast)
   //
   // With this approach, either bank can be displayed, and an
   // application that uses double buffering will function
   // currectly. However, is is slower that the approach is used for
   // the B/B+, as writes are always slow.
   //
   // A more aggressive approach would allow one of the banks in the
   // machine to be entirely served from local fast RAM, and never
   // written back to the main machine. For example, in shadow mode,
   // don't write back accesses to the main bank. Clearly this will
   // break applications that do double-buffering. But most don't
   //
   // Here's an illustration of those two strategies at play
   //
   // CLOCKS4 figures, with a 80MHz clock, run in MODE 7/135, HIMEM set manually
   //
   // Conservative:
   //     Non-shadow, HIMEM=&7C00, 73.31 MHz
   //     Non-shadow, HIMEM=&3000, 81.55 MHz
   //     Shadow,     HIMEM=&7C00, 73.31 MHz
   //     Shadow,     HIMEM=&3000, 81.55 MHz
   //
   // Aggressive:
   //     Non-shadow, HIMEM=&7C00, 73.31 MHz
   //     Non-shadow, HIMEM=&3000, 81.55 MHz
   //     Shadow,     HIMEM=&7C00, 81.55 MHz <<<< this case gets faster
   //     Shadow,     HIMEM=&3000, 81.55 MHz

   // Signals to implement the above policies
   //   screen_wr_ext - writes to the screen address range are external
   //   screen_rd_ext - reads from the screen address range are external
   //   fsb_wren      - write enable for the fast screen bank


   // Indicates the last instruction was fetched from &C000-&DFFF
   // i.e. the VDU driver
   reg         vdu_op;

   wire        is_rom_latch    = (MODEL == MODEL_ELK) 
                                    ? (cpu_AB == 16'hFE05) 
                                    : (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b00);
   wire        is_shadow_latch = (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b01);
   wire        is_speed_latch  = (cpu_AB[15:4] == 12'hFE3) && (cpu_AB[3:2] == 2'b10);

   wire        screen_wr_ext;
   wire        screen_rd_ext;
   wire        fsb_wren;

   generate if (MODEL == MODEL_MASTER) begin
      if (AGGRESSIVE) begin
         // Aggressive caching strategy, i.e. in shadow mode, cache user writes to the main bank
         assign screen_wr_ext = !(acccon_e & !acccon_x & !vdu_op);
      end else begin
         // Conservative (write-through) caching strategy, i.e. all writes are external
         assign screen_wr_ext = 1'b1;
      end
      assign screen_rd_ext =  ((acccon_e & vdu_op) | (acccon_x & !vdu_op)); // reads from the shadow bank are external
      assign fsb_wren      = !((acccon_e & vdu_op) | (acccon_x & !vdu_op)); // writes to the main bank are mirrored internally
   end else begin
      // B/B+
      assign screen_wr_ext = shadow ?  vdu_op : 1'b0;
      assign screen_rd_ext = shadow ?  vdu_op : 1'b0;
      assign fsb_wren      = shadow ? !vdu_op : 1'b1;
   end
   endgenerate

   assign ram_cpu_A = cpu_AB_next;
   assign ram_cpu_D_wr = cpu_DO_next;
   assign ram_cpu_we = cpu_WE_next && !cpu_AB_next[15] && (cpu_AB_next[14:12] < 3'b011 || fsb_wren);
   assign ram_dout = ram_cpu_D_rd;

   assign ram_dout2 = ram_scrub_D_rd;
   assign ram_scrub_A = {1'b0, scrub_AB};

   // Writable Registers
   always @(posedge cpu_clk)
      if (cpu_clken) begin
         if (cpu_WE) begin
            // &FE30 - ROM latch
            if (is_rom_latch) begin
               rom_latch_basic <= (cpu_DO[3:0] == BASIC_ROM);
               if (MODEL == MODEL_MASTER)
                  ram_at_8000 <= cpu_DO[7];
            end
            // &FE34 - Shadow latch (B+) / Access Control (Master)
            if (is_shadow_latch) begin
               if (MODEL == MODEL_MASTER)
                  {acccon_y, acccon_x, acccon_e} <= cpu_DO[3:1];
               else
                  shadow <= cpu_DO[7];
            end
            // &FE38 - Speed Latch
            if (is_speed_latch) begin
               cpu_div <= cpu_DO[5:0] - 1'b1;
            end
        end
     end

   // Clock delay chain
   always @(posedge cpu_clk) begin
      // Synchronise/delay PhiIn
      Phi0_r <= { Phi0_r[NPHI0_REGS-2:0], PhiIn };
      // Internally the CPU runs at 64/CPU_DIV MHz
      if (clk_div == cpu_div)
        clk_div <= 'b0;
      else
        clk_div <= clk_div + 1'b1;
      // Pipeline the clock enable tick
      tick <= (clk_div == 0);
   end

   assign Phi1Out = !Phi0_r[PHIOUT_TAP];
   assign Phi2Out =  Phi0_r[PHIOUT_TAP];

   // Arlet's 65C02 Core
   cpu_65c02 cpu
     (
      .clk(cpu_clk),
      .reset(cpu_reset),
      .AB(cpu_AB_next),
      .DI(cpu_DI),
      .DO(cpu_DO_next),
      .WE(cpu_WE_next),
      .IRQ(cpu_IRQ),
      .NMI(cpu_NMI),
      .RDY(cpu_clken),
      .SYNC(cpu_SYNC)
      );

  // On the 6502, latch Rdy in the middle of the cycle
   generate if (MODEL == MODEL_MASTER)
      always @(Rdy)
         cpu_RDY = Rdy;
   else
      always @(posedge Phi2Out)
         cpu_RDY <= Rdy;
   endgenerate

wire is_internal;

generate if (IS_INTERNAL_LOOKAHEAD) begin

   reg        r_is_internal;

   assign   is_internal = r_is_internal;

   wire [7:0] page = cpu_AB_next[15:8];

   wire       is_shadow_latch_next = (cpu_AB_next[15:4] == 12'hFE3) && (cpu_AB_next[3:2] == 2'b01);
   wire       is_speed_latch_next  = (cpu_AB_next[15:4] == 12'hFE3) && (cpu_AB_next[3:2] == 2'b10);

   // Determine if the access is internal (fast) or external (slow)
   wire is_internal_next
     = !(
         (page >= 8'h30 && page < 8'h80 && (cpu_WE_next ? screen_wr_ext : screen_rd_ext)) |
      (  (MODEL == MODEL_MASTER)
         ?  (
            // Accesses to private MOS RAM (8000-8FFF)
            (page >= 8'h80 && page < 8'h90 && ram_at_8000) |
            // Accesses to file system RAM (C000-DFFF)
            // or
            // Executing the VDU driver to run from external ROM
            //
            // The Master has logic in one of it's custom chips to
            // determine the destination bank of a screen access by the
            // CPU. Part of this depends on whether the instruction
            // opcode fetch was from the VDU driver or not. For this to
            // function, the VDU driver must be run from slow external
            // ROM. This is the purpose of the acccon_e term.
            (page >= 8'hc0 && page < 8'hE0 && (acccon_y | acccon_e)) 
            )
         : 'b0
      )
      |
         // Accesses to ROMs other then BASIC are external
         (page >= 8'h80 && page < 8'hC0 && !rom_latch_basic) |
         // Accesses to IO are external
         (page >= 8'hfc && page < 8'hff)
         ) |
      (   (MODEL == MODEL_MASTER)
            // On the Master &FE34 is external
         ? is_speed_latch_next
            // On the Beeb &FE34 is internal (otherwise the ROM lach gets trashed)
         : (is_shadow_latch_next | is_speed_latch_next)
      )
      ;

   always @(posedge cpu_clk)
     if (cpu_clken)
       r_is_internal <= is_internal_next;

end else begin

   wire [7:0]  page = cpu_AB[15:8];

   // Determine if the access is internal (fast) or external (slow)
   assign is_internal
     = !(
         (page >= 8'h30 && page < 8'h80 && (cpu_WE ? screen_wr_ext : screen_rd_ext)) 
      |
      (  (MODEL == MODEL_MASTER)
         ? (
            // Accesses to private MOS RAM (8000-8FFF)
            (page >= 8'h80 && page < 8'h90 && ram_at_8000) |
            // Accesses to file system RAM (C000-DFFF)
            // or
            // Executing the VDU driver to run from external ROM
            //
            // The Master has logic in one of it's custom chips to
            // determine the destination bank of a screen access by the
            // CPU. Part of this depends on whether the instruction
            // opcode fetch was from the VDU driver or not. For this to
            // function, the VDU driver must be run from slow external
            // ROM. This is the purpose of the acccon_e term.
            (page >= 8'hc0 && page < 8'hE0 && (acccon_y | acccon_e)) 
         )
         : 'b0
      )
      |
         // Accesses to ROMs other then BASIC are external
         (page >= 8'h80 && page < 8'hC0 && !rom_latch_basic) |
         // Accesses to IO are external
         (page >= 8'hfc && page < 8'hff)
         )
      |
      (  (MODEL == MODEL_MASTER)
           // On the Master &FE34 is external
         ?  is_speed_latch
           // On the Beeb &FE34 is internal (otherwise the ROM lach gets trashed)
         :  (is_shadow_latch | is_speed_latch)
      )
      ;

end
endgenerate


   // When to advance the internal core a tick
   assign cpu_clken = (is_internal && tick && !(|force_slowdown)) ? cpu_RDY :
                      (ext_busy && ext_cycle_end)                 ? cpu_RDY :
                      1'b0;

   // Offset the external cycle by a couple of ticks to give some address hold time
   assign ext_cycle_end = Phi0_r[NPHI0_REGS-1] & !Phi0_r[NPHI0_REGS-2];

   initial scrub_AB <= 'd0;

   always @(posedge cpu_clk) begin
      ext_cycle_start <= ext_cycle_end;
      if (ext_cycle_start) begin
         if (is_internal) begin
            beeb_AB  <=  {1'b0, scrub_AB};
            beeb_WE  <=  1'b1;
            beeb_DO  <=  ram_dout2;
            ext_busy <=  1'b0;
            scrub_AB <=  scrub_AB + 1'b1;
         end else begin
            beeb_AB  <= cpu_AB;
            beeb_WE  <= cpu_WE;
            beeb_DO  <= cpu_DO;
            ext_busy <= 1'b1;
         end
      end
      // Following a write to the addressable latch, we need to slow the CPU for
      // a further few cycles, otherwise the keyboard and sound chips misbehave.
      // In the case of the sound chip, a software delay loop gives a write pulse
      // of 9us. A force_slowdown of ~15 minics this (assume bus cycles are 500ns).
      // In the case of the keyboard, a much smaller delay is acceptable, and we
      // we set force_slowdown to 1. When ever force_slowdown is non-zero, the
      // CPU runs at a maximum of 2MHz.
      if (ext_cycle_end)
        if (cpu_AB == 16'hfe40 && cpu_WE)
          if (cpu_DO[2:0] == 0)
            force_slowdown <= 'hf;
          else
            force_slowdown <= 'h1;
        else if (force_slowdown > 0)
          force_slowdown <= force_slowdown - 1'b1;
      // Writes to the speed register
   end

   // Register the outputs of Arlet's core
   always @(posedge cpu_clk) begin
      if (cpu_clken) begin
         cpu_AB <= cpu_AB_next;
         cpu_WE <= cpu_WE_next;
         cpu_DO <= cpu_DO_next;
         if (cpu_SYNC)
           vdu_op <= 
               (MODEL == MODEL_MASTER)
                  ? ((cpu_AB[15:13] == 3'b110) && !acccon_y)
                  : cpu_AB[15:13] == 3'b110
                  ;
      end
   end

   // Synchronise asynchronous inputs
   always @(posedge cpu_clk) begin
      cpu_reset <= !Res_n;
      cpu_IRQ <= !IRQ_n;
      cpu_NMI <= !NMI_n;
   end

   // CPU Din Multiplexor
   assign cpu_DI = is_internal ? ram_dout : data_r;

   // Sample Data on the falling edge of Phi2 (ref A in the datasheet)
   always @(negedge Phi2Out) begin
      data_r <= Data;
   end

   assign Data    = (beeb_WE & PhiIn) ? beeb_DO : 8'bZ;
   assign Addr    = beeb_AB;
   assign R_W_n   = {2{!beeb_WE}};
   assign Sync    = cpu_SYNC;

   // 65C02 Outputs
   assign ML_n    = 'b1;
   assign VP_n    = 'b1;

endmodule
