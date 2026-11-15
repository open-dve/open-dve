// Bus-level format every agent on the bus must agree on (QSPI carries no mode
// information on the wire): the env hands the same object to all cfgs, and
// the sequence that switches the flash to or from QPI updates it.
class odve_qspi_bus_cfg extends uvm_object;
    `uvm_object_utils(odve_qspi_bus_cfg)
    bit          cpol      = 0;    // SPI mode 0 (sclk idles low) or 3 (idles high); data in on rising, out on falling edges either way
    bit          qpi       = 0;    // the flash is in QPI mode: set by the sequence that sent 38h / FFh
    int unsigned qpi_dummy = 2;    // dummy clocks of 0Bh/EBh in QPI (power-up default)
    function new(string name = "odve_qspi_bus_cfg");
        super.new(name);
    endfunction
endclass

class odve_qspi_cfg extends uvm_object;
    `uvm_object_utils(odve_qspi_cfg)

    odve_qspi_role_e     role     = ODVE_QSPI_MASTER;
    odve_qspi_slv_mode_e slv_mode = ODVE_QSPI_SLV_MEM;   // slave role only
    bit                  has_mon  = 1;                   // one monitor per bus
    virtual odve_qspi_if vif;

    odve_qspi_bus_cfg bus;         // shared bus format (cpol, qpi, qpi_dummy)

    // master timing, system clock cycles
    int unsigned half_period = 4;
    int unsigned lead        = 4;  // cs_n fall -> first sclk edge   (tSLCH)
    int unsigned trail       = 4;  // last sclk edge -> cs_n rise    (tCHSH)
    int unsigned idle        = 4;  // cs_n high between frames       (tSHSL)
    // monitor limits, 0 = half_period
    int unsigned min_lead    = 0;
    int unsigned min_trail   = 0;
    int unsigned min_idle    = 0;
    bit          chk_undriven = 1; // QSPI_IO_Z: no driver on a lane the protocol says is driven

    // slave role: the behavioural flash
    int unsigned mem_bytes = 8192;           // two 4 KiB sectors, 32 pages
    int unsigned tpp       = 1500;           // page program busy time (cycles)
    int unsigned tse       = 5000;           // sector erase busy time
    int unsigned tw        = 200;            // write status register busy time
    bit [7:0]    mfr_id    = 8'hEF;          // JEDEC ID: manufacturer,
    bit [7:0]    type_spi  = 8'h40;          //   memory type in SPI mode,
    bit [7:0]    type_qpi  = 8'h60;          //   in QPI mode,
    bit [7:0]    cap_id    = 8'h0D;          //   capacity 2^13 bytes

    function new(string name = "odve_qspi_cfg");
        super.new(name);
        bus = odve_qspi_bus_cfg::type_id::create("bus");
    endfunction

    function int unsigned min_t(int unsigned v);
        return (v != 0) ? v : half_period;
    endfunction
endclass
