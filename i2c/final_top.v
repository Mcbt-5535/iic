//~ `New testbench
`timescale 1ns / 1ps

module final_top;

    // soft_iic_slave Parameters
    parameter PERIOD = 10;


    // soft_iic_slave Inputs
    reg  clk_i = 0;
    reg  rst_ni = 0;
    wire SDA;
    wire SCL;

    initial begin
        forever #(PERIOD / 2) clk_i = ~clk_i;
    end

    initial begin
        #10000;
        #(PERIOD * 2) rst_ni = 1;
    end

    master u_master (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .SDA   (SDA),
        .SCL   (SCL)
    );

    slave u_slave (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .SDA   (SDA),
        .SCL   (SCL)
    );


    initial begin
        #600000;
        $finish;
    end

endmodule

module master (
    input  clk_i,
    input  rst_ni,
    inout  SDA,
    output SCL
);
    wire sda_i;
    wire sda_o;
    wire sda_oe_o;

    assign SDA   = sda_oe_o ? sda_o : 1'bz;
    assign sda_i = sda_oe_o ? 1'bz : SDA;

    soft_i2c_master u_soft_i2c_master (
        .rst_ni(rst_ni),
        .clk_i (clk_i),
        .sda_i (sda_i),

        .scl_o   (SCL),
        .sda_o   (sda_o),
        .scl_oe_o(),
        .sda_oe_o(sda_oe_o)
    );
endmodule

module slave (
    input clk_i,
    input rst_ni,
    inout SDA,
    input SCL
);
    wire sda_i;
    wire sda_o;
    wire sda_oe_o;
    wire rw_flag;
    wire Wr_vld;
    wire [07:00] Wr_data;
    wire Rd_vld;
    wire [07:00] Rd_data;
    assign SDA   = sda_oe_o ? sda_o : 1'bz;
    assign sda_i = sda_oe_o ? 1'bz : SDA;

    soft_i2c_slave #(
        .DEVICE_ADDR(7'h66)
    ) u_soft_i2c_slave (
        .Clk   (clk_i),
        .Rst_n (rst_ni),
        .Sclk  (SCL),
        .Sda_in(sda_i),

        .Sda_oe (sda_oe_o),
        .Sda_o  (sda_o),
        .rw_flag(rw_flag),
        .Wr_vld (Wr_vld),
        .Wr_data(Wr_data),
        .Rd_vld (Rd_vld),
        .Rd_data(Rd_data)
    );
endmodule
