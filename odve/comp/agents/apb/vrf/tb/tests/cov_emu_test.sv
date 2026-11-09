// The emulation backend on the bus (+apb_slave=cov): mixed traffic sampled
// by the monitor reaches odve_cov_emu through the feed, then the readback
// sequence pulls the counters over APB, checks them against the package
// store and writes the run's cov.dump from them. Without FCOV=1 the block
// is just an APB slave: traffic only.
class cov_emu_test extends base_test;
    `uvm_component_utils(cov_emu_test)

    function new(string name = "cov_emu_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_apb_rw_seq rw = odve_apb_rw_seq::type_id::create("rw");
        super.run_phase(phase);
        phase.raise_objection(this);
        rw.n = 40;
        rw.allow_oor = 1;
        run_seq(rw);
`ifdef ODVE_FCOV
        begin
            odve_apb_cov_emu_seq rb = odve_apb_cov_emu_seq::type_id::create("rb");
            run_seq(rb);
        end
`else
        `uvm_info(get_name(), "no FCOV=1: traffic against odve_cov_emu only, no readback", UVM_LOW)
`endif
        phase.drop_objection(this);
    endtask : run_phase
endclass : cov_emu_test
