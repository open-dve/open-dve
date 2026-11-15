// I2C target with a 16-byte register file - the RTL side of the i2c agent's
// testbench. Synthesizable; built on odve_i2c_tgt_phy.
//
//   * 7-bit address ADDR7 and 10-bit address ADDR10 (UM10204 3.1.11: header
//     1111 0XX + low byte; after Sr the header with R reaches the target
//     addressed by the preceding write header), both on the same registers
//   * EEPROM-style access: the first byte written after the address is the
//     register pointer - NACKed if >= 16 (UM10204 3.1.6, NACK condition 3) -,
//     further bytes are written from it; reads read from it; the pointer
//     increments after every byte (wrapping 15 -> 0) and is kept between
//     transfers (current-address read)
//   * general call (address 0, write): acknowledged; second byte 06h is the
//     software reset (UM10204 3.1.14: registers and pointer to 0), any other
//     second byte is NACKed
//   * register 15 is CTRL: bits [5:0] = SCL stretch after every acknowledge
//     of a continuing transfer, in clk cycles (0 = no stretching)
module dut #(
    parameter logic [6:0] ADDR7  = 7'h50,
    parameter logic [9:0] ADDR10 = 10'h2A5
) (
    input  logic clk,
    input  logic rst_n,
    input  logic scl_i,
    input  logic sda_i,
    output logic scl_o,
    output logic scl_oe,
    output logic sda_o,
    output logic sda_oe
);
    logic       start_p, restart, stop_p, abort_p, tmo_p, rx_p, rx_first, tx_p, mack_p, mack;
    logic [7:0] rx_data, tx_data;
    logic       rx_ack, rx_tx;

    logic [7:0] regs [16];
    logic [3:0] ptr;
    logic [7:0] idx;
    logic       gc, a10_wait, matched10, addressed;

    assign scl_o = 1'b0;
    assign sda_o = 1'b0;

    odve_i2c_tgt_phy #(.TMO_CYC(0)) phy (
        .clk, .rst_n, .scl_i, .sda_i, .scl_oe, .sda_oe,
        .start_p, .restart, .stop_p, .abort_p, .tmo_p,
        .rx_p, .rx_data, .rx_first, .rx_ack, .rx_tx,
        .tx_p, .tx_data, .mack_p, .mack,
        .stretch_cyc({2'b00, regs[15][5:0]})
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) regs[i] <= 8'h00;
            ptr <= 4'h0; idx <= 8'h00;
            gc <= 1'b0; a10_wait <= 1'b0; matched10 <= 1'b0; addressed <= 1'b0;
            rx_ack <= 1'b0; rx_tx <= 1'b0; tx_data <= 8'hFF;
        end else begin
            if (start_p) begin
                gc <= 1'b0; a10_wait <= 1'b0; addressed <= 1'b0;
                if (!restart) matched10 <= 1'b0;
            end
            if (stop_p || tmo_p) begin
                matched10 <= 1'b0; addressed <= 1'b0;
            end
            if (rx_p) begin
                rx_ack <= 1'b0;
                rx_tx  <= 1'b0;
                if (rx_first) begin
                    idx <= 8'h00;
                    addressed <= 1'b0;
                    gc <= 1'b0;
                    if (rx_data[7:3] == 5'b11110) begin
                        if (rx_data[2:1] == ADDR10[9:8]) begin
                            if (!rx_data[0]) begin
                                rx_ack <= 1'b1;            // A1: the low byte decides
                                a10_wait <= 1'b1;
                            end else if (matched10) begin
                                rx_ack <= 1'b1;            // A3: addressed as transmitter
                                rx_tx  <= 1'b1;
                                addressed <= 1'b1;
                            end
                        end
                    end else if (rx_data == 8'h00) begin
                        rx_ack <= 1'b1;
                        gc <= 1'b1;
                        addressed <= 1'b1;
                    end else if (rx_data[7:1] == ADDR7) begin
                        rx_ack <= 1'b1;
                        rx_tx  <= rx_data[0];
                        addressed <= 1'b1;
                    end
                end else if (a10_wait) begin
                    a10_wait <= 1'b0;
                    if (rx_data == ADDR10[7:0]) begin
                        rx_ack <= 1'b1;
                        matched10 <= 1'b1;
                        addressed <= 1'b1;
                    end
                end else if (addressed && gc) begin
                    if (idx == 8'h00 && rx_data == 8'h06) begin
                        rx_ack <= 1'b1;
                        for (int i = 0; i < 16; i++) regs[i] <= 8'h00;
                        ptr <= 4'h0;
                    end
                    idx <= idx + 8'h01;
                end else if (addressed) begin
                    if (idx == 8'h00) begin
                        if (rx_data < 8'd16) begin
                            rx_ack <= 1'b1;
                            ptr <= rx_data[3:0];
                        end
                    end else begin
                        rx_ack <= 1'b1;
                        regs[ptr] <= rx_data;
                        ptr <= ptr + 4'h1;
                    end
                    if (idx != 8'hFF) idx <= idx + 8'h01;
                end
            end
            if (tx_p) begin
                tx_data <= regs[ptr];
                ptr <= ptr + 4'h1;
            end
        end
    end
endmodule
