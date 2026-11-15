// Behavioural registers of one TAP: the instruction register and the data
// registers it selects. Used by the slave driver (SLV_MEM), the responding
// sequence (SLV_SEQ) and the testbench's scoreboard, so all three agree on
// what a TAP captures and updates:
//   EXTEST, SAMPLE/PRELOAD  8-bit boundary register: captures pins, Update latches bsr_upd
//   IDCODE                  32-bit identification register (bit 0 = 1), read only
//   USERDATA                32-bit read/write user register
//   BYPASS / unassigned     1-bit bypass register, captures 0
// Test-Logic-Reset selects IDCODE; TRST_n (full reset) also clears USERDATA
// and the boundary update latch.
class odve_jtag_tap_model extends uvm_object;
    `uvm_object_utils(odve_jtag_tap_model)

    int unsigned ir_len  = 4;
    bit [31:0]   idcode  = 32'h1234_5679;
    bit [7:0]    pins    = 8'hA5;     // what SAMPLE/EXTEST capture
    bit          err_ir_capture = 0;  // fault injection: Capture-IR loads 0000

    bit [3:0]    ir      = ODVE_JTAG_IDCODE;
    bit [31:0]   user    = '0;
    bit [7:0]    bsr_upd = '0;

    function new(string name = "odve_jtag_tap_model");
        super.new(name);
    endfunction

    function void reset(bit full);
        ir = ODVE_JTAG_IDCODE;
        if (full) begin
            user    = '0;
            bsr_upd = '0;
        end
    endfunction

    function bit [3:0] capture_ir();
        return err_ir_capture ? 4'b0000 : ODVE_JTAG_IR_CAPTURE;
    endfunction

    function void update_ir(odve_jtag_vec_t v);
        ir = v[3:0];
    endfunction

    // length and captured value of the data register `instr` selects
    function void capture_dr(bit [3:0] instr, output int unsigned len, output odve_jtag_vec_t cap);
        cap = '0;
        case (instr)
            ODVE_JTAG_EXTEST, ODVE_JTAG_SAMPLE: begin len = 8;  cap[7:0]  = pins;   end
            ODVE_JTAG_IDCODE:                   begin len = 32; cap[31:0] = idcode; end
            ODVE_JTAG_USERDATA:                 begin len = 32; cap[31:0] = user;   end
            default:                            begin len = 1;  cap[0]    = 1'b0;   end
        endcase
    endfunction

    function void update_dr(bit [3:0] instr, odve_jtag_vec_t v);
        case (instr)
            ODVE_JTAG_EXTEST, ODVE_JTAG_SAMPLE: bsr_upd = v[7:0];
            ODVE_JTAG_USERDATA:                 user    = v[31:0];
            default: ;
        endcase
    endfunction
endclass
