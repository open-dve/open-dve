// SMBus side-band signal: SMBALERT#, open drain with pull-up (SMBus 3.3
// A.2). SMBCLK/SMBDAT are the I2C bus of odve_i2c_if (i2c agent), which the
// smbus agent uses as its transport. Drivers as in odve_i2c_if: s_* the
// slave agent, d_* the DUT (assigned in top), x_* a spare.
interface odve_smbus_if (
    input logic clk,
    input logic rst_n
);
    logic s_alert_o = 1'b1, s_alert_oe = 1'b0;
    logic x_alert_o = 1'b1, x_alert_oe = 1'b0;
    logic d_alert_o, d_alert_oe;

    logic alert_n;
    assign alert_n = ~((s_alert_oe & ~s_alert_o) | (d_alert_oe === 1'b1 & d_alert_o === 1'b0) | (x_alert_oe & ~x_alert_o));
endinterface
