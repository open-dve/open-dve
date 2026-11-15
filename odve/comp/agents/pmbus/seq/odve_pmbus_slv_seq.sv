// The PMBus device as a responding sequence (slave agent in
// ODVE_PMBUS_SLV_SEQ mode). Set `model` to the agent's cfg.model and start
// it on <pmbus agent>.smb.i2c.slv_sqr in a fork; it never ends.
class odve_pmbus_slv_seq extends odve_smbus_slv_seq;
    `uvm_object_utils(odve_pmbus_slv_seq)

    function new(string name = "odve_pmbus_slv_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (model == null) model = odve_pmbus_dev_model::type_id::create("model");
        super.body();
    endtask
endclass
