interface apb_if (
    wire clk,
    wire we,
    wire data
);
logic data_r;

initial repeat (20) #10 data_r = $urandom_range(20, 10);

assign data=data_r;
endinterface 