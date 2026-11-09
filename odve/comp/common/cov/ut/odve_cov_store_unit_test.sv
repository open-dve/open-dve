// Unit tests of the functional-coverage runtime (odve_cov_pkg), built
// standalone (svunit.f: no UVM, COVCNT=4, a 16-bin model). Run with
// `make ut` / `make ut VERILATOR=1` in this folder.
`include "svunit_defines.svh"

module odve_cov_store_unit_test;
    import svunit_pkg::svunit_testcase;
    import odve_cov_pkg::*;

    string name = "odve_cov_store_ut";
    svunit_testcase svunit_ut;

    typedef odve_cov_store store;

    function void build();
        svunit_ut = new(name);
    endfunction

    task setup();
        svunit_ut.setup();
        store::cnt      = '0;
        store::nsamples = 0;
        store::every    = 0;
        store::seq      = 0;
        store::dump     = "";
        store::test     = "";
        store::inited   = 1;      // plusargs are the subject of one test only
        store::frozen   = 0;
        store::ext_dumped = 0;
        store::emu      = 0;
        store::smp_q.delete();
        odve_cov_errors = 0;
    endtask

    task teardown();
        svunit_ut.teardown();
    endtask

    // Reads a dump file into `lines`; returns 0 when it cannot be opened.
    function automatic bit read_file(string path, ref string lines[$]);
        int fd = $fopen(path, "r");
        string line;
        lines.delete();
        if (fd == 0) return 0;
        while ($fgets(line, fd) != 0) begin
            if (line.len() > 0 && line.getc(line.len() - 1) == 8'h0A) line = line.substr(0, line.len() - 2);
            lines.push_back(line);
        end
        $fclose(fd);
        return 1;
    endfunction

    `SVUNIT_TESTS_BEGIN

    `SVTEST(hit_counts_and_saturates_at_all_ones)
        repeat (3) store::hit(2);
        `FAIL_UNLESS_EQUAL(store::cnt[2], 3)
        repeat (20) store::hit(5);
        `FAIL_UNLESS_EQUAL(store::cnt[5], 15)          // COVCNT=4: saturates at 4'b1111
        `FAIL_UNLESS_EQUAL(store::cnt[0], 0)
        `FAIL_UNLESS_EQUAL(store::nsamples, 23)
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 0)
    `SVTEST_END

    `SVTEST(hit_out_of_range_is_an_error_and_no_write)
        store::hit(-1);
        store::hit(odve_cov_pkg::N);
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 2)
        `FAIL_UNLESS_EQUAL(store::nsamples, 0)
    `SVTEST_END

    `SVTEST(find_bin_values_ranges_ignore_illegal)
        longint lo[]   = '{1, 2, 8, 0, 256};
        longint hi[]   = '{1, 4, 8, 0, 64'h7FFF_FFFF_FFFF_FFFF};
        byte    kind[] = '{K_BIN, K_BIN, K_BIN, K_IGNORE, K_ILLEGAL};
        int     bidx[] = '{0, 1, 2, -1, -1};
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(1,   lo, hi, kind, bidx), 0)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(3,   lo, hi, kind, bidx), 1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(4,   lo, hi, kind, bidx), 1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(8,   lo, hi, kind, bidx), 2)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(0,   lo, hi, kind, bidx), BIN_IGNORE)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(300, lo, hi, kind, bidx), BIN_ILLEGAL)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(5,   lo, hi, kind, bidx), BIN_NONE)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(-7,  lo, hi, kind, bidx), BIN_NONE)
    `SVTEST_END

    `SVTEST(find_bin_ignore_wins_over_a_coverage_row)
        longint lo[]   = '{0, 5};
        longint hi[]   = '{9, 5};
        byte    kind[] = '{K_BIN, K_IGNORE};
        int     bidx[] = '{0, -1};
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(5, lo, hi, kind, bidx), BIN_IGNORE)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(6, lo, hi, kind, bidx), 0)
    `SVTEST_END

    `SVTEST(find_bin_wildcard_and_default)
        // wildcard bins w = {8'b1???_0000}: value 0x80, care mask clears bits 6..4
        longint lo[]   = '{64'h80, 0};
        longint hi[]   = '{64'hFFFF_FFFF_FFFF_FF8F, 0};
        byte    kind[] = '{K_BIN_WILD, K_DEFAULT};
        int     bidx[] = '{0, 1};
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(64'hA0,  lo, hi, kind, bidx), 0)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(64'hF0,  lo, hi, kind, bidx), 0)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(64'h0F,  lo, hi, kind, bidx), 1)   // default
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_bin(64'h1A0, lo, hi, kind, bidx), 1)   // bit 8 set: not the wildcard
    `SVTEST_END

    `SVTEST(find_trans_sequences_over_a_history)
        longint hist[]   = new[3];
        longint tr[]     = '{1, 2,  2, 3, 4};   // (1 => 2), (2 => 3 => 4)
        int     trlen[]  = '{2, 3};
        int     trbidx[] = '{0, 1};
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(1, hist, tr, trlen, trbidx), -1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(2, hist, tr, trlen, trbidx), 0)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(3, hist, tr, trlen, trbidx), -1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(4, hist, tr, trlen, trbidx), 1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(1, hist, tr, trlen, trbidx), -1)
        `FAIL_UNLESS_EQUAL(odve_cov_group::find_trans(2, hist, tr, trlen, trbidx), 0)
    `SVTEST_END

    `SVTEST(dump_checkpoints_and_final_file)
        string lines[$];
        bit ok;
        store::dump  = "ut_cov.dump";
        store::test  = "ut_test";
        store::every = 3;
        store::hit(1); store::hit(1); store::hit(4);            // 3 hits -> checkpoint 1 in .1
        ok = read_file("ut_cov.dump.1", lines);
        `FAIL_UNLESS(ok)
        `FAIL_UNLESS_STR_EQUAL(lines[$], "# end 1")
        store::hit(1); store::hit(9); store::hit(9);            // 6 hits -> checkpoint 2 in .0
        ok = read_file("ut_cov.dump.0", lines);
        `FAIL_UNLESS(ok)
        `FAIL_UNLESS_STR_EQUAL(lines[$], "# end 2")
        `FAIL_UNLESS_EQUAL(store::seq, 2)
        store::final_dump();
        ok = read_file("ut_cov.dump", lines);
        `FAIL_UNLESS(ok)
        `FAIL_UNLESS_EQUAL(lines.size(), 8)
        `FAIL_UNLESS_STR_EQUAL(lines[0], "# odve-cov 1")
        `FAIL_UNLESS_STR_EQUAL(lines[1], "# model ut hash ut0")
        `FAIL_UNLESS_STR_EQUAL(lines[2], "# test ut_test covcnt 4 n 16")
        `FAIL_UNLESS_STR_EQUAL(lines[3], "# samples 6")
        `FAIL_UNLESS_STR_EQUAL(lines[4], "1 3")
        `FAIL_UNLESS_STR_EQUAL(lines[5], "4 1")
        `FAIL_UNLESS_STR_EQUAL(lines[6], "9 2")
        `FAIL_UNLESS_STR_EQUAL(lines[7], "# end final")
    `SVTEST_END

    `SVTEST(no_dump_path_means_no_checkpoints)
        store::dump  = "";
        store::every = 1;
        store::hit(3);
        store::hit(3);
        store::final_dump();
        `FAIL_UNLESS_EQUAL(store::seq, 0)
        `FAIL_UNLESS_EQUAL(store::cnt[3], 2)
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 0)
    `SVTEST_END

    `SVTEST(frozen_drops_hits_silently)
        store::hit(2);
        store::frozen = 1;
        store::hit(2);
        store::hit(6);
        `FAIL_UNLESS_EQUAL(store::cnt[2], 1)
        `FAIL_UNLESS_EQUAL(store::cnt[6], 0)
        `FAIL_UNLESS_EQUAL(store::nsamples, 1)
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 0)
    `SVTEST_END

    `SVTEST(emu_mirrors_hits_into_the_sample_queue)
        store::hit(3);                       // emu off: not queued
        store::emu = 1;
        store::hit(3);
        store::hit(7);
        store::hit(odve_cov_pkg::N);         // out of range: error, not queued
        store::frozen = 1;
        store::hit(7);                       // frozen: not queued
        `FAIL_UNLESS_EQUAL(store::smp_q.size(), 2)
        `FAIL_UNLESS_EQUAL(store::smp_q[0], 3)
        `FAIL_UNLESS_EQUAL(store::smp_q[1], 7)
        `FAIL_UNLESS_EQUAL(store::cnt[3], 2)
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 1)
    `SVTEST_END

    `SVTEST(write_ext_writes_the_backend_counts_and_final_dump_yields)
        string lines[$];
        int unsigned counts[] = new[odve_cov_pkg::N];
        bit ok;
        store::test = "ut_test";
        counts[5] = 4;
        counts[15] = 1;
        store::write_ext("ut_ext.dump", "final", counts, 5, "emu");
        ok = read_file("ut_ext.dump", lines);
        `FAIL_UNLESS(ok)
        `FAIL_UNLESS_EQUAL(lines.size(), 8)
        `FAIL_UNLESS_STR_EQUAL(lines[3], "# samples 5")
        `FAIL_UNLESS_STR_EQUAL(lines[4], "# backend emu")
        `FAIL_UNLESS_STR_EQUAL(lines[5], "5 4")
        `FAIL_UNLESS_STR_EQUAL(lines[6], "15 1")
        `FAIL_UNLESS_STR_EQUAL(lines[7], "# end final")
        // the store's own final dump leaves a file another backend wrote
        store::dump = "ut_ext.dump";
        store::ext_dumped = 1;
        store::hit(1);
        store::final_dump();
        ok = read_file("ut_ext.dump", lines);
        `FAIL_UNLESS(ok)
        `FAIL_UNLESS_STR_EQUAL(lines[4], "# backend emu")
        // a wrong size is an error and no file
        counts = new[3];
        store::write_ext("ut_ext_bad.dump", "final", counts, 0, "emu");
        `FAIL_UNLESS_EQUAL(odve_cov_errors, 1)
        ok = read_file("ut_ext_bad.dump", lines);
        `FAIL_IF(ok)
    `SVTEST_END

    `SVTEST(init_reads_the_plusargs)
        // `make ut UT_ARGS="+odve_cov_dump=pa.dump +odve_cov_test=pa +odve_cov_every=7"`
        // supplies them; without them init() must leave the defaults.
        store::inited = 0;
        store::init();
        if ($test$plusargs("odve_cov_dump")) begin
            `FAIL_UNLESS_STR_EQUAL(store::dump, "pa.dump")
            `FAIL_UNLESS_STR_EQUAL(store::test, "pa")
            `FAIL_UNLESS_EQUAL(store::every, 7)
        end else begin
            `FAIL_UNLESS_STR_EQUAL(store::dump, "")
            `FAIL_UNLESS_EQUAL(store::every, 0)
        end
        `FAIL_UNLESS(store::inited)
    `SVTEST_END

    `SVUNIT_TESTS_END

endmodule
