module AHB_master_wrapper (
    // input
    input  wire        HCLK,
    input  wire        HRESETN,
    input  wire [31:0] HRDATA,
    input  wire        HREADYOUT,
    input  wire        HRESP,      //not used
    output wire [31:0] HWDATA,     //000   SINGLE
    output wire [31:0] HADDR,
    output wire [25:0] HADDR_26b,
    output wire [ 2:0] HBURST,
    output wire [ 2:0] HSIZE,      //010   32bit
    output wire        HWRITE,     //0     
    output wire [ 1:0] HTRANS,     //0000
    output wire        HMASTLOCK,  //not connected
    output wire [ 3:0] HPROT,
    output wire        HREADY,
    output wire        HSEL,       //not connected

    //user
    input  wire [31:0] ahb_waddr_i,
    input  wire [31:0] ahb_raddr_i,
    input  wire        r_valid_i,
    input  wire        w_valid_i,
    input  wire [31:0] ahb_wdata_i,
    output wire [31:0] ahb_rdata_o
);

    //connect to ahb core signals
    wire [31:0] ahb_HRDATA;
    wire [31:0] ahb_HWDATA;
    wire [31:0] ahb_HADDR;
    wire [ 2:0] ahb_HBURST;
    wire [ 2:0] ahb_HSIZE;
    wire [ 1:0] ahb_HTRANS;
    wire [ 3:0] ahb_HPROT;
    //reversed signals
    wire [31:0] r_HRDATA;
    wire [31:0] r_HWDATA;
    wire [31:0] r_HADDR;
    wire [ 2:0] r_HBURST;
    wire [ 2:0] r_HSIZE;
    wire [ 1:0] r_HTRANS;
    wire [ 3:0] r_HPROT;


    wire [31:0] addr;
    wire        read;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin
            assign r_HRDATA[i] = HRDATA[31-i];
            assign r_HWDATA[i] = ahb_HWDATA[31-i];
            assign r_HADDR[i]  = ahb_HADDR[31-i];
        end
    endgenerate
    genvar j;
    generate
        for (j = 0; j < 3; j = j + 1) begin
            assign r_HBURST[j] = ahb_HBURST[2-j];
            assign r_HSIZE[j]  = ahb_HSIZE[2-j];
        end
    endgenerate
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin
            assign r_HPROT[k] = ahb_HPROT[3-k];
        end
    endgenerate
    assign r_HTRANS[0] = ahb_HTRANS[1];
    assign r_HTRANS[1] = ahb_HTRANS[0];

    /* connector: 0 not reverse; 1 reverse */
    assign ahb_HRDATA = (1'b1) ? r_HRDATA : HRDATA;
    assign HWDATA = (1'b1) ? r_HWDATA : ahb_wdata_i;
    assign HADDR = (1'b1) ? r_HADDR : ahb_HADDR;
    assign HBURST = (1'b1) ? r_HBURST : ahb_HBURST;
    assign HSIZE = (1'b1) ? r_HSIZE : ahb_HSIZE;
    assign HTRANS = (1'b1) ? r_HTRANS : ahb_HTRANS;
    assign HPROT = (1'b1) ? r_HPROT : ahb_HPROT;

    assign HADDR_26b = HADDR[31-:26];

    assign addr = (r_valid_i===1'b1)?ahb_raddr_i:(w_valid_i===1'b1)?ahb_waddr_i:32'hzzzzzzzz;
    assign read = (r_valid_i === 1'b1) ? 1'b1 : (w_valid_i === 1'b1) ? 1'b0 : 1'bz;

    AHB_master u_AHB_master (
        /* input */
        .HCLK     (HCLK),
        .HRESETN  (HRESETN),
        .HRDATA   (ahb_HRDATA),
        .HREADYOUT(HREADYOUT),
        .HRESP    (HRESP),
        /* output */
        .HWDATA   (ahb_HWDATA),
        .HADDR    (ahb_HADDR),
        .HBURST   (ahb_HBURST),
        .HSIZE    (ahb_HSIZE),
        .HWRITE   (HWRITE),
        .HTRANS   (ahb_HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HPROT    (ahb_HPROT),
        .HREADY   (HREADY),
        .HSEL     (HSEL),
        /* user */
        .addr     (addr),
        .read     (read),
        .w_data   (ahb_wdata_i),
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

