// Configuration of one odve_pmbus_agent. The agent builds an smbus agent
// ("smb", itself on an i2c agent) and derives its odve_smbus_cfg from this
// one (or uses smb_cfg when set before build): the smbus monitor decodes
// every command by its Part II Table 31 transaction type.
class odve_pmbus_cfg extends uvm_object;
    `uvm_object_utils(odve_pmbus_cfg)

    odve_pmbus_role_e     role     = ODVE_PMBUS_MASTER;
    odve_pmbus_slv_mode_e slv_mode = ODVE_PMBUS_SLV_MEM;
    bit                   has_mon  = 1;
    virtual odve_smbus_if vif;          // SMBALERT#
    virtual odve_i2c_if   i2c_vif;      // SMBCLK/SMBDAT
    odve_smbus_cfg        smb_cfg;      // optional: the transport's cfg (else derived)

    bit [6:0]             addr   = 7'h40;   // slave: the device address
    odve_pmbus_dev_model  model;            // slave: default odve_pmbus_dev_model
    int unsigned          npages = 2;       // monitor: valid PAGE values 0..npages-1
    bit [4:0]             vout_exp = 5'h17; // monitor/host: VOUT_MODE exponent until a VOUT_MODE read is seen (-9)

    function new(string name = "odve_pmbus_cfg");
        super.new(name);
    endfunction
endclass
