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

    odve_uart_if uart_if (.clk(clk), .rst_n(rst_n));
    uart_tb_if   tb_if   (.clk(clk), .rst_n(rst_n));

    // tb_if.lcr / div / afe are written by the env (env::apply_format).

    // Who answers the master: the RTL echo device (default) or the slave
    // agent (+uart_slave=mem|seq, see tb/env/cc.sv). One continuous driver
    // per line, no tristates.
    logic  dut_txd, dut_rts_n;
    int    slave_src = 0;     // 0 = dut, 1 = slave agent
    string slave_sel;
    initial if ($value$plusargs("uart_slave=%s", slave_sel))
        slave_src = (slave_sel == "dut") ? 0 : 1;
    assign uart_if.rxd   = (slave_src == 0) ? dut_txd   : uart_if.s_rxd;
    assign uart_if.cts_n = (slave_src == 0) ? dut_rts_n : uart_if.s_cts_n;

    dut #(.DEPTH(8)) dut_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .lcr      (tb_if.lcr),
        .div      (tb_if.div),
        .afe      (tb_if.afe),
        .rxd      (uart_if.txd),
        .txd      (dut_txd),
        .cts_n    (uart_if.rts_n),
        .rts_n    (dut_rts_n),
        .st_valid (tb_if.st_valid),
        .st_oe    (tb_if.st_oe),
        .st_pe    (tb_if.st_pe),
        .st_fe    (tb_if.st_fe),
        .st_bi    (tb_if.st_bi),
        .rx_level (tb_if.rx_level)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_uart_if)::set(null, "*", "vif", uart_if);
        uvm_config_db #(virtual uart_tb_if)::set(null, "*", "vtb", tb_if);
        run_test("basic_test");
    end
endmodule
