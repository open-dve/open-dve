`ifndef ODVE_MACRO_SV
`define ODVE_MACRO_SV
`define odve_rand(obj) obj.user_randomize();

// Functional coverage (doc/fcov-plan.md 4.1). The covergroup itself is written
// in standard syntax inside an `ifdef ODVE_COV_NATIVE block at package scope;
// with FCOV=1 `covgen.py scan` turns it into odve_cov_pkg::odve_cov_<name>,
// and these two macros are the only thing the testbench code carries:
//
//     `odve_cov_create(apb_cg)                    // class property: the group object apb_cg_i
//     `odve_cov_sample(apb_cg, item.len, item.dir)  // apb_cg_i.sample(item.len, item.dir, NA, ...)
//
// Both expand to nothing unless the build was made with FCOV=1, so sampling
// code costs nothing by default. SystemVerilog has no variadic macros, so up
// to 8 values are accepted and the unused positions carry odve_cov_pkg::NA;
// a generated sample() declares its spare formals with that default and
// reports any real value there as an arity error.
`ifdef ODVE_FCOV
`define odve_cov_create(NAME) odve_cov_pkg::odve_cov_``NAME NAME``_i = new(`"NAME`");
`define odve_cov_sample(grp, a1, a2=odve_cov_pkg::NA, a3=odve_cov_pkg::NA, a4=odve_cov_pkg::NA, a5=odve_cov_pkg::NA, a6=odve_cov_pkg::NA, a7=odve_cov_pkg::NA, a8=odve_cov_pkg::NA) \
    grp``_i.sample(a1, a2, a3, a4, a5, a6, a7, a8);
`else
`define odve_cov_create(NAME)
`define odve_cov_sample(grp, a1, a2=, a3=, a4=, a5=, a6=, a7=, a8=)
`endif
`endif
