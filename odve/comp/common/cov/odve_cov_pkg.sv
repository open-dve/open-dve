// Functional-coverage runtime (doc/fcov-plan.md). Everything is
// package-static: the flat memory of bin counters, hit(), the dump and
// checkpoint logic, and the base class of the generated coverage groups.
// The generated classes themselves (odve_cov_gen_classes.svh, written by
// `covgen.py scan` into $(COV_DIR) at build time) are included at the end of
// this package, so a testbench refers to them as odve_cov_pkg::odve_cov_<name>.
//
// The only thing a package cannot hold by the LRM is a `final` block - that
// is the one-line module odve_cov_final, instantiated in top.
//
// Compiled to nothing without FCOV=1 (+define+ODVE_FCOV).
`ifdef ODVE_FCOV
`include "odve_cov_gen.svh"

`ifndef ODVE_COVCNT
`define ODVE_COVCNT 1
`endif

// Reporting (used inside the package only). With UVM (the default) an ODVE_COV_ERR is a uvm_error; without
// it (+define+ODVE_COV_NO_UVM: unit tests, testbenches that do not use UVM)
// it is a $display. Either way odve_cov_errors counts them, so a test can
// check that an error was raised without parsing a log.
`ifdef ODVE_COV_NO_UVM
`define ODVE_COV_ERR(msg)  begin odve_cov_errors++; $display("ODVE_COV ERROR: %s", msg); end
`define ODVE_COV_WARN(msg) $display("ODVE_COV WARNING: %s", msg);
`else
`define ODVE_COV_ERR(msg)  begin odve_cov_errors++; `uvm_error("ODVE_COV", msg) end
`define ODVE_COV_WARN(msg) `uvm_warning("ODVE_COV", msg)
`endif

package odve_cov_pkg;
`ifndef ODVE_COV_NO_UVM
    import uvm_pkg::*;
    `include "uvm_macros.svh"
`endif

    int odve_cov_errors = 0;   // ODVE_COV_ERRs raised so far

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

    // Row kinds of the generated lo/hi/kind/bidx tables (covlib/gen.py):
    // *_WILD rows match (value & hi) == lo with hi holding the care mask,
    // DEFAULT matches whatever no other coverage row matched.
    localparam byte K_BIN = 0, K_IGNORE = 1, K_ILLEGAL = 2,
                    K_BIN_WILD = 3, K_IGNORE_WILD = 4, K_ILLEGAL_WILD = 5, K_DEFAULT = 6;

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
        static bit              frozen   = 0;   // hit() drops samples while set (a readback wants a stable store)
        static bit              ext_dumped = 0; // another backend already wrote <dump>: final_dump() leaves it

        // Emulation backend (odve_cov_emu.sv): with an odve_cov_emu_feed in
        // the testbench every hit is also queued here, and the feed drives
        // it onto the block's sample port one per clock.
        static bit              emu = 0;
        static int              smp_q[$];

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
                `ODVE_COV_ERR($sformatf("bin index %0d out of range (N=%0d) - ignored", idx, N))
                return;
            end
            if (frozen) return;
            if (cnt[idx] != {W{1'b1}}) cnt[idx] = cnt[idx] + 1'b1;
            nsamples++;
            if (emu) smp_q.push_back(idx);
            if (every != 0 && (nsamples % longint'(every)) == 0) checkpoint();
        endfunction

        // Dump format (doc/fcov-plan.md 4.2): header lines, "idx count" for
        // non-zero bins only, then a closing "# end <tag>" line - a reader
        // treats a file without it as truncated. `backend` names another
        // source of the counts ("emu"); "" is this store.
        static function int open_dump(string path, longint unsigned samples, string backend);
            int fd = $fopen(path, "w");
            if (fd == 0) begin
                `ODVE_COV_WARN($sformatf("cannot open %s for writing", path))
                return 0;
            end
            $fwrite(fd, "# odve-cov 1\n");
            $fwrite(fd, "# model %s hash %s\n", `ODVE_COV_MODEL, `ODVE_COV_HASH);
            $fwrite(fd, "# test %s covcnt %0d n %0d\n", test, W, N);
            $fwrite(fd, "# samples %0d\n", samples);
            if (backend != "") $fwrite(fd, "# backend %s\n", backend);
            return fd;
        endfunction

        static function void write(string path, string tag);
            int fd = open_dump(path, nsamples, "");
            if (fd == 0) return;
            for (int i = 0; i < N; i++)
                if (cnt[i] != 0) $fwrite(fd, "%0d %0d\n", i, cnt[i]);
            $fwrite(fd, "# end %s\n", tag);
            $fclose(fd);
        endfunction

        // The same file from counts read back from another backend
        // (odve_cov_emu over APB); counts.size() must be N.
        static function void write_ext(input string path, input string tag, ref int unsigned counts[],
                                       input longint unsigned samples, input string backend);
            int fd;
            if (counts.size() != N) begin
                `ODVE_COV_ERR($sformatf("write_ext: %0d counts for N=%0d bins - no dump", counts.size(), N))
                return;
            end
            fd = open_dump(path, samples, backend);
            if (fd == 0) return;
            for (int i = 0; i < N; i++)
                if (counts[i] != 0) $fwrite(fd, "%0d %0d\n", i, counts[i]);
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
            if (dump != "" && !ext_dumped) write(dump, "final");
        endfunction
    endclass

    // ------------------------------------------------- base of the groups
    // One coverage group = one covergroup of the model. The generated
    // subclass owns the bin tables of its points and a sample() with the
    // covergroup's own argument list (plus NA-defaulted spares); this base
    // only provides the lookups and the reporting.
    virtual class odve_cov_group;
        string name;

        function new(string name);
            this.name = name;
            odve_cov_store::init();
        endfunction

        // Table-driven value -> bin over one point's rows (lo, hi, kind, bidx):
        // a value/range row matches lo <= value <= hi, a wildcard row matches
        // (value & hi) == lo. Ignore/illegal rows are checked first, as the
        // LRM has it; then the coverage rows in table order; then a default
        // row. Returns the coverage bin index (bidx of the row), or
        // BIN_IGNORE / BIN_ILLEGAL / BIN_NONE.
        static function int find_bin(longint value, ref longint lo[], ref longint hi[],
                                     ref byte kind[], ref int bidx[]);
            int dflt = BIN_NONE;
            for (int i = 0; i < lo.size(); i++) begin
                case (kind[i])
                    K_IGNORE:       if (value >= lo[i] && value <= hi[i]) return BIN_IGNORE;
                    K_ILLEGAL:      if (value >= lo[i] && value <= hi[i]) return BIN_ILLEGAL;
                    K_IGNORE_WILD:  if ((value & hi[i]) == lo[i]) return BIN_IGNORE;
                    K_ILLEGAL_WILD: if ((value & hi[i]) == lo[i]) return BIN_ILLEGAL;
                    default: ;
                endcase
            end
            for (int i = 0; i < lo.size(); i++) begin
                case (kind[i])
                    K_BIN:      if (value >= lo[i] && value <= hi[i]) return bidx[i];
                    K_BIN_WILD: if ((value & hi[i]) == lo[i]) return bidx[i];
                    K_DEFAULT:  dflt = bidx[i];
                    default: ;
                endcase
            end
            return dflt;
        endfunction

        // Transition bins: hist[] holds the last hist.size() values of the
        // point (oldest first); tr[] is the flattened sequences, trlen[] their
        // lengths, trbidx[] the bin each one belongs to. Pushes `value` and
        // returns the first sequence the history now ends with, or -1.
        static function int find_trans(longint value, ref longint hist[], ref longint tr[],
                                       ref int trlen[], ref int trbidx[]);
            int off = 0;
            for (int i = 0; i < hist.size() - 1; i++) hist[i] = hist[i + 1];
            hist[hist.size() - 1] = value;
            for (int s = 0; s < trlen.size(); s++) begin
                int len = trlen[s];
                bit match = (len <= hist.size());
                for (int k = 0; match && k < len; k++)
                    if (hist[hist.size() - len + k] != tr[off + k]) match = 0;
                if (match) return trbidx[s];
                off += len;
            end
            return -1;
        endfunction

        function void illegal(string point, longint value);
            `ODVE_COV_ERR($sformatf("%s.%s: illegal bin hit by value %0d", name, point, value))
        endfunction

        // A generated sample() calls this on its spare formals.
        function void check_spare(longint a, int pos);
            if (a != NA)
                `ODVE_COV_ERR($sformatf("%s: sample() called with an argument in position %0d, but the covergroup declares fewer", name, pos))
        endfunction
    endclass

    // The generated group classes (covgen.py scan): one per covergroup found
    // in the sources' `ifdef ODVE_COV_NATIVE blocks, or a stub.
    `include "odve_cov_gen_classes.svh"

endpackage
`endif
