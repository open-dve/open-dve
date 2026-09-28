// The one piece of the functional-coverage flow that is not a package: by
// the LRM a `final` block is a module item, so this module - one instance
// in top, under `ifdef ODVE_FCOV - writes the last dump. Everything else is
// odve_cov_pkg::odve_cov_store, package-static.
`ifdef ODVE_FCOV
module odve_cov_final;
    initial odve_cov_pkg::odve_cov_store::init();        // plusargs, as early as possible
    final   odve_cov_pkg::odve_cov_store::final_dump();
endmodule
`endif
