module top;
    import odve_uart_agent_pkg::*;
    initial begin
        #3ns; 
        $display ("Hello Verilator");
        #10ns;
        $display ("First verialtor steps");
        begin
            odve_uart_driver drv = new();
            for (int i=0; i < 10; i++) begin
                odve_uart_item item = new(); 
                item.randomize();
                drv.drive_item(item);
            end
        end 
    end 
endmodule 