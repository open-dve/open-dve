// Simulation-side feed of odve_cov_emu: mirrors every odve_cov_store::hit()
// onto the block's sample port, one per clock, so the emulation backend can
// be verified against the package store in an ordinary UVM run (the apb
// testbench does, +apb_slave=cov). Not part of an emulation build - there
// the sample port is driven by synthesizable monitors.
`ifdef ODVE_FCOV
module odve_cov_emu_feed (
    input  logic        clk,
    input  logic        rst_n,
    output logic        smp_valid,
    output logic [31:0] smp_idx
);
    initial begin
        smp_valid = 1'b0;
        smp_idx   = '0;
        odve_cov_pkg::odve_cov_store::emu = 1;       // from now on hit() also queues the index
    end

    // Monitors sample at negedge (the apb one does), this pops at posedge:
    // no same-timestep race between the push and the pop.
    always @(posedge clk) begin
        if (rst_n && odve_cov_pkg::odve_cov_store::smp_q.size() > 0) begin
            smp_idx   <= odve_cov_pkg::odve_cov_store::smp_q.pop_front();
            smp_valid <= 1'b1;
        end else begin
            smp_valid <= 1'b0;
        end
    end
endmodule
`endif
