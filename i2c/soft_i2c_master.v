module soft_i2c_master (
    input      rst_ni,
    input      clk_i,
    // inout
    output     scl_o,     //r_io0
    input      sda_i,     //r_io1
    output reg sda_o,
    output     scl_oe_o,
    output reg sda_oe_o
);
    //--------------------------------USER CODE BEGIN-------------------------------------
    localparam SLAVE_DEVICE_ADDR = 7'h66;

    localparam WIDTH_I2C_CMD = 20;
    localparam IIC_READ0 = 20'd0;
    localparam IIC_READ1 = 20'd100;
    localparam IIC_WRITE0 = 20'd200;
    localparam IIC_READ2 = 20'd300;


    localparam IDLE = 3'h0;
    localparam READ = 3'h1;
    localparam WRITE = 3'h2;
    localparam START = 3'h3;
    localparam STOP = 3'h4;


    reg [              7:0] data_i2c_w;
    reg [              7:0] data_i2c_r;
    reg [              2:0] flg_i2c;
    reg                     flg_nack;
    reg [WIDTH_I2C_CMD-1:0] i2c_command;

    always @(posedge clk_i or negedge rst_ni) begin : i2c_command_change
        if (!rst_ni) begin
            data_i2c_w <= 8'h0;
            flg_i2c <= IDLE;
            flg_nack <= 1'b0;
        end else begin
            case (i2c_command)
                IIC_READ0 + 0: begin
                    flg_i2c <= START;
                    data_i2c_w <= {7'h1a, 1'b0};  // device address
                end
                IIC_READ0 + 1: begin
                    flg_i2c <= WRITE;
                    data_i2c_w <= 8'h01;
                end
                IIC_READ0 + 2: begin
                    flg_i2c <= START;
                    data_i2c_w <= {7'h1a, 1'b1};  // device address
                end
                IIC_READ0 + 3: begin
                    flg_i2c  <= READ;
                    flg_nack <= 1'b1;
                end


                IIC_READ1 + 0: begin
                    flg_i2c <= START;
                    data_i2c_w <= {SLAVE_DEVICE_ADDR, 1'b0};  // device address
                end
                IIC_READ1 + 1: begin
                    flg_i2c <= WRITE;
                    data_i2c_w <= 8'h01;
                end
                IIC_READ1 + 2: begin
                    flg_i2c <= START;
                    data_i2c_w <= {SLAVE_DEVICE_ADDR, 1'b1};  // device address
                end
                IIC_READ1 + 3: begin
                    flg_i2c  <= READ;
                    flg_nack <= 1'b1;
                end


                IIC_WRITE0 + 0: begin
                    flg_i2c <= START;
                    data_i2c_w <= {SLAVE_DEVICE_ADDR, 1'b0};  // device address & write
                end
                IIC_WRITE0 + 1: begin
                    flg_i2c <= WRITE;
                    data_i2c_w <= 8'h01;  //addr
                end
                IIC_WRITE0 + 2: data_i2c_w <= 8'ha5;  //data
                IIC_WRITE0 + 3: flg_i2c <= STOP;


                IIC_READ2 + 0: begin
                    flg_i2c <= START;
                    data_i2c_w <= {SLAVE_DEVICE_ADDR, 1'b0};  // device address
                end
                IIC_READ2 + 1: begin
                    flg_i2c <= WRITE;
                    data_i2c_w <= 8'h01;
                end
                IIC_READ2 + 2: begin
                    flg_i2c <= START;
                    data_i2c_w <= {SLAVE_DEVICE_ADDR, 1'b1};  // device address
                end
                IIC_READ2 + 3: begin
                    flg_i2c  <= READ;
                    flg_nack <= 1'b1;
                end

                default: begin
                    flg_nack <= 1'b0;
                    data_i2c_w <= 8'h0;
                    flg_i2c <= IDLE;
                end
            endcase
        end
    end
    //--------------------------------USER CODE END-------------------------------------

    //--------------------------------IIC MASTER BEGIN-------------------------------------

    localparam I2C_FSM_IDLE = 3'h0;
    localparam I2C_FSM_START = 3'h1;
    localparam I2C_FSM_DATA = 3'h2;
    localparam I2C_FSM_ACK = 3'h3;
    localparam I2C_FSM_STOP = 3'h4;


    reg [6:0] cnt_clkdiv;
    reg cnt_div_last;
    reg sda_change;
    reg [2:0] fsm_i2c;
    reg [3:0] cnt_byte_i2c;
    reg scl_prev;
    reg sda_prev;

    assign scl_oe_o = 1'b1;
    assign scl_o = (fsm_i2c == I2C_FSM_IDLE) ? 1'b1 : cnt_clkdiv[6];
    // scl_o generate

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) cnt_clkdiv <= 6'h0;
        else cnt_clkdiv <= cnt_clkdiv + 1;
    end

    // sda only read/write at the middle of scl_o

    always @(negedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_div_last <= 1'b0;
            sda_change   <= 1'b0;
        end else begin
            if (!cnt_div_last && cnt_clkdiv[5]) begin
                sda_change   <= 1'b1;
                cnt_div_last <= cnt_clkdiv[5];
            end else begin
                sda_change   <= 1'b0;
                cnt_div_last <= cnt_clkdiv[5];
            end
        end
    end

    // SCL edge detection (in the clk_i clock domain)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            scl_prev <= 1'b1;  // Assume initial high level on SCL
            sda_prev <= 1'b1;  // Assume initial high level on SDA
        end else begin
            scl_prev <= scl_o;  // Record current SCL state
            sda_prev <= sda_o;  // Record current SDA state
        end
    end


    // IIC Master
    always @(posedge clk_i or negedge rst_ni) begin : i2c_master_fsm
        if (!rst_ni) begin
            sda_o <= 1'b1;
            sda_oe_o <= 1'b0;
            fsm_i2c <= I2C_FSM_IDLE;
            cnt_byte_i2c <= 3'h7;
            i2c_command <= {WIDTH_I2C_CMD{1'b0}};
        end else begin
            if (sda_change) begin
                case (fsm_i2c)
                    I2C_FSM_IDLE: begin
                        sda_oe_o <= 1'b1;
                        sda_o <= 1'b1;
                        if (flg_i2c == IDLE) begin
                            fsm_i2c <= I2C_FSM_IDLE;
                            i2c_command <= i2c_command + 1;
                        end else fsm_i2c <= I2C_FSM_START;
                    end
                    I2C_FSM_START: begin
                        if (scl_o) begin
                            sda_oe_o <= 1'b1;
                            sda_o <= 1'b0;
                            cnt_byte_i2c <= 3'h7;
                            fsm_i2c <= I2C_FSM_DATA;
                        end else begin
                            sda_o <= sda_o;
                        end
                    end
                    I2C_FSM_DATA: begin
                        if (flg_i2c == READ) begin  //read
                            sda_oe_o <= 1'b0;
                            if (scl_o) begin
                                data_i2c_r[cnt_byte_i2c] <= sda_i;
                                cnt_byte_i2c <= cnt_byte_i2c - 1;
                            end else begin
                                if (cnt_byte_i2c[3]) begin
                                    i2c_command  <= i2c_command + 1;
                                    cnt_byte_i2c <= 3'h7;
                                    if (flg_nack) begin
                                        fsm_i2c <= I2C_FSM_STOP;
                                        sda_oe_o <= 1'b1;
                                        sda_o <= 1'b0;
                                    end else fsm_i2c <= I2C_FSM_ACK;
                                end else begin
                                    sda_o <= sda_o;
                                end
                            end
                        end else begin  //write
                            if (!scl_o) begin
                                sda_oe_o <= 1'b1;
                                if (cnt_byte_i2c[3]) begin
                                    i2c_command  <= i2c_command + 1;
                                    cnt_byte_i2c <= 3'h7;
                                    if (flg_nack) begin
                                        fsm_i2c <= I2C_FSM_STOP;
                                        sda_oe_o <= 1'b1;
                                        sda_o <= 1'b0;
                                    end else begin
                                        fsm_i2c  <= I2C_FSM_ACK;
                                        sda_oe_o <= 1'b0;
                                    end
                                end else begin
                                    sda_o <= data_i2c_w[cnt_byte_i2c];
                                    cnt_byte_i2c <= cnt_byte_i2c - 1;
                                end
                            end else begin
                                sda_o <= sda_o;
                            end
                        end
                    end
                    I2C_FSM_ACK: begin
                        if (scl_o == 1'b1) begin  //Read when posedge of scl 
                            if (sda_i === 1'b0) begin  //ACK = 0(ACK)
                                if (flg_i2c == START) begin
                                    fsm_i2c  <= I2C_FSM_START;
                                    sda_oe_o <= 1'b1;
                                end else if (flg_i2c == STOP) begin
                                    fsm_i2c  <= I2C_FSM_STOP;
                                    sda_oe_o <= 1'b1;
                                end else begin
                                    fsm_i2c <= I2C_FSM_DATA;
                                end
                            end else begin  //ACK = 1(NACK)
                                fsm_i2c  <= I2C_FSM_STOP;
                                sda_oe_o <= 1'b1;
                            end
                        end else begin
                            fsm_i2c <= fsm_i2c;
                        end
                    end
                    I2C_FSM_STOP: begin
                        if (scl_o) begin
                            sda_o <= 1'b1;
                            cnt_byte_i2c <= 3'h7;
                            fsm_i2c <= I2C_FSM_IDLE;
                        end else begin
                            sda_oe_o <= 1'b1;
                            sda_o <= 1'b0;
                        end
                    end
                    default: sda_o <= sda_o;
                endcase
            end
        end
    end
    //--------------------------------IIC MASTER END-------------------------------------
endmodule
