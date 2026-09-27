// Functional-coverage collector (phase-0 spike, see odve/doc/fcov-plan.md).
//
// One flat memory of bin counters shared by every coverage group in the
// testbench, plus the dump logic. The generated code (odve_cov_gen.svh) sizes
// it (ODVE_COV_N = total bins) and knows which flat index is which bin; the
// interface itself knows nothing about groups, points or names - it counts.
//
// Compiled to nothing without FCOV=1 (+define+ODVE_FCOV).
`ifdef ODVE_FCOV
`include "odve_cov_gen.svh"

`ifndef ODVE_COVCNT
`define ODVE_COVCNT 1
`endif

// The strings the dump header needs live in a package, not in the interface:
// a string member of an interface reached through a virtual interface is
// unsupported by Verilator ("virtual interface trigger on 'string' type").
// (A comment must not start with the tool's name either - that is a pragma.)
package odve_cov_if_pkg;
    string dump  = "";   // +odve_cov_dump: file to write; "" = no dump
    string test  = "";   // +odve_cov_test: test name for the header
    string model = "";   // set by the first group constructed (odve_cov_pkg)
    string hash  = "";
endpackage

interface odve_cov_if #(parameter int N = `ODVE_COV_N, parameter int W = `ODVE_COVCNT);
    import odve_cov_if_pkg::*;

    // Packed 2-D so that COVCNT=1 is a plain bit vector on both simulators
    // (an unpacked array of 1-bit elements is stored per element by ModelSim).
    // Every counter saturates at all-ones.
    bit [N-1:0][W-1:0] cnt;

    longint unsigned nsamples = 0;   // hit() calls since start, drives checkpoints
    int unsigned     every    = 0;   // +odve_cov_every: checkpoint period in hits, 0 = none
    int unsigned     seq      = 0;   // checkpoint sequence number

    initial begin
        if (!$value$plusargs("odve_cov_dump=%s", dump)) dump = "";
        if (!$value$plusargs("odve_cov_test=%s", test)) test = "";
        if (!$value$plusargs("odve_cov_every=%d", every)) every = 0;
    end

    // The one hot path: increment a bin, saturating.
    function automatic void hit(int idx);
        if (idx < 0 || idx >= N) begin
            $display("ODVE_COV: bin index %0d out of range (N=%0d) - ignored", idx, N);
            return;
        end
        if (cnt[idx] != {W{1'b1}}) cnt[idx] = cnt[idx] + 1'b1;
        nsamples++;
        if (every != 0 && (nsamples % every) == 0) checkpoint();
    endfunction

    // Dump format (doc/fcov-plan.md 4.2): header lines, then "idx count" for
    // non-zero bins only, then a closing "# end <tag>" line. A reader treats a
    // file without the closing line as truncated.
    function automatic void write(string path, string tag);
        int fd = $fopen(path, "w");
        if (fd == 0) begin
            $display("ODVE_COV: cannot open %s for writing", path);
            return;
        end
        $fwrite(fd, "# odve-cov 1\n");
        $fwrite(fd, "# model %s hash %s\n", model, hash);
        $fwrite(fd, "# test %s covcnt %0d n %0d\n", test, W, N);
        $fwrite(fd, "# samples %0d\n", nsamples);
        for (int i = 0; i < N; i++)
            if (cnt[i] != 0) $fwrite(fd, "%0d %0d\n", i, cnt[i]);
        $fwrite(fd, "# end %s\n", tag);
        $fclose(fd);
    endfunction

    // Checkpoints alternate between <dump>.0 and <dump>.1 (a kill during the
    // write of one leaves the other intact); the final dump is <dump> itself.
    function automatic void checkpoint();
        if (dump == "") return;
        seq++;
        write($sformatf("%s.%0d", dump, seq % 2), $sformatf("%0d", seq));
    endfunction

    final begin
        if (dump != "") write(dump, "final");
    end

endinterface
`endif
