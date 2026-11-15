// The reactive slave's register file, as a sequence (cfg.slv_mode ==
// ODVE_SPI_SLV_SEQ): for every request the slave driver drops into the
// sequencer's req_fifo it first applies the words received since the last
// one, then answers with the next word to send (rsp.miso[0]). Same command
// protocol as the MEM mode (odve_spi_slv_model). Never ends: start it in a
// fork from the test and do not hold an objection for it.
class odve_spi_slv_rsp_seq extends uvm_sequence #(odve_spi_item);
    `uvm_object_utils(odve_spi_slv_rsp_seq)
    `uvm_declare_p_sequencer(odve_spi_slv_sqr)

    odve_spi_slv_model model;
    int unsigned       n_req = 0;

    function new(string name = "odve_spi_slv_rsp_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_spi_item req, rsp;
        if (model == null) begin
            model = odve_spi_slv_model::type_id::create("model");
            model.id     = p_sequencer.cfg.slv_id;
            model.nbytes = p_sequencer.cfg.slv_nbytes;
        end
        forever begin
            p_sequencer.req_fifo.get(req);
            if (req.mosi.size() == 0 && !req.frame_end) model.start_frame();
            while (model.nrx < req.mosi.size()) model.rx_word(req.mosi[model.nrx], req.word_bits);
            rsp = odve_spi_item::type_id::create("rsp");
            rsp.cs = req.cs;
            rsp.miso.push_back(req.frame_end ? 32'h0 : model.tx_word(req.mosi.size(), req.word_bits));
            n_req++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
