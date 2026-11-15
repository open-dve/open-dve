// Format of one slave (one chip select). SPI carries no mode information on
// the wire: master, slave and monitor must agree out of band, so every agent
// on the bus shares these objects (the env hands the same handles to all
// cfgs) and a test changes a slave's mode only between frames.
class odve_spi_dev_cfg extends uvm_object;
    `uvm_object_utils(odve_spi_dev_cfg)

    bit          cpol      = 0;    // sclk idle level
    bit          cpha      = 0;    // 0: sample on the leading edge, 1: on the trailing edge
    bit          lsb_first = 0;    // block guide LSBFE
    int unsigned word_bits = 8;    // 8, 16 or 32 (any 1..32 works in the agent)

    function new(string name = "odve_spi_dev_cfg");
        super.new(name);
    endfunction

    function int unsigned mode();
        return {cpol, cpha};
    endfunction

    function string convert2string();
        return $sformatf("mode%0d (cpol=%0b cpha=%0b) %s-first %0d-bit", mode(), cpol, cpha, lsb_first ? "LSB" : "MSB", word_bits);
    endfunction
endclass

class odve_spi_cfg extends uvm_object;
    `uvm_object_utils(odve_spi_cfg)

    odve_spi_role_e     role     = ODVE_SPI_MASTER;
    odve_spi_slv_mode_e slv_mode = ODVE_SPI_SLV_MEM;   // slave role only
    bit                 has_mon  = 1;                   // one monitor per bus
    virtual odve_spi_if vif;

    int unsigned        ncs = 1;                         // chip selects in use (<= ODVE_SPI_MAX_CS)
    odve_spi_dev_cfg    dev[`ODVE_SPI_MAX_CS];           // per chip select

    // master timing, system clock cycles (block guide figure 4-2/4-3)
    int unsigned half_period = 4;    // sclk high / low time
    int unsigned lead        = 4;    // tL: cs_n fall -> first edge
    int unsigned trail       = 4;    // tT: last edge -> cs_n rise
    int unsigned idle        = 4;    // tI: cs_n high between frames
    // monitor limits; 0 = half_period (the block guide's minimum: 1/2 SCK each)
    int unsigned min_lead    = 0;
    int unsigned min_trail   = 0;
    int unsigned min_idle    = 0;

    // slave role: the chip select it answers and its register model
    int unsigned        slv_cs = 0;
    bit [7:0]           slv_id = 8'hA5;
    int unsigned        slv_nbytes = 64;

    function int unsigned min_t(int unsigned v);
        return (v != 0) ? v : half_period;
    endfunction

    function new(string name = "odve_spi_cfg");
        super.new(name);
        foreach (dev[i]) dev[i] = odve_spi_dev_cfg::type_id::create($sformatf("dev%0d", i));
    endfunction
endclass
