class odve_uart_driver;
    function new ();
        $display ("Create driver");
    endfunction 

    task run_item(odve_uart_item item);
        repeat(1) $display (item.data);
    endtask 
endclass 