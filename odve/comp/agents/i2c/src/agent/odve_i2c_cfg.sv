// Configuration of one odve_i2c_agent. Times are in cycles of the interface
// clock (vif.clk); the defaults scale Standard-mode (100 kHz) to 1 cycle =
// 0.5 us, so an SCL period is 20 cycles (UM10204 Table 11 minima, rounded
// up: tLOW 4.7 us -> 10, tHIGH 4.0 us -> 8, tHD;STA 4.0 us -> 8,
// tSU;STA 4.7 us -> 10, tSU;STO 4.0 us -> 8, tBUF 4.7 us -> 10).
class odve_i2c_cfg extends uvm_object;
    `uvm_object_utils(odve_i2c_cfg)

    odve_i2c_role_e     role     = ODVE_I2C_MASTER;
    odve_i2c_slv_mode_e slv_mode = ODVE_I2C_SLV_MEM;   // slave role only
    bit                 has_mon  = 1;                   // one monitor per bus
    virtual odve_i2c_if vif;

    // master: the SCL it generates
    int unsigned t_low    = 10;
    int unsigned t_high   = 10;
    int unsigned t_hd_sta = 10;   // START: SDA low -> SCL low
    int unsigned t_su_sta = 10;   // repeated START: SCL high -> SDA low
    int unsigned t_su_sto = 10;   // STOP: SCL high -> SDA high
    int unsigned t_buf    = 10;   // bus free before a START

    // monitor: minima it checks (0 = not checked)
    int unsigned min_t_low    = 10;
    int unsigned min_t_high   = 8;
    int unsigned min_t_hd_sta = 8;
    int unsigned min_t_su_sto = 8;
    int unsigned min_t_buf    = 10;

    // slave (target): its addresses and model
    bit [6:0]    addr7     = 7'h50;
    bit [9:0]    addr10    = 10'h2A5;
    bit          en_addr7  = 1;
    bit          en_addr10 = 1;
    bit          gc_en     = 1;          // acknowledge the general call address
    int unsigned t_timeout = 0;          // release and reset after SCL low this long (SMBus tTIMEOUT), 0 = never
    odve_i2c_slv_model model;            // MEM mode: the target's behaviour (default: odve_i2c_mem_model)

    function new(string name = "odve_i2c_cfg");
        super.new(name);
    endfunction
endclass
