`ifndef __OCDVE_APB_IF_SV
`define __OCDVE_APB_IF_SV
interface ocdve_apb_if#(parameter PADDR_WIDTH = 32,
                        parameter DATA_WIDTH  = 32)
                                                   ( input logic clk    ,
                                                     input logic reset_n,
                                                     // Master's signals
                                                     wire [PADDR_WIDTH-1:0] paddr  ,
                                                     wire /*[PSEL_WIDTH -1:0]*/ psel   ,
                                                     wire                   penable,
                                                     wire                   pwrite ,
                                                     wire [DATA_WIDTH -1:0] pwdata ,
                                                     // Slave's signals
                                                     wire                   pready ,
                                                     wire [DATA_WIDTH -1:0] prdata ,
                                                     wire                   pslverr  );
    logic [PADDR_WIDTH-1:0] paddr_l   = 'bz;
    logic /*[PSEL_WIDTH -1:0]*/ psel_l    = 'bz;
    logic                   penable_l = 'bz;
    logic                   pwrite_l  = 'bz;
    logic [DATA_WIDTH-1:0]  pwdata_l  = 'bz;
    logic                   pready_l  = 'bz;
    logic [DATA_WIDTH-1:0]  prdata_l  = 'bz;
    logic                   pslverr_l = 'bz; 
    assign paddr   = paddr_l  ;
    assign psel    = psel_l   ;
    assign penable = penable_l;
    assign pwrite  = pwrite_l ;
    assign pwdata  = pwdata_l ;
    assign pready  = pready_l ;
    assign prdata  = prdata_l ;
    assign pslverr = pslverr_l;
endinterface : ocdve_apb_if
`endif                  