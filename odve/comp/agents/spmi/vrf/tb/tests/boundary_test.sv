// Boundary lengths and addresses: 1 and 16 bytes (8 long), the first and
// last register of each range, bursts running past the last implemented
// register (the power-state register at 0x40, NRF beyond), the 8-bit and 16-bit address wrap, Register 0 Write
// with 0x00 / 0x7F. REQ-SPMI-012..017, 021, 026.
class boundary_test extends base_test;
    `uvm_component_utils(boundary_test)

    function new(string name = "boundary_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_dir_seq d = dir_seq("d");
        bit [3:0] u = env_o.cc_o.sid_prim;
        bit [3:0] w = env_o.cc_o.sid_sec;
        bit [7:0] v[];
        super.run_phase(phase);
        phase.raise_objection(this);
        bytes(16, v); void'(d.addw(ODVE_SPMI_EXT_WR,  u, 16'h0000, v));
        void'(d.add(ODVE_SPMI_EXT_RD,  u, 16'h0000, 16));
        bytes(1, v);  void'(d.addw(ODVE_SPMI_EXT_WR,  u, 16'h003F, v));
        void'(d.add(ODVE_SPMI_EXT_RD,  u, 16'h003F, 1));
        bytes(16, v); void'(d.addw(ODVE_SPMI_EXT_WR,  w, 16'h0038, v));   // 0x38..0x3F written, 0x40.. not (ACK)
        void'(d.add(ODVE_SPMI_EXT_RD,  w, 16'h0038, 16));                    // 0x40 power state, 0x41..0x47 NRF
        bytes(16, v); void'(d.addw(ODVE_SPMI_EXT_WR,  u, 16'h00F8, v));   // wraps to 0x00..0x07
        void'(d.add(ODVE_SPMI_EXT_RD,  u, 16'h00FC, 16));
        bytes(8, v);  void'(d.addw(ODVE_SPMI_EXTL_WR, u, 16'h003C, v));    // 0x3C..0x3F written
        void'(d.add(ODVE_SPMI_EXTL_RD, u, 16'h003A, 8));
        bytes(8, v);  void'(d.addw(ODVE_SPMI_EXTL_WR, w, 16'hFFFC, v));    // wraps to 0x0000..0x0003
        void'(d.add(ODVE_SPMI_EXTL_RD, w, 16'hFFFE, 8));
        bytes(1, v);  void'(d.addw(ODVE_SPMI_EXTL_WR, w, 16'h0100, v));    // unimplemented
        void'(d.add(ODVE_SPMI_EXTL_RD, w, 16'h0100, 1));
        bytes(1, v);  void'(d.addw(ODVE_SPMI_REG_WR,  u, 16'h001F, v));
        void'(d.add(ODVE_SPMI_REG_RD,  u, 16'h001F, 1));
        v = new[1]; v[0] = 8'h7F; void'(d.addw(ODVE_SPMI_REG0_WR, u, 16'h0000, v));
        void'(d.add(ODVE_SPMI_REG_RD,  u, 16'h0000, 1));
        v = new[1]; v[0] = 8'h00; void'(d.addw(ODVE_SPMI_REG0_WR, w, 16'h0000, v));
        void'(d.add(ODVE_SPMI_EXT_RD,  w, 16'h0000, 4));
        run_seq(d);
        phase.drop_objection(this);
    endtask : run_phase
endclass : boundary_test
