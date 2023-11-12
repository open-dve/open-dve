module top;
    import uvm_pkg::*;
    import test_pkg::*;

    apb_if apb_if ();

    initial repeat (30) $display ("Hello world");
    // Точка входа для запуска UVM теста
    initial begin
        uvm_config_db #(uvm_object_wrapper)::set(null, "*", "uvm_test_top", read_test::type_id::get());
        run_test("read_test");
    end
endmodule 
