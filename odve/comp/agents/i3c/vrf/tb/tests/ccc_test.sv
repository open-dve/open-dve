// Common Command Codes: broadcast and direct SETMWL with GETMWL read-back,
// broadcast DISEC / direct ENEC, GETSTATUS, GETPID/GETBCR/GETDCR, direct CCCs
// to an address nobody has (NACK, both directions), and RSTDAA/ENTDAA again.
// The scoreboard checks every GET payload against its model of the target.
class ccc_test extends base_test;
    `uvm_component_utils(ccc_test)

    function new(string name = "ccc_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item it;
        bit [6:0]     q[$];
        bit           ack;
        bit [7:0]     none[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        assign_all(pool);
        das(q);
        ccc_bc(I3C_CCC_SETMWL_B, '{8'h01, 8'h20});
        foreach (q[i]) ccc_dr(I3C_CCC_GETMWL, q[i], it);
        foreach (q[i]) begin
            ccc_dw(I3C_CCC_SETMWL_D, q[i], '{8'h00, 8'(8'h40 + i)}, ack);
            ccc_dr(I3C_CCC_GETMWL, q[i], it);
            ccc_dr(I3C_CCC_GETSTATUS, q[i], it);
            ccc_dr(I3C_CCC_GETPID, q[i], it);
            ccc_dr(I3C_CCC_GETBCR, q[i], it);
            ccc_dr(I3C_CCC_GETDCR, q[i], it);
        end
        ccc_bc(I3C_CCC_DISEC_B, '{I3C_EVT_ENINT | I3C_EVT_ENHJ});
        foreach (q[i]) ccc_dw(I3C_CCC_ENEC_D, q[i], '{I3C_EVT_ENINT}, ack);
        ccc_dw(I3C_CCC_DISEC_D, q[0], '{I3C_EVT_ENINT}, ack);
        ccc_bc(I3C_CCC_ENEC_B, '{I3C_EVT_ENINT | I3C_EVT_ENHJ});
        // nobody at 0x5B
        ccc_dw(I3C_CCC_SETMWL_D, 7'h5B, '{8'h00, 8'h08}, ack);
        if (ack) `uvm_error(get_name(), "direct SETMWL to 0x5B ACKed")
        ccc_dr(I3C_CCC_GETBCR, 7'h5B, it);
        if (it.ack) `uvm_error(get_name(), "GETBCR from 0x5B ACKed")
        assign_all('{7'h20, 7'h21, 7'h22});
        das(q);
        foreach (q[i]) ccc_dr(I3C_CCC_GETPID, q[i], it);
        phase.drop_objection(this);
    endtask : run_phase
endclass : ccc_test
