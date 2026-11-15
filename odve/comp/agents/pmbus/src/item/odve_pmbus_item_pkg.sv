`ifndef ODVE_PMBUS_ITEM_PKG
`define ODVE_PMBUS_ITEM_PKG
package odve_pmbus_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_smbus_item_pkg::*;

    // How a command is used (the SMBus protocol follows from the command's
    // transaction type, Part II Table 31)
    typedef enum int { PMB_WRITE = 0, PMB_READ = 1, PMB_SEND = 2 } odve_pmbus_op_e;

    // Data formats (Part II 7, 8)
    typedef enum int { PMB_FMT_RAW = 0, PMB_FMT_LINEAR11, PMB_FMT_ULINEAR16 } odve_pmbus_fmt_e;

    // Command codes (Part II Appendix I, Table 31) - the ones this agent names
    parameter bit [7:0] PMB_PAGE                = 8'h00;
    parameter bit [7:0] PMB_OPERATION           = 8'h01;
    parameter bit [7:0] PMB_ON_OFF_CONFIG       = 8'h02;
    parameter bit [7:0] PMB_CLEAR_FAULTS        = 8'h03;
    parameter bit [7:0] PMB_PHASE               = 8'h04;
    parameter bit [7:0] PMB_WRITE_PROTECT       = 8'h10;
    parameter bit [7:0] PMB_STORE_DEFAULT_ALL   = 8'h11;
    parameter bit [7:0] PMB_RESTORE_DEFAULT_ALL = 8'h12;
    parameter bit [7:0] PMB_CAPABILITY          = 8'h19;
    parameter bit [7:0] PMB_VOUT_MODE           = 8'h20;
    parameter bit [7:0] PMB_VOUT_COMMAND        = 8'h21;
    parameter bit [7:0] PMB_VOUT_TRIM           = 8'h22;
    parameter bit [7:0] PMB_VOUT_CAL_OFFSET     = 8'h23;
    parameter bit [7:0] PMB_VOUT_MAX            = 8'h24;
    parameter bit [7:0] PMB_STATUS_BYTE         = 8'h78;
    parameter bit [7:0] PMB_STATUS_WORD         = 8'h79;
    parameter bit [7:0] PMB_STATUS_VOUT         = 8'h7A;
    parameter bit [7:0] PMB_STATUS_IOUT         = 8'h7B;
    parameter bit [7:0] PMB_STATUS_CML          = 8'h7E;
    parameter bit [7:0] PMB_READ_VIN            = 8'h88;
    parameter bit [7:0] PMB_READ_VOUT           = 8'h8B;
    parameter bit [7:0] PMB_READ_IOUT           = 8'h8C;
    parameter bit [7:0] PMB_READ_TEMPERATURE_1  = 8'h8D;
    parameter bit [7:0] PMB_PMBUS_REVISION      = 8'h98;
    parameter bit [7:0] PMB_MFR_ID              = 8'h99;

    // STATUS_BYTE bits (17.1) and STATUS_CML bits (17.7, Table 21)
    parameter int PMB_SB_BUSY = 7, PMB_SB_OFF = 6, PMB_SB_CML = 1;
    parameter int PMB_CML_CMD = 7, PMB_CML_DATA = 6, PMB_CML_PEC = 5, PMB_CML_OTHER = 1;

    // SMBus transaction type of a command, per Table 31 (SMB_CMD_NONE: not named here)
    function automatic odve_smbus_cmd_e odve_pmbus_cmd_kind(bit [7:0] c);
        case (c)
            PMB_PAGE, PMB_OPERATION, PMB_ON_OFF_CONFIG, PMB_PHASE, PMB_WRITE_PROTECT, PMB_CAPABILITY,
            PMB_VOUT_MODE, PMB_STATUS_BYTE, PMB_STATUS_VOUT, PMB_STATUS_IOUT, PMB_STATUS_CML,
            PMB_PMBUS_REVISION:                                           return SMB_CMD_BYTE;
            PMB_CLEAR_FAULTS, PMB_STORE_DEFAULT_ALL, PMB_RESTORE_DEFAULT_ALL: return SMB_CMD_SEND;
            PMB_VOUT_COMMAND, PMB_VOUT_TRIM, PMB_VOUT_CAL_OFFSET, PMB_VOUT_MAX, PMB_STATUS_WORD,
            PMB_READ_VIN, PMB_READ_VOUT, PMB_READ_IOUT, PMB_READ_TEMPERATURE_1: return SMB_CMD_WORD;
            PMB_MFR_ID:                                                   return SMB_CMD_BLOCK;
            default:                                                      return SMB_CMD_NONE;
        endcase
    endfunction

    // Table 31 "N/A" for writing
    function automatic bit odve_pmbus_read_only(bit [7:0] c);
        return c inside {PMB_CAPABILITY, PMB_READ_VIN, PMB_READ_VOUT, PMB_READ_IOUT, PMB_READ_TEMPERATURE_1, PMB_PMBUS_REVISION};
    endfunction

    function automatic odve_pmbus_fmt_e odve_pmbus_fmt(bit [7:0] c);
        case (c)
            PMB_VOUT_COMMAND, PMB_VOUT_TRIM, PMB_VOUT_CAL_OFFSET, PMB_VOUT_MAX, PMB_READ_VOUT: return PMB_FMT_ULINEAR16;
            PMB_READ_VIN, PMB_READ_IOUT, PMB_READ_TEMPERATURE_1:                               return PMB_FMT_LINEAR11;
            default:                                                                          return PMB_FMT_RAW;
        endcase
    endfunction

    function automatic string odve_pmbus_cmd_name(bit [7:0] c);
        case (c)
            PMB_PAGE:                return "PAGE";
            PMB_OPERATION:           return "OPERATION";
            PMB_ON_OFF_CONFIG:       return "ON_OFF_CONFIG";
            PMB_CLEAR_FAULTS:        return "CLEAR_FAULTS";
            PMB_PHASE:               return "PHASE";
            PMB_WRITE_PROTECT:       return "WRITE_PROTECT";
            PMB_STORE_DEFAULT_ALL:   return "STORE_DEFAULT_ALL";
            PMB_RESTORE_DEFAULT_ALL: return "RESTORE_DEFAULT_ALL";
            PMB_CAPABILITY:          return "CAPABILITY";
            PMB_VOUT_MODE:           return "VOUT_MODE";
            PMB_VOUT_COMMAND:        return "VOUT_COMMAND";
            PMB_VOUT_TRIM:           return "VOUT_TRIM";
            PMB_VOUT_CAL_OFFSET:     return "VOUT_CAL_OFFSET";
            PMB_VOUT_MAX:            return "VOUT_MAX";
            PMB_STATUS_BYTE:         return "STATUS_BYTE";
            PMB_STATUS_WORD:         return "STATUS_WORD";
            PMB_STATUS_VOUT:         return "STATUS_VOUT";
            PMB_STATUS_IOUT:         return "STATUS_IOUT";
            PMB_STATUS_CML:          return "STATUS_CML";
            PMB_READ_VIN:            return "READ_VIN";
            PMB_READ_VOUT:           return "READ_VOUT";
            PMB_READ_IOUT:           return "READ_IOUT";
            PMB_READ_TEMPERATURE_1:  return "READ_TEMPERATURE_1";
            PMB_PMBUS_REVISION:      return "PMBUS_REVISION";
            PMB_MFR_ID:              return "MFR_ID";
            default:                 return $sformatf("CMD_%02Xh", c);
        endcase
    endfunction

    // LINEAR11 (7.3): X = Y * 2^N, Y 11-bit and N 5-bit two's complement, N in [15:11]
    function automatic real odve_pmbus_lin11_to_real(bit [15:0] v);
        int y = $signed(v[10:0]);
        int n = $signed(v[15:11]);
        return (n >= 0) ? real'(y) * real'(1 << n) : real'(y) / real'(1 << -n);
    endfunction

    // the LINEAR11 code of x with exponent n (mantissa rounded to nearest, saturated)
    function automatic bit [15:0] odve_pmbus_real_to_lin11(real x, int n);
        real m = (n >= 0) ? x / real'(1 << n) : x * real'(1 << -n);
        int  y = (m >= 0.0) ? $rtoi(m + 0.5) : -$rtoi(-m + 0.5);   // $rtoi truncates; int'() would round again
        if (y > 1023)  y = 1023;
        if (y < -1024) y = -1024;
        return {5'(n), 11'(y)};
    endfunction

    // ULINEAR16 (8.4.1.1): Voltage = V * 2^N, N from VOUT_MODE[4:0] (two's complement)
    function automatic real odve_pmbus_ulin16_to_real(bit [15:0] v, bit [4:0] vout_mode_exp);
        int n = $signed(vout_mode_exp);
        return (n >= 0) ? real'(v) * real'(1 << n) : real'(v) / real'(1 << -n);
    endfunction

    function automatic bit [15:0] odve_pmbus_real_to_ulin16(real volts, bit [4:0] vout_mode_exp);
        int  n = $signed(vout_mode_exp);
        real m = (n >= 0) ? volts / real'(1 << n) : volts * real'(1 << -n);
        if (m < 0.0) m = 0.0;
        if (m > 65535.0) m = 65535.0;
        return 16'($rtoi(m + 0.5));
    endfunction

    `include "odve_pmbus_item.sv"
endpackage
`endif
