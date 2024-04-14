module top;
    initial begin
        #3ns; 
        $display ("Hello Verilator");
        #10ns;
        $display ("First verialtor steps");
    end 
endmodule 