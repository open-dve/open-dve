class odve_uart_item;
    bit start;
    bit [7:0] data;
    bit parity;
    bit stop;
    function new ();
    endfunction 

    function void odve_randomize();
        int urd= $urandom;
        data = urd[7:0];
    endfunction 

endclass 