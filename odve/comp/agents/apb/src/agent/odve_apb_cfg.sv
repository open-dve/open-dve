class odve_apb_cfg extends uvm_object;
    `uvm_object_utils(odve_apb_cfg)

    odve_apb_role_e     role     = ODVE_APB_MASTER;
    odve_apb_slv_mode_e slv_mode = ODVE_APB_SLV_MEM;   // slave role only
    bit                 has_mon  = 1;                   // a second monitor on the same bus would double every observation
    virtual odve_apb_if vif;

    // slave, MEM mode: the memory it models
    int unsigned nregs      = 16;   // words at byte addresses 0 .. nregs*4-1; beyond -> pslverr
    int unsigned wait_every = 3;    // one wait state every wait_every-th transfer, 0 = never

    function new(string name = "odve_apb_cfg");
        super.new(name);
    endfunction
endclass
