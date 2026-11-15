// RFFE master: owns SCLK and drives every master frame. Cycle based on the
// TB clock: one SCLK half period is cfg.sclk_half clocks, every pin changes
// with a non-blocking assignment at a posedge.
//
//   bit:  SCLK rises and the master puts the bit on SDATA in the same clock;
//         receivers sample on the falling edge.
//   SSC:  SDATA high for one SCLK period, then low for one, SCLK held low.
//   BPC:  the bus park cycle: the current driver drives 0 while SCLK is high
//         and releases SDATA at the falling edge.
//   read: after the command/address frames the master parks the bus (BPC),
//         the slave drives the data frames, the slave parks the bus. With
//         cfg.half_speed_read the read data frames run at half the SCLK
//         rate and are sampled on the following rising edge.
// Read data and the NRF mask are written back into the item.
class odve_rffe_mst_drv_base extends uvm_driver #(odve_rffe_item);
    `uvm_component_utils(odve_rffe_mst_drv_base)

    virtual odve_rffe_if vif;
    odve_rffe_cfg        cfg;

    function new(string name = "odve_rffe_mst_drv_base", uvm_component parent = null);
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

    // one SCLK period with the slave driving; returns the sampled bit
    task rx_bit(bit half_speed, output bit b);
        vif.sclk <= 1'b1;
        if (!half_speed) begin
            hwait(1);
            b = vif.sdata;            // falling edge
            vif.sclk <= 1'b0;
            hwait(1);
        end else begin
            hwait(2);
            vif.sclk <= 1'b0;
            hwait(2);
            b = vif.sdata;            // the next rising edge
        end
    endtask

    task rx_frame(bit half_speed, output bit [8:0] v);
        for (int i = 8; i >= 0; i--) rx_bit(half_speed, v[i]);
    endtask

    task drive(odve_rffe_item it);
        int unsigned f = 0;   // frame number, for the parity injection
        bit [7:0] a[2];
        a[0] = it.addr[15:8];
        a[1] = it.addr[7:0];
        ssc();
        tx_cmd(it.usid, it.cmd_byte(), it.inj_par_frame == 0);
        f++;
        for (int i = 2 - it.naddr(); i < 2; i++) begin
            tx_frame(a[i], it.inj_par_frame == int'(f));
            f++;
        end
        if (!it.is_read()) begin
            if (it.kind != ODVE_RFFE_REG0_WR)
                for (int i = 0; i < int'(it.nbytes); i++) begin
                    tx_frame(it.data[i], it.inj_par_frame == int'(f));
                    f++;
                end
            bpc();
        end else begin
            bit hs = cfg.half_speed_read;
            bit [8:0] v;
            bpc();
            it.data     = new[it.nbytes];
            it.nrf_mask = '0;
            for (int i = 0; i < int'(it.nbytes); i++) begin
                rx_frame(hs, v);
                it.data[i] = v[8:1];
                if (v == 9'h0) it.nrf_mask[i] = 1'b1;
            end
            vif.sclk <= 1'b1;         // the slave's bus park cycle
            hwait(1);
            vif.sclk <= 1'b0;
            hwait(1);
        end
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
