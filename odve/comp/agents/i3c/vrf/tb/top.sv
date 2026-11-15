module top;
    import uvm_pkg::*;
    import test_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    odve_i3c_if i3c_if (.clk(clk), .rst_n(rst_n));

    // The RTL target is on the bus for +i3c_target=dut|both (default dut).
    // Its SDA enable is gated here, so with the target agent alone the DUT
    // sees the bus but never drives it. Bus resolution (pull-up, open-drain
    // lows, push-pull highs) is plain logic inside the interface - no inout.
    bit    dut_en = 1'b1;
    string tsel;
    initial if ($value$plusargs("i3c_target=%s", tsel)) dut_en = (tsel == "dut" || tsel == "both");

    logic       dut_sda_o, dut_sda_oe, dut_sda_pp, dut_ibi_pending, dut_has_da;
    logic [6:0] dut_da;
    assign i3c_if.d_sda_oe = dut_en & dut_sda_oe;
    assign i3c_if.d_sda_o  = dut_sda_o;
    assign i3c_if.d_sda_pp = dut_en & dut_sda_pp;

    dut #(
        .PID         (env_pkg::DUT_PID),
        .BCR         (env_pkg::DUT_BCR),
        .DCR         (env_pkg::DUT_DCR),
        .STATIC_ADDR (env_pkg::DUT_SA),
        .NREG        (env_pkg::NREGS)
    ) dut_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .scl_i       (i3c_if.scl),
        .sda_i       (i3c_if.sda),
        .sda_o       (dut_sda_o),
        .sda_oe      (dut_sda_oe),
        .sda_pp      (dut_sda_pp),
        .ibi_req     (i3c_if.d_ibi_req),
        .ibi_mdb     (i3c_if.d_ibi_mdb),
        .ibi_pending (dut_ibi_pending),
        .has_da      (dut_has_da),
        .da          (dut_da)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial repeat (1) $display ("Hello From TB");
    initial begin
        uvm_config_db #(virtual odve_i3c_if)::set(null, "*", "vif", i3c_if);
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", daa_test::type_id::get());
        run_test("daa_test");
    end
endmodule
