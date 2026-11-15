// STOP inside a byte (an aborted transfer): illegal per UM10204 3.1.3/3.1.5,
// so the monitor must flag every one (I2C_BUS_ERR, demoted to info here and
// counted), and the target must drop the partial byte and answer the next
// transfer normally. Aborts after 1..7 bits of a data byte and inside an
// address byte. REQ-I2C-013, 014.
class i2c_abort_test extends base_test;
    `uvm_component_utils(i2c_abort_test)

    int unsigned n_inj = 0;

    function new(string name = "i2c_abort_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.agt.mon.set_report_severity_id_override(UVM_ERROR, "I2C_BUS_ERR", UVM_INFO);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_i2c_item it;
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 8);
        wr_regs(0, d);
        for (int b = 1; b <= 7; b++) begin
            it = mk(I2C_WRITE, 10'(TGT_ADDR7), rng.chance(50));
            if (it.addr10) it.addr = TGT_ADDR10;
            it.wdata = '{8'(b), 8'(rng.u16()), 8'(rng.u16()), 8'(rng.u16())};
            it.abort_byte = it.addr10 ? 4 : 3;      // the third written byte (wdata[2])
            it.abort_bit  = b;
            xfer(it);
            n_inj++;
            rd_regs(0, 8);
        end
        it = mk(I2C_WRITE, 10'(TGT_ADDR7));
        it.wdata = '{8'h00, 8'h77};
        it.abort_byte = 0;                           // inside the address byte
        it.abort_bit  = 5;
        xfer(it);
        n_inj++;
        rd_regs(0, 8);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        // an abort inside the address byte leaves no transfer to report
        if (env_o.agt.mon.n_bus_err != n_inj)
            `uvm_error(get_name(), $sformatf("%0d aborts injected, monitor flagged %0d", n_inj, env_o.agt.mon.n_bus_err))
        if (env_o.agt.mon.n_aborted != n_inj - 1)
            `uvm_error(get_name(), $sformatf("%0d aborted transfers reported, expected %0d", env_o.agt.mon.n_aborted, n_inj - 1))
        if (env_o.agt.drv.n_items != env_o.agt.mon.n_seen + 1)
            `uvm_error(get_name(), $sformatf("master ran %0d transfers, monitor reported %0d (+1 aborted in its address)", env_o.agt.drv.n_items, env_o.agt.mon.n_seen))
    endfunction
endclass : i2c_abort_test
