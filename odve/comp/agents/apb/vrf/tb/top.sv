module top;
    import uvm_pkg::*;
    import test_pkg::*;

    apb_if apb_if ();
`ifdef ODVE_FCOV
    odve_cov_if cov_if ();    // the functional-coverage collector (FCOV=1 only)
`endif

    initial repeat (1) $display ("Hello From TB");
    // Точка входа для запуска UVM теста
    initial begin
`ifdef ODVE_FCOV
        uvm_config_db #(virtual odve_cov_if)::set(null, "*", "odve_cov_vif", cov_if);
`endif
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", read_test::type_id::get());
        run_test("read_test");
    end
endmodule 
