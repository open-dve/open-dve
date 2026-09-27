`define odve_rand ( obj ) \
obj.user_randomize();

// Functional coverage (doc/fcov-plan.md 4.1): expand to nothing unless the
// build was made with FCOV=1, so sampling code costs nothing by default.
//     `odve_cov_sample(cg, item.len, item.dir)   ->   cg.sample(item.len, item.dir, NA, NA, NA, NA, NA, NA);
// SystemVerilog has no variadic macros, so up to 8 values are accepted and
// the unused positions carry odve_cov_pkg::NA; a generated sample() declares
// its spare formals with that default and reports any real value there.
`ifdef ODVE_FCOV
`define odve_cov_sample(grp, a1, a2=odve_cov_pkg::NA, a3=odve_cov_pkg::NA, a4=odve_cov_pkg::NA, a5=odve_cov_pkg::NA, a6=odve_cov_pkg::NA, a7=odve_cov_pkg::NA, a8=odve_cov_pkg::NA) \
    grp.sample(a1, a2, a3, a4, a5, a6, a7, a8);
`else
`define odve_cov_sample(grp, a1, a2=, a3=, a4=, a5=, a6=, a7=, a8=)
`endif