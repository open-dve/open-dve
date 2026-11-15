`ifndef ODVE_SMBUS_ITEM_PKG
`define ODVE_SMBUS_ITEM_PKG
package odve_smbus_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // SMBus 3.3 section 6.5 bus protocols (+ the Alert Response Address read, A.2)
    typedef enum int {
        SMB_QUICK_W = 0, SMB_QUICK_R, SMB_SEND_BYTE, SMB_RECV_BYTE,
        SMB_WRITE_BYTE, SMB_READ_BYTE, SMB_WRITE_WORD, SMB_READ_WORD,
        SMB_PROC_CALL, SMB_BLOCK_WRITE, SMB_BLOCK_READ, SMB_BLOCK_PROC_CALL,
        SMB_ARA, SMB_UNKNOWN
    } odve_smbus_proto_e;

    // What a command code of a device means: the protocols it is used with.
    typedef enum int {
        SMB_CMD_NONE = 0,   // not supported
        SMB_CMD_SEND,       // Send Byte (the command code is the message)
        SMB_CMD_BYTE,       // Write Byte / Read Byte
        SMB_CMD_WORD,       // Write Word / Read Word
        SMB_CMD_PCALL,      // Process Call
        SMB_CMD_BLOCK,      // Block Write / Block Read
        SMB_CMD_BPCALL      // Block Write-Block Read Process Call
    } odve_smbus_cmd_e;

    parameter bit [6:0] SMB_ARA_ADDR = 7'h0C;   // Alert Response Address 0001 100

    // PEC: CRC-8, C(x) = x^8 + x^2 + x + 1, MSB first, initial 0 (SMBus 3.3 6.4)
    function automatic bit [7:0] odve_smbus_crc8(bit [7:0] crc, bit [7:0] data);
        bit [7:0] x = crc ^ data;
        for (int i = 0; i < 8; i++) x = x[7] ? ({x[6:0], 1'b0} ^ 8'h07) : {x[6:0], 1'b0};
        return x;
    endfunction

    function automatic bit [7:0] odve_smbus_pec(bit [7:0] bytes[$]);
        bit [7:0] c = 8'h00;
        foreach (bytes[i]) c = odve_smbus_crc8(c, bytes[i]);
        return c;
    endfunction

    function automatic string odve_smbus_proto_str(odve_smbus_proto_e p);
        case (p)
            SMB_QUICK_W:         return "QUICK_W";
            SMB_QUICK_R:         return "QUICK_R";
            SMB_SEND_BYTE:       return "SEND_BYTE";
            SMB_RECV_BYTE:       return "RECV_BYTE";
            SMB_WRITE_BYTE:      return "WRITE_BYTE";
            SMB_READ_BYTE:       return "READ_BYTE";
            SMB_WRITE_WORD:      return "WRITE_WORD";
            SMB_READ_WORD:       return "READ_WORD";
            SMB_PROC_CALL:       return "PROC_CALL";
            SMB_BLOCK_WRITE:     return "BLOCK_WRITE";
            SMB_BLOCK_READ:      return "BLOCK_READ";
            SMB_BLOCK_PROC_CALL: return "BLOCK_PROC_CALL";
            SMB_ARA:             return "ARA";
            default:             return "UNKNOWN";
        endcase
    endfunction

    `include "odve_smbus_item.sv"
endpackage
`endif
