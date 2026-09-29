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

    // The slave side of the bus comes from the RTL slave below (default),
    // the coverage emulation block (+apb_slave=cov) or the slave agent's
    // driver (+apb_slave=mem|seq, see tb/env/cc.sv): one continuous driver
    // per signal, no tristates.
    logic        dut_pready, dut_pslverr, emu_pready, emu_pslverr;
    logic [31:0] dut_prdata, emu_prdata;
    int          slave_src = 0;     // 0 = dut, 1 = cov block, 2 = slave agent
    string       slave_sel;
    initial if ($value$plusargs("apb_slave=%s", slave_sel))
        slave_src = (slave_sel == "dut") ? 0 : (slave_sel == "cov") ? 1 : 2;
    assign apb_if.pready  = (slave_src == 0) ? dut_pready  : (slave_src == 1) ? emu_pready  : apb_if.s_pready;
    assign apb_if.prdata  = (slave_src == 0) ? dut_prdata  : (slave_src == 1) ? emu_prdata  : apb_if.s_prdata;
    assign apb_if.pslverr = (slave_src == 0) ? dut_pslverr : (slave_src == 1) ? emu_pslverr : apb_if.s_pslverr;

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

    // Functional-coverage emulation backend as a second APB slave. With
    // FCOV=1 it is sized from the generated model and fed every hit of the
    // package store (odve_cov_emu_feed); without, an unfed slave.
    logic        smp_valid;
    logic [31:0] smp_idx;
`ifdef ODVE_FCOV
    odve_cov_emu_feed cov_feed_i (.clk(clk), .rst_n(rst_n), .smp_valid(smp_valid), .smp_idx(smp_idx));
    odve_cov_emu #(.N(odve_cov_pkg::N), .W(odve_cov_pkg::W)) cov_emu_i (
`else
    assign smp_valid = 1'b0;
    assign smp_idx   = '0;
    odve_cov_emu cov_emu_i (
`endif
        .clk       (clk),
        .rst_n     (rst_n),
        .smp_valid (smp_valid),
        .smp_idx   (smp_idx),
        .psel      (apb_if.psel),
        .penable   (apb_if.penable),
        .pwrite    (apb_if.pwrite),
        .paddr     (apb_if.paddr),
        .pwdata    (apb_if.pwdata),
        .pready    (emu_pready),
        .prdata    (emu_prdata),
        .pslverr   (emu_pslverr)
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
