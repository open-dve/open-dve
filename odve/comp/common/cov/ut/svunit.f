// the runtime under test, standalone: no UVM, 4-bit counters so saturation
// is reachable, a fixed 16-bin model from odve_cov_gen.svh next to this file
+define+ODVE_FCOV
+define+ODVE_COVCNT=4
+define+ODVE_COV_NO_UVM
+incdir+${ODVE}/comp/common/cov/ut
${ODVE}/comp/common/cov/odve_cov_pkg.sv
