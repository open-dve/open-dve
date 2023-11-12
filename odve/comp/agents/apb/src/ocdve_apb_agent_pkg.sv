`ifndef __OCDVE_APB_AGENT_PKG_SV
`define __OCDVE_APB_AGENT_PKG_SV
package ocdve_apb_agent_pkg;
    import uvm_pkg::*;
    import ocdve_common_pkg::*;

    typedef enum { APB_READ, APB_WRITE } ocdve_apb_kind_e;

    `include "ocdve_apb_agent_cfg.sv"
    `include "ocdve_apb_seq_item.sv"
    `include "ocdve_apb_monitor.sv"
    `include "ocdve_apb_driver_base.sv"
    `include "ocdve_apb_master_driver.sv"
    `include "ocdve_apb_slave_driver.sv"
    `include "ocdve_apb_agent.sv"
endpackage: ocdve_apb_agent_pkg
`endif
