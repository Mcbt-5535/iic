/* i2c master ahb wrapper */
module soft_i2c_master_ahb_wrapper (
    input  clk_i,
    input  rst_ni,
    inout  SDA,
    output SCL
);
    wire sda_i;
    wire sda_o;
    wire sda_oe_o;
    wire [31:0] ahb_rdata;
    wire ahb_rvaild;
    assign SDA   = sda_oe_o ? sda_o : 1'bz;
    assign sda_i = sda_oe_o ? 1'bz : SDA;
    soft_i2c_master_ahb u_soft_i2c_master_ahb (
        .rst_ni(rst_ni),
        .clk_i(clk_i),
        .sda_i(sda_i),
        .scl_o(SCL),
        .sda_o(sda_o),
        .scl_oe_o(),
        .sda_oe_o(sda_oe_o),
        .ahb_waddr_i(32'h03000018), // AHB_WADDR
        .ahb_raddr_i(32'h03000018), // AHB_RADDR
        .ahb_wdata_i(32'h12345678), // AHB_WDATA
        .ahb_rdata_o(ahb_rdata),    // AHB_RDATA
        .ahb_r_vaild_o(ahb_rvaild)  // AHB_RVALID
    );
endmodule

module i2c_slave_and_ahb_master ();

    wire rw_flag_o;
    wire wr_vld_o;
    wire [7:0] wr_data_o;
    wire rd_vld_o;
    wire [7:0] rd_data_o;
    wire [31:0] ahb_waddr;
    wire [31:0] ahb_raddr;
    wire r_valid;
    wire w_valid;
    wire [31:0] ahb_wdata;
    wire [31:0] ahb_rdata;
    soft_i2c_slave_ahb #(
        .DEVICE_ADDR(7'h66)
    ) u_soft_i2c_slave_ahb (
        .clk_i      (),
        .rst_ni     (),
        /* i2c */
        .scl_i      (),
        .sda_i      (),
        .sda_oe_o   (),
        .sda_o      (),
        /* user */
        .rw_flag_o  (rw_flag_o),
        .wr_vld_o   (wr_vld_o),
        .wr_data_o  (wr_data_o),
        .rd_vld_o   (rd_vld_o),
        .rd_data_o  (rd_data_o),
        /* to ahb master*/
        .ahb_waddr_o(ahb_waddr),
        .ahb_raddr_o(ahb_raddr),
        .r_valid_o  (r_valid),
        .w_valid_o  (w_valid),
        .ahb_wdata_o(ahb_wdata),
        .ahb_rdata_i(ahb_rdata)
    );

    AHB_master_wrapper u_AHB_master_wrapper (
        /* input */
        .HCLK       (),
        .HRESETN    (),
        .HRDATA     (),
        .HREADYOUT  (),
        .HRESP      (),
        /* output */
        .HWDATA     (),
        .HADDR      (),
        .HADDR_26b  (),
        .HBURST     (),
        .HSIZE      (),
        .HWRITE     (),
        .HTRANS     (),
        .HMASTLOCK  (),
        .HPROT      (),
        .HREADY     (),
        .HSEL       (),
        /* user */
        .ahb_waddr_i(ahb_waddr),
        .ahb_raddr_i(ahb_raddr),
        .r_valid_i  (r_valid),
        .w_valid_i  (w_valid),
        .ahb_wdata_i(ahb_wdata),
        .ahb_rdata_o(ahb_rdata)
    );
endmodule
