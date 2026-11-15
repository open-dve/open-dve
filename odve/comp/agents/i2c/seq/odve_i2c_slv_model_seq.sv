// The reactive target's behaviour as a sequence (cfg.slv_mode ==
// ODVE_I2C_SLV_SEQ): takes each event the slave driver drops into the
// sequencer's req_fifo, lets `model` answer it (default: the register-file
// odve_i2c_mem_model) and sends the answer back. It never ends: start it in
// a fork from the test and hold no objection for it. Override respond() in
// a subclass for a target of your own, or plug in another model.
class odve_i2c_slv_model_seq extends uvm_sequence #(odve_i2c_slv_item);
    `uvm_object_utils(odve_i2c_slv_model_seq)
    `uvm_declare_p_sequencer(odve_i2c_slv_sqr)

    odve_i2c_slv_model model;
    int unsigned       n_resp = 0;

    function new(string name = "odve_i2c_slv_model_seq");
        super.new(name);
    endfunction

    virtual function void respond(odve_i2c_slv_item ev);
        model.handle(ev);
    endfunction

    virtual task body();
        odve_i2c_slv_item req, rsp;
        if (model == null) model = odve_i2c_mem_model::type_id::create("model");
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_i2c_slv_item::type_id::create("rsp");
            rsp.ev = req.ev; rsp.addr = req.addr; rsp.addr10 = req.addr10; rsp.rw = req.rw;
            rsp.restart = req.restart; rsp.gc = req.gc; rsp.data = req.data; rsp.idx = req.idx;
            rsp.mack = req.mack; rsp.abort = req.abort; rsp.tmo = req.tmo; rsp.nrd = req.nrd;
            respond(rsp);
            n_resp++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
