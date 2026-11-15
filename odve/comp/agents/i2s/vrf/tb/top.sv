// Two I2S buses around the DUT (an I2S receive -> swap/negate -> I2S
// transmit pipeline, vrf/dut/dut.sv):
//   port A  a_if: transmitter agent -> DUT receiver (or receiver agent)
//   port B  b_if: DUT transmitter -> receiver agent
// Every line has one driver at a time: the agent's a_* or the DUT's d_*
// group, picked by their output enables inside odve_i2s_if; the env sets
// the DUT's configuration pins (dut_cfg_if) for the scenario.
module top;
    import uvm_pkg::*;
    import test_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;          // 100 MHz system clock; SCK is derived (T = 160 ns by default)
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    odve_i2s_if a_if (.clk(clk), .rst_n(rst_n));
    odve_i2s_if b_if (.clk(clk), .rst_n(rst_n));
    dut_cfg_if  dcfg ();

    assign a_if.mclk = clk;
    assign b_if.mclk = clk;

    // the DUT never transmits on port A
    assign a_if.d_sd    = 1'b0;
    assign a_if.d_sd_oe = 1'b0;

    dut dut_i (
        .clk           (clk),
        .rst_n         (rst_n),
        .cfg_fmt       (dcfg.fmt),
        .cfg_wlen      (dcfg.wlen),
        .cfg_slot32    (dcfg.slot32),
        .cfg_nslots    (dcfg.nslots),
        .cfg_rx_master (dcfg.rx_master),
        .cfg_tx_master (dcfg.tx_master),
        .cfg_half      (dcfg.half),
        .a_sck_i       (a_if.sck),
        .a_ws_i        (a_if.ws),
        .a_sd_i        (a_if.sd),
        .a_sck_o       (a_if.d_sck),
        .a_ws_o        (a_if.d_ws),
        .a_clk_oe      (a_if.d_clk_oe),
        .b_sck_i       (b_if.sck),
        .b_ws_i        (b_if.ws),
        .b_sck_o       (b_if.d_sck),
        .b_ws_o        (b_if.d_ws),
        .b_clk_oe      (b_if.d_clk_oe),
        .b_sd_o        (b_if.d_sd),
        .b_sd_oe       (b_if.d_sd_oe),
        .cnt_rx        (),
        .cnt_tx        (),
        .cnt_overrun   ()
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_i2s_if)::set(null, "*", "a_vif", a_if);
        uvm_config_db #(virtual odve_i2s_if)::set(null, "*", "b_vif", b_if);
        uvm_config_db #(virtual dut_cfg_if)::set(null, "*", "dcfg", dcfg);
        run_test("i2s_std_test");
    end
endmodule
