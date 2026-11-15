`ifndef ODVE_QSPI_ITEM_PKG
`define ODVE_QSPI_ITEM_PKG
package odve_qspi_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // Opcodes (Winbond W25Q32FV datasheet rev. H, instruction set tables
    // 8.1.2 - 8.1.4; doc/spec.md lists what is modelled).
    localparam bit [7:0] QSPI_WREN  = 8'h06;   // write enable
    localparam bit [7:0] QSPI_WRDI  = 8'h04;   // write disable
    localparam bit [7:0] QSPI_RDSR1 = 8'h05;   // read status register 1 (BUSY, WEL)
    localparam bit [7:0] QSPI_RDSR2 = 8'h35;   // read status register 2 (QE)
    localparam bit [7:0] QSPI_WRSR2 = 8'h31;   // write status register 2
    localparam bit [7:0] QSPI_RDID  = 8'h9F;   // read JEDEC ID
    localparam bit [7:0] QSPI_READ  = 8'h03;   // read data              1-1-1
    localparam bit [7:0] QSPI_FREAD = 8'h0B;   // fast read              1-1-1 / 4-4-4
    localparam bit [7:0] QSPI_DOR   = 8'h3B;   // fast read dual output  1-1-2
    localparam bit [7:0] QSPI_DIOR  = 8'hBB;   // fast read dual I/O     1-2-2
    localparam bit [7:0] QSPI_QOR   = 8'h6B;   // fast read quad output  1-1-4
    localparam bit [7:0] QSPI_QIOR  = 8'hEB;   // fast read quad I/O     1-4-4 / 4-4-4
    localparam bit [7:0] QSPI_PP    = 8'h02;   // page program           1-1-1 / 4-4-4
    localparam bit [7:0] QSPI_QPP   = 8'h32;   // quad page program      1-1-4
    localparam bit [7:0] QSPI_SE    = 8'h20;   // sector erase (4 KiB)
    localparam bit [7:0] QSPI_SFDP  = 8'h5A;   // read SFDP              1-1-1
    localparam bit [7:0] QSPI_QPIEN = 8'h38;   // enter QPI
    localparam bit [7:0] QSPI_QPIEX = 8'hFF;   // exit QPI

    // Shape of one command on the wire. Clock counts are rising sclk edges.
    typedef struct {
        bit          valid;        // a known opcode in this mode (SPI / QPI)
        int unsigned cmd_lanes;    // 1 (IO0) or 4 (QPI)
        int unsigned addr_lanes;   // 0 = no address, else 1, 2 or 4 (24 bits)
        int unsigned mode_clks;    // clocks of M7-0 after the address, master-driven on the address lanes
        int unsigned dummy_clks;   // further clocks nobody drives
        int unsigned data_lanes;   // 0 = no data phase; 1 = IO0 in / IO1 out; 2 = IO[1:0]; 4 = IO[3:0]
        bit          data_out;     // data flows slave -> master
        bit          needs_qe;     // ignored by the flash unless status bit QE is set
        int unsigned fmt_code;     // 111, 112, 122, 114, 144, 444, 110, 100, 101, 440, 400, 404 (cmd-addr-data lanes)
    } odve_qspi_fmt_t;

    // qpi_dummy: dummy clocks of 0Bh/EBh in QPI (datasheet 8.2.34: 2 after
    // power-up; for EBh the M7-0 clocks count as dummy clocks).
    function automatic odve_qspi_fmt_t odve_qspi_fmt(bit [7:0] cmd, bit qpi, int unsigned qpi_dummy = 2);
        odve_qspi_fmt_t f;
        f = '{valid: 1, cmd_lanes: qpi ? 4 : 1, addr_lanes: 0, mode_clks: 0, dummy_clks: 0,
              data_lanes: 0, data_out: 0, needs_qe: 0, fmt_code: 0};
        if (!qpi) begin
            case (cmd)
                QSPI_WREN, QSPI_WRDI:   ;
                QSPI_QPIEN:             f.needs_qe = 1;
                QSPI_RDSR1, QSPI_RDSR2,
                QSPI_RDID:              begin f.data_lanes = 1; f.data_out = 1; end
                QSPI_WRSR2:             f.data_lanes = 1;
                QSPI_READ:              begin f.addr_lanes = 1; f.data_lanes = 1; f.data_out = 1; end
                QSPI_FREAD, QSPI_SFDP:  begin f.addr_lanes = 1; f.dummy_clks = 8; f.data_lanes = 1; f.data_out = 1; end
                QSPI_DOR:               begin f.addr_lanes = 1; f.dummy_clks = 8; f.data_lanes = 2; f.data_out = 1; end
                QSPI_DIOR:              begin f.addr_lanes = 2; f.mode_clks = 4;  f.data_lanes = 2; f.data_out = 1; end
                QSPI_QOR:               begin f.addr_lanes = 1; f.dummy_clks = 8; f.data_lanes = 4; f.data_out = 1; f.needs_qe = 1; end
                QSPI_QIOR:              begin f.addr_lanes = 4; f.mode_clks = 2; f.dummy_clks = 4; f.data_lanes = 4; f.data_out = 1; f.needs_qe = 1; end
                QSPI_PP:                begin f.addr_lanes = 1; f.data_lanes = 1; end
                QSPI_QPP:               begin f.addr_lanes = 1; f.data_lanes = 4; f.needs_qe = 1; end
                QSPI_SE:                f.addr_lanes = 1;
                default:                f.valid = 0;
            endcase
        end else begin
            case (cmd)
                QSPI_WREN, QSPI_WRDI,
                QSPI_QPIEX:             ;
                QSPI_RDSR1, QSPI_RDSR2,
                QSPI_RDID:              begin f.data_lanes = 4; f.data_out = 1; end
                QSPI_WRSR2:             f.data_lanes = 4;
                QSPI_FREAD:             begin f.addr_lanes = 4; f.dummy_clks = qpi_dummy; f.data_lanes = 4; f.data_out = 1; end
                QSPI_QIOR:              begin f.addr_lanes = 4; f.mode_clks = 2; f.dummy_clks = (qpi_dummy > 2) ? qpi_dummy - 2 : 0;
                                              f.data_lanes = 4; f.data_out = 1; end
                QSPI_PP:                begin f.addr_lanes = 4; f.data_lanes = 4; end
                QSPI_SE:                f.addr_lanes = 4;
                default:                f.valid = 0;
            endcase
        end
        f.fmt_code = 100 * f.cmd_lanes + 10 * f.addr_lanes + f.data_lanes;
        return f;
    endfunction

    // what a reactive slave driver asks its sequence (cfg.slv_mode == SEQ)
    typedef enum { ODVE_QSPI_REQ_NONE, ODVE_QSPI_REQ_DECODE, ODVE_QSPI_REQ_BYTE, ODVE_QSPI_REQ_END } odve_qspi_slv_req_e;

    function automatic int unsigned odve_qspi_hdr_clks(odve_qspi_fmt_t f);
        return 8 / f.cmd_lanes + (f.addr_lanes ? 24 / f.addr_lanes : 0) + f.mode_clks + f.dummy_clks;
    endfunction

    `include "odve_qspi_item.sv"
endpackage
`endif
