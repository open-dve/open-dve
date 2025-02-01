module apb4_master #(
  parameter DATA_WIDTH    = 32,
  parameter ADDRESS_WIDTH = 32,
  parameter CTR_WIDTH     = 7,
  parameter CTR_Cycles    = 100, 
  parameter STRB_WIDTH    = DATA_WIDTH/8,
  parameter ADDR_START_1  = 32'h0000_0000,  // 0    to 255
  parameter ADDR_END_1    = 32'h0000_00_FF, 
  parameter ADDR_START_2  = 32'h0000_01_00, // 256 to 511
  parameter ADDR_END_2    = 32'h0000_01_FF
)(
  // Clock and Reset
  input  wire                         PCLK,
  input  wire                         PRESETn,

  // Bridge Interface Inputs
  input  wire [ADDRESS_WIDTH-1:0]     apb_write_paddr,
  input  wire [ADDRESS_WIDTH-1:0]     apb_read_paddr,
  input  wire [DATA_WIDTH-1:0]        apb_write_data,
  input  wire                         READ_WRITE,
  input  wire                         transfer,
  // input  wire [2:0]                   IN_PROT,        // bit 0: Privlage/Normal bit 1: Secure/Non-Secure bit 2: RW - data / R - instruction
  input  wire [STRB_WIDTH-1:0]        IN_STRB,

  // APB Slave Interface
  input  wire [DATA_WIDTH-1:0]        PRDATA,
  input  wire                         PREADY,
  input  wire                         PSLVERR,

  // Bridge Interface Outputs
  output reg  [DATA_WIDTH-1:0]        apb_read_data_out,
  output reg                          transfer_error,
  output reg  [3:0]                   error_status,

  // APB Master Outputs TO SLAVE
  output reg                          PSEL1,
  output reg                          PSEL2,
  output reg                          PENABLE,
  output reg  [ADDRESS_WIDTH-1:0]     PADDR,
  output reg                          PWRITE,
  output reg  [DATA_WIDTH-1:0]        PWDATA,
  output reg  [STRB_WIDTH-1:0]        PSTRB
  // output reg  [2:0]                   PPROT
);

  // State definitions
  localparam [1:0] 
  IDLE    = 2'b00,
  SETUP   = 2'b01,
  ACCESS  = 2'b10,
  ERROR   = 2'b11;

  // Error status codes
  localparam [3:0]
  NO_ERROR          = 4'b0000,
  PSLV_ERROR        = 4'b0001,
  STRB_ERROR        = 4'b0010,
  TIMEOUT_ERROR     = 4'b0100,
  INVALID_ADDR      = 4'b0101;

  // State registers
  reg [1:0] current_state, next_state;
  reg [CTR_WIDTH-1:0] timeout_counter; // 10–100 cycles

  // Internal signals - CORRECTED ADDRESS CHECKING
  wire [ADDRESS_WIDTH-1:0] current_addr = READ_WRITE ? apb_read_paddr : apb_write_paddr;

  wire addr_in_slave1 = (current_addr >= ADDR_START_1) && (current_addr <= ADDR_END_1);
  wire addr_in_slave2 = (current_addr >= ADDR_START_2) && (current_addr <= ADDR_END_2);
  wire addr_in_range  = addr_in_slave1 || addr_in_slave2;

  wire strb_error     = !READ_WRITE && (IN_STRB == 4'b0000);
  wire setup_error    = !addr_in_range || strb_error;

  // Part 1: Sequential Block - State and Register Updates
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      current_state     <= IDLE;
      timeout_counter   <= 4'h0;
      transfer_error    <= 1'b0;
      error_status      <= NO_ERROR;
    end 
    else begin
      current_state <= next_state;

      // Timeout counter logic
      if (current_state == ACCESS && !PREADY)
        timeout_counter <= timeout_counter + 1'b1;
      else
        timeout_counter <= 4'h0;

      // State-based register updates
      case (current_state)

        IDLE: begin
          transfer_error <= 1'b0;
          error_status <= NO_ERROR;
        end

        ACCESS: begin
          if (PSLVERR) begin
            transfer_error <= 1'b1;
            error_status   <= PSLV_ERROR;
          end
          else if (timeout_counter == CTR_Cycles) begin
            transfer_error <= 1'b1;
            error_status   <= TIMEOUT_ERROR;
          end
          else if (PREADY && READ_WRITE && !PSLVERR) begin
            transfer_error    <= 1'b0;
            error_status      <= NO_ERROR;
          end
        end

        ERROR: begin
          transfer_error <= 1'b1;
          if (!addr_in_range)
            error_status <= INVALID_ADDR;
          else if (strb_error)
            error_status <= STRB_ERROR;
        end
      endcase
    end
  end

  // Part 2: Next State Logic
  always @(*) begin
    case (current_state)
      IDLE: begin
        if (transfer)
          next_state = SETUP;
        else
          next_state = IDLE;
      end

      SETUP: begin
        next_state = setup_error ? ERROR : ACCESS;
      end

      ACCESS: begin
        if (PSLVERR || timeout_counter == CTR_Cycles)
          next_state = ERROR;
        else if (PREADY)
          next_state = transfer ? SETUP : IDLE;
        else
          next_state = ACCESS;
      end

      ERROR: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  // Part 3: Output Logic
  always @(*) begin
    // Default values
    PSEL1   = 1'b0;
    PSEL2   = 1'b0;
    PENABLE = 1'b0;
    PWRITE  = !READ_WRITE;
    apb_read_data_out = 0;
    case (current_state)
      IDLE: begin
        // Default values are good for IDLE
        PWDATA  = 0;
        PADDR   = 32'hFFFF_FFFF; // out of range
        PSTRB   = {STRB_WIDTH{1'b0}}; // For read transfers, the Requester must drive all bits of PSTRB LOW.
      end

      SETUP: begin
        if (!setup_error) begin
          PSEL1   = (addr_in_slave1 );
          PSEL2   = (addr_in_slave2 );
          PADDR   = current_addr;
          PWRITE  = !READ_WRITE;
          PWDATA  = apb_write_data;
          PSTRB   = PWRITE? IN_STRB :{STRB_WIDTH{1'b0}};  // For read transfers, the Requester must drive all bits of PSTRB LOW.
        end
      end

      ACCESS: begin
        if (!setup_error) begin
          PSEL1 = (addr_in_slave1 );
          PSEL2 = (addr_in_slave2 );
          PENABLE = 1'b1;
          apb_read_data_out = PRDATA;
        end
      end

      ERROR: begin
        // Clear all control signals in error state
        PSEL1 = 1'b0;
        PSEL2 = 1'b0;
        PENABLE = 1'b0;
        PSTRB = {STRB_WIDTH{1'b0}};
      end
    endcase
  end

endmodule