// PHASE-0 SPIKE: hand-written stand-in for the class `covgen.py scan` will
// generate (doc/fcov-plan.md 4.1) from this covergroup, which is what the
// testbench source would carry inside an `ifdef ODVE_COV_NATIVE block:
//
//   covergroup apb_cg with function sample(int len, bit dir);
//     cp_len: coverpoint len { bins one = {1}; bins some = {[2:4]}; bins big[] = {8, 16};
//                              ignore_bins zero = {0}; illegal_bins bad = {[256:$]}; }
//     cp_dir: coverpoint dir { bins rd = {0}; bins wr = {1}; }
//     x_len_dir: cross cp_len, cp_dir;
//   endgroup
//
// Flat layout in the store (gen.spike/apb_cov.map.json is the same information
// for the scripts):  cp_len 0..3 | cp_dir 4..5 | x_len_dir 6..13  => ODVE_COV_N = 14
`ifdef ODVE_FCOV
class odve_cov_apb_cg extends odve_cov_pkg::odve_cov_group;
    localparam int B_LEN = 0, NB_LEN = 4;
    localparam int B_DIR = 4, NB_DIR = 2;
    localparam int B_X   = 6;                 // cross bin = len_bin * NB_DIR + dir_bin

    // bin tables: data, not code (doc/fcov-plan.md 3.4)
    longint len_lo[], len_hi[]; byte len_kind[];
    longint dir_lo[], dir_hi[]; byte dir_kind[];

    function new(string name = "apb_cg");
        super.new(name);
        //            one  some  big[8] big[16]  zero(ignore)  bad(illegal)
        len_lo   = '{ 1,   2,    8,     16,      0,            256 };
        len_hi   = '{ 1,   4,    8,     16,      0,            64'h7FFF_FFFF_FFFF_FFFF };
        len_kind = '{ 0,   0,    0,     0,       1,            2 };
        dir_lo   = '{ 0, 1 };
        dir_hi   = '{ 0, 1 };
        dir_kind = '{ 0, 0 };
    endfunction

    // The covergroup's own arguments first, then NA-defaulted spares up to 8:
    // `odve_cov_sample always passes eight, so the call is complete and an
    // extra argument is an error rather than silently dropped.
    function void sample(longint len, longint dir,
                         longint a3 = odve_cov_pkg::NA, longint a4 = odve_cov_pkg::NA,
                         longint a5 = odve_cov_pkg::NA, longint a6 = odve_cov_pkg::NA,
                         longint a7 = odve_cov_pkg::NA, longint a8 = odve_cov_pkg::NA);
        int bl, bd;
        check_spare(a3, 3); check_spare(a4, 4); check_spare(a5, 5);
        check_spare(a6, 6); check_spare(a7, 7); check_spare(a8, 8);
        bl = find_bin(len, len_lo, len_hi, len_kind);
        bd = find_bin(dir, dir_lo, dir_hi, dir_kind);
        if (bl == odve_cov_pkg::BIN_ILLEGAL) illegal("cp_len", len);
        if (bl >= 0) odve_cov_pkg::odve_cov_store::hit(B_LEN + bl);
        if (bd >= 0) odve_cov_pkg::odve_cov_store::hit(B_DIR + bd);
        if (bl >= 0 && bd >= 0) odve_cov_pkg::odve_cov_store::hit(B_X + bl * NB_DIR + bd);   // cross: same call, same values
    endfunction
endclass
`endif
