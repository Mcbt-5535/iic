module soft_i2c_slave_ahb #(
    parameter DEVICE_ADDR = 7'h66
) (
    input wire clk_i,  // System clock 50MHz
    input wire rst_ni, // Reset, low active

    input wire scl_i,  // Serial clock bus
    input wire sda_i,  // Tri-state buffer for writing
    output reg sda_oe_o,  //
    output reg sda_o,  //

    output reg       rw_flag_o,  // Read/write status flag, 0: write; 1: read
    output reg       wr_vld_o,   // Write data valid flag
    output reg [7:0] wr_data_o,  // Data to be written
    output reg       rd_vld_o,   // Read data valid flag
    output reg [7:0] rd_data_o,  // Data read out

    // AHB slave interface signals
    output reg [31:0] ahb_waddr_o,
    output reg [31:0] ahb_raddr_o,
    output reg        r_valid_o,
    output reg        w_valid_o,
    output reg [31:0] ahb_wdata_o,
    input      [31:0] ahb_rdata_i
);

    localparam WR_CTRL_WORD = {DEVICE_ADDR, 1'b0}, RD_CTRL_WORD = {DEVICE_ADDR, 1'b1};

    localparam IDLE = 7'b000_0001,  // Idle state
    START = 7'b000_0010,  // Start bit reception state
    JUG_RW = 7'b000_0100,  // Read/write command reception state
    RW_ADDR = 7'b000_1000,  // Read or write address reception state
    WR_DAT = 7'b001_0000,  // Write data reception state
    RD_DAT = 7'b010_0000,  // Read data transmission state
    STOP = 7'b100_0000;  // Stop bit reception state

    // Internal wire/reg declarations
    reg [7:0] state_c, state_n;  // State machine signal	
    reg [10:0] cnt_sclk;  // Counter for sampling data during SCLK high
    reg [10:0] cnt_sdai_h;  // Counter for both SCLK and SDA_IN being high

    reg bit_buf;  // Bit buffer for high level counting
    reg	[2:0]	samp_flag		; // Low level, and both counters are non-zero, start counting, reach 3 and hold, reset on rising edge

    reg [3:0] cnt_bit;  // Bit counter
    reg [7:0] cnt_byte;  // Byte counter for read/write operations	
    reg [3:0] RW_Addr;  // Read/write address signal	


    reg [7:0] data_buf;  // Data buffer	
    reg [7:0] mem[15:0];  // 16-byte data storage space

    reg [1:0] r_scl, r_sda;  // Register for edge detection

    wire scl_neg, scl_pos;  // SCLK edges
    wire sda_neg, sda_pos;  // SDA edges

    // State transition conditions
    wire idle2start;
    wire start2jug_rw;
    wire jug_rw2rw_addr;
    wire jug_rw2rd_dat;
    wire jug_rw2idle;
    wire rw_addr2wr_dat;
    wire wr_dat2start;
    wire wr_dat2stop;
    wire rd_dat2stop;
    wire stop2idle;
    reg [31:0] ahb_rdata_i_prev;

    /*+++++++++++++++++++++++++++++++++ahb+++++++++++++++++++++++++++++++++*/
    reg [3:0] RW_Addr_prev;  // Read/write address signal	
    always @(negedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ahb_waddr_o <= 32'h0;
            ahb_raddr_o <= 32'h0;
            r_valid_o   <= 1'b0;
            w_valid_o   <= 1'b0;
            ahb_wdata_o <= 32'h0;
        end else begin
            if (RW_Addr_prev == 4'h7 && RW_Addr == 4'h8) begin
                w_valid_o   <= 1'b1;
                ahb_waddr_o <= {mem[0], mem[1], mem[2], mem[3]};
                ahb_wdata_o <= {mem[4], mem[5], mem[6], mem[7]};
            end else if (RW_Addr == 4'hc && !(ahb_rdata_i == ahb_rdata_i_prev)) begin
                {mem[15], mem[14], mem[13], mem[12]} <= ahb_rdata_i;
            end else if (RW_Addr_prev == 4'hb && RW_Addr == 4'hc) begin
                r_valid_o   <= 1'b1;
                ahb_raddr_o <= {mem[8], mem[9], mem[10], mem[11]};
            end else begin
                ahb_rdata_i_prev <= ahb_rdata_i;
                RW_Addr_prev <= RW_Addr;
                w_valid_o <= 1'b0;
                r_valid_o <= 1'b0;
            end
        end
    end
    /*---------------------------------ahb---------------------------------*/


    // Logic Description		
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_scl <= 2'b0;
            r_sda <= 2'b0;
        end else begin
            r_scl <= {r_scl[0], scl_i};
            r_sda <= {r_sda[0], sda_i};
        end
    end  // always end

    assign scl_neg = r_scl == 2'b10;
    assign scl_pos = r_scl == 2'b01;
    assign sda_neg = r_sda == 2'b10;
    assign sda_pos = r_sda == 2'b01;

    // First segment sets up state transitions
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_c <= IDLE;
        end else begin
            state_c <= state_n;
        end
    end
    // Second segment, combinatorial logic defines state transitions
    always @(*) begin
        case (state_c)
            IDLE: begin
                if (idle2start) begin
                    state_n = START;
                end else begin
                    state_n = IDLE;
                end
            end

            START: begin
                if (start2jug_rw) begin  // Transition when SCLK goes low
                    state_n = JUG_RW;
                end else begin
                    state_n = START;
                end
            end

            JUG_RW: begin
                if (jug_rw2rw_addr) begin
                    state_n = RW_ADDR;
                end else if (jug_rw2rd_dat) begin
                    state_n = RD_DAT;
                end else if (jug_rw2idle) begin  // Incorrect command received
                    state_n = IDLE;
                end else begin
                    state_n = JUG_RW;
                end
            end

            RW_ADDR: begin
                if (rw_addr2wr_dat) begin
                    state_n = WR_DAT;
                end else begin
                    state_n = RW_ADDR;
                end
            end

            WR_DAT: begin
                if (wr_dat2start) begin  // Start bit received
                    state_n = START;
                end else if (wr_dat2stop) begin
                    state_n = STOP;
                end else begin
                    state_n = WR_DAT;
                end
            end

            RD_DAT: begin
                if (rd_dat2stop) begin
                    state_n = STOP;
                end else begin
                    state_n = RD_DAT;
                end
            end
            STOP: begin
                if (stop2idle) begin
                    state_n = IDLE;
                end else begin
                    state_n = STOP;
                end
            end
            default: begin
                state_n = IDLE;
            end
        endcase
    end

    assign idle2start = state_c == IDLE && (sda_neg && scl_i); // Start bit, SDA falling edge during SCLK high
    assign start2jug_rw = state_c == START && (scl_pos);  // Transition on rising edge
    assign jug_rw2rw_addr = state_c == JUG_RW && (cnt_bit == 4'd8 && samp_flag == 3'd1 && data_buf == WR_CTRL_WORD);
    assign jug_rw2rd_dat = state_c == JUG_RW && (cnt_bit == 4'd8 && samp_flag == 3'd1 && data_buf == RD_CTRL_WORD);
    assign jug_rw2idle = state_c == JUG_RW && (cnt_bit == 4'd8 && samp_flag == 3'd1 && data_buf != WR_CTRL_WORD && data_buf != RD_CTRL_WORD);
    assign rw_addr2wr_dat = state_c == RW_ADDR && (cnt_bit == 4'd8 && scl_neg);
    assign wr_dat2start = state_c == WR_DAT && (scl_i && sda_neg); // Start bit, SDA falling edge during SCLK high
    assign wr_dat2stop = state_c == WR_DAT && (scl_i && sda_pos);
    assign rd_dat2stop = state_c == RD_DAT && (cnt_bit == 4'd8 && scl_i && sda_i);  // NACK detected
    assign stop2idle = state_c == STOP && (scl_i && sda_i && cnt_sclk >= 11'd50);  // Wait 1 us

    // Third segment, defines the state machine outputs, can be sequential or combinational logic
    // rw_flag_o
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rw_flag_o <= 1'b0;
        end else if (state_c == RD_DAT) begin
            rw_flag_o <= 1'b1;
        end else begin
            rw_flag_o <= 1'b0;
        end
    end  // always end

    // cnt_sclk
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_sclk   <= 'd0;
            cnt_sdai_h <= 'd0;
        end else if (state_c == IDLE || state_c == START) begin
            cnt_sclk   <= 'd0;
            cnt_sdai_h <= 'd0;
        end  
    else if (state_c == JUG_RW || state_c == RW_ADDR 
           || state_c == WR_DAT /* || state_c == RD_DAT */) begin
            if (scl_pos) begin  // Reset on rising edge
                cnt_sclk   <= 'd0;
                cnt_sdai_h <= 'd0;
            end else if (scl_i) begin  // Count during high level
                cnt_sclk <= cnt_sclk + 11'd1;
                if (sda_i) begin
                    cnt_sdai_h <= cnt_sdai_h + 11'd1;
                end
            end else begin
                cnt_sclk   <= cnt_sclk;
                cnt_sdai_h <= cnt_sdai_h;
            end
        end else if (state_c == STOP) begin
            cnt_sclk <= cnt_sclk + 11'd1;
        end else begin
            cnt_sclk <= 'd0;
        end
    end  // always end

    // samp_flag
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            samp_flag <= 3'd0;
        end else if (scl_pos) begin
            samp_flag <= 3'd0;
        end else if (samp_flag == 3'd7) begin
            samp_flag <= 3'd7;
        end else if (cnt_sclk != 0 && ~scl_i) begin
            samp_flag <= samp_flag + 3'd1;
        end else begin
            samp_flag <= samp_flag;
        end
    end  // always end

    // cnt_bit
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_bit <= 4'd0;
        end else if (state_c == IDLE || state_c == START || state_c == STOP) begin
            cnt_bit <= 4'd0;
        end else if (state_c != IDLE && state_c != START && state_c != STOP) begin
            if (cnt_bit == 4'd8 && scl_neg) begin
                cnt_bit <= 4'd0;
            end else if (scl_neg) begin
                cnt_bit <= cnt_bit + 4'd1;
            end
        end else begin
            cnt_bit <= cnt_bit;
        end
    end  // always end

    // cnt_byte
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_byte <= 5'd0;
        end else if (state_c == IDLE || state_c == START || state_c == STOP) begin
            cnt_byte <= 5'd0;
        end else if ((state_c == WR_DAT || state_c == RD_DAT) && (cnt_bit == 4'd8 && scl_neg)) begin
            cnt_byte <= cnt_byte + 5'd1;
        end else begin
            cnt_byte <= cnt_byte;
        end
    end  // always end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sda_o <= 1'b0;
            sda_oe_o <= 1'b0;
            wr_vld_o <= 1'b0;
            wr_data_o <= 8'd0;
            rd_vld_o <= 1'b0;
            rd_data_o <= 8'd0;
            data_buf <= 8'd0;
            RW_Addr <= 4'd0;
            bit_buf <= 1'b0;
        end else begin
            case (state_c)
                IDLE: begin
                    sda_o <= 1'b0;
                    sda_oe_o <= 1'b0;
                    wr_vld_o <= 1'b0;
                    wr_data_o <= 8'd0;
                    rd_vld_o <= 1'b0;
                    data_buf <= 8'd0;
                    bit_buf <= 1'b0;
                end
                // START:
                JUG_RW: begin
                    if (cnt_bit == 4'd7 && scl_neg) begin
                        sda_o <= 1'b0;
                        sda_oe_o <= 1'b1;  // Take control of the bus, send ACK bit
                    end else if (cnt_bit == 4'd8 && scl_neg) begin
                        if (data_buf == RD_CTRL_WORD) begin
                            sda_o <= 1'b0;
                            sda_oe_o <= 1'b1;  // If read command is received, do not release the bus, slave prepares to send data
                        end else begin
                            sda_o <= 1'b0;
                            sda_oe_o <= 1'b0;  // ACK bit sent, release control of the bus
                        end
                    end else if (cnt_bit <= 4'd8) begin  // Receive data
                        if (cnt_sdai_h != cnt_sclk) begin
                            bit_buf <= 1'b0;
                        end else begin
                            bit_buf <= 1'b1;
                        end
                    end
                    if (scl_neg && cnt_bit < 4'd8) begin
                        data_buf <= {data_buf[6:0], bit_buf};
                    end else begin
                        data_buf <= data_buf;
                    end
                end
                RW_ADDR: begin
                    if (cnt_bit == 4'd7 && scl_neg) begin
                        sda_oe_o <= 1'b1;  // Take control of the bus, send ACK bit
                        sda_o <= 1'b0;
                    end else if (cnt_bit == 4'd8 && scl_neg) begin
                        sda_oe_o <= 1'b0;  // ACK bit sent, release control of the bus
                        sda_o <= 1'b0;
                        RW_Addr <= data_buf[3:0];  // Assign address
                    end else if (cnt_bit <= 4'd8) begin  // Receive data
                        if (cnt_sdai_h == cnt_sclk) begin
                            bit_buf <= 1'b1;
                        end else begin
                            bit_buf <= 1'b0;
                        end
                    end
                    if (scl_neg && cnt_bit < 4'd8) begin
                        data_buf <= {data_buf[6:0], bit_buf};
                    end else begin
                        data_buf <= data_buf;
                    end
                end
                WR_DAT: begin
                    if (cnt_bit == 4'd7 && scl_neg) begin
                        sda_oe_o <= 1'b1;  // Take control of the bus, send ACK bit
                        sda_o <= 1'b0;
                    end else if (cnt_bit == 4'd8 && scl_neg) begin
                        sda_oe_o <= 1'b0;  // ACK bit sent, release control of the bus
                        sda_o <= 1'b0;
                        RW_Addr <= RW_Addr + 4'd1;  // Increment write address by 1 after writing 1 byte of data
                        wr_vld_o <= 1'b1;
                        mem[RW_Addr] <= data_buf;  // Write data
                        wr_data_o <= data_buf;
                    end else if (cnt_bit <= 4'd8) begin  // Receive data
                        if (cnt_sdai_h == cnt_sclk) begin
                            bit_buf <= 1'b1;
                        end else begin
                            bit_buf <= 1'b0;
                        end
                    end
                    if (scl_neg && cnt_bit < 4'd8) begin
                        data_buf <= {data_buf[6:0], bit_buf};
                    end else begin
                        wr_vld_o <= 1'b0;
                        data_buf <= data_buf;
                    end
                end
                RD_DAT: begin
                    data_buf  <= mem[RW_Addr];
                    rd_data_o <= data_buf;  // Transmit read data
                    if (cnt_bit == 4'd7 && scl_neg) begin
                        sda_oe_o <= 1'b0;  // Release control of the bus
                        sda_o <= 1'b0;
                    end else if (cnt_bit == 4'd8 && scl_neg) begin
                        sda_oe_o <= 1'b1;  // Take control of the bus
                        RW_Addr  <= RW_Addr + 4'd1;  // Increment read address by 1 after reading 1 byte of data
                        cnt_byte <= cnt_byte + 5'd1;
                        rd_vld_o <= 1'b1;
                    end else if (~scl_i && cnt_bit < 4'd8) begin  // Send data
                        sda_oe_o <= 1'b1;
                        sda_o <= data_buf[7-cnt_bit];
                    end else begin
                        rd_vld_o <= 1'b0;
                    end
                end
                // STOP:
                default: ;
            endcase
        end
    end  // always end

endmodule
