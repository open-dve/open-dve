module top;
    import uvm_pkg::*;
    import odve_mdio_agent_pkg::*;
    import test_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    odve_mdio_if mdio_if (.clk(clk), .rst_n(rst_n));

    // The RTL PHY is on the bus unless +mdio_slave=mem|seq replaces it by the
    // slave agent (tb/env/cc.sv); with +mdio_slave=multi both are. Its MDIO
    // output is a value/enable pair - the line is resolved in the interface.
    logic  dut_o, dut_oe;
    bit    dut_on = 1'b1;
    string slave_sel;
    initial if ($value$plusargs("mdio_slave=%s", slave_sel))
        dut_on = (slave_sel == "dut" || slave_sel == "multi");
    assign mdio_if.dut_o  = dut_o;
    assign mdio_if.dut_oe = dut_on & dut_oe;

    dut #(
        .PHYAD    (5'd1),
        .PRTAD    (5'd1),
        .ID1      (ODVE_MDIO_ID1),
        .ID2      (ODVE_MDIO_ID2),
        .BMCR_RST (ODVE_MDIO_BMCR_RST),
        .BMSR     (ODVE_MDIO_BMSR),
        .MMD_STAT (ODVE_MDIO_MMD_STAT),
        .DEVS     (ODVE_MDIO_DEVS),
        .PRE_MIN  (32),
        .NRW45    (ODVE_MDIO_NRW45)
    ) dut_i (
        .clk     (clk),
        .rst_n   (rst_n),
        .mdc     (mdio_if.mdc),
        .mdio_i  (mdio_if.mdio),
        .mdio_o  (dut_o),
        .mdio_oe (dut_oe)
    );

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_mdio_if)::set(null, "*", "vif", mdio_if);
        run_test("c22_test");
    end
endmodule
