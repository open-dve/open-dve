// Passive observer of the bus: one item per completed transfer (psel &&
// penable && pready, sampled at negedge so every registered value is
// stable), published on item_collected_port and fed to the coverage below.
class odve_apb_mon extends uvm_monitor;
    `uvm_component_utils(odve_apb_mon)

    uvm_analysis_port #(odve_apb_item) item_collected_port;
    virtual odve_apb_if vif;
    int unsigned n_seen = 0;

    // Functional coverage of what actually went over the bus. The covergroup
    // itself is declared in odve_apb_agent_pkg (package scope, standard
    // syntax, `ifdef ODVE_COV_NATIVE); with FCOV=1 the build generates
    // odve_cov_pkg::odve_cov_odve_apb_cg from it and these two macros are the
    // whole hook. Without FCOV=1 both expand to nothing.
    `odve_cov_create(odve_apb_cg)

    function new(string name = "odve_apb_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_apb_item tr;
        forever begin
            @(negedge vif.clk);
            if (vif.rst_n === 1'b1 && vif.psel === 1'b1 && vif.penable === 1'b1 && vif.pready === 1'b1) begin
                tr = odve_apb_item::type_id::create("tr");
                tr.addr   = vif.paddr;
                tr.write  = vif.pwrite;
                tr.data   = vif.pwrite ? vif.pwdata : vif.prdata;
                tr.slverr = vif.pslverr;
                n_seen++;
                `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
                `odve_cov_sample(odve_apb_cg, int'(tr.addr >> 2), tr.write, tr.slverr)
                item_collected_port.write(tr);
            end
        end
    endtask
endclass
