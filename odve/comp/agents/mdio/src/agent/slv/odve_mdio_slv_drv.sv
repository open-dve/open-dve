// PHY side of the bus: one or more PHYs (Clause 22) / ports with MMDs
// (Clause 45). Follows every frame bit by bit at the MDC rising edges, like
// the RTL PHY, and drives phy_o/phy_oe right after a rising edge (a PHY's
// read data changes after the rising edge of MDC). Two modes (cfg.slv_mode):
//
//   ODVE_MDIO_SLV_MEM  autonomous: the register model (odve_mdio_phy_model,
//                      configured from cfg) lives here.
//   ODVE_MDIO_SLV_SEQ  reactive: each frame is published on req_port (the
//                      slave sequencer's req_fifo) - a read right after its
//                      header, before TA, a write-type frame once its data
//                      is in - and the response item (resp = answer or not,
//                      data) comes back from the responding sequence
//                      (seq/odve_mdio_slv_resp_seq.sv, or one of your own).
//
// Frames with fewer than cfg.pre_min preamble ones, undefined C22 opcodes,
// other addresses, absent MMDs or (write) a TA other than 10 are not
// answered: the line is left to the pull-up.
class odve_mdio_slv_drv extends uvm_driver #(odve_mdio_item);
    `uvm_component_utils(odve_mdio_slv_drv)

    virtual odve_mdio_if vif;
    odve_mdio_cfg        cfg;
    odve_mdio_phy_model  model;   // MEM mode
    uvm_analysis_port #(odve_mdio_item) req_port;
    int unsigned n_resp = 0;

    function new(string name = "odve_mdio_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    protected task get_bit(output bit b);
        @(posedge vif.mdc);
        b = vif.mdio;
    endtask

    protected task get_field(int unsigned n, output bit [15:0] v);
        bit b;
        v = '0;
        repeat (n) begin
            get_bit(b);
            v = {v[14:0], b};
        end
    endtask

    // Answer of the PHY(s) to a frame: from the model or from the sequence.
    protected task respond(odve_mdio_item req, output bit hit, output bit [15:0] d);
        odve_mdio_item rsp;
        d = '0;
        if (cfg.slv_mode == ODVE_MDIO_SLV_MEM) begin
            hit = model.claims(req);
            if (hit) d = model.access(req);
        end else begin
            req_port.write(req);
            seq_item_port.get_next_item(rsp);
            hit = rsp.resp;
            d   = rsp.data;
            seq_item_port.item_done();
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        bit              b, hit;
        bit [15:0]       v, d;
        bit [1:0]        st, op;
        int unsigned     ones;
        odve_mdio_item   req;
        if (cfg.slv_mode == ODVE_MDIO_SLV_MEM) begin
            model = odve_mdio_phy_model::type_id::create("model");
            model.configure(cfg);
        end
        vif.phy_oe <= 1'b0;
        vif.phy_o  <= 1'b1;
        wait (vif.rst_n === 1'b1);
        forever begin
            ones = 0;
            forever begin
                get_bit(b);
                if (!b) break;
                ones++;
            end
            req = odve_mdio_item::type_id::create("req");
            req.pre_len = ones;
            get_bit(b);  st = {1'b0, b};
            get_field(2, v); op = v[1:0];
            get_field(5, v); req.phyad = v[4:0];
            get_field(5, v); req.regad = v[4:0];
            req.kind   = odve_mdio_item::decode(st, op);
            req.bad_op = op;
            if (req.is_read()) begin
                respond(req, hit, d);
                get_bit(b);                                   // TA[1] (Z)
                if (hit) begin vif.phy_oe <= 1'b1; vif.phy_o <= 1'b0; end
                get_bit(b);                                   // TA[0]
                for (int i = 15; i >= 0; i--) begin
                    if (hit) vif.phy_o <= d[i];
                    get_bit(b);
                end
                vif.phy_oe <= 1'b0;
                vif.phy_o  <= 1'b1;
            end else begin
                get_field(2, v);  req.ta   = v[1:0];
                get_field(16, v); req.data = v;
                respond(req, hit, d);
            end
            if (hit) n_resp++;
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames answered/applied", n_resp), UVM_LOW)
    endfunction
endclass
