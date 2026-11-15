`ifndef ODVE_QSPI_AGENT_PKG
`define ODVE_QSPI_AGENT_PKG
package odve_qspi_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_qspi_item_pkg::*;

    typedef enum { ODVE_QSPI_MASTER, ODVE_QSPI_SLAVE }     odve_qspi_role_e;
    typedef enum { ODVE_QSPI_SLV_MEM, ODVE_QSPI_SLV_SEQ }  odve_qspi_slv_mode_e;   // flash model in the driver / in a sequence

    // Functional coverage of the frames on the bus (doc/fcov-plan.md 4.1),
    // sampled by the monitor at every cs_n rise:
    //   cmd    opcode               fmt  lanes cmd-addr-data (111, 144, 444, ...)
    //   qpi    QPI mode             len  data bytes moved
    //   cut    1 = truncated / ended mid-byte     mode3  sclk idles high
`ifdef ODVE_COV_NATIVE
    covergroup odve_qspi_cg with function sample(int cmd, int fmt, bit qpi, int len, bit cut, bit mode3);
        cp_cmd:  coverpoint cmd  { bins wren = {6}; bins wrdi = {4}; bins rdsr1 = {5}; bins rdsr2 = {53}; bins wrsr2 = {49};
                                   bins rdid = {159}; bins read = {3}; bins fread = {11}; bins dor = {59}; bins dior = {187};
                                   bins qor = {107}; bins qior = {235}; bins pp = {2}; bins qpp = {50}; bins se = {32};
                                   bins sfdp = {90}; bins qpien = {56}; bins qpiex = {255}; }
        cp_fmt:  coverpoint fmt  { bins f111 = {111}; bins f112 = {112}; bins f122 = {122}; bins f114 = {114};
                                   bins f144 = {144}; bins f444 = {444}; bins f110 = {110}; bins f440 = {440};
                                   bins f100 = {100}; bins f101 = {101}; bins f400 = {400}; bins f404 = {404}; }
        cp_qpi:  coverpoint qpi  { bins spi = {0}; bins qpi = {1}; }
        cp_len:  coverpoint len  { bins none = {0}; bins one = {1}; bins few = {[2:16]}; bins many = {[17:255]}; bins page = {256}; bins over = {[257:$]}; }
        cp_cut:  coverpoint cut  { bins whole = {0}; bins cut = {1}; }
        cp_mode: coverpoint mode3 { bins mode0 = {0}; bins mode3 = {1}; }
        x_qpi_mode: cross cp_qpi, cp_mode;
    endgroup
`endif

    `include "odve_qspi_cfg.sv"
    `include "odve_qspi_flash_model.sv"
    `include "odve_qspi_decoder.sv"
    `include "mon/odve_qspi_mon.sv"
    `include "mst/odve_qspi_mst_drv_base.sv"
    `include "slv/odve_qspi_slv_drv.sv"
    `include "odve_qspi_sqr.sv"
    `include "odve_qspi_slv_sqr.sv"
    `include "odve_qspi_agent.sv"
endpackage
`endif
