// Format straps of the two RTL slaves (not SPI signals): the env drives them
// from the shared odve_spi_dev_cfg of each chip select, so the DUT and the
// agents always agree on the mode. Changed only between frames.
interface spi_strap_if;
    logic [1:0] cpol, cpha, lsb_first;
    logic [1:0] wsel [2];
endinterface
