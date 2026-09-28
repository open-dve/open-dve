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

    dut dut_i (
        .clk     (clk),
        .rst_n   (rst_n),
        .psel    (apb_if.psel),
        .penable (apb_if.penable),
        .pwrite  (apb_if.pwrite),
        .paddr   (apb_if.paddr),
        .pwdata  (apb_if.pwdata),
        .pready  (apb_if.pready),
        .prdata  (apb_if.prdata),
        .pslverr (apb_if.pslverr)
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
