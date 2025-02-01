// APB4 Master Interface Assertions
module apb4_master_assertions #(
  parameter DATA_WIDTH = 32,
  parameter ADDRESS_WIDTH = 32,
  parameter CTR_WIDTH = 7,
  parameter CTR_Cycles = 100,
  parameter STRB_WIDTH = DATA_WIDTH/8,
  parameter ADDR_START_1 = 32'h0000_0000,
  parameter ADDR_END_1 = 32'h0000_00FF,
  parameter ADDR_START_2 = 32'h0000_0100,
  parameter ADDR_END_2 = 32'h0000_01FF
) (
  input wire PCLK,
  input wire PRESETn,
  input wire [1:0] current_state,
  input wire [1:0] next_state,
  input wire [ADDRESS_WIDTH-1:0] PADDR,
  input wire PWRITE,
  input wire PSEL1,
  input wire PSEL2,
  input wire PENABLE,
  input wire PREADY,
  input wire PSLVERR,
  input wire transfer,
  input wire READ_WRITE,
  input wire [STRB_WIDTH-1:0] PSTRB,
  input wire [CTR_WIDTH-1:0] timeout_counter,
  input wire transfer_error,
  input wire [3:0] error_status
);

  // State definitions
  localparam [1:0] 
    IDLE    = 2'b00,
    SETUP   = 2'b01,
    ACCESS  = 2'b10,
    ERROR   = 2'b11;

  // Error status codes
  localparam [3:0]
    NO_ERROR      = 4'b0000,
    PSLV_ERROR    = 4'b0001,
    STRB_ERROR    = 4'b0010,
    TIMEOUT_ERROR = 4'b0100,
    INVALID_ADDR  = 4'b0101;

  // Define default clocking with reset condition
  default clocking my_clk @(posedge PCLK);
  endclocking
  default disable iff (!PRESETn);

  // ============= Properties =============
  
  // Reset Properties
  property p_async_reset_behavior;
    @(negedge PRESETn) 
    1'b1 |=> @(posedge PCLK) (
      current_state == IDLE &&
      !transfer_error &&
      error_status == NO_ERROR &&
      !PSEL1 && !PSEL2 && !PENABLE
    );
  endproperty

  property p_post_reset_stability;
    $rose(PRESETn) |=> (
      current_state == IDLE &&
      !transfer_error &&
      error_status == NO_ERROR &&
      !PSEL1 && !PSEL2 && !PENABLE
    );
  endproperty

  // State Transition Properties
  property p_idle_to_setup_transition;
    (current_state == IDLE && transfer) |-> ##1 (current_state == SETUP);
  endproperty

  property p_valid_address_check;
    (current_state == SETUP) |-> 
    ((PADDR >= ADDR_START_1 && PADDR <= ADDR_END_1) ||
     (PADDR >= ADDR_START_2 && PADDR <= ADDR_END_2));
  endproperty

  // Signal Behavior Properties
  property p_psel_mutual_exclusion;
    !(PSEL1 && PSEL2);
  endproperty

  property p_setup_state_signals;
    (current_state == SETUP) |-> ((PSEL1 || PSEL2) && !PENABLE);
  endproperty

  property p_access_state_signals;
    (current_state == ACCESS) |-> ((PSEL1 || PSEL2) && PENABLE);
  endproperty

  property p_idle_state_signals;
    (current_state == IDLE) |-> (!PSEL1 && !PSEL2 && !PENABLE);
  endproperty

  // Protocol Behavior Properties
  property p_read_pready_check;
    (current_state == ACCESS && READ_WRITE) |-> (##[0:$] PREADY);
  endproperty

  property p_pstrb_read_requirement;
    @(posedge PCLK) disable iff (!PRESETn)
    (READ_WRITE) |-> (PSTRB == 0);
  endproperty

  property p_pstrb_write_requirement;
    @(posedge PCLK) disable iff (!PRESETn)
    (!READ_WRITE && current_state == SETUP) |-> (PSTRB != 0);
  endproperty

  // Error Handling Properties
  property p_timeout_counter_increment;
    @(posedge PCLK) disable iff (!PRESETn)
    (current_state == ACCESS && !PREADY) |-> ##1 (timeout_counter == $past(timeout_counter) + 1);
  endproperty

  property p_pslverr_error_status;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSLVERR && current_state == ACCESS) |-> ##1 (error_status == PSLV_ERROR);
  endproperty

  property p_transfer_error_status;
    @(posedge PCLK) disable iff (!PRESETn)
    (current_state == ERROR) |-> transfer_error;
  endproperty

  // ============= Assertions =============
  
  // Reset Assertions
  assert property (p_async_reset_behavior) 
    $info ("Async reset behavior is correct"); 
    else $error("Async reset behavior violation");

  assert property (p_post_reset_stability) 
    $info("Post-reset stability is correct"); 
    else $error("Post-reset stability violation");

  // State Transition Assertions
  assert property (p_idle_to_setup_transition) 
    $info("IDLE to SETUP transition is correct"); 
    else $error("IDLE to SETUP transition violation");

  assert property (p_valid_address_check) 
    $info("Valid address detected"); 
    else $error("Invalid address detected");

  // Signal Behavior Assertions
  assert property (p_psel_mutual_exclusion) 
    $info("Only one slave is active"); 
    else $error("PSEL1 and PSEL2 active simultaneously");

  assert property (p_setup_state_signals) 
    $info("SETUP State signals assertion passed - PSEL active, PENABLE low"); 
    else $error("SETUP State signals assertion failed");

  assert property (p_access_state_signals) 
    $info("ACCESS State signals assertion passed - PSEL and PENABLE both active"); 
    else $error("ACCESS State signals assertion failed");

  assert property (p_idle_state_signals) 
    $info("IDLE State signals assertion passed - all control signals inactive"); 
    else $error("IDLE State signals assertion failed");

  // Protocol Behavior Assertions
  assert property (p_read_pready_check) 
    $info("READ operation PREADY assertion passed"); 
    else $error("READ operation PREADY assertion failed");

  assert property (p_pstrb_read_requirement) 
    else $error("PSTRB not zero during read");

  assert property (p_pstrb_write_requirement) 
    else $error("PSTRB zero during write");

  // Error Handling Assertions
  assert property (p_timeout_counter_increment) 
    else $error("Timeout counter increment violation");

  assert property (p_pslverr_error_status) 
    else $error("PSLVERR error status not set correctly");

  assert property (p_transfer_error_status) 
    else $error("Transfer error not set in ERROR state");

  // ============= Coverage =============
  
  // State Coverage
  cover property (@(posedge PCLK) (current_state == IDLE)   ##1 (current_state == SETUP))
    $info("Coverage: IDLE to SETUP transition");

  cover property (@(posedge PCLK) (current_state == SETUP)  ##1 (current_state == ACCESS))
    $info("Coverage: SETUP to ACCESS transition");

  cover property (@(posedge PCLK) (current_state == ACCESS) ##1 (current_state == IDLE))
    $info("Coverage: ACCESS to IDLE transition");

  cover property (@(posedge PCLK) (current_state == ACCESS) ##1 (current_state == ERROR))
    $info("Coverage: ACCESS to ERROR transition");

  cover property ((current_state == SETUP))
    $info("Coverage: SETUP state reached");

  cover property ((current_state == ACCESS))
    $info("Coverage: ACCESS state reached");

  cover property ((current_state == IDLE))
    $info("Coverage: IDLE state reached");

  // Protocol Coverage
  cover property ((current_state == ACCESS && READ_WRITE && PREADY))
    $info("Coverage: Read with immediate PREADY observed");

  cover property ((current_state == ACCESS && READ_WRITE && !PREADY) ##[1:$] 
                 (current_state == ACCESS && PREADY))
    $info("Coverage: Read with delayed PREADY observed");

endmodule