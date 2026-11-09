// The reactive slave's memory, as a sequence (cfg.slv_mode == ODVE_APB_SLV_SEQ):
// waits for each request the slave driver drops into the sequencer's
// req_fifo, answers from its own memory - out-of-range -> pslverr, a wait
// state every wait_every-th transfer - and never ends, so start it in a
// fork from the test and do not hold an objection for it.
class odve_apb_slv_mem_seq extends uvm_sequence #(odve_apb_item);
    `uvm_object_utils(odve_apb_slv_mem_seq)
    `uvm_declare_p_sequencer(odve_apb_slv_sqr)

    int unsigned nregs      = 16;
    int unsigned wait_every = 3;
    bit [31:0]   mem [int unsigned];
    int unsigned n_resp = 0;

    function new(string name = "odve_apb_slv_mem_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_apb_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_apb_item::type_id::create("rsp");
            rsp.addr  = req.addr;
            rsp.write = req.write;
            begin
                int unsigned idx = req.addr >> 2;
                bit in_range = idx < nregs;
                rsp.slverr = !in_range;
                rsp.data   = '0;
                if (in_range) begin
                    if (req.write) mem[idx] = req.data;
                    else           rsp.data = mem.exists(idx) ? mem[idx] : 32'h0;
                end
            end
            rsp.wait_states = (wait_every != 0 && (n_resp % wait_every) == wait_every - 1) ? 1 : 0;
            n_resp++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
