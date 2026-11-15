// Station management entity (STA): owns MDC and drives the frame.
//
// Cycle based on the system clock: MDC is low for cfg.mdc_half clocks, then
// high for cfg.mdc_half clocks. The STA changes MDIO at the falling edge
// (half a period of setup and of hold around the rising edge, where both
// ends sample) and reads MDIO in the clock cycle that raises MDC, i.e. the
// value present at the rising edge. MDC only runs while there is a frame
// (it "need not be continuous"), then stays high.
//
// For a read the STA releases MDIO for TA and data; resp = TA[0] seen low.
// For a write it drives req.ta (10 unless an error is injected) and data.
// After the frame req.idle more MDC cycles run with MDIO released.
class odve_mdio_mst_drv_base extends uvm_driver #(odve_mdio_item);
    `uvm_component_utils(odve_mdio_mst_drv_base)

    virtual odve_mdio_if vif;
    odve_mdio_cfg        cfg;

    function new(string name = "odve_mdio_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected task half();
        repeat (cfg.mdc_half) @(posedge vif.clk);
    endtask

    // One MDC period: falling edge with the STA's drive, then the rising edge.
    protected task bit_cycle(bit oe, bit o, output bit s);
        vif.mdc    <= 1'b0;
        vif.sta_oe <= oe;
        vif.sta_o  <= o;
        half();
        s = vif.mdio;
        vif.mdc <= 1'b1;
        half();
    endtask

    protected task send(int unsigned n, bit [15:0] v);
        bit s;
        for (int i = int'(n) - 1; i >= 0; i--) bit_cycle(1'b1, v[i], s);
    endtask

    protected task drive(odve_mdio_item req);
        bit s;
        repeat (req.pre_len) bit_cycle(1'b1, 1'b1, s);
        send(2, 16'(req.st()));
        send(2, 16'(req.op()));
        send(5, 16'(req.phyad));
        send(5, 16'(req.regad));
        if (req.is_read()) begin
            bit_cycle(1'b0, 1'b1, s);          // TA[1]: released
            bit_cycle(1'b0, 1'b1, s);          // TA[0]: the PHY's 0, if any
            req.resp = !s;
            for (int i = 15; i >= 0; i--) begin
                bit_cycle(1'b0, 1'b1, s);
                req.data[i] = s;
            end
        end else begin
            send(2, 16'(req.ta));
            send(16, req.data);
        end
        repeat (req.idle) bit_cycle(1'b0, 1'b1, s);
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.mdc    <= 1'b0;
        vif.sta_oe <= 1'b0;
        vif.sta_o  <= 1'b1;
        wait (vif.rst_n === 1'b1);
        repeat (2) @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(req);
            drive(req);
            `uvm_info(get_name(), req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask
endclass
