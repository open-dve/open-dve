class odve_rffe_cfg extends uvm_object;
    `uvm_object_utils(odve_rffe_cfg)

    odve_rffe_role_e     role     = ODVE_RFFE_MASTER;
    odve_rffe_slv_mode_e slv_mode = ODVE_RFFE_SLV_MEM;   // slave role only
    bit                  has_mon  = 1;                    // one monitor per bus, or every sequence is seen twice
    virtual odve_rffe_if vif;

    // master
    int unsigned sclk_half       = 2;   // TB clocks per SCLK half period (>= 2: the RTL slaves answer one clock after an edge)
    int unsigned idle_halfs      = 4;   // SCLK half periods of idle (SCLK and SDATA low) between sequences
    bit          half_speed_read = 0;   // read data frames at half the SCLK rate, sampled on the next rising edge

    // slave
    bit [3:0]    usid  = 4'h5;          // Unique Slave ID it answers to (and the broadcast ID 0 for writes)
    int unsigned nregs = 64;            // MEM mode: implemented registers 0..nregs-1, others read as NRF

    // monitor
    bit          chk_parity = 1;        // parity errors in master frames are UVM_ERRORs (clear for injection tests)

    function new(string name = "odve_rffe_cfg");
        super.new(name);
    endfunction
endclass
