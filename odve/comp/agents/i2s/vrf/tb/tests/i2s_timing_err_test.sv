// Negative test of the monitor's timing check: the receiver agent controls
// port B with SCK at T = 80 ns (+i2s_sck_half=40 unless given), and the DUT
// transmitter, a clock target that oversamples SCK with a 10 ns clock,
// changes SD about 3 clk after the falling edge - closer than 0.2T to the
// next rising edge. The port B monitor must report I2S_TIMING (expected
// here, demoted to info and counted); the data is still sampled correctly,
// so the scoreboard checks as usual.
class i2s_timing_err_test extends base_test;
    `uvm_component_utils(i2s_timing_err_test)

    i2s_err_catcher catcher;

    function new(string name = "i2s_timing_err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void configure();
        tc.b_clk       = "rx";
        tc.sck_half_ns = 40;
        tc.frames      = 8;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!tc.has_dut()) `uvm_fatal(get_name(), "needs the DUT (+i2s_slave=dut)")
        catcher = new("catcher");
        catcher.ids = '{"I2S_TIMING"};
        uvm_report_cb::add(null, catcher);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (catcher.n == 0)
            `uvm_error(get_name(), "SD set-up violation on port B not reported by the monitor")
        else
            `uvm_info(get_name(), $sformatf("set-up violation reported %0d time(s) by the monitor", catcher.n), UVM_LOW)
    endfunction
endclass
