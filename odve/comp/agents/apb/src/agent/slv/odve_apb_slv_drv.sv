// APB3 slave driver. Watches the bus for a SETUP cycle (psel && !penable)
// and answers in the ACCESS phase through the interface's slave-side
// signals (s_pready / s_prdata / s_pslverr - top wires them onto the bus
// when the slave agent, not a DUT, plays the slave). Two modes (cfg.slv_mode):
//
//   ODVE_APB_SLV_MEM  autonomous: the memory lives here (assoc array,
//                     cfg.nregs words, out-of-range -> pslverr, a wait state
//                     every cfg.wait_every-th transfer). No sequencer needed.
//   ODVE_APB_SLV_SEQ  reactive: the request is published on req_port (the
//                     slave sequencer's req_fifo) and the response - data,
//                     slverr, wait_states - comes back as a sequence item
//                     from the slave sequence that owns the memory
//                     (seq/odve_apb_slv_mem_seq.sv, or one of your own).
class odve_apb_slv_drv extends uvm_driver #(odve_apb_item);
    `uvm_component_utils(odve_apb_slv_drv)

    virtual odve_apb_if vif;
    odve_apb_cfg        cfg;
    uvm_analysis_port #(odve_apb_item) req_port;

    bit [31:0]   mem [int unsigned];   // MEM mode
    int unsigned n_resp = 0;

    function new(string name = "odve_apb_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    // MEM mode: the response comes from the driver's own memory.
    function odve_apb_item respond_from_mem(odve_apb_item req);
        odve_apb_item rsp = odve_apb_item::type_id::create("rsp");
        int unsigned idx = req.addr >> 2;
        bit in_range = idx < cfg.nregs;
        rsp.addr   = req.addr;
        rsp.write  = req.write;
        rsp.slverr = !in_range;
        rsp.data   = '0;
        if (in_range) begin
            if (req.write) mem[idx] = req.data;
            else           rsp.data = mem.exists(idx) ? mem[idx] : 32'h0;
        end
        rsp.wait_states = (cfg.wait_every != 0 && (n_resp % cfg.wait_every) == cfg.wait_every - 1) ? 1 : 0;
        return rsp;
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_apb_item req, rsp;
        vif.s_pready  <= 1'b0;
        vif.s_prdata  <= '0;
        vif.s_pslverr <= 1'b0;
        wait (vif.rst_n === 1'b1);
        forever begin
            @(posedge vif.clk);
            if (vif.psel === 1'b1 && vif.penable === 1'b0) begin      // SETUP seen at this edge
                req = odve_apb_item::type_id::create("req");
                req.addr  = vif.paddr;
                req.write = vif.pwrite;
                req.data  = vif.pwdata;
                if (cfg.slv_mode == ODVE_APB_SLV_MEM) begin
                    rsp = respond_from_mem(req);
                end else begin
                    req_port.write(req);              // the responding sequence picks it up ...
                    seq_item_port.get_next_item(rsp); // ... and answers, zero time later
                end
                repeat (rsp.wait_states) begin
                    vif.s_pready <= 1'b0;
                    @(posedge vif.clk);
                end
                vif.s_pready  <= 1'b1;
                vif.s_prdata  <= rsp.data;
                vif.s_pslverr <= rsp.slverr;
                @(posedge vif.clk);
                vif.s_pready  <= 1'b0;
                vif.s_pslverr <= 1'b0;
                if (cfg.slv_mode == ODVE_APB_SLV_SEQ) seq_item_port.item_done();
                n_resp++;
            end
        end
    endtask
endclass
