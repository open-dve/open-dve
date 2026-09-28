// APB3 master: SETUP cycle (psel, no penable), then ACCESS cycles (penable)
// until the slave raises pready. Signals are driven with non-blocking
// assignments at posedge; pready/prdata are read at negedge, when every
// registered value of the slave is stable.
class odve_apb_mst_drv_base extends uvm_driver #(odve_apb_item);
    `uvm_component_utils(odve_apb_mst_drv_base)

    virtual odve_apb_if vif;

    function new(string name = "odve_apb_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
        vif.paddr   <= '0;
        vif.pwdata  <= '0;
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(req);
            // SETUP
            vif.psel    <= 1'b1;
            vif.penable <= 1'b0;
            vif.pwrite  <= req.write;
            vif.paddr   <= req.addr;
            vif.pwdata  <= req.data;
            @(posedge vif.clk);
            // ACCESS, held until pready
            vif.penable <= 1'b1;
            @(negedge vif.clk);
            while (vif.pready !== 1'b1) @(negedge vif.clk);
            if (!req.write) req.data = vif.prdata;
            req.slverr = vif.pslverr;
            @(posedge vif.clk);
            vif.psel    <= 1'b0;
            vif.penable <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass
