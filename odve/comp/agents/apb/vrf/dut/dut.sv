// APB3 slave used to exercise the agent: NREG 32-bit registers at word
// addresses 0..NREG-1 (byte address = index * 4). Every third transfer takes
// one wait state (pready low for a cycle); an address beyond the register
// file completes with pslverr and is not written.
module dut #(parameter int NREG = 16) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic        pready,
    output logic [31:0] prdata,
    output logic        pslverr
);
    logic [31:0] regs [NREG];
    int unsigned cnt;

    wire [31:0] idx      = paddr >> 2;
    wire        in_range = idx < NREG;
    wire        access   = psel & penable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pready <= 1'b0;
            cnt    <= 0;
            for (int i = 0; i < NREG; i++) regs[i] <= '0;
        end else begin
            if (psel && !penable) begin                 // SETUP: decide the wait state
                cnt    <= cnt + 1;
                pready <= (cnt % 3 != 2);
            end else if (access) begin                  // ACCESS
                if (!pready) pready <= 1'b1;
                else begin
                    if (pwrite && in_range) regs[idx[3:0]] <= pwdata;
                    pready <= 1'b0;
                end
            end else begin
                pready <= 1'b0;
            end
        end
    end

    assign prdata  = (access && in_range) ? regs[idx[3:0]] : '0;
    assign pslverr = access && pready && !in_range;

    initial $display("Hi from DUT: APB slave, %0d registers", NREG);
endmodule
