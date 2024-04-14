class odve_uart_item;
    bit start;
    bit [7:0] data;
    bit parity;
    bit stop;
    function new ();
    endfunction 

    function randomize();
        data = $urandom();
    endfunction 
    
endclass 