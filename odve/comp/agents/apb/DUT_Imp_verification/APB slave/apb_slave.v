module apb_slave #(
    parameter DATA_WIDTH        = 32,
    parameter ADDRESS_WIDTH     = 32,
    parameter MEM_DEPTH        = 256,
    parameter STRB_WIDTH       = DATA_WIDTH/8,
    parameter SLAVE_START_ADDR = 32'h0000_0000,
    parameter SLAVE_END_ADDR   = 32'h0000_FFFF
)(
    // Clock and Reset
    input  wire                      PCLK,
    input  wire                      PRESETn,

    // APB Slave Interface
    input  wire                      PSEL,
    input  wire                      PENABLE,
    input  wire [ADDRESS_WIDTH-1:0]  PADDR,
    input  wire                      PWRITE,
    input  wire [DATA_WIDTH-1:0]     PWDATA,
    input  wire [STRB_WIDTH-1:0]     PSTRB,
    input  wire [2:0]                PPROT,

    // APB Slave Outputs
    output reg                       PREADY,
    output reg                       PSLVERR,
    output reg  [DATA_WIDTH-1:0]     PRDATA
);

    // Memory array
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // State definitions
    localparam [1:0] 
        IDLE    = 2'b00,
        SETUP   = 2'b01,
        ACCESS  = 2'b10;

    // State registers
    reg [1:0] current_state, next_state;

    // Internal registers for address phase sampling
    reg [ADDRESS_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0]    wdata_reg;
    reg [STRB_WIDTH-1:0]    strb_reg;
    reg                     write_reg;
    reg [DATA_WIDTH-1:0]    read_data_reg;

    // Internal signals and address decoding
    wire [ADDRESS_WIDTH-1:0] local_addr;
    wire addr_in_range, addr_aligned;
    wire setup_phase, access_phase;
    wire write_error, alignment_error, error_condition;
    
    // Address decoding and control signals
    assign local_addr     = PADDR - SLAVE_START_ADDR;
    assign addr_in_range  = (PADDR >= SLAVE_START_ADDR) && (PADDR <= SLAVE_END_ADDR);
    assign addr_aligned   = (local_addr < MEM_DEPTH);
    assign setup_phase    = PSEL && !PENABLE;
    assign access_phase   = PSEL && PENABLE;
    
    // Combinatorial error detection
    assign write_error     = PSEL && PWRITE && (PSTRB == 4'b0000);
    assign alignment_error = PSEL && ((PSTRB == 4'b1111 && local_addr[1:0] != 2'b00) ||
                                    (PSTRB == 4'b0011 && local_addr[0] != 1'b0));
    assign error_condition = write_error || alignment_error || 
                           (PSEL && (!addr_in_range || !addr_aligned));

    // Sequential logic for state and register updates
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state <= IDLE;
            addr_reg     <= {ADDRESS_WIDTH{1'b0}};
            wdata_reg    <= {DATA_WIDTH{1'b0}};
            strb_reg     <= {STRB_WIDTH{1'b0}};
            write_reg    <= 1'b0;
            read_data_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            current_state <= next_state;
            
            // Sample control signals during setup phase
            if (setup_phase && !error_condition) begin
                addr_reg  <= local_addr;
                wdata_reg <= PWDATA;
                strb_reg  <= PSTRB;
                write_reg <= PWRITE;
                
                // Pre-fetch read data if it's a read operation
                if (!PWRITE && addr_in_range && addr_aligned) begin
                    read_data_reg <= memory[local_addr];
                end
            end
        end
    end

    // Memory write process
    always @(posedge PCLK) begin
        if (access_phase && write_reg && !error_condition) begin
            if (strb_reg[0]) memory[addr_reg][7:0]   <= wdata_reg[7:0];
            if (strb_reg[1]) memory[addr_reg][15:8]  <= wdata_reg[15:8];
            if (strb_reg[2]) memory[addr_reg][23:16] <= wdata_reg[23:16];
            if (strb_reg[3]) memory[addr_reg][31:24] <= wdata_reg[31:24];
        end
    end

    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (PSEL)
                    next_state = SETUP;
                else
                    next_state = IDLE;
            end

            SETUP: begin
                if (!PSEL)
                    next_state = IDLE;
                else if (PENABLE)
                    next_state = ACCESS;
                else
                    next_state = SETUP;
            end

            ACCESS: begin
                if (!PSEL)
                    next_state = IDLE;
                else if (!PENABLE)
                    next_state = SETUP;
                else
                    next_state = ACCESS;
            end

            default: next_state = IDLE;
        endcase
    end

    // Output logic - Combinatorial error detection and response
    always @(*) begin
        // Default values
        PREADY = 1'b0;
        PSLVERR = 1'b0;
        PRDATA = read_data_reg;

        case (current_state)
            IDLE: begin
                PREADY = 1'b1;
            end

            SETUP: begin
                PREADY = 1'b0;
                if (error_condition) begin
                    PSLVERR = 1'b1;
                    PRDATA = {DATA_WIDTH{1'b0}};
                end
            end

            ACCESS: begin
                PREADY = 1'b1;
                if (error_condition) begin
                    PSLVERR = 1'b1;
                    PRDATA = {DATA_WIDTH{1'b0}};
                end
            end

            default: begin
                PREADY = 1'b1;
                PSLVERR = 1'b0;
                PRDATA = {DATA_WIDTH{1'b0}};
            end
        endcase
    end

    // Optional: Memory Initialization
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = {DATA_WIDTH{1'b0}};
        end
    end

endmodule