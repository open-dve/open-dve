module dut (
    input clk, rst 
);
    
    initial repeat (30) $display ("Hi from DUT");
endmodule 
