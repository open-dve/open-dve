// SPMI master: owns SCLK and drives every master frame. Cycle based on the
// TB clock: one SCLK half period is cfg.sclk_half clocks, every pin changes
// with a non-blocking assignment at a posedge. Bus arbitration is not
// modelled: this is the only master and owns the bus (doc/spec.md).
//
//   bit:  SCLK rises and the master puts the bit on SDATA in the same clock;
//         receivers sample on the falling edge.
//   SSC:  SDATA high for one SCLK period, then low for one, SCLK held low.
//   BPC:  the bus park cycle: the current driver drives 0 while SCLK is high
//         and releases SDATA at the falling edge.
//   read: after the command/address frames the master parks the bus (BPC),
//         the slave drives the data frames, the slave parks the bus.
//   others (writes, Register 0 Write, Reset/Sleep/Shutdown/Wakeup): after
//         the last master frame the master parks the bus, clocks the
//         ACK/NACK cycle (the slave drives 1 = ACK; nobody driving leaves
//         the parked 0 = NACK) and the slave's bus park cycle.
// Read data, the NRF mask and the ACK bit are written back into the item.
class odve_spmi_mst_drv_base extends uvm_driver #(odve_spmi_item);
    `uvm_component_utils(odve_spmi_mst_drv_base)

    virtual odve_spmi_if vif;
    odve_spmi_cfg        cfg;

    function new(string name = "odve_spmi_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task hwait(int unsigned n);
        repeat (n * cfg.sclk_half) @(posedge vif.clk);
    endtask

    task tx_bit(bit b);
        vif.sclk       <= 1'b1;
        vif.m_sdata_oe <= 1'b1;
        vif.m_sdata_o  <= b;
        hwait(1);
        vif.sclk       <= 1'b0;
        hwait(1);
    endtask

    // 8 bits MSB first + odd parity (inverted when flip is set)
    task tx_frame(bit [7:0] v, bit flip);
        for (int i = 7; i >= 0; i--) tx_bit(v[i]);
        tx_bit(~^v ^ flip);
    endtask

    task tx_cmd(bit [3:0] sa, bit [7:0] c, bit flip);
        bit [11:0] v = {sa, c};
        for (int i = 11; i >= 0; i--) tx_bit(v[i]);
        tx_bit(~^v ^ flip);
    endtask

    task ssc();
        vif.m_sdata_oe <= 1'b1;
        vif.m_sdata_o  <= 1'b1;
        hwait(2);
        vif.m_sdata_o  <= 1'b0;
        hwait(2);
    endtask

    // the master's bus park cycle
    task bpc();
        vif.sclk       <= 1'b1;
        vif.m_sdata_oe <= 1'b1;
        vif.m_sdata_o  <= 1'b0;
        hwait(1);
        vif.sclk       <= 1'b0;
        vif.m_sdata_oe <= 1'b0;
        hwait(1);
    endtask

    // one SCLK period with the slave driving; returns the bit sampled at the falling edge
    task rx_bit(output bit b);
        vif.sclk <= 1'b1;
        hwait(1);
        b = vif.sdata;
        vif.sclk <= 1'b0;
        hwait(1);
    endtask

    task rx_frame(output bit [8:0] v);
        for (int i = 8; i >= 0; i--) rx_bit(v[i]);
    endtask

    task drive(odve_spmi_item it);
        int unsigned f = 0;   // frame number, for the parity injection
        bit [7:0] a[2];
        bit       b;
        a[0] = it.addr[15:8];
        a[1] = it.addr[7:0];
        ssc();
        tx_cmd(it.sid, it.cmd_byte(), it.inj_par_frame == 0);
        f++;
        for (int i = 2 - it.naddr(); i < 2; i++) begin
            tx_frame(a[i], it.inj_par_frame == int'(f));
            f++;
        end
        if (!it.is_read()) begin
            if (it.has_wdata())
                for (int i = 0; i < int'(it.nbytes); i++) begin
                    tx_frame(it.data[i], it.inj_par_frame == int'(f));
                    f++;
                end
            bpc();
            rx_bit(b);                // ACK/NACK, driven by the slave
            it.ack = b;
        end else begin
            bit [8:0] v;
            bpc();
            it.data     = new[it.nbytes];
            it.nrf_mask = '0;
            for (int i = 0; i < int'(it.nbytes); i++) begin
                rx_frame(v);
                it.data[i] = v[8:1];
                if (v == 9'h0) it.nrf_mask[i] = 1'b1;
            end
        end
        rx_bit(b);                    // the slave's bus park cycle
        hwait(cfg.idle_halfs);
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.sclk       <= 1'b0;
        vif.m_sdata_oe <= 1'b0;
        vif.m_sdata_o  <= 1'b0;
        wait (vif.rst_n === 1'b1);
        repeat (2) @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_name(), {"drive ", req.convert2string()}, UVM_HIGH)
            drive(req);
            seq_item_port.item_done();
        end
    endtask
endclass
