module AHB_master_reverse (
    // input
    input         HCLK,
    input         HRESETN,
    input  [31:0] HWDATA,
    input  [31:0] HADDR,
    input  [ 2:0] HBURST,       //000   SINGLE
    input  [ 2:0] HSIZE,        //010   32bit
    input         HWRITE,
    input  [ 1:0] HTRANS,
    input         HMASTLOCK,    //0     
    input  [ 3:0] HPROT,        //0000
    input         HREADY,       //not connected
    input         HSEL,         //not connected
    output [31:0] HRDATA,
    output        HREADYOUT,
    output        HRESP,        //not used
    // reversed 
    output [31:0] r_HWDATA,
    output [31:0] r_HADDR,
    output [25:0] r_HADDR_26b,
    output [ 2:0] r_HBURST,     //000   SINGLE
    output [ 2:0] r_HSIZE,      //010   32bit
    output        r_HWRITE,
    output [ 1:0] r_HTRANS,
    output        r_HMASTLOCK,  //0     
    output [ 3:0] r_HPROT,      //0000
    output        r_HREADY,     //not connected
    output        r_HSEL,       //not connected
    input  [31:0] r_HRDATA,
    input         r_HREADYOUT,
    input         r_HRESP,      //not used
    //user
    input  [31:0] ahb_waddr_i,
    input  [31:0] ahb_raddr_i,
    input         r_valid_i,
    input         w_valid_i,
    input  [31:0] ahb_wdata_i,
    output [31:0] ahb_rdata_o
);
    wire [31:0] addr;
    wire read;
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin
            assign r_HWDATA[i] = HWDATA[31-i];
            assign r_HADDR[i]  = HADDR[31-i];
            assign HRDATA[i]   = r_HRDATA[31-i];
        end
    endgenerate
    genvar j;
    generate
        for (j = 0; j < 3; j = j + 1) begin
            assign r_HBURST[j] = HBURST[2-j];
            assign r_HSIZE[j]  = HSIZE[2-j];
        end
    endgenerate
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin
            assign r_HPROT[k] = HPROT[3-k];
        end
    endgenerate
    assign r_HADDR_26b = r_HADDR[31-:26];
    assign r_HTRANS[0] = HTRANS[1];
    assign r_HTRANS[1] = HTRANS[0];
    assign r_HWRITE = HWRITE;
    assign r_HMASTLOCK = HMASTLOCK;
    assign HREADYOUT = r_HREADYOUT;
    assign HRESP = r_HRESP;
    assign r_HREADY = HREADY;
    assign r_HSEL = HSEL;


    assign addr = (r_valid_i===1'b1)?ahb_raddr_i:(w_valid_i===1'b1)?ahb_waddr_i:32'hzzzzzzzz;
    assign read = (r_valid_i === 1'b1) ? 1'b1 : (w_valid_i === 1'b1) ? 1'b0 : 1'bz;

    AHB_master u_AHB_master (
        .HCLK     (HCLK),
        .HRESETN  (HRESETN),
        .HRDATA   (r_HRDATA),
        .HREADYOUT(HREADYOUT),
        .HRESP    (HRESP),
        .addr     (addr),
        .read     (read),
        .w_data   (ahb_wdata_i),

        .HWDATA   (HWDATA),
        .HADDR    (HADDR),
        .HBURST   (HBURST),
        .HSIZE    (HSIZE),
        .HWRITE   (HWRITE),
        .HTRANS   (HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HPROT    (HPROT),
        .HREADY   (HREADY),
        .HSEL     (HSEL),
        .r_data   (ahb_rdata_o)
    );
endmodule

module AHB_master (
    // AHB
    input  wire        HCLK,
    input  wire        HRESETN,
    input  wire [31:0] HRDATA,
    input  wire        HREADYOUT,
    input  wire        HRESP,      //not used
    output reg  [31:0] HWDATA,
    output reg  [31:0] HADDR,
    output wire [ 2:0] HBURST,     //000   SINGLE
    output wire [ 2:0] HSIZE,      //010   32bit
    output reg         HWRITE,
    output reg  [ 1:0] HTRANS,
    output wire        HMASTLOCK,  //0     
    output wire [ 3:0] HPROT,      //0000
    output wire        HREADY,     //not connected
    output wire        HSEL,       //not connected
    // data interface
    input  wire [31:0] addr,
    input  wire        read,
    input  wire [31:0] w_data,
    output reg  [31:0] r_data
);

    //----------------------------------------------------
    //                 AHB Management
    //----------------------------------------------------
    assign HPROT = 4'b0000;
    assign HSIZE = 3'b010;
    assign HBURST = 3'b000;
    assign HMASTLOCK = 1'b0;

    assign HREADY = 1'b0;
    assign HSEL = 1'b0;

    localparam AHB_FSM_IDLE = 3'h0;
    localparam AHB_FSM_WAIT_PHASE = 3'h1;
    localparam AHB_FSM_W_ADDRESS_PHASE = 3'h2;
    localparam AHB_FSM_W_DATA_PHASE = 3'h3;
    localparam AHB_FSM_R_ADDRESS_PHASE = 3'h4;
    localparam AHB_FSM_R_DATA_PHASE = 3'h5;

    localparam AHB_HTRANS_IDLE = 3'h0;
    localparam AHB_HTRANS_BUSY = 3'h1;
    localparam AHB_HTRANS_NONSEQ = 3'h2;
    localparam AHB_HTRANS_SEQ = 3'h3;

    reg [31:0] w_data_last;
    reg [ 2:0] fsm_ahb;

    always @(posedge HCLK or negedge HRESETN) begin
        if (!HRESETN) begin
            HADDR <= 32'b0;
            HWDATA <= 32'b0;
            HWRITE <= 1'b1;
            HTRANS <= AHB_HTRANS_IDLE;
            fsm_ahb <= AHB_FSM_WAIT_PHASE;
            w_data_last <= 32'b0;
        end else begin
            case (fsm_ahb)
                // IDLE
                AHB_FSM_IDLE: begin
                    HADDR   <= 32'b0;
                    HWDATA  <= 32'b0;
                    HWRITE  <= 1'b0;
                    HTRANS  <= AHB_HTRANS_IDLE;
                    fsm_ahb <= AHB_FSM_WAIT_PHASE;
                end

                // WAIT PHASE
                AHB_FSM_WAIT_PHASE: begin
                    HADDR  <= HADDR;
                    HWDATA <= HWDATA;
                    HWRITE <= HWRITE;
                    HTRANS <= AHB_HTRANS_IDLE;
                    if (HREADYOUT) begin
                        if (read) begin
                            HWRITE  <= 1'b0;
                            fsm_ahb <= AHB_FSM_R_ADDRESS_PHASE;
                        end else begin
                            // if (w_data_last == w_data) begin
                            //     HWRITE <= 1'b0;
                            //     fsm_ahb <= fsm_ahb;
                            //     w_data_last <= w_data;
                            // end else begin
                            HWRITE <= 1'b1;
                            fsm_ahb <= AHB_FSM_W_ADDRESS_PHASE;
                            w_data_last <= w_data;
                            // end
                        end
                    end else begin
                        fsm_ahb <= fsm_ahb;
                    end
                end

                // READ ADDRESS PHASE
                AHB_FSM_R_ADDRESS_PHASE: begin
                    HADDR   <= addr;
                    HWDATA  <= HWDATA;
                    HWRITE  <= 1'b0;
                    HTRANS  <= AHB_HTRANS_NONSEQ;
                    fsm_ahb <= AHB_FSM_R_DATA_PHASE;
                end

                // READ DATA PHASE
                AHB_FSM_R_DATA_PHASE: begin
                    if (HREADYOUT) begin
                        HADDR   <= HADDR;
                        HWDATA  <= HWDATA;
                        HWRITE  <= 1'b1;
                        HTRANS  <= AHB_HTRANS_IDLE;
                        r_data  <= HRDATA;
                        fsm_ahb <= AHB_FSM_WAIT_PHASE;
                    end else begin
                        fsm_ahb <= fsm_ahb;
                    end
                end

                // WRITE ADDRESS PHASE
                AHB_FSM_W_ADDRESS_PHASE: begin
                    HADDR   <= addr;
                    HWDATA  <= HWDATA;
                    HWRITE  <= HWRITE;
                    HTRANS  <= AHB_HTRANS_NONSEQ;
                    fsm_ahb <= AHB_FSM_W_DATA_PHASE;
                end

                // WRITE DATA PHASE
                AHB_FSM_W_DATA_PHASE: begin
                    HADDR   <= HADDR;
                    HWDATA  <= w_data;
                    HWRITE  <= HWRITE;
                    HTRANS  <= AHB_HTRANS_IDLE;
                    fsm_ahb <= AHB_FSM_WAIT_PHASE;
                end

                default: begin
                    HWRITE  <= 1'b0;
                    HTRANS  <= AHB_HTRANS_IDLE;
                    fsm_ahb <= AHB_FSM_WAIT_PHASE;
                end
            endcase
        end
    end


endmodule

