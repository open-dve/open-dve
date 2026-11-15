// The reactive slave's registers, as a sequence (cfg.slv_mode ==
// ODVE_RFFE_SLV_SEQ): waits for each request the slave driver drops into the
// sequencer's req_fifo and answers it - a read with data from its registers
// (NRF beyond nregs), a write by updating them and returning an empty
// response. Never ends: start it in a fork from the test, without an
// objection.
class odve_rffe_slv_mem_seq extends uvm_sequence #(odve_rffe_item);
    `uvm_object_utils(odve_rffe_slv_mem_seq)
    `uvm_declare_p_sequencer(odve_rffe_slv_sqr)

    int unsigned nregs = 64;
    bit [7:0]    mem [int unsigned];
    int unsigned n_resp = 0;

    function new(string name = "odve_rffe_slv_mem_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_rffe_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_rffe_item::type_id::create("rsp");
            rsp.kind   = req.kind;
            rsp.addr   = req.addr;
            rsp.nbytes = req.nbytes;
            if (req.is_read()) begin
                rsp.data = new[req.nbytes];
                for (int i = 0; i < int'(req.nbytes); i++) begin
                    int unsigned a = req.byte_addr(i);
                    if (a < nregs) rsp.data[i] = mem.exists(a) ? mem[a] : 8'h00;
                    else           rsp.nrf_mask[i] = 1'b1;
                end
            end else if (req.kind == ODVE_RFFE_REG0_WR) begin
                mem[0] = {1'b0, req.data[0][6:0]};
            end else begin
                foreach (req.data[i]) begin
                    int unsigned a = req.byte_addr(i);
                    if (a < nregs) mem[a] = req.data[i];
                end
            end
            n_resp++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
