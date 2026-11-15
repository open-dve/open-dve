// The reactive slave's registers and power state, as a sequence
// (cfg.slv_mode == ODVE_SPMI_SLV_SEQ): waits for each request the slave
// driver drops into the sequencer's req_fifo and answers it - a read with
// data from its registers (the power state at nregs, NRF beyond), a write or
// PM command by updating them and answering ACK. Never ends: start it in a
// fork from the test, without an objection.
class odve_spmi_slv_mem_seq extends uvm_sequence #(odve_spmi_item);
    `uvm_object_utils(odve_spmi_slv_mem_seq)
    `uvm_declare_p_sequencer(odve_spmi_slv_sqr)

    int unsigned   nregs = 64;
    bit [7:0]      mem [int unsigned];
    odve_spmi_pm_e pm = ODVE_SPMI_ACTIVE;
    int unsigned   n_resp = 0;

    function new(string name = "odve_spmi_slv_mem_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_spmi_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_spmi_item::type_id::create("rsp");
            rsp.kind   = req.kind;
            rsp.addr   = req.addr;
            rsp.nbytes = req.nbytes;
            rsp.ack    = 1;
            case (req.kind)
                ODVE_SPMI_REG_RD, ODVE_SPMI_EXT_RD, ODVE_SPMI_EXTL_RD: begin
                    rsp.data = new[req.nbytes];
                    for (int i = 0; i < int'(req.nbytes); i++) begin
                        int unsigned a = req.byte_addr(i);
                        if (a < nregs)       rsp.data[i] = mem.exists(a) ? mem[a] : 8'h00;
                        else if (a == nregs) rsp.data[i] = {6'h00, pm};
                        else                 rsp.nrf_mask[i] = 1'b1;
                    end
                end
                ODVE_SPMI_REG0_WR: mem[0] = {1'b0, req.data[0][6:0]};
                ODVE_SPMI_RESET: begin
                    mem.delete();
                    pm = ODVE_SPMI_ACTIVE;
                end
                ODVE_SPMI_SLEEP:    pm = ODVE_SPMI_SLEEPING;
                ODVE_SPMI_SHUTDOWN: pm = ODVE_SPMI_SHUTDOWN_ST;
                ODVE_SPMI_WAKEUP:   pm = ODVE_SPMI_ACTIVE;
                default:
                    foreach (req.data[i]) begin
                        int unsigned a = req.byte_addr(i);
                        if (a < nregs) mem[a] = req.data[i];
                    end
            endcase
            n_resp++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
