// Reference model of the target (the DUT's behaviour, written independently
// of the agent's odve_i2c_mem_model): 16 registers, a register pointer set by
// the first written byte (NACK when >= 16) that increments after every byte
// and wraps, general call 06h = software reset, other general-call bytes
// NACKed, every other address NACKed. Every transfer the monitor reports is
// checked: address acknowledge, the acknowledge of every written byte, every
// byte read.
`uvm_analysis_imp_decl(_i2c)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_i2c #(odve_i2c_item, scb) i2c_imp;

    bit [7:0]    model [16];
    int unsigned ptr = 0;
    int unsigned n_xfer = 0, n_wr = 0, n_rd = 0, n_nack = 0, n_gc = 0, n_err = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        i2c_imp = new("i2c_imp", this);
        foreach (model[i]) model[i] = 8'h00;
    endfunction

    function void err(odve_i2c_item tr, string msg);
        n_err++;
        `uvm_error(get_name(), $sformatf("%s: %s", tr.convert2string(), msg))
    endfunction

    function void write_i2c(odve_i2c_item tr);
        bit hit, gc, exp_ack;
        n_xfer++;
        hit = tr.addr10 ? (tr.addr == TGT_ADDR10) : (tr.addr == 10'(TGT_ADDR7));
        gc  = tr.is_gc;
        if (tr.addr_ack != (hit || gc)) err(tr, $sformatf("address %s, expected %s", tr.addr_ack ? "ACKed" : "NACKed", (hit || gc) ? "ACK" : "NACK"));
        if (!tr.addr_ack) begin
            n_nack++;
            return;
        end
        if (gc) begin
            n_gc++;
            foreach (tr.wack[i]) begin
                exp_ack = (i == 0 && tr.wdata[i] == 8'h06);
                if (tr.wack[i] != exp_ack) err(tr, $sformatf("general call byte %0d %s, expected %s", i, tr.wack[i] ? "ACKed" : "NACKed", exp_ack ? "ACK" : "NACK"));
                if (exp_ack) begin
                    foreach (model[r]) model[r] = 8'h00;
                    ptr = 0;
                end
            end
            return;
        end
        foreach (tr.wack[i]) begin
            if (i == 0) begin
                exp_ack = tr.wdata[0] < 16;
                if (exp_ack) ptr = tr.wdata[0];
            end else begin
                exp_ack = 1;
                model[ptr] = tr.wdata[i];
                ptr = (ptr + 1) % 16;
                n_wr++;
            end
            if (tr.wack[i] != exp_ack) err(tr, $sformatf("written byte %0d (0x%02h) %s, expected %s", i, tr.wdata[i], tr.wack[i] ? "ACKed" : "NACKed", exp_ack ? "ACK" : "NACK"));
            if (!tr.wack[i]) n_nack++;
        end
        foreach (tr.rdata[i]) begin
            if (tr.rdata[i] !== model[ptr]) err(tr, $sformatf("read byte %0d = 0x%02h, register %0d holds 0x%02h", i, tr.rdata[i], ptr, model[ptr]));
            ptr = (ptr + 1) % 16;
            n_rd++;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d transfers checked: %0d register writes, %0d reads, %0d NACKs, %0d general calls, %0d errors", n_xfer, n_wr, n_rd, n_nack, n_gc, n_err), UVM_LOW)
        if (n_xfer == 0) `uvm_error(get_name(), "no I2C transfers observed")
    endfunction
endclass : scb
