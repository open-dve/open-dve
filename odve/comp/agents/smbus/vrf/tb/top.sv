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

    odve_i2c_if   i2c_if   (.clk(clk), .rst_n(rst_n));   // SMBCLK / SMBDAT
    odve_smbus_if smbus_if (.clk(clk), .rst_n(rst_n));   // SMBALERT#

    // The device is the RTL below (default) or the slave agent
    // (+smbus_slave=mem|seq, tb/env/cc.sv); open drain, so the DUT is
    // simply disconnected when not selected.
    bit    dut_en = 1'b1;
    string slave_sel;
    initial if ($value$plusargs("smbus_slave=%s", slave_sel)) dut_en = (slave_sel == "dut");

    logic dut_scl_o, dut_scl_oe, dut_sda_o, dut_sda_oe, dut_alert_o, dut_alert_oe;
    assign i2c_if.d_scl_o       = dut_scl_o;
    assign i2c_if.d_scl_oe      = dut_en & dut_scl_oe;
    assign i2c_if.d_sda_o       = dut_sda_o;
    assign i2c_if.d_sda_oe      = dut_en & dut_sda_oe;
    assign smbus_if.d_alert_o   = dut_alert_o;
    assign smbus_if.d_alert_oe  = dut_en & dut_alert_oe;

    dut #(.ADDR(DEV_ADDR), .TMO_CYC(DEV_TMO)) dut_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl_i    (i2c_if.scl),
        .sda_i    (i2c_if.sda),
        .scl_o    (dut_scl_o),
        .scl_oe   (dut_scl_oe),
        .sda_o    (dut_sda_o),
        .sda_oe   (dut_sda_oe),
        .alert_o  (dut_alert_o),
        .alert_oe (dut_alert_oe)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_i2c_if)::set(null, "*", "i2c_vif", i2c_if);
        uvm_config_db #(virtual odve_smbus_if)::set(null, "*", "smbus_vif", smbus_if);
        run_test("smbus_proto_test");
    end
endmodule
