// Half-speed reads: the master clocks the read data frames at half the SCLK
// rate and samples them on the following rising edge; the monitor must see
// every read as half speed and the data must still match. REQ-RFFE-024.
class half_speed_test extends base_test;
    `uvm_component_utils(half_speed_test)

    function new(string name = "half_speed_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_base_seq r = rand_seq("r", 60, 7'h7F);
        super.run_phase(phase);
        phase.raise_objection(this);
        env_o.cfg.half_speed_read = 1;
        run_seq(r);
        phase.drop_objection(this);
        if (env_o.scb_o.n_half != env_o.scb_o.n_rd || env_o.scb_o.n_rd == 0)
            `uvm_error(get_name(), $sformatf("%0d of %0d reads seen at half speed", env_o.scb_o.n_half, env_o.scb_o.n_rd))
    endtask : run_phase
endclass : half_speed_test
