module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
//read write protocol
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
// ram protocol
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n,
	// test wire
	output  wire [1:0] test_wstate,
	output  wire [1:0] test_rstate,
	output  wire [pADDR_WIDTH-1:0] test_waddr,
	output  wire [pADDR_WIDTH-1:0] test_raddr
);
//------------------------Parameter----------------------

localparam
	ADDR_AP_CTRL			= 12'h00, // control: 0=start, 1=done, 2=idle
    DATA_LENGTH 			= 12'h10, // data addr_length
    ADDR_AN32COEF_BASE      = 12'h20, // taps parameter start
    ADDR_AN32COEF_HIGH      = 12'h48, // taps parameter end
	ADDR_AN32DATA_BASE      = 12'h4c, // data start
	ADDR_AN32DATA_HIGH      = 12'h70, // data end
    WRIDLE                  = 2'd0,
    WRDATA                  = 2'd1,
    WRRESP                  = 2'd2,
    WRRESET                 = 2'd3,
    RDIDLE                  = 2'd0,
    RDDATA                  = 2'd1,
    RDRESET                 = 2'd2;


//------------------------Local signal-------------------	
	//write
	wire [pADDR_WIDTH-1:0]        waddr; 
    wire                          aw_hs;
    wire                          w_hs;
	reg 						  BREADY      = 1'b1;
	//read
	wire [pADDR_WIDTH-1:0]        raddr;
    reg  [pDATA_WIDTH-1:0]        int_rdata   =  'b0;
    wire                          ar_hs;
	// axilite
    reg  [pDATA_WIDTH:0]          addr_length =  'b0;	
	reg 						  int_ap_start= 1'b0;                       
    reg                           int_ap_idle = 1'b0;
    reg                           int_ap_done = 1'b0;
	// transaction signals
	reg [31:0] RAM [0:256];
	integer i;
	reg SS_EN = 1'b0;
	reg [3:0] count_data_ram = 0;
	reg [pDATA_WIDTH-1:0] data_address = ADDR_AN32DATA_BASE;
	reg [pDATA_WIDTH-1:0] ss_reg_data;
	reg [pDATA_WIDTH-1:0] result_adder;
	reg [pDATA_WIDTH-1:0] result_multiplier[0:9];
	reg [pDATA_WIDTH-1:0] sm_reg_data;
	reg ss_state = 1'b0, sm_state = 1'b0;
	
	// for coef tap ram
	reg 						  coef_read   = 1'b0;
	reg 						  coef_write  = 1'b0;
	reg  [pDATA_WIDTH-1:0]		  int_coef;
	// tap ram
	reg [pADDR_WIDTH-1:0] tap_address = 'b0;
	reg [pDATA_WIDTH/8-1:0] WSTRB = 4'b0001;
	reg [1:0] count_wstrb=0;
	// FSM
	reg [1:0] wstate;
	reg [1:0]  wnext;
	reg [1:0] rstate;
	reg [1:0]  rnext;
	
	initial begin
        for(i=0;i<256;i=i+1) begin
			RAM[i]='b0;
		end
    end
//------------------------AXI write fsm------------------
	assign waddr     =     awaddr;
	assign awready   =     ((wstate==WRIDLE)||(wstate==WRDATA));
	assign wready    =     ((wstate==WRDATA)&&(rstate!=RDDATA));
	assign aw_hs     =     awvalid & awready;
	assign w_hs      =     wvalid & wready;
	
// write state
	always @(posedge axis_clk) begin
		if (axis_rst_n) begin
			wstate <= WRIDLE;
		end
		else begin
			wstate <= wnext;
		end
	end	
	
	always @(*) begin
		case (wstate)
			WRIDLE:
				if (awvalid&(!int_ap_start)) // remain WRIDLE when ap_start rise
					wnext = WRDATA;
				else
					wnext = WRIDLE;
			WRDATA:
				if (w_hs)
					wnext = WRRESP;
				else
					wnext = WRDATA;
			WRRESP:
				if (BREADY)
					wnext = WRIDLE;
				else
					wnext = WRRESP;
			default:
				wnext = WRIDLE;
		endcase
	end
	
	/*
	// let awaddr delay one clk
	always @(posedge axis_clk) begin
		if (aw_hs) begin
			waddr <= awaddr;
		end
	end
	*/
	
//------------------------AXI read fsm------------------- 
	assign raddr     =     araddr;
	assign arready   =     (rstate==RDIDLE);
	assign rdata     =     int_rdata;
	assign rvalid    =     ((rstate==RDDATA)&&(wstate!=WRDATA));
	assign ar_hs     =     arvalid & arready;
	assign r_hs      =     rready & rvalid;
	
// read state
	always @(posedge axis_clk) begin
		if (axis_rst_n) begin
			rstate <= RDIDLE;
		end
		else begin
			rstate <= rnext;
		end
	end	
	
	always @(*) begin
		case (rstate)
			RDIDLE:
				if (arvalid)
					rnext = RDDATA;
				else
					rnext = RDIDLE;
			RDDATA:
				if (r_hs)
					rnext = RDIDLE;
				else
					rnext = RDDATA;
			default:
				rnext = RDIDLE;
		endcase
	end


// rdata
	always @(*) begin
		if (raddr==ADDR_AP_CTRL) begin
			int_rdata[0] = int_ap_start;
            int_rdata[1] = int_ap_done;
            int_rdata[2] = int_ap_idle;
			int_rdata[pDATA_WIDTH-1:3] = 'b0;
		end
		else if (raddr==DATA_LENGTH) begin
			int_rdata = addr_length;
		end
		else if ((raddr>=ADDR_AN32COEF_BASE)&&(raddr<=ADDR_AN32COEF_HIGH)) begin //check coef read from sram is correct // .......................................................
			int_rdata = tap_Do;
		end
		else begin
			int_rdata = 'b0;
		end
	end

//------------------------Register logic-----------------

// int_ap_start
	always @(*) begin
		if (axis_rst_n) begin
			int_ap_start = 1'b0;
		end
		else begin
			if((wstate==WRDATA)&&(waddr==ADDR_AP_CTRL)) begin // start FIR engine
				int_ap_start = wdata[0];
			end
			else begin // prevent ap_start maintain rise
				int_ap_start = 1'b0;
			end
		end
	end
	
// int_ap_done
	always @(*) begin
		if (axis_rst_n) begin
			int_ap_done = 1'b0;
		end
		else if (rvalid|wready|sm_tlast) begin
			int_ap_done = 1'b1;
		end
		else begin
			int_ap_done = 1'b0;
		end
	end

// int_ap_idle
	always @(*) begin
		if (axis_rst_n) begin
			int_ap_idle = 1'b1;
		end
		else if (int_ap_start) begin
			int_ap_idle = 1'b0;
		end
		else if (rvalid|wready|sm_tlast) begin
			int_ap_idle = 1'b1;
		end
		else begin // might be wrong...
			int_ap_idle = 1'b1;
		end
	end

// addr_length[31:0]
	always @(posedge axis_clk) begin
		if (axis_rst_n) begin
			addr_length <= 'b0;
		end
		if ((wstate==WRDATA) && waddr == DATA_LENGTH) begin
			addr_length <= wdata;
		end
	end	
	
//------------------------transaction protocol-------------------
	// tap data ram
	assign data_WE = (ss_tvalid) ? 4'b1111:4'b0000;
	assign data_EN = SS_EN;
	assign data_A  = data_address;
	assign data_Di = result_adder;
	// transaction
	assign ss_tready = ss_state;
	assign sm_tlast  = sm_state;
	assign sm_tvalid = ss_tready;
	assign sm_tdata = result_adder;

// start fir engine
	always @ (posedge axis_clk) begin
		if (axis_rst_n) begin
			SS_EN <= 1'b0;
		end
		if(int_ap_start==1) begin
			SS_EN <= 1'b1;
		end
	end

// ss 
	always @ (posedge axis_clk) begin
		if(SS_EN)begin
			if (ss_tvalid) begin // data in
				ss_reg_data <= ss_tdata;
				ss_state <= 1'b1;
				result_adder <=0;
				RAM[ADDR_AN32DATA_BASE>>2][31:0] <= ss_tdata;
				RAM[(ADDR_AN32DATA_BASE+4)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+8)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+4)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+12)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+8)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+16)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+12)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+20)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+16)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+24)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+20)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+28)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+24)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+32)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+28)>>2][31:0];
				RAM[(ADDR_AN32DATA_BASE+36)>>2][31:0] <= RAM[(ADDR_AN32DATA_BASE+32)>>2][31:0];
			end
			else begin
				ss_state <= 1'b0;
			end
		end
	end
	
// FIR
	always @ (*) begin
		result_multiplier[0]=(RAM[ADDR_AN32DATA_BASE>>2][31:0])*(RAM[ADDR_AN32COEF_HIGH>>2][31:0]);
		result_multiplier[1]=(RAM[(ADDR_AN32DATA_BASE+4)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-4)>>2][31:0]);
		result_multiplier[2]=(RAM[(ADDR_AN32DATA_BASE+8)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-8)>>2][31:0]);
		result_multiplier[3]=(RAM[(ADDR_AN32DATA_BASE+12)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-12)>>2][31:0]);
		result_multiplier[4]=(RAM[(ADDR_AN32DATA_BASE+16)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-16)>>2][31:0]);
		result_multiplier[5]=(RAM[(ADDR_AN32DATA_BASE+20)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-20)>>2][31:0]);
		result_multiplier[6]=(RAM[(ADDR_AN32DATA_BASE+24)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-24)>>2][31:0]);
		result_multiplier[7]=(RAM[(ADDR_AN32DATA_BASE+28)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-28)>>2][31:0]);
		result_multiplier[8]=(RAM[(ADDR_AN32DATA_BASE+32)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-32)>>2][31:0]);
		result_multiplier[9]=(RAM[(ADDR_AN32DATA_BASE+36)>>2][31:0])*(RAM[(ADDR_AN32COEF_HIGH-36)>>2][31:0]);
		for (i=0;i<10;i=i+1)begin
			result_adder = result_adder + result_multiplier[i];
		end
	end
	
	always @ (posedge axis_clk) begin
		if(ss_tlast) begin
			sm_state <= 1'b1;
		end
		else begin
			sm_state <= 1'b0;
		end
	end


// tap ram-----------------------------------------------------------------------------
	assign tap_EN = (wstate==WRDATA)|(wstate==WRRESP)|(rstate==RDDATA)|SS_EN;	
	assign tap_WE = (coef_write) ? 4'b1111 : 4'b0000;
	assign tap_A  = (tap_address);
	assign tap_Di =  wdata;
// mem write strobe	
	always @ (*) begin
		if(coef_write)begin
			if(count_wstrb==2'd3)begin
				WSTRB=WSTRB<<1;
				count_wstrb=0;
			end
			count_wstrb = count_wstrb+1;
		end
	end
	always @(posedge axis_clk) begin
		if(coef_write&tap_EN)begin
			RAM [tap_address>>2][31:0]<= wdata;
		end
	end
	
// read tap available
	always @ (*) begin
		if (axis_rst_n) begin
			coef_read <= 1'b0; 
		end
		else begin
			if ((rstate==RDDATA)&&(raddr>=ADDR_AN32COEF_BASE)&&(raddr<=ADDR_AN32COEF_HIGH)) begin
				coef_read <= 1'b1;
			end
			else begin
				coef_read <= 1'b0;
			end
		end
	end
	
// write tap available
	always @ (*) begin
		if (axis_rst_n) begin
			coef_write <= 1'b0; 
		end
		else begin
			if ((wstate==WRRESP|wstate==WRDATA)&&(waddr>=ADDR_AN32COEF_BASE)&&(waddr<=ADDR_AN32COEF_HIGH)) begin
				coef_write <= 1'b1;
			end
			else begin
				coef_write <= 1'b0;
			end
		end
	end
// make sure tape address only receive one address value
	always @(*) begin
		if (coef_read) begin // only when read coef
			tap_address = (raddr);
		end
		else if (coef_write) begin // only when write coef
			tap_address = (waddr);
		end
	end
//-----------------------test----------------------------
	assign test_wstate = wstate;
	assign test_rstate = rstate;
	assign test_waddr  = waddr;
	assign test_raddr  = raddr;
endmodule