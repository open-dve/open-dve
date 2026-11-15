module top;
    import uvm_pkg::*;
    import env_pkg::*;
    import test_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    odve_i2c_if i2c_if (.clk(clk), .rst_n(rst_n));

    // The target is the RTL below (default) or the slave agent
    // (+i2c_slave=mem|seq, see tb/env/cc.sv). Open drain: the DUT's pulls
    // reach the bus only when it is selected.
    bit    dut_en = 1'b1;
    string slave_sel;
    initial if ($value$plusargs("i2c_slave=%s", slave_sel)) dut_en = (slave_sel == "dut");

    logic dut_scl_o, dut_scl_oe, dut_sda_o, dut_sda_oe;
    assign i2c_if.d_scl_o  = dut_scl_o;
    assign i2c_if.d_scl_oe = dut_en & dut_scl_oe;
    assign i2c_if.d_sda_o  = dut_sda_o;
    assign i2c_if.d_sda_oe = dut_en & dut_sda_oe;

    dut #(.ADDR7(TGT_ADDR7), .ADDR10(TGT_ADDR10)) dut_i (
        .clk    (clk),
        .rst_n  (rst_n),
        .scl_i  (i2c_if.scl),
        .sda_i  (i2c_if.sda),
        .scl_o  (dut_scl_o),
        .scl_oe (dut_scl_oe),
        .sda_o  (dut_sda_o),
        .sda_oe (dut_sda_oe)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_i2c_if)::set(null, "*", "vif", i2c_if);
        run_test("i2c_basic_test");
    end
endmodule
