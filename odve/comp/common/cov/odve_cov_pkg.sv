// Base classes of the functional-coverage flow (phase-0 spike, see
// odve/doc/fcov-plan.md). The generated per-covergroup classes extend
// odve_cov_group; odve_cov_server hands them the collector interface.
//
// Compiled to nothing without FCOV=1 (+define+ODVE_FCOV).
`ifdef ODVE_FCOV
`include "odve_cov_gen.svh"

package odve_cov_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // find_bin() results other than a bin index
    localparam int BIN_NONE    = -1;   // value matches no bin (and no ignore/illegal)
    localparam int BIN_IGNORE  = -2;
    localparam int BIN_ILLEGAL = -3;

    // kind[] values in the bin tables
    localparam byte BK_BIN = 0, BK_IGNORE = 1, BK_ILLEGAL = 2;

    // Locates the single collector interface (instantiated in top under
    // ODVE_FCOV and published as "odve_cov_vif" in uvm_config_db).
    class odve_cov_server;
        static virtual odve_cov_if vif;

        static function virtual odve_cov_if get();
            if (vif == null) begin
                if (!uvm_config_db#(virtual odve_cov_if)::get(null, "", "odve_cov_vif", vif))
                    `uvm_fatal("ODVE_COV", "no odve_cov_if in uvm_config_db (key odve_cov_vif): is it instantiated in top and was the build made with FCOV=1?")
            end
            return vif;
        endfunction
    endclass

    // One coverage group = one covergroup of the model. The generated subclass
    // owns the bin tables of its points and a sample() with the covergroup's
    // own argument list; this base only provides the lookup and the reporting.
    virtual class odve_cov_group;
        string name;
        virtual odve_cov_if vif;

        function new(string name);
            this.name = name;
            vif = odve_cov_server::get();
            odve_cov_if_pkg::model = `ODVE_COV_MODEL;
            odve_cov_if_pkg::hash  = `ODVE_COV_HASH;
        endfunction

        // Table-driven value -> bin: a point's bins are parallel arrays
        // lo[]/hi[]/kind[] (a value bin has lo == hi; ranges are inclusive).
        // Returns the index among the point's *coverage* bins (kind BK_BIN,
        // in table order), or BIN_IGNORE / BIN_ILLEGAL / BIN_NONE.
        // Ignore and illegal entries are checked first, as the LRM has it.
        static function int find_bin(int value, ref int lo[], ref int hi[], ref byte kind[]);
            int nb = 0;
            for (int i = 0; i < lo.size(); i++)
                if (kind[i] != BK_BIN && value >= lo[i] && value <= hi[i])
                    return (kind[i] == BK_IGNORE) ? BIN_IGNORE : BIN_ILLEGAL;
            for (int i = 0; i < lo.size(); i++) begin
                if (kind[i] != BK_BIN) continue;
                if (value >= lo[i] && value <= hi[i]) return nb;
                nb++;
            end
            return BIN_NONE;
        endfunction

        function void illegal(string point, int value);
            `uvm_error("ODVE_COV", $sformatf("%s.%s: illegal bin hit by value %0d", name, point, value))
        endfunction
    endclass

endpackage
`endif
