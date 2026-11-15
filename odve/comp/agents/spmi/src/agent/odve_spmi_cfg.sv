class odve_spmi_cfg extends uvm_object;
    `uvm_object_utils(odve_spmi_cfg)

    odve_spmi_role_e     role     = ODVE_SPMI_MASTER;
    odve_spmi_slv_mode_e slv_mode = ODVE_SPMI_SLV_MEM;   // slave role only
    bit                  has_mon  = 1;                    // one monitor per bus, or every sequence is seen twice
    virtual odve_spmi_if vif;

    // master
    int unsigned sclk_half       = 2;   // TB clocks per SCLK half period (>= 2: the RTL slaves answer one clock after an edge)
    int unsigned idle_halfs      = 4;   // SCLK half periods of idle (SCLK and SDATA low) between sequences

    // slave
    bit [3:0]    sid   = 4'h5;          // Slave ID it answers to
    int unsigned nregs = 64;            // MEM mode: implemented registers 0..nregs-1, then the read-only
                                        // power-state register at nregs, others read as NRF

    // monitor
    bit          chk_parity = 1;        // parity errors in master frames and NACKs are UVM_ERRORs (clear for injection tests)

    function new(string name = "odve_spmi_cfg");
        super.new(name);
    endfunction
endclass
