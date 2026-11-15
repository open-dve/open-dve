// Configuration of one odve_i3c_agent. role = controller (MASTER) or target
// (SLAVE); a target is autonomous (MEM: register file inside the driver) or
// reactive (SEQ: private-transfer data from a responding sequence).
class odve_i3c_cfg extends uvm_object;
    `uvm_object_utils(odve_i3c_cfg)

    odve_i3c_role_e     role     = ODVE_I3C_MASTER;
    odve_i3c_slv_mode_e slv_mode = ODVE_I3C_SLV_MEM;   // target role only
    bit                 has_mon  = 1;                   // one monitor per bus
    virtual odve_i3c_if vif;

    // ---- controller: SCL timing in clk cycles (low >= 3, high >= 3) and policy
    int unsigned t_low       = 3;
    int unsigned t_high      = 3;
    int unsigned t_buf       = 4;   // bus free time after STOP
    bit          ibi_ack     = 1;   // ACK In-Band Interrupts (else NACK, then Sr / P)
    bit          hj_ack      = 1;   // ACK Hot-Join requests
    int unsigned ibi_max_len = 8;   // IBI payload bytes taken before aborting

    // ---- monitor
    bit          perr_is_error = 1; // a wrong write T-bit is a UVM_ERROR (clear it when injecting)

    // ---- target: identity and register model
    bit [47:0]   pid         = 48'h14B4_0001_7000;
    bit [7:0]    bcr         = 8'h02;      // IBI capable, no payload
    bit [7:0]    dcr         = 8'h00;
    bit [6:0]    static_addr = 7'h00;      // for SETDASA, 0 = none
    int unsigned nregs       = 16;
    int unsigned t_aval      = 8;          // idle clks before a START request (IBI / Hot-Join)
    bit          offline     = 0;          // ignores the bus entirely (not powered yet, for Hot-Join)

    function new(string name = "odve_i3c_cfg");
        super.new(name);
    endfunction
endclass
