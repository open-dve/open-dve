// The reactive PHY's registers, as a sequence (cfg.slv_mode ==
// ODVE_MDIO_SLV_SEQ): takes each frame the slave driver drops into the
// sequencer's req_fifo (a read before its TA, a write-type frame once
// complete), answers it from its own odve_mdio_phy_model - resp = 1 when a
// PHY of the model claims the frame, data for a read - and never ends: start
// it in a fork from the test and hold no objection for it. Configure
// `model` (configure(cfg)) before starting.
class odve_mdio_slv_resp_seq extends uvm_sequence #(odve_mdio_item);
    `uvm_object_utils(odve_mdio_slv_resp_seq)
    `uvm_declare_p_sequencer(odve_mdio_slv_sqr)

    odve_mdio_phy_model model;
    int unsigned        n_req = 0;

    function new(string name = "odve_mdio_slv_resp_seq");
        super.new(name);
        model = odve_mdio_phy_model::type_id::create("model");
    endfunction

    virtual task body();
        odve_mdio_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_mdio_item::type_id::create("rsp");
            rsp.kind  = req.kind;
            rsp.phyad = req.phyad;
            rsp.regad = req.regad;
            rsp.resp  = model.claims(req);
            rsp.data  = rsp.resp ? model.access(req) : 16'h0;
            n_req++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
