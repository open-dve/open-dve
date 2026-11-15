// Configuration of one odve_smbus_agent. The agent builds an i2c agent
// ("i2c") underneath as its transport and derives that agent's
// odve_i2c_cfg from this one (or uses i2c_cfg when set before build).
// Times in cycles of the interface clock; SMBus timeouts are scaled to
// 1 ms = 20 cycles (100x faster than the 1 cycle = 0.5 us bit timing of the
// i2c defaults, so a timeout test stays short):
//   tTIMEOUT,MIN 25 ms -> 500, tTIMEOUT,MAX 35 ms -> 700, tLOW:SEXT 25 ms -> 500
class odve_smbus_cfg extends uvm_object;
    `uvm_object_utils(odve_smbus_cfg)

    odve_smbus_role_e     role     = ODVE_SMBUS_MASTER;
    odve_smbus_slv_mode_e slv_mode = ODVE_SMBUS_SLV_MEM;
    bit                   has_mon  = 1;
    virtual odve_smbus_if vif;          // SMBALERT#
    virtual odve_i2c_if   i2c_vif;      // SMBCLK/SMBDAT
    odve_i2c_cfg          i2c_cfg;      // optional: the transport's cfg (else derived)

    // slave: address and device model (default odve_smbus_ref_model)
    bit [6:0]             addr = 7'h3A;
    odve_smbus_dev_model  model;

    // monitor: what each command code of the device on the bus means
    odve_smbus_cmd_e      cmd_tab[256];

    int unsigned t_timeout_min = 500;   // monitor: SCL low this long = a timeout
    int unsigned t_timeout_max = 700;   // monitor: a target must have released the bus by then
    int unsigned t_timeout_dev = 600;   // slave: resets its interface after SCL low this long
    int unsigned t_low_sext    = 500;   // monitor: cumulative target clock stretching per message

    function new(string name = "odve_smbus_cfg");
        super.new(name);
        foreach (cmd_tab[i]) cmd_tab[i] = SMB_CMD_NONE;
    endfunction

    function void set_cmds(bit [7:0] lo, bit [7:0] hi, odve_smbus_cmd_e k);
        for (int c = lo; c <= hi; c++) cmd_tab[c] = k;
    endfunction

    // the command set of odve_smbus_ref_model / the TB's RTL device
    function void set_ref_cmds();
        set_cmds(8'h00, 8'h07, SMB_CMD_BYTE);
        set_cmds(8'h10, 8'h13, SMB_CMD_WORD);
        set_cmds(8'h20, 8'h20, SMB_CMD_PCALL);
        set_cmds(8'h30, 8'h30, SMB_CMD_BLOCK);
        set_cmds(8'h31, 8'h31, SMB_CMD_BPCALL);
        set_cmds(8'h40, 8'h41, SMB_CMD_SEND);
    endfunction
endclass
