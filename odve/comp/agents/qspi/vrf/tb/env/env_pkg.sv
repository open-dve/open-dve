package env_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_qspi_item_pkg::*;
    import odve_qspi_agent_pkg::*;

    // Functional coverage of the flash behaviour the scoreboard checks
    // (doc/fcov-plan.md 4.1), one sample per frame:
    //   kind     0 read, 1 program, 2 erase, 3 write status, 4 WREN, 5 WRDI,
    //            6 status read, 7 JEDEC ID, 8 SFDP, 9 QPI enter/exit
    //   outcome  0 executed, 1 ignored: busy, 2 ignored: no WEL,
    //            3 ignored: QE clear, 4 ignored: not on a byte/bit boundary
    //   wrap     program wrapped inside its page / read wrapped at the end of the array
    //   overprog program tried to turn a 0 back into 1 (stays 0)
    //   busy     a status read returned BUSY = 1
`ifdef ODVE_COV_NATIVE
    covergroup qspi_flash_cg with function sample(int kind, int outcome, bit wrap, bit overprog, bit busy);
        cp_kind:     coverpoint kind     { bins read = {0}; bins prog = {1}; bins erase = {2}; bins wrsr = {3}; bins wren = {4};
                                           bins wrdi = {5}; bins rdsr = {6}; bins rdid = {7}; bins sfdp = {8}; bins qpi = {9}; }
        cp_outcome:  coverpoint outcome  { bins done = {0}; bins busy = {1}; bins no_wel = {2}; bins no_qe = {3}; bins inexact = {4}; }
        cp_wrap:     coverpoint wrap     { bins linear = {0}; bins wrapped = {1}; }
        cp_overprog: coverpoint overprog { bins clean = {0}; bins over = {1}; }
        cp_busy:     coverpoint busy     { bins ready = {0}; bins busy = {1}; }
    endgroup
`endif

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
