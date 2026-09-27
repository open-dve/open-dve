// Functional-coverage runtime (phase-0 spike, see odve/doc/fcov-plan.md).
//
// Everything is package-static: the flat memory of bin counters, hit(), the
// dump/checkpoint logic and the base class of the generated coverage groups.
// No interface, no config_db: a group calls odve_cov_store::hit() directly.
// The only thing a package cannot do by the LRM is a `final` block - that is
// the one-line module odve_cov_final, instantiated in top.
//
// Compiled to nothing without FCOV=1 (+define+ODVE_FCOV). odve_cov_gen.svh
// is generated into $(COV_DIR) by the `acov` build step and sizes the store.
`ifdef ODVE_FCOV
`include "odve_cov_gen.svh"

`ifndef ODVE_COVCNT
`define ODVE_COVCNT 1
`endif

package odve_cov_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int N = `ODVE_COV_N;      // total bins over all groups (flat layout)
    localparam int W = `ODVE_COVCNT;     // bits per counter: 1 = hit/not hit, 32 = hit count

    // "argument not given" sentinel: the `odve_cov_sample macro fills unused
    // positions with it, and a generated sample() declares its spare formals
    // with it as default, so the call is always complete and an argument
    // beyond the covergroup's own list is detected instead of ignored.
    localparam longint NA = 64'h8000_0000_0000_0000;

    // find_bin() results other than a bin index
    localparam int BIN_NONE    = -1;   // value matches no bin (and no ignore/illegal)
    localparam int BIN_IGNORE  = -2;
    localparam int BIN_ILLEGAL = -3;

    // kind[] values in the bin tables
    localparam byte BK_BIN = 0, BK_IGNORE = 1, BK_ILLEGAL = 2;

    // ------------------------------------------------------------ the store
    class odve_cov_store;
        // Packed 2-D so that COVCNT=1 is a plain bit vector on both simulators.
        // Every counter saturates at all-ones.
        static bit [N-1:0][W-1:0] cnt;

        static longint unsigned nsamples = 0;   // hit() calls so far, drives checkpoints
        static int unsigned     every    = 0;   // +odve_cov_every: checkpoint period in hits, 0 = none
        static int unsigned     seq      = 0;   // checkpoint sequence number
        static string           dump     = "";  // +odve_cov_dump: file to write, "" = no dump
        static string           test     = "";  // +odve_cov_test: test name for the header
        static bit              inited   = 0;

        // Plusargs. Called from odve_cov_final's initial and lazily from the
        // first group, whichever comes first (initial vs build_phase order is
        // not defined).
        static function void init();
            if (inited) return;
            inited = 1;
            if (!$value$plusargs("odve_cov_dump=%s", dump)) dump = "";
            if (!$value$plusargs("odve_cov_test=%s", test)) test = "";
            if (!$value$plusargs("odve_cov_every=%d", every)) every = 0;
        endfunction

        // The one hot path: increment a bin, saturating.
        static function void hit(int idx);
            if (idx < 0 || idx >= N) begin
                `uvm_error("ODVE_COV", $sformatf("bin index %0d out of range (N=%0d) - ignored", idx, N))
                return;
            end
            if (cnt[idx] != {W{1'b1}}) cnt[idx] = cnt[idx] + 1'b1;
            nsamples++;
            if (every != 0 && (nsamples % every) == 0) checkpoint();
        endfunction

        // Dump format (doc/fcov-plan.md 4.2): header lines, "idx count" for
        // non-zero bins only, then a closing "# end <tag>" line - a reader
        // treats a file without it as truncated.
        static function void write(string path, string tag);
            int fd = $fopen(path, "w");
            if (fd == 0) begin
                `uvm_warning("ODVE_COV", $sformatf("cannot open %s for writing", path))
                return;
            end
            $fwrite(fd, "# odve-cov 1\n");
            $fwrite(fd, "# model %s hash %s\n", `ODVE_COV_MODEL, `ODVE_COV_HASH);
            $fwrite(fd, "# test %s covcnt %0d n %0d\n", test, W, N);
            $fwrite(fd, "# samples %0d\n", nsamples);
            for (int i = 0; i < N; i++)
                if (cnt[i] != 0) $fwrite(fd, "%0d %0d\n", i, cnt[i]);
            $fwrite(fd, "# end %s\n", tag);
            $fclose(fd);
        endfunction

        // Checkpoints alternate between <dump>.0 and <dump>.1 (a kill during
        // the write of one leaves the other intact); the final dump is <dump>.
        static function void checkpoint();
            if (dump == "") return;
            seq++;
            write($sformatf("%s.%0d", dump, seq % 2), $sformatf("%0d", seq));
        endfunction

        static function void final_dump();
            init();
            if (dump != "") write(dump, "final");
        endfunction
    endclass

    // ------------------------------------------------- base of the groups
    // One coverage group = one covergroup of the model. The generated
    // subclass owns the bin tables of its points and a sample() with the
    // covergroup's own argument list (plus NA-defaulted spares); this base
    // only provides the lookup and the reporting.
    virtual class odve_cov_group;
        string name;

        function new(string name);
            this.name = name;
            odve_cov_store::init();
        endfunction

        // Table-driven value -> bin: a point's bins are parallel arrays
        // lo[]/hi[]/kind[] (a value bin has lo == hi; ranges are inclusive).
        // Returns the index among the point's *coverage* bins (kind BK_BIN,
        // in table order), or BIN_IGNORE / BIN_ILLEGAL / BIN_NONE.
        // Ignore and illegal entries are checked first, as the LRM has it.
        static function int find_bin(longint value, ref longint lo[], ref longint hi[], ref byte kind[]);
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

        function void illegal(string point, longint value);
            `uvm_error("ODVE_COV", $sformatf("%s.%s: illegal bin hit by value %0d", name, point, value))
        endfunction

        // A generated sample() calls this on its spare formals.
        function void check_spare(longint a, int pos);
            if (a != NA)
                `uvm_error("ODVE_COV", $sformatf("%s: sample() called with an argument in position %0d, but the covergroup declares fewer", name, pos))
        endfunction
    endclass

endpackage
`endif
