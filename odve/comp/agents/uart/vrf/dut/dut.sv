module dut;
    initial begin
        #5ns; 
        $display ("Hello DUT");
        #10ns;
        $display ("By DUT");
    end 
endmodule