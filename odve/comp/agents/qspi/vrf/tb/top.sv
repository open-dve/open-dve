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

    odve_qspi_if qspi_if (.clk(clk), .rst_n(rst_n));

    // Who is the flash (see tb/env/cc.sv): the RTL flash below
    // (+qspi_slave=dut, default) or the slave agent (+qspi_slave=mem|seq);
    // with the agent the RTL flash is kept deselected, so it never drives io.
    // io itself is resolved in odve_qspi_if from the value/enable pairs.
    int    slave_src = 0;     // 0 = dut, 1 = slave agent
    string slave_sel;
    initial if ($value$plusargs("qspi_slave=%s", slave_sel)) slave_src = (slave_sel == "dut") ? 0 : 1;

    dut dut_i (
        .clk   (clk),
        .rst_n (rst_n),
        .sclk  (qspi_if.sclk),
        .cs_n  (slave_src == 0 ? qspi_if.cs_n : 1'b1),
        .io_i  (qspi_if.io),
        .io_o  (qspi_if.d_io),
        .io_oe (qspi_if.d_io_oe)
    );

    // the slave agent's drive stays off unless there is one
    initial begin
        qspi_if.s_io    = '1;
        qspi_if.s_io_oe = '0;
    end

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_qspi_if)::set(null, "*", "vif", qspi_if);
        run_test("read_test");
    end
endmodule
