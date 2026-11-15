// Random mix of flash operations: SPI mode without QE, with QE, then QPI.
class rand_test extends base_test;
    `uvm_component_utils(rand_test)
    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_qspi_rand_seq r = odve_qspi_rand_seq::type_id::create("r");
        odve_qspi_base_seq s = fs("rs");
        super.run_phase(phase);
        phase.raise_objection(this);
        r.rng = rng.spawn("r");
        r.n = 25; r.qe = 0; run_seq(r);
        s.write_sr2(8'h02);
        r.n = 25; r.qe = 1; run_seq(r);
        s.enter_qpi();
        r.n = 20; run_seq(r);
        s.exit_qpi();
        phase.drop_objection(this);
    endtask : run_phase
endclass : rand_test
