class odve_jtag_cfg extends uvm_object;
    `uvm_object_utils(odve_jtag_cfg)

    odve_jtag_role_e     role     = ODVE_JTAG_MASTER;
    odve_jtag_slv_mode_e slv_mode = ODVE_JTAG_SLV_MEM;   // slave role only
    bit                  has_mon  = 1;                    // one monitor per bus
    virtual odve_jtag_if vif;

    // master: TCK = clk / (2 * tck_half)
    int unsigned tck_half = 1;
    int unsigned ir_len   = 4;      // IR length of the chain the master talks to (coverage only)

    // monitor checks
    bit check_ir_capture = 1;       // the first two bits out of an IR scan must be 1, 0 (01 captured)
    bit check_tdo_oe     = 1;       // TDO driven exactly in Shift-IR/Shift-DR

    // slave: the TAP it models (SLV_MEM; in SLV_SEQ the sequence owns the data registers)
    bit [31:0]   idcode         = 32'h1234_5679;
    bit [7:0]    pins           = 8'hA5;
    bit          err_ir_capture = 0;   // fault injection: Capture-IR loads 0000
    bit          err_tdo_oe     = 0;   // fault injection: TDO enabled outside the Shift states

    function new(string name = "odve_jtag_cfg");
        super.new(name);
    endfunction
endclass
