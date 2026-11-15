// SETDASA: dynamic addresses from the static ones (RTL target 0x50, target
// agent 0x51), no ENTDAA. SETDASA to a static address nobody has is NACKed;
// a target that already has an address no longer answers its static one.
// Private transfers and GETPID on the new addresses; an ENTDAA afterwards
// finds nobody to assign.
class setdasa_test extends base_test;
    `uvm_component_utils(setdasa_test)

    function new(string name = "setdasa_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item it;
        bit [6:0]     q[$];
        bit           ack;
        bit [7:0]     none[$];
        i3c_tgt_model d = env_o.scb_o.m_dut, t = env_o.scb_o.m_tgt;
        super.run_phase(phase);
        phase.raise_objection(this);
        ccc_bc(I3C_CCC_RSTDAA, none);
        if (d != null) begin
            ccc_dw(I3C_CCC_SETDASA, DUT_SA, '{8'(7'h40 << 1)}, ack);
            if (!ack) `uvm_error(get_name(), "SETDASA to the RTL target NACKed")
        end
        if (t != null) begin
            ccc_dw(I3C_CCC_SETDASA, TGT_SA, '{8'(7'h41 << 1)}, ack);
            if (!ack) `uvm_error(get_name(), "SETDASA to the target agent NACKed")
        end
        ccc_dw(I3C_CCC_SETDASA, 7'h52, '{8'(7'h42 << 1)}, ack);
        if (ack) `uvm_error(get_name(), "SETDASA to 0x52 (nobody) ACKed")
        if (d != null) begin
            ccc_dw(I3C_CCC_SETDASA, DUT_SA, '{8'(7'h43 << 1)}, ack);   // already has 0x40
            if (ack) `uvm_error(get_name(), "SETDASA ACKed by a target that already has an address")
        end
        das(q);
        foreach (q[i]) begin
            ccc_dr(I3C_CCC_GETPID, q[i], it);
            rand_wr(q[i], 4, 6);
            priv_wr(q[i], '{8'h04});
            priv_rd(q[i], 6, it);
        end
        entdaa(pool, it);
        if (it.daa_id.size() != 0) `uvm_error(get_name(), "ENTDAA after SETDASA assigned an address")
        phase.drop_objection(this);
    endtask : run_phase
endclass : setdasa_test
