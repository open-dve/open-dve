// The SMBus device as a responding sequence (slave agent in
// ODVE_SMBUS_SLV_SEQ mode): an i2c responder whose model is an SMBus device
// - set `model` to the agent's cfg.model so the agent's SMBALERT# and the
// i2c slave driver's ARA matching see the same object. Start it on
// <smbus agent>.i2c.slv_sqr in a fork; it never ends.
class odve_smbus_slv_seq extends odve_i2c_slv_model_seq;
    `uvm_object_utils(odve_smbus_slv_seq)

    function new(string name = "odve_smbus_slv_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (model == null) model = odve_smbus_ref_model::type_id::create("model");
        super.body();
    endtask
endclass
