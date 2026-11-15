// Passive observer of both lines of the link: one thread per direction
// rebuilds every character from the pins (odve_uart_phy::recv, nominal bit
// period cfg.bit_clks, 16x-style mid-bit sampling) and publishes it on
// item_collected_port with its direction, format, error flags and the idle
// gap before it. Protocol checks (uvm_error):
//   - parity error, framing error or break on rxd (the peer never sends one),
//     and on txd unless cfg.allow_tx_err (the test injects them there);
//   - a stop bit shorter than cfg.stop (the 2nd stop bit, or the second half
//     of 1.5, sampled as space) on either line;
//   - a false start bit (space shorter than half a bit) on rxd.
// False start bits on txd are counted (n_glitch) and dropped like a 16550 does.
class odve_uart_mon extends uvm_monitor;
    `uvm_component_utils(odve_uart_mon)

    uvm_analysis_port #(odve_uart_item) item_collected_port;
    virtual odve_uart_if vif;
    odve_uart_cfg        cfg;

    int unsigned n_seen[2]   = '{0, 0};   // per direction (TX, RX)
    int unsigned n_glitch[2] = '{0, 0};
    time         clk_per     = 0;

    // Functional coverage: the covergroup is declared in odve_uart_agent_pkg
    // (package scope, `ifdef ODVE_COV_NATIVE); with FCOV=1 the build generates
    // odve_cov_pkg::odve_cov_odve_uart_cg from it and these two macros are
    // the whole hook. Without FCOV=1 both expand to nothing.
    `odve_cov_create(odve_uart_cg)

    function new(string name = "odve_uart_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        time t0;
        wait (vif.rst_n === 1'b1);
        fork
            begin
                @(posedge vif.clk);
                t0 = $time;
                @(posedge vif.clk);
                clk_per = $time - t0;     // for gap / break lengths in bit times
            end
            watch(ODVE_UART_TX);
            watch(ODVE_UART_RX);
        join
    endtask

    function int err_code(odve_uart_item tr);
        if (tr.brk) return 4;
        return (tr.pe ? 1 : 0) + (tr.fe ? 2 : 0);
    endfunction

    task watch(odve_uart_dir_e dir);
        odve_uart_item tr;
        time           t_start, prev_end = 0;
        bit            have_prev = 0;
        int unsigned   bc, clks, dcls;
        int            d = (dir == ODVE_UART_TX) ? 0 : 1;
        string         line_name = (dir == ODVE_UART_TX) ? "txd" : "rxd";
        forever begin
            odve_uart_phy::recv(vif, dir, cfg, tr, t_start);
            bc = cfg.bit_clks;
            if (tr.kind == ODVE_UART_GLITCH) begin
                n_glitch[d]++;
                if (dir == ODVE_UART_RX)
                    `uvm_error(get_name(), $sformatf("%s: false start bit (space shorter than half a bit) at %0t", line_name, t_start))
                else
                    `uvm_info(get_name(), $sformatf("%s: false start bit at %0t ignored", line_name, t_start), UVM_MEDIUM)
                continue;
            end
            tr.gap_bits = have_prev ? ((t_start > prev_end) ? int'((t_start - prev_end) / (bc * clk_per)) : 0) : 99;
            if (tr.brk) begin
                odve_uart_phy::wait_mark(vif, dir, clks);
                tr.brk_bits = int'(($time - t_start) / (bc * clk_per));
                prev_end    = $time;
            end else begin
                if (!tr.fe && tr.stop != ODVE_UART_STOP1) begin
                    // first stop bit sampled at its middle: the second half
                    // of 1.5 stop bits / the middle of the second is ahead
                    repeat ((tr.stop == ODVE_UART_STOP2) ? bc : bc / 2) @(posedge vif.clk);
                    if (odve_uart_phy::line(vif, dir) !== 1'b1)
                        `uvm_error(get_name(), $sformatf("%s: stop bit shorter than %s: %s", line_name, tr.fmt2string(), tr.convert2string()))
                end
                prev_end = tr.t_end + (cfg.stop_clks(bc) - bc / 2) * clk_per;
            end
            have_prev = 1;
            n_seen[d]++;
            if ((tr.pe || tr.fe || tr.brk) && !(dir == ODVE_UART_TX && cfg.allow_tx_err))
                `uvm_error(get_name(), $sformatf("%s: protocol error: %s", line_name, tr.convert2string()))
            `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
            dcls = (tr.data == 0) ? 0 : (tr.data == odve_uart_mask(tr.data_bits)) ? 1 : 2;
            `odve_cov_sample(odve_uart_cg, d, int'(tr.data_bits), int'(tr.parity), int'(tr.stop), err_code(tr), int'(dcls), int'(tr.gap_bits))
            item_collected_port.write(tr);
        end
    endtask
endclass
