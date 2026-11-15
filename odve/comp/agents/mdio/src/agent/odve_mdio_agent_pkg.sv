`ifndef ODVE_MDIO_AGENT_PKG
`define ODVE_MDIO_AGENT_PKG
package odve_mdio_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_mdio_item_pkg::*;

    typedef enum { ODVE_MDIO_MASTER, ODVE_MDIO_SLAVE }      odve_mdio_role_e;      // STA / PHY
    typedef enum { ODVE_MDIO_SLV_MEM, ODVE_MDIO_SLV_SEQ }   odve_mdio_slv_mode_e;  // model in the driver / in a sequence

    // Register map shared by the PHY model (odve_mdio_phy_model) and the RTL
    // PHY of vrf/dut (top passes these as its parameters).
    parameter bit [15:0] ODVE_MDIO_ID1      = 16'h4F44;   // PHY identifier 1 / MMD device identifier 1
    parameter bit [15:0] ODVE_MDIO_ID2      = 16'h5645;   // PHY identifier 2 / MMD device identifier 2
    parameter bit [15:0] ODVE_MDIO_BMCR_RST = 16'h1140;   // C22 reg 0 reset value
    parameter bit [15:0] ODVE_MDIO_BMSR     = 16'h780D;   // C22 reg 1: 100/10 FD/HD, AN ability, link, ext. capability; bit 6 (MF preamble suppression) = 0
    parameter bit [15:0] ODVE_MDIO_MMD_STAT = 16'h0004;   // C45 reg 1 of each MMD
    parameter bit [15:0] ODVE_MDIO_DEVS     = 16'h000A;   // C45 reg 5: MMDs 1 and 3 present
    parameter bit [4:0]  ODVE_MDIO_MMD_PMA  = 5'd1;
    parameter bit [4:0]  ODVE_MDIO_MMD_PCS  = 5'd3;
    parameter int        ODVE_MDIO_NRW45    = 16;         // C45 RW window 0x8000.. per MMD

    // Functional coverage of the bus traffic (doc/fcov-plan.md 4.1): a real
    // covergroup at package scope, sampled by the monitor through
    // `odve_cov_sample. With FCOV=1 the build turns it into
    // odve_cov_pkg::odve_cov_odve_mdio_cg.
`ifdef ODVE_COV_NATIVE
    covergroup odve_mdio_cg with function sample(int kind, int phyad, int regad, bit resp, int pre_len, bit is_c22, bit is_c45, bit is_rd);
        cp_kind:  coverpoint kind  { bins c22_wr = {0}; bins c22_rd = {1}; bins c45_addr = {2}; bins c45_wr = {3};
                                     bins c45_rd = {4}; bins c45_rinc = {5}; bins c22_badop = {6}; }
        cp_phyad: coverpoint phyad { bins a0 = {0}; bins a1 = {1}; bins a2_3 = {[2:3]}; bins a_hi = {[4:31]}; }
        cp_c22_reg: coverpoint regad iff (is_c22) { bins ctrl = {0}; bins status = {1}; bins id1 = {2}; bins id2 = {3};
                                                    bins rw_lo = {[4:15]}; bins rw_hi = {[16:31]}; }
        cp_c45_dev: coverpoint regad iff (is_c45) { bins pma = {1}; bins pcs = {3}; bins absent = {0, 2, [4:31]}; }
        cp_resp:  coverpoint resp iff (is_rd) { bins no_resp = {0}; bins answered = {1}; }
        cp_rkind: coverpoint kind iff (is_rd) { bins c22_rd = {1}; bins c45_rd = {4}; bins c45_rinc = {5}; }
        cp_pre:   coverpoint pre_len { bins pre_short = {[0:31]}; bins pre_std = {32}; bins pre_long = {[33:$]}; }
        cp_seq:   coverpoint kind  { bins addr_then_wr = (2 => 3); bins addr_then_rd = (2 => 4); bins addr_then_rinc = (2 => 5);
                                     bins rinc_rinc = (5 => 5); bins c22_wr_rd = (0 => 1); bins c22_rd_rd = (1 => 1); }
        x_rkind_resp: cross cp_rkind, cp_resp;
    endgroup
`endif

    `include "odve_mdio_cfg.sv"
    `include "odve_mdio_phy_model.sv"
    `include "mon/odve_mdio_mon.sv"
    `include "mst/odve_mdio_mst_drv_base.sv"
    `include "slv/odve_mdio_slv_drv.sv"
    `include "odve_mdio_sqr.sv"
    `include "odve_mdio_slv_sqr.sv"
    `include "odve_mdio_agent.sv"
endpackage
`endif
