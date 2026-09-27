`define odve_rand ( obj ) \
obj.user_randomize();

// Functional coverage (doc/fcov-plan.md 4.1): expand to nothing unless the
// build was made with FCOV=1, so sampling code costs nothing by default.
// The sample arguments travel as one parenthesised tuple - the parentheses
// keep the preprocessor from splitting them into macro arguments, and there
// is no variadic macro in SystemVerilog:
//     `odve_cov_sample(cg, (item.len, item.dir))   ->   cg.sample (item.len, item.dir);
`ifdef ODVE_FCOV
`define odve_cov_sample(grp, args) grp.sample args;
`else
`define odve_cov_sample(grp, args)
`endif