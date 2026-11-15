// The reactive TAP's data registers, as a sequence (cfg.slv_mode ==
// ODVE_JTAG_SLV_SEQ). For each request the slave driver drops into the
// sequencer's req_fifo:
//   Capture-DR (kind JTAG_DR, is_update 0): answer len and tdi = the captured value
//   Update-DR  (kind JTAG_DR, is_update 1): store tdi into the selected register
//   TRST_n     (kind JTAG_RESET):           clear the registers
// The registers are an odve_jtag_tap_model (idcode/pins set before start).
// Never ends: start it in a fork from the test, without an objection.
class odve_jtag_slv_reg_seq extends uvm_sequence #(odve_jtag_item);
    `uvm_object_utils(odve_jtag_slv_reg_seq)
    `uvm_declare_p_sequencer(odve_jtag_slv_sqr)

    odve_jtag_tap_model tap;
    int unsigned        n_req = 0;

    function new(string name = "odve_jtag_slv_reg_seq");
        super.new(name);
        tap = odve_jtag_tap_model::type_id::create("tap");
    endfunction

    virtual task body();
        odve_jtag_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            n_req++;
            rsp = odve_jtag_item::type_id::create("rsp");
            rsp.kind = req.kind;
            if (req.kind == JTAG_RESET) tap.reset(1);
            else if (req.is_update)     tap.update_dr(req.instr[3:0], req.tdi);
            else                        tap.capture_dr(req.instr[3:0], rsp.len, rsp.tdi);
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
