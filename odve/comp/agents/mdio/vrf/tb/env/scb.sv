// Reference model of every PHY on the bus (odve_mdio_phy_model with the
// addresses cc reports): for each frame the monitor sees it predicts whether
// a PHY answers (reads) or acts on it (write-type frames), checks that a read
// was answered or not as predicted, the data of an answered read, and that
// an unanswered read returns the pull-up (FFFF).
`uvm_analysis_imp_decl(_mdio)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_mdio #(odve_mdio_item, scb) mdio_imp;

    odve_mdio_phy_model model;
    int unsigned n_frames = 0, n_rd = 0, n_wr = 0, n_miss = 0, n_ign = 0;
    int unsigned n_kind[7];

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mdio_imp = new("mdio_imp", this);
        model = odve_mdio_phy_model::type_id::create("model");
    endfunction

    function void write_mdio(odve_mdio_item tr);
        bit        hit = model.claims(tr);
        bit [15:0] exp;
        n_frames++;
        n_kind[int'(tr.kind)]++;
        if (tr.is_read()) begin
            n_rd++;
            if (tr.resp != hit) begin
                `uvm_error(get_name(), $sformatf("%s: %s expected", tr.convert2string(), hit ? "an answer" : "no answer"))
            end else if (hit) begin
                exp = model.access(tr);
                if (tr.data !== exp)
                    `uvm_error(get_name(), $sformatf("%s: read data 0x%04h, expected 0x%04h", tr.convert2string(), tr.data, exp))
            end else begin
                n_miss++;
                if (tr.data !== 16'hFFFF)
                    `uvm_error(get_name(), $sformatf("%s: unanswered read must see the pull-up (FFFF)", tr.convert2string()))
            end
        end else begin
            if (hit) begin
                n_wr++;
                void'(model.access(tr));
            end else begin
                n_ign++;
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames checked: %0d reads (%0d unanswered), %0d write-type applied, %0d write-type ignored; per kind C22_WR %0d C22_RD %0d C45_ADDR %0d C45_WR %0d C45_RD %0d C45_RINC %0d C22_BADOP %0d",
            n_frames, n_rd, n_miss, n_wr, n_ign, n_kind[0], n_kind[1], n_kind[2], n_kind[3], n_kind[4], n_kind[5], n_kind[6]), UVM_LOW)
        if (n_frames == 0)
            `uvm_error(get_name(), "no MDIO frames observed")
    endfunction
endclass : scb
