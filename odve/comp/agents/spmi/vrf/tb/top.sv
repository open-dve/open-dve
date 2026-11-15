// SPMI testbench top: one master (the agent) and two slaves on one bus.
//   primary slave, SID 5:   the RTL slave dut_i (default) or the slave agent
//                           (+spmi_slave=mem|seq, tb/env/cc.sv)
//   secondary slave, SID A: always the RTL slave dut2_i (address filtering
//                           between several slaves)
// SDATA is resolved here from the drivers' explicit output enables (no
// inout/tri): the enabled driver wins, an undriven line keeps its last value
// (bus keeper, 0 after every bus park). The primary DUT's enable is cut off
// the line when the slave agent takes its place.
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

    odve_spmi_if spmi_if (.clk(clk), .rst_n(rst_n));

    localparam logic [3:0] SID_PRIM = 4'h5;
    localparam logic [3:0] SID_SEC  = 4'hA;
    logic [1:0] pm0, pm1;           // the RTL slaves' power states (also readable at 0x40)

    int    slave_src = 0;     // 0 = dut_i, 1 = slave agent
    string slave_sel;
    initial if ($value$plusargs("spmi_slave=%s", slave_sel)) slave_src = (slave_sel == "dut") ? 0 : 1;

    logic d0_o, d0_oe, d1_o, d1_oe;
    logic keep;
    wire  d0_oe_bus = (slave_src == 0) && (d0_oe === 1'b1);
    wire  s_oe_bus  = (slave_src != 0) && (spmi_if.s_sdata_oe === 1'b1);
    wire  m_oe_bus  = (spmi_if.m_sdata_oe === 1'b1);
    wire  d1_oe_bus = (d1_oe === 1'b1);
    wire  drv_val   = m_oe_bus ? spmi_if.m_sdata_o : s_oe_bus ? spmi_if.s_sdata_o : d0_oe_bus ? d0_o : d1_o;

    assign spmi_if.oe_all = {d1_oe_bus, d0_oe_bus, s_oe_bus, m_oe_bus};
    assign spmi_if.sdata  = (m_oe_bus || s_oe_bus || d0_oe_bus || d1_oe_bus) ? drv_val : keep;
    always @(posedge clk) keep <= (rst_n === 1'b1) ? (spmi_if.sdata === 1'b1) : 1'b0;   // bus keeper

    dut #(.NREG(64)) dut_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .sid     (SID_PRIM),
        .sclk     (spmi_if.sclk),
        .sdata_i  (spmi_if.sdata),
        .sdata_o  (d0_o),
        .sdata_oe (d0_oe),
        .pm_state (pm0)
    );

    dut #(.NREG(64)) dut2_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .sid     (SID_SEC),
        .sclk     (spmi_if.sclk),
        .sdata_i  (spmi_if.sdata),
        .sdata_o  (d1_o),
        .sdata_oe (d1_oe),
        .pm_state (pm1)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_spmi_if)::set(null, "*", "vif", spmi_if);
        run_test("rand_test");
    end
endmodule
