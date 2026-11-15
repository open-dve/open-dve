module top;
    import uvm_pkg::*;
    import test_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;          // the agents start when it rises
    logic por_n = 1'b1;          // power-on reset of the RTL TAPs
    always #5 clk = ~clk;
    // por_n falls at 1 ns: the TAPs' asynchronous reset needs a real falling
    // edge (Verilator has no X -> 0 edge at time 0, so a reset that is simply
    // low from the start would never be seen and the IR would come up 0000).
    initial begin
        #1 por_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        por_n = 1'b1;
    end

    odve_jtag_if jtag_if (.clk(clk), .rst_n(rst_n));

    // The target side comes from the single-TAP RTL DUT (default), the
    // two-TAP daisy chain (+jtag_slave=chain) or the slave agent's driver
    // (+jtag_slave=mem|seq, see tb/env/cc.sv): one continuous driver per
    // signal, no tristates. Nobody enabled -> TDO reads 1 (pull-up).
    logic       dut_tdo, dut_tdo_oe, chain_tdo, chain_tdo_oe;
    logic [3:0] dut_state, chain_state;
    logic [7:0] dut_pins;
    logic [15:0] chain_pins;
    int         slave_src = 0;    // 0 = dut, 1 = chain, 2 = slave agent
    string      slave_sel;
    initial if ($value$plusargs("jtag_slave=%s", slave_sel))
        slave_src = (slave_sel == "dut") ? 0 : (slave_sel == "chain") ? 1 : 2;

    logic tdo_val;
    assign tdo_val           = (slave_src == 0) ? dut_tdo    : (slave_src == 1) ? chain_tdo    : jtag_if.s_tdo;
    assign jtag_if.tdo_oe    = (slave_src == 0) ? dut_tdo_oe : (slave_src == 1) ? chain_tdo_oe : jtag_if.s_tdo_oe;
    assign jtag_if.tdo       = jtag_if.tdo_oe ? tdo_val : 1'b1;
    assign jtag_if.dbg_state = (slave_src == 1) ? chain_state : dut_state;

    dut #(.NTAP(1)) dut_i (
        .tck     (jtag_if.tck),
        .tms     (jtag_if.tms),
        .tdi     (jtag_if.tdi),
        .trst_n  (jtag_if.trst_n),
        .por_n   (por_n),
        .tdo     (dut_tdo),
        .tdo_oe  (dut_tdo_oe),
        .pins_o  (dut_pins),
        .state_o (dut_state)
    );

    dut #(.NTAP(2)) chain_i (
        .tck     (jtag_if.tck),
        .tms     (jtag_if.tms),
        .tdi     (jtag_if.tdi),
        .trst_n  (jtag_if.trst_n),
        .por_n   (por_n),
        .tdo     (chain_tdo),
        .tdo_oe  (chain_tdo_oe),
        .pins_o  (chain_pins),
        .state_o (chain_state)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial repeat (1) $display ("Hello From TB");
    initial begin
        uvm_config_db #(virtual odve_jtag_if)::set(null, "*", "vif", jtag_if);
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", idcode_test::type_id::get());
        run_test("idcode_test");
    end
endmodule
