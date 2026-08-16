interface apb_if (
    input wire clk,
    input wire we,
    output wire data
);
logic data_r;

initial repeat (20) #10 data_r = $urandom_range(20, 10);

assign data=data_r;
endinterface 