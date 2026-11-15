`ifndef ODVE_SPI_AGENT_PKG
`define ODVE_SPI_AGENT_PKG
`ifndef ODVE_SPI_MAX_CS
`define ODVE_SPI_MAX_CS 4
`endif
package odve_spi_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_spi_item_pkg::*;

    typedef enum { ODVE_SPI_MASTER, ODVE_SPI_SLAVE }     odve_spi_role_e;
    typedef enum { ODVE_SPI_SLV_MEM, ODVE_SPI_SLV_SEQ }  odve_spi_slv_mode_e;   // model in the driver / in a sequence

    // Functional coverage of the frames on the bus (doc/fcov-plan.md 4.1),
    // sampled by the monitor once per frame (cs_n rise):
    //   mode      {cpol, cpha} 0..3        bits     word width
    //   lsb_first bit order                nwords   complete words in the frame
    //   cs        chip select              aborted  cs_n rose mid-word
    //   gap       an idle pause between words under one cs_n
`ifdef ODVE_COV_NATIVE
    covergroup odve_spi_cg with function sample(int mode, int bits, bit lsb_first, int nwords, int cs, bit aborted, bit gap);
        cp_mode:  coverpoint mode      { bins m[] = {[0:3]}; }
        cp_bits:  coverpoint bits      { bins b8 = {8}; bins b16 = {16}; bins b32 = {32}; }
        cp_order: coverpoint lsb_first { bins msb = {0}; bins lsb = {1}; }
        cp_len:   coverpoint nwords    { bins none = {0}; bins one = {1}; bins two = {2}; bins few = {[3:8]}; bins many = {[9:$]}; }
        cp_cs:    coverpoint cs        { bins sel[] = {[0:1]}; }
        cp_abort: coverpoint aborted   { bins complete = {0}; bins abort = {1}; }
        cp_gap:   coverpoint gap       { bins no_gap = {0}; bins gap = {1}; }
        x_mode_bits:  cross cp_mode, cp_bits;
        x_mode_order: cross cp_mode, cp_order;
    endgroup
`endif

    `include "odve_spi_cfg.sv"
    `include "odve_spi_slv_model.sv"
    `include "mon/odve_spi_mon.sv"
    `include "mst/odve_spi_mst_drv_base.sv"
    `include "slv/odve_spi_slv_drv.sv"
    `include "odve_spi_sqr.sv"
    `include "odve_spi_slv_sqr.sv"
    `include "odve_spi_agent.sv"
endpackage
`endif
