module top;
    
    import odve_uart_agent_pkg::*;
    
    dut dut();
    
    initial begin
        #30ns; 
        $display ("Hello Verilator");
        #10ns;
        $display ("First verialtor steps");
        #20ns;
        begin
            //odve_uart_driver drv = new();
            //for (int i=0; i < 10; i++) begin
            //    odve_uart_item item = new(); 
            //    item.odve_randomize();
            //    drv.drive_item(item);
            //end
        end 
    end 
endmodule 