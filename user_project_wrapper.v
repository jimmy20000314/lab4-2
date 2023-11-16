// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype wire
/*
 *-------------------------------------------------------------
 *
 * user_project_wrapper
 *
 * This wrapper enumerates all of the pins available to the
 * user for the user project.
 *
 * An example user project is provided in this wrapper.  The
 * example should be removed and replaced with the actual
 * user project.
 *
 *-------------------------------------------------------------
 */

module user_project_wrapper #(
    parameter BITS = 32,
	parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter Data_Num    = 600
) (
`ifdef USE_POWER_PINS
    inout vdda1,	// User area 1 3.3V supply
    inout vdda2,	// User area 2 3.3V supply
    inout vssa1,	// User area 1 analog ground
    inout vssa2,	// User area 2 analog ground
    inout vccd1,	// User area 1 1.8V supply
    inout vccd2,	// User area 2 1.8v supply
    inout vssd1,	// User area 1 digital ground
    inout vssd2,	// User area 2 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [-1:0] io_in,
    output [38-1:0] io_out,
    output [38-1:0] io_oeb,

    // Analog (direct connection to GPIO pad---use with caution)
    // Note that analog I/O is not available on the 7 lowest-numbered
    // GPIO pads, and so the analog_io indexing is offset from the
    // GPIO indexing by 7 (also upper 2 GPIOs do not have analog_io).
    inout [38-10:0] analog_io,

    // Independent clock (on independent integer divider)
    input   user_clock2,

    // User maskable interrupt signals
    output [2:0] user_irq
);

// test
	wire [1:0] 					test_wstate;
	wire [1:0] 					test_rstate;
	wire [pADDR_WIDTH-1:0]		test_waddr;
	wire [pADDR_WIDTH-1:0]		test_raddr;
// test
    wire                        awready;
    wire                        wready;
    reg                         awvalid='b0;
    reg   [(pADDR_WIDTH-1): 0]  awaddr='b0;
    reg                         wvalid='b0;
    reg signed [(pDATA_WIDTH-1) : 0] wdata='b0;
    wire                        arready;
    reg                         rready='b0;
    reg                         arvalid='b0;
    reg         [(pADDR_WIDTH-1): 0] araddr='b0;
    wire                        rvalid;
    wire signed [(pDATA_WIDTH-1): 0] rdata;
    reg                         ss_tvalid='b0;
    reg signed [(pDATA_WIDTH-1) : 0] ss_tdata='b0;
    reg                         ss_tlast='b0;
    wire                        ss_tready;
    reg                         sm_tready='b0;
    wire                        sm_tvalid;
    wire signed [(pDATA_WIDTH-1) : 0] sm_tdata;
    wire                        sm_tlast;

// ram for tap
    wire [3:0]               tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;

// ram for data RAM
    wire [3:0]               data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;
	
// wb
	reg [31:0] wb_ctrl_o;
	reg end_task;
	wire io_out1;
	wire [31:0] counter_o;
	reg fir_start = 'b0;
	reg count_fir='b0;
	
	assign wbs_dat_o = wb_ctrl_o;
	assign io_out = (end_task=='b1) ? io_out1 : 'hFFFF; // test whether engine is complete
	
	always @(posedge wb_clk_i)begin
		if(wbs_dat_i=='h2710)begin // lab 4-1
			wb_ctrl_o <= counter_o;
		end
		else if(wbs_dat_i=='h2810)begin // lab 4-2
			wb_ctrl_o <= sm_tdata;
			fir_start <= 'b1;
		end
		else begin
			wb_ctrl_o <= 'd0;
		end
	end
	
// axi-lite protocol
	always @(posedge wb_clk_i)begin
		if(fir_start&&count_fir<11)begin // fill in coef
			wdata <= wbs_dat_i;
			count_fir <= count_fir+1;
		end
		else if (count_fir>=11) begin // engine start
			wdata <= wbs_dat_i;
			ss_tvalid <= 'b1;
		end
		else begin
			wdata <= 'd0;
		end
	end
	
	always @(posedge wb_clk_i)begin
		if(sm_tready&&sm_tready)begin // engine finish
			end_task <= 'b1;
		end
		else begin
			end_task <= 'b0;
		end
	end
/*--------------------------------------*/
/* User project is instantiated  here   */
/*--------------------------------------*/
user_proj_example mprj (
`ifdef USE_POWER_PINS
	.vccd1(vccd1),	// User area 1 1.8V power
	.vssd1(vssd1),	// User area 1 digital ground
`endif

    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),

    // MGMT SoC Wishbone Slave

    .wbs_cyc_i(wbs_cyc_i),
    .wbs_stb_i(wbs_stb_i),
    .wbs_we_i(wbs_we_i),
    .wbs_sel_i(wbs_sel_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_ack_o(wbs_ack_o),
    .wbs_dat_o(counter_o),

    // Logic Analyzer

    .la_data_in(la_data_in),
    .la_data_out(la_data_out),
    .la_oenb (la_oenb),

    // IO Pads

    .io_in (io_in),
    .io_out(io_out1),
    .io_oeb(io_oeb),

    // IRQ
    .irq(user_irq)
);

fir fir_DUT(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),
        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),
        .ss_tvalid(ss_tvalid),
        .ss_tdata(ss_tdata),
        .ss_tlast(ss_tlast),
        .ss_tready(ss_tready),
        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), // engine finish
        .sm_tdata(sm_tdata),
        .sm_tlast(sm_tlast),

        // ram for tap
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // ram for data
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(wb_clk_i),
        .axis_rst_n(wb_rst_i),
		
	// test wire
	.test_wstate(test_wstate),
	.test_rstate(test_rstate),
	.test_waddr(test_waddr),
	.test_raddr(test_raddr)
);
	
// RAM for tap
bram12 tap_RAM (
        .CLK(wb_clk_i),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .A(tap_A),
        .Do(tap_Do)
);

    // RAM for data
bram11 data_RAM(
        .CLK(wb_clk_i),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .A(data_A),
        .Do(data_Do)
);
/* always @(posedge wb_clk_i)begin
	if(wbs_dat_i=='h2710)begin
		$display("counter2710:",wbs_dat_i,wbs_dat_o);
	end
	if(wbs_dat_i=='h2810)begin
		$display("fir2810:",wbs_dat_i,wbs_dat_o);
	end
end */

endmodule	// user_project_wrapper

`default_nettype wire
