// The reactive flash (cfg.slv_mode == ODVE_QSPI_SLV_SEQ): answers every
// request the slave driver drops into the sequencer's req_fifo from its own
// odve_qspi_flash_model - REQ_DECODE: ack = the flash takes the command;
// REQ_BYTE: rdata[0] = data byte idx; REQ_END: execute the frame. Never
// ends: start it in a fork from the test, without an objection.
class odve_qspi_slv_rsp_seq extends uvm_sequence #(odve_qspi_item);
    `uvm_object_utils(odve_qspi_slv_rsp_seq)
    `uvm_declare_p_sequencer(odve_qspi_slv_sqr)

    odve_qspi_flash_model model;
    int unsigned          n_req = 0;

    function new(string name = "odve_qspi_slv_rsp_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_qspi_item req, rsp;
        if (model == null) begin
            model = odve_qspi_flash_model::type_id::create("model");
            model.cfg = p_sequencer.cfg;
        end
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_qspi_item::type_id::create("rsp");
            case (req.slv_req)
                ODVE_QSPI_REQ_DECODE: rsp.ack = model.accepts(req.cmd, req.qpi, req.t_cyc);
                ODVE_QSPI_REQ_BYTE:   rsp.rdata.push_back(model.out_byte(req.cmd, req.qpi, req.addr, req.idx, req.t_cyc));
                ODVE_QSPI_REQ_END:    model.end_frame(req, req.ack, req.t_cyc);
                default: `uvm_error(get_name(), $sformatf("unexpected request kind %s", req.slv_req.name()))
            endcase
            n_req++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
