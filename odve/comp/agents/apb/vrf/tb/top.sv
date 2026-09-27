module top;
    import uvm_pkg::*;
    import test_pkg::*;

    apb_if apb_if ();
`ifdef ODVE_FCOV
    odve_cov_final cov_final ();    // writes the functional-coverage dump at `final (FCOV=1 only)
`endif

    initial repeat (1) $display ("Hello From TB");
    // Точка входа для запуска UVM теста
    initial begin
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", read_test::type_id::get());
        run_test("read_test");
    end
endmodule 
