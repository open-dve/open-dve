// PHASE-0 SPIKE: hand-written stand-in for what `covgen.py scan` will
// generate into $(COV_DIR) (doc/fcov-plan.md 3.5, 4.1); the `acov` build
// step copies it there for now. Sizes the
// collector and names the model for the dump header.
`ifndef ODVE_COV_GEN_SVH
`define ODVE_COV_GEN_SVH
`define ODVE_COV_N     14          // total bins over all groups (flat layout, see odve_cov_apb_cg.sv)
`define ODVE_COV_MODEL "apb_cov"
`define ODVE_COV_HASH  "spike0"    // sha256 of the model in the real generator
`endif
