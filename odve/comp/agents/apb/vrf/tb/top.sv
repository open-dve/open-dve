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

    odve_apb_if apb_if (.clk(clk), .rst_n(rst_n));

    // The slave side of the bus comes from the RTL slave below (default) or
    // from the slave agent's driver (+apb_slave=mem|seq, see tb/env/cc.sv):
    // one continuous driver per signal, no tristates.
    logic        dut_pready, dut_pslverr;
    logic [31:0] dut_prdata;
    bit          use_dut = 1'b1;
    string       slave_sel;
    initial if ($value$plusargs("apb_slave=%s", slave_sel)) use_dut = (slave_sel == "dut");
    assign apb_if.pready  = use_dut ? dut_pready  : apb_if.s_pready;
    assign apb_if.prdata  = use_dut ? dut_prdata  : apb_if.s_prdata;
    assign apb_if.pslverr = use_dut ? dut_pslverr : apb_if.s_pslverr;

    dut dut_i (
        .clk     (clk),
        .rst_n   (rst_n),
        .psel    (apb_if.psel),
        .penable (apb_if.penable),
        .pwrite  (apb_if.pwrite),
        .paddr   (apb_if.paddr),
        .pwdata  (apb_if.pwdata),
        .pready  (dut_pready),
        .prdata  (dut_prdata),
        .pslverr (dut_pslverr)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial repeat (1) $display ("Hello From TB");
    initial begin
        uvm_config_db #(virtual odve_apb_if)::set(null, "*", "vif", apb_if);
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", read_test::type_id::get());
        run_test("read_test");
    end
endmodule
