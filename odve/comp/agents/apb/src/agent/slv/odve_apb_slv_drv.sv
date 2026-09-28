// Slave-side driver: not needed while the DUT is the slave; kept as the
// canonical placeholder for a TB where the agent has to answer a master.
class odve_apb_slv_drv extends uvm_driver #(odve_apb_item);
    `uvm_component_utils(odve_apb_slv_drv)

    virtual odve_apb_if vif;

    function new(string name = "odve_apb_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            // TODO: respond on vif per req
            seq_item_port.item_done();
        end
    endtask
endclass
