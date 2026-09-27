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
// Flat layout in the collector (apb_cov.map.json is the same information for
// the scripts):  cp_len 0..3 | cp_dir 4..5 | x_len_dir 6..13   => ODVE_COV_N = 14
`ifdef ODVE_FCOV
class odve_cov_apb_cg extends odve_cov_pkg::odve_cov_group;
    localparam int B_LEN = 0, NB_LEN = 4;
    localparam int B_DIR = 4, NB_DIR = 2;
    localparam int B_X   = 6;                 // cross bin = len_bin * NB_DIR + dir_bin

    // bin tables: data, not code (doc/fcov-plan.md 3.4)
    int  len_lo[], len_hi[]; byte len_kind[];
    int  dir_lo[], dir_hi[]; byte dir_kind[];

    function new(string name = "apb_cg");
        super.new(name);
        //            one  some  big[8] big[16]  zero(ignore)  bad(illegal)
        len_lo   = '{ 1,   2,    8,     16,      0,            256 };
        len_hi   = '{ 1,   4,    8,     16,      0,            2147483647 };
        len_kind = '{ 0,   0,    0,     0,       1,            2 };
        dir_lo   = '{ 0, 1 };
        dir_hi   = '{ 0, 1 };
        dir_kind = '{ 0, 0 };
    endfunction

    function void sample(int len, bit dir);
        int bl = find_bin(len,       len_lo, len_hi, len_kind);
        int bd = find_bin(int'(dir), dir_lo, dir_hi, dir_kind);
        if (bl == odve_cov_pkg::BIN_ILLEGAL) illegal("cp_len", len);
        if (bl >= 0) vif.hit(B_LEN + bl);
        if (bd >= 0) vif.hit(B_DIR + bd);
        if (bl >= 0 && bd >= 0) vif.hit(B_X + bl * NB_DIR + bd);   // cross: same call, same values
    endfunction
endclass
`endif
