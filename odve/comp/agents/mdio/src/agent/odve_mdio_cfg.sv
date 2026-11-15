class odve_mdio_cfg extends uvm_object;
    `uvm_object_utils(odve_mdio_cfg)

    odve_mdio_role_e     role     = ODVE_MDIO_MASTER;
    odve_mdio_slv_mode_e slv_mode = ODVE_MDIO_SLV_MEM;  // slave role only
    bit                  has_mon  = 1;                  // one monitor per bus
    virtual odve_mdio_if vif;

    // master (STA): MDC half period in system clocks. The PHY side samples
    // MDC/MDIO through a 2-flop synchronizer and changes its output 3 clocks
    // after the rising edge, so keep this >= 4.
    int unsigned mdc_half = 4;

    // PHY side (slave driver, monitor check, scoreboard model): frames with
    // fewer preamble ones than this are ignored (32 = no preamble suppression).
    int unsigned pre_min = 32;

    // slave, MEM mode: the PHYs/ports it plays (the register model of each,
    // see odve_mdio_phy_model)
    bit [4:0]    phyads[$] = '{5'd1};   // Clause 22 PHY addresses
    bit [4:0]    prtads[$] = '{5'd1};   // Clause 45 port addresses
    bit [15:0]   id1 = ODVE_MDIO_ID1;
    bit [15:0]   id2 = ODVE_MDIO_ID2;

    // monitor timing check (ns): STA-driven MDIO stable this long before and
    // after each MDC rising edge; PHY-driven MDIO stable t_su before it.
    realtime     t_su = 10.0;
    realtime     t_hold = 10.0;

    function new(string name = "odve_mdio_cfg");
        super.new(name);
    endfunction
endclass
