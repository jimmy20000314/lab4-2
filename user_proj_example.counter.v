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
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
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
    input  [38-1:0] io_in,
    output [38-1:0] io_out,
    output [38-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk;
    wire rst;
    wire [3:0] wstrb;
    wire valid;
    wire [31:0] wdata;
    wire [31:0] rdata;
	reg [31:0] count;
    reg READY;
    wire [38-1:0] io_in;
    wire [38-1:0] io_out;
    wire [38-1:0] io_oeb;

    assign clk = (~la_oenb[64])?la_data_in[64]:wb_clk_i;
    assign rst = (~la_oenb[65])?la_data_in[65]:wb_rst_i;
    assign wstrb = wbs_sel_i & {4{wbs_we_i}};
    assign valid = wbs_cyc_i && wbs_stb_i;
    assign wdata = wbs_dat_i;
    assign wbs_dat_o = count;
    assign wbs_ack_o = READY;
    //IO
    assign io_out = count;
    assign io_oeb = {(38-1){rst}};
    //IRQ
    assign irq = 3'b000;
    //LA
    assign la_data_out={{(127-BITS){1'b0}},count};
   
 
    bram user_bram (
        .CLK(wb_clk_i),
        .RST(wb_rst_i),
        .WE0(wstrb),
        .EN0(READY),
        .Di0(wdata),
        .Do0(rdata),
        .A0(wbs_adr_i)
    );
	
	always @(posedge wb_clk_i) begin // delay 12 cycle
    	if (rst) begin
    		count <= 32'b0;
    		READY <= 1'b0;
    	end
    	else begin
    	        READY <= 0;
    		if (valid) begin
    			if(count<DELAYS)begin
	    			count <= count + 1;
	    			READY <= 1'b0;
	    		end
	    		else begin
	    			count <= 32'b0;
	    			READY <= 1'b1;
	    		end
    		end
        end
    end
endmodule



`default_nettype wire
