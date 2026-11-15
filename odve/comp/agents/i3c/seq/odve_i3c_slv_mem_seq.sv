// The reactive target's registers, as a sequence (cfg.slv_mode ==
// ODVE_I3C_SLV_SEQ): waits for each private-transfer byte the target driver
// drops into the sequencer's req_fifo and answers it with the same register
// semantics as the autonomous mode and the RTL target - write byte 0 sets
// the pointer, later bytes are written with auto-increment; a read returns
// the register at the pointer, t_end on the last register. Never ends: start
// it in a fork from the test, without an objection.
class odve_i3c_slv_mem_seq extends uvm_sequence #(odve_i3c_item);
    `uvm_object_utils(odve_i3c_slv_mem_seq)
    `uvm_declare_p_sequencer(odve_i3c_slv_sqr)

    int unsigned nregs = 16;
    bit [7:0]    regs [int unsigned];
    int unsigned ptr   = 0;
    int unsigned n_req = 0;

    function new(string name = "odve_i3c_slv_mem_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_i3c_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_i3c_item::type_id::create("rsp");
            rsp.kind = req.kind;
            rsp.addr = req.addr;
            if (req.kind == I3C_PRIV_WR) begin
                if (req.len == 0) ptr = 32'(req.data[0]) % nregs;
                else begin
                    regs[ptr] = req.data[0];
                    ptr = (ptr + 1) % nregs;
                end
            end else begin
                rsp.data.push_back(regs.exists(ptr) ? regs[ptr] : 8'h00);
                rsp.t_end = (ptr == nregs - 1);
                ptr = (ptr + 1) % nregs;
            end
            n_req++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
