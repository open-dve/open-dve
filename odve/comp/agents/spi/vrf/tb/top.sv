// same default as intf/odve_spi_if.sv and the agent package (each compilation unit needs its own)
`ifndef ODVE_SPI_MAX_CS
`define ODVE_SPI_MAX_CS 4
`endif

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

    odve_spi_if  spi_if (.clk(clk), .rst_n(rst_n));
    spi_strap_if strap ();

    // Who answers the two chip selects (see tb/env/cc.sv): the RTL slaves
    // below (+spi_slave=dut, default) or the slave agents (+spi_slave=mem|seq).
    // A deselected RTL slave never drives MISO, so in agent mode its cs_n is
    // simply held high. MISO itself is resolved in odve_spi_if from the
    // explicit value/enable pairs - no tristates.
    int    slave_src = 0;     // 0 = dut, 1 = slave agents
    string slave_sel;
    initial if ($value$plusargs("spi_slave=%s", slave_sel)) slave_src = (slave_sel == "dut") ? 0 : 1;

    logic [1:0] d_miso, d_miso_oe;
    assign spi_if.d_miso    = {{(`ODVE_SPI_MAX_CS-2){1'b1}}, d_miso};
    assign spi_if.d_miso_oe = {{(`ODVE_SPI_MAX_CS-2){1'b0}}, d_miso_oe};

    for (genvar i = 0; i < 2; i++) begin : g_dut
        dut #(.ID(i == 0 ? 8'hA5 : 8'h3C)) dut_i (
            .clk       (clk),
            .rst_n     (rst_n),
            .sclk      (spi_if.sclk),
            .mosi      (spi_if.mosi),
            .cs_n      (slave_src == 0 ? spi_if.cs_n[i] : 1'b1),
            .miso      (d_miso[i]),
            .miso_oe   (d_miso_oe[i]),
            .cpol      (strap.cpol[i]),
            .cpha      (strap.cpha[i]),
            .lsb_first (strap.lsb_first[i]),
            .wsel      (strap.wsel[i])
        );
    end

    // slave-agent drive of the unused chip selects stays off
    initial begin
        spi_if.s_miso    = '1;
        spi_if.s_miso_oe = '0;
    end

`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial begin
        uvm_config_db #(virtual odve_spi_if)::set(null, "*", "vif", spi_if);
        uvm_config_db #(virtual spi_strap_if)::set(null, "*", "strap", strap);
        run_test("rw_test");
    end
endmodule
